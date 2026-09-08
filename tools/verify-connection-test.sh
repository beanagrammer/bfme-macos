#!/bin/zsh
# Verify the BFME1 Patch 2.22 connection test passes repeatedly, with no pinning and
# no retries, now that the game runs at the 2560x1440 the Arena's hardcoded button
# coordinates assume. Usage: verify-connection-test.sh <outdir> <runs>
set -u
OUT="${1:?}"; N="${2:-5}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; W="$P/tools/winlist"
PFX="$HOME/.wine-aio-custom"; AL="$PFX/drive_c/BFME1/arenaapilog.txt"
FLAG="$PFX/drive_c/users/beanagrammer/AppData/Roaming/BFME Competetive Arena/Settings/arena_onlineTestCompletedForBFME1.json"
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
[ -z "$APID" ] && { echo "arena not running"; exit 1; }
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
click(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
snap(){ ID=$("$W" 2>/dev/null | grep -i "Online Arena" | head -1 | sed 's/id=\([0-9]*\).*/\1/')
        [ -n "$ID" ] && screencapture -x -o -l "$ID" "$OUT/$1.png" 2>/dev/null
        [ -f "$OUT/$1.png" ] && sips -s format png -Z 950 "$OUT/$1.png" --out "$OUT/${1}v.png" >/dev/null 2>&1; }
pass=0
for i in $(seq 1 $N); do
  pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 2
  printf 'false' > "$FLAG"; : > "$AL"
  # After a pass the Arena sits inside the arena; BACK returns to the Play page,
  # which is the only place the join (and therefore the test) can be re-triggered.
  click 317 42; sleep 3          # BACK (no-op if already on the Play page)
  click 69 218; sleep 4          # Play
  snap "r${i}_play"
  printf 'false' > "$FLAG"
  START=$(date +%s)
  click 1329 228                 # RESUME on the Patch 2.22 continue card
  ok=0
  for w in $(seq 1 30); do
    sleep 4
    grep -qi true "$FLAG" 2>/dev/null && { ok=1; break; }
  done
  EL=$(( $(date +%s) - START ))
  if [ $ok -eq 1 ]; then pass=$(( pass + 1 )); echo "  run $i: PASSED in ${EL}s"; else echo "  run $i: FAILED"; snap "r${i}_fail"; fi
done
echo "== $pass/$N connection tests passed (no pinning, no retries)"
