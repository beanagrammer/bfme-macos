#!/bin/zsh
# Launch reliability check using wined3d's fps counter (no Arena add-on needed).
# Usage: launch-check.sh <outdir> <n>   [env: TOPO]
set -u
OUT="${1:?}"; N="${2:-10}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME; G="$HOME/.wine-aio-custom/drive_c/BFME1"
ok=0; times=()
for i in $(seq 1 $N); do
  pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 2
  L="$OUT/l$i.log"; S=$(date +%s)
  ( cd "$G" && WINE_CPU_TOPOLOGY="${TOPO:-off}" WINEDEBUG="+fps" "$P/run-custom-wine.sh" "$G/lotrbfme.exe" -noshellmap > "$L" 2>&1 & )
  res="TIMEOUT"
  for w in $(seq 1 60); do
    sleep 1
    grep -qa "fps" "$L" 2>/dev/null && { res="OK"; break; }
    pgrep -f lotrbfme.exe >/dev/null || { res="DIED"; break; }
  done
  E=$(( $(date +%s) - S ))
  [ "$res" = "OK" ] && { ok=$((ok+1)); times+=($E); }
  echo "  $i: $res ${E}s"
done
pkill -9 -f lotrbfme.exe 2>/dev/null
echo "== $ok/$N rendered within 60s; times: ${times[*]}"
