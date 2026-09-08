// Does the x87 precision-control setting change Rosetta's emulation speed?
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static void setprec(unsigned pc){           /* pc: 0x000=24bit 0x200=53bit 0x300=64bit */
    unsigned short cw;
    __asm__ volatile ("fnstcw %0" : "=m"(cw));
    cw = (cw & ~0x0300u) | pc;
    __asm__ volatile ("fldcw %0" :: "m"(cw));
}
static double run(long n){
    double acc=1.0; unsigned x=12345;
    for (long i=0;i<n;i++){ x=x*1664525u+1013904223u; acc += (double)(x>>16)*1e-9; if(acc>1e6) acc*=0.5; }
    return acc;
}
int main(int argc,char**argv){
    long n=(argc>1)?atol(argv[1]):60000000L;
    struct { const char* name; unsigned pc; } modes[] = {
        {"24-bit (single)",0x000},{"53-bit (double)",0x200},{"64-bit (extended)",0x300}};
    for (int m=0;m<3;m++){
        setprec(modes[m].pc);
        clock_t t0=clock(); double r=run(n);
        double sec=(double)(clock()-t0)/CLOCKS_PER_SEC;
        printf("  %-20s %.3f s  (%.1f Miter/s)  acc=%.3f\n", modes[m].name, sec, n/sec/1e6, r);
    }
    return 0;
}
