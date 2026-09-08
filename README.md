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
| Arena connection test | 7/7 passes |
| Display | full width, nothing clipped, macOS resolution never changed |

## Requirements

- Apple Silicon Mac with Rosetta 2 installed (`softwareupdate --install-rosetta`)
- BFME 1 with patch 2.22 and the BFME Online Arena, installed through the
  [All in One Launcher](https://github.com/MarcellVokk/aio-launcher) into a Wine
  prefix (default here: `~/.wine-aio-custom`)
- The patched Wine build — see [Building](#building)

## Playing

```sh
./arena-bfme.sh     # ranked multiplayer through the Online Arena
./play-bfme.sh      # solo skirmish / campaign
```

Both scripts configure Wine and launch. They never change your macOS display
resolution.

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

## Building

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
```

`run-custom-wine.sh` expects the result in `build-wine/` and the x86_64 support
libraries (freetype, gnutls, MoltenVK, SDL) in `deps-x86_64/lib`. Never wrap it
in `nohup`: that is SIP-protected and strips `DYLD_LIBRARY_PATH`, after which
WPF applications crash in font code.

x87sidecar binaries live in `tools/x87sidecar/`; set `BFME_NO_X87=1` to run
without it.

## Layout

```
arena-bfme.sh        launch the Online Arena (ranked)
play-bfme.sh         launch BFME 1 directly (solo)
bfme-config.sh       shared setup: display scale, virtual desktop, Options.ini
run-custom-wine.sh   Wine wrapper (prefix, library path, x87sidecar)
patches/             the three Wine patches, with what each fixes and why
docs/                findings, including the Arena's game-side protocol
tools/               diagnostics that are still useful; tools/archive/ is history
config/              GameLOD override for lower-end machines
```

`wine/`, `build-wine/`, `deps-x86_64/` and the game installers are not in git —
they are large third-party artifacts. See [Building](#building).
