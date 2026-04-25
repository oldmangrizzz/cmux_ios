#!/usr/bin/env python3
"""Generate iOS app icon PNGs for cmux terminal app."""

from PIL import Image, ImageDraw, ImageFont
import os

SIZES = {
    "icon-40.png": 40,
    "icon-58.png": 58,
    "icon-60.png": 60,
    "icon-76.png": 76,
    "icon-80.png": 80,
    "icon-87.png": 87,
    "icon-120.png": 120,
    "icon-152.png": 152,
    "icon-167.png": 167,
    "icon-180.png": 180,
    "icon-1024.png": 1024,
}

OUT_DIR = "/Users/grizzmed/cmux_ios/cmux_iOS/Assets.xcassets/AppIcon.appiconset"
BG = (26, 27, 38)        # Tokyo Night bg
TERMINAL_GREEN = (158, 206, 106)
PROMPT_CYAN = (125, 207, 255)
ACCENT = (122, 162, 247)

def make_icon(size):
    img = Image.new("RGBA", (size, size), BG)
    draw = ImageDraw.Draw(img)

    # Draw a terminal prompt symbol: a chevron ">" followed by underscore cursor
    # Scale everything relative to icon size
    pad = int(size * 0.22)
    line_h = int(size * 0.50)
    stroke = max(int(size * 0.045), 2)

    # Chevron ">"
    cx = int(size * 0.38)
    cy = int(size * 0.50)
    pts = [
        (cx - stroke, cy - line_h // 2),
        (cx + line_h // 2, cy),
        (cx - stroke, cy + line_h // 2),
    ]
    draw.line(pts, fill=TERMINAL_GREEN, width=stroke, joint="curve")

    # Cursor block
    cursor_x = int(size * 0.62)
    cursor_w = max(int(size * 0.06), 3)
    cursor_h = max(int(size * 0.20), 4)
    draw.rectangle(
        [cursor_x, cy - cursor_h // 2, cursor_x + cursor_w, cy + cursor_h // 2],
        fill=PROMPT_CYAN,
    )

    # Corner accent lines (subtle terminal frame)
    accent_stroke = max(stroke - 1, 1)
    corner_len = int(size * 0.10)
    # Top-left
    draw.line([pad, pad + corner_len, pad, pad], fill=ACCENT, width=accent_stroke)
    draw.line([pad, pad, pad + corner_len, pad], fill=ACCENT, width=accent_stroke)
    # Bottom-right
    draw.line([size - pad - corner_len, size - pad, size - pad, size - pad], fill=ACCENT, width=accent_stroke)
    draw.line([size - pad, size - pad, size - pad, size - pad - corner_len], fill=ACCENT, width=accent_stroke)

    return img


if __name__ == "__main__":
    for name, px in SIZES.items():
        path = os.path.join(OUT_DIR, name)
        make_icon(px).save(path, "PNG")
        print(f"  {path}  ({px}x{px})")
    print("Done.")
