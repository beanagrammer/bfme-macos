// Mixed integer/FP compute, no syscalls. Compares Rosetta-translated x86 (32- and
// 64-bit, under Wine) against a native arm64 build of the identical loop.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
int main(int argc, char** argv){
    long n = (argc > 1) ? atol(argv[1]) : 300000000L;
    volatile double acc = 1.0; unsigned x = 12345;
    clock_t t0 = clock();
    for (long i = 0; i < n; i++) {
        x = x * 1664525u + 1013904223u;
        acc += (double)(x >> 16) * 1e-9;
        if (acc > 1e6) acc *= 0.5;
    }
    double sec = (double)(clock() - t0) / CLOCKS_PER_SEC;
    printf("%ld iters in %.3f s  (%.1f Miter/s)  acc=%.3f\n", n, sec, n/sec/1e6, acc);
    return 0;
}
