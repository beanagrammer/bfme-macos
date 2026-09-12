#!/bin/zsh
# Build the redistributable Wine runtime from a patched build tree.
#
# Produces dist/bfme-wine-<version>-arm64.tar.zst plus a SHA256 file, ready to
# attach to a GitHub release. About 90 MB compressed, 440 MB on disk.
set -eu
ROOT="${0:A:h:h}"
BUILD="$ROOT/build-wine"
OUT="$ROOT/dist"
STAGE=$(mktemp -d -t bfme-pkg)
trap 'rm -rf "$STAGE"' EXIT

[ -x "$BUILD/loader/wine" ] || { echo "FATAL: no build tree at $BUILD -- see README" >&2; exit 1; }
VERSION=$("$BUILD/loader/wine" --version 2>/dev/null | sed 's/^wine-//') \
  || { echo "FATAL: could not read the Wine version" >&2; exit 1; }
echo "Packaging Wine $VERSION"

# install-lib is the runtime half: no headers, no man pages.
make -C "$BUILD" -j"$(sysctl -n hw.ncpu)" install-lib DESTDIR="$STAGE" >/dev/null \
  || { echo "FATAL: make install-lib failed" >&2; exit 1; }

# Unstripped PE objects carry DWARF from mingw: 1.5 GB -> 440 MB.
echo "Stripping debug info..."
find "$STAGE" \( -name '*.dll' -o -name '*.exe' \) -print0 \
  | xargs -0 -P "$(sysctl -n hw.ncpu)" -n 20 x86_64-w64-mingw32-strip 2>/dev/null || true
find "$STAGE" -name '*.so' -print0 \
  | xargs -0 -P "$(sysctl -n hw.ncpu)" -n 20 strip -x 2>/dev/null || true
strip -x "$STAGE"/usr/local/bin/* 2>/dev/null || true

BUNDLE="$STAGE/bfme-wine"
mkdir -p "$BUNDLE"
mv "$STAGE"/usr/local/bin "$STAGE"/usr/local/lib "$STAGE"/usr/local/share "$BUNDLE/"
cp -R "$ROOT/deps-x86_64" "$BUNDLE/deps"
cp -R "$ROOT/tools/x87sidecar" "$BUNDLE/x87sidecar"
printf '%s\n' "$VERSION" > "$BUNDLE/WINE_VERSION"

# Sanity check before shipping: the copy in its new location must actually run.
DYLD_LIBRARY_PATH="$BUNDLE/deps/lib" WINEDEBUG=-all "$BUNDLE/bin/wine" --version >/dev/null \
  || { echo "FATAL: the packaged Wine does not run" >&2; exit 1; }

# And the x87 JIT must actually accelerate something. It fails silently -- the
# sidecar starts, its probe passes, and everything runs at Rosetta's software-x87
# speed -- so a bundle has shipped broken twice without this check. Use the real
# loader, never bin/wine: that stub re-execs and drops the sidecar's hook.
BENCH="$ROOT/tools/x87check/x87bench.exe"
LOADER="$BUNDLE/lib/wine/x86_64-unix/wine"
if [ -f "$BENCH" ] && [ -x "$LOADER" ]; then
  echo "Checking the x87 JIT..."
  run_bench() {
    WINEPREFIX="${WINEPREFIX:-$HOME/.wine-aio-custom}" WINEDEBUG=-all \
    DYLD_LIBRARY_PATH="$BUNDLE/deps/lib" ${1:+ROSETTA_X87_PATH="$BUNDLE/x87sidecar/x87sidecar"} \
      "$LOADER" "$BENCH" 20000000 2>/dev/null | sed -n 's/.*(\([0-9.]*\) Miter.*/\1/p'
  }
  JIT=$(run_bench 1); NOJIT=$(run_bench "")
  [ -n "$JIT" ] && [ -n "$NOJIT" ] \
    || { echo "FATAL: could not measure the x87 JIT in the packaged bundle" >&2; exit 1; }
  RATIO=$(awk -v a="$JIT" -v b="$NOJIT" 'BEGIN{ if (b>0) printf "%.1f", a/b; else print "0" }')
  echo "  $JIT Miter/s with the JIT, $NOJIT without (${RATIO}x)"
  [ "$(awk -v r="$RATIO" 'BEGIN{print (r < 3) ? 1 : 0}')" = "1" ] \
    && { echo "FATAL: the x87 JIT is not working in this bundle; refusing to ship it." >&2
         echo "       See docs/HOW-IT-WORKS.md -- usually bin/wine or a leaked X87_SIDECAR_ACTIVE." >&2
         exit 1; }
else
  echo "WARNING: no x87 benchmark to verify the JIT with" >&2
fi

mkdir -p "$OUT"
TARBALL="$OUT/bfme-wine-$VERSION-arm64.tar.zst"
echo "Compressing (this takes a minute)..."
rm -f "$TARBALL"        # zstd refuses to overwrite, and a stale tarball is worse than none
tar -C "$STAGE" -cf - bfme-wine | zstd -19 -T0 -q -o "$TARBALL"
shasum -a 256 "$TARBALL" | sed "s|$OUT/||" > "$TARBALL.sha256"

echo
echo "$TARBALL"
echo "  $(du -h "$TARBALL" | cut -f1) compressed, $(du -sh "$BUNDLE" | cut -f1) installed"
echo "  $(cat "$TARBALL.sha256")"
