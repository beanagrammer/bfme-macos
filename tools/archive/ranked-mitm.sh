#!/bin/zsh
# Ranked 2.22 test with a logging MITM on the Arena<->addon pipe.
# The Arena writes arena_api_interface.conf with GUID G; we swap it to G2 before the
# add-on reads it, then proxy G -> G2 so every request/response is logged.
set -u
OUT="${1:?}"; N="${2:-10}"; mkdir -p "$OUT"
R=/Users/beanagrammer/Projects/BFME/run-custom-wine.sh
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
CONF="$G/arena_api_interface.conf"
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
DUR=$(( N * 70 + 500 ))
( "$R" "$T" pin "lotrbfme" $DUR ) > "$OUT/pin.log" 2>&1 &
PINPID=$!
trap "kill $PINPID 2>/dev/null" EXIT
click(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
for a in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; pkill -f "wintool.exe apiproxy" 2>/dev/null; sleep 2
  : > "$AL"; rm -f "$CONF" "$G/arena_api_proxy.conf"
  # watcher: swap the guid the add-on will read, then proxy
  ( for i in $(seq 1 8000); do
      if [ -f "$CONF" ]; then
        ORIG=$(tr -d '\r\n\0' < "$CONF" | tr -cd 'A-Za-z0-9-')
        NEW="deadbeef-0000-4000-8000-$(printf %012d $RANDOM$RANDOM)"
        printf '%s' "$NEW" > "$CONF"
        echo "swap at $(date +%T): arena=$ORIG addon=$NEW" >> "$OUT/mitm_$a.log"
        "$R" "$T" apiproxy "bfme_api_interface_$ORIG" "bfme_api_interface_$NEW" 240 >> "$OUT/mitm_$a.log" 2>&1
        break
      fi
      perl -e 'select undef,undef,undef,0.03'
    done ) &
  WPID=$!
  click 645 455; sleep 1; click 591 471
  echo "attempt $a: clicked $(date +%T)"
  pres=0
  for w in $(seq 1 20); do sleep 3; grep -qa 'first frame presented' "$AL" 2>/dev/null && { pres=1; break; }; done
  if [ $pres -eq 0 ]; then echo "  no frame"; kill $WPID 2>/dev/null; continue; fi
  echo "  FRAME PRESENTED $(date +%T)"
  for w in $(seq 1 40); do
    sleep 4
    pgrep -f lotrbfme.exe >/dev/null || { echo "  game exited at $(date +%T)"; break; }
  done
  kill $WPID 2>/dev/null
  echo "  --- addon log tail ---"; tail -6 "$AL"
  break
done
echo "=== finished $(date +%T) ==="
