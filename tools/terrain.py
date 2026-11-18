"""Build BubbleMap's terrain tile table: BubbleMap/Data/Tiles.lua.

For each continent: which of its 64 x 64 terrain tiles exist, and each tile's minimap texture
(FileDataID), which BubbleMap draws with Texture:SetTexture(fileID) around and beyond the minimap.
Design: docs/design/terrain-map.md ("Data").

The data is pinned to the client build in tools/toolchain.json (wow_ui_source.build): FileDataIDs can
change between builds, so the table is rebuilt when the pin moves. Everything comes from wago.tools at
that exact build:
  - Map.csv: every map's ID, type, parent and WdtFileDataID (the map's WDT file);
  - UiMapAssignment.csv: which maps have zones (a continent has; a test map doesn't);
  - each continent's WDT: its MAID chunk holds, per tile, the tile's files; minimapTexture is the
    texture we draw (verified 2026-11-17: all 1,796 match TerrainWorldMap's listfile-based IDs).
No game-file extraction tool and no community listfile needed. wago.tools is a third party with an
undocumented API; if it goes, CASCConsole (as TerrainWorldMap uses) can read the same WDTs from the
local install.

Pinning trap: `?product=wowf&build=X` ignores the build and serves the latest; `?build=X` alone pins,
and the downloaded file's name (content-disposition) carries the build, checked here.

Map selection follows TerrainWorldMap (MIT, Dramacydal/TerrainWorldMap, scripts/gen_mapareas.js):
a top-level world map (ParentMapID -1, MapType 1, InstanceType 0) with at least one UiMapAssignment.
Tile layout (WDT MAIN/MAID): entry i is tile (col = i % 64, row = i // 64), col = 32 - worldY / 533.33,
row = 32 - worldX / 533.33 (UnitPosition's x and y). The table's key is col * 64 + row.

Usage:
  python tools/terrain.py           fetch (cached in .tools/terrain/<build>/) and write the table
  python tools/terrain.py --check   only check the committed table is the one this build gives
"""
from __future__ import annotations

import csv
import io
import json
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLCHAIN = ROOT / "tools" / "toolchain.json"
OUT = ROOT / "BubbleMap" / "Data" / "Tiles.lua"
CACHE = ROOT / ".tools" / "terrain"

DB2_URL = "https://wago.tools/db2/{table}/csv?build={build}"
FILE_URL = "https://wago.tools/api/casc/{fdid}?version={build}"

TILES = 64
MAID_ENTRY = 32           # 8 uint32: rootADT, obj0, obj1, tex0, lod, mapTexture, mapTextureN, minimap
MINIMAP_FIELD = 7

# Known tiles, as a check that the axes and the key are right (TerrainWorldMap's areas for them).
SANITY = [
  (0, 32, 49, "Elwynn Forest"),
  (0, 29, 51, "Duskwood"),
  (0, 30, 48, "Stormwind City"),
]


def fetch(url: str, build: str | None = None) -> bytes:
  """GET with curl (it uses the OS certificate store; see tools/lint.py). With `build`, the file's
  name must carry it: wago.tools serves the latest build when a pin is ignored."""
  proc = subprocess.run(["curl", "-fsSL", "-D", "-", "-o", "-", url], check=True, capture_output=True)
  raw = proc.stdout
  split = raw.find(b"\r\n\r\n")
  headers, body = raw[:split].decode("latin-1"), raw[split + 4:]
  if build:
    match = re.search(r'filename="([^"]+)"', headers)
    if not match or build not in match.group(1):
      raise SystemExit(f"terrain: {url} didn't serve build {build} ({match.group(1) if match else 'no name'})")
  return body


def cached(build: str, name: str, url: str, check_build: bool) -> bytes:
  path = CACHE / build / name
  if path.exists():
    return path.read_bytes()
  print(f"terrain: fetching {name}")
  data = fetch(url, build if check_build else None)
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_bytes(data)
  return data


def table(build: str, name: str) -> list[dict[str, str]]:
  data = cached(build, f"{name}.csv", DB2_URL.format(table=name, build=build), check_build=True)
  return list(csv.DictReader(io.StringIO(data.decode("utf-8"))))


def continents(build: str) -> list[dict[str, str]]:
  zoned = {row["MapID"] for row in table(build, "UiMapAssignment")}
  return [m for m in table(build, "Map")
          if m["ParentMapID"] == "-1" and m["MapType"] == "1" and m["InstanceType"] == "0"
          and m["ID"] in zoned and m["WdtFileDataID"] not in ("", "0")]


def chunks(data: bytes) -> dict[str, bytes]:
  """A WDT's chunks by name (stored reversed on disk: b"DIAM" is MAID)."""
  out, pos = {}, 0
  while pos + 8 <= len(data):
    magic, size = data[pos:pos + 4][::-1].decode("ascii", "replace"), struct.unpack_from("<I", data, pos + 4)[0]
    out[magic] = data[pos + 8:pos + 8 + size]
    pos += 8 + size
  return out


def tiles(wdt: bytes, name: str) -> dict[int, int]:
  """{col * 64 + row: minimap FileDataID} for every tile with terrain."""
  maid = chunks(wdt).get("MAID")
  if maid is None or len(maid) < TILES * TILES * MAID_ENTRY:
    raise SystemExit(f"terrain: {name}: no MAID chunk")
  out = {}
  for i in range(TILES * TILES):
    fields = struct.unpack_from("<8I", maid, i * MAID_ENTRY)
    if fields[0] == 0:
      continue  # no terrain here
    minimap = fields[MINIMAP_FIELD]
    if minimap == 0:
      raise SystemExit(f"terrain: {name}: tile {i % TILES},{i // TILES} has terrain but no minimap texture")
    col, row = i % TILES, i // TILES
    out[col * TILES + row] = minimap
  return out


def render(build: str, maps: list[tuple[dict[str, str], dict[int, int]]]) -> str:
  lines = [
    "local _, ns = ...",
    "",
    "-- Generated by tools/terrain.py; don't edit. Each continent's terrain tiles: [col * 64 + row] =",
    "-- the tile's minimap texture (FileDataID). col = 32 - worldY / 533.33, row = 32 - worldX / 533.33",
    "-- (UnitPosition's x and y). Keyed by map ID (UnitPosition's 4th return). Source: wago.tools at the",
    "-- build below. Map selection after TerrainWorldMap (MIT, Dramacydal/TerrainWorldMap).",
    "",
    "ns.Tiles = {",
    f'  build = "{build}",',
    "  maps = {",
  ]
  for info, data in maps:
    lines.append(f"    [{info['ID']}] = {{  -- {info['Directory']} ({len(data)} tiles)")
    keys = sorted(data)
    for start in range(0, len(keys), 6):
      lines.append("      " + " ".join(f"[{k}]={data[k]}," for k in keys[start:start + 6]))
    lines.append("    },")
  lines += ["  },", "}", ""]
  return "\n".join(lines)


def build_table(build: str) -> str:
  maps = []
  for info in sorted(continents(build), key=lambda m: int(m["ID"])):
    fdid = info["WdtFileDataID"]
    wdt = cached(build, f"{info['ID']}-{info['Directory']}.wdt", FILE_URL.format(fdid=fdid, build=build),
                 check_build=False)
    maps.append((info, tiles(wdt, info["Directory"])))
  by_id = {int(info["ID"]): data for info, data in maps}
  for map_id, col, row, where in SANITY:
    if col * TILES + row not in by_id.get(map_id, {}):
      raise SystemExit(f"terrain: sanity check failed: no tile {col},{row} on map {map_id} ({where})")
  for info, data in maps:
    print(f"terrain: {info['ID']} {info['Directory']}: {len(data)} tiles")
  return render(build, maps)


def main() -> int:
  build = json.loads(TOOLCHAIN.read_text(encoding="utf-8"))["wow_ui_source"]["build"]
  text = build_table(build)
  if "--check" in sys.argv[1:]:
    current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    if current != text:
      print(f"terrain --check: {OUT.relative_to(ROOT)} is not the table for build {build}; run tools/terrain.py")
      return 1
    print(f"terrain --check: OK (build {build})")
    return 0
  OUT.parent.mkdir(parents=True, exist_ok=True)
  OUT.write_text(text, encoding="utf-8", newline="\n")
  print(f"terrain: wrote {OUT.relative_to(ROOT)} ({len(text) / 1024:.0f} KB, build {build})")
  return 0


if __name__ == "__main__":
  sys.exit(main())
