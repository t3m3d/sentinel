# Sentinel — KryptOS System Monitor

Sentinel is the planned native task manager and system monitor for **KryptOS**:
live process management, performance analytics, SysVinit service control,
security visibility and diagnostics — written predominantly in **Krypton**
with an Objective-K / Choc GUI architecture, dark purple/green visual
identity.

> **Status: 0.0.1 proof of concept.** This repo currently contains the
> Linux-first GUI proof of concept for KryptOS, not the full 12-section
> roadmap from `docs/blueprint.md`. See `docs/poc-findings.md` for what is
> proven, what is not, and what KryptOS still needs to provide.

## What works today (verified on x86_64 Linux, weston 14 headless)

- `src/sentinel.k` opens a **960×600 Wayland window** titled "KryptOS
  Sentinel" and renders a KryptOS-styled dashboard frame: sidebar with the
  full planned navigation (Dashboard selected), CPU / Memory / Load / Uptime
  cards, resource-pressure bars and a system panel.
- **Live /proc collectors**: CPU utilization (two samples 250 ms apart),
  memory (total/available from `MemAvailable`), load average, uptime, kernel,
  hostname, user, CPU model and thread count.
- **Pixel-level render verification** (`--verify`) against the in-memory
  SmackSurface — sidebar, background, selected nav accent, card border and
  card fill.
- Builds to a single **static, syscall-only ELF** (no libc, no gcc, no GTK).

## Build & run (inside KryptOS / x86_64 Linux)

```sh
# needs a krypton checkout (KRYPTON_ROOT) with the Linux ELF backend
./build_linux.sh            # build ./sentinel
./build_linux.sh --smoke    # build, print collected stats, no window
./build_linux.sh --run      # build, draw one frame, present, exit
./sentinel --verify         # draw frame, self-check pixels, exit 0/1
./sentinel --watch          # interactive: redraw on events, q/Esc quits
```

`--smoke`, `--verify` and `--watch` are proof-of-concept flags, not the
final CLI surface.

## Layout

```
src/sentinel.k     the whole POC (collectors + frame + entry point)
build_linux.sh     static ELF build wrapper
docs/blueprint.md  product blueprint (the 12 sections)
docs/poc-findings.md  what the POC proved/found, and what is missing
```

## License

GPL-3.0 (see LICENSE).
