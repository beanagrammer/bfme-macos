#!/bin/zsh
# Launch BFME, drive it into a skirmish, and report map load time + steady-state fps.
# Uses wined3d's own fps counter (WINEDEBUG=+fps); no Arena add-on needed.
# Usage: skirmish-timer.sh <outdir> [label]
set -u
OUT="${1:?}"; LABEL="${2:-run}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
G="$HOME/.wine-aio-custom/drive_c/BFME1"
LOG="$OUT/${LABEL}.log"
W="Battle for Middle-earth"
click(){ "$R" "$T" hwclick "$W" "$1" "$2" >/dev/null 2>&1; }
shot(){ screencapture -x -R0,33,1600,900 "$OUT/${LABEL}_s.png" 2>/dev/null
        python3 "$IS" stats "$OUT/${LABEL}_s.png" 2>/dev/null | sed 's/mean=\([0-9.]*\).*/\1/'; }

pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 2
pkill -9 -f "build-wine/server/wineserver" 2>/dev/null; sleep 2
( cd "$G" && WINE_CPU_TOPOLOGY="${TOPO:-off}" WINEDEBUG="+fps" "$R" "$G/lotrbfme.exe" -noshellmap ${=EXTRA:-} > "$LOG" 2>&1 & )

# wait for the main menu
for w in $(seq 1 60); do sleep 2; M=$(shot); [ -n "$M" ] && [ "$(echo "$M > 15 && $M < 60" | bc -l)" = "1" ] && break; done
echo "$LABEL: menu up"
click 185 858; sleep 6      # SOLO PLAY
click 649 860; sleep 10     # SKIRMISH
START=$(date +%s)
click 667 855               # START GAME
LOADED=0
for w in $(seq 1 180); do
  sleep 5
  M=$(shot)
  if [ -n "$M" ] && [ "$(echo "$M > 60" | bc -l)" = "1" ]; then LOADED=$(( $(date +%s) - START )); break; fi
  pgrep -f lotrbfme.exe >/dev/null || break
done
if [ $LOADED -eq 0 ]; then echo "$LABEL: never loaded"; pkill -9 -f lotrbfme.exe; exit 1; fi
sleep 25
FPS=$(grep -ao "approx [0-9.]*fps" "$LOG" | tail -6 | sed 's/approx //;s/fps//' | awk '{s+=$1;n++} END{if(n)printf "%.1f",s/n}')
echo "$LABEL: LOAD ${LOADED}s   in-game ${FPS} fps"
pkill -9 -f lotrbfme.exe 2>/dev/null
