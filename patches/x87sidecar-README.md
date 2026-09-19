# Patch for x87sidecar: bit-exact FSIN/FCOS

`x87sidecar-0002-exact-trig.patch` applies to
[athei/x87sidecar](https://github.com/athei/x87sidecar) at **v1.6.0** and adds
`X87_EXACT=1`, which makes FSIN and FCOS match real x87 bit for bit at almost
no cost.

## Why

BFME is a lockstep RTS: only inputs cross the network, every client re-derives
the same state, and one differing bit desynchronises the match. The JIT's
inline transcendentals disagree with real x87 on 63% of `fsin` and 70% of
`fcos` results. That was confirmed to break a real online game, and confirmed
fixed by running x87 on stock Rosetta instead.

## What x87 actually computes

Not undocumented microcode, which is what we assumed for a long time. It
reduces the argument using **pi rounded to 66 significant bits**, then rounds
the result correctly. Measured against a live reference over 2500 inputs:

| reduction constant | matches real x87 |
| --- | --- |
| pi to 53 bits | 60.9% |
| pi to 64 bits | 93.4% |
| **pi to 66 bits** | **100.0%** |
| pi to 80 bits | 98.7% |
| the host's libm | 95.4% |

So "make the transcendentals more accurate" is the wrong goal: correct rounding
against the *true* pi disagrees with x87 on ~5% of inputs and by up to 393 ulp
for large arguments.

## What the patch does

Keeps the existing shape -- reduce mod pi, sine series only, flip the sign on
an odd multiple, no quadrant branch, no cosine polynomial -- and changes two
things:

1. the reduction constant becomes the 66-bit pi (which needs only two doubles;
   the third term is exactly zero), and
2. the reduction and the series are carried in double-double.

The reduced argument and its square live in a 32-byte stack frame, because the
8-FPR pool cannot hold a double-double Horner otherwise. SP is a usable stack
inside a translated block.

## Measured

| | skirmish load | in-game | `fsin` | `fcos` |
| --- | --- | --- | --- | --- |
| stock v1.6.0 | 19.1 s | 38.5 fps | 63% differ | 70% differ |
| **this patch, `X87_EXACT=1`** | **23.2 s** | **38.3 fps** | **0%** | **0%** |
| JIT disabled entirely | 311.5 s | 33.8 fps | 0% | 0% |

Raw x87 throughput is unchanged: 55.9 against 54.9 Miter/s.

## Not done yet

- `fpatan` (29% differ) and `fyl2xp1` (43% differ) still use the fast path.
  BFME reaches both, so they still need doing. `fpatan` is straightforward in
  principle: correctly-rounded `atan2` matches x87 1200/1200, so it needs no
  special constant, just double-double evaluation. `fyl2xp1` is only 94% under
  correct rounding, so it needs x87's intermediate precision emulated as well.
- `f2xm1` (67% differ) is left alone deliberately: BFME never reaches it, and
  inside its defined domain of |x| <= 1 correct rounding already matches x87
  2999/3000.
- The exact path needs six free FPRs and falls back to the fast path below
  that. It did not trigger once in a full game load, but the fallback is
  silent correctness loss, so it should probably become a spill instead.

## On the double rounding

x87 computes into an 80-bit register and only then rounds to the 53 bits the
control word asks for. Collapsing a 106-bit double-double straight to 53
disagrees at near-ties -- one `fcos` input in 3000, where the true value sits
0.49992 through an ulp. The patch snaps the low half onto the 64-bit grid
first, which removes that case. Worth knowing if you touch the tail of the
sequence: an earlier attempt scaled the add-subtract rounding magic by the
exponent, which is wrong; the magic is a plain 1.5 * 2^52.

## Reproducing the measurements

`tools/x87check` in this repo: `x87diff.exe` plus `x87diff.py` for the
differential rate, and `x87exact-model.py` for the offline model the algorithm
was derived from.
