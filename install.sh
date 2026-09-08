#!/bin/zsh
# One-time setup for BFME on macOS.
#
#   git clone https://github.com/YOUR-USER/bfme-macos.git
#   cd bfme-macos && ./install.sh
#
# Installs a patched Wine, creates a prefix, runs the official All in One
# Launcher installer inside it, and puts double-clickable apps in ~/Applications.
# Nothing is installed system-wide and your display settings are never changed.
set -u
REPO="${0:A:h}"
APP_SUPPORT="$HOME/Library/Application Support/bfme-macos"
WINE_DIR="$APP_SUPPORT/wine"
APP_DIR="$APP_SUPPORT/app"
LAUNCHER_URL="https://bfmeladder.com/download-go?app=aio"

die() { print -r -- "FATAL: $*" >&2; exit 1; }
step() { print -r -- ""; print -r -- "==> $*"; }

# ---------------------------------------------------------------- preconditions
step "Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || die "this installer is macOS only"
[ "$(uname -m)" = "arm64" ] || die "this build targets Apple Silicon; you are on $(uname -m)"
if ! /usr/bin/pgrep -q oahd && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  die "Rosetta 2 is required. Install it with:
    softwareupdate --install-rosetta --agree-to-license"
fi
print -r -- "  macOS $(sw_vers -productVersion) on $(uname -m), Rosetta 2 present"

# --------------------------------------------------------------------- the wine
step "Installing the patched Wine runtime"
TARBALL="${BFME_WINE_TARBALL:-}"
if [ -z "$TARBALL" ]; then
  [ -f "$REPO/dist/wine-release.txt" ] \
    || die "no dist/wine-release.txt and no BFME_WINE_TARBALL set, so there is nothing to download"
  URL=$(grep -v '^#' "$REPO/dist/wine-release.txt" | grep -m1 . ) \
    || die "dist/wine-release.txt has no URL in it"
  TARBALL="$APP_SUPPORT/$(basename "$URL")"
  mkdir -p "$APP_SUPPORT"
  if [ ! -f "$TARBALL" ]; then
    print -r -- "  downloading $URL"
    curl -fL --progress-bar -o "$TARBALL.part" "$URL" || die "download failed"
    mv "$TARBALL.part" "$TARBALL"
  else
    print -r -- "  already downloaded: $TARBALL"
  fi
fi
[ -f "$TARBALL" ] || die "Wine bundle not found: $TARBALL"

if [ -f "$TARBALL.sha256" ] || [ -f "$REPO/dist/$(basename "$TARBALL").sha256" ]; then
  SUMFILE="$TARBALL.sha256"; [ -f "$SUMFILE" ] || SUMFILE="$REPO/dist/$(basename "$TARBALL").sha256"
  WANT=$(awk '{print $1}' "$SUMFILE")
  GOT=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
  [ "$WANT" = "$GOT" ] || die "checksum mismatch for $TARBALL
    expected $WANT
    got      $GOT"
  print -r -- "  checksum ok"
else
  print -r -- "  no checksum file alongside the bundle; skipping verification"
fi

rm -rf "$WINE_DIR"
mkdir -p "$WINE_DIR"
tar -C "$WINE_DIR" --strip-components=1 -xf "$TARBALL" --use-compress-program=unzstd \
  || die "could not extract $TARBALL"
# This macOS ships an xattr without -r, so walk the tree. Only matters when the
# bundle was fetched with a browser; curl does not set the quarantine flag.
find "$WINE_DIR" -exec xattr -d com.apple.quarantine {} + >/dev/null 2>&1 || true
[ -x "$WINE_DIR/bin/wine" ] || die "extracted bundle has no bin/wine"
DYLD_LIBRARY_PATH="$WINE_DIR/deps/lib" WINEDEBUG=-all "$WINE_DIR/bin/wine" --version >/dev/null 2>&1 \
  || die "the installed Wine does not run"
print -r -- "  Wine $(cat "$WINE_DIR/WINE_VERSION" 2>/dev/null || echo '?') installed in $WINE_DIR"

# ------------------------------------------------------------------- the launcher scripts
step "Installing the launcher scripts"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/tools"
for f in bfme bfme-config.sh; do
  [ -f "$REPO/$f" ] || die "missing $f in $REPO -- run this from a clone of the repo"
  cp "$REPO/$f" "$APP_DIR/"
done
cp "$REPO/tools/listmodes" "$APP_DIR/tools/" || die "missing tools/listmodes"
chmod +x "$APP_DIR/bfme"
print -r -- "  $APP_DIR"

# ---------------------------------------------------------------------- prefix
step "Preparing the Wine prefix"
"$APP_DIR/bfme" bootstrap || die "prefix setup failed"

# --------------------------------------------------------------- the aio launcher
step "Installing the BFME All in One Launcher"
PREFIX=$("$APP_DIR/bfme" prefix-path)
if [ -d "$PREFIX/drive_c/users/$USER/AppData/Roaming/BFME All In One Launcher" ]; then
  print -r -- "  already installed, skipping"
else
  SETUP="$APP_SUPPORT/AllInOneLauncherSetup.exe"
  if [ ! -f "$SETUP" ]; then
    print -r -- "  downloading the launcher from bfmeladder.com (about 270 MB)"
    curl -fL --progress-bar -o "$SETUP.part" "$LAUNCHER_URL" || die "launcher download failed"
    mv "$SETUP.part" "$SETUP"
  fi
  print -r -- "  running the installer -- follow its window, then come back here"
  "$APP_DIR/bfme" run "$SETUP" || die "the launcher installer did not complete"
fi

# ------------------------------------------------------------------- app bundles
step "Creating apps in ~/Applications"
"$APP_DIR/bfme" make-apps || die "could not create the app bundles"

print -r -- ""
print -r -- "Done."
print -r -- ""
print -r -- "  ~/Applications/BFME Launcher.app   install and patch the game, then play"
print -r -- "  ~/Applications/BFME Arena.app      ranked multiplayer"
print -r -- "  ~/Applications/BFME Solo.app       skirmish and campaign"
print -r -- ""
print -r -- "Open the Launcher first and let it install BFME 1 with patch 2.22."
print -r -- "Command line equivalent: $APP_DIR/bfme launcher | arena | play | doctor"
