"""Draw Questmark's arrow textures (Media/Arrows/*.tga) and a preview sheet.

  python tools/make_arrows.py

Each arrow points up (the angle maths relies on that): a near-white fill with a dark outline. The game
tints the fill (Texture:SetVertexColor) gold, or by distance; the outline stays dark, so it reads on
bright and dark ground alike. Drawn at 8x and downsampled for smooth edges; saved as 64x64 32-bit TGA,
which the client loads directly. The preview shows them tinted gold. Requires Pillow.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Media" / "Arrows"
SIZE = 64
SCALE = 8
FILL = (250, 250, 250, 255)     # tinted in game
PREVIEW_TINT = (255, 209, 0)    # Blizzard's UI gold, the untinted-by-distance colour
OUTLINE = (25, 18, 5, 235)
OUTLINE_WIDTH = 5               # in final pixels, half of it outside the shape

# Shapes in unit coordinates (0..1, y down), pointing up.
SHAPES = {
  # Shaft and head.
  "classic": [(0.50, 0.06), (0.88, 0.48), (0.63, 0.48), (0.63, 0.94), (0.37, 0.94), (0.37, 0.48), (0.12, 0.48)],
  # Navigation-app pointer: a dart with a notched tail.
  "dart": [(0.50, 0.06), (0.86, 0.92), (0.50, 0.72), (0.14, 0.92)],
  # Narrow shaft, smaller head.
  "thin": [(0.50, 0.06), (0.80, 0.40), (0.57, 0.40), (0.57, 0.94), (0.43, 0.94), (0.43, 0.40), (0.20, 0.40)],
}


def draw(points: list[tuple[float, float]]) -> Image.Image:
  big = SIZE * SCALE
  image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
  pen = ImageDraw.Draw(image)
  xy = [(x * big, y * big) for x, y in points]
  pen.polygon(xy, fill=OUTLINE, outline=OUTLINE, width=OUTLINE_WIDTH * SCALE)
  pen.polygon(xy, fill=FILL)
  return image.resize((SIZE, SIZE), Image.LANCZOS)


def tinted(image: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
  """What SetVertexColor does: multiply every pixel's colour."""
  r, g, b, a = image.split()
  r = r.point(lambda v: v * rgb[0] // 255)
  g = g.point(lambda v: v * rgb[1] // 255)
  b = b.point(lambda v: v * rgb[2] // 255)
  return Image.merge("RGBA", (r, g, b, a))


def main() -> None:
  OUT.mkdir(parents=True, exist_ok=True)
  sheet = Image.new("RGBA", (len(SHAPES) * 140, 120), (40, 60, 30, 255))  # grass-ish backdrop
  for i, (name, points) in enumerate(SHAPES.items()):
    arrow = draw(points)
    arrow.save(OUT / f"{name}.tga")
    gold = tinted(arrow, PREVIEW_TINT)
    for j, (size, angle) in enumerate([(16, 0), (16, 90), (32, 0), (32, 135)]):
      shown = gold.resize((size, size), Image.LANCZOS).rotate(angle, expand=True, resample=Image.BICUBIC)
      sheet.alpha_composite(shown, (i * 140 + 8 + (j % 2) * 34 + (j // 2) * 50, 40 - shown.height // 2 + (j // 2) * 40))
  sheet.save(ROOT / ".tools" / "arrows-preview.png")
  print(f"wrote {', '.join(SHAPES)} to {OUT.relative_to(ROOT).as_posix()}; preview .tools/arrows-preview.png")


if __name__ == "__main__":
  main()
