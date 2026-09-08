# Driving the BFME Launcher / Online Arena / game under Wine on macOS

How this session automated the WPF Arena and the D3D game **without disturbing the
Mac desktop** (no focus stealing, cursor restored). Reproducible playbook.

## 0. Start everything

```bash
# The Arena (standalone is fine; login persists in the prefix):
( ~/Projects/BFME/run-custom-wine.sh \
  "C:\\users\\beanagrammer\\AppData\\Roaming\\BFME Competetive Arena\\BfmeFoundationProject_OnlineArena.exe" \
  > /tmp/arena.log 2>&1 & )
# The launcher:
( ~/Projects/BFME/run-custom-wine.sh \
  "C:\\users\\beanagrammer\\AppData\\Roaming\\BFME All In One Launcher\\AllInOneLauncher.exe" \
  > /tmp/launcher.log 2>&1 & )
```
Never wrap in `nohup` — SIP strips DYLD_LIBRARY_PATH and WPF then crashes in font code.
`run-custom-wine.sh` already exports the fixes (csmt via registry, WINE_CPU_TOPOLOGY=1:0,
virtual desktop via registry, MVK_CONFIG_LOG_LEVEL=0, BFME_PROXY_* off, WINEDEBUG=-all).

## 1. Find window ids

- Host CGWindow id (for screenshots): `tools/winlist` prints `id=<CGWindowID> ... owner=wine name="..."`.
- Windows HWNDs (for clicks): `run-custom-wine.sh tools/wintool/wintool.exe listall`
  (dumps every top-level + child window: hwnd, pid, vis, child, parent, style, rect, class, title).

## 2. Screenshots (no focus change)

- **WPF windows (launcher, Arena):** `screencapture -x -o -l <CGWindowID> out.png`.
  Captures one window even when behind others; does NOT steal focus.
- **The D3D game:** per-window capture returns BLACK (winemac presents through a Metal layer
  that off-screen capture misses). Use full-screen `screencapture -x out.png` to see the game.
- A window moved off-screen / onto another Space cannot be captured. Keep windows on the desktop.
- Shrink for viewing: `sips -Z 1400 out.png --out small.png`.

## 3. Input — tools/wintool/wintool.exe (run with the app's WINEPREFIX)

Commands: `list | listall | find <title> | shot <title> <out.bmp> | move <title> x y |
detach <hwnd> | show <hwnd> | click|click2|sclick <title> x y | hwclick <title> x y |
wheel <title> x y <notches> | text <title> <str> | key <title> <vk>`

- **Use `hwclick` for WPF buttons.** It uses SendInput (real absolute mouse move+click from
  ClientToScreen coords), warps the cursor for ~0.3s and **restores it**, and does NOT activate
  the Wine app (winemac only activates within 2s of keyboard-driven focus). Posted-message
  clicks (`click2`, `sclick`) only *focus* WPF buttons; they don't fire Click.
- `wheel <title> x y -N` scrolls (SendInput wheel) — for long settings pages.
- `x y` are **client** coordinates of the titled HWND.

## 4. Coordinate calibration

Coordinates depend on the Arena window size. With the **1280x720 virtual desktop** (current setup)
the Arena fills the desktop; a 1400-wide screenshot maps to client coords by ~×0.914 in x, and in y
by: `client_y ≈ 187 + (shot_y − 243) × 0.92` (anchor: the sidebar item at client y=187 sits at
screenshot y≈243). Re-anchor from a fresh screenshot whenever the window size changes.

## 5. Ranked BFME 1 Patch 2.22 compat-test navigation (1280x720 desktop)

Client-coord `hwclick "Online Arena" x y`, ~3-4s between steps, screenshot to verify each:
1. Play submenu:            `45 152`  (also expands the Ranked/Freeplay/... submenu)
2. Ranked:                  `68 187`
3. BFME 1 "Patch 2.22" card:`388 384` (the Eye-of-Sauron tile in the BFME1 column)
4. "Sync to join" CONTINUE: `751 458`
5. Failure dialog OKAY:     `645 455`

## 6. Monitoring the compat test (no Wine spawns in the loop)

- Game process: `pgrep -f lotrbfme.exe`.
- Overlay log (truth of the test): `~/.wine-aio-custom/drive_c/BFME1/arenaapilog.txt`
  — watch for `first frame presented`, then the SYSTEM TEST / room-creation lines.
  It contains non-UTF8 bytes; pipe through `sed 's/[^[:print:]]//g'` before `cut`.
- Crash minidumps: `BFME1/DUMP-*.dmp` (parse with the minidump reader used in-session:
  streams 4=modules, 6=exception, 3=threads; MINIDUMP_MODULE is 108 bytes, nameRva at +20;
  thread entry 48 bytes, ThreadContext loc at +40; CONTEXT_i386 Eip@0xb8 Ebp@0xb4 Esp@0xc4).
- Arena C# stdout log (the launch/handshake stack): the run*.log you redirected the Arena to.

## 7. Gotchas

- `sed -i '' 's#...#...#'` breaks when the replacement contains `#`; rewrite the file with a
  heredoc instead (bit me twice editing run-custom-wine.sh).
- Calling `wintool listall` inside a tight poll loop is slow (each spawns Wine). Poll `pgrep`
  + read files instead; only call wintool when you need window geometry.
- The virtual desktop makes the Arena a single host window at the desktop size; layout reflows,
  so recalibrate coordinates after changing the desktop size.

## Window position is what matters — but not via pinning (corrected)

An earlier version of this file said the game window had to be pinned to 0,0 with
`wintool.exe pin` and forced foreground. That was the wrong conclusion drawn from
a correlation. Pinning the *Win32* window to 0,0 does not fix anything: Cocoa
keeps its own frame, and the pointer the Arena drives still lands offset.

What actually matters is that the Wine window sits at the true top-left of the
screen, so that the absolute coordinates the Arena sends (`inputMove 700 1357`,
`inputClick 2415 1357`, …) address the pixels it thinks they do. Cocoa pushes any
window that does not cover a whole screen below the menu bar, which shifts the
Win32 origin down by the menu bar height and makes every one of those coordinates
miss. `ConstrainWindows=N` (patch 0003) is the fix; see
[HOW-IT-WORKS.md](HOW-IT-WORKS.md).

Making the Wine app frontmost on macOS is still required — `GetForegroundWindow()`
inside Wine returns NULL whenever another macOS app is active:

```sh
APID=$(pgrep -f BfmeFoundationProject_OnlineArena.exe | head -1)
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APID) to true"
```

## Reading the Arena's state without a log file

`LogDiagnostic` only invokes a static `OnDiagnostic` event; there is no log file. Use
instead:

* `~/.wine-aio-custom/drive_c/BFME1/arenaapilog.txt` — the add-on's own log
  (`first frame presented` is the milestone that matters).
* `.../BFME Competetive Arena/Settings/arena_onlineTestCompletedForBFME1.json` —
  `true` once the connection test has passed.
* `screencapture -x -o -l <CGWindowID>` on the Arena window, then
  `sips -s format png` to view it. `wintool shot` returns black for WPF.

## Inspecting the Arena <-> add-on pipe

* `wintool apisrv <pipename> <secs>` impersonates the add-on and logs Arena requests.
* `wintool apiproxy <listen> <upstream> <secs>` proxies and logs both directions.
  To use it, watch for `arena_api_interface.conf`, replace the GUID the add-on will
  read, and proxy the Arena's original GUID to the new one.
