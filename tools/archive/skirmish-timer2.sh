#!/bin/zsh
# Timed skirmish load with a detector that cannot false-positive:
#   * capture the GAME WINDOW's real bounds, never a fixed screen region
#   * require the game process to still be alive
#   * require wined3d to be presenting frames (fps lines advancing)
# Usage: skirmish-timer2.sh <outdir> <label>   [env: EXTRA="-flags", TOPO]
set -u
OUT="${1:?}"; LABEL="${2:-run}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
G="$HOME/.wine-aio-custom/drive_c/BFME1"; LOG="$OUT/${LABEL}.log"
W="Battle for Middle-earth"
click(){ "$R" "$T" hwclick "$W" "$1" "$2" >/dev/null 2>&1; }
alive(){ pgrep -f lotrbfme.exe >/dev/null; }
fpscount(){ local c; c=$(grep -ac "approx" "$LOG" 2>/dev/null); [ -z "$c" ] && c=0; echo "$c"; }
# capture the game window; prints "" if there is no game window to capture
gshot(){ local f="$1" rect
  rect=$("$P/tools/gamerect.sh" 2>/dev/null) || return 1
  [ -z "$rect" ] && return 1
  screencapture -x -R"$rect" "$f" 2>/dev/null || return 1
  python3 "$IS" stats "$f" 2>/dev/null | sed 's/mean=\([0-9.]*\).*/\1/'; }

pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 2
pkill -9 -f "build-wine/server/wineserver" 2>/dev/null; sleep 2
( cd "$G" && WINE_CPU_TOPOLOGY="${TOPO:-off}" WINEDEBUG="+fps" "$R" "$G/lotrbfme.exe" -noshellmap ${=EXTRA:-} > "$LOG" 2>&1 & )

for w in $(seq 1 60); do sleep 2
  M=$(gshot "$OUT/${LABEL}_menu.png") || continue
  [ -n "$M" ] && [ "$(echo "$M > 15 && $M < 60" | bc -l)" = "1" ] && break
done
alive || { echo "$LABEL: died before the menu"; exit 1; }
echo "$LABEL: menu up (fps lines so far: $(fpscount))"
click 185 858; sleep 6
click 649 860; sleep 10
alive || { echo "$LABEL: died during navigation"; exit 1; }
F0=$(fpscount); START=$(date +%s)
click 667 855
LOADED=0
for w in $(seq 1 200); do
  sleep 5
  if ! alive; then echo "$LABEL: CRASHED ${$(( $(date +%s) - START ))}s into the load"; exit 1; fi
  gshot "$OUT/${LABEL}_s.png" >/dev/null 2>&1 || continue   # no game window -> keep waiting
  ST=$(python3 "$IS" stats "$OUT/${LABEL}_s.png" 2>/dev/null)
  MEAN=$(echo "$ST" | sed 's/mean=\([0-9.]*\).*/\1/')
  FRAC=$(echo "$ST" | sed 's/.*frac=\([0-9.]*\).*/\1/')
  DIFF=$(python3 "$IS" diff "$P/tools/splash-ref.png" "$OUT/${LABEL}_s.png" 2>/dev/null | sed 's/diff=//')
  E=$(( $(date +%s) - START ))
  echo "   t=${E}s mean=$MEAN frac=$FRAC diff=$DIFF" >> "$OUT/${LABEL}_phases.txt"
  [ -z "$FRAC" ] && continue
  # in-game only: near-fully bright AND not the splash artwork
  if [ "$(echo "$FRAC > 0.93 && $DIFF > 25" | bc -l)" = "1" ]; then LOADED=$E; break; fi
done
[ $LOADED -eq 0 ] && { echo "$LABEL: never loaded"; pkill -9 -f lotrbfme.exe; exit 1; }
sleep 20
F1=$(fpscount)
alive || { echo "$LABEL: loaded in ${LOADED}s but then died"; exit 1; }
if [ "$F1" -le "$F0" ]; then echo "$LABEL: REJECTED - screen looked loaded at ${LOADED}s but wined3d presented no new frames ($F0 -> $F1)"; pkill -9 -f lotrbfme.exe; exit 1; fi
FPS=$(grep -ao "approx [0-9.]*fps" "$LOG" | tail -6 | sed 's/approx //;s/fps//' | awk '{s+=$1;n++} END{if(n)printf "%.1f",s/n}')
echo "$LABEL: LOAD ${LOADED}s   in-game ${FPS} fps   (frames verified: $F0 -> $F1)"
cp "$OUT/${LABEL}_s.png" "$OUT/${LABEL}_proof.png" 2>/dev/null
pkill -9 -f lotrbfme.exe 2>/dev/null
