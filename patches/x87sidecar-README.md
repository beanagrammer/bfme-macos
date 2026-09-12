# Patch for x87sidecar (not for Wine)

`x87sidecar-0001-exact-mode.patch` applies to
[athei/x87sidecar](https://github.com/athei/x87sidecar) at **v1.6.0**, which is
the release the shipped binary is built from. It adds `X87_EXACT=1`.

## What it is for

BFME is a lockstep simulation: only inputs cross the network and every client
runs the same physics from them. One differing bit puts two clients on different
timelines and the game calls it out of sync within seconds.

The JIT is fast because it keeps the x87 stack in ARM double registers. For add,
sub, mul, div and `fsqrt` that is bit-exact at the `0x027F` control word a
Windows process runs at, because both round to the same 53-bit result. For the
transcendentals it is not: the JIT emits its own Cody-Waite reduction and
polynomial, which lands within a unit in the last place of the true result but
not on the same value Intel's hardware produces. `tools/x87check/x87exact.exe`
measures it.

`X87_EXACT=1` hands those operations to stock Rosetta and JITs everything else.

## Why it is not just `X87_STOCK_OPS`

The sidecar already has `X87_STOCK_OPS`, which looks like the same thing. It
short-circuits the translate request and replies None without ever entering the
translator. That leaves deferred stack state which already-emitted code still
owes, and the result is garbage rather than merely imprecise --
`tools/x87check/stockops-bug.c` reproduces it, and no other knob avoids it.

The codebase already has the correct mechanism, and its own comment describes
it: `fclex`, `finit`, `fldenv`, `fstenv`, `fxsave` and `fxrstor` reach stock by
returning false from `is_handled_x87`, so the run breaks *before* the
instruction, `x87_end` flushes deferred state, and stock translates it against
coherent `X87State`. This patch routes the non-exact opcodes the same way, which
needs both halves: the `is_handled_x87` refusal *and* a `std::nullopt` return in
the dispatch, since breaking the run does not stop the instruction getting its
own translate request.

`X87Cache.cpp` warns that a general per-opcode fallback would clash with stock's
`{x22, w23}` helper-call ABI. Measured, it does not: the results come back
bit-exact and the game runs.

## Measured

Same build, `tools/x87check/x87bench.exe` over 20M iterations, and
`x87exact.exe` diffed against `BFME_NO_X87=1`:

| | throughput | bit-exact at 0x027F |
| --- | --- | --- |
| v1.6.0 unmodified | 73.5 Miter/s | no |
| v1.6.0 + patch, `X87_EXACT` unset | 74.1 Miter/s | no |
| v1.6.0 + patch, `X87_EXACT=1` | 74.3 Miter/s | **yes** |
| no JIT at all (`BFME_NO_X87=1`) | 7.8 Miter/s | yes |

So exactness is free. The earlier belief that speed and sync were in conflict
was wrong.

## Limits

Exactness is established at `0x027F`, 53-bit, which is what Windows and Wine
both hand a new process. At `0x037F` and `0x003F` the JIT still ignores the
precision-control field and computes at 53 bits. Nothing here changes that.

## Building

Apple's clang 16 cannot compile its own SDK's libc++ headers here
(`__builtin_ctzg` undeclared); use Homebrew LLVM.

```sh
git clone https://github.com/athei/x87sidecar && cd x87sidecar
git checkout v1.6.0
git apply /path/to/x87sidecar-0001-exact-mode.patch
cmake -B build -DCMAKE_C_COMPILER=/opt/homebrew/opt/llvm/bin/clang \
               -DCMAKE_CXX_COMPILER=/opt/homebrew/opt/llvm/bin/clang++
cmake --build build -j8
```

Note: upstream `master` at 010f50a is about 1.6x slower than v1.6.0 on
`x87bench` (46 vs 73 Miter/s), unrelated to this patch. Build from the tag.

## Upstreaming

Worth offering upstream, along with the `X87_STOCK_OPS` bug report. Both are
about the same thing: letting a caller trade a little speed for x87 results that
match the hardware everyone else is running on.
