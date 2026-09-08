#!/bin/zsh
# Retry the BFME1 2.22 ranked connection test until the add-on opens its relay sockets
# (the signal that the handshake completed and the ingame room is being created).
set -u
OUT="${1:?}"; TRIES="${2:-10}"; mkdir -p "$OUT"
R="${WINE_RUNNER:-/Users/beanagrammer/Projects/BFME/run-custom-wine.sh}"
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
WL=/Users/beanagrammer/Projects/BFME/tools/winlist
G="${BFME_GAMEDIR:-$HOME/.wine-aio-custom/drive_c/BFME1}"; AL="$G/arenaapilog.txt"
c(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
socks(){ local n=0; for pid in $(pgrep -f lotrbfme.exe); do n=$(( n + $(lsof -nP -p "$pid" 2>/dev/null | grep -cE 'TCP|UDP') )); done; echo $n; }
for a in $(seq 1 $TRIES); do
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  c 645 455; sleep 1     # OKAY (GAME LAUNCH FAILED)
  c 683 472; sleep 1     # CANCEL (Connection test failed)
  c 45 152;  sleep 3     # Play
  c 68 187;  sleep 3     # Ranked
  c 388 384; sleep 4     # BFME1 Patch 2.22
  : > "$AL" 2>/dev/null
  c 751 458              # CONTINUE
  best=0; alive=0
  for w in $(seq 1 40); do
    sleep 3
    if pgrep -f lotrbfme.exe >/dev/null; then alive=1; else [ $w -gt 5 ] && break; fi
    s=$(socks); [ "$s" -gt "$best" ] && best=$s
    if [ "$best" -gt 0 ]; then
      echo "attempt $a: *** GAME OPENED $best SOCKET(S) — handshake progressed ***"
      cp "$AL" "$OUT/pass_$a.log" 2>/dev/null
      exit 0
    fi
    grep -qa 'P2P Ready\|relayReady' "$AL" 2>/dev/null && { echo "attempt $a: *** RELAY READY ***"; exit 0; }
  done
  pres=$(grep -ca 'first frame presented' "$AL" 2>/dev/null)
  echo "attempt $a: no sockets (presented=$pres alive=$alive)"
done
echo "exhausted $TRIES attempts without sockets"; exit 1
