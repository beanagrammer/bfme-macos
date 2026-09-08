#!/bin/zsh
# Ranked 2.22 connection test with the game pinned to 0,0 + foreground,
# capturing the GAME window (which carries the Arena's step overlay) every few seconds.
set -u
OUT="${1:?}"; N="${2:-10}"; mkdir -p "$OUT"
R=/Users/beanagrammer/Projects/BFME/run-custom-wine.sh
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
W=/Users/beanagrammer/Projects/BFME/tools/winlist
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
DUR=$(( N * 70 + 500 ))
( "$R" "$T" pin "lotrbfme" $DUR ) > "$OUT/pin.log" 2>&1 &
PINPID=$!
trap "kill $PINPID 2>/dev/null" EXIT
gwid(){ "$W" 2>/dev/null | grep -i "Battle for Middle-earth" | grep -v Arena | head -1 | sed 's/id=\([0-9]*\).*/\1/'; }
aid(){ "$W" 2>/dev/null | grep -i "Online Arena" | head -1 | sed 's/id=\([0-9]*\).*/\1/'; }
snap(){ local id="$1" f="$2"; [ -z "$id" ] && return
        screencapture -x -o -l "$id" "$OUT/$f.png" 2>/dev/null
        [ -f "$OUT/$f.png" ] && sips -s format png -Z 900 "$OUT/$f.png" --out "$OUT/${f}v.png" >/dev/null 2>&1; }
click(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
for a in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  : > "$AL"; rm -f "$G/arena_api_proxy.conf"
  click 645 455; sleep 1; click 591 471
  echo "attempt $a: clicked $(date +%T)"
  pres=0
  for w in $(seq 1 20); do sleep 3; grep -qa 'first frame presented' "$AL" 2>/dev/null && { pres=1; break; }; done
  [ $pres -eq 0 ] && { echo "  no frame"; continue; }
  echo "  FRAME PRESENTED $(date +%T)"
  GWIN=$(gwid); echo "  game window id=$GWIN"
  for w in $(seq 1 30); do
    snap "$GWIN" "g_$(printf %02d $w)"
    sleep 4
    pgrep -f lotrbfme.exe >/dev/null || { echo "  game exited at $(date +%T)"; break; }
  done
  snap "$(aid)" "arena_end"
  echo "  --- addon log tail ---"; tail -6 "$AL"
  break
done
echo "=== finished $(date +%T) ==="
