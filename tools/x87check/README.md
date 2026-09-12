# x87 JIT check

`x87bench.exe` is a 32-bit x86 loop of mixed integer and x87 floating point, built
from `x87bench.c`. It takes an iteration count so it can be run short.

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
