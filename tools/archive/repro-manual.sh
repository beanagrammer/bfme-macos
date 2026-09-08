#!/bin/zsh
# Reproduce the connection test the way a human hits it: Wine app frontmost (as a real
# click would leave it), NO window pinning, and only passive observation.
set -u
OUT="${1:?}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; W="$P/tools/winlist"
PFX="$HOME/.wine-aio-custom"; G="$PFX/drive_c/BFME1"; AL="$G/arenaapilog.txt"
FLAG="$PFX/drive_c/users/beanagrammer/AppData/Roaming/BFME Competetive Arena/Settings/arena_onlineTestCompletedForBFME1.json"
pkill -9 -f "wintool.exe pin" 2>/dev/null
printf 'false' > "$FLAG"
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
[ -z "$APID" ] && { echo "arena not running"; exit 1; }
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
: > "$AL"
( "$R" "$T" winwatch "lotrbfme" 150 ) > "$OUT/watch.log" 2>&1 &
WPID=$!
click(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
snap(){ ID=$("$W" 2>/dev/null | grep -i "Online Arena" | head -1 | sed 's/id=\([0-9]*\).*/\1/')
        [ -n "$ID" ] && screencapture -x -o -l "$ID" "$OUT/$1.png" 2>/dev/null
        [ -f "$OUT/$1.png" ] && sips -s format png -Z 950 "$OUT/$1.png" --out "$OUT/${1}v.png" >/dev/null 2>&1; }
# dismiss whatever dialog is up, then navigate Play > Ranked > 2.22 > CONTINUE
click 645 455; sleep 1; click 683 472; sleep 1
click 45 152;  sleep 3
click 68 187;  sleep 3
click 388 384; sleep 4
snap 00_before
click 751 458
echo "CONTINUE clicked $(date +%T)"
for w in $(seq 1 30); do
  sleep 4
  if grep -qi true "$FLAG" 2>/dev/null; then echo "PASSED at $(date +%T)"; break; fi
done
snap 99_after
kill $WPID 2>/dev/null
printf "flag = "; cat "$FLAG"; echo
echo "=== watch log ==="; cat "$OUT/watch.log"
