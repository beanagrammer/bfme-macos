#!/bin/zsh
# Deterministically retry the BFME1 2.22 ranked connection test until the game presents a frame.
# Usage: playtest-loop.sh <outdir> <attempts>
set -u
OUT="${1:?}"; N="${2:-6}"; mkdir -p "$OUT"
R="${WINE_RUNNER:-/Users/beanagrammer/Projects/BFME/run-custom-wine.sh}"
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
G="${BFME_GAMEDIR:-$HOME/.wine-aio-custom/drive_c/BFME1}"; AL="$G/arenaapilog.txt"
c(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
for a in $(seq 1 $N); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  c 645 455; sleep 1      # OKAY  (GAME LAUNCH FAILED)
  c 683 472; sleep 1      # CANCEL (Connection test failed)
  c 45 152;  sleep 3      # Play
  c 68 187;  sleep 3      # Ranked
  c 388 384; sleep 4      # BFME1 Patch 2.22
  : > "$AL" 2>/dev/null
  c 751 458               # CONTINUE (sync)
  started=0
  for w in $(seq 1 6); do sleep 3; pgrep -f lotrbfme.exe >/dev/null && { started=1; break; }; done
  if [ $started -eq 0 ]; then echo "attempt $a: game never started"; continue; fi
  pres=0
  for w in $(seq 1 15); do
    sleep 3
    grep -qa 'first frame presented' "$AL" 2>/dev/null && { pres=1; break; }
    pgrep -f lotrbfme.exe >/dev/null || break
  done
  if [ $pres -eq 1 ]; then echo "attempt $a: PRESENTED"; exit 0; fi
  echo "attempt $a: died before presenting"
done
echo "no attempt presented"; exit 1
