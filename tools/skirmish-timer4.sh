#!/bin/zsh
# Verified skirmish load timer. Everything here is a lesson from a wrong measurement:
#  - captures the game WINDOW by CGWindowID, never a screen region (no stale/other windows)
#  - does NOT kill wineserver (that cold start costs ~90s and is not the game's fault)
#  - waits for wined3d to actually present frames before believing any screenshot
#  - checks the skirmish-setup signature so a mis-click cannot masquerade as success
#  - requires frames to advance across the load
# Usage: skirmish-timer4.sh <outdir> <label>   [env: EXTRA, TOPO]
set -u
OUT="${1:?}"; LABEL="${2:-run}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
G="$HOME/.wine-aio-custom/drive_c/BFME1"; LOG="$OUT/${LABEL}.log"; PH="$OUT/${LABEL}_phases.txt"
W="Battle for Middle-earth"; : > "$PH"
SW="${SCRW:-1600}"
sx(){ echo $(( $1 * SW / 1600 )); }
alive(){ pgrep -f lotrbfme.exe >/dev/null; }
fpsn(){ local c; c=$(grep -ac approx "$LOG" 2>/dev/null); [ -z "$c" ] && c=0; echo "$c"; }
winid(){ "$P/tools/winlist" 2>/dev/null | grep -i "$W" | grep -vi arena | head -1 | sed 's/id=\([0-9]*\).*/\1/'; }
snap(){ local id=$(winid); [ -z "$id" ] && return 1
        screencapture -x -o -l "$id" "$1" 2>/dev/null || return 1
        python3 "$IS" stats "$1" 2>/dev/null; }
frac(){ echo "$1" | sed 's/.*frac=\([0-9.]*\).*/\1/'; }

pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 3
( cd "$G" && WINE_CPU_TOPOLOGY="${TOPO:-off}" WINEDEBUG="+fps" "$R" "$G/lotrbfme.exe" -noshellmap ${=EXTRA:-} > "$LOG" 2>&1 & )
LT=$(date +%s)
for w in $(seq 1 150); do sleep 2; alive || { echo "$LABEL: died at boot"; exit 1; }
  [ "$(fpsn)" -gt 3 ] && break; done
[ "$(fpsn)" -le 3 ] && { echo "$LABEL: never presented a frame"; pkill -9 -f lotrbfme.exe; exit 1; }
echo "$LABEL: first frames after $(( $(date +%s) - LT ))s"
for w in $(seq 1 60); do sleep 3; s=$(snap "$OUT/menu.png") || continue
  f=$(frac "$s"); [ -n "$f" ] && [ "$(echo "$f > 0.10 && $f < 0.40" | bc -l)" = "1" ] && break; done
echo "$LABEL: main menu ($s)"
"$R" "$T" hwclick "$W" $(sx 185) $(sx 858) >/dev/null 2>&1; sleep 7
"$R" "$T" hwclick "$W" $(sx 649) $(sx 860) >/dev/null 2>&1; sleep 14
s=$(snap "$OUT/setup.png"); f=$(frac "$s")
# The setup screen reads brighter at 2560x1440 with UltraHigh textures (0.40-0.41)
# than it did at the resolution this was first calibrated on, hence the wider band.
if [ -z "$f" ] || [ "$(echo "$f > 0.20 && $f < 0.45" | bc -l)" != "1" ]; then
  echo "$LABEL: skirmish setup NOT reached ($s)"; pkill -9 -f lotrbfme.exe; exit 1; fi
echo "$LABEL: skirmish setup confirmed ($s)"
F0=$(fpsn); "$R" "$T" hwclick "$W" $(sx 667) $(sx 857) >/dev/null 2>&1; T0=$(perl -MTime::HiRes=time -e "print time()")
LOADED=0
for w in $(seq 1 2400); do
  perl -e "select undef,undef,undef,0.15"; alive || { echo "$LABEL: CRASHED during load"; exit 1; }
  s=$(snap "$OUT/${LABEL}_s.png") || continue
  f=$(frac "$s"); E=$(perl -MTime::HiRes=time -e "printf(\"%.2f\", time()-$T0)"); echo "t=${E}s $s" >> "$PH"
  [ -n "$f" ] && [ "$(echo "$f > 0.85" | bc -l)" = "1" ] && { LOADED=$E; break; }
done
[ "$LOADED" = "0" ] && { echo "$LABEL: never reached gameplay"; pkill -9 -f lotrbfme.exe; exit 1; }   # LOADED is fractional seconds, not an integer
sleep 20; F1=$(fpsn)
[ "$F1" -le "$F0" ] && { echo "$LABEL: REJECTED, frames did not advance"; pkill -9 -f lotrbfme.exe; exit 1; }
FPS=$(grep -ao "approx [0-9.]*fps" "$LOG" | tail -6 | sed 's/approx //;s/fps//' | awk '{s+=$1;n++} END{if(n)printf "%.1f",s/n}')
cp "$OUT/${LABEL}_s.png" "$OUT/${LABEL}_proof.png" 2>/dev/null
echo "$LABEL: LOAD ${LOADED}s   in-game ${FPS} fps   (frames $F0 -> $F1)"
pkill -9 -f lotrbfme.exe 2>/dev/null
