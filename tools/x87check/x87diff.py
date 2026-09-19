#!/usr/bin/env python3
"""Compare two x87diff.exe runs and report the disagreement rate per opcode."""
import collections
import sys


def load(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            f = line.split()
            # Data lines only: anything the sidecar logs is dropped here rather
            # than silently counted as a result.
            # 3 fields for a one-operand op, 4 for a two-operand one
            if len(f) in (3, 4) and all(len(v) == 16 for v in f[1:]):
                try:
                    for v in f[1:]:
                        int(v, 16)
                except ValueError:
                    continue
                rows.append((f[0], " ".join(f[1:-1]), f[-1]))
    return rows


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: x87diff.py <jit.txt> <reference.txt>")
    a, b = load(sys.argv[1]), load(sys.argv[2])
    if not a or not b:
        sys.exit(f"no data rows: {len(a)} vs {len(b)} -- did the runs produce output?")
    if len(a) != len(b):
        sys.exit(f"row count differs ({len(a)} vs {len(b)}); the runs are not comparable")

    total = collections.Counter()
    bad = collections.Counter()
    ulps = collections.Counter()
    examples = {}
    for (op1, in1, r1), (op2, in2, r2) in zip(a, b):
        if op1 != op2 or in1 != in2:
            sys.exit("runs diverge in inputs; the sample generator is not deterministic")
        total[op1] += 1
        if r1 != r2:
            bad[op1] += 1
            d = int(r1, 16) - int(r2, 16)
            ulps[(op1, max(-3, min(3, d)))] += 1
            examples.setdefault(op1, (in1, r1, r2))

    print(f"{'opcode':<8}{'cases':>10}{'differ':>10}{'rate':>9}")
    for op in total:
        pct = 100.0 * bad[op] / total[op]
        print(f"{op:<8}{total[op]:>10}{bad[op]:>10}{pct:>8.2f}%")
    print()
    for op, (i, r1, r2) in examples.items():
        print(f"  first {op} mismatch: input {i}  jit {r1}  ref {r2}")
    print()
    print("ulp deltas (jit minus reference, clamped):")
    for (op, d), c in sorted(ulps.items()):
        print(f"  {op:<8} {d:+d} ulp: {c}")
    print()
    print("VERDICT:", "bit-exact" if not sum(bad.values()) else
          f"{sum(bad.values())} of {sum(total.values())} results differ")


if __name__ == "__main__":
    main()
