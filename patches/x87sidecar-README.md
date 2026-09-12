# x87sidecar exact-mode attempt — DOES NOT WORK

`x87sidecar-0001-exact-mode.patch` applies cleanly to
[athei/x87sidecar](https://github.com/athei/x87sidecar) at **v1.6.0** and
produces a sidecar that computes **wrong answers**. It is kept here as a record
of an approach that fails, and why, so nobody tries it again the same way.

**Do not install it.**

## What it was trying to do

BFME is a lockstep simulation: one differing bit desynchronises a match. The JIT
is bit-exact with real x87 for add, sub, mul, div and `fsqrt` at the `0x027F`
control word Windows runs at, and off by one unit in the last place for every
transcendental, because it emits its own Cody-Waite reduction and polynomial
rather than Intel's. `tools/x87check/x87exact.exe` measures it.

The idea was to hand just those opcodes to stock Rosetta and JIT everything
else, via a new `X87_EXACT=1`.

## Why it fails

`X87Cache.cpp` says plainly:

> There is deliberately no general per-opcode fallback: transcendentals would
> clash on stock's {x22, w23} helper-call ABI, which is why this list stays
> short.

That is exactly what happens. With the patch applied and `X87_EXACT=1`, the
refused instructions do not execute at all. `fsin` and `fcos` leave their input
on the stack unchanged, `fpatan` and `fyl2x` return zeros, and the
rotate-and-normalise loop in `x87exact.exe` comes back as NaN. The opcodes are
refused by `is_handled_x87` and returned as `std::nullopt` from the dispatch,
which is the mechanism `fclex`/`finit`/`fldenv`/`fstenv`/`fxsave`/`fxrstor` use
correctly — but those are metadata-only ops that do not go through stock's
helper-call path. The transcendentals do, and composing it does not work.

It is not a subtle failure. It is worse than the divergence it was meant to fix.

## How it briefly looked like it worked

The verification filtered the program's output with `grep -v '^\['` before
diffing. The section headers it needed to find are `[0x027F 53-bit ...]`, which
start with `[`, so the filter removed them, the range extraction matched
nothing, and two empty strings compared equal. The measurement reported
"bit-exact" while the build was returning NaN.

Two lessons, both now enforced in `bfme doctor`:

- A comparison that can pass by comparing nothing is not a test. Assert the
  inputs are non-empty first.
- "Could not measure" must read as unknown, never as passing.

The upstream test suite does not catch this either: 987 passed, 0 failed with
the patch applied, because nothing in it exercises `X87_EXACT`.

## What would actually be needed

Making the JIT's transcendentals match Intel bit for bit, in the JIT, rather
than delegating them. Bochs and QEMU both carry softfloat x87 implementations
aimed at this. That is a real project, not a knob.

The separate `X87_STOCK_OPS` bug is still worth reporting upstream on its own:
see `tools/x87check/stockops-bug.c`.

## Current state

Unchanged from before this attempt: the JIT is fast and one ulp off on
transcendentals. `bfme doctor` now reports that honestly instead of staying
quiet about it.
