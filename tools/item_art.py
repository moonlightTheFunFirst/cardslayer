"""Consumable item icons (16x16, shown at 2x). Used by gen_assets.py."""
from PIL import ImageDraw

from pixel import canvas, compose, glow, part, px, rgb

S = (16, 16)


def bottle(body, liquid, cork="#a07040", tall=False):
    top = 2 if tall else 4
    glass = part(S, lambda d: (d.ellipse([3, top + 4, 12, 15], fill=255), d.rectangle([6, top, 9, top + 5], fill=255)), body)
    fill = part(S, lambda d: d.ellipse([4, top + 7, 11, 14], fill=255), liquid, outline=None)
    stopper = part(S, lambda d: d.rectangle([6, top - 2, 9, top], fill=255), cork)
    img = compose(canvas(16, 16), glass, fill, stopper)
    px(img, [(5, top + 7), (5, top + 8)], "#ffffff")
    return img


def herb():
    stem = part(S, lambda d: d.line([(8, 15), (8, 6)], fill=255, width=1), "#4a7a2a")
    leaves = part(S, lambda d: (d.ellipse([2, 4, 8, 9], fill=255), d.ellipse([8, 2, 14, 7], fill=255), d.ellipse([3, 9, 8, 13], fill=255), d.ellipse([9, 8, 14, 12], fill=255)), "#5ad05a")
    tie = part(S, lambda d: d.rectangle([7, 12, 9, 13], fill=255), "#c09050")
    img = compose(canvas(16, 16), stem, leaves, tie)
    px(img, [(4, 6), (10, 4)], "#c0ffc0")
    return img


def pill(color):
    img = compose(canvas(16, 16), part(S, lambda d: d.rounded_rectangle([2, 5, 14, 11], radius=3, fill=255), color),
                  part(S, lambda d: d.rounded_rectangle([8, 5, 14, 11], radius=3, fill=255), "#f0e8e0"))
    px(img, [(4, 6), (5, 6)], "#ffffff")
    return img


def dice():
    cube = part(S, lambda d: d.rounded_rectangle([2, 2, 13, 13], radius=2, fill=255), "#e8e0f0")
    img = compose(canvas(16, 16), cube)
    px(img, [(5, 5), (10, 5), (5, 10), (10, 10), (7, 7), (8, 8), (7, 8), (8, 7)], "#5a3a8a")
    return img


def item_icons():
    return {
        "herb": herb(),
        "elixir": glow(bottle("#d8e0f0", "#fff0a0", tall=True), rgb("#fff0a0"), 1, 70),
        "power": pill("#e0503a"),
        "defense": pill("#4a8ae0"),
        "vial": glow(bottle("#c0c8d0", "#ffe040"), rgb("#ffe040"), 1, 80),
        "dice": dice(),
        "potion_red": bottle("#c8d0d8", "#e04a5a"),
        "potion_blue": bottle("#c8d0d8", "#4a8ae0"),
    }
