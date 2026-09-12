import struct, math, sys
from fractions import Fraction as F
S = sys.argv[1]

def bits(d): return struct.unpack('<Q', struct.pack('<d', d))[0]
def tod(h): return struct.unpack('<d', struct.pack('<Q', int(h,16)))[0]

try:
    fma = math.fma
except AttributeError:
    def fma(a, b, c): return float(F(a)*F(b) + F(c))

inv_pi = float.fromhex('0x1.45f306dc9c883p-2')
pi_1 = math.pi
pi_2 = float.fromhex('0x1.1a62633145c06p-53')
pi_3 = float.fromhex('0x1.c1cd129024e09p-106')
c = [float.fromhex(h) for h in (
    '-0x1.555555555547bp-3','0x1.1111111108a4dp-7','-0x1.a01a019936f27p-13',
    '0x1.71de37a97d93ep-19','-0x1.ae633919987c6p-26','0x1.60e277ae07cecp-33',
    '-0x1.9e9540300a1p-41')]

def rint_ties_away(v):
    return math.floor(v + 0.5) if v >= 0 else math.ceil(v - 0.5)

def jit_sin(x):
    n = float(rint_ties_away(x * inv_pi)); qn = int(n)
    r = fma(-n, pi_1, x); r = fma(-n, pi_2, r); r = fma(-n, pi_3, r)
    r2 = r*r; r4 = r2*r2
    p01 = fma(r2, c[1], c[0]); p23 = fma(r2, c[3], c[2]); p45 = fma(r2, c[5], c[4])
    p46 = fma(r4, c[6], p45); p26 = fma(r4, p46, p23); p06 = fma(r4, p26, p01)
    y = fma(r2*r, p06, r)
    return -y if (qn & 1) else y

rows = [l.split() for l in open(f"{S}/d-jit.txt", errors="replace")]
rows = [f for f in rows if len(f)==3 and f[0]=="fsin" and len(f[1])==16]
ok = sum(1 for f in rows[:4000] if bits(jit_sin(tod(f[1]))) == int(f[2],16))
print(f"model reproduces the real JIT on {ok}/4000 sampled fsin cases")

def exact_same_coeffs(x):
    n = rint_ties_away(x * inv_pi)
    r = F(x) - F(n)*(F(pi_1)+F(pi_2)+F(pi_3))
    r2 = r*r
    P = F(0)
    for k in range(6, -1, -1): P = P*r2 + F(c[k])
    y = r + r*r2*P
    return -float(y) if (n & 1) else float(y)

small = [tod(f[1]) for f in rows if abs(tod(f[1])) < 0.7854][:3000]
bad_jit  = sum(1 for x in small if bits(jit_sin(x))         != bits(math.sin(x)))
bad_eval = sum(1 for x in small if bits(exact_same_coeffs(x)) != bits(math.sin(x)))
print()
print(f"|x| < pi/4, {len(small)} cases:")
print(f"  JIT as emitted                      : {bad_jit:>5} differ from correctly rounded")
print(f"  same coefficients, exact arithmetic : {bad_eval:>5} differ")
print()
if bad_eval > len(small)//20:
    print("=> the COEFFICIENTS are the limit: better ones would fix it")
else:
    print("=> the EVALUATION rounding is the limit: the coefficients are fine")
