#!/usr/bin/env python3
"""Builds Coreplay's icon assets from the designer-supplied logo.

Source: Design/Coreplay-logo-source.png (1254×1254, the icon tile on a dark backdrop).
Usage (from the repository root; needs Python 3 with Pillow, NumPy and OpenCV):
  pip install pillow numpy opencv-python-headless
  python3 Tools/make_brand_assets.py Design/Coreplay-logo-source.png \
      App/Coreplay/Assets.xcassets/AppIcon.appiconset \
      Packages/DesignSystem/Sources/DesignSystem/Resources/Brand.xcassets/AppLogo.imageset \
      /tmp

The tile bounds below were measured from the current source image; update
them if the artwork changes size or position.

Outputs:
  - iOS app icon: full-bleed 1024×1024, opaque (iOS applies its own mask).
  - macOS app icon: the tile on a transparent 1024 canvas at Apple's 824-pt grid,
    with a soft drop shadow, in all ten sizes.
  - AppLogo: the tile with transparent corners for in-app use (1×, 2×, 3×).
"""
import sys
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

src_path, ios_dir, logo_dir, preview_dir = sys.argv[1:5]
src = Image.open(src_path).convert("RGB")

# Tile bounds measured from the source (left 166, right 1085, top 148, bottom 1077).
LEFT, RIGHT, TOP, BOTTOM = 166, 1085, 148, 1077
side = RIGHT - LEFT + 1                      # 920
cy = (TOP + BOTTOM) / 2
box = (LEFT, int(round(cy - side / 2)), LEFT + side, int(round(cy - side / 2)) + side)
tile = src.crop(box)                          # 920×920, tile edges at the crop edges
RADIUS = 232                                  # from the 68 px diagonal inset of the corner

def rounded_mask(size, radius, inset=0, supersample=4):
    s = size * supersample
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [inset * supersample, inset * supersample, s - 1 - inset * supersample, s - 1 - inset * supersample],
        radius=(radius - inset) * supersample, fill=255)
    return m.resize((size, size), Image.LANCZOS)

# --- iOS: full bleed. Keep the tile's interior (minus its glassy rim) and
# inpaint the corners and rim from the surrounding background.
RIM = 22
keep = np.array(rounded_mask(side, RADIUS, inset=RIM)) > 250
arr = cv2.cvtColor(np.array(tile), cv2.COLOR_RGB2BGR)
hole = (~keep).astype(np.uint8) * 255
filled = cv2.inpaint(arr, hole, 9, cv2.INPAINT_TELEA)
# Smooth the inpainted band so it reads as the same soft gradient as the tile.
blurred = cv2.GaussianBlur(filled, (0, 0), 18)
band = cv2.GaussianBlur(hole.astype(np.float32) / 255.0, (0, 0), 6)[..., None]
merged = (filled * (1 - band) + blurred * band).astype(np.uint8)
ios = Image.fromarray(cv2.cvtColor(merged, cv2.COLOR_BGR2RGB)).resize((1024, 1024), Image.LANCZOS)
ios.save(f"{ios_dir}/AppIcon-iOS-1024.png")

# --- macOS: the tile as designed (rim included) on a transparent canvas.
BODY = 824
tile_rgba = tile.convert("RGBA")
tile_rgba.putalpha(rounded_mask(side, RADIUS))
body = tile_rgba.resize((BODY, BODY), Image.LANCZOS)
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
offset = (1024 - BODY) // 2
shadow_mask = Image.new("L", (1024, 1024), 0)
shadow_mask.paste(body.split()[3], (offset, offset + 12))
shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 120), (0, 0), shadow_mask)
shadow = shadow.filter(ImageFilter.GaussianBlur(16))
canvas = Image.alpha_composite(canvas, shadow)
canvas.alpha_composite(body, (offset, offset))
for points in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        px = points * scale
        canvas.resize((px, px), Image.LANCZOS).save(f"{ios_dir}/AppIcon-mac-{points}@{scale}x.png")

# --- In-app logo: the tile with transparent corners, 128 pt base.
for scale in [1, 2, 3]:
    px = 128 * scale
    tile_rgba.resize((px, px), Image.LANCZOS).save(f"{logo_dir}/AppLogo@{scale}x.png")

# Previews for checking by eye.
preview = Image.new("RGB", (1024 * 2 + 40, 1024), (255, 255, 255))
masked = ios.convert("RGBA")
masked.putalpha(rounded_mask(1024, int(1024 * 0.2237)))
preview.paste(masked, (0, 0), masked)
preview.paste(canvas, (1024 + 40, 0), canvas)
preview.save(f"{preview_dir}/icon-preview.png")
print("ok")
