"""Draw the soft round texture for map areas (Media/Map/blob.tga).

White, alpha falling smoothly from the centre to 0 at the edge: one per spawn point on the world map,
tinted per quest; overlapping ones merge inside a frame buffer into one soft shape (UI/MapAreas.lua).
Uncompressed 32-bit TGA, like the arrows.

Usage: python tools/make_blob.py
"""
import math
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Media" / "Map" / "blob.tga"
SIZE = 64


def main() -> None:
  pixels = bytearray()
  centre = (SIZE - 1) / 2
  for y in range(SIZE - 1, -1, -1):  # TGA rows bottom-up
    for x in range(SIZE):
      r = math.hypot(x - centre, y - centre) / (SIZE / 2)
      alpha = 0.0 if r >= 1 else (1 - r * r) ** 2  # smooth falloff, soft edge
      pixels += bytes((255, 255, 255, int(alpha * 255 + 0.5)))
  header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
  OUT.parent.mkdir(parents=True, exist_ok=True)
  OUT.write_bytes(header + bytes(pixels))
  print(f"wrote {OUT.relative_to(OUT.parents[2])}")


if __name__ == "__main__":
  main()
