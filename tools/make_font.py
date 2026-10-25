"""The bubbles' font: Pangolin (tools/fonts/pangolin.ttf, the Teardown mod's, with U+2B1A added; OFL) as a DST font
package - fonts/pc_pangolin.zip, holding font.fnt (BMFont XML) and font.tex (KTEX), as the game's own fonts are.

    python tools/make_font.py

As the game's fonts (read from data/databundles/fonts.zip, 2026-10-15): drawn at size 50, white letters in a black
outline (so a colour tints the letter and the outline stays dark, readable on any ground), DXT5 with mipmaps, flags 3.
Only Latin and Cyrillic are drawn here; everything else (Chinese, Japanese, Korean, the controller's ∷, ♪) comes from
the game's fallback fonts (modmain: SetupFontFallbacks with DEFAULT_FALLBACK_TABLE_OUTLINE).
Needs Pillow, numpy and fontTools (the conda env "teardown" has them).
"""
import os
import sys
import zipfile

import numpy as np
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import ktex  # noqa: E402

HERE = os.path.dirname(__file__)
TTF = os.path.join(HERE, "fonts", "pangolin.ttf")
OUT = os.path.join(HERE, "..", "fonts", "pc_pangolin.zip")
SIZE = 50             # the size the game scales from (Text(font, 28): 28 / 50 of these)
DRAW = 56             # drawn a bit bigger: Pangolin's letters are small for its size (the Teardown mod: 32 for 30)
LINE, BASE = 56, 44   # the line's height, and its baseline from the top
OUTLINE = 3           # the black outline, in pixels (the game's talkingfont: 3)
GAP = 4               # between glyphs on the sheet (their mipmaps must not touch)
SHEET_W = 1024
RANGES = [(0x20, 0x7E), (0xA0, 0x17F), (0x400, 0x45F), (0x490, 0x491), (0x2010, 0x2030), (0x20AC, 0x20AC),
          (0x2122, 0x2122), (0x2B1A, 0x2B1A)]


def disc(mask, r):
    """mask grown by r pixels in every direction (a round outline)"""
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r + r:
                continue
            src = mask[max(0, -dy):h - max(0, dy), max(0, -dx):w - max(0, dx)]
            dst = out[max(0, dy):h - max(0, -dy), max(0, dx):w - max(0, -dx)]
            np.maximum(dst, src, out=dst)
    return out


def glyph(font, ch, ascent):
    """-> (RGBA image, xoffset, yoffset, xadvance)"""
    adv = font.getlength(ch)
    x0, y0, x1, y1 = font.getbbox(ch)
    if x1 <= x0 or y1 <= y0:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0)), 0, BASE, round(adv)
    pad = OUTLINE + 1
    w, h = x1 - x0 + 2 * pad, y1 - y0 + 2 * pad
    im = Image.new("L", (w, h), 0)
    ImageDraw.Draw(im).text((pad - x0, pad - y0), ch, font=font, fill=255)
    a = np.asarray(im).astype(np.float32) / 255
    o = disc(a, OUTLINE)
    # white over black: the colour is the letter's coverage, the alpha the outline's (premultiplied = straight here,
    # since every see-through pixel is black)
    alpha = np.maximum(a, o)
    rgb = (a * 255).round().astype(np.uint8)
    rgba = np.dstack([rgb, rgb, rgb, (alpha * 255).round().astype(np.uint8)])
    # (y: the glyph's top from the line's top; PIL's bbox is from the ascender's top)
    return Image.fromarray(rgba, "RGBA"), x0 - pad, BASE - ascent + y0 - pad, round(adv)


def build():
    cmap = TTFont(TTF).getBestCmap()
    font = ImageFont.truetype(TTF, DRAW)
    ascent, _ = font.getmetrics()
    codes = [c for a, b in RANGES for c in range(a, b + 1) if c in cmap]
    glyphs = {c: glyph(font, chr(c), ascent) for c in codes}
    # shelves, tallest first
    order = sorted(codes, key=lambda c: -glyphs[c][0].size[1])
    x = y = shelf = 0
    pos = {}
    for c in order:
        w, h = glyphs[c][0].size
        if x + w > SHEET_W:
            x, y, shelf = 0, y + shelf + GAP, 0
        pos[c] = (x, y)
        x += w + GAP
        shelf = max(shelf, h)
    height = 1
    while height < y + shelf:
        height *= 2
    sheet = Image.new("RGBA", (SHEET_W, height), (0, 0, 0, 0))
    chars = []
    for c in codes:
        im, xo, yo, adv = glyphs[c]
        px, py = pos[c]
        sheet.paste(im, (px, py))
        chars.append(f'    <char id="{c}" x="{px}" y="{py}" width="{im.size[0]}" height="{im.size[1]}" xoffset="{xo}" '
                     f'yoffset="{yo}" xadvance="{adv}" page="0" chnl="15" />')
    fnt = "\n".join([
        '<?xml version="1.0"?>',
        "<font>",
        f'  <info face="Pangolin" size="{SIZE}" bold="0" italic="0" charset="" unicode="1" stretchH="100" smooth="1" '
        f'aa="1" padding="1,1,1,1" spacing="{GAP},{GAP}" outline="{OUTLINE}"/>',
        f'  <common lineHeight="{LINE}" base="{BASE}" scaleW="{SHEET_W}" scaleH="{height}" pages="1" packed="0" '
        'alphaChnl="1" redChnl="0" greenChnl="0" blueChnl="0"/>',
        "  <pages>",
        '    <page id="0" file="pc_pangolin_0.png" />',
        "  </pages>",
        f'  <chars count="{len(chars)}">',
        *chars,
        "  </chars>",
        "</font>",
        "",
    ])
    return sheet, fnt, len(codes)


if __name__ == "__main__":
    sheet, fnt, n = build()
    png = os.path.join(HERE, "fonts", "pc_pangolin_0.png")
    sheet.save(png)
    tex = os.path.join(HERE, "fonts", "pc_pangolin.tex")
    ktex.write(png, tex)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("font.fnt", fnt)
        z.write(tex, "font.tex")
    os.remove(tex)
    print(f"fonts/pc_pangolin.zip: {n} glyphs on {sheet.size[0]} x {sheet.size[1]}")
