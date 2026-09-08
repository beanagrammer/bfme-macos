# Wine patches

Three patches against **Wine 11.17** (`36b6a2cf67`, tag `wine-11.17`). Apply from
the root of a Wine checkout:

```sh
cd wine
git checkout wine-11.17
for p in ../patches/*.patch; do git apply "$p"; done
```

All three are needed for BFME under Rosetta on Apple Silicon. Nothing here is
BFME-specific in its implementation — each fixes a general problem that BFME
happens to hit hard.

---

## 0001 — wow64cpu: Rosetta mis-executes the 32→64 bit mode switch

**Problem.** Wine's new WoW64 runs 32-bit PE code inside a single 64-bit process
and switches CPU mode with a far indirect jump (`ljmp *(%r14)`). Rosetta 2 takes
the offset from that instruction but does not load the new code segment, so
execution continues in the wrong mode and the process dies in whatever it hits
next. It is intermittent because it depends on what the stale mode reaches.

**Fix.** Replace both mode-switch paths with sequences Rosetta emulates
correctly: a far return (`push cs; push addr; lret`) in the 32→64 thunk, and an
iret frame plus `iretq` in the `syscall_32to64` / `unix_call_32to64` fast paths.
The `iretq` version must also do `movq %rsp,%r14` first, because the old
`xchgq %r14,%rsp` left `r14` holding the 64-bit stack for the next transition.

**Measured.** Stock Wine: 4 of 10 BFME launches reach the main menu. Patched:
10 of 10. This was A/B'd twice, once accidentally when the patch was reverted.

**Upstream status.** Not submitted. This is the one most worth sending: it is a
correctness fix for any WoW64 program under Rosetta, not a BFME workaround.
Wine may prefer a Rosetta-detection guard rather than changing the sequence for
every x86-64 host, so expect that discussion.

---

## 0002 — ntdll: hand the process to x87sidecar

**Problem.** Rosetta 2 emulates x87 floating point in software, roughly 35x
slower than its integer and SSE2 paths. BFME is a 2004 game built around x87, so
this dominates everything: a skirmish took about eight minutes to load.

**Fix.** Wire up [x87sidecar](https://github.com/Sonic-The-Hedgehog-LNK1123/rosetta-x87)
(ported from athei/wine's `cx-26-patched`): re-exec through the sidecar in
`preloader_exec()`, and perform the Mach port cooperative handshake at the top of
`__wine_main()`. Both halves are required — the handshake alone handles zero
requests.

**Measured.** Skirmish load 470s → 19s. In-game 20fps → 38fps (the engine's cap).

**Upstream status.** Not submittable as-is: it depends on an external binary. It
is here so the build is reproducible, and it is the same approach CrossOver
ships.

---

## 0003 — winemac.drv: let a virtual desktop fill the screen

**Problem.** Three separate things, all of which break an application that drives
itself with absolute screen coordinates:

1. `macdrv_GetDeviceCaps` doubles `HORZRES`/`VERTRES` whenever Retina mode is on.
   With a virtual desktop the generic driver already reports the desktop size in
   Win32 pixels, so the doubling double-counts and `HORZRES` ends up at twice
   `SM_CXSCREEN` (observed: 5120 vs 2560).
2. Retina mode is hardcoded to exactly two Win32 pixels per Cocoa point, so a
   fixed-resolution virtual desktop can only be shown at half size — a 2560x1440
   desktop becomes a 1280x720 window in the corner of a 1728x1117 screen.
3. Cocoa refuses to leave a window under the menu bar unless it covers a whole
   screen, silently shifting the Win32 origin down by the menu bar height. Every
   absolute coordinate the application uses is then wrong by that amount.

**Fix.** Two new registry values under `HKCU\Software\Wine\Mac Driver`:

| Value | Type | Meaning |
|---|---|---|
| `RetinaScale` | `REG_SZ` | Win32 pixels per Cocoa point while Retina mode is on. Default `2`, accepted range 1–8. |
| `ConstrainWindows` | `REG_SZ` | `N` disables Cocoa's frame constraint so windows land exactly where Win32 puts them. Default on. |

`HORZRES`/`VERTRES` now follow `SM_CXSCREEN`/`SM_CYSCREEN` instead of being
blindly doubled, and a window that spans a screen's width and reaches its top
edge is treated as fullscreen for window-level purposes when `ConstrainWindows`
is off — otherwise the menu bar is drawn over its top rows.

**Measured.** With `RetinaScale=1.481481` (2560/1728) and `ConstrainWindows=N`,
a 2560x1440 virtual desktop is displayed at 1728x972 points at the top-left of a
1728x1117 screen: full width, nothing clipped, macOS display mode untouched. The
Arena connection test goes from 0/7 to 7/7.

**Upstream status.** Not submitted. The `HORZRES` double-count is a plain bug and
should go upstream on its own. `RetinaScale` and `ConstrainWindows` are new
options and would need a discussion about naming and defaults.
