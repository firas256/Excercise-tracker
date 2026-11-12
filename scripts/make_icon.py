"""Draws the app icon (1024x1024, no alpha) used by both the iPhone and Watch apps."""
import sys
from PIL import Image, ImageDraw

S = 1024
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
# Vertical gradient background (dark teal -> green)
top, bottom = (10, 40, 45), (40, 190, 100)
for y in range(S):
    t = y / (S - 1)
    d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))

white = (255, 255, 255)
cy = 470
# Dumbbell: bar + two plates on each side
d.rounded_rectangle([250, cy - 28, 774, cy + 28], radius=28, fill=white)
for x0, w, h in [(170, 70, 300), (250, 60, 220)]:
    d.rounded_rectangle([x0, cy - h // 2, x0 + w, cy + h // 2], radius=24, fill=white)
    d.rounded_rectangle([S - x0 - w, cy - h // 2, S - x0, cy + h // 2], radius=24, fill=white)
# Motion arc (rep path) under the dumbbell
d.arc([262, 360, 762, 860], start=20, end=160, fill=white, width=34)
for cx in (262 + 250 + 235, 262 + 250 - 235):
    d.ellipse([cx - 30, 700 - 30, cx + 30, 700 + 30], fill=white)

for path in sys.argv[1:]:
    img.save(path, "PNG")
