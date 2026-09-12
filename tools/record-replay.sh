#!/bin/zsh
# Record a real BFME replay: play a skirmish for a while, then leave the match
# through the in-game menu so the replay is finalised on disk.
#
# A replay is the only way to re-run the simulation from identical inputs, which
# is what determinism testing needs. Killing the game instead of exiting leaves
# a header-only .rep file, which is why this bothers with the menu.
#
# Usage: SCRW=2560 record-replay.sh <outdir> [seconds-to-play]
set -u
OUT="${1:?}"; PLAY="${2:-90}"; mkdir -p "$OUT"
P="${0:A:h:h}"
T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
A="$HOME/.wine-aio-custom"
G="$A/drive_c/BFME1"; LOG="$OUT/rec.log"
REP="$A/drive_c/users/$USER/AppData/Roaming/My Battle for Middle-earth Files/Replays/LastReplay.rep"
W="Battle for Middle-earth"; SW="${SCRW:-2560}"
sx(){ echo $(( $1 * SW / 1600 )); }
alive(){ pgrep -f lotrbfme.exe >/dev/null; }
fpsn(){ local c; c=$(grep -ac approx "$LOG" 2>/dev/null); [ -z "$c" ] && c=0; echo "$c"; }
winline(){ "$P/tools/winlist" 2>/dev/null | grep -i "$W" | grep -vi arena | head -1; }
winid(){ winline | sed -n 's/^id=\([0-9]*\).*/\1/p'; }
winpid(){ winline | sed -n 's/.*pid=\([0-9]*\).*/\1/p'; }
snap(){ local id=$(winid); [ -z "$id" ] && return 1
        screencapture -x -o -l "$id" "$1" 2>/dev/null || return 1
        python3 "$IS" stats "$1" 2>/dev/null; }
frac(){ echo "$1" | sed 's/.*frac=\([0-9.]*\).*/\1/'; }
front(){ osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null; }
activate(){ local pid=$(winpid); [ -z "$pid" ] && return 1
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" >/dev/null 2>&1
  sleep 2; $P/bfme run "$T" fg "$W" >/dev/null 2>&1; sleep 1; }
key(){ [ "$(front)" = "wine" ] || { echo "refusing: game not frontmost" >&2; return 1; }
       osascript -e "tell application \"System Events\" to key code $1" >/dev/null 2>&1; }

rm -f "$REP"
pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 3
( cd "$G" && WINEDEBUG="+fps" $P/bfme run "$G/lotrbfme.exe" -noshellmap > "$LOG" 2>&1 & )
for w in $(seq 1 150); do sleep 2; alive || { echo "died at boot"; exit 1; }
  [ "$(fpsn)" -gt 3 ] && break; done
echo "booted"
for w in $(seq 1 60); do sleep 3; s=$(snap "$OUT/menu.png") || continue
  f=$(frac "$s"); [ -n "$f" ] && [ "$(echo "$f > 0.05 && $f < 0.45" | bc -l)" = "1" ] && break; done
$P/bfme run "$T" hwclick "$W" $(sx 185) $(sx 858) >/dev/null 2>&1; sleep 7
$P/bfme run "$T" hwclick "$W" $(sx 649) $(sx 860) >/dev/null 2>&1; sleep 14
s=$(snap "$OUT/setup.png"); echo "setup: $s"
$P/bfme run "$T" hwclick "$W" $(sx 667) $(sx 857) >/dev/null 2>&1
for w in $(seq 1 900); do
  perl -e "select undef,undef,undef,0.3"; alive || { echo "crashed during load"; exit 1; }
  s=$(snap "$OUT/load.png") || continue
  f=$(frac "$s"); [ -n "$f" ] && [ "$(echo "$f > 0.70" | bc -l)" = "1" ] && break
done
echo "in game ($s); playing for ${PLAY}s"
sleep "$PLAY"
snap "$OUT/played.png" >/dev/null

activate || { echo "could not focus the game"; exit 1; }
key 53 || exit 1          # Escape opens the in-game menu
sleep 3
snap "$OUT/escmenu.png" >/dev/null
echo "captured the in-game menu; the caller picks the exit button from it"
