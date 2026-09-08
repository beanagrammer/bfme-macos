#!/bin/zsh
# Run a program with the STOCK WineHQ 11.0 cask build, same fixes as the custom build.
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-aio-stock}"
export WINEDEBUG="${WINEDEBUG:--all}"
export MVK_CONFIG_LOG_LEVEL=0
export WINE_CPU_TOPOLOGY="${WINE_CPU_TOPOLOGY:-1:0}"
export BFME_PROXY_UPNP="${BFME_PROXY_UPNP:-0}"
export BFME_PROXY_NATPMP="${BFME_PROXY_NATPMP:-0}"
exec /opt/homebrew/bin/wine "$@"
