"""The speech bubble's texture: a white rounded box cut in nine (DST's NineSlice: corners, edges, centre) and a tail
for each side (it points at the speaker from whichever side of the box faces them), tinted dark and see-through in game (scripts/widgets/pc_bubbles.lua).

    python tools/make_bubble.py            -> images/pc_bubble.png, .tex, .xml

Needs Pillow (the conda env "teardown" has it).
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import ktex  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "images")
W, H = 128, 64
PIECE = 12            # a corner's size (pc_bubbles.lua's CORNER)
RADIUS = 10
BOX = (8, 8)          # the box: 3 x 3 pieces from here
# the tails: x, y, width, height (pc_bubbles.lua's TAIL), and where the box is (its base; white beyond it, so the
# edge that meets the box samples white: no seam)
TAILS = {
    "tail_down": ((56, 8, 24, 12), "up"),
    "tail_up": ((56, 40, 24, 12), "down"),
    "tail_left": ((92, 8, 12, 24), "right"),
    "tail_right": ((112, 8, 12, 24), "left"),
}
SS = 8                # supersampling, for smooth edges


def draw():
    big = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(big)
    x, y, side = BOX[0] * SS, BOX[1] * SS, 3 * PIECE * SS
    d.rounded_rectangle([x, y, x + side - 1, y + side - 1], radius=RADIUS * SS, fill=255)
    for (tx, ty, tw, th), base in TAILS.values():
        tx, ty, tw, th, p = tx * SS, ty * SS, tw * SS, th * SS, 4 * SS
        if base == "up":
            d.rectangle([tx, ty - p, tx + tw - 1, ty - 1], fill=255)
            d.polygon([(tx, ty), (tx + tw, ty), (tx + tw / 2, ty + th)], fill=255)
        elif base == "down":
            d.rectangle([tx, ty + th, tx + tw - 1, ty + th + p - 1], fill=255)
            d.polygon([(tx, ty + th), (tx + tw, ty + th), (tx + tw / 2, ty)], fill=255)
        elif base == "right":
            d.rectangle([tx + tw, ty, tx + tw + p - 1, ty + th - 1], fill=255)
            d.polygon([(tx + tw, ty), (tx + tw, ty + th), (tx, ty + th / 2)], fill=255)
        else:
            d.rectangle([tx - p, ty, tx - 1, ty + th - 1], fill=255)
            d.polygon([(tx, ty), (tx, ty + th), (tx + tw, ty + th / 2)], fill=255)
    alpha = big.resize((W, H), Image.LANCZOS)
    im = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    im.putalpha(alpha)
    return im


def atlas():
    names = [["topleft", "top", "topright"], ["left", "center", "right"], ["bottomleft", "bottom", "bottomright"]]
    out = []
    for r, row in enumerate(names):
        for c, n in enumerate(row):
            out.append((n, BOX[0] + c * PIECE, BOX[1] + r * PIECE, PIECE, PIECE))
    for n, (rect, _) in TAILS.items():
        out.append((n, *rect))
    els = "".join(
        f'<Element name="{n}.tex" u1="{x / W:.6f}" u2="{(x + w) / W:.6f}" v1="{1 - (y + h) / H:.6f}" v2="{1 - y / H:.6f}" />'
        for n, x, y, w, h in out)
    return f'<Atlas><Texture filename="pc_bubble.tex" /><Elements>{els}</Elements></Atlas>'


if __name__ == "__main__":
    png = os.path.join(ROOT, "pc_bubble.png")
    draw().save(png)
    ktex.write(png, os.path.join(ROOT, "pc_bubble.tex"))
    open(os.path.join(ROOT, "pc_bubble.xml"), "w").write(atlas())
    print("images/pc_bubble.png, .tex, .xml")
