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

mkdir -p "$OUT"
TARBALL="$OUT/bfme-wine-$VERSION-arm64.tar.zst"
echo "Compressing (this takes a minute)..."
tar -C "$STAGE" -cf - bfme-wine | zstd -19 -T0 -q -o "$TARBALL"
shasum -a 256 "$TARBALL" | sed "s|$OUT/||" > "$TARBALL.sha256"

echo
echo "$TARBALL"
echo "  $(du -h "$TARBALL" | cut -f1) compressed, $(du -sh "$BUNDLE" | cut -f1) installed"
echo "  $(cat "$TARBALL.sha256")"
