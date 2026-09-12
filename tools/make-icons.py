#!/usr/bin/env python3
"""Build .icns files for the BFME apps from the installed Windows executables.

    make-icons.py <output-dir> [name=path ...]

Writes <name>.icns for each executable given, defaulting to the game, the Arena
and the All-in-One Launcher in the Wine prefix.

The artwork belongs to EA and to the Arena's authors, so it is extracted on the
machine that already has the games installed rather than shipped in this
repository. That means this has to run on a stock Mac: it uses only the Python
standard library plus sips and iconutil, both of which are part of macOS.
"""
import os
import struct
import subprocess
import sys
import tempfile

RT_ICON = 3

# The sizes iconutil expects, as (points, scale).
ICONSET = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
           (256, 1), (256, 2), (512, 1), (512, 2)]


class BadPE(Exception):
    pass


def _u16(b, o): return struct.unpack_from("<H", b, o)[0]
def _u32(b, o): return struct.unpack_from("<I", b, o)[0]
def _i32(b, o): return struct.unpack_from("<i", b, o)[0]


def _sections(data, pe_off):
    """Return [(virtual_addr, virtual_size, raw_ptr, raw_size)] for RVA mapping."""
    nsections = _u16(data, pe_off + 6)
    opt_size = _u16(data, pe_off + 20)
    table = pe_off + 24 + opt_size
    out = []
    for i in range(nsections):
        s = table + i * 40
        if s + 40 > len(data):
            raise BadPE("section table runs past the end of the file")
        out.append((_u32(data, s + 12), _u32(data, s + 8), _u32(data, s + 20), _u32(data, s + 16)))
    return out


def _rva_to_off(sections, rva):
    for va, vsize, ptr, rsize in sections:
        if va <= rva < va + max(vsize, rsize):
            return ptr + (rva - va)
    raise BadPE("resource at RVA 0x%x is not inside any section" % rva)


def _walk(data, base, off, depth, found):
    """Walk an IMAGE_RESOURCE_DIRECTORY tree, collecting leaves under RT_ICON."""
    if base + off + 16 > len(data):
        raise BadPE("resource directory runs past the end of the file")
    nnamed = _u16(data, base + off + 12)
    nid = _u16(data, base + off + 14)
    entries = base + off + 16
    for i in range(nnamed + nid):
        e = entries + i * 8
        name = _u32(data, e)
        child = _u32(data, e + 4)
        if depth == 0 and (name & 0x80000000 or name != RT_ICON):
            continue                      # only the RT_ICON branch matters
        if child & 0x80000000:
            _walk(data, base, child & 0x7FFFFFFF, depth + 1, found)
        else:
            found.append((_u32(data, base + child), _u32(data, base + child + 4)))


def extract_icons(path):
    """Return the RT_ICON payloads in a PE file, largest first."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:2] != b"MZ":
        raise BadPE("not a Windows executable (no MZ header)")
    pe_off = _u32(data, 0x3C)
    if data[pe_off:pe_off + 4] != b"PE\0\0":
        raise BadPE("not a Windows executable (no PE header)")

    opt = pe_off + 24
    magic = _u16(data, opt)
    # The data directory sits after the optional header, whose size differs
    # between PE32 (96 bytes) and PE32+ (112).
    ddir = opt + (112 if magic == 0x20B else 96)
    res_rva = _u32(data, ddir + 2 * 8)
    if not res_rva:
        return []

    sections = _sections(data, pe_off)
    base = _rva_to_off(sections, res_rva)
    leaves = []
    _walk(data, base, 0, 0, leaves)

    blobs = []
    for rva, size in leaves:
        off = _rva_to_off(sections, rva)
        if off + size > len(data):
            raise BadPE("icon data runs past the end of the file")
        blobs.append(data[off:off + size])
    return sorted(blobs, key=len, reverse=True)


def to_png(blob, dest):
    """Write an RT_ICON payload out as a PNG, via sips."""
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        with open(dest, "wb") as fh:      # already a PNG (Vista-era icons)
            fh.write(blob)
        return

    # Otherwise it is a headerless DIB. Wrap it back into a single-image .ico so
    # that ImageIO, which sips is built on, decodes the colour and mask planes.
    width, height, bitcount = _i32(blob, 4), _i32(blob, 8), _u16(blob, 14)
    height //= 2                          # a DIB icon stacks colour over mask
    if not (0 < width <= 256 and 0 < height <= 256):
        raise BadPE("implausible icon dimensions %dx%d" % (width, height))
    ico = struct.pack("<HHH", 0, 1, 1)
    ico += struct.pack("<BBBBHHII", width & 0xFF, height & 0xFF, 0, 0,
                       1, bitcount, len(blob), 22) + blob

    with tempfile.NamedTemporaryFile(suffix=".ico", delete=False) as fh:
        fh.write(ico)
        tmp = fh.name
    try:
        subprocess.run(["sips", "-s", "format", "png", tmp, "--out", dest],
                       check=True, capture_output=True)
    finally:
        os.unlink(tmp)


def build_icns(png, dest):
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "icon.iconset")
        os.makedirs(iconset)
        for size, scale in ICONSET:
            px = size * scale
            name = "icon_%dx%d%s.png" % (size, size, "@2x" if scale == 2 else "")
            out = os.path.join(iconset, name)
            subprocess.run(["sips", "-z", str(px), str(px), png, "--out", out],
                           check=True, capture_output=True)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", dest],
                       check=True, capture_output=True)


def default_sources():
    prefix = os.environ.get("BFME_PREFIX_DIR") or os.path.expanduser("~/.wine-aio-custom")
    roaming = "%s/drive_c/users/%s/AppData/Roaming" % (prefix, os.environ.get("USER", ""))
    return [
        ("game", "%s/drive_c/BFME1/lotrbfme.exe" % prefix),
        ("arena", "%s/BFME Competetive Arena/BfmeFoundationProject_OnlineArena.exe" % roaming),
        ("launcher", "%s/BFME All In One Launcher/AllInOneLauncher.exe" % roaming),
    ]


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: make-icons.py <output-dir> [name=path ...]")
    outdir = sys.argv[1]
    sources = [tuple(a.split("=", 1)) for a in sys.argv[2:]] or default_sources()
    os.makedirs(outdir, exist_ok=True)

    made = failed = 0
    for name, path in sources:
        if not os.path.exists(path):
            print("  %s: not installed, no icon" % name)
            continue
        try:
            blobs = extract_icons(path)
            if not blobs:
                raise BadPE("the executable has no icon resource")
            png = os.path.join(outdir, name + ".png")
            to_png(blobs[0], png)
            dest = os.path.join(outdir, name + ".icns")
            build_icns(png, dest)
            os.unlink(png)
            print("  %s: %s" % (name, dest))
            made += 1
        except Exception as exc:
            # Loud, but not fatal: an app with no icon still launches the game.
            print("  %s: could not build an icon: %s" % (name, exc), file=sys.stderr)
            failed += 1

    if failed and not made:
        sys.exit("no icons could be built")


if __name__ == "__main__":
    main()
