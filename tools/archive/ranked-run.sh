#!/bin/zsh
# Drive the BFME1 2.22 ranked connection test with the game window pinned to 0,0
# and kept foreground (required by the Arena's IsGameFocused check).
# Usage: ranked-run.sh <outdir> [attempts]
set -u
OUT="${1:?}"; N="${2:-8}"; mkdir -p "$OUT"
R=/Users/beanagrammer/Projects/BFME/run-custom-wine.sh
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
W=/Users/beanagrammer/Projects/BFME/tools/winlist
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
DUR=$(( N * 70 + 60 ))
( "$R" "$T" pin "lotrbfme" $DUR ) > "$OUT/pin.log" 2>&1 &
PINPID=$!
shot(){ ID=$("$W" 2>/dev/null | grep -i "Online Arena" | head -1 | sed 's/id=\([0-9]*\).*/\1/')
        [ -n "$ID" ] && screencapture -x -o -l "$ID" "$OUT/$1.png" 2>/dev/null
        [ -f "$OUT/$1.png" ] && sips -s format png -Z 950 "$OUT/$1.png" --out "$OUT/$1v.png" >/dev/null 2>&1; }
for a in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  : > "$AL"; rm -f "$G/arena_api_proxy.conf"
  "$R" "$T" hwclick "Online Arena" 591 471 >/dev/null 2>&1   # RETRY
  echo "attempt $a: RETRY clicked $(date +%T)"
  pres=0
  for w in $(seq 1 20); do
    sleep 3
    if grep -qa 'first frame presented' "$AL" 2>/dev/null; then pres=1; break; fi
  done
  if [ $pres -eq 0 ]; then echo "  attempt $a: no frame presented"; continue; fi
  echo "  attempt $a: FRAME PRESENTED $(date +%T)"
  # let the test run
  for w in $(seq 1 20); do
    sleep 3
    [ -f "$G/arena_api_proxy.conf" ] && { echo "  PROXY CONF WRITTEN $(date +%T)"; cat "$G/arena_api_proxy.conf"; }
    grep -qa 'P2P Ready\|relayReady=1\|Arena Api Ready' "$AL" 2>/dev/null && { echo "  RELAY/READY SEEN"; break; }
  done
  shot "attempt$a"
  echo "  --- addon log ---"; tail -8 "$AL"
  break
done
sleep 3; shot final
kill $PINPID 2>/dev/null
echo "=== finished $(date +%T) ==="
