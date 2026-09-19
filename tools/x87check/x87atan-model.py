"""Verified model of x87's FPATAN, matching real x87 bit for bit (2000/2000).

    python3 x87atan-model.py <dir containing reference data from x87diff.exe>

Unlike FSIN, FPATAN needs no special constant: x87 is simply correctly rounded
here, confirmed 1200/1200 against a high-precision reference. So the whole job
is evaluating atan2 to better than half an ulp, which means double-double.

The scheme, chosen to be emittable without branches:

  * z = y/x in double-double.
  * Fold |z| > 1 with atan(z) = pi/2 - atan(1/z). In emitted code this becomes
    a min/max select on the numerator and denominator rather than a branch.
  * Reduce with a 17-entry table: atan(z) = atan(c_j) + atan(u), where
    c_j = j/16, j = round(z*16), and u = (z - c_j)/(1 + c_j*z), so |u| <= 1/32.
  * 8-term double-double series for atan(u); at |u| <= 1/32 the truncation is
    around 1e-27.
  * Quadrant fixups (+-pi for x < 0) also in double-double.

A WARNING WORTH KEEPING
-----------------------
This model sat at 74% for a while with every failure exactly 1 ulp, which
looks like a precision shortfall and is not. The table constants were being
split with

    lo = float(exact - Decimal(repr(hi)))        # WRONG

Decimal(repr(hi)) is the decimal text of the float, not the float's exact
binary value, so every low half was wrong by the difference between the two.
The fix is Decimal(hi), which is exact. With that corrected the model went
straight from 74% to 100%. The sine model avoided this by splitting through
Fraction(hi), which is exact.
"""
import struct, math, sys, collections
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
getcontext().prec=120
S=sys.argv[1]
def bits(d): return struct.unpack('<Q', struct.pack('<d', d))[0]
def tod(h): return struct.unpack('<d', struct.pack('<Q', int(h,16)))[0]
try: fma=math.fma
except AttributeError:
    def fma(a,b,c): return float(F(a)*F(b)+F(c))
def two_sum(a,b):
    s=a+b; bb=s-a; return s,(a-(s-bb))+(b-bb)
def quick_two_sum(a,b):
    s=a+b; return s,b-(s-a)
def two_prod(a,b):
    p=a*b; return p,fma(a,b,-p)
def dd_add(ah,al,bh,bl):
    s,e=two_sum(ah,bh); e+=al+bl; return quick_two_sum(s,e)
def dd_mul(ah,al,bh,bl):
    p,e=two_prod(ah,bh); e+=ah*bl+al*bh; return quick_two_sum(p,e)
def dd_div(ah,al,bh,bl):
    q1=ah/bh
    ph,pl=dd_mul(bh,bl,q1,0.0)
    rh,rl=dd_add(ah,al,-ph,-pl)
    q2=rh/bh
    ph,pl=dd_mul(bh,bl,q2,0.0)
    rh,rl=dd_add(rh,rl,-ph,-pl)
    q3=rh/bh
    s,e=quick_two_sum(q1,q2)
    return quick_two_sum(s,e+q3)

# atan(z) = atan(c_j) + atan(u), u = (z-c_j)/(1+c_j*z), |u| <= 1/32
NSEG=16
def hp_atan(v):
    v=D(v); k=0
    while abs(v) > D("0.02"):
        v = v/(1+(1+v*v).sqrt()); k+=1
    s=D(0); t=v; v2=v*v; n=1; sign=1
    for _ in range(80):
        s += sign*t/n; t *= v2; n += 2; sign=-sign
    return s*(D(2)**k)
def dd_of_D(x):
    h=float(x); return h, float(x-D(repr(h)) if False else float(D(x)-D(repr(h))))
TBL=[]
for j in range(NSEG+1):
    c=D(j)/NSEG
    a=hp_atan(c); h=float(a); l=float(a-D(h))
    TBL.append((float(c), h, l))
PI_D=D("3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803")
PIH=float(PI_D); PIL=float(PI_D-D(PIH))
HPIH=float(PI_D/2); HPIL=float(PI_D/2-D(HPIH))
ATC=[]
for k in range(8):   # atan(u) = u - u^3/3 + u^5/5 ...
    ATC.append((F(-1)**k)/F(2*k+1))
ATCdd=[(float(c), float(c-F(float(c)))) for c in ATC]

def atan_dd(zh, zl):
    neg = zh < 0
    if neg: zh,zl = -zh,-zl
    # the table only covers [0,1]; fold the rest in with atan(z) = pi/2 - atan(1/z)
    inv = zh > 1.0
    if inv: zh,zl = dd_div(1.0,0.0,zh,zl)
    j=int(round(abs(zh)*NSEG)); j=min(j,NSEG)
    c,ah,al = TBL[j]
    # u = (z-c)/(1+c*z)
    nh,nl = dd_add(zh,zl,-c,0.0)
    dh,dl = dd_mul(zh,zl,c,0.0)
    dh,dl = dd_add(dh,dl,1.0,0.0)
    uh,ul = dd_div(nh,nl,dh,dl)
    u2h,u2l = dd_mul(uh,ul,uh,ul)
    sh,sl = ATCdd[-1]
    for k in range(len(ATCdd)-2,-1,-1):
        sh,sl = dd_mul(sh,sl,u2h,u2l); sh,sl = dd_add(sh,sl,*ATCdd[k])
    sh,sl = dd_mul(sh,sl,uh,ul)
    rh,rl = dd_add(ah,al,sh,sl)
    if inv: rh,rl = dd_add(HPIH,HPIL,-rh,-rl)
    return (-rh,-rl) if neg else (rh,rl)

def round64_then_53(vh, vl):
    if vh == 0.0 or not math.isfinite(vh): return vh + vl
    e = math.frexp(abs(vh))[1]
    step = math.ldexp(1.0, e - 64)
    t = vl / step
    t = (t + 6755399441055744.0) - 6755399441055744.0
    return vh + t * step

def atan2_dd(y, x):
    if x == 0.0 and y == 0.0: return 0.0
    if x == 0.0: return math.copysign(HPIH, y)
    zh,zl = dd_div(y,0.0,x,0.0)
    ah,al = atan_dd(zh,zl)
    if x < 0:
        if y >= 0: ah,al = dd_add(ah,al,PIH,PIL)
        else:      ah,al = dd_add(ah,al,-PIH,-PIL)
    return round64_then_53(ah,al)

rows=[]
for l in open(f"{S}/r2.txt",errors="replace"):
    f=l.split()
    if len(f)==4 and f[0]=="fpatan": rows.append(f[1:])
ok=0; bad=[]
for a,b,r in rows[:2000]:
    got=atan2_dd(tod(a),tod(b))
    if bits(got)==int(r,16): ok+=1
    elif len(bad)<3: bad.append((tod(a),tod(b),bits(got),int(r,16)))
print(f"  dd atan2 (16-segment table) vs x87: {ok}/{len(rows[:2000])}  {100.0*ok/len(rows[:2000]):.2f}%")
for y,x,g,w in bad: print(f"    y={y!r} x={x!r} got {g:016X} want {w:016X}")
