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

## Where each opcode stands

BFME reaches five of these, measured by logging every opcode the sidecar
translates during a real game: `fsin` 9 sites, `fcos` 7, `fpatan` 5,
`fyl2xp1` 4, `fldpi` 1. It never reaches `f2xm1`, `fyl2x`, `fptan`, `fprem`
or `fsincos`.

| opcode | sites | state |
| --- | --- | --- |
| `fsin` | 9 | **exact**, this patch |
| `fcos` | 7 | **exact**, this patch |
| `fpatan` | 5 | algorithm verified exact, emitter not written |
| `fyl2xp1` | 4 | see below -- cannot be recomputed |
| `fldpi` | 1 | not looked at |
| `f2xm1` | 0 | not reached by this game |

`fpatan` needs no special constant: x87 is correctly rounded there, confirmed
1200/1200. `tools/x87check/x87atan-model.py` in the bfme-macos repo has a
verified double-double scheme (2000/2000) designed to be emittable without
branches -- reciprocal fold as a min/max select, a 17-entry table of
atan(j/16), an 8-term series. It just needs writing as an emitter.

`fyl2xp1` is the awkward one. x87 is **not** correctly rounded for it: inside
its defined domain, for |x| between 1e-6 and 0.01, it sits 2 to 3 ulp off the
correctly-rounded value on 39% of inputs, while outside that band it is exact.
So it cannot be reproduced by computing it accurately -- it would need x87's
own algorithm. The natural answer is to route just that opcode to stock
Rosetta, which is affordable precisely because it is rare, but a first attempt
at a selective handoff did not work and was reverted. Note that the handoff
mechanism itself is sound once `cache.invalidate()` is added to the None path;
the difficulty is making it fire only for the chosen opcodes.

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
