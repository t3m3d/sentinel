// sentinel.k — KryptOS Sentinel, Linux GUI proof of concept (0.0.1-poc).
//
// Proves the Linux-first UI path end to end, inside KryptOS/Linux:
//   • window creation + shm rendering through k:choc_linux (Wayland wire
//     protocol, pure Krypton — no GTK, no FFI, no libc)
//   • drawing primitives (fill rect, stroke rect, BGRA pixels, font text)
//   • keyboard events (q / Escape quits in --watch mode)
//   • live /proc collectors (CPU, memory, load average, uptime, kernel)
//   • a KryptOS-styled frame: Catppuccin-Mocha dark base, purple/green accents
//
// Build (inside KryptOS or the x86_64 Lima VM):
//   KRYPTON_ROOT=<krypton> ./bootstrap/kcc_driver_linux_x86_64 \
//     src/sentinel.k -o sentinel
//
// Run:
//   ./sentinel            draw one frame, present it, print status, exit
//   ./sentinel --smoke    no window; print collected stats and exit
//   ./sentinel --watch    interactive; redraw on events, q/Esc quits
//
// NOTE: the Linux ELF frontend only processes transitive imports one level
// deep, so k:smack/geometry (where colorRGB lives) is imported directly.

import "k:choc_linux"
import "k:smack/geometry"
import "k:smack/compositor"

// ── palette (KryptOS / Catppuccin Mocha dark) ────────────────────────
let BG       = colorRGB(30, 30, 46)     // #1e1e2e base
let BG_CRUST = colorRGB(17, 17, 27)     // #11111b sidebar / panels
let SURFACE  = colorRGB(49, 50, 68)     // #313244 borders
let FG       = colorRGB(205, 214, 244)  // #cdd6f4
let FG_DIM   = colorRGB(166, 173, 200)  // #a6adc8
let PURPLE   = colorRGB(203, 166, 247)  // #cba6f7 accent
let GREEN    = colorRGB(166, 227, 161)  // #a6e3a1 accent
let SEL_BG   = colorRGB(47, 40, 70)     // selected nav row

// ── small string / parse helpers (mirrors kryofetch/run_linux.k) ─────
// native linecount() crashes on the Linux ELF backend; local re-implementation
// (same algorithm as kryofetch/run_linux.k).
func lineCount(s) {
    if s == "" { emit 0 }
    let t = trim(s)
    if t == "" { emit 0 }
    let n = 1
    let i = 0
    while i < len(t) {
        let ch = substring(t, i, i + 1)
        if ch == "\n" { n += 1 }
        i += 1
    }
    emit n
}

func findLine(s, key) {
    let n = toInt(lineCount(s))
    let i = 0
    while i < n {
        let ln = getLine(s, i)
        if startsWith(ln, key) { emit ln }
        i = i + 1
    }
    emit ""
}

func afterColon(s) {
    let p = indexOf(s, ":")
    if p < 0 { emit trim(s) }
    emit trim(substring(s, p + 1, len(s)))
}

func firstpart(s, delim) {
    let p = indexOf(s, delim)
    if p < 0 { emit s }
    emit substring(s, 0, toInt(p))
}

func afterpart(s, delim) {
    let p = indexOf(s, delim)
    if p < 0 { emit "" }
    emit substring(s, toInt(p) + 1, len(s))
}

// nth space-separated token as an int (tolerates runs of spaces)
func nthNum(line, want) {
    let i = 0
    let n = len(line)
    let field = 0 - 1
    while i < n {
        while i < n && line[i] == " " { i += 1 }
        let start = i
        while i < n && line[i] != " " { i += 1 }
        if start < i {
            field += 1
            if field == want { emit toInt(substring(line, start, i)) }
        }
    }
    emit 0
}

// nth space-separated token as raw text
func nthTok(s, want) {
    let i = 0
    let n = len(s)
    let field = 0 - 1
    while i < n {
        while i < n && s[i] == " " { i += 1 }
        let start = i
        while i < n && s[i] != " " { i += 1 }
        if start < i {
            field += 1
            if field == want { emit substring(s, start, i) }
        }
    }
    emit ""
}

func clip(s, max) {
    if len(s) > max { emit substring(s, 0, max) }
    emit s
}

// ── /proc collectors ─────────────────────────────────────────────────
// aggregate ticks from /proc/stat, packed "total,idle"
func cpuPair() {
    let st = readProc("/proc/stat")
    let n = toInt(lineCount(st))
    let i = 0
    while i < n {
        let ln = getLine(st, i)
        // aggregate line is exactly "cpu " + fields; per-core lines are "cpuN"
        if substring(ln, 0, 4) == "cpu " {
            let total = nthNum(ln, 1) + nthNum(ln, 2) + nthNum(ln, 3) + nthNum(ln, 4) + nthNum(ln, 5) + nthNum(ln, 6) + nthNum(ln, 7) + nthNum(ln, 8)
            let idle  = nthNum(ln, 4) + nthNum(ln, 5)
            emit total + "," + idle
        }
        i += 1
    }
    emit "0,0"
}

func cpuPercent() {
    let a = cpuPair()
    let aTotal = toInt(firstpart(a, ","))
    let aIdle  = toInt(afterpart(a, ","))
    sleepUs(0, 250000)
    let b = cpuPair()
    let bTotal = toInt(firstpart(b, ","))
    let bIdle  = toInt(afterpart(b, ","))
    let dTotal = bTotal - aTotal
    let dIdle  = bIdle - aIdle
    if dTotal <= 0 { emit 0 }
    emit (dTotal - dIdle) * 100 / dTotal
}

// "usedMB,totalMB,pct" from /proc/meminfo
func memInfo() {
    let mi = readProc("/proc/meminfo")
    let tl = findLine(mi, "MemTotal:")
    let al = findLine(mi, "MemAvailable:")
    if tl == "" { emit "0,0,0" }
    let total = toInt(firstpart(afterColon(tl), " "))
    let avail = toInt(firstpart(afterColon(al), " "))
    if total <= 0 { emit "0,0,0" }
    let used = total - avail
    emit (used / 1024) + "," + (total / 1024) + "," + (used * 100 / total)
}

func loadavg() {
    emit trim(readProc("/proc/loadavg"))
}

func uptimeParts() {
    let raw = trim(readProc("/proc/uptime"))
    emit firstpart(raw, ".")
}

func uptimeStr() {
    let secs = toInt(uptimeParts())
    let d = secs / 86400
    let h = (secs % 86400) / 3600
    let m = (secs % 3600) / 60
    if d > 0 { emit d + "d " + h + "h " + m + "m" }
    if h > 0 { emit h + "h " + m + "m" }
    emit m + "m"
}

func cpuModel() {
    let ci = readProc("/proc/cpuinfo")
    let ln = findLine(ci, "model name")
    if ln != "" { emit clip(afterColon(ln), 62) }
    emit "Unknown CPU"
}

func coreCount() {
    let ci = readProc("/proc/cpuinfo")
    let n = toInt(lineCount(ci))
    let i = 0
    let c = 0
    while i < n {
        let ln = getLine(ci, i)
        if substring(ln, 0, 9) == "processor" { c += 1 }
        i += 1
    }
    if c == 0 { c = 1 }
    emit c
}

func hostName() {
    let h = trim(readProc("/proc/sys/kernel/hostname"))
    if h == "" { emit "unknown" }
    emit h
}

func kernelRelease() {
    let k = trim(readProc("/proc/sys/kernel/osrelease"))
    if k == "" { emit "unknown" }
    emit k
}

// gather everything once into a struct
func collect() {
    let mi = memInfo()
    let s = structNew()
    s = setField(s, "cpuPct", cpuPercent())
    s = setField(s, "memUsed", firstpart(mi, ","))
    let rest = afterpart(mi, ",")
    s = setField(s, "memTotal", firstpart(rest, ","))
    s = setField(s, "memPct", afterpart(rest, ","))
    let la = loadavg()
    s = setField(s, "load1", nthTok(la, 0))
    s = setField(s, "load5", nthTok(la, 1))
    s = setField(s, "load15", nthTok(la, 2))
    s = setField(s, "uptime", uptimeStr())
    s = setField(s, "cpuModel", cpuModel())
    s = setField(s, "cores", coreCount())
    s = setField(s, "host", hostName())
    s = setField(s, "kernel", kernelRelease())
    let u = environ("USER")
    if u == "" { u = "unknown" }
    s = setField(s, "user", u)
    emit s
}

// ── drawing ──────────────────────────────────────────────────────────
func navItem(win, y, label, selected) {
    if selected == 1 {
        chocFillRect(win, 10, y - 3, 212, 24, SEL_BG)
        chocFillRect(win, 10, y - 3, 3, 24, PURPLE)
        chocDrawText(win, 24, y, label, PURPLE)
        return 1
    }
    chocDrawText(win, 24, y, label, FG_DIM)
    return 0
}

func sidebar(win) {
    chocFillRect(win, 0, 0, 232, 600, BG_CRUST)
    chocDrawText(win, 20, 24, "SENTINEL", PURPLE)
    chocDrawText(win, 20, 44, "KryptOS System Monitor", FG_DIM)
    chocFillRect(win, 16, 68, 200, 1, SURFACE)
    let items = "Dashboard,Processes,Performance,Memory,Storage,Network,Hardware,Services,Startup,Security,System Logs,Diagnostics"
    let i = 0
    let y = 84
    while i < 12 {
        let label = firstpart(items, ",")
        let sel = 0
        if i == 0 { sel = 1 }
        navItem(win, y, label, sel)
        // advance past the comma we just consumed
        let p = indexOf(items, ",")
        if p < 0 { items = "" } else { items = substring(items, toInt(p) + 1, len(items)) }
        i += 1
        y += 34
    }
    // sidebar footer: nominal status + version
    chocFillRect(win, 20, 508, 8, 8, GREEN)
    chocDrawText(win, 36, 508, "All systems nominal", FG_DIM)
    chocDrawText(win, 20, 556, "sentinel v0.0.1-poc", FG_DIM)
}

func card(win, x, label, value, sub, accent) {
    chocFillRect(win, x, 64, 160, 96, BG_CRUST)
    chocStrokeRect(win, x, 64, 160, 96, SURFACE, 1)
    chocDrawText(win, x + 12, 76, label, FG_DIM)
    chocDrawText(win, x + 12, 100, value, accent)
    chocDrawText(win, x + 12, 128, sub, FG_DIM)
}

func bar(win, y, label, pct, color) {
    chocDrawText(win, 256, y, label, FG_DIM)
    chocFillRect(win, 312, y, 520, 14, SURFACE)
    let w = toInt(pct) * 520 / 100
    if w > 0 { chocFillRect(win, 312, y, w, 14, color) }
    chocDrawText(win, 844, y - 1, pct + "%", FG)
}

func drawFrame(win, s) {
    chocClear(win, BG)
    sidebar(win)

    // header
    let host = getField(s, "host")
    chocDrawText(win, 256, 20, "Dashboard", FG)
    let hx = 952 - len(host) * 8
    if hx < 500 { hx = 500 }
    chocDrawText(win, hx, 22, host, FG_DIM)
    chocFillRect(win, 256, 44, 696, 1, SURFACE)

    // cards: CPU / MEMORY / LOAD AVG / UPTIME
    let cpuPct = toInt(getField(s, "cpuPct"))
    let memPct = toInt(getField(s, "memPct"))
    card(win, 256, "CPU", cpuPct + "%", getField(s, "cores") + " threads", PURPLE)
    card(win, 428, "MEMORY", getField(s, "memUsed") + " MB", "of " + getField(s, "memTotal") + " MB", GREEN)
    card(win, 600, "LOAD AVG", getField(s, "load1"), getField(s, "load5") + " / " + getField(s, "load15"), FG)
    card(win, 772, "UPTIME", getField(s, "uptime"), "since boot", FG)

    // resource pressure bars
    chocDrawText(win, 256, 184, "RESOURCE PRESSURE", FG_DIM)
    bar(win, 208, "CPU", cpuPct + "", PURPLE)
    bar(win, 240, "RAM", memPct + "", GREEN)

    // system panel
    chocDrawText(win, 256, 288, "SYSTEM", FG_DIM)
    chocFillRect(win, 256, 304, 696, 160, BG_CRUST)
    chocStrokeRect(win, 256, 304, 696, 160, SURFACE, 1)
    chocDrawText(win, 272, 320, "Kernel:    " + getField(s, "kernel"), FG)
    chocDrawText(win, 272, 344, "CPU:       " + getField(s, "cpuModel"), FG)
    chocDrawText(win, 272, 368, "Hostname:  " + getField(s, "host"), FG)
    chocDrawText(win, 272, 392, "User:      " + getField(s, "user"), FG)
    chocDrawText(win, 272, 416, "Processes: unavailable (needs getdents64)", FG_DIM)

    // footer
    chocDrawText(win, 256, 556, "sentinel 0.0.1-poc - KryptOS - Wayland", FG_DIM)
}

// pixel self-check for --verify: compare against expected packed colors
func checkPx(smack, x, y, want) {
    let px = smackSurfacePixel(smack, x, y)
    if px == want {
        print("verify ok (" + x + "," + y + ")")
        emit 0
    }
    print("verify FAIL (" + x + "," + y + ") want=" + want + " got=" + px)
    emit 1
}

// ── input ────────────────────────────────────────────────────────────
let pocQuit = 0
func onKey(kc, mods) {
    if kc == 16 { pocQuit = 1 }   // evdev KEY_Q
    if kc == 1  { pocQuit = 1 }   // evdev KEY_ESC
}

// ── entry ────────────────────────────────────────────────────────────
just run {
    let smoke = 0
    let watch = 0
    let verify = 0
    let i = 0
    let n = argCount()
    while i < n {
        let a = arg(i)
        if a == "--smoke" { smoke = 1 }
        if a == "--watch" { watch = 1 }
        if a == "--verify" { verify = 1 }
        i += 1
    }

    if smoke == 1 {
        let s = collect()
        print("sentinel-smoke cpuPct=" + getField(s, "cpuPct"))
        print("sentinel-smoke memUsed=" + getField(s, "memUsed") + " memTotal=" + getField(s, "memTotal") + " memPct=" + getField(s, "memPct"))
        print("sentinel-smoke load1=" + getField(s, "load1") + " load5=" + getField(s, "load5") + " load15=" + getField(s, "load15"))
        print("sentinel-smoke uptime=" + getField(s, "uptime") + " kernel=" + getField(s, "kernel"))
        print("sentinel-smoke hostname=" + getField(s, "host") + " user=" + getField(s, "user"))
        print("sentinel-smoke cpu=" + getField(s, "cpuModel") + " cores=" + getField(s, "cores"))
        print("sentinel-smoke ok")
        exit("0")
    }

    let app = chocSharedApp()
    let win = chocWindow(app, "KryptOS Sentinel", 960, 600)
    chocShow(win, app)
    win = chocOnKey(win, funcptr(onKey))

    if watch == 1 {
        let s = collect()
        drawFrame(win, s)
        win = chocPresent(win)
        while pocQuit == 0 {
            win = chocPumpEvents(win)
            let s2 = collect()
            drawFrame(win, s2)
            win = chocPresent(win)
        }
        chocClear(win, BG)
        print("sentinel-poc watch exit")
        exit("0")
    }

    let s = collect()
    drawFrame(win, s)
    if verify == 1 {
        let smack = getField(win, "smack")
        let fails = 0
        fails += checkPx(smack, 5, 5, "17,17,27,255")      // sidebar BG_CRUST
        fails += checkPx(smack, 400, 500, "30,30,46,255")  // content BG
        fails += checkPx(smack, 11, 90, "203,166,247,255") // Dashboard accent bar PURPLE
        fails += checkPx(smack, 100, 90, "47,40,70,255")   // selected nav row SEL_BG
        fails += checkPx(smack, 330, 64, "49,50,68,255")   // CPU card border SURFACE
        fails += checkPx(smack, 300, 110, "17,17,27,255")  // card fill BG_CRUST
        if fails == 0 { print("sentinel-verify ok")  exit("0") }
        print("sentinel-verify failed=" + fails)
        exit("1")
    }
    win = chocPumpEvents(win)          // ack xdg configure + present
    win = chocPresent(win)
    print("sentinel-poc-frame ok")
}
