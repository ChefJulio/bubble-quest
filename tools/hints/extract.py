"""Extract every forever-db step row from the vendored LibForeverData into candidates.jsonl.

  python tools/hints/extract.py

One JSON object per line: id (forever-db's stable step id), quest, title, level, action, text, and the
quest's objective target names (what the game's objective text is about: creature, item or object).
Rows already decided in tools/hints/triage/*.jsonl are marked `"decided": true`, so a new forever-db
release only sends new rows to triage. Reads data files only; runs nothing from them.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "Libs" / "LibForeverData" / "Data"
OUT = Path(__file__).resolve().parent / "candidates.jsonl"
TRIAGE = Path(__file__).resolve().parent / "triage"

_ROW = re.compile(r"^(\d+)\t([^\n]*)$", re.M)
_ESC = re.compile(r"%([0-9A-Fa-f]{2})")


def unesc(text: str) -> str:
  return _ESC.sub(lambda m: chr(int(m.group(1), 16)), text)


def rows(name: str) -> dict[int, str]:
  return {int(m.group(1)): m.group(2) for m in _ROW.finditer((LIB / name).read_text(encoding="utf-8"))}


def main() -> int:
  quests, steps = rows("Quests.lua"), rows("Steps.lua")
  names = {"k": rows("Npcs.lua"), "t": rows("Npcs.lua"), "i": rows("Items.lua"), "o": rows("Objects.lua")}

  decided: set[str] = set()
  for path in sorted(TRIAGE.glob("*.jsonl")) if TRIAGE.exists() else []:
    for line in path.read_text(encoding="utf-8").splitlines():
      if line.strip():
        decided.add(json.loads(line)["id"])

  count = new = 0
  with OUT.open("w", encoding="utf-8", newline="\n") as out:
    for quest_id in sorted(steps):
      fields = quests.get(quest_id, "").split(";")
      title = unesc(fields[0]) if fields and fields[0] else "?"
      level = fields[1] if len(fields) > 1 else ""
      targets = []
      if len(fields) > 13:
        for objective in fields[13].split(","):
          parts = objective.split(":")
          table = names.get(parts[0])
          if table is not None and len(parts) > 1 and parts[1].isdigit():
            target = table.get(int(parts[1]), "").split(";")[0]
            if target:
              targets.append(unesc(target))
      for row in steps[quest_id].split("|"):
        parts = row.split(":")
        if len(parts) < 8:
          continue
        step_id = unesc(parts[1])
        record = {
          "id": step_id, "quest": quest_id, "title": title, "level": level,
          "action": unesc(parts[2]), "text": unesc(parts[7]), "objectives": targets,
        }
        if step_id in decided:
          record["decided"] = True
        else:
          new += 1
        out.write(json.dumps(record, ensure_ascii=False) + "\n")
        count += 1
  print(f"extract: {count} step rows, {new} not yet triaged -> {OUT.relative_to(ROOT).as_posix()}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
