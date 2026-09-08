#!/bin/zsh
# Launch BFME 1 directly for solo play (skirmish, campaign).
#
# Uses exactly the same display setup as the Arena launcher, so what you see here
# is what ranked games look like.
set -u
BFME_ROOT="${0:A:h}"
source "$BFME_ROOT/bfme-config.sh"

GAME_DIR="$PREFIX/drive_c/BFME1"
[ -x "$GAME_DIR/lotrbfme.exe" ] || bfme_die "BFME 1 not found at $GAME_DIR/lotrbfme.exe"

echo "Stopping any running Wine processes..."
bfme_stop_wine

echo "Configuring Wine..."
bfme_configure

echo "Launching BFME 1..."
cd "$GAME_DIR" || bfme_die "could not enter $GAME_DIR"
exec "$WINE" "$GAME_DIR/lotrbfme.exe" -noshellmap
