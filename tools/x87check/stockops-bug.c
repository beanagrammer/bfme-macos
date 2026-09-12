/* Minimal reproducer for an x87sidecar bug, for reporting upstream.
 *
 * X87_STOCK_OPS=<op> is meant to hand every block containing <op> to stock
 * Rosetta and leave the rest to the JIT. It does that correctly only while the
 * x87 register stack is empty at the handoff. When the compiler is keeping live
 * doubles in st(n) across the block -- which is the normal state of affairs in
 * optimised 32-bit x86 code -- the handoff returns garbage.
 *
 *   i686-w64-mingw32-gcc -O1 -static -o stockops-bug.exe stockops-bug.c
 *
 *   wine stockops-bug.exe                      -> C052105278C64505   (JIT)
 *   X87_ALWAYS_NONE=1 wine stockops-bug.exe    -> C052105278C644ED   (stock)
 *   X87_STOCK_OPS=fsin,fcos wine stockops-bug.exe
 *                                              -> 0000FFFFC0000000   (garbage)
 *
 * (mingw's startup leaves the control word at 0x037F, 64-bit extended, so those
 * are the extended-precision answers. At the 0x027F a Windows process really
 * starts with, stock gives C052105278C644C9 and the JIT still gives ...4505,
 * because the JIT computes at 53 bits whatever the precision-control field says.)
 *
 * The same source built -O0, which spills every local to memory and so leaves
 * the x87 stack empty around the asm, gives the correct stock answer under
 * X87_STOCK_OPS. Neither X87_ENABLE_BRIDGE=0, X87_DISABLE_CACHE=1,
 * X87_DISABLE_X87_IR=1, X87_DISABLE_ALL_FUSIONS=1, X87_DISABLE_DEFERRED_FXCH=1
 * nor X87_DISABLE_SINGLE_FAST=1 changes the -O1 result.
 *
 * This matters because handing just the transcendentals to stock is what makes
 * the JIT bit-exact with real x87, and bit-exactness is what a lockstep game
 * needs to stay in sync with players on other platforms.
 */
#include <stdio.h>
#include <string.h>

static double sim(long n) {
    double x = 0.7071067811865476, y = 0.7071067811865476, acc = 0.0;
    for (long i = 0; i < n; i++) {
        double ang = 0.01 + acc * 1e-9, s, c, sq, len;
        __asm__ volatile("fldl %2\n\t" "fsin\n\t" "fstpl %0\n\t"
                         "fldl %2\n\t" "fcos\n\t" "fstpl %1"
                         : "=m"(s), "=m"(c) : "m"(ang) : "st");
        double nx = x * c - y * s, ny = x * s + y * c;
        sq = nx * nx + ny * ny;
        __asm__ volatile("fldl %1\n\t" "fsqrt\n\t" "fstpl %0"
                         : "=m"(len) : "m"(sq) : "st");
        x = nx / len; y = ny / len;
        acc += x * 1.000001 - y * 0.999999;
    }
    return acc;
}

int main(void) {
    double r = sim(20000);
    unsigned long long u;
    memcpy(&u, &r, 8);
    printf("%016llX\n", u);
    return 0;
}
