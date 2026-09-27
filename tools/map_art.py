"""Area map background (parchment, 320x180 shown at 4x) and node icons (24x24, shown at 2x)."""
import math

from PIL import ImageDraw

from pixel import canvas, compose, dither_gradient, part, px, rgb, rng

W, H = 320, 180
INK = "#4a3624"


def parchment():
    img = canvas(W, H)
    dither_gradient(img, (0, 0, W, H), "#e2cfa0", "#c8ad78", steps=5)
    r = rng(314)
    # Burnt, dithered edges.
    for y in range(H):
        for x in range(W):
            edge = min(x, y, W - 1 - x, H - 1 - y)
            if edge < 10 and ((x + y) % 2 == 0 or edge < 4):
                shade = "#8a6a40" if edge < 4 else "#a88a58"
                if edge < 2:
                    shade = "#5a4028"
                px(img, [(x, y)], shade)
    for _ in range(260):  # paper grain
        x, y = r.randint(10, W - 11), r.randint(10, H - 11)
        px(img, [(x, y)], "#d4bc8a" if r.random() < 0.6 else "#ecdcb4")
    d = ImageDraw.Draw(img)
    ink = rgb(INK)
    soft = rgb("#8a7050")
    # River.
    pts = [(24 + i * 4, 150 - int(18 * math.sin(i / 7)) - i // 3) for i in range(72)]
    for a, b in zip(pts, pts[1:]):
        d.line([a, b], fill=rgb("#6a8aa0"), width=2)
    # Scattered ink trees and hills (kept light so nodes stay readable).
    for _ in range(70):
        x, y = r.randint(16, W - 20), r.randint(18, H - 22)
        if r.random() < 0.75:
            d.polygon([(x, y - 6), (x - 4, y + 2), (x + 4, y + 2)], outline=soft)
            px(img, [(x, y + 3), (x, y + 4)], soft)
        else:
            d.arc([x - 7, y - 4, x + 7, y + 6], 180, 360, fill=soft)
    # Compass rose.
    cx, cy = W - 34, 30
    d.polygon([(cx, cy - 12), (cx + 3, cy), (cx, cy + 12), (cx - 3, cy)], fill=ink)
    d.polygon([(cx - 12, cy), (cx, cy - 3), (cx + 12, cy), (cx, cy + 3)], outline=ink)
    px(img, [(cx - 1, cy - 16), (cx, cy - 17), (cx + 1, cy - 16), (cx, cy - 15)], INK)
    return img


def node_icon(kind):
    S = (24, 24)
    base = part(S, lambda d: d.ellipse([1, 1, 22, 22], fill=255), "#e8d8b0", outline=rgb(INK))
    img = compose(canvas(24, 24), base)
    d = ImageDraw.Draw(img)
    ink = rgb(INK)
    if kind == "start":
        d.line([(9, 5), (9, 19)], fill=ink, width=2)
        d.polygon([(10, 5), (18, 8), (10, 12)], fill=rgb("#b03040"))
        d.line([(6, 19), (13, 19)], fill=ink, width=1)
    elif kind == "battle":
        d.line([(6, 6), (17, 17)], fill=ink, width=2)
        d.line([(17, 6), (6, 17)], fill=ink, width=2)
        d.line([(4, 10), (10, 4)], fill=ink, width=1)
        d.line([(13, 4), (19, 10)], fill=ink, width=1)
    elif kind == "boss":
        d.ellipse([5, 4, 18, 16], fill=ink)
        d.rectangle([8, 15, 15, 19], fill=ink)
        for ex in (8, 13):
            d.rectangle([ex, 8, ex + 2, 11], fill=rgb("#ff5040"))
        for tx in (9, 11, 13):
            px(img, [(tx, 17)], "#e8d8b0")
    return img


def map_assets():
    return {
        "backgrounds/map_parchment": parchment(),
        "map/node_start": node_icon("start"),
        "map/node_battle": node_icon("battle"),
        "map/node_boss": node_icon("boss"),
    }
