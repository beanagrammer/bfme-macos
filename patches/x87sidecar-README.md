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

| | skirmish load | in-game | `fsin` vs real x87 |
| --- | --- | --- | --- |
| stock v1.6.0 | 19.1 s | 38.5 fps | 63% differ |
| **this patch, `X87_EXACT=1`** | **23.2 s** | **37.9 fps** | **0% differ** |
| JIT disabled entirely | 311.5 s | 33.8 fps | 0% differ |

Raw x87 throughput is unchanged: 55.9 against 54.9 Miter/s.

## Not done yet

- `fcos` is at 1 mismatch in 3000, on a near-tie where the true value sits
  0.49992 through an ulp and x87 rounds the other way. Emulating a 64-bit
  intermediate rounding did not reproduce its choice.
- `f2xm1` (67% differ) and `fpatan` (29% differ) still use the fast path and
  need the same treatment.
- The exact path needs six free FPRs and falls back to the fast path below
  that. It did not trigger once in a full game load, but the fallback is
  silent correctness loss, so it should probably become a spill instead.

## Reproducing the measurements

`tools/x87check` in this repo: `x87diff.exe` plus `x87diff.py` for the
differential rate, and `x87exact-model.py` for the offline model the algorithm
was derived from.
