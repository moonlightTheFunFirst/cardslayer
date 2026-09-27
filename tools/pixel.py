"""Small pixel-art toolkit used by gen_assets.py.

Each part is drawn as a hard-edged mask, colored with a hue-shifted ramp,
rim lit / shaded, and outlined. Parts are composited back-to-front so the
sprites get internal outlines like hand-made pixel art.
"""
import colorsys
import random

import numpy as np
from PIL import Image, ImageDraw

OUTLINE = (24, 16, 32, 255)


def rgb(value, alpha=255):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def shift(color, hue=0.0, sat=1.0, val=1.0):
    r, g, b = (c / 255 for c in color[:3])
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    r, g, b = colorsys.hsv_to_rgb((h + hue) % 1.0, min(1, s * sat), min(1, v * val))
    return (round(r * 255), round(g * 255), round(b * 255), color[3] if len(color) > 3 else 255)


def ramp(base):
    """Highlight, base, shadow and deep shadow with hue shifting."""
    base = rgb(base) if isinstance(base, str) else base
    return {
        "hi": shift(base, -0.03, 0.8, 1.22),
        "base": base,
        "lo": shift(base, 0.04, 1.12, 0.72),
        "deep": shift(base, 0.07, 1.2, 0.5),
    }


def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def at(mask, dx, dy):
    """result[y, x] = mask[y + dy, x + dx], False outside."""
    h, w = mask.shape
    out = np.zeros_like(mask)
    ys = slice(max(0, -dy), min(h, h - dy))
    xs = slice(max(0, -dx), min(w, w - dx))
    ys2 = slice(max(0, dy), min(h, h + dy))
    xs2 = slice(max(0, dx), min(w, w + dx))
    out[ys, xs] = mask[ys2, xs2]
    return out


def part(size, fn, color, outline=OUTLINE, light=True, dither=True):
    """Draw a shaded, outlined part. fn(draw) paints with fill=255."""
    mask_img = Image.new("L", size, 0)
    fn(ImageDraw.Draw(mask_img))
    m = np.array(mask_img) > 127
    r = ramp(color)
    img = np.zeros((size[1], size[0], 4), np.uint8)
    img[m] = r["base"]
    if light:
        deep = m & ~at(m, 2, 2)
        lo = m & ~at(m, 1, 1)
        band = m & ~at(m, 3, 3) & ~deep
        if dither:
            yy, xx = np.indices(m.shape)
            img[band & ((xx + yy) % 2 == 0)] = r["lo"]
        img[deep] = r["lo"]
        img[lo & ~at(m, 0, 1)] = r["deep"]
        hi = m & (~at(m, -1, -1) | ~at(m, 0, -1)) & at(m, 1, 1)
        img[hi] = r["hi"]
    if outline is not None:
        grow = at(m, 1, 0) | at(m, -1, 0) | at(m, 0, 1) | at(m, 0, -1)
        img[grow & ~m] = outline
    return Image.fromarray(img, "RGBA")


def flat(size, fn, color):
    mask_img = Image.new("L", size, 0)
    fn(ImageDraw.Draw(mask_img))
    m = np.array(mask_img) > 127
    img = np.zeros((size[1], size[0], 4), np.uint8)
    img[m] = color if len(color) == 4 else (*color, 255)
    return Image.fromarray(img, "RGBA")


def compose(base, *layers):
    for layer in layers:
        base.alpha_composite(layer)
    return base


def px(img, points, color):
    color = rgb(color) if isinstance(color, str) else color
    for x, y in points:
        if 0 <= x < img.width and 0 <= y < img.height:
            img.putpixel((x, y), color)


def outline_all(img, color=OUTLINE):
    a = np.array(img)
    m = a[:, :, 3] > 0
    grow = at(m, 1, 0) | at(m, -1, 0) | at(m, 0, 1) | at(m, 0, -1)
    a[grow & ~m] = color
    return Image.fromarray(a, "RGBA")


def glow(img, color, radius=2, alpha=90):
    """Soft pixel halo behind opaque pixels (dithered, not blurred)."""
    a = np.array(img)
    m = a[:, :, 3] > 0
    halo = np.zeros_like(m)
    for dx in range(-radius, radius + 1):
        for dy in range(-radius, radius + 1):
            if dx * dx + dy * dy <= radius * radius:
                halo |= at(m, dx, dy)
    yy, xx = np.indices(m.shape)
    halo &= ~m & ((xx + yy) % 2 == 0)
    out = np.zeros_like(a)
    out[halo] = (*color[:3], alpha)
    under = Image.fromarray(out, "RGBA")
    under.alpha_composite(img)
    return under


def dither_gradient(img, box, top, bottom, steps=6, seed=0):
    """Banded vertical gradient with checker dithering at band edges."""
    x0, y0, x1, y1 = box
    top = rgb(top) if isinstance(top, str) else top
    bottom = rgb(bottom) if isinstance(bottom, str) else bottom
    colors = [tuple(round(top[i] + (bottom[i] - top[i]) * s / (steps - 1)) for i in range(3)) + (255,) for s in range(steps)]
    height = y1 - y0
    for y in range(y0, y1):
        t = (y - y0) / max(1, height - 1) * (steps - 1)
        band = int(t)
        frac = t - band
        for x in range(x0, x1):
            use = band
            if band + 1 < steps and frac > 0.5 and (x + y) % 2 == 0:
                use = band + 1
            elif band + 1 < steps and frac > 0.75:
                use = band + 1
            img.putpixel((x, y), colors[min(use, steps - 1)])


def upscale(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def rng(seed):
    return random.Random(seed)
