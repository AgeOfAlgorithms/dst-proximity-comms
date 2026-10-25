"""Klei's KTEX textures (Don't Starve Together's .tex), written as DXT5 - enough for a mod's icon.

    python tools/ktex.py info <file.tex>                 the header and mipmaps
    python tools/ktex.py write <in.png> <out.tex>        a PNG (any size; a power of two is best) -> .tex with mipmaps
    python tools/ktex.py read <in.tex> <out.png>         (a check) the first mipmap of a DXT5 .tex back to a PNG

The header (after "KTEX"), a 32-bit little-endian word, from the low bits: platform 4 (0: default), pixel format 5
(0 DXT1, 2 DXT5, 5 RGB), texture type 4 (1: 2D), mipmaps 5, flags 2, then 12 bits all set. Each mipmap: width u16,
height u16, pitch u16 (blocks across x 16), data size u32; then the mipmaps' data in that order. Rows are stored bottom
first (as ktools' ktech writes them by default). Read from the game's own files (2026-10-13): 1391 are DXT5 with flags
3, 105 DXT1, 33 RGB, none uncompressed RGBA - so this writes DXT5 with flags 3, as they are; colours premultiplied
by alpha, as ktech does by default (a straight-alpha icon showed a blocky light edge in game, 2026-10-13).
Needs Pillow (the conda env "teardown" has it).
"""
import struct
import sys

DXT5 = 2


def info(path):
    b = open(path, "rb").read()
    if b[:4] != b"KTEX":
        raise SystemExit(f"{path}: not KTEX")
    h = struct.unpack("<I", b[4:8])[0]
    f = dict(platform=h & 0xF, format=(h >> 4) & 0x1F, type=(h >> 9) & 0xF, mips=(h >> 13) & 0x1F, flags=(h >> 18) & 0x3,
             fill=hex(h >> 20))
    out = [f"{path}: {f}, {len(b)} bytes"]
    off = 8
    for i in range(f["mips"]):
        w, hh, pitch, size = struct.unpack("<HHHI", b[off:off + 10])
        off += 10
        out.append(f"  mip {i}: {w} x {hh}, pitch {pitch}, {size} bytes")
    return f, out


def _565(c):
    return ((c[0] >> 3) << 11) | ((c[1] >> 2) << 5) | (c[2] >> 3)


def _rgb(v):
    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def _block(px):
    """16 RGBA pixels (row by row) -> one 16-byte DXT5 block."""
    alphas = [p[3] for p in px]
    a0, a1 = max(alphas), min(alphas)
    if a0 == a1:
        aidx = [0] * 16
    else:
        pal = [a0, a1] + [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
        aidx = [min(range(8), key=lambda k: abs(pal[k] - a)) for a in alphas]
    abits = 0
    for i, k in enumerate(aidx):
        abits |= k << (3 * i)
    # colour: the two pixels farthest apart along the brightest axis (premultiplied: a transparent pixel is black, and
    #  black must be an end, or the block's transparent pixels add a colour - a blocky halo round a round picture)
    lo = min(px, key=lambda p: p[0] * 2 + p[1] * 4 + p[2])
    hi = max(px, key=lambda p: p[0] * 2 + p[1] * 4 + p[2])
    c0, c1 = _565(hi), _565(lo)
    if c0 < c1:
        c0, c1 = c1, c0
    e0, e1 = _rgb(c0), _rgb(c1)
    pal = [e0, e1, tuple((2 * x + y) // 3 for x, y in zip(e0, e1)), tuple((x + 2 * y) // 3 for x, y in zip(e0, e1))]
    cbits = 0
    for i, p in enumerate(px):
        k = 0 if c0 == c1 else min(range(4), key=lambda j: sum((pal[j][c] - p[c]) ** 2 for c in range(3)))
        cbits |= k << (2 * i)
    return struct.pack("<BB", a0, a1) + abits.to_bytes(6, "little") + struct.pack("<HHI", c0, c1, cbits)


def _dxt5(im):
    w, h = im.size
    data = im.load()
    out = bytearray()
    for by in range(0, max(h, 1), 4):
        for bx in range(0, max(w, 1), 4):
            px = [data[min(bx + x, w - 1), min(by + y, h - 1)] for y in range(4) for x in range(4)]
            out += _block(px)
    return bytes(out)


def premultiply(im):
    """colours times alpha: DST draws textures premultiplied (Klei's ktech premultiplies by default); a straight-alpha
    texture shows its transparent pixels' colour as a light, blocky edge"""
    from PIL import Image, ImageChops
    r, g, b, a = im.split()
    return Image.merge("RGBA", (ImageChops.multiply(r, a), ImageChops.multiply(g, a), ImageChops.multiply(b, a), a))


def premultiplied(im):
    """no colour brighter than its alpha (a premultiplied pixel can't be): DST blends (one, 1 - src alpha), so such a
    pixel adds light - a white speck"""
    from PIL import ImageChops
    r, g, b, a = im.split()
    from PIL import Image
    return Image.merge("RGBA", (ImageChops.darker(r, a), ImageChops.darker(g, a), ImageChops.darker(b, a), a))


def write(png, tex):
    from PIL import Image
    im = premultiply(Image.open(png).convert("RGBA"))
    levels = []
    w, h = im.size
    while True:
        # (the mipmaps: averaged (BOX) from the full size - LANCZOS rings past sharp edges, and its overshoot left
        #  colour where alpha is ~0: white specks round the font's letters at the size the game draws them,
        #  2026-10-16; the game's own fonts have none)
        level = premultiplied(im.resize((w, h), Image.BOX)) if (w, h) != im.size else im
        levels.append((w, h, _dxt5(level.transpose(Image.FLIP_TOP_BOTTOM))))
        if w == 1 and h == 1:
            break
        w, h = max(1, w // 2), max(1, h // 2)
    header = 0 | (DXT5 << 4) | (1 << 9) | (len(levels) << 13) | (3 << 18) | (0xFFF << 20)
    out = bytearray(b"KTEX" + struct.pack("<I", header))
    for w, h, data in levels:
        out += struct.pack("<HHHI", w, h, max(1, (w + 3) // 4) * 16, len(data))
    for _, _, data in levels:
        out += data
    open(tex, "wb").write(out)


def read(tex, png):
    """(a check) a DXT5 .tex's first mipmap back to a PNG (colours as stored: premultiplied)."""
    from PIL import Image
    b = open(tex, "rb").read()
    f, _ = info(tex)
    w, h, _, size = struct.unpack("<HHHI", b[8:18])
    off = 8 + 10 * f["mips"]
    im = Image.new("RGBA", (w, h))
    px = im.load()
    i = off
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            blk = b[i:i + 16]
            i += 16
            a0, a1 = blk[0], blk[1]
            abits = int.from_bytes(blk[2:8], "little")
            apal = [a0, a1] + ([((7 - k) * a0 + k * a1) // 7 for k in range(1, 7)] if a0 > a1 else
                               [((5 - k) * a0 + k * a1) // 5 for k in range(1, 5)] + [0, 255])
            c0, c1, cbits = struct.unpack("<HHI", blk[8:16])
            e0, e1 = _rgb(c0), _rgb(c1)
            cpal = [e0, e1, tuple((2 * x + y) // 3 for x, y in zip(e0, e1)), tuple((x + 2 * y) // 3 for x, y in zip(e0, e1))]
            for k in range(16):
                x, y = bx + k % 4, by + k // 4
                if x < w and y < h:
                    c = cpal[(cbits >> (2 * k)) & 3]
                    px[x, y] = (c[0], c[1], c[2], apal[(abits >> (3 * k)) & 7])
    im.transpose(Image.FLIP_TOP_BOTTOM).save(png)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "info":
        for p in sys.argv[2:]:
            print("\n".join(info(p)[1]))
    elif len(sys.argv) == 4 and sys.argv[1] == "read":
        read(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "write":
        write(sys.argv[2], sys.argv[3])
        print("\n".join(info(sys.argv[3])[1]))
    else:
        print(__doc__)
