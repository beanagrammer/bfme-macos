#!/bin/zsh
# Reproduce the connection test with a logging MITM on the Arena<->addon pipe, so we can
# see exactly which request the Arena is waiting on when it reports "A task was canceled".
set -u
OUT="${1:?}"; N="${2:-3}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"; W="$P/tools/winlist"
PFX="$HOME/.wine-aio-custom"; G="$PFX/drive_c/BFME1"; AL="$G/arenaapilog.txt"
CONF="$G/arena_api_interface.conf"
FLAG="$PFX/drive_c/users/beanagrammer/AppData/Roaming/BFME Competetive Arena/Settings/arena_onlineTestCompletedForBFME1.json"
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
[ -z "$APID" ] && { echo "arena not running"; exit 1; }
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
click(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
snap(){ ID=$("$W" 2>/dev/null | grep -i "Online Arena" | head -1 | sed 's/id=\([0-9]*\).*/\1/')
        [ -n "$ID" ] && screencapture -x -o -l "$ID" "$OUT/$1.png" 2>/dev/null
        [ -f "$OUT/$1.png" ] && sips -s format png -Z 950 "$OUT/$1.png" --out "$OUT/${1}v.png" >/dev/null 2>&1; }
for a in $(seq 1 $N); do
  printf 'false' > "$FLAG"
  pkill -9 -f lotrbfme.exe 2>/dev/null; pkill -9 -f "wintool.exe apiproxy" 2>/dev/null; sleep 2
  : > "$AL"; rm -f "$CONF" "$G/arena_api_proxy.conf"
  ( for i in $(seq 1 20000); do
      if [ -f "$CONF" ]; then
        ORIG=$(tr -d '\r\n\0' < "$CONF" | tr -cd 'A-Za-z0-9-')
        NEW="deadbeef-0000-4000-8000-$(printf %012d $RANDOM$RANDOM)"
        printf '%s' "$NEW" > "$CONF"
        echo "[swap $(date +%T)] arena=$ORIG addon=$NEW" >> "$OUT/mitm_$a.log"
        "$R" "$T" apiproxy "bfme_api_interface_$ORIG" "bfme_api_interface_$NEW" 200 >> "$OUT/mitm_$a.log" 2>&1
        break
      fi
      perl -e 'select undef,undef,undef,0.02'
    done ) &
  WPID=$!
  click 645 455; sleep 1; click 591 471; sleep 1   # OKAY then RETRY
  echo "attempt $a: retry clicked $(date +%T)"
  passed=0
  for w in $(seq 1 30); do
    sleep 4
    grep -qi true "$FLAG" 2>/dev/null && { passed=1; break; }
    pgrep -f lotrbfme.exe >/dev/null || { sleep 6; grep -qi true "$FLAG" 2>/dev/null && passed=1; break; }
  done
  kill $WPID 2>/dev/null; pkill -9 -f "wintool.exe apiproxy" 2>/dev/null
  snap "a${a}_end"
  if [ $passed -eq 1 ]; then echo "  attempt $a: PASSED"; else echo "  attempt $a: FAILED"; fi
  echo "  --- last 25 pipe messages ---"; tail -25 "$OUT/mitm_$a.log" 2>/dev/null
done
