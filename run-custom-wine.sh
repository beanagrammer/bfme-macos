#!/bin/zsh
# Run a program under the patched Wine build that ships with this repo.
#
# Do NOT wrap this in nohup: /usr/bin/nohup is SIP-protected and strips
# DYLD_LIBRARY_PATH, after which Wine cannot find freetype/gnutls/MoltenVK and
# WPF apps (the Arena, the launcher) crash in font code.
set -u
ROOT="${0:A:h}"

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-aio-custom}"
export DYLD_LIBRARY_PATH="$ROOT/deps-x86_64/lib"
export WINEDEBUG="${WINEDEBUG:--all}"
export MVK_CONFIG_LOG_LEVEL=0

# WINE_CPU_TOPOLOGY=1:0 used to be needed because BFME1 raced on multi-core and
# crashed at startup.  That was really the Rosetta WoW64 mode-switch bug (patch
# 0001); with it fixed all cores are reliable, so nothing is pinned by default.
# Set WINE_CPU_TOPOLOGY=1:0 explicitly to restore the old single-core behaviour.
if [ -n "${WINE_CPU_TOPOLOGY:-}" ] && [ "${WINE_CPU_TOPOLOGY}" != "off" ]; then
  export WINE_CPU_TOPOLOGY
else
  unset WINE_CPU_TOPOLOGY
fi

# The Arena's relay tries to punch a hole through the router; under Wine there is
# no router access and the attempt just hangs, so turn it off.
export BFME_PROXY_UPNP="${BFME_PROXY_UPNP:-0}"
export BFME_PROXY_NATPMP="${BFME_PROXY_NATPMP:-0}"
export BFME_PROXY_IPV6="${BFME_PROXY_IPV6:-0}"

# Rosetta emulates x87 in software, roughly 35x slower than SSE2/integer, and
# BFME is full of x87.  x87sidecar JITs those instructions to ARM64 instead and
# is what takes a skirmish load from minutes to seconds.  Needs patch 0002.
# Set BFME_NO_X87=1 to run without it.
X87="$ROOT/tools/x87sidecar/x87sidecar"
if [ -z "${BFME_NO_X87:-}" ] && [ -x "$X87" ]; then
  export ROSETTA_X87_PATH="$X87"
fi

exec "$ROOT/build-wine/loader/wine" "$@"
