#!/bin/zsh
set -u
OUT="${1:?}"; mkdir -p "$OUT"
R=/Users/beanagrammer/Projects/BFME/run-custom-wine.sh
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
APID=$(pgrep -f "BfmeFoundationProject_OnlineArena.exe" | head -1)
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true" 2>/dev/null
sleep 2
: > "$AL"; rm -f "$G/arena_api_proxy.conf"
( for i in $(seq 1 90); do printf "%s " "$(date +%T)"; "$R" "$T" fgq 2>/dev/null; sleep 2; done ) > "$OUT/fg.log" 2>&1 &
FPID=$!
"$R" "$T" hwclick "Online Arena" 591 471 >/dev/null 2>&1
echo "RETRY clicked $(date +%T)"
sleep 80
kill $FPID 2>/dev/null
echo "done $(date +%T)"
