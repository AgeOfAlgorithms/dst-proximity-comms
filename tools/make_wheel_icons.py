"""The controller wheel's pictures (Quick chat in DST's command wheel), drawn like the game's own wheel medallions
(images/command_wheel.tex: a brown frame on parchment, a black inked picture) - a different one for every folder and
every line, saying what it says (the user, 2026-10-13: "these nodes should all have different images representing
their words"). The pictures are Noto Emoji's (Google's black-and-white emoji font, SIL Open Font License 1.1:
images/NotoEmoji-OFL.txt), inked on the medallion; Quick chat's own is a drawn speech bubble.

Writes images/pc_wheel.png, images/pc_wheel.tex (KTEX, DXT5) and images/pc_wheel.xml (the atlas): 112 x 112 pictures
on a 1024 x 1024 sheet (DST's own wheel pictures are ~105 px). Names: pc_quick, pc_<folder>, pc_<folder>_<1..8>.
The folders and the lines' order are scripts/proxcomms/strings.lua's WHEEL_FOLDERS (the same in every language).

Needs Pillow (conda env "teardown") and the font (not in the repo):
  curl -L -o NotoEmoji.ttf "https://github.com/google/fonts/raw/main/ofl/notoemoji/NotoEmoji%5Bwght%5D.ttf"
Run from the repo root: python tools/make_wheel_icons.py <path to NotoEmoji.ttf>
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import ktex  # noqa: E402

N = 112          # one picture (9 x 9 on a 1024 sheet)
SHEET = 1024
K = 4            # drawn at 4x, then scaled down
INK = (24, 18, 12, 255)
FRAME_DARK = (58, 40, 22, 255)
FRAME = (128, 96, 52, 255)
FRAME_LIGHT = (176, 138, 78, 255)
PARCHMENT = (222, 205, 160, 255)
PARCHMENT_DARK = (190, 168, 118, 255)
PAPER = (247, 242, 228, 255)

# folder -> (its own picture, its 8 lines' pictures), as strings.lua's WHEEL_FOLDERS; "players" is the session's names
PICTURES = {
    "callouts": (0x1F4E2, [0x1F4CD, 0x1F463, 0x1F3C3, 0x1F440, 0x1F198, 0x1F92B, 0x270B, 0x26A0]),
    # (Over here! pin, Follow me footprints, Run! runner, Look! eyes, Help! SOS, Be quiet shush, Wait! hand, Watch out! sign)
    "questions": (0x2753, [0x1F464, 0x2753, 0x1F9ED, 0x23F0, 0x1F914, 0x1F527, 0x1F3AF, 0x1F3C1]),
    # (Who? person, What? ?, Where? compass, When? clock, Why? thinking, How? wrench, Correct? target, Ready? flag)
    "replies": (0x1F4AC, [0x1F44C, 0x1F64F, 0x2714, 0x1F614, 0x1F937, 0x1F926, 0x274C, 0x1F44D]),
    # (OK, Thanks! hands, Yes check, Sorry! sad, Dunno shrug, My bad facepalm, No cross, No problem thumbs up)
    "things": (0x1F392, [0x1F356, 0x1FAB5, 0x1FAA8, 0x1F33E, 0x1F3E0, 0x1F525, 0x1F479, 0x1F480]),
    # (Food meat, Wood log, Stone rock, Grass, Base house, Fire, Monster ogre, Boss skull)
    "insults": (0x1F620, [0x1F44E, 0x1F4A9, 0x1F423, 0x1F3F3, 0x1F4AA, 0x1F3AE, 0x1F921, 0x1F610]),
    # (You suck thumbs down, You stink, Noob chick, Loser white flag, Get good muscle, Skill issue pad, Clown, Bruh)
    "social": (0x1F60A, [0x1F44B, 0x270C, 0x1F451, 0x1F602, 0x1F605, 0x1F62E, 0x1F44F, 0x1F680]),
    # (Hi! wave, Bye! peace, I'm the best crown, LOL, Oops sweat, Wow!, Well played clap, Let's go! rocket)
    "survival": (0x26FA, [0x1F319, 0x1F37D, 0x1F526, 0x1F300, 0x1F43A, 0x2764, 0x2744, 0x1FA81]),
    # (Night is coming! moon, I'm starving plate, Need light torch, Going insane swirl, Hounds! wolf, Revive me! heart,
    #  Winter is coming snowflake, Kite it! kite)
    "players": (0x1F465, []),
}


def wobbly(points, amount):
    return [(x + random.uniform(-amount, amount), y + random.uniform(-amount, amount)) for x, y in points]


def circle(cx, cy, r, n=120, amount=0.0):
    pts = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return wobbly(pts, amount) if amount else pts


def medallion(d, c, s):
    d.polygon(circle(c, c, 61 * s, amount=0.8 * s), fill=INK)
    d.polygon(circle(c, c, 58 * s, amount=0.5 * s), fill=FRAME_DARK)
    d.polygon(circle(c, c, 55.5 * s, amount=0.5 * s), fill=FRAME)
    d.polygon(circle(c, c, 49.5 * s, amount=0.5 * s), fill=FRAME_LIGHT)
    d.polygon(circle(c, c, 47.5 * s, amount=0.5 * s), fill=INK)
    for k in range(20):
        t = k / 19
        col = tuple(int(PARCHMENT_DARK[i] + (PARCHMENT[i] - PARCHMENT_DARK[i]) * t) for i in range(3)) + (255,)
        r = (46 - k) * s
        d.ellipse((c - r, c - r, c + r, c + r), fill=col)


def emoji(d, c, s, font, cp):
    text = chr(cp)
    box = d.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text((c - w / 2 - box[0], c - h / 2 - box[1]), text, font=font, fill=INK)


def bubble(d, c, s):
    cx, cy, rx, ry = c, c - 3 * s, 31 * s, 23 * s
    pts = [(cx + rx * math.cos(2 * math.pi * i / 120), cy + ry * math.sin(2 * math.pi * i / 120)) for i in range(120)]
    d.polygon(wobbly(pts, 0.8 * s), fill=INK)
    d.polygon([(cx - 17 * s, cy + 15 * s), (cx - 26 * s, cy + 33 * s), (cx - 3 * s, cy + 19 * s)], fill=INK)
    inner = [(cx + (rx - 4.5 * s) * math.cos(2 * math.pi * i / 120), cy + (ry - 4.5 * s) * math.sin(2 * math.pi * i / 120))
             for i in range(120)]
    d.polygon(inner, fill=PAPER)
    d.polygon([(cx - 15 * s, cy + 14 * s), (cx - 21 * s, cy + 26 * s), (cx - 5 * s, cy + 16 * s)], fill=PAPER)
    for i in range(3):
        x = cx + (i - 1) * 13 * s
        d.ellipse((x - 4.5 * s, cy - 4.5 * s, x + 4.5 * s, cy + 4.5 * s), fill=INK)


def picture(name, cp, font, seed):
    random.seed(seed)
    s, c = K * N / 128, N * K / 2           # (the shapes are drawn for 128: scaled to N)
    im = Image.new("RGBA", (N * K, N * K), (0, 0, 0, 0))
    medallion(ImageDraw.Draw(im), c, s)
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if cp is None:
        bubble(d, c, s)
    else:
        emoji(d, c, s, font, cp)
    mask = Image.new("L", im.size, 0)
    r = 46 * s
    ImageDraw.Draw(mask).ellipse((c - r, c - r, c + r, c + r), fill=255)
    clipped = Image.new("RGBA", im.size, (0, 0, 0, 0))
    clipped.paste(layer, (0, 0), mask)
    im.alpha_composite(clipped)
    return im.resize((N, N), Image.LANCZOS)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    font = ImageFont.truetype(sys.argv[1], int(60 * K * N / 128))
    try:
        font.set_variation_by_axes([700])        # (bold: thin lines vanish at the wheel's size)
    except Exception:
        pass
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "images")
    os.makedirs(out, exist_ok=True)
    pics = [("pc_quick", None)]
    for folder, (own, lines) in PICTURES.items():
        pics.append(("pc_" + folder, own))
        for i, cp in enumerate(lines, 1):
            pics.append(("pc_%s_%d" % (folder, i), cp))
    cols = rows = SHEET // N
    assert len(pics) <= cols * rows, len(pics)
    sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
    elements = []
    for i, (name, cp) in enumerate(pics):
        col, row = i % cols, i // cols
        sheet.paste(picture(name, cp, font, i + 3), (col * N, row * N))
        u1, u2 = col * N / sheet.width, (col + 1) * N / sheet.width
        v2 = 1 - row * N / sheet.height          # (an atlas's v runs from the bottom of the sheet)
        v1 = 1 - (row + 1) * N / sheet.height
        elements.append('<Element name="%s.tex" u1="%.6f" u2="%.6f" v1="%.6f" v2="%.6f" />' % (name, u1, u2, v1, v2))
    sheet.save(os.path.join(out, "pc_wheel.png"))
    ktex.write(os.path.join(out, "pc_wheel.png"), os.path.join(out, "pc_wheel.tex"))
    with open(os.path.join(out, "pc_wheel.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write('<Atlas><Texture filename="pc_wheel.tex" /><Elements>' + "".join(elements) + "</Elements></Atlas>\n")
    print(len(pics), "pictures;", ktex.info(os.path.join(out, "pc_wheel.tex"))[1][0])


if __name__ == "__main__":
    main()
