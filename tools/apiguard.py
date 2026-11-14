"""Forever API guard: flags API calls that are missing or restricted on the WoW Forever client.

LuaLS (with Ketho's annotations) catches typos, undefined globals and wrong argument types,
but its annotations track retail and drop Blizzard's restriction metadata. This checker reads
Blizzard's own generated API documentation from the Forever branch of wow-ui-source and checks
every call in the addon against it.

Errors (always fail):
  - protected function (IsProtectedFunction): addon calls are blocked (ADDON_ACTION_BLOCKED)
  - SecureOnly function or system: unavailable to addon code
  - function missing from a documented C_ namespace: likely retail-only, not in Forever
  - event name not documented: RegisterEvent would error or never fire
  - obj:Method() whose name nothing defines: not a documented widget method, not a method in
    the Forever UI source (mixins), not in Ketho's widget annotations, not defined by the addon.
    LuaLS does not catch these because CreateFrame's return type is too loose.

Warnings (fail unless acknowledged):
  - restricted calls (HasRestrictions, Secret*, Requires*Access, ...) and events
  - secure templates (Secure*Template) in Lua or XML: the frame's protected methods (Show, Hide,
    SetPoint, SetAttribute, ...) are blocked in combat, so every change must be combat-guarded.
    Protected methods are not flagged per call: the receiver is unknown statically and on
    ordinary frames they are fine, so the secure frame's creation is the place to review.

Acknowledge a reviewed warning with a comment on the same line or the line above:
  -- apiguard: allow <reason>
Errors can be acknowledged the same way (for a documented-but-wrong case), but should be rare.

Usage: python tools/apiguard.py <docs_dir> <file_or_dir> [...]
       (standalone mode skips the method check; tools/lint.py supplies the method sources)
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# --------------------------------------------------------------------------------------------
# Lua lexer (shared by the doc parser and the addon scanner)
# --------------------------------------------------------------------------------------------

_LONG_OPEN = re.compile(r"\[(=*)\[")
_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_NUMBER = re.compile(r"0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?")
_OPS = ("...", "..", "==", "~=", "<=", ">=", "::")


@dataclass
class Tok:
  kind: str  # name | string | number | op | comment
  value: str
  line: int


def lex(src: str) -> list[Tok]:
  toks: list[Tok] = []
  i, n, line = 0, len(src), 1
  while i < n:
    c = src[i]
    if c == "\n":
      line += 1
      i += 1
    elif c in " \t\r":
      i += 1
    elif src.startswith("--", i):
      start_line = line
      m = _LONG_OPEN.match(src, i + 2)
      if m:
        close = "]" + m.group(1) + "]"
        end = src.find(close, m.end())
        end = n if end < 0 else end + len(close)
      else:
        end = src.find("\n", i)
        end = n if end < 0 else end
      text = src[i:end]
      line += text.count("\n")
      toks.append(Tok("comment", text, start_line))
      i = end
    elif c in "\"'":
      j = i + 1
      buf = []
      while j < n and src[j] != c:
        if src[j] == "\\" and j + 1 < n:
          if src[j + 1] == "\n":
            line += 1
          buf.append(src[j:j + 2])
          j += 2
          continue
        if src[j] == "\n":
          break  # unterminated; let LuaLS report it
        buf.append(src[j])
        j += 1
      toks.append(Tok("string", "".join(buf), line))
      i = j + 1
    elif c == "[" and _LONG_OPEN.match(src, i):
      m = _LONG_OPEN.match(src, i)
      close = "]" + m.group(1) + "]"
      end = src.find(close, m.end())
      end = n if end < 0 else end
      text = src[m.end():end]
      toks.append(Tok("string", text, line))
      line += text.count("\n")
      i = end + len(close)
    elif c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
      m = _NUMBER.match(src, i)
      toks.append(Tok("number", m.group(0), line))
      i = m.end()
    elif c.isalpha() or c == "_":
      m = _NAME.match(src, i)
      toks.append(Tok("name", m.group(0), line))
      i = m.end()
    else:
      op = next((o for o in _OPS if src.startswith(o, i)), c)
      toks.append(Tok("op", op, line))
      i += len(op)
  return toks


# --------------------------------------------------------------------------------------------
# Blizzard API documentation loader
# --------------------------------------------------------------------------------------------

class _TableParser:
  """Parses the literal table constructors used by Blizzard_APIDocumentationGenerated."""

  def __init__(self, toks: list[Tok]):
    self.toks = [t for t in toks if t.kind != "comment"]
    self.i = 0

  def peek(self, k: int = 0) -> Tok | None:
    j = self.i + k
    return self.toks[j] if j < len(self.toks) else None

  def take(self) -> Tok:
    t = self.toks[self.i]
    self.i += 1
    return t

  def value(self):
    v = self._atom()
    if self.peek() and self.peek().value not in (",", ";", "}"):
      # Expression such as `Constants.Foo + 1`: skip to the end of the field, keep as opaque text.
      parts = [str(v)]
      while self.peek().value not in (",", ";", "}"):
        parts.append(self.take().value)
      return " ".join(parts)
    return v

  def _atom(self):
    t = self.take()
    if t.kind == "op" and t.value == "{":
      return self.table()
    if t.kind == "op" and t.value == "-":
      v = self._atom()
      return -v if isinstance(v, (int, float)) else f"-{v}"
    if t.kind == "string":
      return t.value
    if t.kind == "number":
      return float(t.value) if "." in t.value else int(t.value, 0)
    if t.kind == "name":
      if t.value in ("true", "false"):
        return t.value == "true"
      if t.value == "nil":
        return None
      parts = [t.value]  # dotted reference such as Enum.Foo: keep as text
      while self.peek() and self.peek().value == "." and self.peek(1) and self.peek(1).kind == "name":
        self.take()
        parts.append(self.take().value)
      return ".".join(parts)
    raise ValueError(f"unexpected token {t.value!r} on line {t.line}")

  def table(self):
    fields: dict = {}
    items: list = []
    while True:
      t = self.peek()
      if t.kind == "op" and t.value == "}":
        self.take()
        break
      if t.kind == "name" and self.peek(1).value == "=":
        key = self.take().value
        self.take()
        fields[key] = self.value()
      else:
        items.append(self.value())
      if self.peek().value in (",", ";"):
        self.take()
    if items and not fields:
      return items
    if items:
      fields["__items"] = items
    return fields


def _parse_doc_file(path: Path) -> dict | None:
  toks = [t for t in lex(path.read_text(encoding="utf-8")) if t.kind != "comment"]
  for k in range(len(toks) - 3):
    if toks[k].value == "local" and toks[k + 2].value == "=" and toks[k + 3].value == "{":
      p = _TableParser(toks)
      p.i = k + 4
      return p.table()
  return None


# Flags whose presence means a call can be blocked, return secrets, or fail under restrictions.
_RESTRICTION_FLAG = re.compile(r"Secret|Restrict|Forbidden|Declassified|Access|Lockdown|InCombat|LimitedInput")
_BENIGN_SECRET_ARGS = ("AllowedWhenUntainted", "AllowedWhenTainted")


def restriction_flags(entry: dict) -> list[str]:
  out = []
  for key, val in entry.items():
    if key == "SecretArguments":
      if val not in _BENIGN_SECRET_ARGS:
        out.append(f"SecretArguments={val}")
    elif key == "HasRestrictions" or _RESTRICTION_FLAG.search(key):
      if val is True:
        out.append(key)
      elif val not in (False, None):
        out.append(f"{key}={val}")
  return out


@dataclass
class ApiEntry:
  name: str
  system: str
  protected: bool = False
  secure_only: bool = False
  flags: list[str] = field(default_factory=list)


@dataclass
class ApiDb:
  namespaces: dict[str, dict[str, ApiEntry]] = field(default_factory=dict)  # C_Foo -> name -> entry
  globals: dict[str, ApiEntry] = field(default_factory=dict)
  events: dict[str, ApiEntry] = field(default_factory=dict)
  widget_methods: set[str] = field(default_factory=set)  # from ScriptObject docs
  known_methods: set[str] | None = None  # None: method check disabled


def load_docs(docs_dir: Path) -> ApiDb:
  db = ApiDb()
  files = sorted(docs_dir.glob("*.lua"))
  if not files:
    raise SystemExit(f"apiguard: no API documentation found in {docs_dir}")
  for path in files:
    try:
      doc = _parse_doc_file(path)
    except (ValueError, IndexError, AttributeError) as e:
      print(f"apiguard: warning: could not parse {path.name}: {e}", file=sys.stderr)
      continue
    if not isinstance(doc, dict):
      continue
    system = doc.get("Name", path.stem)
    system_secure = doc.get("Environment") == "SecureOnly"
    ns = doc.get("Namespace")
    is_script_object = doc.get("Type") == "ScriptObject"
    for fn in doc.get("Functions") or []:
      if not isinstance(fn, dict) or "Name" not in fn:
        continue
      entry = ApiEntry(
        name=fn["Name"],
        system=system,
        protected=fn.get("IsProtectedFunction") is True,
        secure_only=system_secure or fn.get("Environment") == "SecureOnly",
        flags=restriction_flags(fn),
      )
      if is_script_object:
        # Receiver unknown statically, so restrictions aren't checked here (see secure-template
        # rule); the name only feeds the unknown-method check.
        db.widget_methods.add(entry.name)
        continue
      if ns:
        db.namespaces.setdefault(ns, {})[entry.name] = entry
      else:
        db.globals[entry.name] = entry
    for ev in doc.get("Events") or []:
      if isinstance(ev, dict) and "LiteralName" in ev:
        db.events[ev["LiteralName"]] = ApiEntry(ev["LiteralName"], system, flags=restriction_flags(ev))
  return db


# `function Foo:Name(`, `function Foo.Name(`, `Name = function`, `Foo.Name = function`
_METHOD_DEF = re.compile(r"function\s+[\w.:]+[:.](\w+)\s*\(|(\w+)\s*=\s*function\b")


def collect_defined_names(paths: list[Path]) -> set[str]:
  """Every function name defined as a field/method anywhere under the given Lua files or dirs."""
  names: set[str] = set()
  for root in paths:
    files = [root] if root.is_file() else root.rglob("*.lua")
    for f in files:
      for m in _METHOD_DEF.finditer(f.read_text(encoding="utf-8", errors="replace")):
        names.add(m.group(1) or m.group(2))
  return names


# --------------------------------------------------------------------------------------------
# Addon scanner
# --------------------------------------------------------------------------------------------

_ACK = re.compile(r"apiguard:\s*allow\s+\S")
_SECURE_TEMPLATE = re.compile(r"\bSecure\w*Template\b")
_XML_INHERITS = re.compile(r"""inherits\s*=\s*["']([^"']*)["']""")
_EVENT_REGISTRARS = {
  "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "IsEventRegistered",
  "RegisterFrameEventAndCallback", "RegisterFrameEvent",
}


@dataclass
class Finding:
  path: Path
  line: int
  severity: str  # error | warning
  message: str


def _describe(entry: ApiEntry, label: str) -> tuple[str, str] | None:
  if entry.protected:
    return "error", f"{label} is protected: addon calls are blocked (ADDON_ACTION_BLOCKED)"
  if entry.secure_only:
    return "error", f"{label} is SecureOnly: not callable from addon code"
  if entry.flags:
    return "warning", f"{label} is restricted [{', '.join(entry.flags)}]"
  return None


def _secure_template_finding(template: str) -> tuple[str, str]:
  return "warning", (f"secure template ({template}): Show/Hide/SetPoint/SetAttribute and other protected "
                     "methods on this frame are blocked in combat; guard every change with "
                     "InCombatLockdown() and queue it for PLAYER_REGEN_ENABLED")


def scan_file(path: Path, db: ApiDb) -> list[Finding]:
  all_toks = lex(path.read_text(encoding="utf-8"))
  acked_lines: set[int] = set()
  code_lines: set[int] = {t.line for t in all_toks if t.kind != "comment"}
  for t in all_toks:
    if t.kind == "comment" and _ACK.search(t.value):
      acked_lines.add(t.line)
      end_line = t.line + t.value.count("\n")
      if end_line not in code_lines:  # comment-only line: covers the next line
        acked_lines.add(end_line + 1)

  toks = [t for t in all_toks if t.kind != "comment"]
  findings: list[Finding] = []

  def report(tok: Tok, result: tuple[str, str] | None):
    if result and tok.line not in acked_lines:
      findings.append(Finding(path, tok.line, *result))

  for k, t in enumerate(toks):
    if t.kind == "string" and _SECURE_TEMPLATE.search(t.value):
      report(t, _secure_template_finding(t.value))
    if t.kind != "name":
      continue
    prev = toks[k - 1] if k > 0 else None
    nxt = toks[k + 1] if k + 1 < len(toks) else None
    after_access = prev is not None and prev.kind == "op" and prev.value in (".", ":")

    # obj:Method(...)
    if (db.known_methods is not None and prev is not None and prev.value == ":"
        and t.value not in db.known_methods):
      report(t, ("error", f":{t.value}() is not a known widget/mixin method or a function defined in "
                          "the addon (typo?)"))
      continue

    # C_Namespace.Function. Only C_ namespaces are fully documented; others (math, string, ...)
    # list just a few functions, so for them a missing entry means nothing.
    if t.value in db.namespaces and not after_access and nxt and nxt.value == "." and k + 2 < len(toks):
      member = toks[k + 2]
      if member.kind == "name":
        label = f"{t.value}.{member.value}"
        entry = db.namespaces[t.value].get(member.value)
        if entry is not None:
          report(member, _describe(entry, label))
        elif t.value.startswith("C_"):
          report(member, ("error", f"{label} is not in the Forever API docs (retail-only or misspelled?)"))
      continue

    # Documented global function (not a field access, not a local/function definition)
    if t.value in db.globals and not after_access and not (prev and prev.value in ("function", "local")):
      report(t, _describe(db.globals[t.value], t.value))

    # RegisterEvent("EVENT_NAME") and friends
    if t.value in _EVENT_REGISTRARS and nxt and nxt.value == "(" and k + 2 < len(toks):
      arg = toks[k + 2]
      if arg.kind == "string":
        ev = db.events.get(arg.value)
        if ev is None:
          report(arg, ("error", f'event "{arg.value}" is not in the Forever API docs'))
        elif ev.flags:
          report(arg, ("warning", f'event "{arg.value}" is restricted [{", ".join(ev.flags)}]'))

  return findings


def scan_xml(path: Path) -> list[Finding]:
  """Frame XML can't call APIs, but it can inherit secure templates."""
  lines = path.read_text(encoding="utf-8").splitlines()
  findings: list[Finding] = []
  for idx, text in enumerate(lines):
    m = _XML_INHERITS.search(text)
    if not m or not _SECURE_TEMPLATE.search(m.group(1)):
      continue
    if _ACK.search(text) or (idx > 0 and _ACK.search(lines[idx - 1])):
      continue
    findings.append(Finding(path, idx + 1, *_secure_template_finding(m.group(1))))
  return findings


def iter_source_files(targets: list[Path], exclude: tuple[str, ...]) -> list[Path]:
  files: list[Path] = []
  for target in targets:
    if target.is_file():
      candidates = [target]
    else:
      candidates = sorted(p for p in target.rglob("*") if p.suffix in (".lua", ".xml"))
    for f in candidates:
      if not any(part in exclude for part in f.parts):
        files.append(f)
  return files


def run(docs_dir: Path, targets: list[Path], method_sources: list[Path] | None = None,
        exclude: tuple[str, ...] = (".tools", ".git", "Libs")) -> int:
  """method_sources: dirs of Lua that define legal method names (UI source, annotations).
  When given, the addon's own files are added and the unknown-method check is enabled."""
  db = load_docs(docs_dir)
  files = iter_source_files(targets, exclude)
  if method_sources is not None:
    # Embedded libraries (Libs/) aren't linted but do define methods the addon calls.
    own = [f for f in iter_source_files(targets, (".tools", ".git")) if f.suffix == ".lua"]
    db.known_methods = db.widget_methods | collect_defined_names(method_sources + own)
  findings = [f for path in files for f in (scan_xml(path) if path.suffix == ".xml" else scan_file(path, db))]
  cwd = Path.cwd().resolve()
  for f in findings:
    path = f.path.resolve()
    shown = path.relative_to(cwd) if path.is_relative_to(cwd) else path
    print(f"{shown.as_posix()}:{f.line}: {f.severity}: {f.message}")
  errors = sum(f.severity == "error" for f in findings)
  warnings = len(findings) - errors
  n_funcs = sum(len(v) for v in db.namespaces.values()) + len(db.globals)
  print(f"apiguard: {len(files)} file(s) checked against {n_funcs} functions / {len(db.events)} events; "
        f"{errors} error(s), {warnings} unacknowledged warning(s)")
  return 1 if findings else 0


if __name__ == "__main__":
  if len(sys.argv) < 3:
    print(__doc__)
    sys.exit(2)
  sys.exit(run(Path(sys.argv[1]), [Path(p) for p in sys.argv[2:]]))
