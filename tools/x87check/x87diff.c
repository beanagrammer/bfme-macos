/* Differential tester: how often does the x87 JIT disagree with real x87?
 *
 * x87exact.exe samples ten hand-picked inputs per opcode, which is enough to
 * show that a difference exists and nowhere near enough to trust a fix. This
 * sweeps a large pseudorandom range and prints every result, so two runs can be
 * diffed to get an exact mismatch rate and concrete failing inputs:
 *
 *     bfme run tools/x87check/x87diff.exe 100000 > jit.txt
 *     BFME_NO_X87=1 bfme run tools/x87check/x87diff.exe 100000 > ref.txt
 *     python3 tools/x87check/x87diff.py jit.txt ref.txt
 *
 * Inputs come from a fixed LCG so both runs see identical values. Output is one
 * "<op> <input-bits> <result-bits>" line per case, hex, so a stray log line from
 * the sidecar cannot be mistaken for data.
 *
 * The control word is set to 0x027F throughout: that is what a Windows process
 * runs at, and the only setting whose agreement matters for matching x86 players.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned long long u64;
typedef unsigned int u32;

static u64 g_state = 0x2545F4914F6CDD1DULL;
static u64 rnd(void) {                       /* xorshift64*, identical everywhere */
    g_state ^= g_state >> 12;
    g_state ^= g_state << 25;
    g_state ^= g_state >> 27;
    return g_state * 0x2545F4914F6CDD1DULL;
}

static double bits_to_double(u64 u) { double d; memcpy(&d, &u, 8); return d; }
static u64 double_to_bits(double d) { u64 u; memcpy(&u, &d, 8); return u; }

/* A spread of magnitudes a game actually uses: angles, unit coordinates,
 * normalised vectors and the odd large value, rather than uniform bit patterns
 * that would be mostly NaNs and denormals. */
static double sample(void) {
    u64 r = rnd();
    int bucket = (int)(r & 7);
    double m = (double)((r >> 11) & 0xFFFFFFFFULL) / 4294967296.0;  /* [0,1) */
    switch (bucket) {
        case 0: return m * 6.283185307179586 - 3.141592653589793;   /* +-pi   */
        case 1: return m * 2.0 - 1.0;                               /* +-1    */
        case 2: return m * 200.0 - 100.0;                           /* map    */
        case 3: return m * 0.002 - 0.001;                           /* tiny   */
        case 4: return m * 20000.0 - 10000.0;                       /* large  */
        case 5: return m * 1.5707963267948966;                      /* 0..pi/2*/
        case 6: return m;                                           /* 0..1   */
        default: return m * 12.566370614359172 - 6.283185307179586; /* +-2pi  */
    }
}

#define UNARY(tag, insn)                                                       \
    do {                                                                       \
        for (long i = 0; i < n; i++) {                                         \
            double x = sample(), r;                                            \
            __asm__ volatile("fldl %1\n\t" insn "\n\t" "fstpl %0"               \
                             : "=m"(r) : "m"(x) : "st");                        \
            printf(tag " %016llX %016llX\n", double_to_bits(x),                 \
                   double_to_bits(r));                                          \
        }                                                                       \
    } while (0)

int main(int argc, char **argv) {
    long n = (argc > 1) ? atol(argv[1]) : 20000;
    unsigned short cw = 0x027F;
    __asm__ volatile("fldcw %0" :: "m"(cw));

    UNARY("fsin ", "fsin");
    UNARY("fcos ", "fcos");
    UNARY("fsqrt", "fsqrt");          /* expected to agree: the control */
    UNARY("f2xm1", "f2xm1");

    for (long i = 0; i < n; i++) {    /* fpatan takes two operands */
        double y = sample(), x = sample(), r;
        __asm__ volatile("fldl %1\n\t" "fldl %2\n\t" "fpatan\n\t" "fstpl %0"
                         : "=m"(r) : "m"(y), "m"(x) : "st");
        printf("fpatan %016llX %016llX\n", double_to_bits(y) ^ double_to_bits(x),
               double_to_bits(r));
    }
    return 0;
}
