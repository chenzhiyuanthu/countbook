#!/usr/bin/env python3
"""Draw the app icon and every raster size the two platforms need.

The mark is the product's argument in one image: three ledger rules against the
vertical standard line, and the middle one crossing it — 破版, the same gesture
the app uses on screen when a day goes over. No letterform, no glyph, nothing to
translate.

Run: python3 scripts/gen-icons.py
"""
from PIL import Image, ImageDraw
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PALETTES = {
    "light": dict(ground="#F7F6F3", ink="#111110", faint="#C9C5BB", over="#A32A22"),
    "dark":  dict(ground="#121211", ink="#F2F0EA", faint="#3D3B36", over="#E0655A"),
}

S = 1024
LEFT = 196
STANDARD_X = 792          # the line you set for yourself
RULE_H = 52
STANDARD_W = 16
# Only the middle rule may cross the standard; the other two must stop short of
# it, or the mark stops meaning anything.
ROWS = [
    (348, 552, "ink"),    # a row inside the line
    (512, 828, "over"),   # the row that went past it, bleeding off the edge
    (676, 372, "ink"),    # and one well under
]


def draw(palette: dict, transparent: bool = False) -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0) if transparent else palette["ground"])
    d = ImageDraw.Draw(img)

    # The standard: a full-height hairline the rows are measured against.
    d.rectangle([STANDARD_X - STANDARD_W // 2, 214, STANDARD_X + STANDARD_W // 2, 810], fill=palette["faint"])

    for y, length, tone in ROWS:
        d.rectangle([LEFT, y - RULE_H // 2, LEFT + length, y + RULE_H // 2], fill=palette[tone])

    return img


def save(img: Image.Image, rel: str, size: int | None = None) -> None:
    out = ROOT / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    (img.resize((size, size), Image.LANCZOS) if size else img).save(out)
    print(f"  {rel}" + (f"  {size}px" if size else ""))


print("icons:")
light = draw(PALETTES["light"])
dark = draw(PALETTES["dark"])
# A tinted icon is composited by the system against its own background, so it
# ships as a mask: luminance carries the shape, the ground is transparent.
tinted = draw(dict(PALETTES["dark"], ground=(0, 0, 0, 0)), transparent=True)

save(light.convert("RGB"), "ios/Countbook/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
save(dark.convert("RGB"), "ios/Countbook/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024-dark.png")
save(tinted, "ios/Countbook/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024-tinted.png")

for size in (180, 192, 512):
    save(light.convert("RGB"), f"web/public/icon-{size}.png", size)
save(light.convert("RGB"), "web/public/apple-touch-icon.png", 180)
save(dark.convert("RGB"), "web/public/icon-512-dark.png", 512)
