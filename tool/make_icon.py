"""Generate the ImmichLauncher launcher icons.

Design: the Immich flower (icon/immich-logo.svg, from immich-app/immich
design/immich-logo.svg) with a white centre disc holding a power (on/off)
symbol drawn with a sweep gradient of the Immich colours, ordered like the
petals around the flower.

Outputs:
  - legacy mipmaps:   android/app/src/main/res/mipmap-*/ic_launcher.png
  - adaptive layers:  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png
  - icon/preview.png (512px) and icon/icon_1024.png

Run: python3 tool/make_icon.py   (requires Pillow)
"""
import math
import os
import re

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
LOGO = os.path.join(ROOT, "icon", "immich-logo.svg")

S = 2048  # working canvas = 108dp adaptive canvas (supersampled)
C = S / 2
U = S / 1024  # unit: dimensions below are expressed on a 1024 canvas

FLOWER_SCALE = 0.51  # flower bounding box / canvas; keeps it in the 66dp safe zone
DISC_R = 103 * U
POWER_R, POWER_STROKE = 61 * U, 21 * U
LEGACY_ZOOM = 1.45  # how much the legacy (non-adaptive) icon enlarges the foreground


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def parse_path(d):
    """Flatten an SVG path (M/L/H/V/C/S/Z, abs + rel) into a polygon."""
    toks = re.findall(r"[MmCcSsLlHhVvZz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    pts, i, cmd = [], 0, None
    cur = start = (0.0, 0.0)
    lastc = None

    def num():
        nonlocal i
        i += 1
        return float(toks[i - 1])

    def cubic(p0, p1, p2, p3):
        for k in range(1, 25):
            t = k / 24
            mt = 1 - t
            pts.append(tuple(mt ** 3 * p0[j] + 3 * mt * mt * t * p1[j] + 3 * mt * t * t * p2[j] + t ** 3 * p3[j]
                             for j in range(2)))

    while i < len(toks):
        if re.match(r"[A-Za-z]", toks[i]):
            cmd = toks[i]
            i += 1
        rel, c = cmd.islower(), cmd.upper()
        ox, oy = cur if rel else (0.0, 0.0)
        if c == "M":
            cur = start = (num() + ox, num() + oy)
            pts.append(cur)
            cmd, lastc = ("l" if rel else "L"), None
        elif c == "L":
            cur = (num() + ox, num() + oy)
            pts.append(cur)
            lastc = None
        elif c == "H":
            cur = (num() + ox, cur[1])
            pts.append(cur)
            lastc = None
        elif c == "V":
            cur = (cur[0], num() + oy)
            pts.append(cur)
            lastc = None
        elif c == "C":
            p1, p2, p3 = [(num() + ox, num() + oy) for _ in range(3)]
            cubic(cur, p1, p2, p3)
            lastc, cur = p2, p3
        elif c == "S":
            p1 = (2 * cur[0] - lastc[0], 2 * cur[1] - lastc[1]) if lastc else cur
            p2, p3 = [(num() + ox, num() + oy) for _ in range(2)]
            cubic(cur, p1, p2, p3)
            lastc, cur = p2, p3
        elif c == "Z":
            cur = start
    return pts


def load_petals():
    src = open(LOGO, encoding="utf-8").read()
    fills = dict(re.findall(r"\.(st\d)\{fill:(#[0-9A-Fa-f]{6});\}", src))
    return [(hex_rgb(fills[c]), parse_path(d)) for c, d in re.findall(r'class="(st\d)" d="([^"]+)"', src, re.S)]


PETALS = load_petals()  # red, pink, yellow, blue, green


def flower():
    xs = [x for _, p in PETALS for x, _ in p]
    ys = [y for _, p in PETALS for _, y in p]
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    f = S * FLOWER_SCALE / span
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for rgb, pts in PETALS:
        d.polygon([(C + (x - cx) * f, C + (y - cy) * f) for x, y in pts], fill=rgb + (255,))
    return img


def sweep_gradient():
    """Conic gradient starting at the top, clockwise, in the petals' order."""
    red, pink, yellow, blue, green = (rgb for rgb, _ in PETALS)
    order = [red, yellow, green, blue, pink]
    n = len(order)
    px = []
    for y in range(S):
        for x in range(S):
            f = ((math.atan2(x - C, -(y - C)) / (2 * math.pi)) % 1.0) * n
            i = int(f) % n
            px.append(lerp(order[i], order[(i + 1) % n], f - int(f)))
    img = Image.new("RGB", (S, S))
    img.putdata(px)
    return img


def power_mask():
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    r, w = POWER_R, POWER_STROKE
    d.arc([C - r, C - r, C + r, C + r], start=-55, end=235, fill=255, width=int(w))
    for ang in (-55, 235):  # round caps
        a = math.radians(ang)
        px, py = C + (r - w / 2) * math.cos(a), C + (r - w / 2) * math.sin(a)
        d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=255)
    d.rounded_rectangle([C - w / 2, C - r - w * 0.4, C + w / 2, C + r * 0.1], radius=w / 2, fill=255)
    return m


def foreground():
    fg = flower()
    shadow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shadow).ellipse([C - DISC_R, C - DISC_R + 6 * U, C + DISC_R, C + DISC_R + 6 * U], fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(10 * U))
    fg = Image.alpha_composite(fg, Image.merge("RGBA", [Image.new("L", (S, S), 0)] * 3 + [shadow]))
    disc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse([C - DISC_R, C - DISC_R, C + DISC_R, C + DISC_R], fill=(255, 255, 255, 255))
    fg = Image.alpha_composite(fg, disc)
    pw = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pw.paste(sweep_gradient(), (0, 0), power_mask())
    return Image.alpha_composite(fg, pw)


def legacy(fg):
    """Legacy icon: white circle background, foreground enlarged to fill it."""
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([16 * U, 16 * U, S - 16 * U, S - 16 * U], fill=255)
    out.paste((255, 255, 255, 255), (0, 0), mask)
    z = fg.resize((int(S * LEGACY_ZOOM),) * 2, Image.LANCZOS)
    zc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    zc.paste(z, ((S - z.width) // 2,) * 2)
    zc.putalpha(ImageChops.multiply(zc.getchannel("A"), mask))
    return Image.alpha_composite(out, zc)


def main():
    fg = foreground()
    leg = legacy(fg)
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, k in densities.items():
        d = os.path.join(RES, f"mipmap-{name}")
        os.makedirs(d, exist_ok=True)
        leg.resize((int(48 * k),) * 2, Image.LANCZOS).save(os.path.join(d, "ic_launcher.png"))
        fg.resize((int(108 * k),) * 2, Image.LANCZOS).save(os.path.join(d, "ic_launcher_foreground.png"))
    leg.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "icon", "preview.png"))
    leg.resize((1024, 1024), Image.LANCZOS).save(os.path.join(ROOT, "icon", "icon_1024.png"))
    print("done")


if __name__ == "__main__":
    main()
