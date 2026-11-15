import math
import sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
S = 4  # supersample
W = 512 * S

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

# Background: dark rounded square with a radial glow and faint map grid.
bg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
px = bg.load()
cx, cy = W / 2, W * 0.45
for y in range(0, W, S):
  for x in range(0, W, S):
    d = math.hypot(x - cx, y - cy) / (W * 0.75)
    t = max(0.0, 1 - d)
    r = int(18 + 22 * t)
    g = int(22 + 26 * t)
    b = int(32 + 34 * t)
    for yy in range(S):
      for xx in range(S):
        px[x + xx, y + yy] = (r, g, b, 255)
overlay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
grid = ImageDraw.Draw(overlay)
step = W // 8
for i in range(1, 8):
  grid.line([(i * step, 0), (i * step, W)], fill=(255, 255, 255, 12), width=S)
  grid.line([(0, i * step), (W, i * step)], fill=(255, 255, 255, 12), width=S)
# Faint dotted route across the map
for i in range(16):
  t = i / 15
  x = W * (0.06 + 0.88 * t)
  y = W * (0.84 - 0.30 * math.sin(t * math.pi * 1.1))
  grid.ellipse([x - 6 * S, y - 6 * S, x + 6 * S, y + 6 * S], fill=(232, 184, 74, 110))
bg.alpha_composite(overlay)

mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=96 * S, fill=255)
img.paste(bg, (0, 0), mask)

d = ImageDraw.Draw(img)

# Bookmark ribbon (the "mark").
left, right = W * 0.30, W * 0.70
top, bottom = W * 0.14, W * 0.86
notch = W * 0.70
ribbon = [(left, top), (right, top), (right, bottom), ((left + right) / 2, notch), (left, bottom)]

shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(shadow).polygon([(x + 10 * S, y + 14 * S) for x, y in ribbon], fill=(0, 0, 0, 150))
shadow = shadow.filter(ImageFilter.GaussianBlur(14 * S))
img.alpha_composite(shadow)

d = ImageDraw.Draw(img)
d.polygon(ribbon, fill=(232, 184, 74, 255))
# Lighter left half for a folded look
half = [(left, top), ((left + right) / 2, top), ((left + right) / 2, notch), (left, bottom)]
d.polygon(half, fill=(244, 202, 98, 255))
# Edge outline
d.line(ribbon + [ribbon[0]], fill=(150, 104, 30, 255), width=5 * S, joint="curve")

# Navigation arrow inside the ribbon, pointing up.
ax = (left + right) / 2
tip = W * 0.24
base = W * 0.52
wing = W * 0.13
inner = W * 0.45
arrow = [(ax, tip), (ax + wing, base), (ax, inner), (ax - wing, base)]
d.polygon(arrow, fill=(28, 32, 44, 255))
d.polygon([(ax, tip), (ax, inner), (ax - wing, base)], fill=(48, 54, 72, 255))

img = img.resize((512, 512), Image.LANCZOS)
img.save(OUT)
