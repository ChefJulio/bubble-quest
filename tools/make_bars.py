"""Draw the solid-colour textures for the tooltip's mini progress bars (Media/Bar/*.tga).

Inline tooltip textures (|T...|t) can't be tinted reliably (the vertex-colour form isn't used anywhere in
Blizzard's UI source), so each colour is its own 8x8 file. Uncompressed 32-bit TGA, like the arrows.

Usage: python tools/make_bars.py
"""
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Media" / "Bar"
SIZE = 8
COLORS = {  # name -> (r, g, b, a), matching the card progress bars
  "fill": (230, 184, 46, 255),   # gold: progress
  "done": (51, 204, 51, 255),    # green: objective complete
  "empty": (60, 60, 60, 230),    # dark: what's left
}


def tga(rgba: tuple[int, int, int, int]) -> bytes:
  header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
  r, g, b, a = rgba
  return header + bytes((b, g, r, a)) * (SIZE * SIZE)


def main() -> None:
  OUT.mkdir(parents=True, exist_ok=True)
  for name, rgba in COLORS.items():
    (OUT / f"{name}.tga").write_bytes(tga(rgba))
    print(f"wrote Media/Bar/{name}.tga")


if __name__ == "__main__":
  main()
