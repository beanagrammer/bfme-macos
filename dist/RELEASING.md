# Cutting a release

The Wine runtime is too big for git, so it lives as a GitHub release asset and
`install.sh` downloads it.

```sh
./dist/package-wine.sh            # -> dist/bfme-wine-<version>-arm64.tar.zst (+ .sha256)
gh release create wine-11.17 \
  dist/bfme-wine-11.17-arm64.tar.zst \
  --title "Wine 11.17 for BFME" \
  --notes "Patched Wine 11.17 runtime. See patches/README.md."
```

Then point `dist/wine-release.txt` at the uploaded asset and commit both it and
the `.sha256` file, so `install.sh` can verify what it downloads.

## What is in the bundle

`bin/`, `lib/`, `share/` from `make install-lib` with debug info stripped, plus
`deps/` (the x86_64 freetype/gnutls/MoltenVK/SDL that Wine links against) and
`x87sidecar/`. About 97 MB compressed, 470 MB installed. It is relocatable —
tested from three different directories.

## Checklist before publishing

- `./dist/package-wine.sh` succeeds (it refuses to package a Wine that will not run)
- `BFME_WINE_TARBALL=dist/<tarball> ./install.sh` on a machine that has never had this
- `bfme doctor` reports everything installed
- the Arena connection test passes from `~/Applications/BFME Arena.app`

## Later: a Homebrew tap

A cask would remove the clone-and-run step and handle updates:
`brew tap YOUR-USER/bfme && brew install --cask bfme-macos`. The cask would
depend on Rosetta, fetch the same release asset, and run `install.sh --no-wine`.
Not built yet.
