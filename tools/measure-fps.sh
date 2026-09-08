#!/bin/zsh
# Launch BFME1 standalone with the Arena add-on injected and sample its fps counter.
# Usage: measure-fps.sh <outdir> [attempts]
set -u
OUT="${1:?}"; N="${2:-8}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"
SCR=/private/tmp/claude-501/-Users-beanagrammer-Projects-BFME/8c03f450-31ff-4a41-8e2b-1eb8d873da5e/scratchpad
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
GUID="fpsfpsf-1111-4000-8000-000000000001"

cp "$SCR/addon.dll" "$G/dinput8.dll"
printf '%s' "$GUID" > "$G/arena_api_interface.conf"

for a in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  : > "$AL"
  ( cd "$G" && "$R" "$G/lotrbfme.exe" -noshellmap > "$OUT/game_$a.log" 2>&1 & )
  ( "$R" "$T" pin "lotrbfme" 120 ) > "$OUT/pin_$a.log" 2>&1 &
  PINPID=$!
  pres=0
  for w in $(seq 1 25); do
    sleep 2
    grep -qa 'first frame presented' "$AL" 2>/dev/null && { pres=1; break; }
    pgrep -f lotrbfme.exe >/dev/null || break
  done
  if [ $pres -eq 0 ]; then echo "attempt $a: no frame"; kill $PINPID 2>/dev/null; continue; fi
  echo "attempt $a: presented at $(date +%T), sampling fps"
  sleep 8
  for s in $(seq 1 10); do
    R1=$("$R" "$T" pipecmd2 "bfme_api_interface_$GUID" getNetworkStats 2>/dev/null | tr -d '\r')
    echo "$R1" | grep -o 'fps=[0-9.]*' | sed "s/^/  sample $s: /"
    sleep 3
    pgrep -f lotrbfme.exe >/dev/null || { echo "  game exited during sampling"; break; }
  done
  "$R" "$T" pipecmd2 "bfme_api_interface_$GUID" getViewportSize 2>/dev/null | tr -d '\r' | sed 's/^/  viewport: /'
  kill $PINPID 2>/dev/null
  exit 0
done
echo "never presented in $N attempts"; exit 1
