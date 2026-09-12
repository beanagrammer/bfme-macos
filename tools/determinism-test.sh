#!/bin/zsh
# Does BFME's simulation depend on the x87 JIT?
#
# A desync means two clients computed different physics from the same inputs.
# That can be tested with ONE machine if the game is deterministic run to run:
# start the same skirmish, touch nothing, and compare the screen at the same
# in-game time. The AI moves units, so any divergence shows up as units in
# different places.
#
# Both modes hold above the engine's fixed 30 Hz logic rate (38.5 fps with the
# JIT, 33.8 without), so elapsed in-game seconds map to the same logic frame in
# both. The control run is what makes this valid: two runs in the SAME mode must
# agree, or the game is not deterministic and the comparison means nothing.
#
# STATUS: the control works, the comparison does not yet.
#
# Two runs in the same mode give a pixel-identical HUD at the same offset, so
# the simulation IS deterministic and the HUD is a valid signal. But the timer
# starts on a brightness threshold, and that fires at a different point in the
# opening camera pan depending on how fast the game loaded. The no-JIT run
# therefore samples a different logic frame -- 1090 resources against 1150 --
# and resources accrue with time, so that difference is start offset, not
# divergence. Its camera was somewhere else entirely too.
#
# To make it decisive the sample has to be synchronised on a simulation
# milestone rather than a wall clock: wait until the resource counter reads a
# specific value in both runs, then compare the minimap, which shows unit
# positions and does not move with the camera.
#
# Usage: SCRW=2560 determinism-test.sh <outdir> <label> <seconds> [nojit]
set -u
OUT="${1:?}"; LABEL="${2:?}"; PLAY="${3:-60}"; MODE="${4:-jit}"
mkdir -p "$OUT"
P="${0:A:h:h}"
T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
A="$HOME/.wine-aio-custom"; G="$A/drive_c/BFME1"; LOG="$OUT/$LABEL.log"
W="Battle for Middle-earth"; SW="${SCRW:-2560}"
sx(){ echo $(( $1 * SW / 1600 )); }
alive(){ pgrep -f lotrbfme.exe >/dev/null; }
fpsn(){ local c; c=$(grep -ac approx "$LOG" 2>/dev/null); [ -z "$c" ] && c=0; echo "$c"; }
winid(){ "$P/tools/winlist" 2>/dev/null | grep -i "$W" | grep -vi arena | head -1 | sed -n 's/^id=\([0-9]*\).*/\1/p'; }
snap(){ local id=$(winid); [ -z "$id" ] && return 1
        screencapture -x -o -l "$id" "$1" 2>/dev/null || return 1
        python3 "$IS" stats "$1" 2>/dev/null; }
frac(){ echo "$1" | sed 's/.*frac=\([0-9.]*\).*/\1/'; }

pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 3
if [ "$MODE" = "nojit" ]; then export BFME_NO_X87=1; fi
( cd "$G" && WINEDEBUG="+fps" $P/bfme run "$G/lotrbfme.exe" -noshellmap > "$LOG" 2>&1 & )
for w in $(seq 1 200); do sleep 2; alive || { echo "$LABEL: died at boot"; exit 1; }
  [ "$(fpsn)" -gt 3 ] && break; done
for w in $(seq 1 60); do sleep 3; s=$(snap "$OUT/$LABEL-menu.png") || continue
  f=$(frac "$s"); [ -n "$f" ] && [ "$(echo "$f > 0.05 && $f < 0.45" | bc -l)" = "1" ] && break; done
$P/bfme run "$T" hwclick "$W" $(sx 185) $(sx 858) >/dev/null 2>&1; sleep 7
$P/bfme run "$T" hwclick "$W" $(sx 649) $(sx 860) >/dev/null 2>&1; sleep 14
s=$(snap "$OUT/$LABEL-setup.png")
$P/bfme run "$T" hwclick "$W" $(sx 667) $(sx 857) >/dev/null 2>&1
# Wait for gameplay, then timestamp it: everything after is measured from here.
for w in $(seq 1 3000); do
  perl -e "select undef,undef,undef,0.3"; alive || { echo "$LABEL: crashed during load"; exit 1; }
  s=$(snap "$OUT/$LABEL-load.png") || continue
  f=$(frac "$s"); [ -n "$f" ] && [ "$(echo "$f > 0.70" | bc -l)" = "1" ] && break
done
T0=$(perl -MTime::HiRes=time -e "print time()")
echo "$LABEL: gameplay reached, holding ${PLAY}s with no input"
# Sleep to an absolute deadline so load-time differences cannot shift the sample.
perl -MTime::HiRes=time,sleep -e "my \$d=$T0+$PLAY; my \$n=time(); sleep(\$d-\$n) if \$d>\$n"
if out=$(snap "$OUT/$LABEL-t${PLAY}.png"); then
  echo "$LABEL: captured at T+${PLAY}s ($out)"
else
  echo "$LABEL: CAPTURE FAILED at T+${PLAY}s -- no game window" >&2
  pkill -9 -f lotrbfme.exe 2>/dev/null; exit 1
fi
pkill -9 -f lotrbfme.exe 2>/dev/null
