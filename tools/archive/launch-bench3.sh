#!/bin/zsh
# Launch benchmark with the strictest bar: the interactive MAIN MENU must be on screen.
# Distinguishes three stages -- first presented frame, splash screen, main menu --
# because the splash is a static image that would otherwise pass a brightness test.
# Usage: launch-bench3.sh <outdir> <iterations> [label]
set -u
OUT="${1:?}"; N="${2:-10}"; LABEL="${3:-run}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
REF="$P/tools/splash-ref.png"
SCR=/private/tmp/claude-501/-Users-beanagrammer-Projects-BFME/8c03f450-31ff-4a41-8e2b-1eb8d873da5e/scratchpad
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
GUID="benchben-1111-4000-8000-000000000001"
DEADLINE="${DEADLINE:-60}"
cp "$SCR/addon.dll" "$G/dinput8.dll"; printf '%s' "$GUID" > "$G/arena_api_interface.conf"

ok=0; mtimes=()
echo "# $LABEL  deadline=${DEADLINE}s  main-menu = (frac>0.05 and diff-from-splash>25)  n=$N" | tee "$OUT/summary.txt"
for i in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 1
  pkill -9 -f lotrbfme.exe 2>/dev/null; pkill -9 -f "wintool.exe pin" 2>/dev/null
  for _w in $(seq 1 10); do pgrep -f lotrbfme.exe >/dev/null || break; sleep 1; pkill -9 -f lotrbfme.exe 2>/dev/null; done
  pgrep -f lotrbfme.exe >/dev/null && { echo "  $i: SKIPPED (stuck instance)" | tee -a "$OUT/summary.txt"; continue; }
  sleep 1; : > "$AL"
  START=$(date +%s)
  ( cd "$G" && "$R" "$G/lotrbfme.exe" -noshellmap > "$OUT/${LABEL}_$i.log" 2>&1 & )
  ( "$R" "$T" pin "lotrbfme" $(( DEADLINE + 15 )) ) > "$OUT/pin_${LABEL}_$i.log" 2>&1 &
  tf=""; ts=""; tm=""; res="TIMEOUT"
  while :; do
    el=$(( $(date +%s) - START ))
    [ $el -ge $DEADLINE ] && break
    if ! pgrep -f lotrbfme.exe >/dev/null; then res="DIED"; break; fi
    [ -z "$tf" ] && grep -qa 'first frame presented' "$AL" 2>/dev/null && tf=$el
    if [ -n "$tf" ]; then
      SHOT="$OUT/shot_${LABEL}_$i.png"
      RECT=$("$P/tools/gamerect.sh" 2>/dev/null)
      [ -z "$RECT" ] && { sleep 1; continue; }
      screencapture -x -R"$RECT" "$SHOT" 2>/dev/null
      FRAC=$(python3 "$IS" stats "$SHOT" 2>/dev/null | sed -n 's/.*frac=\([0-9.-]*\).*/\1/p')
      DIFF=$(python3 "$IS" diff "$REF" "$SHOT" 2>/dev/null | sed -n 's/diff=\([0-9.-]*\)/\1/p')
      if [ -n "$FRAC" ] && [ -n "$DIFF" ]; then
        if [ -z "$ts" ] && [ "$(echo "$DIFF < 10" | bc -l)" = "1" ]; then ts=$el; fi
        if [ "$(echo "$FRAC > 0.05 && $DIFF > 25" | bc -l)" = "1" ]; then
          tm=$el; res="OK"; cp "$SHOT" "$OUT/mainmenu_${LABEL}_$i.png" 2>/dev/null; break
        fi
      fi
    fi
    sleep 1
  done
  pkill -9 -f "wintool.exe pin" 2>/dev/null
  [ "$res" = "OK" ] && { ok=$(( ok + 1 )); mtimes+=($tm); }
  echo "  $i: $res  first_frame=${tf:--}s  splash=${ts:--}s  main_menu=${tm:--}s" | tee -a "$OUT/summary.txt"
done
pkill -9 -f lotrbfme.exe 2>/dev/null
echo "== $LABEL: $ok/$N reached the MAIN MENU within ${DEADLINE}s" | tee -a "$OUT/summary.txt"
echo "   main-menu times: ${mtimes[*]}" | tee -a "$OUT/summary.txt"
