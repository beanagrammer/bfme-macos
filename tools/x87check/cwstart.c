/* What x87 control word does a Windows process start with under Wine?
 *
 * It decides how much of the JIT's divergence from real x87 matters. At 0x027F
 * (53-bit) the JIT's arithmetic is bit-exact and only the transcendentals are
 * wrong; at 0x037F (64-bit extended) every divide and square root is wrong too,
 * because the JIT computes at 53 bits whatever the precision-control field says.
 *
 * Built with -nostdlib so no C runtime gets to call _controlfp before the read.
 * A C runtime is exactly what would hide the answer: mingw's sets 0x037F, which
 * is why a normally-linked probe reports the wrong thing.
 *
 *   i686-w64-mingw32-gcc -O1 -nostdlib -Wl,-e,_start -o cwstart.exe cwstart.c -lkernel32
 *
 * Real Windows hands a new process 0x027F. So does Wine, as of 11.17.
 */
#include <windows.h>

void __stdcall start(void) {
    unsigned short cw;
    __asm__ volatile("fnstcw %0" : "=m"(cw));
    static const char h[] = "0123456789ABCDEF";
    char buf[8] = { '0', 'x', h[(cw >> 12) & 15], h[(cw >> 8) & 15],
                    h[(cw >> 4) & 15], h[cw & 15], '\n', 0 };
    DWORD n;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), buf, 7, &n, 0);
    ExitProcess(0);
}
