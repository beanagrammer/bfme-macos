#!/bin/zsh
# Drive the BFME1 2.22 ranked connection test. Keeps the game window pinned to 0,0
# and foreground for the WHOLE run (the Arena's IsGameFocused requires it).
# Usage: ranked-run2.sh <outdir> [attempts]
set -u
OUT="${1:?}"; N="${2:-10}"; mkdir -p "$OUT"
R=/Users/beanagrammer/Projects/BFME/run-custom-wine.sh
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
W=/Users/beanagrammer/Projects/BFME/tools/winlist
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
DUR=$(( N * 70 + 400 ))
( "$R" "$T" pin "lotrbfme" $DUR ) > "$OUT/pin.log" 2>&1 &
PINPID=$!
trap "kill $PINPID 2>/dev/null" EXIT
shot(){ ID=$("$W" 2>/dev/null | grep -i "Online Arena" | head -1 | sed 's/id=\([0-9]*\).*/\1/')
        [ -n "$ID" ] && screencapture -x -o -l "$ID" "$OUT/$1.png" 2>/dev/null
        [ -f "$OUT/$1.png" ] && sips -s format png -Z 950 "$OUT/$1.png" --out "$OUT/$1v.png" >/dev/null 2>&1; }
click(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
for a in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  : > "$AL"; rm -f "$G/arena_api_proxy.conf"
  click 645 455       # OKAY on GAME LAUNCH FAILED
  sleep 1
  click 591 471       # RETRY on Connection test failed
  echo "attempt $a: clicked $(date +%T)"
  pres=0
  for w in $(seq 1 20); do
    sleep 3
    grep -qa 'first frame presented' "$AL" 2>/dev/null && { pres=1; break; }
  done
  if [ $pres -eq 0 ]; then echo "  no frame presented"; continue; fi
  echo "  FRAME PRESENTED $(date +%T) -- letting the test run, pin stays up"
  for w in $(seq 1 40); do
    sleep 5
    if [ -f "$G/arena_api_proxy.conf" ]; then echo "  PROXY CONF at $(date +%T):"; cat "$G/arena_api_proxy.conf"; fi
    grep -qa 'P2P Ready\|Arena Api Ready\|Relay watchdog' "$AL" 2>/dev/null && echo "  relay milestone at $(date +%T)"
    pgrep -f lotrbfme.exe >/dev/null || { echo "  game exited at $(date +%T)"; break; }
  done
  shot "attempt$a"
  echo "  --- addon log tail ---"; tail -12 "$AL"
  break
done
sleep 2; shot final
echo "=== finished $(date +%T) ==="
