#!/bin/zsh
# Stricter launch benchmark: a launch only counts when the main menu is actually
# VISIBLE on screen, not merely when the D3D9 hook reports its first presented frame.
# Usage: launch-bench2.sh <outdir> <iterations> [label]
set -u
OUT="${1:?}"; N="${2:-10}"; LABEL="${3:-run}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; BR="$P/tools/brightness.py"
SCR=/private/tmp/claude-501/-Users-beanagrammer-Projects-BFME/8c03f450-31ff-4a41-8e2b-1eb8d873da5e/scratchpad
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
GUID="benchben-1111-4000-8000-000000000001"
DEADLINE="${DEADLINE:-60}"
MINFRAC="${MINFRAC:-0.08}"
cp "$SCR/addon.dll" "$G/dinput8.dll"; printf '%s' "$GUID" > "$G/arena_api_interface.conf"

ok=0; ftimes=(); mtimes=()
echo "# $LABEL  deadline=${DEADLINE}s  menu threshold bright_frac>$MINFRAC  n=$N" | tee "$OUT/summary.txt"
for i in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 1
  pkill -9 -f lotrbfme.exe 2>/dev/null; pkill -9 -f "wintool.exe pin" 2>/dev/null
  for _w in 1 2 3 4 5 6 7 8 9 10; do pgrep -f lotrbfme.exe >/dev/null || break; sleep 1; pkill -9 -f lotrbfme.exe 2>/dev/null; done
  pgrep -f lotrbfme.exe >/dev/null && { echo "  $i: SKIPPED (stuck instance)" | tee -a "$OUT/summary.txt"; continue; }
  sleep 1; : > "$AL"
  START=$(date +%s)
  ( cd "$G" && "$R" "$G/lotrbfme.exe" -noshellmap > "$OUT/${LABEL}_$i.log" 2>&1 & )
  ( "$R" "$T" pin "lotrbfme" $(( DEADLINE + 15 )) ) > "$OUT/pin_${LABEL}_$i.log" 2>&1 &
  tf=""; tm=""; res="TIMEOUT"
  while :; do
    el=$(( $(date +%s) - START ))
    [ $el -ge $DEADLINE ] && break
    if ! pgrep -f lotrbfme.exe >/dev/null; then res="DIED"; break; fi
    if [ -z "$tf" ] && grep -qa 'first frame presented' "$AL" 2>/dev/null; then tf=$el; fi
    if [ -n "$tf" ]; then
      screencapture -x -R0,33,1280,720 "$OUT/shot_${LABEL}_$i.png" 2>/dev/null
      FRAC=$(python3 "$BR" "$OUT/shot_${LABEL}_$i.png" 2>/dev/null | sed -n 's/.*bright_frac=\([0-9.]*\).*/\1/p')
      if [ -n "$FRAC" ] && [ "$(echo "$FRAC > $MINFRAC" | bc -l 2>/dev/null)" = "1" ]; then
        tm=$el; res="OK"
        cp "$OUT/shot_${LABEL}_$i.png" "$OUT/menu_${LABEL}_$i.png" 2>/dev/null
        break
      fi
    fi
    sleep 1
  done
  pkill -9 -f "wintool.exe pin" 2>/dev/null
  if [ "$res" = "OK" ]; then ok=$(( ok + 1 )); ftimes+=($tf); mtimes+=($tm); fi
  echo "  $i: $res  first_frame=${tf:--}s  menu_visible=${tm:--}s" | tee -a "$OUT/summary.txt"
done
pkill -9 -f lotrbfme.exe 2>/dev/null
echo "== $LABEL: $ok/$N reached a VISIBLE menu within ${DEADLINE}s" | tee -a "$OUT/summary.txt"
echo "   first-frame times: ${ftimes[*]}" | tee -a "$OUT/summary.txt"
echo "   menu-visible times: ${mtimes[*]}" | tee -a "$OUT/summary.txt"
