#!/bin/zsh
# Launch the BFME Online Arena for ranked play.
#
# See bfme-config.sh for why the game is pinned to 2560x1440 and how it is still
# made to fill the screen without touching the macOS display mode.
set -u
BFME_ROOT="${0:A:h}"
source "$BFME_ROOT/bfme-config.sh"

ARENA="C:\\users\\$USER\\AppData\\Roaming\\BFME Competetive Arena\\BfmeFoundationProject_OnlineArena.exe"

echo "Stopping any running Wine processes..."
bfme_stop_wine

echo "Configuring Wine..."
bfme_configure

echo "Launching the Online Arena..."
exec "$WINE" "$ARENA"
