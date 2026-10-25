"""The mod's icon and Workshop picture, in the look of DST's own round medallions (images/command_wheel.tex): a frame,
a hand-drawn speech bubble with "..." and sound waves (talk that carries a distance). Writes
  modicon.png (128 x 128), modicon.tex + modicon.xml (the game's), and tools/workshop/preview.png (512 x 512, the
  Workshop page's picture) - both in the POP palette (night blue, gold, the modes' colours on the dots; the user,
  2026-10-13: "make the preview image pop a little more, using different colors"). CLASSIC (brown on parchment, as
  the game's own medallions) was the first icon.
Needs Pillow (conda env "teardown"). Run from the repo root: python tools/make_icon.py
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import ktex  # noqa: E402

S = 1024  # drawn large, then scaled down

CLASSIC = dict(
    ink=(24, 18, 12), frame_dark=(58, 40, 22), frame=(128, 96, 52), frame_light=(176, 138, 78),
    inside_edge=(190, 168, 118), inside_mid=(222, 205, 160), bubble=(247, 242, 228),
    waves=[(92, 64, 34, 255), (92, 64, 34, 200), (92, 64, 34, 140)], dots=[(24, 18, 12)] * 3, glow=None,
)
POP = dict(
    ink=(14, 10, 24), frame_dark=(96, 50, 14), frame=(214, 142, 44), frame_light=(255, 214, 112),
    inside_edge=(16, 22, 58), inside_mid=(52, 78, 150), bubble=(255, 251, 240),
    # (the waves: yellow, orange, coral - warm against the night; the dots: Whisper purple, Speak teal, Yell orange)
    waves=[(255, 222, 86, 255), (255, 156, 52, 235), (255, 92, 92, 215)],
    dots=[(140, 92, 230), (24, 170, 160), (244, 122, 28)], glow=(255, 190, 90, 150),
)


def wobbly(points, amount):
    """a hand-drawn line: each point nudged a little"""
    return [(x + random.uniform(-amount, amount), y + random.uniform(-amount, amount)) for x, y in points]


def circle(cx, cy, r, n=180, amount=0.0):
    pts = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return wobbly(pts, amount) if amount else pts


def bubble_outline(cx, cy, rx, ry, tail):
    """an oval bubble with a tail toward `tail` (a point), as one polygon"""
    pts = []
    n = 160
    ang_t = math.atan2(tail[1] - cy, tail[0] - cx)
    for i in range(n):
        a = 2 * math.pi * i / n
        # (the tail: replace a narrow arc of the oval with a point)
        da = (a - ang_t + math.pi) % (2 * math.pi) - math.pi
        if abs(da) < 0.3:
            if abs(da) < 2 * math.pi / n:
                pts.append(tail)
            continue
        pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return pts


def draw(p):
    random.seed(7)  # (the same hand-drawn wobble for every palette)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    rgba = lambda col: tuple(col[:3]) + (col[3] if len(col) > 3 else 255,)  # noqa: E731
    # the medallion: ink rim, dark frame, frame, light bevel, ink
    d.polygon(circle(c, c, 500, amount=3), fill=rgba(p["ink"]))
    d.polygon(circle(c, c, 478, amount=2), fill=rgba(p["frame_dark"]))
    d.polygon(circle(c, c, 458, amount=2), fill=rgba(p["frame"]))
    d.polygon(circle(c, c, 410, amount=2), fill=rgba(p["frame_light"]))
    d.polygon(circle(c, c, 396, amount=2), fill=rgba(p["ink"]))
    # the inside: darker at the edge (a radial falloff)
    par = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pd = ImageDraw.Draw(par)
    for k in range(40):
        t = k / 39
        col = tuple(int(p["inside_edge"][i] + (p["inside_mid"][i] - p["inside_edge"][i]) * t) for i in range(3)) + (255,)
        pd.ellipse((c - 384 + k * 4, c - 384 + k * 4, c + 384 - k * 4, c + 384 - k * 4), fill=col)
    im.alpha_composite(par)
    # a warm glow behind the bubble (POP)
    if p["glow"]:
        glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse((c - 70 - 330, c - 70 - 270, c - 70 + 330, c - 70 + 270), fill=p["glow"])
        glow = glow.filter(ImageFilter.GaussianBlur(70))
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).ellipse((c - 384, c - 384, c + 384, c + 384), fill=255)
        clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        clipped.paste(glow, (0, 0), mask)
        im.alpha_composite(clipped)
    # sound waves: three arcs to the right (a voice that carries)
    for i, (r, col) in enumerate(zip([240, 300, 360], p["waves"])):
        box = (c - 40 - r, c - 70 - r, c - 40 + r, c - 70 + r)
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        if p["glow"]:  # (an ink edge under each wave, so it reads on the dark blue)
            ld.arc(box, start=-38, end=38, fill=rgba(p["ink"]), width=40 - i * 4)
        span = 36 if p["glow"] else 38
        ld.arc(box, start=-span, end=span, fill=rgba(col), width=30 - i * 4)
        im.alpha_composite(layer)
    d = ImageDraw.Draw(im)
    # the bubble: ink outline, then the paper inside
    tail = (c - 250, c + 255)
    d.polygon(wobbly(bubble_outline(c - 70, c - 70, 250, 190, tail), 3), fill=rgba(p["ink"]))
    inner = bubble_outline(c - 70, c - 70, 222, 163, (tail[0] + 34, tail[1] - 42))
    d.polygon(wobbly(inner, 2), fill=rgba(p["bubble"]))
    # "..." inside
    for i, col in enumerate(p["dots"]):
        x = c - 70 + (i - 1) * 105
        d.ellipse((x - 34, c - 70 - 34, x + 34, c - 70 + 34), fill=rgba(col))
    return im


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.makedirs(os.path.join(root, "tools", "workshop"), exist_ok=True)
    draw(POP).resize((512, 512), Image.LANCZOS).save(os.path.join(root, "tools", "workshop", "preview.png"))
    small = draw(POP).resize((128, 128), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
    small.save(os.path.join(root, "modicon.png"))
    ktex.write(os.path.join(root, "modicon.png"), os.path.join(root, "modicon.tex"))
    with open(os.path.join(root, "modicon.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write('<Atlas><Texture filename="modicon.tex" /><Elements><Element name="modicon.tex" u1="0" u2="1" v1="0" '
                'v2="1" /></Elements></Atlas>\n')
    print("\n".join(ktex.info(os.path.join(root, "modicon.tex"))[1]))


if __name__ == "__main__":
    main()
