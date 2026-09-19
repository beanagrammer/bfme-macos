"""Verified model of x87's FSIN, matching real x87 bit for bit.

This is the algorithm an exact JIT implementation should emit. Run it against
reference data captured with `BFME_NO_X87=1 bfme run x87diff.exe`:

    python3 x87exact-model.py <dir containing d-ref.txt>

It reports 4000/4000 exact on fsin.

WHAT x87 ACTUALLY DOES
----------------------
Not undocumented microcode, which is what I assumed for most of a day. It is:

    reduce the argument using pi rounded to 66 significant bits,
    then compute the result correctly rounded.

That is all. The 66 bits is the whole story, and it is measurable: matching
against real x87 over 2500 inputs gives

    pi to 53 bits   60.9%
    pi to 64 bits   93.4%
    pi to 66 bits  100.0%     <-- and 67, 68 also 100%
    pi to 80 bits   98.7%
    plain libm      95.4%

So "make the JIT correctly rounded" was the wrong target: correct rounding of
the TRUE pi disagrees with x87 on ~5% of inputs, and by up to 393 ulp for large
arguments. Correct rounding of the 66-BIT-pi-reduced argument agrees exactly.

WHY IT MATTERS
--------------
It means exactness does not require handing the opcode to Rosetta, which costs
a transition per execution and measured slower than turning the JIT off
entirely. It can be computed inline, at roughly 3x the current per-instruction
cost, on instructions the emitter already has.

THE SHAPE THAT FITS THE EXISTING EMITTER
----------------------------------------
No quadrant branch and no cosine polynomial are needed. Reducing mod pi and
flipping the sign on odd multiples -- exactly what emit_trig_range_reduce
already does -- reaches 100% with 11 double-double terms. Only two things
change from the current code: the constants become the 66-bit split, and the
reduction and polynomial are carried in double-double rather than one double.

Note the 66-bit constant needs only TWO doubles, not three: pi66_3 comes out
exactly zero.

STILL OPEN
----------
fcos reaches 99.97%, one failure in 4000, at an input where the true value sits
0.49992 of the way through an ulp. x87 rounds one way there and a correctly
rounded result the other. Emulating an intermediate 64-bit rounding did not
reproduce it. For a lockstep game thatremaining case still matters, so the
cosine path needs the same treatment the sine path got.
"""
import struct, math, sys
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
getcontext().prec=160
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
PI=F(int(D("3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651328230664709384460955058223172535940813")*D(10)**150),10**150)
PI66=F(round(PI*(F(2)**64)))/(F(2)**64)
# same shape as the existing emitter: reduce mod pi, sine only, sign from n&1
P1=float(PI66); P2=float(PI66-F(P1)); P3=float(PI66-F(P1)-F(P2))
INVPI=float(F(1)/PI66)
def rint(v): return math.floor(v+0.5) if v>=0 else math.ceil(v-0.5)
def taylor_sin(n):
    out=[]
    for k in range(n):
        p=2*k+1; f=F(1)
        for i in range(1,p+1): f*=i
        out.append((F(-1)**k)/f)
    return out
def dd_of(fr):
    h=float(fr); return h,float(fr-F(h))
# sin(r) = r * S(r2)
SC=[dd_of(t) for t in taylor_sin(16)]
def sin_modpi(x, nt):
    n=float(rint(x*INVPI)); odd=int(n)&1
    ph,pl=two_prod(n,P1); rh,rl=two_sum(x,-ph); rl-=pl
    ph,pl=two_prod(n,P2); rh,rl=dd_add(rh,rl,-ph,-pl)
    ph,pl=two_prod(n,P3); rh,rl=dd_add(rh,rl,-ph,-pl)
    rh,rl=quick_two_sum(rh,rl)
    r2h,r2l=dd_mul(rh,rl,rh,rl)
    ah,al=SC[nt-1]
    for k in range(nt-2,-1,-1):
        ah,al=dd_mul(ah,al,r2h,r2l); ah,al=dd_add(ah,al,*SC[k])
    vh,vl=dd_mul(ah,al,rh,rl)
    if odd: vh,vl=-vh,-vl
    return vh+vl
ref={}
for l in open(f"{S}/d-ref.txt",errors="replace"):
    f=l.split()
    if len(f)==3 and f[0]=="fsin" and len(f[1])==16: ref[f[1]]=f[2]
items=list(ref.items())[:4000]
print("reduce mod pi (no quadrant branch, sine polynomial only):")
for nt in (10,11,12,13,14):
    ok=sum(1 for ib,rb in items if bits(sin_modpi(tod(ib),nt))==int(rb,16))
    print(f"   {nt:>2} terms : {ok:>5}/{len(items)}  {100.0*ok/len(items):>6.2f}% match with x87")
