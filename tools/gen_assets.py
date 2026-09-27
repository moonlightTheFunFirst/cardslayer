"""Generate CardSlayer's pixel-art assets into res://assets.

Run: python tools/gen_assets.py
Everything is drawn procedurally, so re-running reproduces the same files.
Sprites are exported at 1x; the game scales them with nearest filtering.
"""
import math
import os

from PIL import Image, ImageDraw

from pixel import (OUTLINE, canvas, compose, dither_gradient, flat, glow, outline_all, part, px, ramp, rgb, rng,
                   shift, upscale)

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")


def save(img, *path):
    target = os.path.join(ROOT, *path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    img.save(target)
    return target


# ---------------------------------------------------------------- characters

def hero():
    W, H = 56, 72
    s = (W, H)
    img = canvas(W, H)
    cape = part(s, lambda d: d.polygon([(19, 29), (27, 28), (24, 46), (18, 62), (8, 64), (11, 50)], fill=255), "#8c2b3a")
    leg_back = part(s, lambda d: (d.rectangle([22, 50, 27, 63], fill=255)), "#3a3550")
    boot_back = part(s, lambda d: d.polygon([(21, 62), (28, 62), (29, 70), (19, 70)], fill=255), "#5a3a2a")
    leg_front = part(s, lambda d: d.polygon([(29, 50), (35, 50), (37, 63), (31, 63)], fill=255), "#433d5e")
    boot_front = part(s, lambda d: d.polygon([(30, 62), (38, 62), (41, 67), (41, 70), (30, 70)], fill=255), "#6b4530")
    arm_back = part(s, lambda d: d.polygon([(22, 32), (26, 32), (25, 44), (21, 44)], fill=255), "#56607a")
    buckler = part(s, lambda d: d.ellipse([14, 36, 26, 49], fill=255), "#8a6a3a")
    torso = part(s, lambda d: d.polygon([(21, 29), (35, 29), (37, 40), (35, 51), (21, 51), (20, 40)], fill=255), "#5f7fa8")
    tabard = part(s, lambda d: d.polygon([(25, 33), (32, 33), (33, 52), (24, 52)], fill=255), "#b8b6c8")
    belt = part(s, lambda d: d.rectangle([20, 44, 36, 47], fill=255), "#6b4a2b")
    neck = part(s, lambda d: d.rectangle([26, 25, 31, 30], fill=255), "#e0a57a")
    head = part(s, lambda d: d.polygon([(23, 13), (35, 12), (38, 17), (37, 24), (33, 28), (26, 28), (23, 24)], fill=255), "#f0b98c", dither=False)
    hair = part(s, lambda d: d.polygon([(20, 14), (23, 7), (29, 5), (36, 7), (39, 12), (38, 16), (33, 13), (27, 15), (24, 20), (21, 22), (17, 19), (20, 17)], fill=255), "#d0762e")
    scarf = part(s, lambda d: (d.polygon([(23, 27), (34, 27), (35, 31), (22, 31)], fill=255), d.polygon([(22, 29), (16, 33), (11, 32), (14, 36), (22, 33)], fill=255)), "#c9384a")
    arm_front = part(s, lambda d: d.polygon([(31, 31), (36, 31), (41, 40), (38, 43), (33, 37)], fill=255), "#6c8cb4")
    glove = part(s, lambda d: d.rectangle([37, 39, 42, 44], fill=255), "#6b4530")
    blade = part(s, lambda d: d.polygon([(41, 38), (52, 17), (55, 15), (54, 19), (44, 40)], fill=255), "#d8e0ec")
    guard = part(s, lambda d: d.polygon([(37, 36), (40, 35), (47, 41), (45, 43)], fill=255), "#d9a441")
    grip = part(s, lambda d: d.polygon([(37, 43), (39, 42), (41, 46), (39, 47)], fill=255), "#4a3020")
    compose(img, cape, leg_back, boot_back, arm_back, buckler, leg_front, boot_front, torso, tabard, belt, neck, head, hair,
            scarf, grip, glove, guard, blade, arm_front)
    px(img, [(34, 18), (34, 19), (33, 19)], "#1f1a2e")  # eye
    px(img, [(33, 16), (34, 16), (35, 16)], "#8a4020")  # brow
    px(img, [(30, 18), (31, 18)], "#c98b62")
    px(img, [(34, 24), (35, 24)], "#b86a52")  # mouth
    px(img, [(27, 45), (28, 45), (29, 45)], "#f2cf5a")  # buckle
    px(img, [(20, 42), (20, 43)], "#f2cf5a")  # buckler boss
    px(img, [(47, 30), (49, 26), (51, 22)], "#ffffff")  # blade glint
    return img


def mossling():
    W, H = 48, 48
    s = (W, H)
    img = canvas(W, H)
    ear_l = part(s, lambda d: d.polygon([(14, 25), (1, 15), (4, 22), (12, 31)], fill=255), "#7f9046")
    ear_r = part(s, lambda d: d.polygon([(34, 23), (46, 13), (44, 21), (37, 30)], fill=255), "#6f8040")
    feet = part(s, lambda d: (d.ellipse([13, 41, 22, 47], fill=255), d.ellipse([26, 41, 35, 47], fill=255)), "#4a5528")
    body = part(s, lambda d: d.ellipse([11, 19, 38, 45], fill=255), "#6f7e3c")
    belly = part(s, lambda d: d.ellipse([15, 30, 29, 43], fill=255), "#a8a060", light=False)

    def cap(d):
        for box in ([9, 13, 24, 29], [17, 9, 34, 26], [27, 13, 40, 28], [13, 11, 24, 22]):
            d.ellipse(box, fill=255)
        d.rectangle([0, 26, 48, 48], fill=0)
    moss = part(s, cap, "#3f8f3c")
    arm = part(s, lambda d: d.polygon([(13, 33), (4, 36), (5, 40), (15, 38)], fill=255), "#7f9046")
    compose(img, ear_l, ear_r, feet, body, belly, moss, arm)
    for ex in (16, 23):
        px(img, [(ex + dx, 27 + dy) for dx in range(3) for dy in range(3)], "#ffe04a")
        px(img, [(ex, 28), (ex, 29)], "#1a1010")
    px(img, [(x, 34) for x in range(15, 26)], "#2a1a18")
    px(img, [(16, 33), (19, 33), (22, 33), (25, 33)], "#f0f0e0")
    px(img, [(3, 36), (3, 38), (4, 40)], "#f0f0e0")
    px(img, [(19, 13), (29, 15), (13, 19), (35, 20)], "#f07aa0")
    px(img, [(24, 11), (33, 19)], "#ffffff")
    return img


def thorn():
    W, H = 76, 58
    s = (W, H)
    img = canvas(W, H)
    legs_back = part(s, lambda d: (d.rectangle([46, 40, 52, 56], fill=255), d.rectangle([58, 40, 64, 56], fill=255)), "#3a2838")

    def spikes(d):
        for i, x in enumerate(range(20, 66, 6)):
            d.polygon([(x, 26), (x + 3, 6 + (i % 2) * 5), (x + 7, 26)], fill=255)
    spike = part(s, spikes, "#d6c98e")
    tail = part(s, lambda d: d.polygon([(62, 30), (75, 18), (73, 28), (67, 36)], fill=255), "#523650")
    body = part(s, lambda d: d.ellipse([12, 18, 68, 47], fill=255), "#5d3c56")
    legs_front = part(s, lambda d: (d.polygon([(15, 40), (22, 40), (21, 56), (13, 56)], fill=255), d.polygon([(26, 40), (33, 40), (33, 56), (25, 56)], fill=255)), "#4c3248")
    head = part(s, lambda d: d.polygon([(3, 27), (15, 18), (27, 21), (28, 39), (13, 43), (1, 37)], fill=255), "#704862")
    vine = part(s, lambda d: d.line([(26, 22), (34, 34), (44, 30), (52, 42), (60, 34)], fill=255, width=2), "#4f8a3e")
    compose(img, legs_back, spike, tail, body, legs_front, head, vine)
    eye = canvas(W, H)
    px(eye, [(9, 27), (10, 27), (9, 28), (10, 28)], "#ff5a3a")
    img = compose(img, glow(eye, rgb("#ff5a3a"), 2, 120))
    px(img, [(10, 27)], "#fff0c0")
    px(img, [(3, 37), (6, 38), (9, 39)], "#f0ecd0")  # teeth
    px(img, [(4, 40), (4, 41), (5, 42)], "#f0ecd0")  # tusk
    return img


def wisp():
    W, H = 44, 58
    s = (W, H)
    edge = rgb("#6a1e1a")
    outer = part(s, lambda d: d.polygon([(22, 1), (26, 10), (32, 14), (30, 20), (37, 28), (37, 40), (30, 50), (22, 54), (13, 50), (6, 40), (6, 29), (12, 22), (11, 13), (17, 16)], fill=255), "#e0562a", outline=edge)
    mid = part(s, lambda d: d.polygon([(22, 12), (27, 24), (31, 34), (28, 45), (22, 49), (15, 45), (12, 34), (16, 24)], fill=255), "#f4a23a", outline=None)
    core = part(s, lambda d: d.ellipse([14, 30, 30, 48], fill=255), "#fff2a4", outline=None, light=False)
    img = compose(canvas(W, H), outer, mid, core)
    for ex in (17, 25):
        px(img, [(ex, 35), (ex + 1, 35), (ex, 36), (ex + 1, 36), (ex, 37), (ex + 1, 37)], "#3a1414")
    px(img, [(20, 42), (21, 42), (22, 42), (23, 42)], "#3a1414")
    px(img, [(4, 12), (40, 8), (38, 46), (2, 44)], "#ffd070")
    return glow(img, rgb("#ffa040"), 3, 70)


def warden():
    W, H = 116, 132
    s = (W, H)
    img = canvas(W, H)
    arm_back = part(s, lambda d: d.polygon([(80, 52), (102, 66), (108, 88), (101, 90), (96, 72), (77, 62)], fill=255), "#4f3624")

    def crown(d):
        for box in ([12, 10, 58, 50], [36, 2, 88, 44], [64, 12, 108, 54], [22, 26, 96, 58]):
            d.ellipse(box, fill=255)
    leaves = part(s, crown, "#7a5a2c")
    roots = part(s, lambda d: (d.polygon([(30, 112), (50, 106), (54, 131), (18, 131)], fill=255), d.polygon([(62, 106), (86, 110), (98, 131), (60, 131)], fill=255)), "#4a3222")
    trunk = part(s, lambda d: d.polygon([(34, 42), (82, 40), (90, 72), (86, 114), (30, 114), (26, 72)], fill=255), "#6c4b30")
    face = flat(s, lambda d: d.ellipse([38, 54, 70, 84], fill=255), rgb("#24160f"))
    arm = part(s, lambda d: d.polygon([(34, 58), (16, 70), (10, 88), (17, 90), (24, 76), (40, 68)], fill=255), "#5c3f28")
    handle = part(s, lambda d: d.line([(14, 70), (10, 104)], fill=255, width=3), "#3a2618")
    hammer = part(s, lambda d: d.polygon([(0, 94), (24, 92), (26, 112), (2, 114)], fill=255), "#6f7c70")
    moss = part(s, lambda d: (d.ellipse([2, 90, 16, 98], fill=255), d.ellipse([18, 38, 34, 50], fill=255), d.ellipse([68, 36, 90, 48], fill=255), d.ellipse([46, 30, 60, 42], fill=255)), "#4a8a3a")
    shroom = part(s, lambda d: (d.pieslice([78, 48, 92, 60], 180, 360, fill=255), d.pieslice([26, 50, 38, 60], 180, 360, fill=255)), "#c0343a")
    compose(img, arm_back, leaves, roots, trunk, face, moss, arm, handle, hammer, shroom)
    r = rng(7)
    for _ in range(26):
        x, y = r.randint(32, 84), r.randint(86, 112)
        px(img, [(x, y), (x, y + 1), (x, y + 2)], "#4a3020")
    for _ in range(40):
        x, y = r.randint(16, 104), r.randint(8, 52)
        c = img.getpixel((x, y))
        if c[3] and c[:3] != OUTLINE[:3]:
            px(img, [(x, y)], r.choice(["#a07a3a", "#5a4020", "#c0903a"]))
    for x, y in ((80, 52), (83, 51), (30, 54), (33, 53)):
        px(img, [(x, y)], "#f0e0d0")
    eyes = canvas(W, H)
    for ex in (44, 58):
        px(eyes, [(ex + dx, 62 + dy) for dx in range(5) for dy in range(4)], "#8aff6a")
    img = compose(img, glow(eyes, rgb("#8aff6a"), 3, 110))
    px(img, [(46, 63), (60, 63)], "#ffffff")
    for x in range(44, 66, 3):
        px(img, [(x, 75), (x + 1, 76), (x + 2, 75)], "#8aff6a")
    return img


def slime():
    W, H = 40, 32
    s = (W, H)
    body = part(s, lambda d: d.polygon([(2, 31), (4, 18), (12, 8), (28, 8), (36, 18), (38, 31)], fill=255), "#4fb0a0")
    img = compose(canvas(W, H), body)
    px(img, [(14, 18), (14, 19), (24, 18), (24, 19)], "#10201e")
    px(img, [(10, 12), (11, 11)], "#e0fff8")
    return img


# ---------------------------------------------------------------- background

def background(boss=False):
    W, H = 320, 180
    img = canvas(W, H)
    r = rng(42 if not boss else 99)
    sky_top, sky_bottom = ("#120e24", "#3a4a58") if not boss else ("#1e0a14", "#6a2a2a")
    dither_gradient(img, (0, 0, W, 132), sky_top, sky_bottom, steps=7)
    moon_col = "#d8f0c8" if not boss else "#ffb080"
    moon = part((W, H), lambda d: d.ellipse([238, 18, 274, 54], fill=255), moon_col, outline=None)
    img = compose(img, glow(moon, rgb(moon_col), 4, 60))
    for cx, cy in ((250, 30), (262, 42), (246, 44)):
        px(img, [(cx, cy), (cx + 1, cy), (cx, cy + 1)], shift(rgb(moon_col), 0, 1.1, 0.85))
    for _ in range(60):
        x, y = r.randint(0, W - 1), r.randint(0, 70)
        if img.getpixel((x, y))[:3] != rgb(moon_col)[:3]:
            px(img, [(x, y)], "#c8d0e8" if r.random() < 0.7 else "#fff4c0")

    def trees(color, base_y, count, height, width, seed):
        rr = rng(seed)
        layer = canvas(W, H)
        d = ImageDraw.Draw(layer)
        c = rgb(color)
        d.rectangle([0, base_y, W, H], fill=c)
        for _ in range(count):
            x = rr.randint(-10, W + 10)
            h = rr.randint(height // 2, height)
            w = rr.randint(width // 2, width)
            if rr.random() < 0.65:
                for tier in range(4):
                    ty = base_y - h + tier * h // 4
                    tw = w * (tier + 2) // 5
                    d.polygon([(x, ty - 6), (x - tw, ty + h // 3), (x + tw, ty + h // 3)], fill=c)
            else:
                d.rectangle([x - 2, base_y - h, x + 2, base_y], fill=c)
                for b in range(3):
                    by = base_y - h + b * h // 4 + 4
                    dx = rr.choice((-1, 1)) * rr.randint(6, 12)
                    d.line([(x, by + 6), (x + dx, by)], fill=c, width=2)
        return layer

    far = "#26334a" if not boss else "#3a1a2a"
    mid = "#1a2234" if not boss else "#2a1020"
    near = "#10141e" if not boss else "#180a12"
    img = compose(img, trees(far, 112, 34, 46, 10, 1))
    fog = canvas(W, H)
    fog_col = rgb("#8aa0a8" if not boss else "#a07070")
    for y in range(104, 124):
        for x in range(W):
            if (x + y) % 2 == 0 and r.random() < 0.55 - abs(y - 114) / 22:
                fog.putpixel((x, y), (*fog_col[:3], 70))
    img = compose(img, fog)
    img = compose(img, trees(mid, 124, 18, 64, 14, 2))
    ground = canvas(W, H)
    dither_gradient(ground, (0, 128, W, H), "#2a3a2a" if not boss else "#3a2226", "#141a14" if not boss else "#140a0c", steps=5)
    img = compose(img, ground)
    gd = ImageDraw.Draw(img)
    path = rgb("#3e4034" if not boss else "#3e2a2a")
    gd.polygon([(40, 180), (110, 136), (220, 136), (300, 180)], fill=path)
    for y in range(137, 180, 3):
        for x in range(0, W, 2):
            if img.getpixel((x, y))[:3] == path[:3] and r.random() < 0.25:
                px(img, [(x, y)], shift(path, 0, 1, 0.8))
    grass = "#4a7a3a" if not boss else "#6a4a3a"
    for x in range(0, W, 2):
        px(img, [(x, 128 - k) for k in range(r.randint(1, 4))], grass)
    for _ in range(40):
        x, y = r.randint(0, W - 2), r.randint(132, 178)
        px(img, [(x, y), (x + 1, y)], "#5a6a4a" if not boss else "#5a3a3a")
    for _ in range(14):  # glowing mushrooms
        x, y = r.randint(4, W - 6), r.randint(130, 176)
        col = "#6af0e0" if not boss else "#ff7a4a"
        px(img, [(x, y), (x + 1, y), (x - 1, y), (x, y + 1)], col)
        px(img, [(x, y + 2)], "#c0c0a0")
    for _ in range(18):  # fireflies
        x, y = r.randint(0, W - 1), r.randint(60, 150)
        px(img, [(x, y)], "#e8ff9a" if not boss else "#ffb070")
    frame = canvas(W, H)
    fd = ImageDraw.Draw(frame)
    nc = rgb(near)
    fd.polygon([(0, 0), (22, 0), (18, 60), (26, 120), (34, 180), (0, 180)], fill=nc)
    fd.polygon([(320, 0), (296, 0), (302, 70), (290, 130), (286, 180), (320, 180)], fill=nc)
    fd.line([(20, 40), (60, 20), (90, 24)], fill=nc, width=3)
    fd.line([(300, 50), (262, 30)], fill=nc, width=2)
    for x, y in ((64, 22), (80, 25), (272, 34)):
        fd.line([(x, y), (x + 2, y + 10)], fill=nc, width=1)
    return compose(img, frame)


# ---------------------------------------------------------------- cards

CARD_COLORS = {"attack": "#a8404a", "support": "#3a7a8a", "buff": "#b08a3a"}


def card_frame(category):
    W, H = 80, 112
    s = (W, H)
    body = part(s, lambda d: d.rounded_rectangle([1, 1, 78, 110], radius=5, fill=255), CARD_COLORS[category])
    inner = flat(s, lambda d: d.rectangle([5, 66, 74, 106], fill=255), rgb("#231c2a"))
    window = flat(s, lambda d: d.rectangle([7, 17, 72, 62], fill=255), rgb("#120e18"))
    img = compose(canvas(W, H), body, inner, window)
    d = ImageDraw.Draw(img)
    d.rectangle([6, 16, 73, 63], outline=rgb("#1a1420"))
    d.rectangle([4, 65, 75, 107], outline=shift(rgb(CARD_COLORS[category]), 0, 1, 0.55))
    banner = part(s, lambda d2: d2.polygon([(15, 4), (76, 4), (74, 9), (76, 14), (15, 14)], fill=255), "#dccba0")
    ribbon = part(s, lambda d2: d2.rectangle([26, 60, 53, 68], fill=255), shift(rgb(CARD_COLORS[category]), 0, 1, 0.65))
    gem = part(s, lambda d2: d2.ellipse([0, 0, 17, 17], fill=255), "#e8842a")
    return compose(img, banner, ribbon, gem)


def art_base(category):
    W, H = 64, 44
    img = canvas(W, H)
    tops = {"attack": ("#3a1420", "#7a3a3a"), "support": ("#10283a", "#2a5a6a"), "buff": ("#2a2010", "#6a5a2a")}
    dither_gradient(img, (0, 0, W, H), *tops[category], steps=5)
    return img


def art(card_id, category):
    W, H = 64, 44
    s = (W, H)
    img = art_base(category)
    if card_id == "strike":
        slash = canvas(W, H)
        ImageDraw.Draw(slash).arc([8, -10, 70, 50], 100, 200, fill=rgb("#ffffff"), width=2)
        img = compose(img, glow(slash, rgb("#ffe0a0"), 2, 90),
                      part(s, lambda d: d.polygon([(14, 38), (46, 6), (50, 4), (48, 9), (17, 41)], fill=255), "#d8e0ec"),
                      part(s, lambda d: d.polygon([(10, 32), (14, 30), (22, 38), (19, 41)], fill=255), "#d9a441"),
                      part(s, lambda d: d.line([(10, 42), (15, 37)], fill=255, width=3), "#4a3020"))
    elif card_id == "guard":
        img = compose(img, glow(part(s, lambda d: d.polygon([(18, 6), (46, 6), (46, 22), (32, 40), (18, 22)], fill=255), "#7a8aa0"), rgb("#a0d0ff"), 3, 70),
                      part(s, lambda d: d.polygon([(24, 11), (40, 11), (40, 21), (32, 32), (24, 21)], fill=255), "#b03a44"))
        px(img, [(31, 14), (32, 14), (31, 15), (32, 15), (30, 16), (33, 16), (31, 17), (32, 17)], "#f2cf5a")
    elif card_id == "heavy_strike":
        burst = canvas(W, H)
        bd = ImageDraw.Draw(burst)
        for a in range(0, 360, 30):
            rr = 18 if a % 60 else 24
            bd.line([(32, 36), (32 + rr * math.cos(math.radians(a)), 36 + rr * math.sin(math.radians(a)) * 0.5)], fill=rgb("#ffd060"), width=1)
        img = compose(img, burst,
                      part(s, lambda d: d.line([(46, 2), (36, 28)], fill=255, width=4), "#5a3a22"),
                      part(s, lambda d: d.polygon([(20, 24), (48, 20), (50, 34), (22, 38)], fill=255), "#8a929a"))
        px(img, [(x, 42) for x in range(10, 56, 3)], "#2a1a10")
    elif card_id == "fireball":
        trail = part(s, lambda d: d.polygon([(4, 40), (28, 18), (36, 30)], fill=255), "#c04020", outline=None)
        ball = part(s, lambda d: d.ellipse([26, 8, 50, 32], fill=255), "#f08a2a", outline=rgb("#6a1e1a"))
        core = part(s, lambda d: d.ellipse([32, 13, 44, 25], fill=255), "#fff0a0", outline=None, light=False)
        img = compose(img, trail, glow(compose(ball, core), rgb("#ffa040"), 3, 90))
        px(img, [(10, 30), (16, 38), (20, 26), (8, 36)], "#ffd070")
    elif card_id == "sweep":
        arcs = canvas(W, H)
        ad = ImageDraw.Draw(arcs)
        for i, col in enumerate(("#ffffff", "#ffe0b0", "#e0a070")):
            ad.arc([2 + i * 3, 8 + i * 3, 62 - i * 3, 52 - i * 3], 190, 350, fill=rgb(col), width=1)
        img = compose(img, glow(arcs, rgb("#ffe0a0"), 1, 80),
                      part(s, lambda d: d.polygon([(8, 34), (52, 24), (56, 26), (52, 28), (9, 37)], fill=255), "#d8e0ec"),
                      part(s, lambda d: d.polygon([(4, 36), (10, 30), (12, 39)], fill=255), "#d9a441"))
    elif card_id == "insight":
        for i, x in enumerate((10, 20, 30)):
            img = compose(img, part(s, lambda d, x=x, i=i: d.rectangle([x, 12 - i * 2, x + 14, 34 - i * 2], fill=255), "#d8c8a0"))
        eye = part(s, lambda d: d.ellipse([30, 14, 58, 32], fill=255), "#e8f0ff")
        iris = part(s, lambda d: d.ellipse([39, 17, 49, 29], fill=255), "#3a8adf", light=False)
        img = compose(img, glow(eye, rgb("#8ac8ff"), 3, 80), iris)
        px(img, [(43, 22), (44, 22), (43, 23), (44, 23)], "#10182a")
        px(img, [(41, 19)], "#ffffff")
    elif card_id == "heal":
        cross = part(s, lambda d: (d.rectangle([27, 8, 37, 38], fill=255), d.rectangle([17, 18, 47, 28], fill=255)), "#5ad06a")
        img = compose(img, glow(cross, rgb("#a0ffa0"), 3, 80))
        for x, y in ((12, 10), (52, 14), (48, 36), (14, 34), (8, 22)):
            px(img, [(x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)], "#e0ffd0")
    elif card_id == "focus":
        swirl = canvas(W, H)
        sd = ImageDraw.Draw(swirl)
        for i in range(4):
            sd.arc([12 + i * 5, 4 + i * 4, 52 - i * 5, 40 - i * 4], i * 70, i * 70 + 220, fill=rgb("#8ac8ff"), width=1)
        crystal = part(s, lambda d: d.polygon([(32, 8), (40, 20), (32, 36), (24, 20)], fill=255), "#4a90e0")
        img = compose(img, swirl, glow(crystal, rgb("#8ac8ff"), 2, 100))
        px(img, [(30, 14), (30, 15), (29, 16)], "#ffffff")
    elif card_id == "poison_stab":
        dagger = part(s, lambda d: d.polygon([(16, 36), (44, 10), (48, 8), (46, 13), (19, 39)], fill=255), "#c0d0c8")
        img = compose(img, dagger, part(s, lambda d: d.polygon([(12, 32), (16, 30), (22, 36), (19, 40)], fill=255), "#4a3a5a"))
        venom = canvas(W, H)
        for x, y in ((40, 16), (34, 22), (28, 28), (36, 26), (30, 34), (42, 22)):
            px(venom, [(x, y), (x, y + 1), (x - 1, y + 2), (x + 1, y + 2), (x, y + 3)], "#7aff4a")
        img = compose(img, glow(venom, rgb("#7aff4a"), 2, 80))
    elif card_id == "battle_cry":
        waves = canvas(W, H)
        wd = ImageDraw.Draw(waves)
        for i in range(3):
            wd.arc([20 - i * 7, 6 - i * 5, 44 + i * 7, 42 + i * 5], 200, 340, fill=rgb("#ffb040"), width=1)
        arm = part(s, lambda d: d.rectangle([27, 26, 37, 44], fill=255), "#b03a44")
        fist = part(s, lambda d: d.rounded_rectangle([21, 10, 43, 28], radius=3, fill=255), "#e8a878")
        img = compose(img, waves, arm, fist)
        px(img, [(x, y) for x in (26, 31, 36) for y in range(11, 17)], "#a86848")
        px(img, [(x, 22) for x in range(23, 34)], "#a86848")
    else:
        rune = part(s, lambda d: d.ellipse([20, 6, 44, 38], fill=255), CARD_COLORS[category])
        img = compose(img, glow(rune, rgb("#ffffff"), 2, 50))
        px(img, [(30, 14), (31, 14), (32, 14), (33, 15), (33, 16), (32, 17), (31, 18), (31, 19), (31, 22)], "#ffffff")
    return img


# ---------------------------------------------------------------- icons & ui

def icon(name):
    W = H = 16
    s = (W, H)
    if name == "attack":
        return compose(canvas(W, H), part(s, lambda d: d.polygon([(2, 12), (12, 2), (14, 2), (14, 4), (4, 14)], fill=255), "#d8e0ec"),
                       part(s, lambda d: d.polygon([(1, 10), (3, 9), (7, 13), (6, 15)], fill=255), "#d9a441"))
    if name == "block":
        return compose(canvas(W, H), part(s, lambda d: d.polygon([(2, 2), (14, 2), (14, 8), (8, 15), (2, 8)], fill=255), "#5a8ad0"))
    if name == "buff":
        return compose(canvas(W, H), part(s, lambda d: d.polygon([(8, 1), (15, 8), (11, 8), (11, 15), (5, 15), (5, 8), (1, 8)], fill=255), "#e04a3a"))
    if name == "poison":
        return compose(canvas(W, H), part(s, lambda d: (d.polygon([(8, 1), (13, 9), (3, 9)], fill=255), d.ellipse([3, 5, 13, 15], fill=255)), "#6ad04a"))
    if name == "heal":
        return compose(canvas(W, H), part(s, lambda d: (d.ellipse([1, 2, 8, 9], fill=255), d.ellipse([7, 2, 14, 9], fill=255), d.polygon([(1, 6), (14, 6), (8, 14)], fill=255)), "#e04a5a"))
    if name == "mp":
        return compose(canvas(W, H), part(s, lambda d: d.polygon([(8, 1), (14, 7), (8, 15), (2, 7)], fill=255), "#4a8ae0"))
    if name == "draw":
        return compose(canvas(W, H), part(s, lambda d: d.rectangle([2, 3, 9, 13], fill=255), "#c8b890"), part(s, lambda d: d.rectangle([6, 1, 13, 11], fill=255), "#e8d8b0"))
    if name == "unknown":
        img = compose(canvas(W, H), part(s, lambda d: d.ellipse([1, 1, 14, 14], fill=255), "#8a7aa0"))
        px(img, [(6, 4), (7, 4), (8, 4), (9, 5), (9, 6), (8, 7), (7, 8), (7, 9), (7, 11)], "#ffffff")
        return img
    raise ValueError(name)


def energy_orb():
    W = H = 40
    s = (W, H)
    ring = part(s, lambda d: d.ellipse([1, 1, 38, 38], fill=255), "#6a3a1a")
    core = part(s, lambda d: d.ellipse([5, 5, 34, 34], fill=255), "#f08a2a", outline=None)
    shine = part(s, lambda d: d.ellipse([11, 8, 20, 15], fill=255), "#ffe0a0", outline=None, light=False)
    return glow(compose(canvas(W, H), ring, core, shine), rgb("#ffa040"), 2, 80)


def deck_icon():
    W, H = 26, 30
    s = (W, H)
    img = canvas(W, H)
    for i in range(3):
        img = compose(img, part(s, lambda d, i=i: d.rounded_rectangle([2 + i * 3, 1 + i * 3, 17 + i * 3, 23 + i * 3], radius=2, fill=255), "#6a4a8a"))
    px(img, [(14, 14), (15, 15), (14, 16), (13, 15)], "#f2cf5a")
    return img


def nine_patch(fill, border, size=12):
    W = H = size
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    d.rectangle([1, 1, W - 2, H - 2], fill=rgb(fill))
    d.rectangle([0, 1, W - 1, H - 2], outline=OUTLINE)
    d.rectangle([1, 0, W - 2, H - 1], outline=OUTLINE)
    d.line([(2, 1), (W - 3, 1)], fill=shift(rgb(border), 0, 0.8, 1.2))
    d.line([(1, 2), (1, H - 3)], fill=shift(rgb(border), 0, 0.8, 1.2))
    d.line([(2, H - 2), (W - 3, H - 2)], fill=shift(rgb(border), 0, 1.1, 0.6))
    d.line([(W - 2, 2), (W - 2, H - 3)], fill=shift(rgb(border), 0, 1.1, 0.6))
    return upscale(img, 2)


CARD_IDS = {"strike": "attack", "guard": "support", "heavy_strike": "attack", "fireball": "attack", "sweep": "attack",
            "insight": "support", "heal": "support", "focus": "support", "poison_stab": "attack", "battle_cry": "buff"}


def build():
    save(hero(), "sprites", "hero.png")
    for name, fn in (("mossling", mossling), ("thorn", thorn), ("wisp", wisp), ("warden", warden), ("default", slime)):
        save(fn(), "sprites", "enemies", name + ".png")
    save(background(False), "backgrounds", "forest.png")
    save(background(True), "backgrounds", "forest_boss.png")
    for category in CARD_COLORS:
        save(card_frame(category), "cards", "frame_%s.png" % category)
        save(art("default", category), "cards", "art", "default_%s.png" % category)
    for card_id, category in CARD_IDS.items():
        save(art(card_id, category), "cards", "art", card_id + ".png")
    for name in ("attack", "block", "buff", "poison", "heal", "mp", "draw", "unknown"):
        save(icon(name), "ui", "icon_%s.png" % name)
    save(energy_orb(), "ui", "energy_orb.png")
    save(deck_icon(), "ui", "deck.png")
    save(nine_patch("#241c30", "#6a5a8a"), "ui", "panel.png")
    save(nine_patch("#8a4a2a", "#e0a050"), "ui", "button_end.png")
    save(nine_patch("#b0602a", "#ffd080"), "ui", "button_end_hover.png")
    save(nine_patch("#3a3040", "#6a6070"), "ui", "button_end_disabled.png")
    save(nine_patch("#2e2640", "#7a6aa0"), "ui", "button.png")
    save(nine_patch("#443a60", "#b0a0e0"), "ui", "button_hover.png")


if __name__ == "__main__":
    build()
    print("assets generated in", ROOT)
