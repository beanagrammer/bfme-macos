#!/bin/zsh
# Reproduce the BFME1 Patch 2.22 connection test PASS from a clean state.
#   1. kill the Arena, delete arena_onlineTestCompletedForBFME1.json
#   2. relaunch the Arena, navigate Play > Ranked > BFME1 Patch 2.22 > CONTINUE
#   3. keep the Wine app frontmost and the game window pinned at 0,0 + foreground
#   4. retry until the flag file comes back as "true"
set -u
OUT="${1:?}"; N="${2:-12}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; W="$P/tools/winlist"
PFX="$HOME/.wine-aio-custom"
G="$PFX/drive_c/BFME1"; AL="$G/arenaapilog.txt"
FLAG="$PFX/drive_c/users/beanagrammer/AppData/Roaming/BFME Competetive Arena/Settings/arena_onlineTestCompletedForBFME1.json"
ARENA="C:\\users\\beanagrammer\\AppData\\Roaming\\BFME Competetive Arena\\BfmeFoundationProject_OnlineArena.exe"

echo "== resetting =="
pkill -f lotrbfme.exe 2>/dev/null
pkill -f "BfmeFoundationProject_OnlineArena.exe" 2>/dev/null
pkill -f "wintool.exe pin" 2>/dev/null
sleep 5
[ -f "$FLAG" ] && cp "$FLAG" "$OUT/flag.before.json"
rm -f "$FLAG"
echo "flag present after delete: $([ -f "$FLAG" ] && echo YES || echo no)"

echo "== launching arena =="
( "$R" "$ARENA" > "$OUT/arena.log" 2>&1 & )
for i in $(seq 1 30); do sleep 3; pgrep -f "BfmeFoundationProject_OnlineArena.exe" >/dev/null && break; done
sleep 25
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1); echo "arena pid $APID"
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 3

DUR=$(( N * 75 + 500 ))
( "$R" "$T" pin "lotrbfme" $DUR ) > "$OUT/pin.log" 2>&1 &
PINPID=$!
trap "kill $PINPID 2>/dev/null" EXIT

click(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
snap(){ ID=$("$W" 2>/dev/null | grep -i "Online Arena" | head -1 | sed 's/id=\([0-9]*\).*/\1/')
        [ -n "$ID" ] && screencapture -x -o -l "$ID" "$OUT/$1.png" 2>/dev/null
        [ -f "$OUT/$1.png" ] && sips -s format png -Z 950 "$OUT/$1.png" --out "$OUT/${1}v.png" >/dev/null 2>&1; }

echo "== navigating to ranked BFME1 patch 2.22 =="
snap 00_home
click 45 152;  sleep 3      # Play
click 68 187;  sleep 3      # Ranked
snap 01_patchlist
click 388 384; sleep 4      # BFME1 Patch 2.22 card
snap 02_selected
click 751 458               # CONTINUE
echo "CONTINUE clicked $(date +%T)"

for a in $(seq 1 $N); do
  ok=0
  for w in $(seq 1 25); do
    sleep 3
    if [ -f "$FLAG" ] && grep -qi true "$FLAG" 2>/dev/null; then ok=1; break; fi
    grep -qa 'first frame presented' "$AL" 2>/dev/null && echo "  frame presented $(date +%T)"
  done
  if [ $ok -eq 1 ]; then
    echo "*** CONNECTION TEST PASSED at $(date +%T) ***"
    echo "flag contents: $(cat "$FLAG")"
    snap 99_passed
    tail -8 "$AL"
    exit 0
  fi
  echo "attempt $a failed, retrying $(date +%T)"
  snap "fail_$a"
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  : > "$AL"
  click 645 455; sleep 1     # OKAY  (GAME LAUNCH FAILED)
  click 591 471; sleep 1     # RETRY (Connection test failed)
done
echo "!!! did not pass in $N attempts"
snap 98_final
exit 1
