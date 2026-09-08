# BFME All-in-One Launcher + Online Arena on macOS (Apple Silicon) — Breakthroughs

> **This is a chronological log, not a description of the current setup.** Later
> entries supersede earlier ones, and several conclusions recorded here were later
> shown to be wrong — notably that window pinning and foreground state were what
> made the Arena connection test pass. For what is actually true now, read
> [HOW-IT-WORKS.md](HOW-IT-WORKS.md).

Goal: run the BFME All-in-One Launcher and the Online Arena, and **pass the BFME 1
competitive Patch 2.22 compatibility test**, on the M2 Max MacBook (macOS 27) using a
custom Wine clone — mirroring the Linux setup.

Status legend: ✅ done · 🟡 partial · ❌ blocker

---

## TL;DR status (2026-09-06)

- ✅ Launcher (AllInOneLauncher.exe) runs, WPF UI correct.
- ✅ Online Arena (BfmeFoundationProject_OnlineArena.exe) runs standalone; Google login done; full UI navigable.
- ✅ BFME 1 + Patch 2.22 installed via the launcher/Arena to `C:\BFME1`.
- ✅ **BFME 1 Patch 2.22 game launches and renders its main menu reliably** (the big win).
- ✅ Compatibility test **executes**: Arena injects "ARENA API v450", confirms BFME1 signature,
  logs `first frame presented, viewport 1280x720`, runs the in-game "SYSTEM TEST".
- ❌ **P1 — connection/compat test does not PASS**: the SYSTEM TEST's "create ingame room"
  (networking via the Arena relay proxy) fails under Wine, so `Bfme1Client.WaitForMainMenu()`
  cancels → "GAME LAUNCH FAILED: A task was canceled."
- 🟡 **P2 — intermittent early-exit**: ~40% of Arena-driven launches the game exits cleanly at
  ~10s after loading d3d9, before presenting. Direct (non-Arena) launches present every time,
  so it's tied to the overlay injection. Likely needs fixing anyway to make P1 reliable.

Feasibility: the upstream Wine commit that enables the Arena overlay
(`d3d9: Add a fake d3d9 device vtbl initialization sequence`, author redacted,
in wine ≥ 11.9) is written *for* "BFME Online Arena" and is already in our build — proof the
Arena works on Linux Wine and that our rendering/hook layer is correct. P1 is achievable.

---

## The environment (all under ~/Projects/BFME)

| Path | What |
|------|------|
| `wine/` | upstream Wine source, tag **wine-11.17** (blobless clone) |
| `build-wine/` | our x86_64 build (loader/wine, server/wineserver, dlls/*.so) |
| `deps-x86_64/lib/` | private copies of the cask's bundled dylibs (freetype, gnutls, SDL2, MoltenVK, …) with absolute install-names, so the build links/loads them |
| `casklib` | symlink → `/Applications/Wine Stable.app/.../wine/lib` (space-free path for configure) |
| `run-custom-wine.sh` | **the launcher script** — sets prefix, DYLD path, and all env fixes, then execs our wine |
| `tools/wintool/wintool.exe` | mingw helper to drive Wine windows (see DRIVING-THE-ARENA.md) |
| `tools/winlist` | Swift CGWindowList enumerator (host-side window ids) |
| `~/.wine-aio-custom` | the working 64-bit prefix (launcher + Arena + game + Patch 2.22) |
| `~/.wine-aio-stock` | scratch prefix on the stock WineHQ 11.0 cask |

Build recipe (already done): configure with `--enable-archs=i386,x86_64 --without-x
--with-mingw --with-vulkan --with-freetype --with-gnutls --with-sdl --without-opengl`,
using `PKG_CONFIG_LIBDIR=<empty>` and `*_CFLAGS/_LIBS` pointing at `deps-x86_64/lib` +
arm64-brew headers + `brew install bison vulkan-headers`. Then `make -j`.

## THE GAME FIX STACK (why BFME 1 finally runs)

The game crashed at startup until **all three** were applied together. Each alone is not enough.
All three are set by `run-custom-wine.sh` + the prefix registry:

1. **wined3d CSMT off** — `HKCU\Software\Wine\Direct3D` `csmt`=REG_DWORD `0`.
   BFME assumes single-threaded D3D; CSMT ran D3D on a worker thread that hit a null object.
2. **Single CPU** — `WINE_CPU_TOPOLOGY=1:0`. The SAGE engine races on multi-core at startup;
   the intermittent access violation (EAX=0, read of `[eax+0x5dc9]`) only stops when the game
   sees one CPU. (Earlier topology-only test failed because CSMT was still on.)
3. **Wine virtual desktop** — `HKCU\Software\Wine\Explorer` `Desktop`=`Default`,
   `HKCU\Software\Wine\Explorer\Desktops` `Default`=`1280x720`. The game's fullscreen
   display-mode switch crashes even with 1+2; rendering into a desktop window avoids it.

Result: 0 crashes across runs, reliably reaches the Patch 2.22 main menu.
Also set: `MVK_CONFIG_LOG_LEVEL=0` (silence MoltenVK), `WINEDEBUG=-all`.
Untested lever for P1 networking: `BFME_PROXY_UPNP=0 BFME_PROXY_NATPMP=0 BFME_PROXY_IPV6=0`
(now in the script; the Arena reads these for its relay proxy).

## Compat-test evidence (good run)

`~/.wine-aio-custom/drive_c/BFME1/arenaapilog.txt`:
```
Latency: BFME1 1.03 confirmed by signature; earlysend=1 ...
SageDiag: BFME1 1.03 identified. Per-frame instrument armed on the Present path.
[Firewall] hooks installed (CoCreateInstance=yes, CoCreateInstanceEx=yes)
Overlay: d3d9.dll loaded after ~3.4s
Overlay: device vtable found after 0ms
Overlay: D3D9 hooks attached, waiting for the first presented frame
Overlay: first frame presented, viewport 1280x720
SageDiag: Present thread MATCHES the main thread. Pumping is permitted.
[Firewall] wrapped CLSID_NetFwMgr — get_Enabled overrides now active
```
Then in-game "SYSTEM TEST / LOADING" (ARENA API v450) → fails at ingame-room creation.

## Failure signatures

- Arena C# (in its stdout log): `BfmeSessionManager.Launch failed: TaskCanceledException` at
  `Bfme1Client.WaitForMainMenu()` → `WaitWhileBounded(...timeoutSeconds)`.
- Arena UI dialogs: "GAME LAUNCH FAILED: A task was canceled" and, earlier,
  "Connection test failed: Failed to create ingame room" (`arena.failedToCreateIngameRoom`).
- WPF renders blank white until `HKCU\Software\Microsoft\Avalon.Graphics` `DisableHWAcceleration`=1
  (software rendering). Needed for the launcher/Arena UI; the game uses D3D (not this).

## Next steps (priority order)

1. **P1 — ingame room / relay proxy under Wine.** Determine the ports the game + Arena proxy
   bind and whether loopback/relay works under winemac; test the `BFME_PROXY_*` knobs on a run
   that actually presents. This is the gate to passing.
2. **P2 — early-exit.** Find why the overlay-injected launch exits ~10s in ~40% of the time
   (direct launches are reliable). May be required for P1 to be repeatable.
3. Later (parked): winex11 + XQuartz/Xvfb for fully invisible operation (needs one sudo).

Related memory: [[bfme-macos-wine-discovery]], [[open-bfme-repos]], [[bfme-headless-options-macos]].
See also: docs/DRIVING-THE-ARENA.md

---

## ROOT CAUSE of the startup crash (2026-09-06, confirmed)

`WINEDEBUG=+seh` on a crashing run gives:
```
dispatch_exception code=c0000005 addr=7BC6123D info[0]=0 info[1]=0x5DC9
eip=7bc6123d esp=00229bb4 ... cs=0107 ds=0023 ss=0023
```
`cs=0107` is the **32-bit** code selector (cs32_sel). The faulting address is
`unix_call_32to64 + 0x29` inside Wine's WoW64 thunk (`dlls/wow64cpu/cpu.c`), whose bytes are
`8b 15 c9 5d 00 00`:

| mode | decodes as | result |
|------|-----------|--------|
| 64-bit | `mov 0x5dc9(%rip),%edx`  (loads `cs32_sel`) | correct |
| 32-bit | `mov edx,[0x00005dc9]`   (absolute) | reads 0x5dc9 → **access violation** |

`info[1]=0x5DC9` is exactly that absolute address. So the **64-bit thunk is being executed in
32-bit mode**: the far jump that 32-bit code uses to enter 64-bit mode
(`ljmp` with `cs64_sel`, built in `BTCpuGetBopCode`/`__wine_get_unix_opcode`) **intermittently
fails to switch mode under Rosetta 2**. Every syscall/unix-call from 32-bit code goes through
this thunk, so startup (thousands of transitions) hits it ~50% of the time.

Notes:
- Same signature every time: tid 36, `eip = <32-bit ntdll base> - 0x2edc3`, `info[1]=0x5dc9`.
- The game throws many *handled* c0000005s normally (its own SEH); the fatal one is this thunk fault.
- The preceding thunk bytes `4c 87 f4` (`xchgq %r14,%rsp` in 64-bit) decode in 32-bit as
  `dec %esp; xchg %esi,%esp`, so ESP/ESI are already corrupted before the fault — naive
  fault-recovery would have to invert that garbage, which is fragile.
- This is the class of problem Gcenx/winerosetta exists for ("instructions not natively
  supported" by Rosetta). Not BFME-specific; affects any 32-bit app on Wine WoW64 under Rosetta.
- **Practical stance:** not cheaply fixable from our side; treat as flaky-launch and RETRY.
  ~30-50% of launches reach the menu; once past startup the game is stable.

---

## Deep dive: how the Arena playtest actually works (2026-09-06, reverse-engineered)

Extracted `BfmeFoundationProject.BfmeClient.dll` from the Arena's .NET single-file bundle
(bundle signature + manifest parser; see docs below) and disassembled it with dnfile/dncil,
plus the injected native add-on.

**Architecture of the connection test**
1. Arena writes the add-on DLL + `arena_api_interface.conf` (a GUID) into the game install dir
   (`UpdateInterfaceConfig` -> `File.WriteAllText(GetGameInstallDirectory(), ...)`; it deletes
   the file afterwards, which is why it is normally absent on disk).
2. Arena launches `lotrbfme.exe -noshellmap`. The add-on (PE32, Detours, imports d3dx9_43 /
   ws2_32 / iphlpapi) loads into the game, hooks D3D9 Present, wraps `CLSID_NetFwMgr` so the
   in-game "Firewall Detected" dialog never appears, and writes `arenaapilog.txt`.
3. Add-on builds `\\.\pipe\bfme_api_interface_<GUID from the conf>`, calls `CreateNamedPipeA`
   then blocks in `ConnectNamedPipe`. The Arena connects; this is the "ApiInterface".
4. Arena then drives the game **by screen-scraping over that pipe**:
   `WaitForMainMenu` -> `Move(GetPosFromConfig(...))` then `ScreenReader.IsMenu1()`, where
   `IsMenu1` = `GetPixelColor(x,y)` (a pipe request the add-on answers from the D3D surface)
   and returns `Color.GetBrightness()*100 > 55`.
   Then `GoToMultiplayerMenu` -> `GoToNetworkMenu` -> `Creating ingame room...`, clicking named
   BFME UI elements (`ButtonNetwork`, `ButtonNetworkBack`).
5. Only after that does the add-on open its relay/P2P sockets ("Connecting to server",
   "P2P Ready!"). The game itself opens **no** sockets before this point.

**What we proved works under our Wine**
- Add-on injects, hooks D3D9, presents, wraps the firewall COM.
- The pipe rendezvous **succeeds**: probing the live pipe returns `ERROR_PIPE_BUSY (231)`,
  i.e. the instance exists and the Arena is connected to it.
- Cross-process/cross-bitness named pipes, `ReadProcessMemory`, `VirtualQueryEx`, and synthetic
  input (SendInput reaches the game's menus) all work.
- D3D9 backbuffer readback works in isolation (GetRenderTargetData+LockRect returns the cleared
  colour before and after a single Present).

**Wine fix applied in our tree**
- `dlls/user32/input.c`: `BlockInput()` was a stub returning FALSE. The add-on logged
  `BlockInput(TRUE) failed` as the LAST line every run. Patched to report success; the add-on
  now proceeds past it to the firewall-wrap stage. (Wine cannot really block input; reporting
  failure breaks automation tools.)

**Still failing (P1)**
The Arena connects and runs its automation, but `WaitForMainMenu` never satisfies
`IsMenu1` (pixel brightness > 55%), so it never advances to creating the ingame room and
reports "Failed to create ingame room" / "A task was canceled". Suspects, in order:
the add-on's pixel sample being taken from a surface that reads back dark under winemac,
or its own dimmed overlay covering the sampled point.

**Cross-cutting instability (now the dominant problem)**
The Rosetta WoW64 far-jump bug (see root cause above) crashes ~50% of *all* 32-bit launches —
it even crashed a 12-line standalone D3D9 test program. This corrupts test runs and may also
kill the add-on mid-handshake, so it should be treated as the top blocker before further
playtest work.

---

## 2026-09-06 06:55 — BFME1 Patch 2.22 connection test PASSES

`~/.wine-aio-custom/.../BFME Competetive Arena/Settings/arena_onlineTestCompletedForBFME1.json`
contains `true`, written 06:55:24, and the Arena advanced to the ranked "Pick a queue"
page for Patch 2.22.

### Root cause of the long-standing failure

`BfmeClient.LaunchGame` waits with `WaitWhile(<LaunchGame>b__2, 0, 0, 100)`.
`b__2` aborts after 30 s with "The game didn't start in 30 seconds" and its loop
predicate is `IsGameFocused()`. Decompiled, `IsGameFocused` requires ALL of:

1. a live process named `lotrbfme`,
2. one of its windows equals `GetForegroundWindow()`,
3. `GetWindowRect` succeeds,
4. `rect.Left <= 80 && rect.Top <= 80 && rect.Left >= 0 && rect.Top >= 0`.

On macOS both conditions failed:

* **`GetForegroundWindow()` returns NULL whenever the Wine app is not the frontmost
  macOS application.** Verified directly: with Terminal frontmost `wintool fgq` prints
  `fg=0000000000000000`; after `osascript ... set frontmost` it prints the Arena window.
* **The game's window starts at 800x600 centred in the 1280x720 virtual desktop, i.e.
  `rect = 240,33,1040,633`.** `Left = 240 > 80`, so even when focused the check failed.

So the Arena could never see the game as "focused", `LaunchGame` timed out, the Arena
aborted, `arena_api_proxy.conf` was never written and the test reported
"Failed to create ingame room" / "A task was canceled".

### The fix

Two things, both needed, applied from outside the game:

1. Make the Wine app frontmost on macOS before the test:
   `osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is <arena pid>) to true'`
2. Keep the game window at 0,0 and foreground for the whole run:
   `wintool.exe pin lotrbfme <seconds>` — every 300 ms it finds the largest visible
   window belonging to a process whose image name contains `lotrbfme`,
   `SetWindowPos(...,0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE)` if it has moved, and
   `BringWindowToTop` + `SetForegroundWindow` + `SetActiveWindow` if it is not foreground.

Observed pinned launch sequence (`tools/ranked-run3.sh`):

```
06:55:09 win rect=0,0,800,600  fg=YES  "The Battle for Middle-earth"
06:55:14 win rect=0,0,800,600  fg=YES  "Lord of the Rings The Battle for Middle-earth"
06:55:2x win rect=0,0,1280,720 fg=YES
06:55:23 Overlay: first frame presented, viewport 1280x720
06:55:24 arena_onlineTestCompletedForBFME1.json = true
```

The pin must stay up for the WHOLE test. In an earlier run the pinner was killed at
06:48:37 and the game died within 20 s with "A task was canceled".

### Launch flakiness still applies

Roughly half of all 32-bit launches die before presenting (the Rosetta WoW64 far-jump
bug documented above), so the driver retries. `tools/ranked-run3.sh` retries until
`first frame presented` appears in `arenaapilog.txt`.

### Reverse-engineered Arena API protocol (from the add-on binary)

Command vocabulary on `\\.\pipe\bfme_api_interface_<guid>`:
`updateOverlayMarkup`, `getPixelColor`, `getViewportSize`, `getNetworkStats`,
`captureGrid`, `inputClick`, `inputMove`, `inputSetLock`.
Errors: `ERR_BAD_COMMAND`, `ERR_COMMAND_UNKNOWN`.
Framing: command on line 1, one argument per following line.

`getNetworkStats` reply is a semicolon-separated key=value string beginning with
`peersKnown=` and including `selfSlot ipv6 framesDelivered framesDuplicate
endpointsLearned localPort upnp relayReady peersPunched punchPings firstP2p
firstP2p6 firstRelayTcp firstRelayUdp framesSelfEcho framesUnicast framesBroadcast
relayUdp relayFail natpmp ra raMax raN fps pump pumps eng relay`.

`arena_api_proxy.conf` is READ by the add-on (relay host/port/room/bind, one per line)
and WRITTEN by `BfmeClient.UpdateProxyConfig`, which deletes it when the first three
values are empty.

`LaunchGame`'s 13-element `requiredDlls` array is NOT a gate: `<LaunchGame>b__5`
renames every `*.dll` in the game folder that is NOT in that list to `.disabledDll`.

### Tools added this session

* `wintool fgq` — print the current `GetForegroundWindow()` with pid/rect/title.
* `wintool fgwatch <secs>` — log foreground changes from one process.
* `wintool pin <process-substr> <secs>` — hold a process's window at 0,0 and foreground.
* `wintool apisrv <pipename> <secs>` — impersonate the add-on, log Arena requests.
* `wintool apiproxy <listen> <upstream> <secs>` — logging MITM between Arena and add-on.
* `tools/ranked-run3.sh` — end-to-end driver: frontmost + pin + retry + capture.

### Proof that the pass is real (not a skipped test)

The flag is written in exactly one place: the success branch of the connection-test
async state machine (`BfmeFoundationProject_OnlineArena.dll`, MethodDef rid 5328
`MoveNext`). That branch reads:

```
CancelEverything(0,0)
Settings.Set("arena_onlineTestCompletedFor" + Game, true)
state_started.Visibility = Collapsed
state_success.Visibility = Visible
state_fail.Visibility    = Collapsed
buttonCancel/buttonRetry = Hidden
StopTimeout(); dismissInSeconds = 5
loop 5x { progress; text "arena.joiningArenaIn <i>"; await Task.Delay(1000) }
Submit("1")
```

There is no other writer, and the failure branch never sets it. After the write the
Arena auto-joins the arena, which is what we observe: the client lands on the
Patch 2.22 ranked "Pick a queue" page (1v1..FFA, army and colour pickers, chat,
SEARCH), with the live player counter populated.

### Reproduction

`tools/prove-connection-test.sh <outdir> [attempts]` reproduces it from scratch:
kills the Arena, deletes `arena_onlineTestCompletedForBFME1.json`, relaunches the
Arena, navigates Play > Ranked > BFME1 Patch 2.22 > CONTINUE, holds the Wine app
frontmost, pins the game window, and retries until the flag returns as `true`.

Verified run 2026-09-06:

```
07:07:5x  flag deleted, arena relaunched
07:08:12  CONTINUE clicked
07:08:17  game window 0,0,800,600 fg=YES
07:08:26  game window 0,0,1280,720 fg=YES
07:09:27  attempt 1 timed out -> OKAY + RETRY
07:09:39  game window 0,0,800,600 fg=YES
07:09:47  game window 0,0,1280,720 fg=YES
07:09:52  Overlay: first frame presented, viewport 1280x720
07:09:56  arena_onlineTestCompletedForBFME1.json == true   <-- PASS
```

Earlier unassisted (unpinned) runs at 06:47, 06:51 and 06:53 all reached
"first frame presented" and still failed, so the frame alone is not sufficient;
the focus/position pin is what makes the difference.

### Screen coordinate mapping (1280x720 Wine desktop)

`screencapture -l <CGWindowID>` of the Arena scaled to 950 px wide maps to
`wintool hwclick` client coordinates as:

```
client_x = image_x * 1.35158 - 5
client_y = image_y * 1.35158 - 36
```

Buttons used by the drivers: Play `45 152`, Ranked `68 187`,
BFME1 Patch 2.22 card `388 384`, CONTINUE `751 458`,
OKAY on GAME LAUNCH FAILED `645 455`, RETRY on Connection test failed `591 471`.

---

## 2026-09-06 09:00 — Launch flakiness root-caused and fixed in Wine

Baseline before this work: **2/10 launches reached a presented frame within 60 s.**

### It was never "the game is slow", it was two mode-switch bugs plus a driver assertion

The decisive clue came from the user noticing an "Exception" dialog on the desktop.
Wine's unhandled-exception dialog is modal, so a crash presented as a 100 %-CPU hang
rather than a process exit. Setting

```
HKCU\Software\Wine\WineDbg  ShowCrashDialog = 0   (REG_DWORD)
```

turns those into fast failures with a usable trace, and is worth keeping set.

#### Bug 1 — 32-to-64 transition (`ljmp *disp32`)

`dlls/wow64cpu/cpu.c` built a `struct thunk_32to64` containing `ff 2d <disp32>`, a far
indirect jump used by 32-bit code to enter the 64-bit syscall thunks. Rosetta 2
intermittently executes it as a *near* jump: it takes the offset but never loads the new
CS. The 64-bit entry point then runs in 32-bit mode, where
`mov 0x5dc9(%rip),%edx` decodes as an absolute read of `0x5dc9`. Exactly what the
Exception dialog showed:

```
EXCEPTION_ACCESS_VIOLATION, "Access address 0x00005dc9 was read from."
EIP: 0x7bc6123d   CS: 0x0107 (the 32-bit selector)
```

Fix: build the thunk as `push imm32 (cs64); push imm32 (addr); lret` instead. A far
return switches mode reliably under Rosetta and is stack-neutral, so the 32-bit
`call` return address stays exactly where `syscall_32to64` expects it.

#### Bug 2 — 64-to-32 transition (`ljmp *(%r14)`)

The return path in `syscall_32to64` and `unix_call_32to64` used the same instruction and
failed the same way, in the other direction: 32-bit code left running with `cs=0x2b`.
`WINEDEBUG=+seh` caught it directly:

```
dispatch_exception code=c0000005 rip=000000007611f681 rsp=0000000000229b30
rdx=0000000000000107        <- the 32-bit CS that was never loaded
cs=002b ss=0023             <- still in 64-bit mode
err:seh:call_seh_handlers invalid frame ... => unable to dispatch exception
```

Fix: build a full iret frame and use `iretq`, the same mechanism the neighbouring
reset-state path already used. One subtlety cost a debugging round: the old `xchgq
%r14,%rsp` also left `%r14` holding the 64-bit stack for the *next* transition, so the
replacement must do `movq %rsp,%r14` explicitly. Without it every launch died instantly.

#### Bug 3 — Apple GL driver assertion

With both switches fixed, the residual failures were all:

```
wine[...] failed assertion false at line 394 in clearFramebufferData. missing clear mask bits
```

The game issues a clear whose flags map to no GL buffer bits. A zero mask is a legal
no-op per the GL spec, but Apple's GL-on-Metal driver asserts and wedges the context:
the process stays alive at ~5 % CPU with a correctly sized window and never presents.
Fix: guard the three `p_glClear(clear_mask)` calls in `dlls/wined3d/texture_gl.c` with
`if (clear_mask)`.

Note on build targets: `make dlls/wined3d/wined3d.dll` silently builds nothing useful.
The real outputs are `dlls/wined3d/i386-windows/wined3d.dll` (the one a 32-bit game
loads) and `dlls/wined3d/x86_64-windows/wined3d.dll`. A first attempt at this fix was
measured without ever being compiled in, so check artifact timestamps after building.

### Measuring it

`tools/launch-bench.sh <outdir> <n> [label]` launches the game standalone with the
add-on injected and records time-to-first-frame, with a 60 s deadline. On failure it
captures the add-on log, CPU, the Wine window list, a `sample` of the process and the
game log. Note the hard-cleanup step: a wedged instance ignores SIGTERM and blocks every
later launch, which produced a run of bogus consecutive failures before it was fixed.

### Results

Measured with `tools/launch-bench3.sh`, which distinguishes three stages, because the
BFME splash screen is a static bright image that passes a naive brightness test and
would otherwise be mistaken for a loaded game:

| Stage | Signature (32px grayscale) |
|---|---|
| black / nothing | `frac` 0.000 |
| splash screen | `diff` 0.0 from `tools/splash-ref.png` |
| interactive main menu | `diff` ~63, `frac` ~0.16 |

| Configuration | Result |
|---|---|
| Baseline | **2/10** reached a first frame within 60 s |
| + both WoW64 mode-switch fixes | **19/20** first frame; the one failure was the Metal assertion |
| + the `glClear` guard (actually compiled) | **20/20** to splash, 17-24 s |
| Same build, bar raised to the interactive main menu | **20/20**, 17-25 s |

Timings are tight: first frame at 15-17 s, splash at 17-22 s, main menu at 23-25 s.

Two measurement traps worth remembering, both of which produced a wrong answer first:

* "First frame presented" is not "the game is up". The harness killed the game at frame
  one, so every launch looked like a black flash on screen even when healthy.
* Brightness alone is not "the menu is up". The splash screen scores *higher* than the
  menu (mean 83 vs 25). Two different launches returning byte-identical stats is what
  gave it away; always compare against a splash reference.

### Regression check

With all three fixes in, the BFME1 Patch 2.22 connection test still passes from a clean
state (flag deleted, Arena relaunched, UI navigated from Home):
`tools/prove-connection-test.sh` reported PASS at 09:59:02 on 2026-09-06 and
`arena_onlineTestCompletedForBFME1.json` was rewritten to `true`.

### Still open

* `run-custom-wine.sh` still pins `WINE_CPU_TOPOLOGY=1:0`. That was added as a
  workaround before the mode-switch bugs were understood and has not been re-tested
  since; dropping it is the most promising remaining lever for the slow skirmish map
  load (~470 s) and the 20 fps in-game frame rate. `tools/bench-matrix.sh` is set up
  for that A/B, but note `run-custom-wine.sh` uses `${WINE_CPU_TOPOLOGY:-1:0}`, so an
  empty value still selects the default; the script needs `${WINE_CPU_TOPOLOGY-1:0}`
  to allow an explicit override to nothing.
* The wined3d `csmt=0` prefix setting is similarly untested since the fixes.

---

## 2026-09-06 10:40 — CORRECTION: the real cause was the game's resolution

**The 06:55 section above is wrong and is kept only as a record of a mistaken diagnosis.**
Pinning the game window to 0,0 and holding it foreground did NOT fix the connection
test. `IsGameFocused` is a real gate and its conditions are as described, but they were
already being satisfied without any pinning: a passive `wintool winwatch` log through a
failing run shows the game window at `pos_ok=YES fg=YES` for its entire lifetime while
the test still failed. What actually made the earlier runs "pass" was the retry loop
hitting an intermittent success, which I wrongly attributed to the pin.

### The actual cause

The Arena drives BFME1 by screen-scraping and clicking through the pipe, using button
positions that are **compile-time constants with no runtime scaling**. From the BFME1
client constructor:

```
ButtonMultiplayer        700 1357     ButtonJoinGame           1280  443
ButtonNetwork           1070 1357     ButtonPopupDismiss       1280  860
ButtonNetworkBack       2415 1357     PopupVisibleIfDarkPixel   860  860
ButtonCreateGame        1070 1357     GameChatBox              1255 1170
ButtonStartGame         1070 1357     ButtonLeaveGame          1495 1357
```

Those coordinates describe a **2560x1440** game: 1280 is exactly half of 2560, and
1357/1440 = 0.942 lands on the menu button row. `GetPosFromConfig` adds only an optional
offset, and `Move`, `Click` and `GetPixel` pass the Point straight to `InputMove`,
`InputClick` and `GetPixelColor`, so nothing rescales it. The MITM log confirms the raw
values go over the pipe: `REQ getPixelColor|2415 1357`.

The game was running at 1280x720, so every click was ~1.9x off. The intermittency has a
tidy explanation too: y=1357 clamps to the bottom edge of a 720-tall backbuffer, which is
exactly where the button row is, so clicks landed on a plausible-but-wrong button and the
sequence occasionally worked out by luck.

### The fix

Run BFME1 at 2560x1440:

* `Options.ini` -> `Resolution = 2560 1440`
* `HKCU\Software\Wine\Explorer\Desktops` -> `Default = 2560x1440`

Result, via `tools/verify-connection-test.sh` (no pinning, no retries):
**5/5 connection tests passed, 42 s each.** Previously it was roughly a coin flip.

Side effect: the Arena's own window scales with the virtual desktop (now 1500x1000
client), so UI click coordinates must be recalibrated. For a 950px-wide screenshot of
that window: `client_x = image_x * 1500/950`, `client_y = (image_y - 22) * 1000/613`.
Useful buttons: BACK `317 42`, Play `69 218`, RESUME on the 2.22 card `1329 228`.

Re-triggering the test requires leaving the arena first (BACK), because the test only
runs on join. Setting the flag to false while already inside the arena does nothing.

### Launch reliability re-measured at the shipping resolution

The 20/20 figure above was measured at 1280x720, which is not the resolution the Arena
needs. Re-run at 2560x1440 with `tools/launch-bench3.sh`:

**10/10 reached the interactive main menu, 19-20 s each** (first frame at 17-18 s).
Slightly faster to menu than at 1280x720, where it was 23-25 s.

Two harness bugs produced a spurious 0/10 first, both worth remembering because each
looked exactly like a product failure:

* `gamerect.sh` had a Python syntax error (a backslash inside an f-string), so it printed
  nothing and the benchmark never captured a frame.
* `imgstat.py` used `sips -Z`, which preserves aspect ratio. Comparing captures of
  different shapes gave different-length vectors and returned `diff=-1`, so the menu test
  could never pass. It now forces an exact 32x18 grid via `--resampleHeightWidth`.

Calibration after the fix, confirming the check works at both resolutions:

| Capture | frac | diff vs splash-ref |
|---|---|---|
| Main menu @ 2560x1440 | 0.168 | 63.5 |
| Main menu @ 1280x720 | 0.158 | 62.6 |
| Splash reference | 0.806 | 0 |

### Known cosmetic issue at 2560x1440

The Mac's display is 3456x2234 physical / ~1832x1184 logical, so a 2560x1440 Wine
desktop is larger than the screen and the game window is clipped: only the top-left
portion is visible and the menu button row sits off-screen. This does not affect the
Arena, which scrapes the D3D backbuffer through the add-on rather than the screen (hence
5/5 connection test passes), but it does mean the window looks wrong to a human.

---

## 2026-09-06 13:30 — Why BFME is slow: Rosetta's x87 emulation

Symptoms: a 2-player skirmish map takes ~470 s to load and runs at ~20 fps, on an M2 Max.

### It is not what the profile appears to say

`sample` during a load shows nearly all time in `__wine_syscall_dispatcher` and
`__wine_unix_call_dispatcher`. That is an artefact: `sample` cannot unwind
Rosetta-translated code, so it attributes everything to the last frame it recognises.
A direct microbenchmark shows WoW64 transitions are cheap:

| | per syscall |
|---|---|
| x86-64 (no mode switch) | 1.01 us |
| x86-32 (crosses the WoW64 boundary) | 1.12 us |

About 110 ns of overhead. At that rate 470 s would need ~400 million syscalls, which is
not plausible for a map load. Transitions are not the problem, and neither are cores or
CSMT (see the table below).

### The actual cause

Identical compute loop, 300M iterations (`tools/wintool/cpubench.c`, `intbench.c`):

| Workload | native arm64 | x86-64 (Rosetta) | x86-32 (WoW64) |
|---|---|---|---|
| integer | - | 650.8 Miter/s | **650.8 Miter/s** |
| float via SSE2 | 221.7 Miter/s | 217.4 Miter/s | **217.9 Miter/s** |
| float via x87 | - | - | **6.2 Miter/s** |

**Rosetta translates x87 floating point about 35x slower than integer or SSE2 code.**
32-bit itself costs nothing; Rosetta's 64-bit translation is essentially native speed.
BFME is a 2004 MSVC build, so all of its floating point — physics, pathfinding,
transforms and the asset processing during a map load — is x87. That single factor
accounts for both the ~30x load time and the frame rate.

x87 precision control is not a lever (`tools/wintool/x87prec.c`):
24-bit 8.4, 53-bit 8.2, 64-bit 8.2 Miter/s. No fast path for reduced precision.

This is in Apple's translation layer, on a binary we cannot recompile. Nothing in Wine
or the prefix addresses it.

### What did help

| Config | load | in-game fps | launches |
|---|---|---|---|
| 1 core, csmt=0 (old workarounds) | 470 s | 20 | - |
| all 12 cores, csmt=1 | 482 s / 464 s | 24.2 | 10/10 in 19-20 s |

CSMT is worth keeping (+20% fps). Extra cores do nothing for load time, which makes
sense: the loader is single-threaded and x87-bound. Both settings were crash workarounds
for the wow64cpu mode-switch bugs; with those fixed, all cores are reliable, so
`run-custom-wine.sh` no longer pins `WINE_CPU_TOPOLOGY` and `csmt` is left at 1.

Load time is the same on a second load of the same map (464 s vs 470 s), so it is not
cache warming — it is paid every time.

Still untested: `StaticGameLOD` is `UltraHigh`; lowering it reduces per-frame FP work and
is the one remaining lever on frame rate.

---

## 2026-09-07 — Skirmish load time: 470s -> 48s

All figures below were measured with `tools/skirmish-timer4.sh`, which captures the game
window by CGWindowID, waits for wined3d to actually present frames, verifies the
skirmish-setup screen before clicking START GAME, and requires the frame counter to
advance across the load. Earlier numbers in this document from `skirmish-timer*.sh`
versions 1-3 were produced by drivers that could mistake the desktop, a stale window or
the splash screen for gameplay, and should not be trusted.

### What worked

| Change | Load |
|---|---|
| baseline (UltraHigh, 1 core, csmt=0) | ~470 s |
| all cores + csmt=1 | no change to load; fps 20 -> 24 |
| `StaticGameLOD = VeryLow` | 385 -> **75 s** |
| + `TextureReductionFactor = 4` (was 2) | **48 s** |

Final: **47 s load, 38.5 fps**, verified against a screenshot of real gameplay.

(The 48 s figure came from a timer that polled every 5 s and so rounded up. Re-measured
at 1 s resolution it is 47 s, twice. Render resolution makes no difference at all:
1280x720 also measures 47 s, which confirms the load is not rendering-bound.)

### What did not work

| Change | Result |
|---|---|
| `TextureReductionFactor = 5` | 48 s — texture reduction has saturated |
| object counts (`MaxTankTrackEdges=0`, particles 100) | game never renders — do not set these |
| wined3d Vulkan renderer (MoltenVK) | 64 s and 30 fps, worse than GL |
| AI army `Random` -> same faction | 48 s, no change |
| `-noaudio` | 98 s vs 75 s, worse |
| `-nozerofillmemory` | 192 vs 197 s, no real change |
| all 12 cores | no change to load (the loader is not core-bound) |

### The LOD trap

`Low` is **not a valid LOD value**. The engine's levels are `VeryLow, Medium, High,
VeryHigh, UltraHigh` (plus `Custom`). Setting `Low` makes the engine fall back to running
its CPU benchmark on every launch — `GameLODPresets.ini` holds the reference
`BenchProfile` scores it compares against — and that benchmark is x87, so Rosetta turns
it into an ~85 s startup penalty (103 s to first frame vs 18 s on a valid preset).

### Where the remaining 48 s goes

Asset-volume reductions produced 8x and then stopped dead. Nothing else moves the number.
That points at fixed per-map engine computation — terrain meshing, pathfinding grids,
object instantiation — which no setting exposes and which is float-heavy, i.e. exactly
the work Rosetta runs ~35x slower than integer/SSE2 (see the x87 section above).

Native loads this map in roughly 5 s, so 48 s is about 10x native. Reaching the 10 s that
was asked for would need ~2x native, which requires that remaining work to run on
Rosetta's fast paths. It does not. **10 s is not reachable by configuration.**

### Applying it

`play-bfme.sh` now sets the three LOD keys to `VeryLow`, installs
`config/gamelod-fastload.ini` as `data/ini/gamelod.ini`, and passes `-preferLocalFiles`
so the loose override wins over the packed archive.

### Final characterisation (2026-09-07)

Load time is **map-independent**: Amon Sul 47 s, Andrast 47 s. It is also independent of
render resolution (1600x900 and 1280x720 both 47 s) and of faction selection. Combined
with texture reduction saturating at factor 4, this places the floor at 47 s and
identifies the residue as fixed per-map engine computation with no exposed control.

`-preferLocalFiles` is required, not optional: without it the loose `gamelod.ini`
override is ignored and the load returns to 68 s.

Neither the 45 s nor the 10 s target is reachable by configuration. Delivered:
**470 s -> 47 s load, 20 -> 38.5 fps.**

---

## 2026-09-07 — x87sidecar: 470s -> 9.6s

**The earlier conclusion that this was unfixable was wrong.** It rested on "Rosetta's x87
is slow and we cannot change Rosetta", which is true but not the end of the story:
someone has already written the fix.

[athei/x87sidecar](https://github.com/athei/x87sidecar) hooks Rosetta and replaces its
x87 handlers with an AArch64 JIT running in a separate native process. It descends from
[Lifeisawful/rosettax87](https://github.com/Lifeisawful/rosettax87) and is actively
maintained (v1.6.0, 2026-09-03).

### Measured on this machine

| Workload | stock Rosetta | with sidecar | gain |
|---|---|---|---|
| native x86-64 x87 loop | 5.2 Miter/s | **226 Miter/s** | 43x |
| 32-bit PE x87 loop under Wine | 6.2 Miter/s | **55.4 Miter/s** | 8.9x |

226 Miter/s is native-ARM64 speed (222 Miter/s on the same loop), and results are
bit-identical, so this is not trading correctness for speed.

### Skirmish load, by detail preset

| preset | before sidecar | with sidecar |
|---|---|---|
| VeryLow + `TextureReductionFactor=4` | 47 s | **9.6 s** |
| VeryLow, stock textures | 75 s | **12.0 s** |
| Medium | — | **22.1 s** |
| UltraHigh (full detail) | 385 s | **22.6 s** |

Frame rate is ~38 fps in every case. Note the sidecar helps *more* at high detail (17x at
UltraHigh vs 4.9x at VeryLow), so the visual downgrade is no longer forced: full detail
now loads in 22.6 s, where it used to take 385 s.

### Getting it working (the tool alone does nothing)

Dropping the binary in and setting `ROSETTA_X87_PATH` produced **0 requests handled**.
Two separate problems, both needing Wine patches:

1. **Attach mode.** The default `task_for_pid` + `ptrace` attach could not write
   `g_disable_aot` after wine's `execv` (`Failed to read memory at 0x20000d8b4`), so
   Rosetta kept serving cached AOT translations and the hooked `translate_insn` was never
   called. The fix is *cooperative* mode, where the target hands over its own task port —
   which requires wine to perform a handshake.
2. **Wine execs itself.** Porting the handshake alone still gave 0 requests: it ran in a
   process that then `execv`'d, taking the hook with it. The missing half is re-execing
   *through* the sidecar in `preloader_exec`, so the sidecar attaches to the final process.

Both are ported from athei's `cx-26-patched` branch to our Wine 11.17 and saved as
`config/wine-x87sidecar-handshake.patch` + `config/coop_proto.h`. **Re-apply them after
any clean wine rebuild** — without them the sidecar attaches and silently does nothing.

### Using it

`run-custom-wine.sh` sets `ROSETTA_X87_PATH` automatically when
`tools/x87sidecar/x87sidecar` is present (`BFME_NO_X87=1` disables it).
`play-bfme.sh [fast|normal|quality] [WxH]` picks the detail preset.
`x87sidecar --probe` validates against the installed Rosetta; it prints `supported` here.

### Sidecar tuning at full detail (all rejected)

Baseline UltraHigh with the sidecar: **22.6 s** (confirmed twice: 22.59, 22.62).

| knob | load | verdict |
|---|---|---|
| `X87_FAST_ROUND=2` | 31.5 s | **worse**, and risks mis-rounding (RC is persistent thread state) |
| `X87_ENABLE_FMA_CONTRACT=1` | 22.0 s | +0.6 s, within noise; changes float rounding, so a desync risk in an RTS. Not worth it |

During a full-detail load the sidecar translates **13,673 x87 blocks**, peaking at
1468 req/s, so it is genuinely working — the remaining 22.6 s is asset loading at full
quality, not translation overhead. Translation tuning is exhausted.

### Attribution: translation vs settings

Holding detail constant, the sidecar alone gives:

| detail | before | after | factor |
|---|---|---|---|
| UltraHigh | 385 s | 22.6 s | **17x** |
| VeryLow + `TextureReductionFactor=4` | 47 s | 9.6 s | **4.9x** |

Going from 22.6 s to 9.6 s is settings, not translation, and it costs real image quality
(1/16-resolution textures). `play-bfme.sh` therefore defaults to **quality**: full
UltraHigh detail at 22.6 s. Use `./play-bfme.sh fast` only when load time matters more
than how the game looks.

---

## 2026-09-07 — Which wine patches are actually needed (ablation)

Each patch reverted individually and re-measured on the same build.

| patch | with | without | verdict |
|---|---|---|---|
| `wow64cpu` far jump -> `lret`/`iretq` | **10/10** launches | **4/10** | **REQUIRED** |
| `ntdll` x87sidecar handshake + re-exec | 9.6 s loads | sidecar handles 0 requests | **REQUIRED** for the sidecar |
| `wined3d` zero-mask `glClear` guard | 10/10 | 10/10, zero assertions | **unproven** — does not reproduce at current settings |
| `user32` `BlockInput` returns TRUE | 8/8 connection tests | **5/6** | **REDUNDANT — removed** |

The `BlockInput` change was a misdiagnosis: the add-on does log `BlockInput(TRUE) failed`,
but the actual blocker was always the game's resolution not matching the Arena's
hardcoded 2560x1440 coordinates. Reverted to stock.

The `glClear` guard fired ~2 times in 15 runs when the game ran at 1600x900 with the
*unpatched* wow64cpu; it has not reproduced since. Kept (harmless, and a zero mask is a
legal no-op that Apple's driver should not assert on) but it is not evidence-backed.

### Upstream assessment

* **`wow64cpu` mode switch — strong candidate.** Not BFME-specific: it affects every
  32-bit Windows application under Wine on Apple Silicon, and ~60% of launches die
  without it. Mechanism is precise (Rosetta executes `ljmp *m16:32` as a near jump,
  taking the offset without loading CS), the fix is small, and the neighbouring
  reset-state path in the same file already uses `iretq`.
* **`glClear` guard — defensible but unproven.** Correct per the GL spec; no current repro.
* **x87sidecar handshake — not ours to upstream.** It is athei's patch, already carried on
  their `cx-*-patched` branches, and marked `CW HACK`.
