# x87 JIT checks

Two different questions, two different programs.

## `x87bench.exe` — is the JIT running at all?

A 32-bit x86 loop of mixed integer and x87 floating point, built from
`x87bench.c`. It takes an iteration count so it can be run short.

It exists because the x87 JIT fails **silently**: the sidecar process starts, its
`--probe` passes, boot times look roughly normal, and everything simply runs at
Rosetta's software-x87 speed. The only way to know is to measure.

Expect roughly a 9x difference on an M2:

```sh
bfme run tools/x87check/x87bench.exe 30000000      # ~70 Miter/s with the JIT
BFME_NO_X87=1 bfme run tools/x87check/x87bench.exe 30000000   # ~7.5 without
```

`bfme doctor` runs this, and `dist/package-wine.sh` refuses to ship a bundle that
fails it.

## `x87exact.exe` — does the JIT compute the *same bits*?

Speed is not the only thing that matters. BFME is a lockstep simulation: every
client runs the same physics from the same inputs and only the inputs travel
over the network, so one differing bit anywhere desynchronises the match. That
makes bit-exactness with real x87 a correctness requirement for online play.

`x87exact.exe` runs the x87 instruction set over fixed inputs at each of the
three precision-control settings and prints every result as a raw bit pattern,
including raw 80-bit stores and a chaotic iteration that compounds small
differences. Diff two runs:

```sh
bfme run tools/x87check/x87exact.exe            > with-jit.txt
BFME_NO_X87=1 bfme run tools/x87check/x87exact.exe > without-jit.txt
diff with-jit.txt without-jit.txt
```

Rosetta's own emulation is the reference: it reproduces the documented Intel
constants exactly (`fldpi` gives `4000C90FDAA22168C235`), and it is what every
other x86 program on the Mac already runs on.

### What it currently reports

A Windows process starts with control word `0x027F`, 53-bit precision, and
`cwstart.exe` confirms Wine hands out the same value. That matters: at `0x027F`
the JIT is bit-exact for everything except the list below, while at `0x037F`
every divide and square root would be wrong too.

| Diverges | Exact |
| --- | --- |
| `fsin` `fcos` `fsincos` | `fadd` `fsub` `fmul` `fdiv` |
| `f2xm1` `fyl2x` `fpatan` | `fsqrt` `frndint` |
| `fprem` | `fabs` `fchs` `fscale` |
| `fldpi` `fldln2` (and the other irrational constants) | `fld1` `fldz` |

So the arithmetic is fine and the transcendentals are not. The JIT computes them
through doubles and is off by one unit in the last place; it also ignores the
precision-control field entirely, which is invisible at `0x027F` but shows up at
`0x037F` and `0x003F`.

### Why this is not simply fixed with `X87_STOCK_OPS`

The sidecar has exactly the right knob for this — `X87_STOCK_OPS=fsin,fcos,...`
hands every block containing those opcodes to stock Rosetta and JITs the rest,
which costs nothing measurable on `x87bench` and makes `x87exact` bit-exact.

It only works while the x87 register stack is empty at the handoff. When the
compiler is keeping live doubles in `st(n)` across the block, which is the normal
state of optimised 32-bit code, the handoff returns garbage. `stockops-bug.c` is
a minimal reproducer for reporting upstream. Until that is fixed, the knob cannot
be turned on.
