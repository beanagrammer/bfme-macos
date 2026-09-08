#!/bin/zsh
# Re-check whether the old workarounds are still needed now that the WoW64
# mode-switch bugs are fixed. Each cell is a full launch-bench run.
set -u
OUT="${1:?}"; N="${2:-10}"; mkdir -p "$OUT"
B=/Users/beanagrammer/Projects/BFME/tools/launch-bench.sh
echo "== with topology pin (current default) =="
WINE_CPU_TOPOLOGY=1:0 "$B" "$OUT/topo_on" "$N" topo_on | tail -2
echo "== without topology pin =="
WINE_CPU_TOPOLOGY= "$B" "$OUT/topo_off" "$N" topo_off | tail -2
