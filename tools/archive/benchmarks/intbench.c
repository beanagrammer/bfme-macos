#include <stdio.h>
#include <stdlib.h>
#include <time.h>
int main(int argc, char** argv){
    long n = (argc>1)?atol(argv[1]):300000000L;
    volatile unsigned sink=0; unsigned x=12345, y=6789;
    clock_t t0=clock();
    for (long i=0;i<n;i++){ x = x*1664525u+1013904223u; y ^= x>>13; y = y*2246822519u; }
    sink = x^y;
    double sec=(double)(clock()-t0)/CLOCKS_PER_SEC;
    printf("integer: %ld iters in %.3f s (%.1f Miter/s) sink=%u\n", n, sec, n/sec/1e6, sink);
    return 0;
}
