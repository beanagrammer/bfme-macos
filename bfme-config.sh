#!/bin/zsh
# Shared setup: locating Wine and the prefix, and the display configuration.
# Source this, don't run it.
#
# BFME under the Arena has one hard constraint: the game must run at 2560x1440.
# The Arena drives the game by sending absolute screen coordinates over a named
# pipe (inputMove/inputClick/getPixelColor at 2415,1357 and friends) and those
# are compile-time constants for a 2560x1440 game sitting at 0,0.  At any other
# resolution the automation hovers empty space, the button never highlights, and
# the Arena gives up with "Failed to start the game: A task was canceled".
#
# So the resolution is fixed and the *display* adapts instead:
#   - a 2560x1440 Wine virtual desktop gives the Arena the coordinate space it wants
#   - RetinaScale shrinks that desktop to fit the Mac screen without changing the
#     game's resolution and without touching the macOS display mode
#   - ConstrainWindows=N stops Cocoa pushing the window below the menu bar, which
#     would shift every coordinate down by the menu bar height and break the same
#     automation
set -u

BFME_APP_SUPPORT="$HOME/Library/Application Support/bfme-macos"
GAME_W=2560
GAME_H=1440

bfme_die() { print -r -- "FATAL: $*" >&2; exit 1; }

# Wine: an explicit override, then the installed bundle, then a dev build tree.
bfme_find_wine() {
  if [ -n "${BFME_WINE_DIR:-}" ]; then
    [ -x "$BFME_WINE_DIR/bin/wine" ] || bfme_die "BFME_WINE_DIR has no bin/wine: $BFME_WINE_DIR"
    print -r -- "$BFME_WINE_DIR"; return
  fi
  if [ -x "$BFME_APP_SUPPORT/wine/bin/wine" ]; then
    print -r -- "$BFME_APP_SUPPORT/wine"; return
  fi
  if [ -x "$BFME_HOME/build-wine/loader/wine" ]; then
    print -r -- "$BFME_HOME/build-wine"; return
  fi
  bfme_die "no Wine found. Run ./install.sh, or set BFME_WINE_DIR."
}

# Prefix: an explicit override, then the prefix an earlier setup left behind,
# then the default. Always reported so it is never a surprise which one is used.
bfme_find_prefix() {
  if [ -n "${BFME_PREFIX:-}" ]; then print -r -- "$BFME_PREFIX"; return; fi
  if [ -n "${WINEPREFIX:-}" ];   then print -r -- "$WINEPREFIX";   return; fi
  if [ -d "$HOME/.wine-aio-custom" ]; then print -r -- "$HOME/.wine-aio-custom"; return; fi
  print -r -- "$BFME_APP_SUPPORT/prefix"
}

# Run a program under our Wine. Never wrap this in nohup: that is SIP-protected
# and strips DYLD_LIBRARY_PATH, after which WPF apps crash in font code.
bfme_wine() {
  local w="$BFME_WINE_ROOT"
  local loader="$w/bin/wine"
  [ -x "$loader" ] || loader="$w/loader/wine"      # dev build tree
  [ -x "$loader" ] || bfme_die "no wine loader under $w"
  local deps="$w/deps/lib"
  [ -d "$deps" ] || deps="$BFME_HOME/deps-x86_64/lib"
  local sidecar="$w/x87sidecar/x87sidecar"
  [ -x "$sidecar" ] || sidecar="$BFME_HOME/tools/x87sidecar/x87sidecar"

  (
    export WINEPREFIX="$BFME_PREFIX_DIR"
    export DYLD_LIBRARY_PATH="$deps"
    export WINEDEBUG="${WINEDEBUG:--all}"
    export MVK_CONFIG_LOG_LEVEL=0
    # The Arena's relay tries to punch a hole through the router; under Wine
    # there is no router access and the attempt just hangs.
    export BFME_PROXY_UPNP=0 BFME_PROXY_NATPMP=0 BFME_PROXY_IPV6=0
    # Rosetta emulates x87 in software at roughly 1/35th speed and BFME is full
    # of it; x87sidecar JITs those instructions to ARM64 instead.
    if [ -z "${BFME_NO_X87:-}" ] && [ -x "$sidecar" ]; then
      export ROSETTA_X87_PATH="$sidecar"
    fi
    exec "$loader" "$@"
  )
}

# Wait for the prefix to go idle. wineboot --init returns before wineserver has
# finished writing the registry, and anything imported in that window is lost.
bfme_wineserver_wait() {
  local w="$BFME_WINE_ROOT"
  local ws="$w/bin/wineserver"
  [ -x "$ws" ] || ws="$w/server/wineserver"       # dev build tree
  [ -x "$ws" ] || bfme_die "no wineserver under $w"
  local deps="$w/deps/lib"
  [ -d "$deps" ] || deps="$BFME_HOME/deps-x86_64/lib"
  WINEPREFIX="$BFME_PREFIX_DIR" DYLD_LIBRARY_PATH="$deps" "$ws" -w
}

# Scale the 2560x1440 desktop down to the largest size that still fits the screen.
# Both axes are considered so the window never overflows; the larger ratio wins.
bfme_display_scale() {
  local dims w h
  dims=$("$BFME_TOOLS/listmodes" 2>/dev/null | head -1) \
    || bfme_die "could not read the display size (tools/listmodes missing?)"
  w=$(printf '%s\n' "$dims" | sed -n 's/^current: \([0-9]*\) x \([0-9]*\).*/\1/p')
  h=$(printf '%s\n' "$dims" | sed -n 's/^current: \([0-9]*\) x \([0-9]*\).*/\2/p')
  [ -n "$w" ] && [ -n "$h" ] || bfme_die "could not parse the display size from: $dims"
  awk -v w="$w" -v h="$h" -v gw=$GAME_W -v gh=$GAME_H \
    'BEGIN { s = gw / w; t = gh / h; if (t > s) s = t; if (s < 1) s = 1; printf "%.6f", s }'
}

# Wine-side settings. Safe to run against a brand new prefix.
bfme_configure_wine() {
  local scale reg shown applied
  scale=$(bfme_display_scale)
  shown=$(awk -v s=$scale -v gw=$GAME_W -v gh=$GAME_H 'BEGIN{printf "%dx%d", gw/s, gh/s}')
  print -r -- "  display scale $scale: a ${GAME_W}x${GAME_H} game shown at $shown points"

  # One import instead of five "reg add" calls -- each of those is a separate
  # Wine start, which is most of the wait before the window appears.
  # Built with printf, not a heredoc: getting single backslashes through heredoc
  # quoting is easy to get wrong, and a .reg file with doubled backslashes is
  # rejected by regedit with "Unable to open the registry key".
  reg=$(mktemp -t bfme-config).reg
  {
    printf 'REGEDIT4\n\n'
    printf '[HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]\n'
    printf '"RetinaMode"="y"\n'
    printf '"RetinaScale"="%s"\n' "$scale"
    printf '"ConstrainWindows"="N"\n\n'
    printf '[HKEY_CURRENT_USER\\Software\\Wine\\Explorer]\n'
    printf '"Desktop"="Default"\n\n'
    printf '[HKEY_CURRENT_USER\\Software\\Wine\\Explorer\\Desktops]\n'
    printf '"Default"="%sx%s"\n\n' "$GAME_W" "$GAME_H"
    printf '[HKEY_CURRENT_USER\\Software\\Wine\\Direct3D]\n'
    printf '"renderer"="gl"\n'
  } > "$reg"
  local regout
  regout=$(bfme_wine regedit /S "$reg" 2>&1)
  if [ $? -ne 0 ]; then
    rm -f "$reg"
    bfme_die "could not import the Wine settings:
    $regout"
  fi
  rm -f "$reg"

  # Read it all back rather than trusting the import silently.
  # printf, not echo: zsh's echo eats the backslashes in registry paths.
  applied=$(bfme_wine reg query 'HKCU\Software\Wine' /s 2>/dev/null) \
    || bfme_die "could not read back the Wine settings"
  local expect
  for expect in "RetinaMode.*y" "RetinaScale.*$scale" "ConstrainWindows.*N" \
                "Desktop.*Default" "Default.*${GAME_W}x${GAME_H}"; do
    printf '%s\n' "$applied" | grep -qE "$expect" \
      || bfme_die "Wine setting did not apply: $expect"
  done
}

# Game-side settings. Needs the game to have been run once so Options.ini exists.
bfme_configure_game() {
  local options="$BFME_PREFIX_DIR/drive_c/users/$USER/AppData/Roaming/My Battle for Middle-earth Files/Options.ini"
  [ -f "$options" ] || bfme_die "Options.ini not found at
    $options
  Open the launcher and start BFME 1 once so the game writes it."
  sed -i '' "s/^Resolution = .*/Resolution = ${GAME_W} ${GAME_H}/" "$options"
  grep -q "^Resolution = ${GAME_W} ${GAME_H}$" "$options" \
    || bfme_die "Options.ini Resolution was not set"
}

# wineserver publishes its Mach port in the bootstrap namespace of whatever
# session started it, so a wineserver launched from a terminal is invisible to an
# app launched from the Dock or Spotlight, and vice versa. Wine then refuses to
# start with "a wine server seems to be running, but I cannot connect to it".
# Detect that and clear the unreachable server; a reachable one is left alone,
# because a cold start costs about 90 seconds.
bfme_ensure_wineserver() {
  local probe
  probe=$(bfme_wine reg query 'HKCU\Software' 2>&1)
  printf '%s' "$probe" | grep -q "cannot connect to it" || return 0

  print -r -- "  a wineserver from another login session is unreachable; restarting it"
  pkill -9 -f "$BFME_WINE_ROOT.*wineserver" 2>/dev/null
  pkill -9 -f "wine/x86_64-unix/wine" 2>/dev/null
  sleep 3
  probe=$(bfme_wine reg query 'HKCU\Software' 2>&1)
  printf '%s' "$probe" | grep -q "cannot connect to it" \
    && bfme_die "could not reach a wineserver even after restarting it:
    $probe"
  return 0
}

# Bring an already-running Wine program to the front.
bfme_activate() {
  local pid
  pid=$(pgrep -f "$1" | head -1) || return 1
  [ -n "$pid" ] || return 1
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" \
    >/dev/null 2>&1
}

# Guard a launch. Opening an app that is already running should focus it, not
# restart it -- and two launches racing each other is worse than that, because
# each one stops Wine first and so kills the other's game.
# Returns 1 when the caller should not launch.
bfme_launch_guard() {
  local pattern="$1" label="$2"
  local lock="$BFME_APP_SUPPORT/.launching"

  if pgrep -f "$pattern" >/dev/null 2>&1; then
    bfme_activate "$pattern"
    print -r -- "$label is already running."
    return 1
  fi

  mkdir -p "$BFME_APP_SUPPORT" 2>/dev/null
  if ! mkdir "$lock" 2>/dev/null; then
    # A lock older than two minutes is left over from something that died.
    local age
    age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || echo 0) ))
    if [ "$age" -lt 120 ]; then
      print -r -- "another launch is already in progress; giving it a moment."
      return 1
    fi
    print -r -- "clearing a stale launch lock"
    rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || return 1
  fi
  # The lock only has to cover the seconds before the game process exists.
  BFME_LAUNCH_LOCK="$lock"
  return 0
}

bfme_launch_unlock() {
  [ -n "${BFME_LAUNCH_LOCK:-}" ] && rmdir "$BFME_LAUNCH_LOCK" 2>/dev/null
  BFME_LAUNCH_LOCK=""
}

# Deliberately does NOT kill wineserver: a cold start costs about 90 seconds and
# nothing here needs one, because the driver options are read per process.
bfme_stop_wine() {
  pkill -9 -f lotrbfme.exe 2>/dev/null
  pkill -9 -f BfmeFoundationProject_OnlineArena.exe 2>/dev/null
  pkill -9 -f "wintool.exe" 2>/dev/null
  sleep 2
}
