#!/bin/zsh
# Run the ranked 2.22 connection test with the Wine app kept macOS-frontmost,
# and log GetForegroundWindow throughout so we can see whether IsGameFocused can pass.
set -u
OUT="${1:?}"; mkdir -p "$OUT"
R=/Users/beanagrammer/Projects/BFME/run-custom-wine.sh
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
c(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
echo "arena pid $APID"
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
: > "$AL"; rm -f "$G/arena_api_proxy.conf"
# background foreground-logger
( for i in $(seq 1 120); do
    printf "%s " "$(date +%T)"; "$R" "$T" fgq 2>/dev/null
    sleep 2
  done ) > "$OUT/fg.log" 2>&1 &
FPID=$!
c 45 152;  sleep 3
c 68 187;  sleep 3
c 388 384; sleep 4
c 751 458
echo "CONTINUE clicked $(date +%T)"
sleep 75
kill $FPID 2>/dev/null
echo "=== done $(date +%T) ==="
