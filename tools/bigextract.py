#!/usr/bin/env python3
"""Extract one file from a SAGE .big archive (BIGF/BIG4 format)."""
import struct, sys
def entries(path):
    d=open(path,'rb').read()
    magic=d[:4]
    if magic not in (b'BIGF', b'BIG4'): raise SystemExit(f"not a big: {magic!r}")
    count, = struct.unpack('>I', d[8:12])
    pos=16; out=[]
    for _ in range(count):
        off,size = struct.unpack('>II', d[pos:pos+8]); pos+=8
        e=d.index(b'\0',pos); name=d[pos:e].decode('latin1'); pos=e+1
        out.append((name,off,size))
    return d,out
if __name__=='__main__':
    arc, want = sys.argv[1], sys.argv[2].lower()
    d,es = entries(arc)
    for name,off,size in es:
        if want in name.lower():
            sys.stderr.write(f"{name}  ({size} bytes)\n")
            sys.stdout.buffer.write(d[off:off+size]); break
