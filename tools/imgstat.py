#!/usr/bin/env python3
"""Image stats + similarity, via sips -> BMP (no third-party deps).

  imgstat.py stats  <img>            -> "mean=<f> frac=<f>"
  imgstat.py diff   <ref> <img>      -> "diff=<f>"   (mean abs grayscale difference, 0-255)
"""
import subprocess, sys, struct, tempfile, os

def grid(path, width=32, height=18):
    # force an exact WxH grid: -Z preserves aspect, which makes captures of different
    # shapes produce different-length vectors and breaks diff comparisons.
    with tempfile.TemporaryDirectory() as d:
        bmp = os.path.join(d, "t.bmp")
        r = subprocess.run(["sips", "-s", "format", "bmp",
                            "--resampleHeightWidth", str(height), str(width),
                            path, "--out", bmp], capture_output=True)
        if r.returncode != 0 or not os.path.exists(bmp):
            return None
        b = open(bmp, "rb").read()
    off = struct.unpack_from("<I", b, 10)[0]
    w   = struct.unpack_from("<i", b, 18)[0]
    h   = abs(struct.unpack_from("<i", b, 22)[0])
    bpp = struct.unpack_from("<H", b, 28)[0]
    if bpp not in (24, 32): return None
    px = bpp // 8
    rowsize = ((bpp * w + 31) // 32) * 4
    out = []
    for y in range(h):
        base = off + y * rowsize
        for x in range(w):
            i = base + x * px
            if i + 2 >= len(b): out.append(0); continue
            out.append((b[i]*114 + b[i+1]*587 + b[i+2]*299)//1000)
    return out

def main():
    mode = sys.argv[1]
    if mode == "stats":
        g = grid(sys.argv[2])
        if not g: print("mean=-1 frac=-1"); return
        print("mean=%.1f frac=%.3f" % (sum(g)/len(g), sum(1 for v in g if v > 40)/len(g)))
    elif mode == "diff":
        a, b = grid(sys.argv[2]), grid(sys.argv[3])
        if not a or not b or len(a) != len(b): print("diff=-1"); return
        print("diff=%.1f" % (sum(abs(x-y) for x, y in zip(a, b))/len(a)))

main()
