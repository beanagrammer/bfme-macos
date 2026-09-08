#!/bin/zsh
# Single launch, long deadline, with periodic sampling to see whether a "hung"
# launch is actually just very slow, and where it is spending time.
set -u
OUT="${1:?}"; MAX="${2:-300}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"
SCR=/private/tmp/claude-501/-Users-beanagrammer-Projects-BFME/8c03f450-31ff-4a41-8e2b-1eb8d873da5e/scratchpad
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
GUID="benchben-1111-4000-8000-000000000001"
cp "$SCR/addon.dll" "$G/dinput8.dll"; printf '%s' "$GUID" > "$G/arena_api_interface.conf"
pkill -f lotrbfme.exe 2>/dev/null; pkill -f "wintool.exe pin" 2>/dev/null; sleep 2
: > "$AL"
START=$(date +%s)
( cd "$G" && "$R" "$G/lotrbfme.exe" -noshellmap > "$OUT/game.log" 2>&1 & )
( "$R" "$T" pin "lotrbfme" $(( MAX + 20 )) ) > "$OUT/pin.log" 2>&1 &
sampled=0
while :; do
  el=$(( $(date +%s) - START ))
  if grep -qa 'first frame presented' "$AL" 2>/dev/null; then echo "PRESENTED at ${el}s"; break; fi
  if [ $el -ge $MAX ]; then echo "gave up at ${el}s"; break; fi
  if ! pgrep -f lotrbfme.exe >/dev/null; then echo "DIED at ${el}s"; break; fi
  if [ $el -ge 45 ] && [ $sampled -eq 0 ]; then
     PID=$(pgrep -f lotrbfme.exe | head -1)
     echo "  sampling at ${el}s (pid $PID, cpu $(ps -o %cpu= -p $PID | tr -d ' '))"
     sample $PID 3 -f "$OUT/sample.txt" >/dev/null 2>&1
     sampled=1
  fi
  [ $(( el % 20 )) -eq 0 ] && echo "  t=${el}s cpu=$(ps -o %cpu= -p $(pgrep -f lotrbfme.exe | head -1) 2>/dev/null | tr -d ' ')"
  sleep 2
done
pkill -f "wintool.exe pin" 2>/dev/null
