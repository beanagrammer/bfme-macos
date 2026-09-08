#!/bin/zsh
# Bring BFME1 up standalone with the add-on injected and hold it, retrying past the
# Rosetta launch flakiness. Leaves the game running and the pin active.
set -u
OUT="${1:?}"; HOLD="${2:-600}"; N="${3:-10}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"
SCR=/private/tmp/claude-501/-Users-beanagrammer-Projects-BFME/8c03f450-31ff-4a41-8e2b-1eb8d873da5e/scratchpad
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
GUID="fpsfpsf-1111-4000-8000-000000000001"
cp "$SCR/addon.dll" "$G/dinput8.dll"
printf '%s' "$GUID" > "$G/arena_api_interface.conf"
pkill -f "wintool.exe pin" 2>/dev/null
for a in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  : > "$AL"
  ( cd "$G" && "$R" "$G/lotrbfme.exe" -noshellmap > "$OUT/game.log" 2>&1 & )
  ( "$R" "$T" pin "lotrbfme" $HOLD ) > "$OUT/pin.log" 2>&1 &
  for w in $(seq 1 25); do
    sleep 2
    grep -qa 'first frame presented' "$AL" 2>/dev/null && { echo "UP after $a attempt(s) at $(date +%T)"; exit 0; }
    pgrep -f lotrbfme.exe >/dev/null || break
  done
  echo "attempt $a: died"
  pkill -f "wintool.exe pin" 2>/dev/null
done
echo "failed to bring the game up"; exit 1
