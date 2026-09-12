# Upstream report, ready to file: x87sidecar transcendentals are not correctly rounded

For [athei/x87sidecar](https://github.com/athei/x87sidecar). Not yet filed; it
would go under the reporter's own GitHub identity, so it needs a human to post.

---

**Title:** Inline transcendentals are ~1 ulp off, which desynchronises lockstep
games against players on real x86

**Version:** v1.6.0, and master at 010f50a. macOS 27, M2 Max, Wine 11.17 new-WoW64.

## What happens

The inline transcendentals do not produce the correctly-rounded double, while
stock Rosetta's emulation does. Sampling `fsin` over ten inputs at control word
`0x027F`:

| | matches the correctly-rounded double |
| --- | --- |
| stock Rosetta (`X87_ALWAYS_NONE=1`) | 10 / 10 |
| x87sidecar | 3 / 10 |

The same holds for `fcos`, `f2xm1`, `fyl2x`, `fpatan` and `fprem`. The irrational
constant loads `fldpi` and `fldln2` lose their low mantissa bits. Add, subtract,
multiply, divide, `fsqrt`, `frndint`, `fabs`, `fchs` and `fscale` are all exact.

## Measured disagreement rate

`x87diff.exe` sweeps 40,000 pseudorandom game-shaped inputs per opcode at control
word `0x027F` and prints every result, so two runs can be diffed exactly.
`fsqrt` is the control: it is expected to agree, and does.

| opcode | cases | differ | rate |
| --- | --- | --- | --- |
| `fsin` | 40000 | 25175 | 62.9% |
| `fcos` | 40000 | 27997 | 70.0% |
| `fsqrt` | 40000 | 0 | **0.0%** |
| `f2xm1` | 40000 | 26771 | 66.9% |
| `fpatan` | 40000 | 12317 | 30.8% |

Errors are mostly one or two ulp in both directions; `f2xm1` has a large cluster
at three or more. This is not a rare edge case: about two in three sine and
cosine results differ from what an x86 player computes.

## Why it is worth fixing

A Windows process runs x87 at `0x027F`, 53-bit precision, and Wine hands out the
same value. Intel computes internally to roughly 68 bits and rounds to 53, so at
that setting Intel's result *is* the correctly-rounded double. That makes this a
well-defined target rather than an attempt to replicate undocumented hardware:
correctly rounded is the answer x86 players compute.

It matters for lockstep simulations, where only inputs cross the network and
every client re-derives the same state. One differing bit desynchronises the
match. A 20,000-iteration rotate-and-normalise loop, the shape of RTS unit
movement, already lands on a different double.

The cause looks like the accuracy budget rather than a bug: a degree-7 minimax
polynomial with three-step Cody-Waite reduction lands about a ulp out, in both
directions, which is the expected quality for that construction.

## Reproducer

`x87exact.exe` runs the x87 set over fixed inputs at all three precision-control
settings and prints raw bit patterns. Diff a normal run against
`X87_ALWAYS_NONE=1`. Source and binary: `tools/x87check/x87exact.c`.

## What a user cannot work around

`X87_STOCK_OPS=fsin,fcos,...` is the natural workaround and is itself broken: it
short-circuits the translate request and replies None without entering the
translator, leaving deferred stack state that already-emitted code still owes.
Results come back as garbage rather than imprecise. Minimal reproducer:
`tools/x87check/stockops-bug.c`. It is only correct when the x87 register stack
happens to be empty, i.e. `-O0` builds. No combination of `X87_ENABLE_BRIDGE=0`,
`X87_DISABLE_CACHE=1`, `X87_DISABLE_X87_IR=1`, `X87_DISABLE_ALL_FUSIONS=1`,
`X87_DISABLE_DEFERRED_FXCH=1` or `X87_DISABLE_SINGLE_FAST=1` avoids it.

Routing those opcodes through the mechanism that works for
`fclex`/`fldenv`/`fxsave` -- refusing them in `is_handled_x87` and returning
`std::nullopt` from the dispatch -- does not work either. The refused
instructions then never execute: `fsin` leaves its input on the stack and the
test loop returns NaN. This matches the warning in `X87Cache.cpp` about stock's
`{x22, w23}` helper-call ABI. `w23` appears nowhere else in the tree, so an
outside contributor cannot tell what stock expects there.

## Two things I tried, so you do not have to

**A host call is not available.** I added an AAPCS call from the emitted code to
a libm helper: a 704-byte SP frame saving x0-x18, x30 and all 32 vector
registers in full, then `BLR`. It fails with

```
rosetta error: no code fragment associated with the given arm pc
```

Bisected: emitting the entire frame, the saves, the argument spills and the
restores works perfectly, and the program runs to completion. Adding only the
`BLR` produces the error. So SP *is* a valid, usable stack inside a translated
block, and the register traffic is fine; Rosetta simply refuses control flow
leaving the fragment to an address it does not know. That rules out routing
these opcodes through the host's libm from outside the project, and explains why
there is no host-call infrastructure in the tree.

**The range reduction is not where the error comes from.** My first guess was
that the reduced argument being rounded to a single double was the culprit,
since d(sin)/dr is about 1 and that rounding is the same size as the observed
error. I extended `emit_trig_range_reduce` to keep the residual as a
double-double, using an exact product error via FMSUB plus a two-sum on the
final `n*pi3` step, and folded the low half into the correction term before the
last rounding:

```
corr = fma(r3, p06, r_lo);   y = r_hi + corr
```

That moved `fsin` from 62.80% differing to 63.00%, i.e. nowhere. The dominant
error is the polynomial evaluation itself, so a fix needs the Estrin chain
carried in double-double too, not just the reduction.

## Where the error actually is

I built a bit-exact offline model of the emitted `fsin` (it reproduces a real
run on 4000/4000 sampled inputs; `tools/x87check/sinmodel.py`) and bisected:

| variant | disagreement with real x87 |
| --- | --- |
| as shipped | 63.5% |
| same coefficients, exact arithmetic | unchanged |
| coefficients refit over [0, pi/4] | 49% -> 1.8% *for `\|x\| < pi/4` only* |
| coefficients refit over [0, pi/2], degree 6 | 47.1% |
| **degree 7, refit over [0, pi/2]** | **14.1%** |
| degree 8, degree 9 | 15.0%, 14.9% (no better) |
| degree 7 + exact reduction | 14.1% |
| degree 7 + exact reduction + double-double `r` | 13.1% |

Two things fall out. The coefficients are fitted over `[0, pi/4]` but the
reduction uses `1/pi`, so the reduced argument actually spans `[-pi/2, pi/2]`;
refitting over the range that is really used, plus one more term, is worth
63.5% -> 14.1% and costs one FMA.

After that it stops, and neither a better polynomial nor a better reduction
moves it. The floor is the rounding of the correction term `r^3 * P`: near
`pi/2` that term is 36% of the result, so its own rounding lands directly in the
last place. Reducing to `[-pi/4, pi/4]` with a quadrant-selected sin/cos pair
would make it 8%, and a compensated final combination would take care of the
rest. That is the standard scalar-libm structure, and it looks like what this
needs.

Worth saying plainly: for a lockstep game a partial improvement is worth
nothing. 14% desynchronises as reliably as 63%. It is exact or it is unusable,
which is why I have not sent you a coefficients patch.

## Correction: "correctly rounded" is the wrong target

Everything above measures the JIT against the correctly-rounded double, on the
reasoning that Intel computes to ~68 bits and rounds to 53. Measured over 4,000
inputs, that reasoning is wrong: stock Rosetta's x87 differs from the
correctly-rounded result too.

| range | x87 differs from correctly rounded | worst gap |
| --- | --- | --- |
| `\|x\| < pi/4` | 1.8% | 1 ulp |
| `pi/4 .. pi` | 5.4% | 2 ulp |
| `pi .. 4pi` | 4.3% | 1 ulp |
| `4pi .. 200` | 4.0% | 1 ulp |
| `> 200` | 14.1% | **393 ulp** |

The blow-up at large arguments is the known x87 behaviour: its reduction uses a
66-bit approximation of pi, so it loses precision where a full Payne-Hanek
reduction would not. Rosetta reproduces that faithfully, which is exactly what
an emulator should do.

The consequence for anyone trying to match x87: you cannot get there by being
more accurate. A correctly-rounded implementation disagrees with x87 on about
5% of inputs and by hundreds of ulp on large ones. Matching means reproducing
x87's own reduction constant and its own polynomial, i.e. reimplementing
undocumented microcode, and "nearly" is worth nothing to a lockstep game.

So this report is no longer a request to make the transcendentals
correctly rounded. If anything is worth doing upstream it is the narrower
`X87_STOCK_OPS` fix below, which would let a caller pay for exactness only on
the opcodes that need it, without giving up the JIT everywhere.

## What would help

Any one of:

1. A correctly-rounded mode for the transcendentals, opt-in, accepting the speed
   cost. On our workload the transcendentals are rare -- 26 instruction sites out
   of 13,728 translated in a game session -- so even a slow path for them would
   cost little.
2. Fixing `X87_STOCK_OPS` so the documented per-opcode exclusion works.
3. Documenting what `w23` must hold, so the `is_handled_x87` route can be
   completed outside the project.

## Unrelated observation

master at 010f50a is about 1.6x slower than v1.6.0 on an x87-heavy benchmark,
46 vs 73 Miter/s, same machine and toolchain.
