"""Home-base and shop backgrounds (320x180, shown at 4x). Used by gen_assets.py."""
import math

from PIL import ImageDraw

from pixel import canvas, compose, dither_gradient, glow, part, px, rgb, rng, shift

W, H = 320, 180


def warm_glow(img, cx, cy, radius, color, strength=90):
    """Dithered radial light pool."""
    layer = canvas(W, H)
    c = rgb(color)
    for y in range(max(0, cy - radius), min(H, cy + radius)):
        for x in range(max(0, cx - radius * 2), min(W, cx + radius * 2)):
            d = math.hypot((x - cx) / 2.0, y - cy) / radius
            if d < 1:
                a = int(strength * (1 - d))
                if d > 0.6 and (x + y) % 2:
                    continue
                layer.putpixel((x, y), (*c[:3], a))
    return compose(img, layer)


def fire(img, cx, base_y, scale=1.0):
    s = (W, H)
    h = int(18 * scale)
    w = int(7 * scale)
    outer = part(s, lambda d: d.polygon([(cx, base_y - h), (cx + w, base_y - h // 3), (cx + w - 1, base_y), (cx - w + 1, base_y), (cx - w, base_y - h // 3)], fill=255), "#e0562a", outline=rgb("#6a1e1a"))
    inner = part(s, lambda d: d.polygon([(cx, base_y - h * 2 // 3), (cx + w // 2 + 1, base_y - h // 4), (cx + w // 2, base_y), (cx - w // 2, base_y), (cx - w // 2 - 1, base_y - h // 4)], fill=255), "#ffd060", outline=None)
    return compose(img, glow(compose(outer, inner), rgb("#ffa040"), 2, 80))


def sky(img, top, bottom, stars=40, seed=1, height=120):
    dither_gradient(img, (0, 0, W, height), top, bottom, steps=7)
    r = rng(seed)
    for _ in range(stars):
        x, y = r.randint(0, W - 1), r.randint(0, height // 2)
        px(img, [(x, y)], "#d8e0f0" if r.random() < 0.7 else "#fff4c0")


def conifers(img, color, base_y, count, height, seed):
    r = rng(seed)
    d = ImageDraw.Draw(img)
    c = rgb(color)
    d.rectangle([0, base_y, W, H], fill=c)
    for _ in range(count):
        x = r.randint(-10, W + 10)
        h = r.randint(height // 2, height)
        w = r.randint(8, 16)
        for tier in range(4):
            ty = base_y - h + tier * h // 4
            tw = w * (tier + 2) // 5
            d.polygon([(x, ty - 6), (x - tw, ty + h // 3), (x + tw, ty + h // 3)], fill=c)


def camp():
    img = canvas(W, H)
    sky(img, "#0e0c20", "#2a3050", 70, seed=3)
    moon = part((W, H), lambda d: d.ellipse([40, 16, 62, 38], fill=255), "#e8f0d0", outline=None)
    cut = ImageDraw.Draw(moon)
    cut.ellipse([46, 12, 70, 36], fill=(0, 0, 0, 0))
    img = compose(img, glow(moon, rgb("#e8f0d0"), 3, 50))
    conifers(img, "#1c2438", 118, 30, 60, 5)
    conifers(img, "#121828", 132, 16, 70, 6)
    ground = canvas(W, H)
    dither_gradient(ground, (0, 132, W, H), "#2c3424", "#12160e", steps=5)
    img = compose(img, ground)
    r = rng(8)
    for x in range(0, W, 2):
        px(img, [(x, 132 - k) for k in range(r.randint(1, 3))], "#3a5a30")
    img = warm_glow(img, 120, 150, 46, "#ff9a40", 110)
    s = (W, H)
    tent = part(s, lambda d: d.polygon([(178, 150), (214, 100), (252, 150)], fill=255), "#b89a6a")
    door = part(s, lambda d: d.polygon([(205, 150), (214, 118), (223, 150)], fill=255), "#3a2a20", light=False)
    flap = part(s, lambda d: d.polygon([(214, 118), (223, 150), (230, 150)], fill=255), "#d8c090")
    pole = part(s, lambda d: d.line([(214, 96), (214, 100)], fill=255, width=2), "#5a3a22")
    crate = part(s, lambda d: d.rectangle([150, 134, 166, 150], fill=255), "#8a6a3a")
    barrel = part(s, lambda d: d.rounded_rectangle([60, 128, 76, 150], radius=3, fill=255), "#7a5030")
    bench = part(s, lambda d: d.rounded_rectangle([82, 150, 110, 156], radius=2, fill=255), "#6a4428")
    logs = part(s, lambda d: (d.line([(108, 152), (132, 146)], fill=255, width=3), d.line([(108, 146), (132, 152)], fill=255, width=3)), "#5a3a22")
    stones = part(s, lambda d: [d.ellipse([100 + i * 7, 150, 106 + i * 7, 155], fill=255) for i in range(5)], "#6a6a70")
    lantern_pole = part(s, lambda d: (d.line([(28, 150), (28, 96)], fill=255, width=2), d.line([(28, 98), (40, 98)], fill=255, width=1)), "#4a3020")
    lantern = part(s, lambda d: d.rectangle([37, 100, 43, 108], fill=255), "#f0c060")
    img = compose(img, tent, door, flap, pole, crate, barrel, bench, lantern_pole, stones, logs)
    img = compose(img, glow(lantern, rgb("#ffd070"), 3, 90))
    img = fire(img, 120, 148, 1.2)
    for x, y in ((116, 118), (124, 110), (119, 102)):
        px(img, [(x, y)], "#ffd070")
    for _ in range(14):
        x, y = r.randint(0, W - 1), r.randint(70, 130)
        px(img, [(x, y)], "#e8ff9a")
    px(img, [(x, 142) for x in range(152, 166, 3)], "#5a4020")
    return img


def bricks(img, box, base, seed, brick=(14, 7)):
    x0, y0, x1, y1 = box
    r = rng(seed)
    d = ImageDraw.Draw(img)
    mortar = shift(rgb(base), 0.02, 1.1, 0.55)
    d.rectangle(box, fill=mortar)
    bw, bh = brick
    for row, y in enumerate(range(y0, y1, bh)):
        offset = (bw // 2) * (row % 2)
        for x in range(x0 - offset, x1, bw):
            tone = shift(rgb(base), 0, 1, r.uniform(0.85, 1.1))
            d.rectangle([max(x0, x + 1), y + 1, min(x1, x + bw - 1), min(y1, y + bh - 1)], fill=tone)
            px(img, [(max(x0, x + 1), y + 1)], shift(tone, 0, 0.9, 1.15))


def hall():
    img = canvas(W, H)
    bricks(img, (0, 0, W, 130), "#4a4658", 11)
    d = ImageDraw.Draw(img)
    # arched window with night sky
    window = canvas(W, H)
    dither_gradient(window, (48, 24, 88, 76), "#101830", "#2a3a60", steps=4)
    mask = canvas(W, H)
    ImageDraw.Draw(mask).rounded_rectangle([48, 18, 88, 76], radius=20, fill=(255, 255, 255, 255))
    import numpy as np
    wa = np.array(window)
    wa[np.array(mask)[:, :, 3] == 0] = 0
    from PIL import Image
    img = compose(img, Image.fromarray(wa, "RGBA"))
    d.rounded_rectangle([47, 17, 89, 77], radius=21, outline=rgb("#2a2430"), width=2)
    d.line([(68, 18), (68, 76)], fill=rgb("#2a2430"), width=2)
    d.line([(48, 46), (88, 46)], fill=rgb("#2a2430"), width=2)
    px(img, [(56, 32), (78, 28), (60, 60)], "#e0e8ff")
    # floor planks
    floor = canvas(W, H)
    dither_gradient(floor, (0, 130, W, H), "#6a4a30", "#2a1a10", steps=5)
    img = compose(img, floor)
    d = ImageDraw.Draw(img)
    for i in range(-8, 9):
        d.line([(160 + i * 12, 130), (160 + i * 40, H)], fill=rgb("#3a2618"), width=1)
    for y in (140, 154, 170):
        d.line([(0, y), (W, y)], fill=rgb("#3a2618"), width=1)
    s = (W, H)
    # fireplace
    hearth = part(s, lambda dd: dd.rectangle([112, 70, 178, 132], fill=255), "#6a6470")
    mouth = part(s, lambda dd: dd.rounded_rectangle([124, 92, 166, 132], radius=10, fill=255), "#1a1014", light=False)
    mantle = part(s, lambda dd: dd.rectangle([106, 64, 184, 72], fill=255), "#7a5a3a")
    img = compose(img, hearth, mouth, mantle)
    img = warm_glow(img, 145, 128, 50, "#ff9040", 100)
    img = fire(img, 138, 130, 1.0)
    img = fire(img, 152, 130, 0.8)
    # banner
    banner = part(s, lambda dd: dd.polygon([(196, 16), (222, 16), (222, 70), (209, 62), (196, 70)], fill=255), "#9a2a3a")
    emblem = part(s, lambda dd: dd.polygon([(209, 28), (216, 38), (209, 50), (202, 38)], fill=255), "#e0b040")
    rod = part(s, lambda dd: dd.line([(192, 15), (226, 15)], fill=255, width=2), "#5a3a22")
    # torches
    img = compose(img, banner, emblem, rod)
    for tx in (30, 250):
        img = warm_glow(img, tx, 58, 24, "#ffb050", 80)
        img = compose(img, part(s, lambda dd, tx=tx: dd.polygon([(tx - 2, 60), (tx + 2, 60), (tx + 1, 72), (tx - 1, 72)], fill=255), "#5a3a22"))
        img = fire(img, tx, 60, 0.5)
    # table with map and candle
    table = part(s, lambda dd: (dd.rectangle([214, 128, 290, 134], fill=255), dd.rectangle([220, 134, 225, 158], fill=255), dd.rectangle([280, 134, 285, 158], fill=255)), "#7a5230")
    paper = part(s, lambda dd: dd.polygon([(228, 124), (262, 122), (266, 128), (230, 129)], fill=255), "#e0d0a0")
    candle = part(s, lambda dd: dd.rectangle([272, 116, 275, 127], fill=255), "#f0e8d0")
    img = compose(img, table, paper, candle)
    img = fire(img, 273, 116, 0.3)
    px(img, [(236, 125), (240, 126), (246, 124), (252, 125), (244, 127)], "#8a3a2a")
    # weapon rack
    rack = part(s, lambda dd: dd.rectangle([262, 40, 300, 44], fill=255), "#5a3a22")
    swords = part(s, lambda dd: [dd.line([(268 + i * 10, 36), (268 + i * 10, 96)], fill=255, width=2) for i in range(3)], "#c8d0dc")
    img = compose(img, swords, rack)
    return img


def tower():
    img = canvas(W, H)
    dither_gradient(img, (0, 0, W, 130), "#2a1a4a", "#f09050", steps=8)
    sun = part((W, H), lambda d: d.ellipse([196, 86, 244, 134], fill=255), "#ffd080", outline=None, light=False)
    img = compose(img, glow(sun, rgb("#ffb070"), 4, 70))
    r = rng(21)
    d = ImageDraw.Draw(img)
    for y, width, col in ((34, 90, "#c07aa0"), (52, 120, "#d88a90"), (70, 70, "#e8a080")):
        x = r.randint(0, W - width)
        d.rounded_rectangle([x, y, x + width, y + 5], radius=2, fill=rgb(col))
        d.rounded_rectangle([x + 20, y - 3, x + width - 30, y + 2], radius=2, fill=rgb(col))

    def ridge(color, base, amp, seed):
        rr = rng(seed)
        pts = [(0, H)]
        x = 0
        while x <= W:
            pts.append((x, base - rr.randint(0, amp)))
            x += rr.randint(12, 30)
        pts += [(W, base), (W, H)]
        ImageDraw.Draw(img).polygon(pts, fill=rgb(color))

    ridge("#6a3a6a", 112, 30, 4)
    ridge("#4a2850", 124, 22, 5)
    castle = rgb("#3a1e40")
    d.rectangle([40, 96, 70, 124], fill=castle)
    d.rectangle([48, 84, 56, 96], fill=castle)
    for x in range(40, 71, 6):
        d.rectangle([x, 92, x + 2, 96], fill=castle)
    d.polygon([(46, 84), (52, 72), (58, 84)], fill=castle)
    for bx, by in ((120, 40), (136, 34), (150, 44)):
        px(img, [(bx - 2, by - 1), (bx - 1, by), (bx, by + 1), (bx + 1, by), (bx + 2, by - 1)], "#2a1a30")
    s = (W, H)
    wall = canvas(W, H)
    bricks(wall, (0, 140, W, H), "#6a5a60", 30, (16, 8))
    img = compose(img, wall)
    merlons = part(s, lambda dd: [dd.rectangle([x, 124, x + 18, 141], fill=255) for x in range(0, W, 34)], "#7a6a70")
    pole = part(s, lambda dd: dd.line([(262, 50), (262, 126)], fill=255, width=3), "#5a3a22")
    flag = part(s, lambda dd: dd.polygon([(263, 52), (300, 58), (290, 64), (300, 70), (263, 72)], fill=255), "#b03040")
    img = compose(img, merlons, pole, flag)
    px(img, [(276, 60), (277, 61), (276, 62), (275, 61)], "#f0c050")
    return img


def shop():
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    r = rng(51)
    for x in range(0, W, 12):
        tone = shift(rgb("#6a4a30"), 0, 1, r.uniform(0.8, 1.05))
        d.rectangle([x, 0, x + 11, 130], fill=tone)
        d.line([(x, 0), (x, 130)], fill=rgb("#3a2618"))
        for y in (r.randint(10, 40), r.randint(60, 110)):
            px(img, [(x + 5, y), (x + 6, y)], "#3a2618")
    s = (W, H)
    img = warm_glow(img, 160, 40, 60, "#ffc070", 60)
    colors = ["#e04a5a", "#4a8ae0", "#6ad04a", "#e0b040", "#b060e0"]
    for shelf_y in (44, 80):
        img = compose(img, part(s, lambda dd, y=shelf_y: dd.rectangle([24, y, 136, y + 4], fill=255), "#8a6038"))
        for i, x in enumerate(range(30, 132, 13)):
            col = colors[(i + shelf_y) % len(colors)]
            bottle = part(s, lambda dd, x=x, y=shelf_y: (dd.ellipse([x, y - 12, x + 9, y - 1], fill=255), dd.rectangle([x + 3, y - 17, x + 6, y - 11], fill=255)), col)
            img = compose(img, bottle)
            px(img, [(x + 2, y - 9)], "#ffffff")
    img = compose(img, part(s, lambda dd: dd.rectangle([184, 30, 296, 34], fill=255), "#8a6038"))
    for i, x in enumerate(range(192, 292, 22)):
        img = compose(img, part(s, lambda dd, x=x: dd.polygon([(x + 8, 36), (x + 10, 36), (x + 11, 86), (x + 7, 86)], fill=255), "#c8d0dc"),
                      part(s, lambda dd, x=x: dd.rectangle([x + 3, 84, x + 15, 87], fill=255), "#d9a441"))
    shield = part(s, lambda dd: dd.polygon([(222, 94), (250, 94), (250, 110), (236, 124), (222, 110)], fill=255), "#5a7ab0")
    img = compose(img, shield)
    lamp = part(s, lambda dd: dd.ellipse([152, 14, 168, 30], fill=255), "#ffd070")
    img = compose(img, part(s, lambda dd: dd.line([(160, 0), (160, 14)], fill=255, width=1), "#3a2618"), glow(lamp, rgb("#ffd070"), 3, 90))
    # merchant behind the counter
    robe = part(s, lambda dd: dd.polygon([(140, 138), (150, 104), (170, 104), (180, 138)], fill=255), "#5a3a7a")
    hood = part(s, lambda dd: dd.ellipse([146, 86, 174, 114], fill=255), "#6a4a8a")
    face = part(s, lambda dd: dd.ellipse([152, 94, 168, 110], fill=255), "#20162a", light=False)
    img = compose(img, robe, hood, face)
    px(img, [(156, 101), (157, 101), (163, 101), (164, 101)], "#ffe070")
    counter = part(s, lambda dd: dd.rectangle([0, 132, W - 1, 179], fill=255), "#8a5a32")
    top = part(s, lambda dd: dd.rectangle([0, 128, W - 1, 136], fill=255), "#a8703c")
    img = compose(img, counter, top)
    d = ImageDraw.Draw(img)
    for x in range(20, W, 40):
        d.line([(x, 138), (x, 179)], fill=rgb("#5a3a20"))
    coins = part(s, lambda dd: [dd.ellipse([x, 122, x + 7, 128], fill=255) for x in (190, 196, 202, 193)], "#f0c040")
    scroll = part(s, lambda dd: dd.rectangle([100, 122, 126, 127], fill=255), "#e0d0a0")
    img = compose(img, coins, scroll)
    return img


def hub_backgrounds():
    return {"hub_camp": camp(), "hub_hall": hall(), "hub_tower": tower(), "shop": shop()}
