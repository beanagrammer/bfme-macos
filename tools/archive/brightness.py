#!/usr/bin/env python3
"""Mean brightness + bright-pixel fraction of an image, via sips -> BMP (no deps)."""
import subprocess, sys, struct, tempfile, os

def stats(path, width=64):
    with tempfile.TemporaryDirectory() as d:
        bmp = os.path.join(d, "t.bmp")
        r = subprocess.run(["sips", "-s", "format", "bmp", "-Z", str(width), path, "--out", bmp],
                           capture_output=True)
        if r.returncode != 0 or not os.path.exists(bmp):
            return None
        b = open(bmp, "rb").read()
    off = struct.unpack_from("<I", b, 10)[0]
    w   = struct.unpack_from("<i", b, 18)[0]
    h   = struct.unpack_from("<i", b, 22)[0]
    bpp = struct.unpack_from("<H", b, 28)[0]
    if bpp not in (24, 32):
        return None
    px = bpp // 8
    rowsize = ((bpp * w + 31) // 32) * 4
    tot = 0; n = 0; bright = 0
    for y in range(abs(h)):
        base = off + y * rowsize
        for x in range(w):
            i = base + x * px
            if i + 2 >= len(b): continue
            lum = (b[i] * 114 + b[i+1] * 587 + b[i+2] * 299) // 1000
            tot += lum; n += 1
            if lum > 40: bright += 1
    if not n: return None
    return tot / n, bright / n

if __name__ == "__main__":
    for p in sys.argv[1:]:
        s = stats(p)
        print(f"{p}: " + ("unreadable" if s is None else f"mean={s[0]:.1f} bright_frac={s[1]:.3f}"))
