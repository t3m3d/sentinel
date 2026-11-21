// sentinel.k — KryptOS Sentinel task manager 0.1.0-dev
// Pure Krypton + k:choc_linux on Wayland (wl_shm). Single source file
// (Linux ELF frontend follows imports one level deep).
//
//   KRYPTON_ROOT=<k> kcc_driver_linux_x86_64 src/sentinel.k -o sentinel
//   ./sentinel            interactive (q/Esc quits)
//   ./sentinel --smoke    telemetry snapshot, no window
//   ./sentinel --verify   pixel self-check against the framebuffer
//
// Controls: q/Esc quit · r refresh · 1..0 switch sidebar section
//   Up/Down navigate process list · Tab toggle filter focus
//   letters type filter · Backspace delete · Enter inspect
//   k kill · s stop · c continue · click sidebar/rows

import "k:choc_linux"
import "k:smack/geometry"

// ── palette (KryptOS / Catppuccin Mocha dark) ────────────────────────
let BG       = colorRGB(30, 30, 46)
let BG_CRUST = colorRGB(17, 17, 27)
let SURFACE  = colorRGB(49, 50, 68)
let BORDER   = colorRGB(88, 90, 124)
let FG       = colorRGB(205, 214, 244)
let FG_DIM   = colorRGB(166, 173, 200)
let PURPLE   = colorRGB(203, 166, 247)
let GREEN    = colorRGB(166, 227, 161)
let RED      = colorRGB(243, 139, 168)
let SEL_BG   = colorRGB(47, 40, 70)
let ROW_ALT  = colorRGB(42, 43, 62)

// ── geometry ─────────────────────────────────────────────────────────
let WIN_W = 960
let WIN_H = 600
let SIDEBAR_W = 240
let CONTENT_X = 244
let ROW_H = 16
let TOP_H = 44
let TABLE_Y = 112
let VISIBLE = 38

// ── UI state ─────────────────────────────────────────────────────────
let gView = 0
let gQuit = 0
let gMx = 0
let gMy = 0
let gRows = structNew()
let gRowCount = 0
let gPrev = structNew()
let gPrevTotalC = 0
let gTotalC = 0
let gSel = 0
let gFilterFocus = 0
let gFilter = ""
let gSortCol = 2
let gSortDir = -1
let gScroll = 0
let gDialog = 0
let gDialogPid = ""
let gInspect = 0
let gInspectPid = ""
let gStatus = ""
let gStatusUntil = 0

// ── system snapshot ──────────────────────────────────────────────────
let gMemUsed = 0
let gMemTotal = 0
let gMemPct = 0
let gLoad1 = ""
let gLoad5 = ""
let gLoad15 = ""
let gUptimeS = 0
let gNcores = 1
let gCpuModel = "unknown"
let gHost = "unknown"
let gKernel = "unknown"
let gCores = 0
let gCpuPct = 0

// ── helpers ──────────────────────────────────────────────────────────
func lineCount(s) {
    if s == "" { emit 0 }
    let t = trim(s)
    if t == "" { emit 0 }
    let n = 1
    let i = 0
    while i < len(t) {
        if substring(t, i, i + 1) == "\n" { n += 1 }
        i += 1
    }
    emit n
}

func findLine(s, key) {
    let n = lineCount(s)
    let i = 0
    while i < n {
        let ln = getLine(s, i)
        if startsWith(ln, key) { emit ln }
        i += 1
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
    emit substring(s, 0, p)
}

func afterpart(s, delim) {
    let p = indexOf(s, delim)
    if p < 0 { emit "" }
    emit substring(s, p + 1, len(s))
}

func nthTok(s, want) {
    let i = 0
    let n = len(s)
    let field = -1
    while i < n {
        while i < n && substring(s, i, i + 1) == " " { i += 1 }
        let start = i
        while i < n && substring(s, i, i + 1) != " " { i += 1 }
        field += 1
        if field == want { emit substring(s, start, i) }
        if i < n { i += 1 }
    }
    emit ""
}

func nthNum(line, want) {
    let tok = nthTok(line, want)
    if tok == "" { emit 0 }
    emit toInt(tok)
}

func clip(s, max) {
    if len(s) > max { emit substring(s, 0, max) }
    emit s
}

func padLeftI(n, w) {
    let s = n + ""
    while len(s) < w { s = " " + s }
    emit s
}

func strLower(s) {
    let out = ""
    let i = 0
    let n = len(s)
    while i < n {
        let cc = charCode(substring(s, i, i + 1))
        if cc >= 65 && cc <= 90 { out = out + fromCharCode(cc + 32) }
        else { out = out + substring(s, i, i + 1) }
        i += 1
    }
    emit out
}

func containsCI(s, sub) {
    emit contains(strLower(s), strLower(sub))
}

func rectHit(x, y, x0, y0, w, h) {
    if x >= x0 && x < x0 + w && y >= y0 && y < y0 + h { emit 1 }
    else { emit 0 }
}

func stateColor(st) {
    if st == "R" { emit GREEN }
    else if st == "Z" { emit RED }
    else if st == "T" { emit PURPLE }
    else if st == "D" { emit colorRGB(243, 189, 128) }
    else { emit FG_DIM }
}

func uidToUser(uid) {
    let pw = readProc("/etc/passwd")
    let n = lineCount(pw)
    let i = 0
    while i < n {
        let ln = getLine(pw, i)
        let p1 = indexOf(ln, ":")
        if p1 >= 0 {
            let rest1 = substring(ln, p1 + 1, len(ln))
            let p2 = indexOf(rest1, ":")
            if p2 >= 0 {
                let rest2 = substring(rest1, p2 + 1, len(rest1))
                let p3 = indexOf(rest2, ":")
                if p3 >= 0 {
                    let u = substring(rest2, 0, p3)
                    if u == uid { emit substring(ln, 0, p1) }
                }
            }
        }
        i += 1
    }
    emit uid
}

// ── /proc collectors ─────────────────────────────────────────────────
func cpuPair() {
    let st = readProc("/proc/stat")
    let n = lineCount(st)
    let i = 0
    while i < n {
        let ln = getLine(st, i)
        if substring(ln, 0, 4) == "cpu " {
            let total = nthNum(ln, 1) + nthNum(ln, 2) + nthNum(ln, 3) + nthNum(ln, 4) + nthNum(ln, 5) + nthNum(ln, 6) + nthNum(ln, 7) + nthNum(ln, 8)
            let idle = nthNum(ln, 4) + nthNum(ln, 5)
            emit total + "," + idle
        }
        i += 1
    }
    emit "0,0"
}

func cpuPercent() {
    let a = cpuPair()
    let aTotal = toInt(firstpart(a, ","))
    let aIdle = toInt(afterpart(a, ","))
    sleepUs(0, 250000)
    let b = cpuPair()
    let bTotal = toInt(firstpart(b, ","))
    let bIdle = toInt(afterpart(b, ","))
    let dTotal = bTotal - aTotal
    let dIdle = bIdle - aIdle
    if dTotal <= 0 { emit 0 }
    emit (dTotal - dIdle) * 100 / dTotal
}

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

func loadAvg() {
    emit trim(readProc("/proc/loadavg"))
}

func readUptimeSec() {
    let raw = trim(readProc("/proc/uptime"))
    emit toInt(firstpart(firstpart(raw, " "), "."))
}

func uptimeStr() {
    let secs = readUptimeSec()
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
    if ln != "" { emit clip(afterColon(ln), 56) }
    emit "Unknown CPU"
}

func nCores() {
    let ci = readProc("/proc/cpuinfo")
    let n = lineCount(ci)
    let i = 0
    let c = 0
    while i < n {
        let ln = getLine(ci, i)
        if startsWith(ln, "processor") { c += 1 }
        i += 1
    }
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

// per-core utilization (stores into gCores count only; values in gCoresStr)
let gCoresStr = ""
let gCoreCount = 0
func scanCores() {
    let st = readProc("/proc/stat")
    let n = lineCount(st)
    let i = 0
    let c = 0
    let out = ""
    while i < n {
        let ln = getLine(st, i)
        if substring(ln, 0, 3) == "cpu" {
            let cc = charCode(substring(ln, 3, 4))
            if cc >= 48 && cc <= 57 {
                let total = nthNum(ln, 1) + nthNum(ln, 2) + nthNum(ln, 3) + nthNum(ln, 4) + nthNum(ln, 5) + nthNum(ln, 6) + nthNum(ln, 7) + nthNum(ln, 8)
                let idle = nthNum(ln, 4) + nthNum(ln, 5)
                out = out + total + "," + idle + ";"
                c += 1
            }
        }
        i += 1
    }
    gCoreCount = c
    gCoresStr = out
}

// parse per-core percent into gCorePctStr (comma list) using prev snapshot stored in gCorePrevStr
let gCorePrevStr = ""
let gCorePctStr = ""
func corePercents() {
    let st = readProc("/proc/stat")
    // rebuild totals list
    let n = lineCount(st)
    let i = 0
    let totals = ""
    while i < n {
        let ln = getLine(st, i)
        if substring(ln, 0, 3) == "cpu" {
            let cc = charCode(substring(ln, 3, 4))
            if cc >= 48 && cc <= 57 {
                let total = nthNum(ln, 1) + nthNum(ln, 2) + nthNum(ln, 3) + nthNum(ln, 4) + nthNum(ln, 5) + nthNum(ln, 6) + nthNum(ln, 7) + nthNum(ln, 8)
                let idle = nthNum(ln, 4) + nthNum(ln, 5)
                totals = totals + total + "," + idle + ";"
            }
        }
        i += 1
    }
    // compute deltas vs gCorePrevStr
    let prev = gCorePrevStr
    let pctOut = ""
    let ti = 0
    let pi = 0
    // walk both lists
    let trest = totals
    let prest = prev
    while len(trest) > 0 {
        let tseg = firstpart(trest, ";")
        trest = afterpart(trest, ";")
        let pseg = ""
        if len(prest) > 0 {
            pseg = firstpart(prest, ";")
            prest = afterpart(prest, ";")
        }
        let tTotal = toInt(firstpart(tseg, ","))
        let tIdle = toInt(afterpart(tseg, ","))
        let pTotal = 0
        let pIdle = 0
        if pseg != "" {
            pTotal = toInt(firstpart(pseg, ","))
            pIdle = toInt(afterpart(pseg, ","))
        }
        let dt = tTotal - pTotal
        let di = tIdle - pIdle
        let pct = 0
        if dt > 0 { pct = (dt - di) * 100 / dt }
        pctOut = pctOut + pct + ","
    }
    gCorePctStr = pctOut
    gCorePrevStr = totals
}

// process enumeration via exec (workaround until getdents64 builtin exists)
func scanProcesses() {
    let out = exec("printf '%s\\n' /proc/[0-9]* 2>/dev/null")
    let n = lineCount(out)
    let count = 0
    let i = 0
    let pair = cpuPair()
    let totalC = toInt(firstpart(pair, ","))
    let dtot = totalC - gPrevTotalC
    if dtot <= 0 { dtot = 1 }
    gPrevTotalC = totalC
    gTotalC = totalC
    // reset rows
    gRows = structNew()
    while i < n {
        let ln = getLine(out, i)
        if substring(ln, 0, 6) == "/proc/" {
            let pid = substring(ln, 6, len(ln))
            let stat = readProc("/proc/" + pid + "/stat")
            if len(stat) > 0 {
                let pp = indexOf(stat, ")")
                if pp >= 0 {
                    let rest = substring(stat, pp + 2, len(stat))
                    let state = substring(rest, 0, 1)
                    let ppid = nthTok(rest, 1)
                    let utime = nthTok(rest, 11)
                    let stime = nthTok(rest, 12)
                    let priority = nthTok(rest, 15)
                    let nice = nthTok(rest, 16)
                    let threads = nthTok(rest, 17)
                    let ticks = toInt(utime) + toInt(stime)
                    let prevTicks = 0
                    let key = "t" + pid
                    let pv = getField(gPrev, key)
                    if pv != "" { prevTicks = toInt(pv) }
                    let dTicks = ticks - prevTicks
                    let pct = dTicks * 100 / dtot
                    if pct < 0 { pct = 0 }
                    if pct > 999 { pct = 999 }
                    gPrev = setField(gPrev, key, ticks + "")
                    let sts = readProc("/proc/" + pid + "/status")
                    let name = "(" + pid + ")"
                    let nameRaw = findLine(sts, "Name:")
                    if nameRaw != "" { name = trim(afterColon(nameRaw)) }
                    let uidLine = findLine(sts, "Uid:")
                    let uid = "0"
                    if uidLine != "" { uid = nthTok(uidLine, 1) }
                    let user = uidToUser(uid)
                    let vmLine = findLine(sts, "VmRSS:")
                    let rssMB = 0
                    if vmLine != "" { rssMB = toInt(firstpart(afterColon(vmLine), " ")) / 1024 }
                    let thrLine = findLine(sts, "Threads:")
                    let thr = threads
                    if thrLine != "" { thr = nthTok(thrLine, 1) }
                    let row = pid + "|" + name + "|" + pct + "|" + rssMB + "|" + state + "|" + user + "|" + ppid + "|" + thr + "|" + priority + "|" + nice
                    gRows = setField(gRows, "p" + count, row)
                    count += 1
                }
            }
        }
        i += 1
    }
    gRowCount = count
}

func refreshSys() {
    let mi = memInfo()
    gMemUsed = toInt(firstpart(mi, ","))
    let r1 = afterpart(mi, ",")
    gMemTotal = toInt(firstpart(r1, ","))
    let r2 = afterpart(r1, ",")
    gMemPct = toInt(r2)
    let la = loadAvg()
    gLoad1 = nthTok(la, 0)
    gLoad5 = nthTok(la, 1)
    gLoad15 = nthTok(la, 2)
    gNcores = nCores()
    gCpuModel = cpuModel()
    gHost = hostName()
    gKernel = kernelRelease()
    gUptimeS = readUptimeSec()
    scanCores()
    corePercents()
    scanProcesses()
}

func maybeTick() {
    let sec = readUptimeSec()
    // always refresh on first call (gUptimeS==0) or new second
    if gUptimeS == 0 || sec != gUptimeS {
        refreshSys()
    }
}

func setStatus(msg) {
    gStatus = msg
    gStatusUntil = readUptimeSec() + 4
}

func sigAction(pid, sig) {
    let out = exec("kill -" + sig + " " + pid + " 2>&1")
    let t = trim(out)
    if t == "" { setStatus("signal " + sig + " sent to " + pid) }
    else { setStatus("kill " + sig + " " + pid + ": " + t) }
}

// ── row helpers ──────────────────────────────────────────────────────
func rowPid(row) { emit nthTok(row, 0) }  // pipe split manual below
func nthPipe(s, want) {
    let i = 0
    let n = len(s)
    let field = -1
    while i < n {
        let start = i
        while i < n && substring(s, i, i + 1) != "|" { i += 1 }
        field += 1
        if field == want { emit substring(s, start, i) }
        if i < n { i += 1 }
    }
    emit ""
}

func matchingCount() {
    let c = 0
    let i = 0
    while i < gRowCount {
        let row = getField(gRows, "p" + i)
        if containsCI(row, gFilter) { c += 1 }
        i += 1
    }
    emit c
}

func nthMatchingIndex(sel) {
    let c = 0
    let i = 0
    while i < gRowCount {
        let row = getField(gRows, "p" + i)
        if containsCI(row, gFilter) {
            if c == sel { emit i }
            c += 1
        }
        i += 1
    }
    emit -1
}

func selectedPid() {
    let si = nthMatchingIndex(gSel)
    if si < 0 { emit "" }
    let row = getField(gRows, "p" + si)
    emit nthPipe(row, 0)
}

func clampSel() {
    let mc = matchingCount()
    if mc == 0 { gSel = 0 }
    else if gSel >= mc { gSel = mc - 1 }
    if gSel < 0 { gSel = 0 }
    if gSel < gScroll { gScroll = gSel }
    if gSel >= gScroll + VISIBLE { gScroll = gSel - VISIBLE + 1 }
    if gScroll < 0 { gScroll = 0 }
}

func cmpRows(a, b) {
    let fa = nthPipe(a, gSortCol)
    let fb = nthPipe(b, gSortCol)
    let c = 0
    if gSortCol == 0 || gSortCol == 2 || gSortCol == 3 {
        let ia = toInt(fa)
        let ib = toInt(fb)
        if ia < ib { c = -1 }
        else if ia > ib { c = 1 }
    } else {
        if fa < fb { c = -1 }
        else if fa > fb { c = 1 }
    }
    emit c * gSortDir
}

func sortRows() {
    let i = 0
    while i < gRowCount - 1 {
        let j = 0
        while j < gRowCount - 1 - i {
            let ra = getField(gRows, "p" + j)
            let rb = getField(gRows, "p" + (j + 1))
            if cmpRows(ra, rb) > 0 {
                let t = ra
                gRows = setField(gRows, "p" + j, rb)
                gRows = setField(gRows, "p" + (j + 1), t)
            }
            j += 1
        }
        i += 1
    }
}

// ── drawing ──────────────────────────────────────────────────────────

func card(win, x, y, label, value, sub, accent) {
    chocFillRect(win, x, y, 216, 86, BG_CRUST)
    chocStrokeRect(win, x, y, 216, 86, BORDER, 1)
    chocDrawText(win, x + 12, y + 12, label, FG_DIM)
    chocDrawText(win, x + 12, y + 36, value, accent)
    chocDrawText(win, x + 12, y + 64, sub, FG_DIM)
}

func bar(win, x, y, w, label, pct, color) {
    chocDrawText(win, x, y, label, FG_DIM)
    let bx = x + 120
    chocFillRect(win, bx, y + 2, w, 10, SURFACE)
    chocStrokeRect(win, bx, y + 2, w, 10, BORDER, 1)
    let bw = toInt(pct) * w / 100
    if bw > 0 { chocFillRect(win, bx, y + 2, bw, 10, color) }
    chocDrawText(win, bx + w + 6, y, pct + "%", FG)
}

func drawSidebar(win) {
    chocFillRect(win, 0, 0, SIDEBAR_W, WIN_H, BG_CRUST)
    chocDrawText(win, 20, 22, "SENTINEL", PURPLE)
    chocDrawText(win, 20, 40, "KryptOS Task Manager", FG_DIM)
    chocFillRect(win, 14, 60, SIDEBAR_W - 28, 1, BORDER)
    let items = "Dashboard,Processes,CPU & Scheduling,Memory & Swap,Storage,Network,Services,Wayland Session,Hardware,Users & Sessions,Logs / Journal,Settings"
    let i = 0
    let y = 84
    while i < 12 {
        let label = firstpart(items, ",")
        let p = indexOf(items, ",")
        if p < 0 { items = "" }
        else { items = substring(items, p + 1, len(items)) }
        let active = 0
        if gView == i { active = 1 }
        if active == 1 {
            chocFillRect(win, 12, y - 2, SIDEBAR_W - 24, ROW_H + 4, SEL_BG)
            chocFillRect(win, 12, y - 2, 6, ROW_H + 4, PURPLE)
            chocDrawText(win, 28, y, toInt(i + 1) + "  " + label, PURPLE)
        } else {
            chocDrawText(win, 28, y, toInt(i + 1) + "  " + label, FG_DIM)
        }
        i += 1
        y += 34
    }
    chocFillRect(win, 20, WIN_H - 40, 8, 8, GREEN)
    chocDrawText(win, 36, WIN_H - 42, "All systems nominal", FG_DIM)
    chocDrawText(win, 20, WIN_H - 22, "sentinel 0.1.0-dev", FG_DIM)
}

func sectionTitle() {
    let titles = "Dashboard,Processes,CPU & Scheduling,Memory & Swap,Storage,Network,Services,Wayland Session,Hardware,Users & Sessions,Logs / Journal,Settings"
    let i = 0
    let rest = titles
    while i < gView {
        let p = indexOf(rest, ",")
        rest = substring(rest, p + 1, len(rest))
        i += 1
    }
    emit firstpart(rest, ",")
}

func drawTopBar(win) {
    chocFillRect(win, CONTENT_X, 0, WIN_W - CONTENT_X, TOP_H, BG_CRUST)
    chocDrawText(win, CONTENT_X + 12, 14, sectionTitle(), FG)
    chocDrawText(win, CONTENT_X + 12, 30, "uptime " + uptimeStr() + "  ·  " + environ("USER") + "@" + gHost, FG_DIM)
    chocFillRect(win, CONTENT_X, TOP_H - 1, WIN_W - CONTENT_X, 1, BORDER)
}

func drawDashboard(win) {
    let cx = CONTENT_X + 12
    let cy = 60
    let cw = 216
    let gap = 12
    card(win, cx, cy, "CPU", gCpuPct + "%", gNcores + " cores", PURPLE)
    card(win, cx + cw + gap, cy, "MEM", gMemUsed + " MB", "of " + gMemTotal + " MB", GREEN)
    card(win, cx + (cw + gap) * 2, cy, "SWAP", gMemTotal - gMemUsed + " MB free", "available", FG_DIM)
    card(win, cx + (cw + gap) * 3, cy, "LOAD", gLoad1, gLoad5 + " / " + gLoad15, FG)
    let y2 = cy + 96
    card(win, cx, y2, "PROCS", gRowCount + "", "tasks", FG_DIM)
    card(win, cx + cw + gap, y2, "CORES", gNcores + "", "online", FG_DIM)
    card(win, cx + (cw + gap) * 2, y2, "UPTIME", uptimeStr(), "since boot", FG_DIM)
    card(win, cx + (cw + gap) * 3, y2, "USER", environ("USER"), "session", FG_DIM)
    // per-core bars
    let yy = y2 + 106
    chocDrawText(win, cx, yy, "PER CORE", FG_DIM)
    let by = yy + 20
    let bw = 104
    let bgap = 12
    let i = 0
    let pctArr = gCorePctStr
    while i < gCoreCount && i < 8 {
        let pct = toInt(firstpart(pctArr, ","))
        pctArr = afterpart(pctArr, ",")
        chocDrawText(win, cx + i * (bw + bgap), by - 14, "cpu" + i, FG_DIM)
        bar(win, cx + i * (bw + bgap), by, bw, "", pct, PURPLE)
        i += 1
    }
    let my = by + 44
    chocDrawText(win, cx, my, "memory:  total " + gMemTotal + " MB   avail " + (gMemTotal - gMemUsed) + " MB", FG_DIM)
    chocDrawText(win, cx, my + 18, "swap:    load " + gLoad1 + " " + gLoad5 + " " + gLoad15, FG_DIM)
    // system panel
    let sy = my + 50
    chocFillRect(win, cx, sy, WIN_W - CONTENT_X - 24, 108, BG_CRUST)
    chocStrokeRect(win, cx, sy, WIN_W - CONTENT_X - 24, 108, BORDER, 1)
    chocDrawText(win, cx + 12, sy + 14, "Kernel:    " + gKernel, FG)
    chocDrawText(win, cx + 12, sy + 32, "CPU:       " + clip(gCpuModel, 56), FG)
    chocDrawText(win, cx + 12, sy + 50, "Hostname:  " + gHost, FG)
    chocDrawText(win, cx + 12, sy + 68, "User:      " + environ("USER"), FG)
    chocDrawText(win, cx + 12, sy + 86, "Processes: " + gRowCount, FG_DIM)
}

func drawProcesses(win) {
    let ty = TOP_H + 10
    // filter box
    chocFillRect(win, CONTENT_X + 12, ty, 260, 20, SURFACE)
    if gFilterFocus == 1 { chocStrokeRect(win, CONTENT_X + 12, ty, 260, 20, PURPLE, 1) }
    else { chocStrokeRect(win, CONTENT_X + 12, ty, 260, 20, BORDER, 1) }
    let cur = gFilter
    if gFilterFocus == 1 { cur = cur + "_" }
    chocDrawText(win, CONTENT_X + 18, ty + 4, "filter: " + cur, FG)
    // buttons
    let bx = WIN_W - 96
    chocFillRect(win, bx, ty, 80, 20, SURFACE); chocStrokeRect(win, bx, ty, 80, 20, BORDER, 1); chocDrawText(win, bx + 6, ty + 4, "Refresh", FG)
    bx = bx - 54
    chocFillRect(win, bx, ty, 48, 20, SURFACE); chocStrokeRect(win, bx, ty, 48, 20, BORDER, 1); chocDrawText(win, bx + 4, ty + 4, "Kill", FG)
    bx = bx - 52
    chocFillRect(win, bx, ty, 46, 20, SURFACE); chocStrokeRect(win, bx, ty, 46, 20, BORDER, 1); chocDrawText(win, bx + 4, ty + 4, "Stop", FG)
    bx = bx - 56
    chocFillRect(win, bx, ty, 50, 20, SURFACE); chocStrokeRect(win, bx, ty, 50, 20, BORDER, 1); chocDrawText(win, bx + 6, ty + 4, "Cont", FG)
    bx = bx - 58
    chocFillRect(win, bx, ty, 52, 20, SURFACE); chocStrokeRect(win, bx, ty, 52, 20, BORDER, 1); chocDrawText(win, bx + 6, ty + 4, "Inspect", FG)
    let mc = matchingCount()
    chocDrawText(win, CONTENT_X + 12, ty + 28, "processes: " + gRowCount + "   matching: " + mc, FG_DIM)
    // header
    let hy = TABLE_Y - 18
    chocFillRect(win, CONTENT_X, hy, WIN_W - CONTENT_X - 8, ROW_H, SURFACE)
    chocStrokeRect(win, CONTENT_X, hy, WIN_W - CONTENT_X - 8, ROW_H, BORDER, 1)
    chocDrawText(win, CONTENT_X + 4, hy + 2, "PID", FG_DIM)
    chocDrawText(win, CONTENT_X + 52, hy + 2, "NAME", FG_DIM)
    chocDrawText(win, CONTENT_X + 252, hy + 2, "CPU%", FG_DIM)
    chocDrawText(win, CONTENT_X + 310, hy + 2, "MEM MB", FG_DIM)
    chocDrawText(win, CONTENT_X + 372, hy + 2, "STATE", FG_DIM)
    chocDrawText(win, CONTENT_X + 434, hy + 2, "USER", FG_DIM)
    chocDrawText(win, CONTENT_X + 540, hy + 2, "COMMAND", FG_DIM)
    if gSortCol == 2 { chocDrawText(win, CONTENT_X + 288, hy + 2, gSortDir > 0 ? "v" : "^", PURPLE) }
    // rows
    let disp = 0
    let i = 0
    let si = nthMatchingIndex(gSel)
    while i < gRowCount {
        let row = getField(gRows, "p" + i)
        if containsCI(row, gFilter) {
            if disp >= gScroll && disp < gScroll + VISIBLE {
                let rowY = TABLE_Y + (disp - gScroll) * ROW_H
                let selRow = 0
                if si >= 0 && si == i { selRow = 1 }
                let hovered = 0
                if gMx >= CONTENT_X && gMx < WIN_W - 8 && gMy >= rowY - 1 && gMy < rowY + ROW_H - 1 { hovered = 1 }
                if selRow == 1 { chocFillRect(win, CONTENT_X, rowY - 1, WIN_W - CONTENT_X - 8, ROW_H, SEL_BG) }
                else if hovered == 1 { chocFillRect(win, CONTENT_X, rowY - 1, WIN_W - CONTENT_X - 8, ROW_H, ROW_ALT) }
                chocDrawText(win, CONTENT_X + 4, rowY, nthPipe(row, 0), FG)
                chocDrawText(win, CONTENT_X + 52, rowY, clip(nthPipe(row, 1), 22), stateColor(nthPipe(row, 4)))
                chocDrawText(win, CONTENT_X + 252, rowY, padLeftI(toInt(nthPipe(row, 2)), 4) + "%", FG)
                chocDrawText(win, CONTENT_X + 310, rowY, nthPipe(row, 3), FG)
                chocDrawText(win, CONTENT_X + 372, rowY, nthPipe(row, 4), stateColor(nthPipe(row, 4)))
                chocDrawText(win, CONTENT_X + 434, rowY, clip(nthPipe(row, 5), 14), FG)
                chocDrawText(win, CONTENT_X + 540, rowY, clip(nthPipe(row, 1), 70), FG_DIM)
            }
            disp += 1
        }
        i += 1
    }
    chocDrawText(win, CONTENT_X + 12, WIN_H - 20, "q/Esc quit  ·  r refresh  ·  Up/Down select  ·  Tab filter  ·  Enter inspect  ·  k kill  ·  s stop  ·  c continue", FG_DIM)
}

func drawCPUSched(win) {
    let cx = CONTENT_X + 12
    let cy = TOP_H + 10
    chocFillRect(win, cx, cy, WIN_W - CONTENT_X - 24, 108, BG_CRUST)
    chocStrokeRect(win, cx, cy, WIN_W - CONTENT_X - 24, 108, BORDER, 1)
    chocDrawText(win, cx + 12, cy + 14, "CPU OVERVIEW", FG_DIM)
    chocDrawText(win, cx + 12, cy + 32, "total cpu: " + gCpuPct + "%  ·  " + gNcores + " cores online", FG)
    chocDrawText(win, cx + 12, cy + 50, "load avg: " + gLoad1 + " " + gLoad5 + " " + gLoad15, FG)
    chocDrawText(win, cx + 12, cy + 68, "cpu model: " + clip(gCpuModel, 56), FG)
    chocDrawText(win, cx + 12, cy + 86, "per-core: " + gCorePctStr, FG_DIM)
}

func drawMemSwap(win) {
    let cx = CONTENT_X + 12
    let cy = TOP_H + 10
    fill(win, cx, cy, WIN_W - CONTENT_X - 24, 108, BG_CRUST)
    stroke(win, cx, cy, WIN_W - CONTENT_X - 24, 108, BORDER)
    text(win, cx + 12, cy + 14, "MEMORY & SWAP", FG_DIM)
    text(win, cx + 12, cy + 32, "used: " + gMemUsed + " MB  ·  total: " + gMemTotal + " MB", FG)
    text(win, cx + 12, cy + 50, "pct: " + gMemPct + "  ·  free: " + (gMemTotal - gMemUsed) + " MB", FG)
    text(win, cx + 12, cy + 68, "swap: " + (gMemTotal - gMemUsed) + " MB free", FG_DIM)
    bar(win, cx, cy + 86, 560, "MEM", gMemPct, GREEN)
    bar(win, cx, cy + 116, 560, "FREE", (gMemTotal - gMemUsed) * 100 / (gMemTotal + 1), FG_DIM)
}

func drawPlaceholder(win, index) {
    let titles = "Dashboard,Processes,CPU & Scheduling,Memory & Swap,Storage,Network,Services,Wayland Session,Hardware,Users & Sessions,Logs / Journal,Settings"
    let i = 0
    let rest = titles
    while i < index {
        let p = indexOf(rest, ",")
        rest = substring(rest, p + 1, len(rest))
        i += 1
    }
    let label = firstpart(rest, ",")
    let cx = CONTENT_X + 12
    let cy = 100
    chocFillRect(win, cx, cy, 600, 200, BG_CRUST)
    chocStrokeRect(win, cx, cy, 600, 200, BORDER, 1)
    chocDrawText(win, cx + 20, cy + 40, "Section " + (index + 1) + " of 12 — " + label, FG)
    chocDrawText(win, cx + 20, cy + 72, "Planned for a later milestone (see docs/blueprint.md)", FG_DIM)
    chocDrawText(win, cx + 20, cy + 104, "This build implements Dashboard and Processes.", FG_DIM)
}

func drawDialog(win) {
    let cx = WIN_W / 2 - 200
    let cy = WIN_H / 2 - 80
    chocFillRect(win, 0, 0, WIN_W, WIN_H, colorRGB(0, 0, 0))
    chocFillRect(win, cx, cy, 400, 160, BG_CRUST)
    chocStrokeRect(win, cx, cy, 400, 160, BORDER, 1)
    chocFillRect(win, cx, cy, 400, 30, SURFACE)
    chocDrawText(win, cx + 16, cy + 8, "Confirm signal", PURPLE)
    chocDrawText(win, cx + 20, cy + 56, "Send SIGTERM to PID " + gDialogPid + "?", FG)
    chocDrawText(win, cx + 20, cy + 76, "This cannot be undone.", FG_DIM)
    let by = cy + 104
    chocFillRect(win, cx + 40, by, 60, 26, SURFACE); chocStrokeRect(win, cx + 40, by, 60, 26, PURPLE, 1); chocDrawText(win, cx + 56, by + 6, "Yes", PURPLE)
    chocFillRect(win, cx + 130, by, 60, 26, SURFACE); chocStrokeRect(win, cx + 130, by, 60, 26, BORDER, 1); chocDrawText(win, cx + 146, by + 6, "No", FG)
}

func drawInspector(win) {
    let cx = WIN_W / 2 - 260
    let cy = WIN_H / 2 - 160
    chocFillRect(win, 0, 0, WIN_W, WIN_H, colorRGB(0, 0, 0))
    chocFillRect(win, cx, cy, 520, 320, BG_CRUST)
    chocStrokeRect(win, cx, cy, 520, 320, BORDER, 1)
    chocFillRect(win, cx, cy, 520, 30, SURFACE)
    chocDrawText(win, cx + 16, cy + 8, "Process Inspect", PURPLE)
    let row = ""
    let i = 0
    while i < gRowCount {
        let r = getField(gRows, "p" + i)
        if nthPipe(r, 0) == gInspectPid { row = r }
        i += 1
    }
    let yy = cy + 44
    if row == "" { chocDrawText(win, cx + 20, yy, "process no longer exists", FG_DIM) }
    else {
        chocDrawText(win, cx + 20, yy, "PID:        " + nthPipe(row, 0), FG)
        chocDrawText(win, cx + 20, yy + 18, "Name:       " + clip(nthPipe(row, 1), 50), FG)
        chocDrawText(win, cx + 20, yy + 36, "State:      " + nthPipe(row, 4), stateColor(nthPipe(row, 4)))
        chocDrawText(win, cx + 20, yy + 54, "User:       " + nthPipe(row, 5), FG)
        chocDrawText(win, cx + 20, yy + 72, "PPID:       " + nthPipe(row, 6), FG)
        chocDrawText(win, cx + 20, yy + 90, "Threads:    " + nthPipe(row, 7), FG)
        chocDrawText(win, cx + 20, yy + 108, "Priority:   " + nthPipe(row, 8), FG)
        chocDrawText(win, cx + 20, yy + 126, "Nice:       " + nthPipe(row, 9), FG)
        chocDrawText(win, cx + 20, yy + 144, "RSS:        " + nthPipe(row, 3) + " MB", FG)
        chocDrawText(win, cx + 20, yy + 162, "CPU %:      " + nthPipe(row, 2), FG)
    }
    chocDrawText(win, cx + 20, cy + 284, "Esc / Enter to close", FG_DIM)
}

func drawToast(win) {
    if gStatus != "" && readUptimeSec() < gStatusUntil {
        chocDrawText(win, CONTENT_X + 12, WIN_H - 38, gStatus, GREEN)
    }
}

func drawFrame(win) {
    chocFillRect(win, 0, 0, WIN_W, WIN_H, colorRGB(30, 30, 46))
    drawSidebar(win)
    drawTopBar(win)
    if gDialog == 1 { drawDialog(win) }
    else if gInspect == 1 { drawInspector(win) }
    else if gView == 0 { drawDashboard(win) }
    else if gView == 1 { drawProcesses(win) }
    else if gView == 2 { drawCPUSched(win) }
    else if (gView == 3 { drawMemSwap(win) }
    else { drawPlaceholder(win, gView) }
    drawToast(win)
}

// ── input ────────────────────────────────────────────────────────────
func clampSel() {
    let mc = matchingCount()
    if mc == 0 { gSel = 0 }
    else if gSel >= mc { gSel = mc - 1 }
    if gSel < 0 { gSel = 0 }
    if gSel < gScroll { gScroll = gSel }
    if gSel >= gScroll + VISIBLE { gScroll = gSel - VISIBLE + 1 }
    if gScroll < 0 { gScroll = 0 }
}

func onKey(kc, mods) {
    if gDialog == 1 {
        if kc == 1 { gDialog = 0 }
        else if kc == 24 || kc == 28 { sigAction(gDialogPid, "TERM"); gDialog = 0 }
        else if kc == 49 { gDialog = 0 }
        emit 0
    }
    if gInspect == 1 {
        if kc == 1 || kc == 28 { gInspect = 0 }
        emit 0
    }
    if kc == 16 || kc == 1 { gQuit = 1 }
    else if kc == 19 { gStatus = ""; refreshSys(); setStatus("refreshed") }
    else if kc == 103 { if gSel > 0 { gSel -= 1 } clampSel() }
    else if kc == 108 { gSel += 1; clampSel() }
    else if kc == 15 { gFilterFocus = 1 - gFilterFocus }
    else if kc == 28 {
        let p = selectedPid()
        if p != "" { gInspect = 1; gInspectPid = p }
    }
    else if kc == 37 {
        let p = selectedPid()
        if p != "" { gDialog = 1; gDialogPid = p }
    }
    else if kc == 31 {
        let p = selectedPid()
        if p != "" { sigAction(p, "STOP") }
    }
    else if kc == 46 {
        let p = selectedPid()
        if p != "" { sigAction(p, "CONT") }
    }
    else if kc >= 2 && kc <= 11 {
        // number keys 1..0 (keycodes 2..11) -> sections 0..9
        let idx = kc - 2
        if kc == 11 { idx = 9 }
        gView = idx
        gSel = 0; gScroll = 0
    }
    else if gFilterFocus == 1 {
        if kc == 14 {
            if len(gFilter) > 0 { gFilter = substring(gFilter, 0, len(gFilter) - 1) }
        }
        else if kc >= 30 && kc <= 52 {
            gFilter = gFilter + fromCharCode(kc + 67)
        }
    }
    emit 0
}

func onPointer(x, y) {
    gMx = x
    gMy = y
    if gDialog == 1 {
        let cx = WIN_W / 2 - 200
        let cy = WIN_H / 2 - 80
        let by = cy + 104
        if rectHit(x, y, cx + 40, by, 60, 26) { sigAction(gDialogPid, "TERM"); gDialog = 0 }
        else if rectHit(x, y, cx + 130, by, 60, 26) { gDialog = 0 }
        emit 0
    }
    if x < SIDEBAR_W && y >= 84 && y < 84 + 12 * 34 {
        let i = 0
        while i < 12 {
            let iy = 84 + i * 34
            if y >= iy - 2 && y < iy + 30 {
                gView = i
                gSel = 0; gScroll = 0
                i = 12
            }
            i += 1
        }
        emit 0
    }
    if gView == 1 && y >= TABLE_Y - 18 && y < TABLE_Y {
        // header click -> sort by column
        let ci = 0
        // columns boundaries
        let bounds = "4,52,252,310,372,434,540"
        let rest = bounds
        while ci < 7 {
            let cx0 = toInt(firstpart(rest, ","))
            rest = afterpart(rest, ",")
            let w = 44
            if ci == 1 { w = 200 }
            else if ci == 2 { w = 58 }
            else if ci == 3 { w = 62 }
            else if ci == 4 { w = 62 }
            else if ci == 5 { w = 106 }
            else if ci == 6 { w = 200 }
            if x >= CONTENT_X + cx0 && x < CONTENT_X + cx0 + w {
                if gSortCol == ci { gSortDir = 0 - gSortDir }
                else { gSortCol = ci; gSortDir = -1 }
                sortRows()
                gSel = 0; gScroll = 0
                ci = 7
            }
            ci += 1
        }
        emit 0
    }
    if gView == 1 && y >= TABLE_Y {
        let disp = 0
        let i = 0
        while i < gRowCount {
            let row = getField(gRows, "p" + i)
            if containsCI(row, gFilter) {
                let rowY = TABLE_Y + (disp - gScroll) * ROW_H
                if disp >= gScroll && disp < gScroll + VISIBLE && y >= rowY - 1 && y < rowY + ROW_H - 1 {
                    gSel = disp
                    clampSel()
                    i = gRowCount
                }
                disp += 1
            }
            i += 1
        }
    }
    emit 0
}

// ── entry ────────────────────────────────────────────────────────────
just run {
    let smoke = 0
    let verify = 0
    let i = 0
    let n = argCount()
    while i < n {
        let a = arg(i)
        if a == "--smoke" { smoke = 1 }
        if a == "--verify" { verify = 1 }
        i += 1
    }

    if smoke == 1 {
        refreshSys()
        gCpuPct = cpuPercent()
        print("sentinel-smoke cpuPct=" + gCpuPct)
        print("sentinel-smoke memUsed=" + gMemUsed + " memTotal=" + gMemTotal + " memPct=" + gMemPct)
        print("sentinel-smoke load=" + gLoad1 + " " + gLoad5 + " " + gLoad15)
        print("sentinel-smoke uptime=" + uptimeStr() + " kernel=" + gKernel)
        print("sentinel-smoke host=" + gHost + " user=" + environ("USER"))
        print("sentinel-smoke cores=" + gNcores + " procs=" + gRowCount)
        let t = 0
        while t < 3 && t < gRowCount {
            let r = getField(gRows, "p" + t)
            print("sentinel-smoke proc=" + nthPipe(r, 0) + " " + nthPipe(r, 1) + " cpu=" + nthPipe(r, 2) + "% mem=" + nthPipe(r, 3) + "MB")
            t += 1
        }
        print("sentinel-smoke ok")
        exit("0")
    }

    let app = chocSharedApp()
    let win = chocWindow(app, "KryptOS Sentinel", WIN_W, WIN_H)
    chocShow(win, app)
    win = chocOnKey(win, funcptr(onKey))

    refreshSys()
    gCpuPct = cpuPercent()

    drawFrame(win)
    win = chocPumpEvents(win)
    win = chocPresent(win)

    if verify == 1 {
        let smack = getField(win, "smack")
        let fails = 0
        let px1 = smackSurfacePixel(smack, 6, 6)
        if px1 != "17,17,27,255" { fails += 1 }
        let px2 = smackSurfacePixel(smack, 400, 500)
        if px2 != "30,30,46,255" { fails += 1 }
        let px3 = smackSurfacePixel(smack, 13, 90)
        if px3 != "203,166,247,255" { fails += 1 }
        let px4 = smackSurfacePixel(smack, 100, 90)
        if px4 != "47,40,70,255" { fails += 1 }
        let px5 = smackSurfacePixel(smack, 400, 22)
        if px5 != "17,17,27,255" { fails += 1 }
        let px6 = smackSurfacePixel(smack, 300, 80)
        if px6 != "17,17,27,255" { fails += 1 }
        if fails == 0 { print("sentinel-verify ok"); exit("0") }
        print("sentinel-verify failed=" + fails)
        exit("1")
    }

    while gQuit == 0 {
        win = chocPumpEvents(win)
        let sec = readUptimeSec()
        if sec != gUptimeS { refreshSys(); gCpuPct = cpuPercent() }
        drawFrame(win)
        win = chocPresent(win)
    }

    chocClear(win, BG)
    print("sentinel exit ok")
}
