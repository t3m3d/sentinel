# Sentinel POC — findings (2026-11-19)

What the Linux GUI proof of concept (`src/sentinel.k`) established, and
what it exposed. Verified on an x86_64 Lima VM (`krypton`, Ubuntu 25.10,
kernel 6.17, weston 14 headless) building against the krypton checkout's
Linux ELF backend (`bootstrap/kcc_driver_linux_x86_64`).

## Proven

- **The KryptOS Linux GUI path works end to end.** `k:choc_linux`
  (Wayland wire protocol spoken directly from pure-Krypton code, rendering
  into an in-arena `SmackSurface`, blitting via `wl_shm`) opens a window,
  draws, presents frames, and pumps keyboard events. No GTK, no FFI, no
  libc — the same static-syscall ELF pipeline as the rest of KryptOS.
- **Live /proc collectors work from Krypton**: `readProc()` handles the
  virtual files fine. CPU % (250 ms double-sample), memory via
  `MemAvailable`, load average, uptime, kernel release, CPU model,
  thread count. CPU % moved from 0 to ~15% under `yes` load.
- **Pixel-level verification is possible headlessly**: `--verify` samples
  the SmackSurface backing buffer (sidebar, accent bar, selected row,
  card border/fill) and passes 6/6 under headless weston.
- **Single static ELF**: ~94 KB binary, no runtime dependencies.

## Found / fixed

1. **Native `linecount()` segfaults on the Linux ELF backend** (SIGSEGV /
   SIGTRAP, isolated with minimal repros). kryofetch already avoids it
   with its own reimplementation; Sentinel carries a local `lineCount()`.
   Any other code using native `linecount()` on Linux will crash the same
   way — this should be fixed in the backend or the builtin documented.
2. **`KCC_FAST=1` produces a spurious failure** (`elf: wrote …` followed
   by `kcc: native codegen failed`) on this toolchain; the default driver
   invocation is clean. `build_linux.sh` does not set it.
3. **Lima share serves stale file contents.** After editing files on the
   macOS host, the guest kept serving the previous version of an exact
   path (host 13202 B vs guest 12825 B, hours apart), producing
   impossible "same source, different result" crashes. Build from a fresh
   copy or a guest-native sync (`tar | limactl shell … tar -x`), not from
   the shared path. Newly created files were never affected.
4. `--watch` redraws only when an input event arrives (see gaps); under
   headless weston it sat in the event pump until killed — no crash,
   clean frame presents.

## Not available yet (needed before Phase 1 features)

- **No process enumeration**: no `getdents64`/readdir builtin exists in
  the Linux backend and `shellRun()` returns only an exit code. Listing
  `/proc` requires either a `getdents64` host builtin or a sanctioned
  helper. Without one there is no process list — the core of Sentinel.
- **No timers / frame callbacks in `k:wayland`**: the event loop blocks
  in `sockRecv` (`recvfrom`, flags=0). A 1 Hz refresh needs either
  compositor frame callbacks, `wl_surface.frame`, or a poll-with-timeout
  path in the backend (e.g. `poll()`/`ppoll` builtin) plus scheduler.
- **`xdg_toplevel.close` is not handled** by `k:choc_linux` — closing the
  window from the compositor is ignored; only `q`/Esc quits (POC).
- **No controls**: `choc_linux` ships `chocFillRect`/`chocDrawText` and
  raw key/pointer callbacks only — no buttons, tables, scrollbars,
  focus, or text input. Everything interactive must be built from hit
  testing on the framebuffer (acceptable for a sidebar POC, not for
  process tables).
- **Text**: single 8×16 bitmap font (`fbDrawText`); `fbTextWidth` is
  `len*8`. No font sizing, no bold, no proportional metrics.
- **Window sizing**: fixed 960×600 POC layout; `xdg_configure` resizes
  would need relayout logic.
- **Key input**: `--watch` key handling (q/Esc) compiled but not
  interactively tested — headless weston has no keyboard. Pointer/key
  paths are untested with a real seat.
- **Colors are packed `"r,g,b,a"` strings** (`k:smack/geometry`), not
  ints; `split()` is broken natively on Linux — compare packed strings
  instead.
- **Process pressure**: PSI (`/proc/pressure/`) not read yet; trivial
  addition via `readProc` once defined.

## Suggested order for Phase 1 proper

1. Land a `getdents64`-based directory builtin (or `readDirProc`) in the
   Linux backend + expose it to Krypton.
2. Add poll/timeout socket reads + a compositor frame callback so the UI
   can refresh at 1 Hz.
3. Handle `xdg_toplevel.close` (and `ping`) in `k:choc_linux`.
4. Minimal table/scroll/text-input widgets on the framebuffer, or a
   decision on the GTK4 bridge (blueprint §3) before building the
   process list UI.
5. Real process view: `/proc/[pid]/{stat,status,cmdline,io}` parsing,
   CPU/mem per process, sorting, filter, SIGTERM with PID-reuse check
   (`pidfd_open`).
