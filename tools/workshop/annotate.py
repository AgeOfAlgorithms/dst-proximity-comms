"""The Workshop screenshots with a badge each: an icon (Noto Emoji, OFL) and a short title, in a look unlike the
game's bubbles (bright yellow, a bold UI font); the modes' shot also gets one-word tags. tools/workshop/screenshots/
<n>-<name>.jpg -> tools/workshop/screenshots/annotated/<n>-<name>.jpg

    python tools/workshop/annotate.py [path to NotoEmoji.ttf]

Positions are the screenshots' own pixels (2560 x 1378, taken by tools/devtest SHOTS=1). Needs Pillow; the title font
is Windows' Segoe UI Bold.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "screenshots")
OUT = os.path.join(SRC, "annotated")
TITLE_FONT = r"C:\Windows\Fonts\segoeuib.ttf"
SUB_FONT = r"C:\Windows\Fonts\segoeui.ttf"
EMOJI_FONT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "fonts", "NotoEmoji.ttf")
YELLOW = (255, 210, 64)
DARK = (28, 24, 20)

# file: (icon, title, where: "left" (top left) / "center" (top centre), keys to draw before the title, tags)
# tags: (word, its top-left, the arrow's tip)
SPECS = {
    "1-speech-modes": ("\U0001F4AC", "Proximity chat", (1240, 1120), None, [
        ("Whisper", (330, 300), (560, 222)),
        ("Speak", (1700, 36), (1646, 72)),
        ("Yell", (2160, 360), (2080, 228)),
    ]),
    "2-far-away-garbled": ("\U0001F442", "Too far? Garbled", "left", None, []),
    "3-translation": ("\U0001F310", "Auto translation", (140, 1080), None, []),
    "4-live-captions": ("\U0001F3A4", "Live captions", "left", None, [
        ("\U0001F3A4", (1896, 166), None),
    ], "Requires the free Koetama app"),
    "5-wes-brackets": ("\U0001F3AD", "Wes can talk", "left", None, []),
    "6-v-tab-mode-strip": (None, "Switch modes", "left", ["V", "+", "Tab"], []),
    "7-settings": ("\u2699", "In-game settings", (300, 1060), None, []),
    "8-controller-quick-chat": ("\U0001F3AE", "Controller support", "center", None, []),
    "9-languages": ("\U0001F310", "Talk across languages", (1240, 1000), None, [], "Requires the free Koetama app"),
}


def emoji_font(size):
    f = ImageFont.truetype(EMOJI_FONT, size)
    try:
        f.set_variation_by_name("Bold")
    except Exception:
        pass
    return f


def keycap(d, x, cy, text, font):
    """a keyboard key: x is its left edge, cy its middle; -> its right edge"""
    tw = d.textlength(text, font=font)
    w, h = max(78, tw + 40), 78
    d.rounded_rectangle([x, cy - h / 2 + 6, x + w, cy + h / 2 + 6], radius=14, fill=(150, 112, 20))
    d.rounded_rectangle([x, cy - h / 2, x + w, cy + h / 2], radius=14, fill=(255, 246, 220), outline=DARK, width=4)
    d.text((x + w / 2, cy), text, font=font, fill=DARK, anchor="mm")
    return x + w


def badge(d, W, icon, title, where, keys, sub=None):
    tf = ImageFont.truetype(TITLE_FONT, 64)
    kf = ImageFont.truetype(TITLE_FONT, 40)
    sf = ImageFont.truetype(SUB_FONT, 38)
    ef = emoji_font(76)
    pad, gap, h = 34, 22, (164 if sub else 118)
    # its width: the icon or the keys, then the title
    lead = 0
    if icon:
        lead = 84
    if keys:
        for k in keys:
            lead += (24 if k == "+" else max(78, d.textlength(k, font=kf) + 40)) + 10
    w = pad + lead + gap + max(d.textlength(title, font=tf), d.textlength(sub, font=sf) if sub else 0) + pad
    # (where: "left" / "center" along the top, or (x, y) - an empty spot of the shot)
    if isinstance(where, tuple):
        x, y = where
    else:
        x, y = (110 if where == "left" else (W - w) / 2), 34
    d.rounded_rectangle([x + 8, y + 10, x + w + 8, y + h + 10], radius=30, fill=(0, 0, 0, 120))   # (shadow)
    d.rounded_rectangle([x, y, x + w, y + h], radius=30, fill=YELLOW, outline=DARK, width=5)
    cx, cy = x + pad, y + h / 2
    if icon:
        d.text((cx + 40, cy + 2), icon, font=ef, fill=DARK, anchor="mm")
        cx += 84
    if keys:
        for k in keys:
            if k == "+":
                d.text((cx + 12, cy), "+", font=tf, fill=DARK, anchor="mm")
                cx += 34
            else:
                cx = keycap(d, cx, cy - 3, k, kf) + 10
    if sub:
        d.text((cx + gap, cy - 24), title, font=tf, fill=DARK, anchor="lm")
        d.text((cx + gap, cy + 36), sub, font=sf, fill=DARK, anchor="lm")
    else:
        d.text((cx + gap, cy - 2), title, font=tf, fill=DARK, anchor="lm")


def tag(d, word, xy, tip):
    import math
    icon = len(word) == 1 and ord(word) > 0x2000            # (one icon: in Noto Emoji, a bigger tag)
    f = emoji_font(56) if icon else ImageFont.truetype(TITLE_FONT, 40)
    x, y = xy
    w, h = (88, 88) if icon else (d.textlength(word, font=f) + 36, 64)
    box = (x, y, x + w, y + h)
    cx, cy = x + w / 2, y + h / 2
    if tip:
        # (the arrow from the side facing its tip; none: the tag sits right by what it names)
        sx = x + w if tip[0] > x + w else (x if tip[0] < x else cx)
        sy = cy if sx != cx else (y + h if tip[1] > cy else y)
        d.line([(sx, sy), tip], fill=DARK, width=11)
        d.line([(sx, sy), tip], fill=YELLOW, width=6)
        ang = math.atan2(tip[1] - sy, tip[0] - sx)
        head = 24
        pts = [tip, (tip[0] - head * math.cos(ang - 0.5), tip[1] - head * math.sin(ang - 0.5)),
               (tip[0] - head * math.cos(ang + 0.5), tip[1] - head * math.sin(ang + 0.5))]
        d.polygon(pts, fill=YELLOW, outline=DARK)
    d.rounded_rectangle(box, radius=20, fill=YELLOW, outline=DARK, width=4)
    d.text((cx, cy - 2), word, font=f, fill=DARK, anchor="mm")


def annotate(name, spec):
    icon, title, where, keys, tags = spec[:5]
    sub = spec[5] if len(spec) > 5 else None
    im = Image.open(os.path.join(SRC, name + ".jpg")).convert("RGBA")
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for word, xy, tip in tags:
        tag(d, word, xy, tip)
    badge(d, im.size[0], icon, title, where, keys, sub)
    out = Image.alpha_composite(im, layer).convert("RGB")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".jpg")
    out.save(path, quality=92)
    return path


if __name__ == "__main__":
    for name, spec in SPECS.items():
        print(annotate(name, spec))
