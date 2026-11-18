"""Draw BubbleMap's minimap masks for the magnify zoom (BubbleMap/Media/).

mask_<k>x.tga: transparent, with an opaque centred square 1/k of the texture's width. Set as the
minimap's mask while the Minimap frame is k times its size, only the middle shows, at the same size
as before: k times magnified (docs/design/questmarker-map.md, "Zoom", mask magnify).
Uncompressed 32-bit TGA, like the other generated textures (tools/make_blob.py).

Usage: python tools/make_masks.py
"""
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "BubbleMap" / "Media"
SIZE = 240  # divisible by every factor: crisp edges
FACTORS = (2, 3, 4)


def write(factor: int) -> None:
  inner = SIZE / factor
  lo, hi = (SIZE - inner) / 2, (SIZE + inner) / 2
  pixels = bytearray()
  for y in range(SIZE - 1, -1, -1):  # TGA rows bottom-up
    for x in range(SIZE):
      inside = lo <= x + 0.5 < hi and lo <= y + 0.5 < hi
      pixels += bytes((255, 255, 255, 255 if inside else 0))  # BGRA
  header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
  OUT.mkdir(parents=True, exist_ok=True)
  (OUT / f"mask_{factor}x.tga").write_bytes(header + pixels)


if __name__ == "__main__":
  for f in FACTORS:
    write(f)
  print(f"make_masks: wrote {len(FACTORS)} masks to {OUT}")
