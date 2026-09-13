#!/bin/zsh
# Does the x87 JIT change BFME's simulation? One machine, no opponent.
#
# The earlier attempt compared a fixed number of wall-clock seconds after
# gameplay started, and that is not a fixed point in the simulation: the trigger
# fires at a different moment in the opening camera pan depending on load speed,
# so the runs sampled different logic frames and the resource counters differed
# purely from the offset.
#
# This synchronises on the simulation instead. The resource counter is a
# deterministic function of the simulation state, and two runs in the same mode
# render it pixel-identically. So: record a reference crop of that counter from
# one run, then in every other run poll until the counter renders EXACTLY that
# image, and capture there. Both captures are then the same logic frame, and
# what remains to compare is the rest of the screen.
#
#   record: sim-compare.sh <dir> <label> record [nojit]
#   match : sim-compare.sh <dir> <label> match  [nojit]
set -u
OUT="${1:?}"; LABEL="${2:?}"; MODE="${3:-record}"; XMODE="${4:-jit}"
mkdir -p "$OUT"
P="${0:A:h:h}"
T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
A="$HOME/.wine-aio-custom"; G="$A/drive_c/BFME1"; LOG="$OUT/$LABEL.log"
W="Battle for Middle-earth"; SW="${SCRW:-2560}"
REF="$OUT/reference-counter.png"
SETTLE="${SETTLE:-100}"      # let the opening camera pan finish in both modes
sx(){ echo $(( $1 * SW / 1600 )); }
alive(){ pgrep -f lotrbfme.exe >/dev/null; }
fpsn(){ local c; c=$(grep -ac approx "$LOG" 2>/dev/null); [ -z "$c" ] && c=0; echo "$c"; }
winid(){ "$P/tools/winlist" 2>/dev/null | grep -i "$W" | grep -vi arena | head -1 | sed -n 's/^id=\([0-9]*\).*/\1/p'; }
shot(){ local id=$(winid); [ -z "$id" ] && return 1; screencapture -x -o -l "$id" "$1" 2>/dev/null; }
frac(){ python3 "$IS" stats "$1" 2>/dev/null | sed 's/.*frac=\([0-9.]*\).*/\1/'; }
crop(){ python3 -c "
from PIL import Image; import sys
Image.open(sys.argv[1]).convert('RGB').crop((0,1330,520,1420)).save(sys.argv[2])" "$1" "$2"; }
same(){ python3 -c "
from PIL import Image, ImageChops; import sys
a=Image.open(sys.argv[1]).convert('RGB'); b=Image.open(sys.argv[2]).convert('RGB')
sys.exit(0 if a.size==b.size and ImageChops.difference(a,b).getbbox() is None else 1)" "$1" "$2"; }

pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 3
[ "$XMODE" = "nojit" ] && export BFME_NO_X87=1
( cd "$G" && WINEDEBUG="+fps" $P/bfme run "$G/lotrbfme.exe" -noshellmap > "$LOG" 2>&1 & )
for w in $(seq 1 240); do sleep 2; alive || { echo "$LABEL: died at boot"; exit 1; }
  [ "$(fpsn)" -gt 3 ] && break; done
for w in $(seq 1 60); do sleep 3; shot "$OUT/$LABEL-menu.png" || continue
  f=$(frac "$OUT/$LABEL-menu.png"); [ -n "$f" ] && [ "$(echo "$f > 0.05 && $f < 0.45" | bc -l)" = "1" ] && break; done
$P/bfme run "$T" hwclick "$W" $(sx 185) $(sx 858) >/dev/null 2>&1; sleep 7
$P/bfme run "$T" hwclick "$W" $(sx 649) $(sx 860) >/dev/null 2>&1; sleep 14
shot "$OUT/$LABEL-setup.png"
$P/bfme run "$T" hwclick "$W" $(sx 667) $(sx 857) >/dev/null 2>&1
for w in $(seq 1 4000); do
  perl -e "select undef,undef,undef,0.3"; alive || { echo "$LABEL: crashed during load"; exit 1; }
  shot "$OUT/$LABEL-load.png" || continue
  f=$(frac "$OUT/$LABEL-load.png"); [ -n "$f" ] && [ "$(echo "$f > 0.70" | bc -l)" = "1" ] && break
done
echo "$LABEL: gameplay reached"
# Only the recording run waits. A matching run must start probing immediately:
# the counter only ever increases, so sleeping first can step straight past the
# value it is looking for, and then it can never match.
[ "$MODE" = "record" ] && sleep "$SETTLE"

if [ "$MODE" = "record" ]; then
  shot "$OUT/$LABEL-frame.png" || { echo "$LABEL: capture failed"; exit 1; }
  crop "$OUT/$LABEL-frame.png" "$REF"
  echo "$LABEL: recorded the reference counter and frame"
else
  [ -f "$REF" ] || { echo "$LABEL: no reference to match"; exit 1; }
  for w in $(seq 1 900); do
    alive || { echo "$LABEL: game exited while matching"; exit 1; }
    shot "$OUT/$LABEL-probe.png" || { perl -e "select undef,undef,undef,0.5"; continue; }
    crop "$OUT/$LABEL-probe.png" "$OUT/$LABEL-probe-crop.png"
    if same "$OUT/$LABEL-probe-crop.png" "$REF"; then
      cp "$OUT/$LABEL-probe.png" "$OUT/$LABEL-frame.png"
      echo "$LABEL: matched the reference counter after ${w} probes"
      break
    fi
    perl -e "select undef,undef,undef,0.4"
  done
  [ -f "$OUT/$LABEL-frame.png" ] || { echo "$LABEL: NEVER matched the reference counter"; pkill -9 -f lotrbfme.exe; exit 1; }
fi
pkill -9 -f lotrbfme.exe 2>/dev/null
