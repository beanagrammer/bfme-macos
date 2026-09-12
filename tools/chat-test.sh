#!/bin/zsh
# Reproduce the in-game chat bug: press Enter, type, press Enter, and see whether
# the message appears. Captures the game WINDOW by CGWindowID -- which includes
# any part of it hidden under the macOS menu bar -- *and* the whole screen, so
# "not rendered at all" can be told apart from "rendered where you cannot see it".
#
# Usage: SCRW=2560 chat-test.sh <outdir>
set -u
OUT="${1:?}"; mkdir -p "$OUT"
P="${0:A:h:h}"
T="$P/tools/wintool/wintool.exe"; IS="$P/tools/imgstat.py"
G="$HOME/.wine-aio-custom/drive_c/BFME1"; LOG="$OUT/chat.log"
W="Battle for Middle-earth"
SW="${SCRW:-2560}"
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
cap(){ snap "$OUT/$1.png" >/dev/null 2>&1; screencapture -x "$OUT/$1-screen.png"; }

# Two ways to deliver keys, because it is not obvious which the game listens to:
# PostMessage from inside Wine (needs no macOS focus), and real macOS key events.
wkey(){ $P/bfme run "$T" key "$W" "$1" >/dev/null 2>&1; }
wtext(){ $P/bfme run "$T" text "$W" "$1" >/dev/null 2>&1; }

front(){ osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null; }
# NSRunningApplication.activate() silently does nothing for a process with no
# bundle, and a CGEvent click needs an Accessibility grant this tool lacks.
# System Events has one and works -- but only given the pid that OWNS THE WINDOW,
# which is not the first pid matching the exe name.
activate(){
  local pid=$(winpid)
  [ -z "$pid" ] && { echo "no game window found" >&2; return 1; }
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" >/dev/null 2>&1
  sleep 2
  # Being the active macOS app is not the same as the game window being Wine's
  # foreground window; set that too.
  $P/bfme run "$T" fg "$W" >/dev/null 2>&1
  sleep 1
}
# Allowlist, not a denylist: type only when the game really is frontmost.
# Getting this wrong sends the keystrokes into whatever the user had open.
safe_to_type(){
  local f=$(front)
  [ "$f" = "wine" ] || { echo "REFUSING to type: frontmost is '$f', not the game" >&2; return 1; }
  echo "frontmost is '$f'"
}
key(){ osascript -e "tell application \"System Events\" to key code $1" >/dev/null 2>&1; }
type_(){ osascript -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null 2>&1; }

pkill -9 -f lotrbfme.exe 2>/dev/null; sleep 3
( cd "$G" && WINEDEBUG="+fps" $P/bfme run "$G/lotrbfme.exe" -noshellmap > "$LOG" 2>&1 & )
for w in $(seq 1 150); do sleep 2; alive || { echo "died at boot"; exit 1; }
  [ "$(fpsn)" -gt 3 ] && break; done
echo "booted"
for w in $(seq 1 60); do sleep 3; s=$(snap "$OUT/menu.png") || continue
  f=$(frac "$s"); [ -n "$f" ] && [ "$(echo "$f > 0.10 && $f < 0.40" | bc -l)" = "1" ] && break; done
echo "main menu"
$P/bfme run "$T" hwclick "$W" $(sx 185) $(sx 858) >/dev/null 2>&1; sleep 7
$P/bfme run "$T" hwclick "$W" $(sx 649) $(sx 860) >/dev/null 2>&1; sleep 14
s=$(snap "$OUT/setup.png"); f=$(frac "$s")
if [ -z "$f" ] || [ "$(echo "$f > 0.20 && $f < 0.45" | bc -l)" != "1" ]; then
  echo "skirmish setup NOT reached ($s)"; pkill -9 -f lotrbfme.exe; exit 1; fi
echo "skirmish setup"
$P/bfme run "$T" hwclick "$W" $(sx 667) $(sx 857) >/dev/null 2>&1
for w in $(seq 1 600); do
  perl -e "select undef,undef,undef,0.2"; alive || { echo "CRASHED during load"; exit 1; }
  s=$(snap "$OUT/load.png") || continue
  f=$(frac "$s"); [ -n "$f" ] && [ "$(echo "$f > 0.85" | bc -l)" = "1" ] && break
done
echo "in game"
sleep 8
cap "0-ingame"

echo "--- attempt 1: PostMessage from inside Wine ---"
wkey 13; sleep 2; cap "A1-chatbox"
wtext "POSTMSG TEST"; sleep 2; cap "A2-typed"
wkey 13; sleep 1; cap "A3-sent"

echo "--- attempt 2: real macOS key events ---"
activate
if safe_to_type; then
  # Control first: arrow keys scroll the camera, which is a large, obvious
  # change. Without this there is no way to tell "chat is broken" apart from
  # "the keystrokes never reached the game".
  # Escape opens the in-game menu: a full-screen change no animation can fake.
  key 53; sleep 3; cap "B0-escape"
  key 53; sleep 3; cap "B0-escape-back"

  key 36; sleep 2; cap "B1-chatbox"
  type_ "MACOS TEST"; sleep 2; cap "B2-typed"
  key 36
  for i in 1 2 3; do perl -e "select undef,undef,undef,0.7"; cap "B3-sent-$i"; done
else
  echo "skipped the macOS path"
fi
echo "captured"
pkill -9 -f lotrbfme.exe 2>/dev/null
