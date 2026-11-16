"""Draw the round textures for map areas (Media/Map/).

blob.tga: white, alpha falling smoothly from the centre to 0 at the edge: one per spawn point on the
maps, tinted per quest; overlaps build up colour (UI/MapAreas.lua, UI/MinimapAreas.lua).
dot.tga: a crisp white disc with a dark rim, for the minimap's guide line (tinted per quest; the rim
stays dark, so the dots read on any ground).
Uncompressed 32-bit TGA, like the arrows.

Usage: python tools/make_blob.py
"""
import math
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Media" / "Map"
SIZE = 64
DOT_CORE = 0.62  # the disc's radius, as a share of the texture's; the rim fills the rest


def blob(r: float) -> tuple[int, int]:
  """Brightness and alpha at radius r (0 centre, 1 edge)."""
  alpha = 0.0 if r >= 1 else (1 - r * r) ** 2  # smooth falloff, soft edge
  return 255, int(alpha * 255 + 0.5)


def dot(r: float) -> tuple[int, int]:
  edge = 1.5 / (SIZE / 2)  # anti-aliasing width: a pixel and a half
  if r <= DOT_CORE:
    return 255, 255
  if r <= DOT_CORE + edge:  # disc blends into the rim
    t = (r - DOT_CORE) / edge
    return int(255 * (1 - t) + 0.5), 255
  rim = max(0.0, min(1.0, (1 - r) / edge))  # rim fades out at the edge
  return 0, int(200 * rim + 0.5)


def write(name: str, shade) -> None:
  pixels = bytearray()
  centre = (SIZE - 1) / 2
  for y in range(SIZE - 1, -1, -1):  # TGA rows bottom-up
    for x in range(SIZE):
      grey, alpha = shade(math.hypot(x - centre, y - centre) / (SIZE / 2))
      pixels += bytes((grey, grey, grey, alpha))
  header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
  OUT.mkdir(parents=True, exist_ok=True)
  path = OUT / name
  path.write_bytes(header + bytes(pixels))
  print(f"wrote {path.relative_to(OUT.parents[1])}")


def main() -> None:
  write("blob.tga", blob)
  write("dot.tga", dot)


if __name__ == "__main__":
  main()
