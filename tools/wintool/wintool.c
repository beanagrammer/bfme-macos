// wintool: drive/capture Wine windows from the Windows side (no host mouse/screen involvement).
// usage: wintool list | find <title-substr> | shot <hwnd|title> <out.bmp> | click <hwnd|title> <x> <y> | move <hwnd|title> <x> <y> | text <hwnd|title> <string> | key <hwnd|title> <vk>
#include <windows.h>
#include <stdio.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static HWND g_found; static const char *g_needle;
static BOOL CALLBACK enum_find(HWND h, LPARAM lp){ char t[512]; if(!IsWindowVisible(h)) return TRUE; GetWindowTextA(h,t,sizeof t); if(t[0] && strstr(t,g_needle)){ g_found=h; return FALSE;} return TRUE; }
static BOOL CALLBACK enum_list(HWND h, LPARAM lp){ char t[512],c[128]; RECT r; if(!IsWindowVisible(h)) return TRUE; GetWindowTextA(h,t,sizeof t); GetClassNameA(h,c,sizeof c); GetWindowRect(h,&r); DWORD pid=0; GetWindowThreadProcessId(h,&pid); printf("hwnd=%p pid=%lu class=%s rect=%ld,%ld,%ld,%ld title=\"%s\"\n",h,(unsigned long)pid,c,r.left,r.top,r.right,r.bottom,t); return TRUE; }

static void dump_one(HWND h,int depth){ char t[256],c[128]; RECT r; DWORD pid=0; GetWindowTextA(h,t,sizeof t); GetClassNameA(h,c,sizeof c); GetWindowRect(h,&r); GetWindowThreadProcessId(h,&pid); LONG st=GetWindowLongA(h,GWL_STYLE), ex=GetWindowLongA(h,GWL_EXSTYLE); HWND par=GetParent(h), own=GetWindow(h,GW_OWNER);
  printf("%*shwnd=%p pid=%lu vis=%d child=%d parent=%p owner=%p style=%08lx ex=%08lx rect=%ld,%ld,%ld,%ld class=%s title=\"%s\"\n",depth*2,"",h,(unsigned long)pid,IsWindowVisible(h)?1:0,(st&WS_CHILD)?1:0,par,own,(unsigned long)st,(unsigned long)ex,r.left,r.top,r.right,r.bottom,c,t); }
static BOOL CALLBACK enum_child_all(HWND h, LPARAM lp){ dump_one(h,(int)lp); return TRUE; }
static BOOL CALLBACK enum_all(HWND h, LPARAM lp){ dump_one(h,0); EnumChildWindows(h,enum_child_all,1); return TRUE; }
static HWND resolve(const char *s){ if(s[0]=='0'&&(s[1]=='x'||s[1]=='X')) return (HWND)(ULONG_PTR)strtoull(s,NULL,16); g_found=NULL; g_needle=s; EnumWindows(enum_find,0); return g_found; }

static int shot(HWND h, const char *out){
  RECT r; GetClientRect(h,&r); int w=r.right-r.left, hh=r.bottom-r.top; if(w<=0||hh<=0){fprintf(stderr,"bad size\n");return 2;}
  HDC wdc=GetDC(h); HDC mdc=CreateCompatibleDC(wdc);
  BITMAPINFO bi; memset(&bi,0,sizeof bi); bi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER); bi.bmiHeader.biWidth=w; bi.bmiHeader.biHeight=-hh; bi.bmiHeader.biPlanes=1; bi.bmiHeader.biBitCount=32; bi.bmiHeader.biCompression=BI_RGB;
  void *bits=NULL; HBITMAP bmp=CreateDIBSection(mdc,&bi,DIB_RGB_COLORS,&bits,NULL,0); HGDIOBJ old=SelectObject(mdc,bmp);
  BOOL ok=FALSE; const char *mode=getenv("WINTOOL_SHOT");
  if(mode && !strcmp(mode,"print")) ok=PrintWindow(h,mdc,2 /*PW_RENDERFULLCONTENT*/|1 /*PW_CLIENTONLY*/);
  else ok=BitBlt(mdc,0,0,w,hh,wdc,0,0,SRCCOPY|CAPTUREBLT);
  // write BMP (bottom-up) 
  FILE *f=fopen(out,"wb"); if(!f){fprintf(stderr,"cannot open %s\n",out);return 3;}
  BITMAPFILEHEADER fh; memset(&fh,0,sizeof fh); fh.bfType=0x4D42; fh.bfOffBits=sizeof(BITMAPFILEHEADER)+sizeof(BITMAPINFOHEADER); fh.bfSize=fh.bfOffBits+w*hh*4;
  BITMAPINFOHEADER ih=bi.bmiHeader; ih.biHeight=hh; // positive = bottom-up
  fwrite(&fh,sizeof fh,1,f); fwrite(&ih,sizeof ih,1,f);
  for(int y=hh-1;y>=0;y--) fwrite((char*)bits+y*w*4,w*4,1,f);
  fclose(f);
  // count non-white pixels as a sanity metric
  unsigned long nonwhite=0; unsigned *px=bits; for(long i=0;i<(long)w*hh;i++) if((px[i]&0xffffff)!=0xffffff) nonwhite++;
  printf("shot %dx%d ok=%d nonwhite=%lu -> %s\n",w,hh,ok,nonwhite,out);
  SelectObject(mdc,old); DeleteObject(bmp); DeleteDC(mdc); ReleaseDC(h,wdc); return 0;
}
static int click(HWND h,int x,int y){ LPARAM lp=MAKELPARAM(x,y); 
  // child window hit test so messages go to the right hwnd (WPF uses a single hwnd, fine)
  POINT p={x,y}; ClientToScreen(h,&p); HWND child=WindowFromPoint(p); HWND target=child?child:h; if(child&&child!=h){ POINT q=p; ScreenToClient(child,&q); lp=MAKELPARAM(q.x,q.y);} 
  PostMessageA(target,WM_MOUSEMOVE,0,lp); Sleep(60); PostMessageA(target,WM_LBUTTONDOWN,MK_LBUTTON,lp); Sleep(60); PostMessageA(target,WM_LBUTTONUP,0,lp); Sleep(60); PostMessageA(target,WM_MOUSEMOVE,0,lp);
  printf("clicked %p at %d,%d (target %p)\n",h,x,y,target); return 0; }

static int click2(HWND h,int x,int y){ LPARAM lp=MAKELPARAM(x,y); PostMessageA(h,WM_MOUSEMOVE,0,lp); PostMessageA(h,WM_LBUTTONDOWN,MK_LBUTTON,lp); PostMessageA(h,WM_LBUTTONUP,0,lp); printf("click2 %p at %d,%d\n",h,x,y); return 0; }
static int hwclick(HWND h,int x,int y){ POINT old; GetCursorPos(&old); POINT p={x,y}; ClientToScreen(h,&p);
  int vx=GetSystemMetrics(SM_XVIRTUALSCREEN), vy=GetSystemMetrics(SM_YVIRTUALSCREEN), vw=GetSystemMetrics(SM_CXVIRTUALSCREEN), vh=GetSystemMetrics(SM_CYVIRTUALSCREEN);
  INPUT in[3]; memset(in,0,sizeof in); for(int i=0;i<3;i++){ in[i].type=INPUT_MOUSE; in[i].mi.dx=(p.x-vx)*65535/(vw-1); in[i].mi.dy=(p.y-vy)*65535/(vh-1); in[i].mi.dwFlags=MOUSEEVENTF_ABSOLUTE|MOUSEEVENTF_VIRTUALDESK|MOUSEEVENTF_MOVE; }
  in[1].mi.dwFlags|=MOUSEEVENTF_LEFTDOWN; in[2].mi.dwFlags|=MOUSEEVENTF_LEFTUP;
  SendInput(1,&in[0],sizeof(INPUT)); Sleep(80); SendInput(1,&in[1],sizeof(INPUT)); Sleep(80); SendInput(1,&in[2],sizeof(INPUT)); Sleep(120);
  SetCursorPos(old.x,old.y); printf("hwclick %p at client %d,%d screen %ld,%ld (restored cursor to %ld,%ld)\n",h,x,y,p.x,p.y,old.x,old.y); return 0; }

static int sclick(HWND h,int x,int y){ LPARAM lp=MAKELPARAM(x,y); SendMessageA(h,WM_MOUSEMOVE,0,lp); SendMessageA(h,WM_LBUTTONDOWN,MK_LBUTTON,lp); SendMessageA(h,WM_LBUTTONUP,0,lp); printf("sclick %p at %d,%d\n",h,x,y); return 0; }

static int hwwheel(HWND h,int x,int y,int notches){ POINT old; GetCursorPos(&old); POINT p={x,y}; ClientToScreen(h,&p);
  int vx=GetSystemMetrics(SM_XVIRTUALSCREEN), vy=GetSystemMetrics(SM_YVIRTUALSCREEN), vw=GetSystemMetrics(SM_CXVIRTUALSCREEN), vh=GetSystemMetrics(SM_CYVIRTUALSCREEN);
  INPUT in; memset(&in,0,sizeof in); in.type=INPUT_MOUSE; in.mi.dx=(p.x-vx)*65535/(vw-1); in.mi.dy=(p.y-vy)*65535/(vh-1); in.mi.dwFlags=MOUSEEVENTF_ABSOLUTE|MOUSEEVENTF_VIRTUALDESK|MOUSEEVENTF_MOVE; SendInput(1,&in,sizeof(INPUT)); Sleep(100);
  int n=notches<0?-notches:notches; for(int i=0;i<n;i++){ INPUT w; memset(&w,0,sizeof w); w.type=INPUT_MOUSE; w.mi.dwFlags=MOUSEEVENTF_WHEEL; w.mi.mouseData=(DWORD)(notches<0?(DWORD)-120:120); SendInput(1,&w,sizeof(INPUT)); Sleep(70);} Sleep(100); SetCursorPos(old.x,old.y); printf("wheel %d at %d,%d\n",notches,x,y); return 0; }

static int do_foreground(HWND h){
  AllowSetForegroundWindow(ASFW_ANY);
  ShowWindow(h, SW_SHOW);
  BringWindowToTop(h);
  SetForegroundWindow(h);
  SetActiveWindow(h);
  SetFocus(h);
  HWND fg=GetForegroundWindow();
  printf("foreground req=%p now=%p active=%p focus=%p\n", h, fg, GetActiveWindow(), GetFocus());
  return 0; }

static int do_rpm(DWORD pid, ULONG_PTR addr, SIZE_T len){
  HANDLE h=OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION,FALSE,pid);
  if(!h){ printf("OpenProcess FAILED pid=%lu err=%lu\n",(unsigned long)pid,(unsigned long)GetLastError()); return 2; }
  unsigned char buf[256]; if(len>sizeof buf) len=sizeof buf;
  SIZE_T got=0; BOOL ok=ReadProcessMemory(h,(LPCVOID)addr,buf,len,&got);
  printf("OpenProcess OK  ReadProcessMemory(0x%llx,%llu) ok=%d got=%llu err=%lu\n",
         (unsigned long long)addr,(unsigned long long)len,ok,(unsigned long long)got,(unsigned long)GetLastError());
  if(ok&&got){ printf("  bytes:"); for(SIZE_T i=0;i<got&&i<32;i++) printf(" %02x",buf[i]);
    printf("   ascii: "); for(SIZE_T i=0;i<got&&i<32;i++) putchar(buf[i]>=32&&buf[i]<127?buf[i]:'.'); printf("\n"); }
  MEMORY_BASIC_INFORMATION mbi; SIZE_T q=VirtualQueryEx(h,(LPCVOID)addr,&mbi,sizeof mbi);
  printf("  VirtualQueryEx ret=%llu state=0x%lx protect=0x%lx base=%p size=0x%llx\n",
         (unsigned long long)q,(unsigned long)mbi.State,(unsigned long)mbi.Protect,mbi.BaseAddress,(unsigned long long)mbi.RegionSize);
  CloseHandle(h); return ok?0:3; }

#include <psapi.h>
static int do_mods(DWORD pid){
  HANDLE h=OpenProcess(PROCESS_QUERY_INFORMATION|PROCESS_VM_READ,FALSE,pid);
  if(!h){ printf("OpenProcess failed err=%lu\n",(unsigned long)GetLastError()); return 2; }
  HMODULE mods[1024]; DWORD need=0;
  if(!EnumProcessModulesEx(h,mods,sizeof mods,&need,0x03 /*LIST_MODULES_ALL*/)){
    printf("EnumProcessModulesEx failed err=%lu\n",(unsigned long)GetLastError()); CloseHandle(h); return 3; }
  DWORD n=need/sizeof(HMODULE); printf("modules=%lu\n",(unsigned long)n);
  for(DWORD i=0;i<n;i++){ char nm[MAX_PATH]=""; if(GetModuleFileNameExA(h,mods[i],nm,sizeof nm)) printf("  %s\n",nm); }
  CloseHandle(h); return 0; }

static int do_pipes(const char*filt){
  WIN32_FIND_DATAA fd; HANDLE h=FindFirstFileA("\\\\.\\pipe\\*",&fd);
  if(h==INVALID_HANDLE_VALUE){ printf("FindFirstFile(pipe) failed err=%lu\n",(unsigned long)GetLastError()); return 2; }
  int n=0;
  do{ if(!filt||strstr(fd.cFileName,filt)){ printf("  pipe: %s\n", fd.cFileName); n++; } }while(FindNextFileA(h,&fd));
  FindClose(h); printf("total matching pipes: %d\n", n); return 0; }

static int do_pipesrv(const char*nm,int secs){
  char path[256]; snprintf(path,sizeof path,"\\\\.\\pipe\\%s",nm);
  HANDLE h=CreateNamedPipeA(path, PIPE_ACCESS_DUPLEX, PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT,
                            PIPE_UNLIMITED_INSTANCES, 10000, 10000, 3000, NULL);
  printf("CreateNamedPipe(%s) -> %s err=%lu\n", path, h==INVALID_HANDLE_VALUE?"FAIL":"OK", (unsigned long)GetLastError());
  if(h==INVALID_HANDLE_VALUE) return 2;
  printf("server holding pipe open for %d s (bitness=%d)\n", secs, (int)(sizeof(void*)*8));
  fflush(stdout);
  Sleep(secs*1000);
  CloseHandle(h); return 0; }
static int do_pipecli(const char*nm){
  char path[256]; snprintf(path,sizeof path,"\\\\.\\pipe\\%s",nm);
  HANDLE h=CreateFileA(path, GENERIC_READ|GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
  DWORD e=GetLastError();
  printf("CreateFile(%s) -> %s err=%lu (bitness=%d)\n", path, h==INVALID_HANDLE_VALUE?"FAIL":"OK",
         (unsigned long)e, (int)(sizeof(void*)*8));
  if(h!=INVALID_HANDLE_VALUE){ CloseHandle(h); return 0; }
  return 3; }

static int do_cursor(void){ POINT p; GetCursorPos(&p); printf("cursor %ld,%ld\n",p.x,p.y); return 0; }

/* Round-trip test: warp the cursor to a Win32 screen point and read it back.
 * Under winemac.drv's Retina mode the warp goes out in Cocoa points and the
 * position comes back from a real Cocoa event, so this shows any scaling error
 * in the path the Arena's automation actually uses. */
static int do_curtest(void){
  static const POINT pts[] = { {0,0}, {100,100}, {1280,720}, {2415,1357}, {2559,1439} };
  printf("screen=%dx%d\n",GetSystemMetrics(SM_CXSCREEN),GetSystemMetrics(SM_CYSCREEN));
  for(unsigned i=0;i<sizeof pts/sizeof pts[0];i++){
    POINT g={0,0};
    SetCursorPos(pts[i].x,pts[i].y); Sleep(120); GetCursorPos(&g);
    printf("SetCursorPos(%4ld,%4ld) -> GetCursorPos(%4ld,%4ld) %s\n",
      pts[i].x,pts[i].y,g.x,g.y,(g.x==pts[i].x&&g.y==pts[i].y)?"ok":"MISMATCH");
  }
  /* the same thing through SendInput absolute coordinates, which is what
   * injected automation normally uses */
  for(unsigned i=0;i<sizeof pts/sizeof pts[0];i++){
    INPUT in; POINT g={0,0};
    memset(&in,0,sizeof in); in.type=INPUT_MOUSE;
    in.mi.dwFlags=MOUSEEVENTF_MOVE|MOUSEEVENTF_ABSOLUTE|MOUSEEVENTF_VIRTUALDESK;
    in.mi.dx=(LONG)((pts[i].x*65535)/(GetSystemMetrics(SM_CXVIRTUALSCREEN)-1));
    in.mi.dy=(LONG)((pts[i].y*65535)/(GetSystemMetrics(SM_CYVIRTUALSCREEN)-1));
    SendInput(1,&in,sizeof in); Sleep(120); GetCursorPos(&g);
    printf("SendInput abs(%4ld,%4ld) -> GetCursorPos(%4ld,%4ld) %s\n",
      pts[i].x,pts[i].y,g.x,g.y,(labs(g.x-pts[i].x)<=1&&labs(g.y-pts[i].y)<=1)?"ok":"MISMATCH");
  }
  return 0; }

static int do_pipecmd(const char*nm,const char*cmd){
  char path[256]; snprintf(path,sizeof path,"\\\\.\\pipe\\%s",nm);
  HANDLE h=CreateFileA(path,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,0,NULL);
  if(h==INVALID_HANDLE_VALUE){ printf("connect FAIL err=%lu\n",(unsigned long)GetLastError()); return 2; }
  printf("connected\n"); fflush(stdout);
  char buf[1024]; int n=snprintf(buf,sizeof buf,"%s\n",cmd);
  DWORD wr=0; BOOL ok=WriteFile(h,buf,n,&wr,NULL);
  printf("write ok=%d wrote=%lu (%s)\n",ok,(unsigned long)wr,cmd); fflush(stdout);
  char rb[2048]; DWORD rd=0;
  ok=ReadFile(h,rb,sizeof rb-1,&rd,NULL);
  if(ok&&rd){ rb[rd]=0; printf("RESPONSE(%lu): %s\n",(unsigned long)rd,rb); }
  else printf("read ok=%d rd=%lu err=%lu\n",ok,(unsigned long)rd,(unsigned long)GetLastError());
  CloseHandle(h); return 0; }

static int do_pipecmd2(const char*nm,int argc,char**argv,int first){
  char path[256]; snprintf(path,sizeof path,"\\\\.\\pipe\\%s",nm);
  HANDLE h=CreateFileA(path,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,0,NULL);
  if(h==INVALID_HANDLE_VALUE){ printf("connect FAIL err=%lu\n",(unsigned long)GetLastError()); return 2; }
  char buf[1024]; int n=0;
  for(int i=first;i<argc;i++) n+=snprintf(buf+n,sizeof buf-n,"%s\n",argv[i]);
  DWORD wr=0; WriteFile(h,buf,n,&wr,NULL);
  printf("sent %lu bytes: ",(unsigned long)wr);
  for(int i=first;i<argc;i++) printf("[%s]",argv[i]);
  printf("\n"); fflush(stdout);
  char rb[2048]; DWORD rd=0;
  if(ReadFile(h,rb,sizeof rb-1,&rd,NULL)&&rd){ rb[rd]=0; printf("RESPONSE(%lu): %s\n",(unsigned long)rd,rb); }
  else printf("read err=%lu\n",(unsigned long)GetLastError());
  CloseHandle(h); return 0; }

static int do_apisrv(const char*nm,int secs){
  char path[256]; snprintf(path,sizeof path,"\\\\.\\pipe\\%s",nm);
  DWORD t0=GetTickCount();
  printf("apisrv listening on %s for %ds\n", path, secs); fflush(stdout);
  while ((GetTickCount()-t0) < (DWORD)secs*1000){
    HANDLE h=CreateNamedPipeA(path, PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT, 255, 10000, 10000, 3000, NULL);
    if(h==INVALID_HANDLE_VALUE){ printf("create fail err=%lu\n",(unsigned long)GetLastError()); Sleep(200); continue; }
    BOOL con=ConnectNamedPipe(h,NULL);
    if(!con && GetLastError()!=ERROR_PIPE_CONNECTED){ CloseHandle(h); Sleep(50); continue; }
    printf("[client connected]\n"); fflush(stdout);
    for(;;){
      char rb[4096]; DWORD rd=0;
      if(!ReadFile(h,rb,sizeof rb-1,&rd,NULL) || !rd) break;
      rb[rd]=0;
      /* first line = command */
      char cmd[256]={0}; int i=0; while(rb[i] && rb[i]!='\n' && i<255){ cmd[i]=rb[i]; i++; }
      printf("REQ: %s | raw=", cmd);
      for(DWORD k=0;k<rd;k++) putchar(rb[k]=='\n'?'|':rb[k]);
      printf("\n"); fflush(stdout);
      const char*resp="OK";
      if(!strcmp(cmd,"getViewportSize")) resp="1280 720";
      else if(!strcmp(cmd,"getPixelColor")) resp="255 255 255";
      else if(!strcmp(cmd,"getNetworkStats")) resp="relayReady=1;relayFail=0;fps=60;eng=1";
      DWORD wr=0; char ob[512]; int n=snprintf(ob,sizeof ob,"%s\n",resp);
      WriteFile(h,ob,n,&wr,NULL);
      printf("RSP: %s\n", resp); fflush(stdout);
    }
    printf("[client gone]\n"); fflush(stdout);
    DisconnectNamedPipe(h); CloseHandle(h);
  }
  return 0; }

static int do_fgq(void){
  HWND f=GetForegroundWindow();
  char t[256]={0}, c[256]={0}; RECT r={0,0,0,0}; DWORD pid=0;
  if(f){ GetWindowTextA(f,t,sizeof t-1); GetClassNameA(f,c,sizeof c-1); GetWindowRect(f,&r); GetWindowThreadProcessId(f,&pid); }
  printf("fg=%p pid=%lu rect=%ld,%ld,%ld,%ld class=\"%s\" title=\"%s\"\n",
    f,(unsigned long)pid,(long)r.left,(long)r.top,(long)r.right,(long)r.bottom,c,t);
  return 0; }

static void desc(HWND f,char*out,int n){
  char t[200]={0}; RECT r={0,0,0,0}; DWORD pid=0;
  if(f){ GetWindowTextA(f,t,sizeof t-1); GetWindowRect(f,&r); GetWindowThreadProcessId(f,&pid); }
  snprintf(out,n,"fg=%p pid=%lu rect=%ld,%ld,%ld,%ld title=\"%s\"",
    f,(unsigned long)pid,(long)r.left,(long)r.top,(long)r.right,(long)r.bottom,t);
}
static int do_fgwatch(int secs){
  setvbuf(stdout,NULL,_IONBF,0);
  DWORD t0=GetTickCount(); char prev[512]=""; char cur[512];
  while((GetTickCount()-t0)<(DWORD)secs*1000){
    HWND f=GetForegroundWindow(); desc(f,cur,sizeof cur);
    if(strcmp(cur,prev)){ SYSTEMTIME st; GetLocalTime(&st);
      printf("%02d:%02d:%02d.%03d %s\n",st.wHour,st.wMinute,st.wSecond,st.wMilliseconds,cur);
      strcpy(prev,cur); }
    Sleep(400);
  }
  return 0; }

typedef struct { const char*sub; HWND found; int bestArea; } pinctx;
static int proc_matches(HWND h,const char*sub){
  DWORD pid=0; GetWindowThreadProcessId(h,&pid); if(!pid) return 0;
  HANDLE ph=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);
  if(!ph) return 0;
  char nm[MAX_PATH]={0}; DWORD n=MAX_PATH;
  int ok=QueryFullProcessImageNameA(ph,0,nm,&n);
  CloseHandle(ph);
  if(!ok) return 0;
  for(char*p=nm;*p;p++) *p=(char)tolower((unsigned char)*p);
  return strstr(nm,sub)!=NULL;
}
static BOOL CALLBACK pin_enum(HWND h, LPARAM lp){
  pinctx*c=(pinctx*)lp;
  if(!IsWindowVisible(h)) return TRUE;
  RECT r; if(!GetWindowRect(h,&r)) return TRUE;
  int area=(r.right-r.left)*(r.bottom-r.top);
  if(area<10000) return TRUE;
  if(!proc_matches(h,c->sub)) return TRUE;
  if(area>c->bestArea){ c->bestArea=area; c->found=h; }
  return TRUE;
}
static int do_pin(const char*sub,int secs){
  setvbuf(stdout,NULL,_IONBF,0);
  DWORD t0=GetTickCount(); char prev[512]=""; char cur[512];
  AllowSetForegroundWindow(ASFW_ANY);
  while((GetTickCount()-t0)<(DWORD)secs*1000){
    pinctx c={sub,NULL,0}; EnumWindows(pin_enum,(LPARAM)&c);
    if(c.found){
      RECT r; GetWindowRect(c.found,&r);
      if(r.left!=0||r.top!=0)
        SetWindowPos(c.found,NULL,0,0,0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE);
      HWND f=GetForegroundWindow();
      if(f!=c.found){ BringWindowToTop(c.found); SetForegroundWindow(c.found); SetActiveWindow(c.found); }
      GetWindowRect(c.found,&r); f=GetForegroundWindow();
      char t[160]={0}; GetWindowTextA(c.found,t,sizeof t-1);
      snprintf(cur,sizeof cur,"win=%p rect=%ld,%ld,%ld,%ld fg=%s title=\"%s\"",c.found,
        (long)r.left,(long)r.top,(long)r.right,(long)r.bottom, f==c.found?"YES":"no", t);
    } else snprintf(cur,sizeof cur,"no window for process \"%s\"",sub);
    if(strcmp(cur,prev)){ SYSTEMTIME st; GetLocalTime(&st);
      printf("%02d:%02d:%02d.%03d %s\n",st.wHour,st.wMinute,st.wSecond,st.wMilliseconds,cur);
      strcpy(prev,cur); }
    Sleep(300);
  }
  return 0; }

static HANDLE up_open(const char*up){
  char path[256]; snprintf(path,sizeof path,"\\\\.\\pipe\\%s",up);
  for(int i=0;i<200;i++){
    HANDLE h=CreateFileA(path,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,0,NULL);
    if(h!=INVALID_HANDLE_VALUE){ DWORD m=PIPE_READMODE_MESSAGE; SetNamedPipeHandleState(h,&m,NULL,NULL); return h; }
    if(GetLastError()==ERROR_PIPE_BUSY){ WaitNamedPipeA(path,2000); continue; }
    Sleep(50);
  }
  return INVALID_HANDLE_VALUE;
}
static void logline(const char*tag,const char*buf,DWORD n){
  SYSTEMTIME st; GetLocalTime(&st);
  printf("%02d:%02d:%02d.%03d %s ",st.wHour,st.wMinute,st.wSecond,st.wMilliseconds,tag);
  for(DWORD i=0;i<n;i++) putchar(buf[i]=='\n'?'|':(buf[i]=='\r'?' ':buf[i]));
  printf("\n");
}
static int do_apiproxy(const char*listen,const char*up,int secs){
  setvbuf(stdout,NULL,_IONBF,0);
  char path[256]; snprintf(path,sizeof path,"\\\\.\\pipe\\%s",listen);
  printf("proxy: listen %s  ->  upstream %s  (%ds)\n",listen,up,secs);
  DWORD t0=GetTickCount();
  while((GetTickCount()-t0)<(DWORD)secs*1000){
    HANDLE cl=CreateNamedPipeA(path,PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT,255,65536,65536,3000,NULL);
    if(cl==INVALID_HANDLE_VALUE){ printf("listen create failed err=%lu\n",(unsigned long)GetLastError()); Sleep(200); continue; }
    BOOL con=ConnectNamedPipe(cl,NULL);
    if(!con && GetLastError()!=ERROR_PIPE_CONNECTED){ CloseHandle(cl); continue; }
    HANDLE us=up_open(up);
    if(us==INVALID_HANDLE_VALUE){ printf("UPSTREAM UNAVAILABLE\n"); CloseHandle(cl); Sleep(200); continue; }
    for(;;){
      char rb[65536]; DWORD rd=0;
      if(!ReadFile(cl,rb,sizeof rb,&rd,NULL)||!rd) break;
      logline("REQ",rb,rd);
      DWORD wr=0;
      if(!WriteFile(us,rb,rd,&wr,NULL)){ printf("upstream write err=%lu\n",(unsigned long)GetLastError()); break; }
      char sb[65536]; DWORD sd=0;
      if(!ReadFile(us,sb,sizeof sb,&sd,NULL)||!sd){ printf("upstream read err=%lu\n",(unsigned long)GetLastError()); break; }
      if(sd<400) logline("RSP",sb,sd); else { SYSTEMTIME st; GetLocalTime(&st);
        printf("%02d:%02d:%02d.%03d RSP <%lu bytes>\n",st.wHour,st.wMinute,st.wSecond,st.wMilliseconds,(unsigned long)sd); }
      if(!WriteFile(cl,sb,sd,&wr,NULL)) break;
    }
    CloseHandle(us); DisconnectNamedPipe(cl); CloseHandle(cl);
  }
  return 0; }

/* passive counterpart of "pin": observe only, change nothing */
static int do_winwatch(const char*sub,int secs){
  setvbuf(stdout,NULL,_IONBF,0);
  DWORD t0=GetTickCount(); char prev[600]=""; char cur[600];
  while((GetTickCount()-t0)<(DWORD)secs*1000){
    pinctx c={sub,NULL,0}; EnumWindows(pin_enum,(LPARAM)&c);
    HWND f=GetForegroundWindow();
    if(c.found){
      RECT r; GetWindowRect(c.found,&r);
      char t[160]={0}; GetWindowTextA(c.found,t,sizeof t-1);
      int okpos = (r.left>=0 && r.left<=80 && r.top>=0 && r.top<=80);
      snprintf(cur,sizeof cur,"game win=%p rect=%ld,%ld,%ld,%ld pos_ok=%s fg=%s (fg win=%p) title=\"%s\"",
        c.found,(long)r.left,(long)r.top,(long)r.right,(long)r.bottom,
        okpos?"YES":"NO", f==c.found?"YES":"NO", f, t);
    } else {
      char ft[160]={0}; if(f) GetWindowTextA(f,ft,sizeof ft-1);
      snprintf(cur,sizeof cur,"no game window; fg=%p \"%s\"",f,ft);
    }
    if(strcmp(cur,prev)){ SYSTEMTIME st; GetLocalTime(&st);
      printf("%02d:%02d:%02d.%03d %s\n",st.wHour,st.wMinute,st.wSecond,st.wMilliseconds,cur);
      strcpy(prev,cur); }
    Sleep(250);
  }
  return 0; }

static int do_dpi(void){
  HMODULE u=GetModuleHandleA("user32.dll");
  UINT (WINAPI *pGetDpiForSystem)(void)=(void*)GetProcAddress(u,"GetDpiForSystem");
  UINT (WINAPI *pGetDpiForWindow)(HWND)=(void*)GetProcAddress(u,"GetDpiForWindow");
  HDC dc=GetDC(NULL);
  printf("SM_CXSCREEN=%d SM_CYSCREEN=%d\n",GetSystemMetrics(SM_CXSCREEN),GetSystemMetrics(SM_CYSCREEN));
  printf("SM_CXVIRTUALSCREEN=%d SM_CYVIRTUALSCREEN=%d\n",GetSystemMetrics(SM_CXVIRTUALSCREEN),GetSystemMetrics(SM_CYVIRTUALSCREEN));
  printf("LOGPIXELSX=%d LOGPIXELSY=%d\n",GetDeviceCaps(dc,LOGPIXELSX),GetDeviceCaps(dc,LOGPIXELSY));
  printf("HORZRES=%d VERTRES=%d DESKTOPHORZRES=%d DESKTOPVERTRES=%d\n",
     GetDeviceCaps(dc,HORZRES),GetDeviceCaps(dc,VERTRES),
     GetDeviceCaps(dc,DESKTOPHORZRES),GetDeviceCaps(dc,DESKTOPVERTRES));
  if(pGetDpiForSystem) printf("GetDpiForSystem=%u\n",pGetDpiForSystem());
  HWND f=GetForegroundWindow();
  if(pGetDpiForWindow&&f) printf("GetDpiForWindow(fg)=%u\n",pGetDpiForWindow(f));
  ReleaseDC(NULL,dc);
  return 0; }

/* Coordinate-rescaling proxy for the Arena API pipe.
 *
 * The Arena's BFME1 button positions are compile-time constants for a 2560x1440
 * game (ButtonNetworkBack 2415,1357; ButtonJoinGame 1280,443) with no runtime
 * scaling, so the game has to be 2560x1440 or every click misses. That does not
 * fit a laptop display. This proxy sits between the Arena and the addon and
 * rescales the coordinate-bearing commands, letting the game run at any 16:9
 * size while the Arena still thinks it is driving 2560x1440.
 */
static int scale_coord(int v, int from, int to){ return (int)(((long long)v * to + from/2) / from); }

static int do_apiscale(const char*listen,const char*up,int sw,int sh,int dw,int dh,int secs){
  setvbuf(stdout,NULL,_IONBF,0);
  char path[256]; snprintf(path,sizeof path,"\\\\.\\pipe\\%s",listen);
  printf("apiscale: %s -> %s   %dx%d -> %dx%d\n",listen,up,sw,sh,dw,dh);
  DWORD t0=GetTickCount();
  while((GetTickCount()-t0)<(DWORD)secs*1000){
    HANDLE cl=CreateNamedPipeA(path,PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT,255,65536,65536,3000,NULL);
    if(cl==INVALID_HANDLE_VALUE){ Sleep(200); continue; }
    BOOL con=ConnectNamedPipe(cl,NULL);
    if(!con && GetLastError()!=ERROR_PIPE_CONNECTED){ CloseHandle(cl); continue; }
    HANDLE us=up_open(up);
    if(us==INVALID_HANDLE_VALUE){ CloseHandle(cl); Sleep(200); continue; }
    for(;;){
      char rb[65536]; DWORD rd=0;
      if(!ReadFile(cl,rb,sizeof rb-1,&rd,NULL)||!rd) break;
      rb[rd]=0;
      char out[65536]; DWORD outlen=rd;
      memcpy(out,rb,rd);
      /* command on line 1, one argument per following line */
      char cmd[64]={0}; int i=0;
      while(rb[i] && rb[i]!='\n' && i<63){ cmd[i]=rb[i]; i++; }
      if(!strcmp(cmd,"getPixelColor")||!strcmp(cmd,"inputClick")||!strcmp(cmd,"inputMove")){
        int x=0,y=0; const char*p=rb+i;
        if(*p=='\n') p++;
        x=atoi(p);
        const char*q=strchr(p,'\n');
        if(q){ y=atoi(q+1);
          int nx=scale_coord(x,sw,dw), ny=scale_coord(y,sh,dh);
          outlen=(DWORD)snprintf(out,sizeof out,"%s\n%d\n%d\n",cmd,nx,ny);
        }
      }
      DWORD wr=0;
      if(!WriteFile(us,out,outlen,&wr,NULL)) break;
      char sb[65536]; DWORD sd=0;
      if(!ReadFile(us,sb,sizeof sb,&sd,NULL)||!sd) break;
      if(getenv("APISCALE_LOG")){
        SYSTEMTIME st; GetLocalTime(&st);
        printf("%02d:%02d:%02d.%03d in[",st.wHour,st.wMinute,st.wSecond,st.wMilliseconds);
        for(DWORD k=0;k<rd&&k<80;k++) putchar(rb[k]=='\n'?'|':rb[k]);
        printf("] out[");
        for(DWORD k=0;k<outlen&&k<80;k++) putchar(out[k]=='\n'?'|':out[k]);
        printf("] rsp[");
        for(DWORD k=0;k<sd&&k<60;k++) putchar(sb[k]=='\n'?'|':sb[k]);
        printf("]\n");
      }
      if(!WriteFile(cl,sb,sd,&wr,NULL)) break;
    }
    CloseHandle(us); DisconnectNamedPipe(cl); CloseHandle(cl);
  }
  return 0; }
int main(int argc,char**argv){
  if(argc<2){fprintf(stderr,"usage\n");return 1;}
  if(!strcmp(argv[1],"list")){ EnumWindows(enum_list,0); return 0; }
  if(!strcmp(argv[1],"cursor")) return do_cursor();
  if(!strcmp(argv[1],"curtest")) return do_curtest();
  if(!strcmp(argv[1],"pipesrv")&&argc>=4) return do_pipesrv(argv[2],atoi(argv[3]));
  if(!strcmp(argv[1],"apisrv")&&argc>=4) return do_apisrv(argv[2],atoi(argv[3]));
  if(!strcmp(argv[1],"apiproxy")&&argc>=5) return do_apiproxy(argv[2],argv[3],atoi(argv[4]));
  if(!strcmp(argv[1],"apiscale")&&argc>=9) return do_apiscale(argv[2],argv[3],atoi(argv[4]),atoi(argv[5]),atoi(argv[6]),atoi(argv[7]),atoi(argv[8]));
  if(!strcmp(argv[1],"pipecli")&&argc>=3) return do_pipecli(argv[2]);
  if(!strcmp(argv[1],"pipecmd")&&argc>=4) return do_pipecmd(argv[2],argv[3]);
  if(!strcmp(argv[1],"pipecmd2")&&argc>=4) return do_pipecmd2(argv[2],argc,argv,3);
  if(!strcmp(argv[1],"pipes")) return do_pipes(argc>2?argv[2]:NULL);
  if(!strcmp(argv[1],"mods")&&argc>=3) return do_mods((DWORD)strtoul(argv[2],NULL,0));
  if(!strcmp(argv[1],"rpm")&&argc>=5) return do_rpm((DWORD)strtoul(argv[2],NULL,0),(ULONG_PTR)strtoull(argv[3],NULL,0),(SIZE_T)strtoull(argv[4],NULL,0));
  if(!strcmp(argv[1],"listall")){ EnumWindows(enum_all,0); return 0; }
  if(!strcmp(argv[1],"fgq")) return do_fgq();
  if(!strcmp(argv[1],"dpi")) return do_dpi();
  if(!strcmp(argv[1],"pin")&&argc>=4) return do_pin(argv[2],atoi(argv[3]));
  if(!strcmp(argv[1],"winwatch")&&argc>=4) return do_winwatch(argv[2],atoi(argv[3]));
  if(!strcmp(argv[1],"fgwatch")&&argc>=3) return do_fgwatch(atoi(argv[2]));
  if(argc<3){fprintf(stderr,"need window\n");return 1;}
  HWND h=resolve(argv[2]); if(!h){fprintf(stderr,"window not found: %s\n",argv[2]);return 4;}
  if(!strcmp(argv[1],"detach")){ LONG st=GetWindowLongA(h,GWL_STYLE); st&=~WS_CHILD; st|=WS_POPUP; SetWindowLongA(h,GWL_STYLE,st); HWND r=SetParent(h,NULL); SetWindowPos(h,HWND_TOP,60,60,0,0,SWP_NOSIZE|SWP_FRAMECHANGED|SWP_SHOWWINDOW); printf("detached %p (old parent %p) err=%lu\n",h,r,(unsigned long)GetLastError()); return 0; }
  if(!strcmp(argv[1],"show")){ ShowWindow(h,SW_SHOW); printf("shown\n"); return 0; }
  if(!strcmp(argv[1],"fg")) return do_foreground(h);
  if(!strcmp(argv[1],"find")){ RECT r; GetWindowRect(h,&r); printf("hwnd=%p rect=%ld,%ld,%ld,%ld\n",h,r.left,r.top,r.right,r.bottom); return 0; }
  if(!strcmp(argv[1],"shot")&&argc>=4) return shot(h,argv[3]);
  if(!strcmp(argv[1],"click")&&argc>=5) return click(h,atoi(argv[3]),atoi(argv[4]));
  if(!strcmp(argv[1],"sclick")&&argc>=5) return sclick(h,atoi(argv[3]),atoi(argv[4]));
  if(!strcmp(argv[1],"click2")&&argc>=5) return click2(h,atoi(argv[3]),atoi(argv[4]));
  if(!strcmp(argv[1],"wheel")&&argc>=6) return hwwheel(h,atoi(argv[3]),atoi(argv[4]),atoi(argv[5]));
  if(!strcmp(argv[1],"hwclick")&&argc>=5) return hwclick(h,atoi(argv[3]),atoi(argv[4]));
  if(!strcmp(argv[1],"move")&&argc>=5){ SetWindowPos(h,NULL,atoi(argv[3]),atoi(argv[4]),0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE); printf("moved\n"); return 0; }
  if(!strcmp(argv[1],"text")&&argc>=4){ for(const char*c=argv[3];*c;c++){ PostMessageA(h,WM_CHAR,(WPARAM)(unsigned char)*c,1); Sleep(20);} printf("typed\n"); return 0; }
  if(!strcmp(argv[1],"key")&&argc>=4){ int vk=atoi(argv[3]); PostMessageA(h,WM_KEYDOWN,vk,1); Sleep(40); PostMessageA(h,WM_KEYUP,vk,(LPARAM)(1|(1u<<30)|(1u<<31))); printf("key %d\n",vk); return 0; }
  fprintf(stderr,"bad command\n"); return 1; }
