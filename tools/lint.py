"""Lint the addon: LuaLS with WoW API annotations, then the Forever API guard.

  python tools/lint.py            fetch pinned tools if missing, then lint
  python tools/lint.py --update   bump tools/toolchain.json to the latest upstream versions, then lint

Layer 1, LuaLS + Ketho's WoW API annotations: undefined globals (nonexistent APIs), unknown
fields, wrong argument types, deprecated calls, accidental global leaks.
Layer 2, tools/apiguard.py: checks calls against Blizzard's own API docs from the Forever
branch of wow-ui-source (protected, SecureOnly, restricted/secret, missing-on-Forever, events).

Tools are fetched into .tools/ (gitignored) at the versions pinned in tools/toolchain.json.
Requires git, curl and Python 3.12+.
"""

from __future__ import annotations

import io
import json
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.parse
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / ".tools"
TOOLCHAIN = ROOT / "tools" / "toolchain.json"
ANNOTATIONS_DIR = TOOLS / "vscode-wow-api"
UI_SOURCE_DIR = TOOLS / "wow-ui-source"
API_DOCS = UI_SOURCE_DIR / "Interface" / "AddOns" / "Blizzard_APIDocumentationGenerated"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apiguard  # noqa: E402


def git(*args: str, cwd: Path | None = None) -> str:
  return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def fetch(url: str) -> bytes:
  # curl rather than urllib: it uses the OS certificate store, which python.org builds on
  # Windows do not, so urllib can fail certificate verification there.
  return subprocess.run(["curl", "-fsSL", url], check=True, capture_output=True).stdout


# --------------------------------------------------------------------------------------------
# Tool bootstrap
# --------------------------------------------------------------------------------------------

def ensure_repo(dest: Path, repo: str, commit: str) -> None:
  if not (dest / ".git").exists():
    print(f"lint: fetching {repo} @ {commit[:10]}")
    dest.mkdir(parents=True, exist_ok=True)
    git("init", "-q", cwd=dest)
    git("remote", "add", "origin", repo, cwd=dest)
  elif git("rev-parse", "HEAD", cwd=dest) == commit:
    return
  else:
    print(f"lint: moving {dest.name} to {commit[:10]}")
  git("fetch", "-q", "--depth", "1", "origin", commit, cwd=dest)
  git("checkout", "-q", "--force", "FETCH_HEAD", cwd=dest)


def _luals_asset(version: str) -> str:
  system, machine = platform.system(), platform.machine().lower()
  arch = "arm64" if machine in ("arm64", "aarch64") else "x64"
  if system == "Windows":
    return f"lua-language-server-{version}-win32-x64.zip"
  if system == "Darwin":
    return f"lua-language-server-{version}-darwin-{arch}.tar.gz"
  return f"lua-language-server-{version}-linux-{arch}.tar.gz"


def ensure_luals(version: str) -> Path:
  dest = TOOLS / f"lua-language-server-{version}"
  exe = dest / "bin" / ("lua-language-server.exe" if platform.system() == "Windows" else "lua-language-server")
  if exe.exists():
    return exe
  asset = _luals_asset(version)
  url = f"https://github.com/LuaLS/lua-language-server/releases/download/{version}/{asset}"
  print(f"lint: downloading {asset}")
  data = fetch(url)
  dest.mkdir(parents=True, exist_ok=True)
  if asset.endswith(".zip"):
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
      zf.extractall(dest)
  else:
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
      tf.extractall(dest, filter="tar")
  return exe


def update_toolchain(cfg: dict) -> None:
  ann, ui = cfg["wow_api_annotations"], cfg["wow_ui_source"]
  ann["commit"] = git("ls-remote", ann["repo"], "HEAD").split()[0]
  ui["commit"] = git("ls-remote", ui["repo"], f"refs/heads/{ui['branch']}").split()[0]
  latest = fetch("https://api.github.com/repos/LuaLS/lua-language-server/releases/latest")
  cfg["luals"]["version"] = json.loads(latest)["tag_name"]
  ensure_repo(UI_SOURCE_DIR, ui["repo"], ui["commit"])
  ui["build"] = (UI_SOURCE_DIR / "version.txt").read_text(encoding="utf-8").strip()
  TOOLCHAIN.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
  print(f"lint: toolchain updated: LuaLS {cfg['luals']['version']}, Forever build {ui['build']}")


XML_GLOBALS = TOOLS / "generated" / "FrameXMLGlobals.lua"
_XML_WIDGET_TAGS = (
  "Frame|Button|CheckButton|EditBox|ScrollFrame|Slider|StatusBar|Texture|MaskTexture|Line|FontString|Font"
  "|GameTooltip|MessageFrame|ScrollingMessageFrame|SimpleHTML|Model|PlayerModel|DressUpModel|ModelScene"
  "|Cooldown|ColorSelect|Minimap|MovieFrame|Browser|OffScreenFrame|AnimationGroup|EventFrame|EventButton"
  "|DropdownButton|WowStyle1DropdownTemplate"
)
_XML_NAMED = re.compile(rf"<({_XML_WIDGET_TAGS})\b([^>]*?)\bname=\"([A-Za-z_][A-Za-z0-9_]*)\"([^>]*)>")


def ensure_xml_globals(ui_commit: str) -> None:
  """LuaLS doesn't read XML, so frames Blizzard names in XML (ObjectiveTrackerFrame, ...) look
  undefined. Generate a declaration file for every named, non-virtual widget in the Forever UI."""
  stamp = f"-- generated from wow-ui-source {ui_commit}"
  if XML_GLOBALS.exists() and XML_GLOBALS.read_text(encoding="utf-8").startswith(stamp):
    return
  decls: dict[str, str] = {}
  for xml in sorted((UI_SOURCE_DIR / "Interface").rglob("*.xml")):
    for m in _XML_NAMED.finditer(xml.read_text(encoding="utf-8", errors="replace")):
      tag, before, name, after = m.groups()
      if 'virtual="true"' not in before + after:
        decls.setdefault(name, tag)
  XML_GLOBALS.parent.mkdir(parents=True, exist_ok=True)
  # `|table` because templates and mixins add methods we don't resolve here (WorldMapFrame:GetMapID
  # comes from MapCanvasMixin via its template); apiguard's method check covers method typos instead.
  lines = [stamp, "---@meta", ""]
  for name, tag in sorted(decls.items()):
    lines += [f"---@type {tag}|table", f"{name} = nil", ""]
  XML_GLOBALS.write_text("\n".join(lines), encoding="utf-8")
  print(f"lint: generated {len(decls)} FrameXML global declarations")


# --------------------------------------------------------------------------------------------
# Lint layers
# --------------------------------------------------------------------------------------------

def run_luals(exe: Path) -> int:
  out_file = TOOLS / "luals-check.json"
  out_file.unlink(missing_ok=True)
  # --checklevel=Information keeps unused locals/params etc.; style hints stay editor-only.
  proc = subprocess.run(
    [str(exe), f"--check={ROOT}", "--checklevel=Information", f"--configpath={ROOT / '.luarc.json'}",
     "--check_format=json", f"--check_out_path={out_file}", f"--logpath={TOOLS / 'luals-log'}"],
    capture_output=True, text=True, encoding="utf-8", errors="replace",
  )
  if not out_file.exists():
    print(proc.stdout + proc.stderr)
    print("lint: LuaLS produced no report")
    return 1
  report = json.loads(out_file.read_text(encoding="utf-8") or "{}") or {}  # LuaLS writes [] when clean
  severity = {1: "error", 2: "warning", 3: "info", 4: "hint"}
  count = 0
  for uri, diags in sorted(report.items()):
    path_str = urllib.parse.unquote(urllib.parse.urlparse(uri).path)
    if re.match(r"^/[A-Za-z]:", path_str):  # file:///c:/... on Windows
      path_str = path_str[1:]
    path = Path(path_str)
    try:
      rel = path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
      rel = path.as_posix()
    for d in sorted(diags, key=lambda d: d["range"]["start"]["line"]):
      line = d["range"]["start"]["line"] + 1
      print(f"{rel}:{line}: {severity.get(d.get('severity'), 'error')}: {d['message']} [{d.get('code', '')}]")
      count += 1
  print(f"luals: {count} problem(s)")
  return 1 if count else 0


def main() -> int:
  missing = [tool for tool in ("git", "curl") if shutil.which(tool) is None]
  if missing:
    print(f"lint: required tool(s) not found: {', '.join(missing)}")
    return 2
  cfg = json.loads(TOOLCHAIN.read_text(encoding="utf-8"))
  if "--update" in sys.argv[1:]:
    update_toolchain(cfg)
  ann, ui = cfg["wow_api_annotations"], cfg["wow_ui_source"]
  ensure_repo(ANNOTATIONS_DIR, ann["repo"], ann["commit"])
  ensure_repo(UI_SOURCE_DIR, ui["repo"], ui["commit"])
  exe = ensure_luals(cfg["luals"]["version"])
  ensure_xml_globals(ui["commit"])

  print(f"== LuaLS {cfg['luals']['version']} + WoW API annotations")
  luals_rc = run_luals(exe)
  print(f"== Forever API guard (build {ui['build']})")
  core = ANNOTATIONS_DIR / "Annotations" / "Core"
  guard_rc = apiguard.run(API_DOCS, [ROOT], method_sources=[
    UI_SOURCE_DIR / "Interface", core / "Widget", core / "Lua", core / "Libraries"])
  ok = luals_rc == 0 and guard_rc == 0
  print("lint: OK" if ok else "lint: FAILED")
  return 0 if ok else 1


if __name__ == "__main__":
  sys.exit(main())
