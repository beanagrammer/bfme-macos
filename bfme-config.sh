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

# Sync-safe mode. The x87 JIT's transcendentals are not correctly rounded -- it
# matches the correctly-rounded double on 3 of 10 sampled sine inputs where
# Rosetta matches 10 of 10 -- so its results differ from every player running on
# real x86. BFME is a lockstep simulation, so that is a desync risk. Turning the
# JIT off runs x87 on Rosetta, which is bit-exact, at roughly nine times the cost.
#
# A marker file rather than an environment variable, because the apps launched
# from Spotlight cannot carry one. `bfme sync-safe on` writes it.
[ -f "$BFME_APP_SUPPORT/sync-safe" ] && export BFME_NO_X87=1
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
  # Use the real loader, not bin/wine. bin/wine is a stub that re-execs the
  # loader, and that extra exec throws away x87sidecar's hook -- the JIT then
  # silently does nothing and everything runs at Rosetta's software-x87 speed
  # (measured: 7.7 vs 72.6 Miter/s on the same machine, and a skirmish load of
  # five minutes instead of twenty seconds).
  local loader="$w/lib/wine/x86_64-unix/wine"      # installed layout
  [ -x "$loader" ] || loader="$w/loader/wine"      # dev build tree
  [ -x "$loader" ] || loader="$w/bin/wine"         # last resort
  [ -x "$loader" ] || bfme_die "no wine loader under $w"
  local deps="$w/deps/lib"
  [ -d "$deps" ] || deps="$BFME_HOME/deps-x86_64/lib"
  # BFME_SIDECAR lets a locally built sidecar be tested without replacing the
  # shipped one.
  local sidecar="${BFME_SIDECAR:-}"
  [ -n "$sidecar" ] && [ ! -x "$sidecar" ] && bfme_die "BFME_SIDECAR is set to $sidecar, which is not executable"
  [ -n "$sidecar" ] || sidecar="$w/x87sidecar/x87sidecar"
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
      # Compute FSIN and FCOS the way real x87 does, so a lockstep match stays
      # in sync with players on Windows. Costs about four seconds of level
      # load and nothing measurable in play. X87_EXACT=0 turns it off.
      export X87_EXACT="${X87_EXACT:-1}"
    fi
    exec "$loader" "$@"
  )
}

# Stop wineserver the way it expects, so it saves the registry on the way out.
bfme_wineserver_kill() {
  local w="$BFME_WINE_ROOT"
  local ws="$w/bin/wineserver"
  [ -x "$ws" ] || ws="$w/server/wineserver"       # dev build tree
  local deps="$w/deps/lib"
  [ -d "$deps" ] || deps="$BFME_HOME/deps-x86_64/lib"
  if [ -x "$ws" ]; then
    WINEPREFIX="$BFME_PREFIX_DIR" DYLD_LIBRARY_PATH="$deps" "$ws" -k 2>/dev/null
    sleep 2
  fi
  # Anything that ignored -k is not going to save anything anyway.
  pkill -9 -f "$BFME_WINE_ROOT.*wineserver" 2>/dev/null
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

# Scale the 2560x1440 game down to the largest size that still fits the screen.
# Both axes are considered so the window never overflows; the larger ratio wins.
bfme_screen_points() {
  local dims w h
  dims=$("$BFME_TOOLS/listmodes" 2>/dev/null | head -1) \
    || bfme_die "could not read the display size (tools/listmodes missing?)"
  w=$(printf '%s\n' "$dims" | sed -n 's/^current: \([0-9]*\) x \([0-9]*\).*/\1/p')
  h=$(printf '%s\n' "$dims" | sed -n 's/^current: \([0-9]*\) x \([0-9]*\).*/\2/p')
  [ -n "$w" ] && [ -n "$h" ] || bfme_die "could not parse the display size from: $dims"
  print -r -- "$w $h"
}

# Wine's Retina mode is two Win32 pixels per Cocoa point and nothing else, and a
# window drawn through OpenGL follows it whether we like it or not: macOS only
# offers "1x" or "the display's full backing scale" for a GL surface, with no
# fractional option. A fractional RetinaScale therefore sizes the *window* by the
# fraction while its contents are still drawn at 2, which both leaves part of the
# window unpainted and, worse, puts every mouse click in the wrong place -- Wine
# maps the click by the fraction while the pixel under the cursor is at 2.
#
# So 2 is the default: correct rendering and correct clicks, with the game shown
# at 1280x720 points rather than filling the screen. BFME_FRACTIONAL_SCALE=1 opts
# into the larger game and accepts the misaimed clicks; it is not usable for the
# Arena, only for looking at the game.
bfme_display_scale() {
  local wh
  [ -z "${BFME_FRACTIONAL_SCALE:-}" ] && { printf '2'; return 0; }
  wh=$(bfme_screen_points) || return 1
  awk -v w="${wh%% *}" -v h="${wh##* }" -v gw=$GAME_W -v gh=$GAME_H \
    'BEGIN { s = gw / w; t = gh / h; if (t > s) s = t; if (s < 1) s = 1; printf "%.6f", s }'
}

# The virtual desktop is sized to the whole screen, not to the game. The game is
# 16:9 and most Macs are not, so something has to fill the leftover strip -- and
# it should be Wine's own black desktop rather than a hole showing whatever is
# behind. The game still sits at 0,0 at exactly GAME_W x GAME_H, which is what
# the Arena's hardcoded coordinates require.
bfme_desktop_size() {
  local wh scale
  wh=$(bfme_screen_points) || return 1
  scale=$(bfme_display_scale) || return 1
  awk -v w="${wh%% *}" -v h="${wh##* }" -v s="$scale" -v gw=$GAME_W -v gh=$GAME_H \
    'BEGIN {
       dw = int(w * s + 0.5); dh = int(h * s + 0.5);
       if (dw < gw) dw = gw;
       if (dh < gh) dh = gh;
       printf "%dx%d", dw, dh
     }'
}

# Wine-side settings. Safe to run against a brand new prefix.
bfme_configure_wine() {
  local scale reg shown applied desktop
  scale=$(bfme_display_scale)
  desktop=$(bfme_desktop_size)
  shown=$(awk -v s=$scale -v gw=$GAME_W -v gh=$GAME_H 'BEGIN{printf "%dx%d", gw/s, gh/s}')
  print -r -- "  display scale $scale: a ${GAME_W}x${GAME_H} game shown at $shown points,"
  print -r -- "  inside a ${desktop} desktop that fills the screen"

  # One import instead of five "reg add" calls -- each of those is a separate
  # Wine start, which is most of the wait before the window appears.
  # The virtual desktop's size is fixed when wineserver creates it, so a change
  # here only takes effect after the server restarts. Notice that before writing.
  local previous
  previous=$(bfme_wine reg query 'HKCU\Software\Wine\Explorer\Desktops' /v Default 2>/dev/null \
             | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '[:space:]')

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
    printf '"Default"="%s"\n\n' "$desktop"
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
                "Desktop.*Default" "Default.*$desktop"; do
    printf '%s\n' "$applied" | grep -qE "$expect" \
      || bfme_die "Wine setting did not apply: $expect"
  done

  # A desktop whose size changed is still the old size in the running server.
  # Shut it down gracefully with "wineserver -k": wineserver only writes the
  # registry back to disk on a clean exit, so killing it with -9 here throws away
  # the settings that were just imported.
  if [ -n "$previous" ] && [ "$previous" != "$desktop" ]; then
    print -r -- "  desktop size changed ($previous -> $desktop); restarting wineserver"
    bfme_wineserver_kill
    sleep 3
  fi
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

# BFME renders 16:9 because the Arena's coordinates require it, and most Macs are
# not 16:9, so a strip is always left over. Fill it with black rather than leaving
# a hole that shows the desktop. The helper only paints while the game is running
# and Wine is frontmost, and exits on its own once the game is gone.
bfme_start_backdrop() {
  local helper="$BFME_TOOLS/backdrop"
  [ -x "$helper" ] || return 0          # optional: the game runs fine without it
  [ -n "${BFME_NO_BACKDROP:-}" ] && return 0
  # Only useful when the game fills the screen and there is a letterbox to fill,
  # which is the fractional-scale case. At the default scale the game is a normal
  # window at normal window level and the backdrop would cover it completely --
  # a black screen instead of a game.
  [ -z "${BFME_FRACTIONAL_SCALE:-}" ] && return 0
  pkill -f "$helper" 2>/dev/null
  ( "$helper" lotrbfme.exe >/dev/null 2>&1 & )
}

# The Arena opens a 1500x1000 window, which on a screen bigger than that leaves
# most of the display showing whatever is behind it. Maximise it once it exists;
# its WPF layout reflows properly. This does not affect the coordinates the Arena
# uses to drive the *game* -- those are absolute screen coordinates for the game
# window and are independent of the Arena's own size.
# The Arena opens a 1500x1000 window. On a screen bigger than that it is just a
# window, which is fine -- but size it to the desktop so it uses the whole screen,
# now that its layer scales correctly. This does not affect the coordinates the
# Arena uses to drive the *game*: those are absolute screen coordinates for the
# game window and are independent of the Arena's own size.
# The Arena opens a 1500x1000 window, which on a large virtual desktop uses a
# small part of the screen. Grow it -- but only to the point where its own layout
# stops growing with it.
#
# Measured: the Arena's WPF content lays out to at most about 1920x1200 window
# pixels. Past that the window gets bigger and the content does not, leaving blank
# area inside the window, which looks worse than a smaller window that is full.
# That limit is inside the Arena itself; nothing out here can scale past it.
#
# This does not affect the coordinates the Arena uses to drive the *game*: those
# are absolute screen coordinates for the game window, independent of the Arena's
# own size.
# The size the Arena opens at, used to centre it.
ARENA_W=1500
ARENA_H=1000

# ConstrainWindows=N puts every window exactly where Win32 says, and Win32 opens
# the Arena at 0,0 -- which is underneath the macOS menu bar, so its title bar and
# the top of its UI are unreachable until you drag it. The game needs 0,0 (the
# Arena's coordinates assume it), but the Arena's own window does not, so centre
# it once it appears.
bfme_place_arena() {
  local tool="$BFME_TOOLS/wintool.exe" desktop dw dh x y
  [ -n "${BFME_NO_PLACE_ARENA:-}" ] && return 0
  [ -f "$tool" ] || return 0            # optional
  desktop=$(bfme_desktop_size) || return 0
  dw=${desktop%x*}; dh=${desktop#*x}
  x=$(( (dw - ARENA_W) / 2 )); [ "$x" -lt 0 ] && x=0
  y=$(( (dh - ARENA_H) / 2 )); [ "$y" -lt 0 ] && y=0
  (
    # no "local" in here: this is a subshell, not a function body, and zsh treats
    # local outside a function as an error, which kills the job silently.
    #
    # Waits on the process rather than on macOS window bounds: reading window
    # names through CGWindowList needs Screen Recording permission, which a
    # terminal usually has and an app bundle does not.
    #
    # Repeated because the Arena restarts itself after its update check, and
    # anything done to the first window is lost when it does.
    for i in $(seq 1 180); do
      sleep 1
      pgrep -f BfmeFoundationProject_OnlineArena.exe >/dev/null 2>&1 && break
    done
    for delay in 8 22 30 40; do
      sleep $delay
      pgrep -f BfmeFoundationProject_OnlineArena.exe >/dev/null 2>&1 || break
      bfme_wine "$tool" move "Online Arena" "$x" "$y" >>"${BFME_PLACE_LOG:-/dev/null}" 2>&1
    done
  ) &
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
