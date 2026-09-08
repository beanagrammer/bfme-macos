#!/bin/zsh
# Drive the Arena to the BFME1 Patch 2.22 ranked playtest, retrying through flaky launches.
# Usage: arena-playtest.sh <outdir> [max_attempts] [net_watch_seconds]
set -u
OUT="${1:?outdir}"; TRIES="${2:-6}"; NETSECS="${3:-150}"; mkdir -p "$OUT"
R=/Users/beanagrammer/Projects/BFME/run-custom-wine.sh
T=/Users/beanagrammer/Projects/BFME/tools/wintool/wintool.exe
WL=/Users/beanagrammer/Projects/BFME/tools/winlist
G="$HOME/.wine-aio-custom/drive_c/BFME1"
AL="$G/arenaapilog.txt"
click(){ "$R" "$T" hwclick "Online Arena" "$1" "$2" >/dev/null 2>&1; }
shot(){ local id=$("$WL" | grep 'owner=wine' | grep -i Arena | grep -oE 'id=[0-9]+' | head -1 | cut -d= -f2); [ -n "$id" ] && screencapture -x -o -l "$id" "$OUT/$1.png" 2>/dev/null && sips -Z 1400 "$OUT/$1.png" --out "$OUT/${1}_small.png" >/dev/null 2>&1; }
socks(){ for pid in $(pgrep -f 'lotrbfme.exe|OnlineArena'); do lsof -nP -p "$pid" 2>/dev/null | grep -E 'TCP|UDP' | sed "s/^/[$1] /"; done; }

if ! pgrep -f OnlineArena >/dev/null; then
  echo "[*] starting Arena"; ( "$R" "C:\\users\\beanagrammer\\AppData\\Roaming\\BFME Competetive Arena\\BfmeFoundationProject_OnlineArena.exe" > "$OUT/arena.log" 2>&1 & ); sleep 40
fi
for a in $(seq 1 $TRIES); do
  echo "=== attempt $a/$TRIES ==="
  pkill -f lotrbfme.exe 2>/dev/null; sleep 2
  click 645 455; sleep 2                 # dismiss any leftover failure dialog
  click 45 152;  sleep 3                 # Play
  click 68 187;  sleep 3                 # Ranked
  click 388 384; sleep 4                 # BFME1 Patch 2.22 card
  click 751 458                          # CONTINUE on sync dialog
  : > "$AL" 2>/dev/null; find "$G" -maxdepth 1 -name 'DUMP-*.dmp' -delete 2>/dev/null
  presented=0; t0=$(date +%s); prev=0
  while [ $(( $(date +%s) - t0 )) -lt 60 ]; do
    sleep 3; el=$(( $(date +%s) - t0 ))
    lines=$(wc -l < "$AL" 2>/dev/null | tr -d ' '); lines=${lines:-0}
    if [ "$lines" != "$prev" ]; then tail -n $(( lines - prev )) "$AL" 2>/dev/null | tr -d '\000' | sed 's/[^[:print:]]//g' | sed "s/^/    [+${el}s] /"; prev=$lines; fi
    grep -qa 'first frame presented' "$AL" 2>/dev/null && { presented=1; echo "  >>> PRESENTED at +${el}s"; break; }
    if ! pgrep -f lotrbfme.exe >/dev/null && [ $el -gt 8 ]; then echo "  game died at +${el}s (dumps=$(find "$G" -maxdepth 1 -name 'DUMP-*.dmp' | wc -l | tr -d ' '))"; break; fi
  done
  if [ $presented -eq 1 ]; then
    echo "[*] entering networking watch (${NETSECS}s)"
    t1=$(date +%s)
    while [ $(( $(date +%s) - t1 )) -lt $NETSECS ]; do
      el=$(( $(date +%s) - t1 ))
      lines=$(wc -l < "$AL" 2>/dev/null | tr -d ' '); lines=${lines:-0}
      if [ "$lines" != "$prev" ]; then tail -n $(( lines - prev )) "$AL" 2>/dev/null | tr -d '\000' | sed 's/[^[:print:]]//g' | sed "s/^/    [+${el}s] /"; prev=$lines; fi
      socks "+${el}s" >> "$OUT/sockets.txt"
      pgrep -f lotrbfme.exe >/dev/null || { echo "  game exited at +${el}s"; sleep 5; break; }
      sleep 3
    done
    shot result
    cp "$AL" "$OUT/arenaapilog.txt" 2>/dev/null
    echo "[*] listening/connected sockets seen:"; grep -hoE '(TCP|UDP) [^ ]+' "$OUT/sockets.txt" 2>/dev/null | sort -u | head -40
    exit 0
  fi
done
echo "[!] no attempt reached a presented frame"; shot result; exit 1
