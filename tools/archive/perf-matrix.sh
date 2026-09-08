#!/bin/zsh
# Compare menu frame rate across the two legacy crash workarounds, using wined3d's
# built-in fps counter (WINEDEBUG=+fps) so no Arena add-on is needed.
# Usage: perf-matrix.sh <outdir>
set -u
OUT="${1:?}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"
G="$HOME/.wine-aio-custom/drive_c/BFME1"

setcsmt(){ python3 - "$1" <<'PY'
import sys
v=int(sys.argv[1])
p='/Users/beanagrammer/.wine-aio-custom/user.reg'
s=open(p,encoding='utf-8',errors='surrogateescape').read().split('\n')
out=[];sec=None
for ln in s:
    if ln.startswith('['): sec=ln
    if sec and sec.startswith('[Software\\\\Wine\\\\Direct3D') and ln.startswith('"csmt"='):
        ln='"csmt"=dword:%08x'%v
    out.append(ln)
open(p,'w',encoding='utf-8',errors='surrogateescape').write('\n'.join(out))
PY
}
cleanup(){ pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 2
           pkill -9 -f "build-wine/server/wineserver" 2>/dev/null; sleep 2; }

run(){ local label="$1" topo="$2" csmt="$3" log="$OUT/${label}.log"
  cleanup; setcsmt "$csmt"
  ( cd "$G" && WINE_CPU_TOPOLOGY="$topo" WINEDEBUG="+fps" "$R" "$G/lotrbfme.exe" -noshellmap > "$log" 2>&1 & )
  local up=0
  for w in $(seq 1 45); do
    sleep 2
    grep -qa "fps" "$log" 2>/dev/null && { up=1; break; }
    pgrep -f lotrbfme.exe >/dev/null || break
  done
  if [ $up -eq 0 ]; then echo "$label (topology=$topo csmt=$csmt): FAILED to render"; cleanup; return; fi
  sleep 25   # let it settle on the menu
  local vals=$(grep -ao "approx [0-9.]*fps" "$log" | tail -12 | sed 's/approx //;s/fps//' | tr '\n' ' ')
  local avg=$(echo "$vals" | tr ' ' '\n' | grep -v '^$' | awk '{s+=$1;n++} END{if(n)printf "%.1f",s/n}')
  echo "$label (topology=$topo csmt=$csmt): avg ${avg} fps   samples: $vals"
  cleanup
}
run "A_baseline_1core_nocsmt" "1:0" 0
run "B_allcores_nocsmt"       "off" 0
run "C_1core_csmt"            "1:0" 1
run "D_allcores_csmt"         "off" 1
