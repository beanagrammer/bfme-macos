#!/bin/zsh
# Measure BFME1 launch reliability and time-to-first-frame.
# Usage: launch-bench.sh <outdir> <iterations> [label]
# Env passed through: WINE_CPU_TOPOLOGY, WINEDEBUG, plus anything run-custom-wine.sh reads.
set -u
OUT="${1:?}"; N="${2:-10}"; LABEL="${3:-run}"; mkdir -p "$OUT"
P=/Users/beanagrammer/Projects/BFME
R="$P/run-custom-wine.sh"; T="$P/tools/wintool/wintool.exe"
SCR=/private/tmp/claude-501/-Users-beanagrammer-Projects-BFME/8c03f450-31ff-4a41-8e2b-1eb8d873da5e/scratchpad
G="$HOME/.wine-aio-custom/drive_c/BFME1"; AL="$G/arenaapilog.txt"
GUID="benchben-1111-4000-8000-000000000001"
DEADLINE="${DEADLINE:-60}"

cp "$SCR/addon.dll" "$G/dinput8.dll"
printf '%s' "$GUID" > "$G/arena_api_interface.conf"
pkill -f "wintool.exe pin" 2>/dev/null

ok=0; times=()
echo "# $LABEL  topology=${WINE_CPU_TOPOLOGY:-1:0 (launcher default)}  deadline=${DEADLINE}s  n=$N" | tee "$OUT/summary.txt"
for i in $(seq 1 $N); do
  # hard cleanup: a stuck instance ignores SIGTERM and blocks every later launch
  pkill -f lotrbfme.exe 2>/dev/null; sleep 1
  pkill -9 -f lotrbfme.exe 2>/dev/null
  pkill -9 -f "wintool.exe pin" 2>/dev/null
  for _w in 1 2 3 4 5 6 7 8 9 10; do pgrep -f lotrbfme.exe >/dev/null || break; sleep 1; pkill -9 -f lotrbfme.exe 2>/dev/null; done
  if pgrep -f lotrbfme.exe >/dev/null; then echo "  $i: SKIPPED (could not clear a stuck instance)"; continue; fi
  sleep 1
  : > "$AL"
  START=$(date +%s)
  ( cd "$G" && "$R" "$G/lotrbfme.exe" -noshellmap > "$OUT/${LABEL}_$i.log" 2>&1 & )
  ( "$R" "$T" pin "lotrbfme" $(( DEADLINE + 10 )) ) > "$OUT/pin_${LABEL}_$i.log" 2>&1 &
  res="TIMEOUT"; el=0
  while :; do
    el=$(( $(date +%s) - START ))
    if grep -qa 'first frame presented' "$AL" 2>/dev/null; then res="OK"; break; fi
    if [ $el -ge $DEADLINE ]; then res="TIMEOUT"; break; fi
    if ! pgrep -f lotrbfme.exe >/dev/null; then sleep 1; grep -qa 'first frame presented' "$AL" 2>/dev/null && { res="OK"; break; }; res="DIED"; break; fi
    perl -e 'select undef,undef,undef,0.25'
  done
  pkill -9 -f "wintool.exe pin" 2>/dev/null
  if [ "$res" = "OK" ]; then ok=$(( ok + 1 )); times+=($el); fi
  # capture the last few lines of the game log for failures
  if [ "$res" != "OK" ]; then
    { echo "== result $res after ${el}s"
      echo "-- addon log tail --"; tail -4 "$AL" 2>/dev/null
      PIDX=$(pgrep -f lotrbfme.exe | head -1)
      if [ -n "$PIDX" ]; then
        echo "-- alive, cpu $(ps -o %cpu= -p $PIDX | tr -d ' ')% --"
        echo "-- wine windows --"; "$R" "$T" list 2>/dev/null | head -5
        sample $PIDX 2 -f "$OUT/sample_${LABEL}_$i.txt" >/dev/null 2>&1
        echo "-- hottest frames --"; grep -aE "^ +[0-9]+ +[A-Za-z_?]" "$OUT/sample_${LABEL}_$i.txt" 2>/dev/null | sort -rn | head -6
      else
        echo "-- process gone --"
      fi
      echo "-- game log tail --"; tail -6 "$OUT/${LABEL}_$i.log" 2>/dev/null
    } > "$OUT/fail_${LABEL}_$i.txt" 2>&1
  fi
  echo "  $i: $res ${el}s" | tee -a "$OUT/summary.txt"
done
pkill -f lotrbfme.exe 2>/dev/null
echo "== $LABEL: $ok/$N succeeded within ${DEADLINE}s; times: ${times[*]}" | tee -a "$OUT/summary.txt"
