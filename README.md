# BFME on macOS

The Battle for Middle-earth 1 (patch 2.22) running under Wine on Apple Silicon,
fast enough to play and passing the BFME Online Arena's connection test, so
ranked multiplayer works.

Measured on an M2 Max, macOS 27, 1728x1117 display:

| | |
|---|---|
| Graphics | UltraHigh, 2560x1440 |
| Skirmish load | 19.3 s |
| In-game frame rate | 38.3 fps (the engine's cap) |
| Arena connection test | 11/11 passes, including from the packaged build |
| Display | full width, nothing clipped, macOS resolution never changed |

## Install

```sh
git clone https://github.com/beanagrammer/bfme-macos.git
cd bfme-macos
./install.sh
```

That downloads a patched Wine (97 MB), creates a prefix, runs the official
All in One Launcher installer inside it, and puts three apps in `~/Applications`:

| | |
|---|---|
| **BFME Launcher** | install and patch the game, mods, maps — open this first |
| **BFME Arena** | ranked multiplayer |
| **BFME Solo** | skirmish and campaign |

Everything lives in `~/Library/Application Support/bfme-macos`. Nothing is
installed system-wide and your display settings are never changed. To remove it,
delete that folder and the three apps.

Command line equivalent, if you prefer:

```sh
bfme launcher | arena | play | doctor
```

`bfme doctor` prints what it found and what is missing — start there if something
looks wrong.

### Requirements

- Apple Silicon Mac with Rosetta 2 (`softwareupdate --install-rosetta --agree-to-license`)
- A legitimate copy of BFME 1. The launcher installs patch 2.22 and the Arena;
  it does not provide the game itself.

Nothing here redistributes EA's game or the All in One Launcher — the installer
fetches the launcher from bfmeladder.com, the same place its Windows users get it.

## Why it needs any of this

Three problems had to be solved, and each has a patch in [`patches/`](patches/README.md):

1. **Launches failed about 60% of the time.** Rosetta mis-executes the far
   indirect jump Wine's WoW64 layer uses to switch between 32- and 64-bit mode.
   Patch 0001 replaces it with sequences Rosetta gets right. 4/10 → 10/10.

2. **A skirmish took eight minutes to load.** Rosetta emulates x87 floating point
   in software at roughly 1/35th speed, and BFME is a 2004 game built on x87.
   Patch 0002 routes those instructions through x87sidecar, which JITs them to
   ARM64. 470 s → 19 s, and 20 fps → 38 fps.

3. **The game was either cut off or unplayable online.** The Arena drives the
   game by sending absolute screen coordinates over a named pipe — `inputMove`,
   `inputClick` and `getPixelColor` at constants like `2415,1357` — which are
   compile-time constants for a 2560x1440 game at `0,0`. So the resolution cannot
   change, and a 2560x1440 window does not fit a 1728x1117 screen. Patch 0003
   lets Wine scale a virtual desktop by an arbitrary factor and stops Cocoa
   pushing the window below the menu bar (which shifted every coordinate down and
   made the Arena click empty space).

[`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) has the details, including the
Arena's game-side protocol.

## Building Wine yourself

The release bundle is built from Wine 11.17 with the three patches in
[`patches/`](patches/README.md):

```sh
git clone https://gitlab.winehq.org/wine/wine.git
cd wine && git checkout wine-11.17
for p in ../patches/*.patch; do git apply "$p"; done
cd .. && mkdir build-wine && cd build-wine
../wine/configure --build=x86_64-apple-darwin --enable-archs=i386,x86_64 \
  --disable-tests --without-x --without-wayland --without-gstreamer \
  --without-gettext --without-krb5 --without-gssapi --without-netapi \
  --without-cups --without-pcap --without-pcsclite --without-dbus \
  --without-alsa --without-oss --without-capi --without-gphoto --without-sane \
  --without-usb --without-udev --without-v4l2 --without-inotify \
  --without-opengl --with-mingw --with-vulkan --with-coreaudio \
  --with-freetype --with-gnutls --with-sdl
make -j8
cd .. && ./dist/package-wine.sh
```

You also need the x86_64 support libraries (freetype, gnutls, MoltenVK, SDL) in
`deps-x86_64/lib`. [`dist/RELEASING.md`](dist/RELEASING.md) covers publishing the
result.

Never wrap the Wine wrapper in `nohup`: that is SIP-protected and strips
`DYLD_LIBRARY_PATH`, after which WPF applications crash in font code.

## Layout

```
install.sh           one-time setup
bfme                 the CLI everything else goes through
bfme-config.sh       locating Wine and the prefix, plus the display configuration
dist/                packaging the redistributable Wine bundle, and how to release it
patches/             the three Wine patches, with what each fixes and why
docs/                findings, including the Arena's game-side protocol
tools/               diagnostics that are still useful; tools/archive/ is history
config/              GameLOD override for lower-end machines
```

`wine/`, `build-wine/`, `deps-x86_64/`, the game installers and the release
tarball are not in git — they are large third-party or generated artifacts.

## Licence

GPL-3.0-or-later — see [`LICENSE`](LICENSE). The Wine patches derive from Wine
(LGPL-2.1-or-later) and the release bundle ships a compiled Wine under Wine's own
licence; [`NOTICE`](NOTICE) records what that requires.
