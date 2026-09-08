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
( "$R" "$T" fgwatch 110 ) > "$OUT/fg.log" 2>&1 &
sleep 2
"$R" "$T" hwclick "Online Arena" "${2:-591}" "${3:-471}" >/dev/null 2>&1
echo "clicked $(date +%T)"
sleep 105
echo "done $(date +%T)"
