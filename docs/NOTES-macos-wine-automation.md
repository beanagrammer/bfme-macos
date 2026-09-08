# Driving Wine GUI apps on this Mac without wrecking the desktop

Learned 2026-09-05/06 while getting the BFME All-in-One Launcher and Online Arena running.
Everything here was verified by experiment on macOS 27 (M2 Max) with WineHQ 11.0 (cask) and
our own wine-11.17 build (`run-custom-wine.sh`).

## Screenshots
- Only `screencapture -x -o -l <CGWindowID>` works. It captures one window even when it is
  behind other windows and does not steal focus. Get the id with `tools/winlist`
  (CGWindowList filtered to owner "wine").
- A window moved off-screen (or onto another Space) cannot be captured
  ("could not create image from window"). Keep Wine windows somewhere on the visible desktop.
- Windows-side capture from inside Wine (BitBlt from a window DC, PrintWindow) returns black on
  winemac.drv. Do not bother.

## Input (tools/wintool/wintool.exe, run it with the same WINEPREFIX as the app)
- `click2 <title> x y` posts WM_MOUSEMOVE/LBUTTONDOWN/LBUTTONUP. Enough for WPF tab headers
  and to give a button keyboard focus, but WPF Buttons do not fire Click from posted messages
  (Wine's mouse-leave tracking sees the real cursor elsewhere and cancels the press).
  Same for `sclick` (SendMessage) and `key 13` (posted Enter) when the window is not active.
- `hwclick <title> x y` uses SendInput. This is what actually presses WPF buttons. It warps the
  real cursor for ~0.3 s and puts it back; it does NOT activate the Wine app on the Mac side
  (winemac only activates the app within 2 s of keyboard-driven focus), so the frontmost app
  and keyboard focus stay with whatever you were using.
- Coordinates are client coordinates. From a 1400px-wide screenshot of a 1236pt window:
  x = px * (1236/1400) - 6, y = px * (1236/1400) - 32 (6px border, 32pt caption).
- `listall` dumps every window incl. invisible/child ones (shows cross-process WS_CHILD
  embedding), `move`, `detach`, `show`, `text`, `key` exist too.

## Wine session hygiene
- Never start the custom build through `nohup`: /usr/bin/nohup is SIP-protected and strips
  DYLD_LIBRARY_PATH, Wine then cannot load freetype/gnutls/MoltenVK and WPF apps crash in
  FontFaceLayoutInfo.ComputeTypographyAvailabilities. Use `( run-custom-wine.sh app.exe > log 2>&1 & )`.
- `explorer /desktop=name,WxH` puts the app on a separate Wine desktop; wintool started outside
  that desktop cannot see its windows. Run apps on the default desktop.
- Kill a prefix's session with `wineserver -k` (stock: /opt/homebrew/bin/wineserver,
  custom: build-wine/server/wineserver) before changing its registry or dlls.

## Fully invisible operation (not done yet)
- winemac.drv always shows real Cocoa windows. Options: build winex11 and run under XQuartz's
  Xvfb (XQuartz install needs sudo), a CGVirtualDisplay helper (private API, DeskPad-style), or
  a linux/amd64 Docker container with Xvfb. Posted-message input keeps working in all of them.

## BFME1 Patch 2.22 game launch — the working fix stack (2026-09-06)
The game crashed at startup until ALL THREE of these were applied together (run-custom-wine.sh sets them):
1. `wined3d csmt=0`  (registry HKCU\Software\Wine\Direct3D csmt=0). BFME assumes single-threaded D3D.
2. `WINE_CPU_TOPOLOGY=1:0`  — the SAGE engine races on multi-core; the intermittent null-object crash
   (EAX=0, reads [eax+0x5dc9]) only stops when the game sees ONE cpu. Neither lever alone is enough.
3. A **Wine virtual desktop** (`HKCU\Software\Wine\Explorer` Desktop=Default, `...\Explorer\Desktops` Default=1280x720)
   so the game's fullscreen renders into a window — no real display-mode switch. Fullscreen without a
   virtual desktop still crashes even with 1+2. With all three: 0 crashes, reliably reaches the 2.22 main menu.
Screenshots of the D3D game only show via full-screen `screencapture -x` (winemac presents through a Metal
layer that per-window capture returns black for).

## Where the Arena compat test stands
Arena launches the game (-noshellmap), overlay 'ARENA API v450' logs to BFME1/arenaapilog.txt and reaches
'first frame presented, viewport 1280x720', then runs an in-game 'SYSTEM TEST'. It fails at the networking
step ('Failed to create ingame room') so the game exits and Arena's Bfme1Client.WaitForMainMenu() cancels.
Next levers: BFME_PROXY_UPNP=0 / BFME_PROXY_NATPMP=0 env (Arena relay proxy), or RE the overlay<->Arena IPC.
