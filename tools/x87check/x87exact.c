/* Is the x87 JIT bit-for-bit identical to the x87 Rosetta emulates?
 *
 * BFME is a lockstep simulation: every client runs the same physics from the
 * same inputs, and a single differing bit anywhere desynchronises the match.
 * The sidecar replaces Rosetta's x87 emulation with AArch64 code, so this asks
 * the only question that matters for online play -- does it produce the same
 * bits? Run it twice and diff:
 *
 *     bfme run tools/x87check/x87exact.exe            > with-jit.txt
 *     BFME_NO_X87=1 bfme run tools/x87check/x87exact.exe > without-jit.txt
 *     diff with-jit.txt without-jit.txt
 *
 * Any difference is a desync waiting to happen.
 */
#include <stdio.h>
#include <string.h>

typedef unsigned long long u64;
typedef unsigned short u16;

static void setcw(u16 cw) { __asm__ volatile("fldcw %0" :: "m"(cw)); }
static u16  getcw(void)   { u16 cw; __asm__ volatile("fnstcw %0" : "=m"(cw)); return cw; }

static u64 bits(double d) { u64 u; memcpy(&u, &d, 8); return u; }

/* Store st(0) as a raw 80-bit extended value. If the JIT works in doubles the
 * bottom 11 mantissa bits come back as zero, which real x87 hardware never does. */
#define EXT80(expr, out) do {                       \
    unsigned char _b[10];                           \
    __asm__ volatile(expr : : : "st");              \
    __asm__ volatile("fstpt %0" : "=m"(_b));        \
    memcpy((out), _b, 10);                          \
} while (0)

static void print80(const char *name, const unsigned char *b) {
    printf("  %-22s", name);
    for (int i = 9; i >= 0; i--) printf("%02X", b[i]);
    printf("\n");
}

/* One transcendental per line, on a spread of inputs, as exact bit patterns. */
#define UNARY(name, insn)                                                     \
static void name##_test(void) {                                               \
    static const double in[] = { 0.0, 0.5, 1.0, -1.0, 0.3, 1.2345678901234567,\
                                 0.78539816339744830961, 0.9999999999,        \
                                 1e-8, 123.456 };                             \
    printf("  %-10s", #name);                                                 \
    for (unsigned i = 0; i < sizeof in / sizeof in[0]; i++) {                  \
        double x = in[i], r;                                                   \
        __asm__ volatile("fldl %1\n\t" insn "\n\t" "fstpl %0"                  \
                         : "=m"(r) : "m"(x) : "st");                           \
        printf(" %016llX", bits(r));                                           \
    }                                                                          \
    printf("\n");                                                              \
}
UNARY(fsin,    "fsin")
UNARY(fcos,    "fcos")
UNARY(fsqrt,   "fsqrt")
UNARY(f2xm1,   "f2xm1")
UNARY(frndint, "frndint")
UNARY(fabs,    "fabs")
UNARY(fchs,    "fchs")

/* Two-operand transcendentals need a second stack slot. */
static void binary_tests(void) {
    static const double a[] = { 1.0, 2.0, 0.5, 3.0,  -1.0, 10.0 };
    static const double b[] = { 2.0, 3.0, 7.0, 0.25,  4.0, 1e-3 };

    printf("  %-10s", "fpatan");
    for (unsigned i = 0; i < 6; i++) {
        double r;
        __asm__ volatile("fldl %1\n\t" "fldl %2\n\t" "fpatan\n\t" "fstpl %0"
                         : "=m"(r) : "m"(b[i]), "m"(a[i]) : "st");
        printf(" %016llX", bits(r));
    }
    printf("\n");

    printf("  %-10s", "fyl2x");
    for (unsigned i = 0; i < 6; i++) {
        double r, x = a[i] < 0 ? -a[i] : a[i];
        __asm__ volatile("fldl %1\n\t" "fldl %2\n\t" "fyl2x\n\t" "fstpl %0"
                         : "=m"(r) : "m"(b[i]), "m"(x) : "st");
        printf(" %016llX", bits(r));
    }
    printf("\n");

    printf("  %-10s", "fprem");
    for (unsigned i = 0; i < 6; i++) {
        double r;
        __asm__ volatile("fldl %2\n\t" "fldl %1\n\t" "fprem\n\t" "fstpl %0\n\t" "fstp %%st(0)"
                         : "=m"(r) : "m"(a[i]), "m"(b[i]) : "st");
        printf(" %016llX", bits(r));
    }
    printf("\n");

    printf("  %-10s", "fscale");
    for (unsigned i = 0; i < 6; i++) {
        double r;
        __asm__ volatile("fldl %2\n\t" "fldl %1\n\t" "fscale\n\t" "fstpl %0\n\t" "fstp %%st(0)"
                         : "=m"(r) : "m"(a[i]), "m"(b[i]) : "st");
        printf(" %016llX", bits(r));
    }
    printf("\n");
}

/* Does the register file actually hold 80 bits? 1/3 and sqrt(2) have mantissas
 * that fill all 64 bits, so a double-backed implementation shows up instantly. */
static void extended_precision(void) {
    unsigned char b[10];
    double one = 1.0, three = 3.0, two = 2.0;

    __asm__ volatile("fldl %1\n\t" "fldl %2\n\t" "fdivp %%st,%%st(1)\n\t" "fstpt %0"
                     : "=m"(b) : "m"(three), "m"(one) : "st");
    print80("1/3 as 80-bit", b);

    __asm__ volatile("fldl %1\n\t" "fsqrt\n\t" "fstpt %0"
                     : "=m"(b) : "m"(two) : "st");
    print80("sqrt(2) as 80-bit", b);

    __asm__ volatile("fldpi\n\t" "fstpt %0" : "=m"(b) :: "st");
    print80("pi as 80-bit", b);

    __asm__ volatile("fldln2\n\t" "fstpt %0" : "=m"(b) :: "st");
    print80("ln2 as 80-bit", b);
}

/* A chaotic loop in the shape of unit movement: rotate, normalise, accumulate.
 * Tiny differences compound here exactly as they would across a match. */
static double simulation(long iters) {
    double x = 0.7071067811865476, y = 0.7071067811865476, acc = 0.0;
    for (long i = 0; i < iters; i++) {
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
    static const struct { const char *name; u16 cw; } modes[] = {
        { "0x027F 53-bit (the Windows default)", 0x027F },
        { "0x037F 64-bit extended",              0x037F },
        { "0x003F 24-bit single",                0x003F },
    };

    printf("inherited control word = 0x%04X\n", getcw());

    for (unsigned m = 0; m < 3; m++) {
        setcw(modes[m].cw);
        printf("\n[%s]\n", modes[m].name);
        fsin_test(); fcos_test(); fsqrt_test(); f2xm1_test();
        frndint_test(); fabs_test(); fchs_test();
        binary_tests();
        extended_precision();
        printf("  %-22s %016llX\n", "simulation(20000)", bits(simulation(20000)));
    }

    setcw(0x027F);
    return 0;
}
