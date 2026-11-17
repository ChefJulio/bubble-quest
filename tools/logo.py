"""Draw BubbleQuest's logo: gold "BQ" on a dark navy square, edge to edge. The BubbleSuite style: the
same as BubbleFonts' "BF" (bubble-fonts/tools/logo.py), letters in Inter SemiBold, read from the
bubble-fonts repo beside this one (BubbleFonts bundles it); Bahnschrift if that isn't there.

Square, no rounded corners: CurseForge frames the logo in its own square tile, and in game the icon is
shown at 16-20 px, where every pixel counts.

Usage: python tools/logo.py <out.png|out.tga> [size]
  python tools/logo.py docs/branding/logo.png 512   CurseForge logo
  python tools/logo.py Media/Icon.tga 64            in-game icon (AddOns list, addon compartment)
The format follows the extension; TGA is saved uncompressed with alpha (sizes must be powers of two).
"""
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 512
S = 4  # supersampling
W = 512 * S
INTER = Path(__file__).resolve().parents[2] / "bubble-fonts" / "Media" / "Fonts" / "Inter" / "Inter-SemiBold.ttf"
FONT = str(INTER) if INTER.exists() else "C:/Windows/Fonts/bahnschrift.ttf"
GOLD_TOP, GOLD_BOTTOM = (255, 214, 110), (214, 148, 40)
OUTLINE = (70, 44, 12, 255)


def background() -> Image.Image:
  """Dark navy with a soft glow behind the letters."""
  bg = Image.new("RGBA", (W, W))
  px = bg.load()
  for y in range(0, W, S):
    for x in range(0, W, S):
      t = max(0.0, 1 - math.hypot(x - W / 2, y - W * 0.45) / (W * 0.75))
      c = (int(18 + 22 * t), int(22 + 26 * t), int(32 + 34 * t), 255)
      for yy in range(S):
        for xx in range(S):
          px[x + xx, y + yy] = c
  return bg


def letters(text: str = "BQ", size: int = 340, spacing: int = -6) -> Image.Image:
  """The letters: vertical gold gradient, dark outline, drop shadow; centred, 70% of the width (as
  BubbleFonts' logo, tuned for Inter)."""
  mask = Image.new("L", (W, W), 0)
  d = ImageDraw.Draw(mask)
  while True:
    font = ImageFont.truetype(FONT, size * S)
    boxes = [d.textbbox((0, 0), ch, font=font) for ch in text]
    total = sum(b[2] - b[0] for b in boxes) + spacing * S * (len(text) - 1)
    if total <= W * 0.70:
      break
    size -= 4
  top = min(b[1] for b in boxes)
  height = max(b[3] for b in boxes) - top
  x, y = (W - total) / 2, (W - height) / 2 - top
  for ch, b in zip(text, boxes):
    d.text((x - b[0], y), ch, font=font, fill=255)
    x += b[2] - b[0] + spacing * S

  gradient = Image.new("RGBA", (W, W))
  g = ImageDraw.Draw(gradient)
  for row in range(W):
    t = row / W
    g.line([(0, row), (W, row)], fill=tuple(int(a + (b - a) * t) for a, b in zip(GOLD_TOP, GOLD_BOTTOM)) + (255,))
  outline = mask.filter(ImageFilter.MaxFilter(9 * S // 2 * 2 + 1))
  shadow = outline.filter(ImageFilter.GaussianBlur(10 * S))

  layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
  layer.paste((0, 0, 0, 170), (8 * S, 12 * S), shadow)
  layer.paste(OUTLINE, (0, 0), outline)
  layer.paste(gradient, (0, 0), mask)
  return layer


img = background()
img.alpha_composite(letters())
img = img.resize((SIZE, SIZE), Image.LANCZOS)
img.save(OUT)
