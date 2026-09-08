#!/bin/zsh
# Timed skirmish load that verifies every step instead of assuming it worked.
#  - waits for the main menu: correct signature, STABLE, and wined3d actually presenting
#  - after each click, requires the screen to visibly change (proof the click landed)
#  - "in-game" requires frac>0.93 AND unlike the splash artwork
# Usage: skirmish-timer3.sh <outdir> <label>   [env: EXTRA, TOPO]
set -u
OUT="${1:?}"; LABEL="${2:-run}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
G="$HOME/.wine-aio-custom/drive_c/BFME1"; LOG="$OUT/${LABEL}.log"; PH="$OUT/${LABEL}_phases.txt"
W="Battle for Middle-earth"; : > "$PH"
alive(){ pgrep -f lotrbfme.exe >/dev/null; }
fpsn(){ local c; c=$(grep -ac "approx" "$LOG" 2>/dev/null); [ -z "$c" ] && c=0; echo "$c"; }
cap(){ local f="$1" rect; rect=$("$P/tools/gamerect.sh" 2>/dev/null); [ -z "$rect" ] && return 1
       screencapture -x -R"$rect" "$f" 2>/dev/null; }
stats(){ python3 "$IS" stats "$1" 2>/dev/null; }
dif(){ python3 "$IS" diff "$1" "$2" 2>/dev/null | sed 's/diff=//'; }
note(){ echo "   $*" >> "$PH"; }

pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 2
pkill -9 -f "build-wine/server/wineserver" 2>/dev/null; sleep 2
( cd "$G" && WINE_CPU_TOPOLOGY="${TOPO:-off}" WINEDEBUG="+fps" "$R" "$G/lotrbfme.exe" -noshellmap ${=EXTRA:-} > "$LOG" 2>&1 & )

# --- wait for a STABLE main menu that is genuinely rendering ---
prev=""; stable=0; menu=0
for w in $(seq 1 120); do
  sleep 2; alive || { echo "$LABEL: died before menu"; exit 1; }
  cap "$OUT/m.png" || continue
  s=$(stats "$OUT/m.png"); f=$(echo "$s" | sed 's/.*frac=\([0-9.]*\).*/\1/')
  d=$(dif "$P/tools/splash-ref.png" "$OUT/m.png")
  [ -z "$f" ] && continue
  note "menu-wait $(( w*2 ))s $s diff=$d fps=$(fpsn)"
  if [ "$(echo "$f > 0.10 && $f < 0.40 && $d > 40" | bc -l)" = "1" ] && [ "$(fpsn)" -gt 0 ]; then
    [ "$s" = "$prev" ] && stable=$(( stable + 1 )) || stable=0
    [ $stable -ge 2 ] && { menu=1; break; }
  else stable=0; fi
  prev="$s"
done
[ $menu -eq 0 ] && { echo "$LABEL: main menu never appeared"; pkill -9 -f lotrbfme.exe; exit 1; }
echo "$LABEL: main menu confirmed (rendering, stable)"

# --- click, and require the screen to change ---
step(){ local x=$1 y=$2 name="$3"
  cap "$OUT/before.png"
  "$R" "$T" hwclick "$W" "$x" "$y" >/dev/null 2>&1
  for k in $(seq 1 15); do
    sleep 2; cap "$OUT/after.png" || continue
    local dd=$(dif "$OUT/before.png" "$OUT/after.png")
    [ -z "$dd" ] && continue
    if [ "$(echo "$dd > 1.5" | bc -l)" = "1" ]; then note "$name: screen changed (diff=$dd)"; return 0; fi
  done
  note "$name: NO screen change"; return 1; }

step 185 858 "SOLO PLAY" || { echo "$LABEL: SOLO PLAY click did nothing"; pkill -9 -f lotrbfme.exe; exit 1; }
step 649 860 "SKIRMISH"  || { echo "$LABEL: SKIRMISH click did nothing"; pkill -9 -f lotrbfme.exe; exit 1; }
F0=$(fpsn); START=$(date +%s)
"$R" "$T" hwclick "$W" 667 855 >/dev/null 2>&1
note "START GAME clicked"
LOADED=0
for w in $(seq 1 200); do
  sleep 5; alive || { echo "$LABEL: CRASHED during load"; exit 1; }
  cap "$OUT/${LABEL}_s.png" || continue
  s=$(stats "$OUT/${LABEL}_s.png"); f=$(echo "$s" | sed 's/.*frac=\([0-9.]*\).*/\1/')
  d=$(dif "$P/tools/splash-ref.png" "$OUT/${LABEL}_s.png"); E=$(( $(date +%s) - START ))
  note "load t=${E}s $s diff=$d"
  [ -z "$f" ] && continue
  [ "$(echo "$f > 0.93 && $d > 25" | bc -l)" = "1" ] && { LOADED=$E; break; }
done
[ $LOADED -eq 0 ] && { echo "$LABEL: never reached gameplay"; pkill -9 -f lotrbfme.exe; exit 1; }
sleep 20; F1=$(fpsn)
[ "$F1" -le "$F0" ] && { echo "$LABEL: REJECTED, no new frames ($F0 -> $F1)"; pkill -9 -f lotrbfme.exe; exit 1; }
FPS=$(grep -ao "approx [0-9.]*fps" "$LOG" | tail -6 | sed 's/approx //;s/fps//' | awk '{s+=$1;n++} END{if(n)printf "%.1f",s/n}')
cp "$OUT/${LABEL}_s.png" "$OUT/${LABEL}_proof.png" 2>/dev/null
echo "$LABEL: LOAD ${LOADED}s   in-game ${FPS} fps   (frames $F0 -> $F1)"
pkill -9 -f lotrbfme.exe 2>/dev/null
