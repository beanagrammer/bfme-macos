#!/bin/zsh
# Shared setup for both launchers.  Source this, don't run it.
#
# BFME under the Arena has one hard constraint: the game must run at 2560x1440.
# The Arena drives the game by sending absolute screen coordinates over a named
# pipe (inputMove/inputClick/getPixelColor at 2415,1357 and friends) and those
# are compile-time constants for a 2560x1440 game sitting at 0,0.  At any other
# resolution the automation hovers empty space, the button never highlights, and
# the Arena gives up with "Failed to start the game: A task was canceled".
#
# So the resolution is fixed and the *display* has to adapt instead:
#   - a 2560x1440 Wine virtual desktop gives the Arena the coordinate space it wants
#   - RetinaScale shrinks that desktop to fit the Mac screen without changing the
#     game's resolution and without touching the macOS display mode
#   - ConstrainWindows=N stops Cocoa pushing the window below the menu bar, which
#     would shift every coordinate down by the menu bar height and break the same
#     automation
set -u
BFME_ROOT="${BFME_ROOT:-${0:A:h}}"
WINE="$BFME_ROOT/run-custom-wine.sh"
PREFIX="${WINEPREFIX:-$HOME/.wine-aio-custom}"
OPTIONS="$PREFIX/drive_c/users/$USER/AppData/Roaming/My Battle for Middle-earth Files/Options.ini"

GAME_W=2560
GAME_H=1440

bfme_die() { echo "FATAL: $*" >&2; exit 1; }

# Scale the 2560x1440 desktop down to the largest size that still fits the screen.
# Both axes are considered so the window never overflows; the larger ratio wins.
bfme_display_scale() {
  local dims w h
  dims=$("$BFME_ROOT/tools/listmodes" 2>/dev/null | head -1) \
    || bfme_die "could not read the display size (tools/listmodes missing?)"
  w=$(printf '%s\n' "$dims" | sed -n 's/^current: \([0-9]*\) x \([0-9]*\).*/\1/p')
  h=$(printf '%s\n' "$dims" | sed -n 's/^current: \([0-9]*\) x \([0-9]*\).*/\2/p')
  [ -n "$w" ] && [ -n "$h" ] || bfme_die "could not parse the display size from: $dims"
  awk -v w="$w" -v h="$h" -v gw=$GAME_W -v gh=$GAME_H \
    'BEGIN { s = gw / w; t = gh / h; if (t > s) s = t; if (s < 1) s = 1; printf "%.6f", s }'
}

bfme_configure() {
  local scale reg shown
  scale=$(bfme_display_scale)
  shown=$(awk -v s=$scale -v gw=$GAME_W -v gh=$GAME_H 'BEGIN{printf "%dx%d", gw/s, gh/s}')
  echo "Display scale $scale: a ${GAME_W}x${GAME_H} game shown at $shown points."

  # One import instead of five "reg add" calls -- each of those is a separate
  # Wine start, which is most of the wait before the window appears.
  reg=$(mktemp -t bfme-config)   # reused as the .reg file itself
  cat > "$reg" <<REGEOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]
"RetinaMode"="y"
"RetinaScale"="$scale"
"ConstrainWindows"="N"

[HKEY_CURRENT_USER\\Software\\Wine\\Explorer]
"Desktop"="Default"

[HKEY_CURRENT_USER\\Software\\Wine\\Explorer\\Desktops]
"Default"="${GAME_W}x${GAME_H}"
REGEOF
  "$WINE" regedit /S "$reg" >/dev/null 2>&1 || { rm -f "$reg"; bfme_die "could not import the Wine settings"; }
  rm -f "$reg"

  # Read it all back in one query rather than trusting the import silently.
  local applied
  applied=$("$WINE" reg query 'HKCU\Software\Wine' /s 2>/dev/null) \
    || bfme_die "could not read back the Wine settings"
  # printf, not echo: zsh's echo eats the backslashes in registry paths.
  for expect in "RetinaMode.*y" "RetinaScale.*$scale" "ConstrainWindows.*N" \
                "Desktop.*Default" "Default.*${GAME_W}x${GAME_H}"; do
    printf '%s\n' "$applied" | grep -qE "$expect" \
      || bfme_die "Wine setting did not apply: $expect"
  done

  [ -f "$OPTIONS" ] || bfme_die "Options.ini not found at $OPTIONS -- run the game once from the launcher first"
  sed -i '' "s/^Resolution = .*/Resolution = ${GAME_W} ${GAME_H}/" "$OPTIONS"
  grep -q "^Resolution = ${GAME_W} ${GAME_H}$" "$OPTIONS" \
    || bfme_die "Options.ini Resolution was not set"
}

# Deliberately does NOT kill wineserver: a cold start costs about 90 seconds and
# nothing here needs one, because the driver options are read per process.
bfme_stop_wine() {
  pkill -9 -f lotrbfme.exe 2>/dev/null
  pkill -9 -f BfmeFoundationProject_OnlineArena.exe 2>/dev/null
  pkill -9 -f "wintool.exe" 2>/dev/null
  sleep 2
}
