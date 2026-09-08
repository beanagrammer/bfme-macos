#!/bin/zsh
# Intercept the Arena<->addon named pipe to log exactly what the Arena asks for.
# Usage: arena-mitm.sh <outdir>
set -u
OUT="${1:?}"; mkdir -p "$OUT"
R=/Users/beanagrammer/Projects/BFME/run-custom-wine.sh
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
G="$HOME/.wine-aio-custom/drive_c/BFME1"
CONF="$G/arena_api_interface.conf"; AL="$G/arenaapilog.txt"
c(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }

rm -f "$CONF"; : > "$AL"
# --- watcher: the instant the conf appears, seize the pipe name ---
(
  for i in $(seq 1 6000); do
    if [ -f "$CONF" ]; then
      GUID=$(tr -d '\r\n\0' < "$CONF" | tr -cd 'A-Za-z0-9-')
      echo "conf appeared at $(date +%T) guid=$GUID" >> "$OUT/mitm.log"
      "$R" "$T" apisrv "bfme_api_interface_$GUID" 300 >> "$OUT/mitm.log" 2>&1
      break
    fi
    perl -e 'select undef,undef,undef,0.05'
  done
) &
WPID=$!
echo "watcher $WPID armed, navigating..."
[ "${SKIP_DIALOGS:-0}" = "1" ] || { c 645 455; sleep 1; c 683 472; sleep 1; }
c 45 152;  sleep 3
c 68 187;  sleep 3
c 388 384; sleep 4
c 751 458
echo "CONTINUE clicked at $(date +%T)"
for w in $(seq 1 40); do sleep 3; grep -qa 'REQ:' "$OUT/mitm.log" 2>/dev/null && break; done
sleep 30
kill $WPID 2>/dev/null
echo "=== done $(date +%T) ==="
