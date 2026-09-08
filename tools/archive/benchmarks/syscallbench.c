// Measure WoW64 32<->64 transition cost: VirtualQuery is a thin syscall, so the
// loop time is dominated by the mode switch rather than kernel work.
#include <windows.h>
#include <stdio.h>
int main(int argc, char** argv){
    int n = (argc > 1) ? atoi(argv[1]) : 200000;
    MEMORY_BASIC_INFORMATION mbi;
    void* p = (void*)&mbi;
    LARGE_INTEGER f, a, b;
    QueryPerformanceFrequency(&f);
    VirtualQuery(p, &mbi, sizeof mbi);           /* warm up */
    QueryPerformanceCounter(&a);
    for (int i = 0; i < n; i++) VirtualQuery(p, &mbi, sizeof mbi);
    QueryPerformanceCounter(&b);
    double sec = (double)(b.QuadPart - a.QuadPart) / (double)f.QuadPart;
    printf("%d syscalls in %.3f s  =  %.2f us each  (%.0f/sec)\n",
           n, sec, sec * 1e6 / n, n / sec);
    return 0;
}
