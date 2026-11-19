# KryptOS Sentinel — Development Blueprint

Native System Monitor • Task Manager • Process Controller
Krypton + Objective-K. (Source: product blueprint, Nov 2026 — preserved
verbatim apart from cleanup of reference-link artifacts.)

## Primary development goals

- Written predominantly in Krypton, using Objective-K for the
  object-oriented GUI architecture.
- Native Linux application, not a browser-based task manager.
- Lightweight enough to run continuously without consuming excessive
  system resources.
- Integrate directly with the Linux kernel and KryptOS SysVinit
  infrastructure.
- Basic controls for everyday users, advanced capabilities for developers
  and administrators.
- KryptOS purple, green and dark visual identity.
- Ship as a standard component of the KryptOS desktop environment.

## 1. Sidebar navigation (12 sections — long-term roadmap)

Dashboard · Processes · Performance · Memory · Storage · Network ·
Hardware · Services · Startup · Security · System Logs · Diagnostics

## 2. Feature requirements (summary)

### Dashboard — System overview
Live CPU/RAM/GPU/disk/network usage; uptime and session; process/thread
counts; load averages; highest-consumption apps; disk space; temperature
and fan readings when available; recently started/stopped processes;
resource-exhaustion warnings; quick actions. Lightweight graphs,
configurable widgets.

### Processes — Task management (most important section)
Name/icon, PID, PPID, owner, CPU/CPU-time, resident/virtual memory,
disk I/O, threads, executable path, command line, start time, state,
priority, affinity, process tree, open files/FDs/sockets, per-process I/O.
Controls: SIGTERM, SIGKILL, SIGSTOP/SIGCONT, priority change, affinity,
launch, restart-where-safe, show location, copy PID/path/cmdline, filter
by name/PID/owner/state/consumption, highlight unresponsive/heavy
processes. **Termination must verify the intended process still exists —
PID file descriptors can protect against PID-reuse errors.**

### Performance — Real-time analytics
Overall and per-core CPU graphs; frequency/topology; user/system/idle/
iowait; load averages; context switches/interrupts; history graphs.
Memory: physical RAM, available/cached/buffered/reclaimable, swap usage and
activity, per-app usage, pressure/trends, OOM-event indicators. GPU: name/
driver/utilization/VRAM/temperature/power/clocks where supported;
per-process GPU stats where the driver exposes them.

### Memory — Advanced analysis
Sort by resident/proportional memory; growth detection; consumption graph;
memory mappings; anon/shared/file-backed breakdown; per-process swap where
supported; OOM adjustment values; probable-leak highlighting (suspected,
not confirmed); export.

### Storage — Disk and filesystem
Mounts/partitions; capacity/usage; throughput/IOPS; per-device latency/
utilization when measurable; NVMe/SATA details; SSD health/temperature via
optional SMART helper; filesystem types; disk-space alerts; per-process I/O;
safe navigation to disk-management tools. **No destructive partitioning or
formatting inside Sentinel.**

### Network — Connections and bandwidth
Per-interface up/down speeds; totals; Ethernet/Wi-Fi/virtual/loopback;
IPv4/IPv6; status; TCP/UDP sockets; listening ports; PID/app association
when accessible; remote endpoints; states; graphs; filters; alerts on
unexpected listeners. Advanced: per-process bandwidth accounting with an
optional kernel-supported backend.

### Hardware — Detailed monitoring
CPU model/cores/cache; temperature/clocks; motherboard/chipset; GPU; RAM
modules where discoverable; fans/thermals; battery/power for laptops;
storage identification; USB/PCI devices; kernel drivers; thermal warnings.
Hardware monitoring stays **read-only** initially. `/sys/class/hwmon` is
the standard sensor interface.

### Services — SysVinit service manager (KryptOS differentiator)
Works directly with `/etc/rc.d/init.d` scripts and `/etc/rc.d/rc?.d`
runlevel symlinks — **no mandatory systemd dependency**. List services with
active/stopped/unknown state; start/stop/restart/reload when supported;
show PIDs, configured runlevels, enable/disable autostart; inspect the
script; boot order/dependencies where documented; detect failed starts;
warn before touching essential services; request elevated authorization
for protected operations.

### Startup — Application and boot management
User-session autostart entries (enable/disable/add/remove), missing-
executable detection, boot-time services, recorded boot duration, init-
sequence visualization, slow-starter highlighting, safe startup-speed
recommendations. Later: Boot Analyzer for the SysVinit boot path.

### Security — Sentinel Security Monitor
Privileged/root processes; unexpected privileged processes; unfamiliar
listeners; deleted-binary executables; unusual resource behavior;
executable paths and optional hashes; capabilities/security context;
parentage/exec history while Sentinel runs; optional executable/package
verification; configurable alerts. Actions: investigate, inspect
executable, inspect connections, stop with authorization, export report,
mark trusted. **Alerts must explain their evidence; a single signal
(root, high CPU, unfamiliar name) must never label a process malicious.**

### System Logs — Event and error viewer
SysVinit boot logs; kernel messages; auth/system logs where configured;
service start/stop failures; Sentinel-observable crashes/terminations;
device warnings; filter by date/severity/component; search; export;
follow/live; optional process↔log correlation. **Do not assume journald.**

### Diagnostics — Troubleshooting and recovery
Health summary; high-CPU/memory investigations; zombie detection; D-state
processes; growing-FD detection; disk/memory pressure warnings; abnormal
restarts; crash info; snapshot comparisons; exportable diagnostic reports;
privacy-aware support bundles. **PSI (`/proc/pressure/`) is the key
signal** for distinguishing busy from stalled.

## 3. Architecture

```
Sentinel GUI     Objective-K components + KryptOS Linux graphics backend
Sentinel Core    Krypton: sampling, process models, calculations, alerts, config
Linux Collector  /proc, /sys, kernel interfaces
Privileged Helper  authorized service/process actions (narrowly scoped, separate)
```

| Component | Implementation |
| --- | --- |
| System info collection | Krypton |
| Process enumeration and controls | Krypton |
| CPU/memory/I/O calculations | Krypton |
| Historical metric storage | Krypton |
| Service management | Krypton |
| Security checks and diagnostics | Krypton |
| GUI windows and controllers | Objective-K |
| Data tables and navigation | Objective-K |
| Performance graph components | Objective-K plus graphics backend |
| Linux GUI toolkit integration | Krypton/Objective-K bindings and ABI bridge |
| Elevated operations | Separate narrowly privileged Krypton helper |

Linux GUI: evaluate a native toolkit bridge (GTK4) or a KryptOS-specific
graphics backend (Objective-K/Choc design). The first prototype must prove
window creation, widgets, events, timers, rendering and text accessibility
on Linux. Collection architecture must be asynchronous (threads or a
collector process) so slow kernel reads never freeze the GUI.

## 4. Linux kernel interfaces

| Source | Purpose |
| --- | --- |
| `/proc/stat` | CPU utilization and system counters |
| `/proc/meminfo` | RAM and swap information |
| `/proc/loadavg` | System load |
| `/proc/uptime` | System uptime |
| `/proc/[pid]/stat` | Process statistics and CPU accounting |
| `/proc/[pid]/status` | Process status, memory, UID, threads |
| `/proc/[pid]/cmdline` | Command-line arguments |
| `/proc/[pid]/io` | Per-process I/O accounting |
| `/proc/[pid]/fd` | Open file descriptors |
| `/proc/diskstats` | Disk I/O counters |
| `/proc/net/dev` | Network interface counters |
| `/proc/pressure/` | CPU, memory, and I/O pressure |
| `/sys/class/hwmon/` | Temperature and fan readings |
| `/sys/class/net/` | Network interface details |
| `/sys/class/power_supply/` | Battery and power information |
| `/sys/class/drm/` | GPU device information |

All access must be permission-aware and tolerate missing files and kernel
configuration differences.

## 5. Source code organization

```
sentinel/
├── README.md  LICENSE
├── build/  packaging/  resources/{icons,themes,translations}/
├── src/
│   ├── main.k
│   ├── core/{processes,cpu,memory,disk,network,hardware,services,security,diagnostics,metrics}.k
│   ├── platform/linux/{procfs,sysfs,signals,sysvinit,permissions}.k
│   ├── gui/{app,dashboard,processes,performance,services,security}.htk + components/
│   └── helper/{protocol,authorization}.k
└── tests/{process_tests,metrics_tests,service_tests,security_tests}.k
```

`.htk` is the proposed convention for Objective-K GUI files; the exact
build/import structure must match the compiler's Linux implementation.

## 6. Performance and security requirements

| Requirement | Suggested target |
| --- | --- |
| CPU and RAM refresh | every 1 s |
| Process list refresh | every 1–2 s |
| Disk/network refresh | every 1 s |
| Hardware sensor refresh | every 3–5 s |
| Default graph history | 60 s |
| Extended history | configurable, bounded |
| Idle resource usage | < 1% of one core |
| RAM usage | < 75 MB initially |
| Desktop responsiveness | GUI never blocked on collector reads |
| Privileges | unprivileged by default |

Engineering targets to validate on the actual KryptOS build, not
guaranteed measurements. Security model: explicit authorization for
privileged actions, minimal helper permissions, fixed service-script paths,
shell-injection protection, careful handling of rapidly exiting processes;
PID 1, critical services and the current desktop session get extra warnings
before destructive actions.

## 7. Roadmap

**Phase 1 — Native foundation**
- Confirm Objective-K Linux GUI support
- Sentinel window, navigation, theme, graph component
- Krypton procfs collectors
- Live CPU/RAM/process views
- Process sorting, search, details, safe termination

**Phase 2 — KryptOS integration**
- SysVinit service detection and status
- Authorized service controls
- Startup applications and runlevels
- Disk and network monitoring
- Desktop launcher, icons, packaging

**Phase 3 — Advanced performance**
- Per-core CPU graphs, process trees
- Memory pressure, swap, I/O diagnostics
- Hardware sensor discovery
- GPU statistics where available
- Logging, history, diagnostic exports

**Phase 4 — Security and release**
- Security visibility and configurable alerts
- Restricted privileged helper + authorization tests
- Stress and low-memory testing
- Behavior validation across supported hardware
- Accessibility, localization, documentation

## 8. After version 1.0

Krypton application awareness (package-manager metadata); resource limits
via cgroups; developer mode (args, threads, maps, fds, debug info);
recovery mode (fallback UI under load); historical comparisons across app
updates; Boot Optimization Assistant; optional remote monitoring via a
separately secured service.

## 9. Release criteria

1. Launches reliably without root.
2. Works with SysVinit; no mandatory systemd dependency.
3. Accurate process CPU and memory reporting.
4. Multi-core/multi-processor support.
5. Responsive under high CPU/RAM/disk pressure.
6. Handles processes disappearing during collection.
7. Never terminates the wrong process (PID reuse protection).
8. Handles missing hardware sensors gracefully.
9. Distinguishes unavailable information from zero usage.
10. Recovers from failed privileged operations without crashing.

## Recommendation

Sentinel 0.1: fully functional lightweight process manager — polished
Objective-K GUI, live performance graphs, dependable process controls.
Sentinel 0.2: SysVinit service and startup management as first-class
features. The gating milestone is proving the Objective-K/Choc GUI path on
Linux; once it works, the collector and everything else can grow
independently.
