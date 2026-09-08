// Does the x87 control word (exception masks / rounding / precision) change how fast
// Rosetta emulates x87? Windows default is 0x027F: all 6 exceptions masked, 53-bit.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static void setcw(unsigned short cw){ __asm__ volatile ("fldcw %0" :: "m"(cw)); }
static unsigned short getcw(void){ unsigned short cw; __asm__ volatile ("fnstcw %0" : "=m"(cw)); return cw; }
static double run(long n){
    double acc=1.0; unsigned x=12345;
    for (long i=0;i<n;i++){ x=x*1664525u+1013904223u; acc += (double)(x>>16)*1e-9; if(acc>1e6) acc*=0.5; }
    return acc;
}
int main(int argc,char**argv){
    long n=(argc>1)?atol(argv[1]):40000000L;
    printf("inherited control word = 0x%04X\n", getcw());
    struct { const char* name; unsigned short cw; } t[] = {
        {"0x027F windows default (all masked, 53-bit)", 0x027F},
        {"0x037F all masked, 64-bit extended",          0x037F},
        {"0x003F all masked, 24-bit",                   0x003F},
        {"0x0272 invalid+overflow UNmasked",            0x0272},
        {"0x0200 ALL exceptions unmasked",              0x0200},
    };
    for (int i=0;i<5;i++){
        setcw(t[i].cw);
        clock_t t0=clock(); double r=run(n);
        double sec=(double)(clock()-t0)/CLOCKS_PER_SEC;
        printf("  %-44s %.3f s  (%.1f Miter/s) acc=%.1f\n", t[i].name, sec, n/sec/1e6, r);
        setcw(0x027F);
    }
    return 0;
}
