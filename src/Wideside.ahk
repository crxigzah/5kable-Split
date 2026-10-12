; Wideside - Easy Arrange style window zones for big / ultrawide monitors
; Built for the MSI MAG C42CQR E2 but works on any monitor (it reads the
; resolution and taskbar position from Windows at runtime).
;
; Requires AutoHotkey v2 to run from source. build.cmd compiles it to an .exe
; and wraps it in an installer.

;@Ahk2Exe-SetName Wideside
;@Ahk2Exe-SetProductName Wideside
;@Ahk2Exe-SetDescription Wideside
;@Ahk2Exe-SetVersion 1.7.0
;@Ahk2Exe-SetCompanyName Wideside
;@Ahk2Exe-SetCopyright Copyright 2026 Wideside
;@Ahk2Exe-SetOrigFilename Wideside.exe
;@Ahk2Exe-SetMainIcon app.ico

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Work in real pixels on every monitor (per-monitor DPI aware v2) so scaling
; like 125% doesn't throw the zone maths off.
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
CoordMode "Mouse", "Screen"

global AppName := "Wideside"
global AppVersion := "1.7.0"
global AppUrl := "https://crxigzah.github.io/wideside/"

; Settings live in %AppData% so it works when installed to Program Files.
global DataDir := A_AppData "\Wideside"
global IniFile := DataDir "\settings.ini"
global LogoFile := DataDir "\logo.png"

; Wideside palette
global C_Bg := "101114", C_Card := "1C1E25", C_Accent := "FF7A3D"
global C_Text := "F4F4F5", C_Muted := "9A9DA8"
global C_Border := "2A2D35", C_Zone := "3A3D48"

; Zones are [x, y, width, height] as fractions of the screen's work area.
global BuiltInLayouts := [
    {name: "Two halves (50/50)", short: "50 / 50", zones: [[0, 0, 1/2, 1], [1/2, 0, 1/2, 1]]},
    {name: "Wide left (60/40)", short: "60 / 40", zones: [[0, 0, 0.6, 1], [0.6, 0, 0.4, 1]]},
    {name: "Wide right (40/60)", short: "40 / 60", zones: [[0, 0, 0.4, 1], [0.4, 0, 0.6, 1]]},
    {name: "Three columns", short: "Thirds", zones: [[0, 0, 1/3, 1], [1/3, 0, 1/3, 1], [2/3, 0, 1/3, 1]]},
    {name: "Focus centre (25/50/25)", short: "Focus", zones: [[0, 0, 0.25, 1], [0.25, 0, 0.5, 1], [0.75, 0, 0.25, 1]]},
    {name: "Left half + right stacked", short: "Left + stack", zones: [[0, 0, 1/2, 1], [1/2, 0, 1/2, 1/2], [1/2, 1/2, 1/2, 1/2]]},
    {name: "Four quarters", short: "Quarters", zones: [[0, 0, 1/2, 1/2], [1/2, 0, 1/2, 1/2], [0, 1/2, 1/2, 1/2], [1/2, 1/2, 1/2, 1/2]]}
]
global GapOptions := [0, 4, 8, 12, 16, 24]

global Layouts := []
global LayoutIndex := 1
global Gap := 0
global RequireShift := false
global PauseWinSnap := true
global RememberApps := true
global CheckUpdates := true
global Paused := false
global LatestVersion := ""      ; set when a newer release is found
global OrigWinSnap := -1        ; Windows Snap setting from before we paused it
global ZoneOf := Map()          ; hwnd -> {idx, x, y, w, h} of the last snap

global OverlayCache := Map(), OverlayMon := 0, OverlayHi := -1
global HotFill := 0, HotFrame := 0, HotLines := []
global Drag := 0                ; drag in progress: {hwnd, sx, sy, shown, sel, mon, viaMouse}
; How close to the line between two zones counts as "on the line" (spans both)
global SpanPx := Round(40 * A_ScreenDPI / 96)
global WatchHwnd := 0, WatchX := 0, WatchY := 0, LastShift := 0
global SettingsGui := 0, AboutGui := 0

; ---------------------------------------------------------------- startup

DirCreate DataDir
FileInstall "logo.png", LogoFile, 1
if !A_IsCompiled && FileExist(A_ScriptDir "\app.ico")
    TraySetIcon A_ScriptDir "\app.ico"

FirstRun := !FileExist(IniFile)
if FirstRun
    WriteDefaultSettings()

LoadSettings()
BuildTrayMenu()

Loop 9
    Hotkey "#!" A_Index, SnapActiveHotkey

; Watch for any window starting / finishing a move (EVENT_SYSTEM_MOVESIZESTART/END)
global MoveSizeCB := CallbackCreate(OnMoveSize, , 7)
global MoveSizeHook := DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B
    , "ptr", 0, "ptr", MoveSizeCB, "uint", 0, "uint", 0, "uint", 0, "ptr")

ApplyWinSnap()
OnExit RestoreWinSnap

; Hear about new windows, so apps can reopen in their remembered zone
DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
OnMessage DllCall("RegisterWindowMessage", "str", "SHELLHOOK", "uint"), OnShellMessage

if CheckUpdates
    SetTimer CheckForUpdates, -8000
OnMessage 0x7E, (*) => InvalidateOverlays()   ; WM_DISPLAYCHANGE: resolution or monitors changed

if FirstRun
    ShowAbout(true)
else
    TrayTip "Running in the system tray`nLayout: " Layouts[LayoutIndex].name, AppName

#!Left::  CycleZone(-1)
#!Right:: CycleZone(1)
#!Up::    MaximiseActive()
#!l::     NextLayout()
#!z::     PreviewZones()
#!a::     ArrangeAll()
#!p::     TogglePause()

; Track the left mouse button so tabs pulled off a browser's tab bar can
; snap too (see WatchMouseDrag). ~ lets the click through as normal.
~LButton:: {
    global WatchHwnd
    WatchHwnd := 0
    SetTimer WatchMouseDrag, 30
}

~LButton Up:: {
    SetTimer WatchMouseDrag, 0
    ; Browsers finish placing a torn-off tab's window just after the button comes up
    if Drag && Drag.viaMouse
        EndDrag(80)
}

; ---------------------------------------------------------------- settings

WriteDefaultSettings() {
    FileAppend "
    (
[Settings]
; Layout number (built-in layouts first, then your custom ones)
Layout=1
; Gap in pixels around and between windows
Gap=0
; 1 = only show zones when Shift is held while dragging, 0 = every drag
RequireShift=0
; 1 = turn off Windows' own Snap while Wideside is running
PauseWindowsSnap=1
; 1 = apps reopen in the zone they were last snapped to
RememberAppZones=1
; 1 = check GitHub for new versions every few hours
CheckForUpdates=1
SettingsVersion=2

[CustomLayouts]
; Add your own layouts here, then right-click the tray icon > Reload.
; Name=zone | zone | zone ...
; Each zone is x,y,width,height as fractions of the screen (0 to 1).
; Remove the ; at the start of a line to turn an example on.
;Coding=0,0,0.65,1 | 0.65,0,0.35,0.5 | 0.65,0.5,0.35,0.5
;Halves + chat=0,0,0.4,1 | 0.4,0,0.4,1 | 0.8,0,0.2,1
    )", IniFile, "UTF-16"
}

LoadSettings() {
    global Layouts, LayoutIndex, Gap, RequireShift, PauseWinSnap, RememberApps, CheckUpdates
    Layouts := BuiltInLayouts.Clone()

    try {
        section := IniRead(IniFile, "CustomLayouts")
        Loop Parse section, "`n", "`r" {
            line := Trim(A_LoopField)
            if line = "" || SubStr(line, 1, 1) = ";" || !(p := InStr(line, "="))
                continue
            zones := ParseZones(SubStr(line, p + 1))
            if zones.Length
                Layouts.Push({name: Trim(SubStr(line, 1, p - 1)), zones: zones})
        }
    }

    LayoutIndex := ReadInt("Layout", 1)
    if LayoutIndex < 1 || LayoutIndex > Layouts.Length
        LayoutIndex := 1
    Gap := Max(0, ReadInt("Gap", 0))
    RequireShift := ReadInt("RequireShift", 0) != 0
    PauseWinSnap := ReadInt("PauseWindowsSnap", 1) != 0
    RememberApps := ReadInt("RememberAppZones", 1) != 0
    CheckUpdates := ReadInt("CheckForUpdates", 1) != 0
    ; Settings saved before 1.4 switch to Easy Arrange behaviour: zones on
    ; every drag and no gap
    if ReadInt("SettingsVersion", 1) < 2 {
        RequireShift := false, Gap := 0
        SaveSettings()
    }
}

ReadInt(key, default) {
    try return Integer(IniRead(IniFile, "Settings", key, default))
    return default
}

SaveSettings() {
    IniWrite LayoutIndex, IniFile, "Settings", "Layout"
    IniWrite Gap, IniFile, "Settings", "Gap"
    IniWrite RequireShift ? 1 : 0, IniFile, "Settings", "RequireShift"
    IniWrite PauseWinSnap ? 1 : 0, IniFile, "Settings", "PauseWindowsSnap"
    IniWrite RememberApps ? 1 : 0, IniFile, "Settings", "RememberAppZones"
    IniWrite CheckUpdates ? 1 : 0, IniFile, "Settings", "CheckForUpdates"
    IniWrite 2, IniFile, "Settings", "SettingsVersion"
}

; "0,0,0.5,1 | 0.5,0,0.5,1" -> [[0,0,0.5,1], [0.5,0,0.5,1]]
ParseZones(str) {
    zones := []
    for part in StrSplit(str, "|") {
        nums := StrSplit(Trim(part), ",", " `t")
        if nums.Length != 4
            return []
        z := []
        for n in nums {
            if !IsNumber(n)
                return []
            n := Number(n)
            if n < 0 || n > 1
                return []
            z.Push(n)
        }
        zones.Push(z)
    }
    return zones
}

CurrentZones() => Layouts[LayoutIndex].zones

; ---------------------------------------------------------------- geometry

MonitorFromPoint(x, y) {
    Loop MonitorGetCount() {
        MonitorGet A_Index, &L, &T, &R, &B
        if x >= L && x < R && y >= T && y < B
            return A_Index
    }
    return MonitorGetPrimary()
}

MonitorOfWindow(hwnd) {
    WinGetPos &x, &y, &w, &h, hwnd
    return MonitorFromPoint(x + w // 2, y + h // 2)
}

; Pixel rect for a zone on a monitor, with an even gap around and between zones.
ZoneRect(mon, z) {
    MonitorGetWorkArea mon, &L, &T, &R, &B
    hg := Gap / 2
    aw := (R - L) - Gap, ah := (B - T) - Gap
    x1 := Round(L + hg + z[1] * aw + hg)
    y1 := Round(T + hg + z[2] * ah + hg)
    x2 := Round(L + hg + (z[1] + z[3]) * aw - hg)
    y2 := Round(T + hg + (z[2] + z[4]) * ah - hg)
    return {x: x1, y: y1, w: x2 - x1, h: y2 - y1}
}

; Zones under the point. Near the line between zones the neighbouring zones
; count too, so dropping on a line spans them (and near a corner where four
; zones meet, all four).
ZonesAtPoint(mon, x, y) {
    MonitorGetWorkArea mon, &L, &T, &R, &B
    W := R - L, H := B - T, sel := []
    for i, z in CurrentZones() {
        zx1 := L + z[1] * W, zy1 := T + z[2] * H
        zx2 := zx1 + z[3] * W, zy2 := zy1 + z[4] * H
        dx := Max(zx1 - x, 0, x - zx2), dy := Max(zy1 - y, 0, y - zy2)
        if dx <= SpanPx && dy <= SpanPx
            sel.Push(i)
    }
    return sel
}

; Bounding rect of several zones, gaps included, for spanning
UnionRect(mon, sel) {
    zones := CurrentZones()
    for i in sel {
        r := ZoneRect(mon, zones[i])
        if A_Index = 1
            x1 := r.x, y1 := r.y, x2 := r.x + r.w, y2 := r.y + r.h
        else
            x1 := Min(x1, r.x), y1 := Min(y1, r.y), x2 := Max(x2, r.x + r.w), y2 := Max(y2, r.y + r.h)
    }
    return {x: x1, y: y1, w: x2 - x1, h: y2 - y1}
}

JoinZones(sel) {
    out := ""
    for i in sel
        out .= (A_Index > 1 ? "," : "") i
    return out
}

ZoneAtPoint(mon, x, y) {
    MonitorGetWorkArea mon, &L, &T, &R, &B
    fx := (x - L) / (R - L), fy := (y - T) / (B - T)
    for i, z in CurrentZones()
        if fx >= z[1] && fx < z[1] + z[3] && fy >= z[2] && fy < z[2] + z[4]
            return i
    return 0
}

; ---------------------------------------------------------------- moving windows

IsSnappable(hwnd) {
    if !hwnd || !WinExist(hwnd)
        return false
    cls := WinGetClass(hwnd)
    if cls ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
        return false
    ; Don't snap our own windows or the zone overlays
    return WinGetPID(hwnd) != ProcessExist()
}

ActiveTarget() {
    hwnd := WinExist("A")
    return IsSnappable(hwnd) ? hwnd : 0
}

; Windows 10/11 windows have an invisible resize border (~7px) that WinMove
; includes, so measure it with DWM and compensate to make zones line up exactly.
MoveWindowTo(hwnd, r) {
    if WinGetMinMax(hwnd) != 0
        WinRestore hwnd
    WinGetPos &wx, &wy, &ww, &wh, hwnd
    bl := bt := br := bb := 0
    rect := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", rect, "uint", 16) = 0 {
        bl := NumGet(rect, 0, "int") - wx
        bt := NumGet(rect, 4, "int") - wy
        br := (wx + ww) - NumGet(rect, 8, "int")
        bb := (wy + wh) - NumGet(rect, 12, "int")
    }
    nx := r.x - bl, ny := r.y - bt, nw := r.w + bl + br, nh := r.h + bt + bb
    WinMove nx, ny, nw, nh, hwnd
    ; Second pass covers apps that rescale themselves after crossing to a
    ; monitor with different DPI scaling.
    WinGetPos &ax, &ay, &aw, &ah, hwnd
    if ax != nx || ay != ny || aw != nw || ah != nh
        WinMove nx, ny, nw, nh, hwnd
}

SnapToZone(hwnd, mon, idx) => SnapToZones(hwnd, mon, [idx])

; Snap to one zone, or several spanned together
SnapToZones(hwnd, mon, sel) {
    n := CurrentZones().Length
    if !IsSnappable(hwnd) || !sel.Length
        return
    for i in sel
        if i < 1 || i > n
            return
    try {
        MoveWindowTo(hwnd, UnionRect(mon, sel))
        WinGetPos &x, &y, &w, &h, hwnd
        ZoneOf[hwnd] := {idx: sel[1], x: x, y: y, w: w, h: h}
        RememberZone(hwnd, mon, sel)
    }
}

; A normal, visible app window: not a dialog, tool window, minimised,
; hidden or a background (cloaked) store app
IsAppWindow(hwnd) {
    if !IsSnappable(hwnd) || WinGetMinMax(hwnd) = -1 || WinGetTitle(hwnd) = ""
        return false
    if !(WinGetStyle(hwnd) & 0x10000000) || (WinGetExStyle(hwnd) & 0x80)
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")   ; owned window, e.g. a dialog
        return false
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "int*", &cloaked, "uint", 4)
    return !cloaked
}

; Fill the zones with the open windows on this monitor, most recently used first
ArrangeAll(*) {
    if hwnd := ActiveTarget()
        mon := MonitorOfWindow(hwnd)
    else {
        MouseGetPos &mx, &my
        mon := MonitorFromPoint(mx, my)
    }
    n := CurrentZones().Length, i := 0
    for win in WinGetList() {
        if i >= n
            break
        try {
            if !IsAppWindow(win) || MonitorOfWindow(win) != mon
                continue
        } catch
            continue
        SnapToZone(win, mon, ++i)
    }
    ToolTip i ? "Arranged " i " window" (i = 1 ? "" : "s") : "No windows to arrange"
    SetTimer () => ToolTip(), -1200
}

; ---------------------------------------------------------------- remembered app zones

RememberZone(hwnd, mon, sel) {
    if !RememberApps
        return
    try IniWrite LayoutIndex "|" mon "|" JoinZones(sel), IniFile, "AppZones", WinGetProcessName(hwnd)
}

OnShellMessage(wParam, lParam, *) {
    if wParam = 1 && RememberApps && !Paused   ; HSHELL_WINDOWCREATED
        SetTimer () => PlaceNewWindow(lParam), -400
}

; Put a newly opened app back in the zone it was last snapped to. Only when
; it's the app's only window (so extra windows, tabs pulled off and dialogs
; are left alone), nothing is being dragged, and the layout hasn't changed.
PlaceNewWindow(hwnd) {
    if Drag || GetKeyState("LButton", "P")
        return
    try {
        if !IsAppWindow(hwnd)
            return
        exe := WinGetProcessName(hwnd)
        parts := StrSplit(IniRead(IniFile, "AppZones", exe, ""), "|")
        if parts.Length != 3 || Integer(parts[1]) != LayoutIndex
            return
        mon := Integer(parts[2])
        if mon < 1 || mon > MonitorGetCount()
            return
        count := 0
        for w in WinGetList("ahk_exe " exe)
            if IsAppWindow(w)
                count++
        if count > 1
            return
        sel := []
        for z in StrSplit(parts[3], ",")
            sel.Push(Integer(z))
        SnapToZones(hwnd, mon, sel)
    }
}

; Zone the window is currently sitting in, or 0 if it's been moved since we snapped it.
CurrentZoneOf(hwnd) {
    if !ZoneOf.Has(hwnd)
        return 0
    s := ZoneOf[hwnd]
    WinGetPos &x, &y, &w, &h, hwnd
    return (x = s.x && y = s.y && w = s.w && h = s.h && WinGetMinMax(hwnd) = 0) ? s.idx : 0
}

SnapActive(idx) {
    if hwnd := ActiveTarget()
        SnapToZone(hwnd, MonitorOfWindow(hwnd), idx)
}

SnapActiveHotkey(thisHotkey) => SnapActive(Integer(SubStr(thisHotkey, 3)))

CycleZone(dir) {
    if !(hwnd := ActiveTarget())
        return
    n := CurrentZones().Length
    cur := CurrentZoneOf(hwnd)
    next := cur ? Max(1, Min(n, cur + dir)) : (dir > 0 ? 1 : n)
    SnapToZone(hwnd, MonitorOfWindow(hwnd), next)
}

MaximiseActive() {
    if hwnd := ActiveTarget()
        WinMaximize hwnd
}

; ---------------------------------------------------------------- drag to snap

; A drag starts from Windows' own move event (title-bar drags) or from
; WatchMouseDrag (browser tabs pulled off the tab bar). Both end in EndDrag.
OnMoveSize(hHook, event, hwnd, idObject, idChild, idThread, time) {
    if idObject != 0
        return
    if event = 0x000A {
        ; The same event fires when resizing; the sizing cursor gives that away
        if !Paused && IsSnappable(hwnd) && !(A_Cursor ~= "^Size(NS|WE|NWSE|NESW)$")
            BeginDrag(hwnd, false)
    } else if event = 0x000B && Drag && Drag.hwnd = hwnd && !Drag.viaMouse
        EndDrag(10)
}

BeginDrag(hwnd, viaMouse) {
    global Drag
    MouseGetPos &x, &y
    Drag := {hwnd: hwnd, sx: x, sy: y, shown: false, sel: [], mon: 0, viaMouse: viaMouse}
    SetTimer DragTick, 15
}

EndDrag(delay) {
    global Drag
    SetTimer DragTick, 0
    if !Drag
        return
    hwnd := Drag.hwnd, sel := Drag.sel, mon := Drag.mon
    Drag := 0
    HideOverlay()
    if sel.Length && !GetKeyState("Ctrl", "P")
        SetTimer () => SnapToZones(hwnd, mon, sel), -delay
}

DragTick() {
    global Drag, LastShift
    if !Drag
        return
    if !WinExist(Drag.hwnd) {
        SetTimer DragTick, 0
        Drag := 0
        HideOverlay()
        return
    }
    if GetKeyState("Shift", "P")
        LastShift := A_TickCount
    MouseGetPos &mx, &my
    ; Only show zones once the window is really being dragged, not on a
    ; click of the title bar
    if !Drag.shown && Abs(mx - Drag.sx) + Abs(my - Drag.sy) < 12
        return
    ; Ctrl = place freely. In Shift mode, a short grace period means letting
    ; go of Shift a moment before the mouse button still snaps.
    if GetKeyState("Ctrl", "P") || (RequireShift && A_TickCount - LastShift > 250) {
        Drag.sel := []
        HideOverlay()
        return
    }
    Drag.shown := true
    mon := MonitorFromPoint(mx, my)
    sel := ZonesAtPoint(mon, mx, my)
    ShowOverlay(mon, sel)
    Drag.sel := sel, Drag.mon := mon
}

; Chrome, Edge, Opera and other Chromium browsers move a torn-off tab's new
; window themselves, so no move event fires. Spot those by watching the
; active browser window move while the mouse button is held.
WatchMouseDrag() {
    global WatchHwnd, WatchX, WatchY
    if Drag || Paused
        return
    win := WinExist("A")
    try {
        if !IsSnappable(win) || WinGetClass(win) != "Chrome_WidgetWin_1"
            return
        WinGetPos &x, &y, , , win
    } catch
        return
    if win != WatchHwnd {      ; new active window (e.g. the torn-off tab): start watching it
        WatchHwnd := win, WatchX := x, WatchY := y
        return
    }
    if x != WatchX || y != WatchY
        BeginDrag(win, true)
}

; ---------------------------------------------------------------- overlay

; Easy Arrange style: every zone is an orange outline with a number tag, and
; the zone under the mouse gets a thick outline and a light tint. The windows
; are built once per monitor and then just shown and hidden, so dragging
; stays smooth.
ShowOverlay(mon, sel) {
    global OverlayMon, OverlayHi
    EnsureHotWindows()
    if mon != OverlayMon {
        HideOverlay()
        if !OverlayCache.Has(mon)
            OverlayCache[mon] := BuildOverlay(mon)
        for f in OverlayCache[mon].frames
            f.Show("NA")
        OverlayMon := mon, OverlayHi := -1
    }
    key := JoinZones(sel)
    if key == OverlayHi
        return
    OverlayHi := key
    if !sel.Length {
        HotFill.Hide(), HotFrame.Hide()
        return
    }
    r := UnionRect(mon, sel), t := 6
    HotLines[1].Move(0, 0, r.w, t)
    HotLines[2].Move(0, r.h - t, r.w, t)
    HotLines[3].Move(0, 0, t, r.h)
    HotLines[4].Move(r.w - t, 0, t, r.h)
    HotFill.Show("NA x" r.x " y" r.y " w" r.w " h" r.h)
    HotFrame.Show("NA x" r.x " y" r.y " w" r.w " h" r.h)
}

BuildOverlay(mon) {
    DetectHiddenWindows true
    frames := [], rects := []
    for i, z in CurrentZones() {
        r := ZoneRect(mon, z), t := 2
        ; The key colour is made fully transparent, so only the outline and
        ; number tag are drawn
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
        g.BackColor := "010203"
        g.AddText("x0 y0 w" r.w " h" t " Background" C_Accent)
        g.AddText("x0 y" (r.h - t) " w" r.w " h" t " Background" C_Accent)
        g.AddText("x0 y0 w" t " h" r.h " Background" C_Accent)
        g.AddText("x" (r.w - t) " y0 w" t " h" r.h " Background" C_Accent)
        g.SetFont("s11 bold c" C_Bg, "Segoe UI")
        g.AddText("x14 y14 w30 h30 Center +0x200 Background" C_Accent, i)
        g.Show("Hide x" r.x " y" r.y " w" r.w " h" r.h)
        WinSetTransColor "010203", g
        frames.Push(g), rects.Push(r)
    }
    return {frames: frames, rects: rects}
}

; The highlight for the zone under the mouse: a tinted fill plus a thick
; outline, moved from zone to zone rather than redrawn
EnsureHotWindows() {
    global HotFill, HotFrame, HotLines
    if HotFill
        return
    DetectHiddenWindows true
    HotFill := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    HotFill.BackColor := C_Accent
    HotFill.Show("Hide x0 y0 w10 h10")
    WinSetTransparent 45, HotFill
    HotFrame := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    HotFrame.BackColor := "010203"
    HotLines := []
    Loop 4
        HotLines.Push(HotFrame.AddText("x0 y0 w1 h1 Background" C_Accent))
    HotFrame.Show("Hide x0 y0 w10 h10")
    WinSetTransColor "010203", HotFrame
}

HideOverlay(*) {
    global OverlayMon, OverlayHi
    if !OverlayMon
        return
    for f in OverlayCache[OverlayMon].frames
        f.Hide()
    HotFill.Hide(), HotFrame.Hide()
    OverlayMon := 0, OverlayHi := -1
}

; Throw away the cached zone windows after the layout, gap or displays change
InvalidateOverlays() {
    HideOverlay()
    for mon, o in OverlayCache
        for f in o.frames
            f.Destroy()
    OverlayCache.Clear()
}

PreviewZones(*) {
    MouseGetPos &mx, &my
    HideOverlay()
    ShowOverlay(MonitorFromPoint(mx, my), [])
    SetTimer HideOverlay, -1500
}

; ---------------------------------------------------------------- applying changes

SetLayout(i, *) {
    global LayoutIndex
    LayoutIndex := i
    ZoneOf.Clear()
    InvalidateOverlays()
    SaveSettings()
    BuildTrayMenu()
    RefreshSettings()
    PreviewZones()
}

NextLayout() {
    SetLayout(Mod(LayoutIndex, Layouts.Length) + 1)
    ToolTip "Layout: " Layouts[LayoutIndex].name
    SetTimer () => ToolTip(), -1500
}

SetGap(g) {
    global Gap
    Gap := g
    ZoneOf.Clear()
    InvalidateOverlays()
    SaveSettings()
    PreviewZones()
}

SetRequireShift(on) {
    global RequireShift
    RequireShift := on
    SaveSettings()
}

; Windows' own Snap (edge snapping and the snap layout bar) competes with the
; zones, so it can be paused while Wideside runs. Only the live setting is
; changed, not the saved one, so it's back after signing in again even if
; Wideside were to crash.
ApplyWinSnap() {
    global OrigWinSnap
    if OrigWinSnap = -1 {
        v := 0
        DllCall("SystemParametersInfo", "uint", 0x0082, "uint", 0, "int*", &v, "uint", 0)
        OrigWinSnap := v
    }
    ; While Wideside is paused, Windows Snap is allowed back
    DllCall("SystemParametersInfo", "uint", 0x0083, "uint", (PauseWinSnap && !Paused) ? 0 : OrigWinSnap, "ptr", 0, "uint", 2)
}

RestoreWinSnap(*) {
    if OrigWinSnap != -1
        DllCall("SystemParametersInfo", "uint", 0x0083, "uint", OrigWinSnap, "ptr", 0, "uint", 2)
}

SetPauseWinSnap(on) {
    global PauseWinSnap
    PauseWinSnap := on
    SaveSettings()
    ApplyWinSnap()
}

TogglePause(*) {
    global Paused
    Paused := !Paused
    ApplyWinSnap()
    BuildTrayMenu()
    ToolTip Paused ? "Wideside paused" : "Wideside on"
    SetTimer () => ToolTip(), -1200
}

SetRememberApps(on) {
    global RememberApps
    RememberApps := on
    SaveSettings()
}

SetCheckUpdates(on) {
    global CheckUpdates
    CheckUpdates := on
    SaveSettings()
    if on
        SetTimer CheckForUpdates, -1000
}

; ---------------------------------------------------------------- updates

; Ask GitHub for the latest release without blocking the script; PollUpdate
; picks up the answer. Repeats every 6 hours while the setting is on.
global UpdateReq := 0, UpdateManual := false

CheckForUpdates(manual := false, *) {
    global UpdateReq, UpdateManual
    if UpdateReq
        return
    UpdateManual := manual
    try {
        UpdateReq := ComObject("WinHttp.WinHttpRequest.5.1")
        UpdateReq.Open("GET", "https://api.github.com/repos/crxigzah/wideside/releases/latest", true)
        UpdateReq.SetRequestHeader("User-Agent", "Wideside/" AppVersion)
        UpdateReq.Send()
        SetTimer PollUpdate, 500
    } catch
        UpdateReq := 0
    if CheckUpdates
        SetTimer CheckForUpdates, -6 * 60 * 60 * 1000
}

PollUpdate() {
    global UpdateReq, LatestVersion
    static waited := 0
    found := false
    try {
        if !UpdateReq.WaitForResponse(0) {
            if (waited += 500) < 20000
                return
            throw Error("No response")
        }
        if UpdateReq.Status = 200 && RegExMatch(UpdateReq.ResponseText, '"tag_name"\s*:\s*"v?([\d.]+)"', &m)
            && VerCompare(m[1], AppVersion) > 0 {
            found := true
            if m[1] != LatestVersion {
                LatestVersion := m[1]
                BuildTrayMenu()
                TrayTip "Version " LatestVersion " is available. Click the tray icon's Update option to install it.", AppName
            }
        }
    }
    SetTimer PollUpdate, 0
    UpdateReq := 0, waited := 0
    if UpdateManual && !found
        MsgBox "You're on the latest version (" AppVersion ").", AppName, "Iconi"
}

; Download the new installer and run it. It closes this copy, upgrades in
; place and offers to relaunch.
InstallUpdate(*) {
    file := A_Temp "\Wideside-Setup.exe"
    try {
        ToolTip "Downloading Wideside " LatestVersion "..."
        Download "https://github.com/crxigzah/wideside/releases/latest/download/Wideside-Setup.exe", file
        ToolTip()
        Run '"' file '"'
    } catch {
        ToolTip()
        Run "https://github.com/crxigzah/wideside/releases/latest"
    }
}

; The guide ships next to the exe (installer and portable zip); fall back to
; the website copy when running from source
OpenGuide(*) {
    guideFile := A_ScriptDir "\Wideside Guide.html"
    Run FileExist(guideFile) ? '"' guideFile '"' : AppUrl "guide.html"
}

StartupLink() => A_Startup "\" AppName ".lnk"

SetStartup(on) {
    if on && !FileExist(StartupLink())
        FileCreateShortcut A_ScriptFullPath, StartupLink(), A_ScriptDir
    else if !on && FileExist(StartupLink())
        FileDelete StartupLink()
}

EditCustomLayouts(*) {
    Run 'notepad.exe "' IniFile '"'
}

; ---------------------------------------------------------------- branded windows

; Dark Wideside-styled window with a dark title bar on Windows 10/11.
NewBrandedGui(title) {
    g := Gui("-MinimizeBox -MaximizeBox", title)
    g.BackColor := C_Bg
    g.MarginX := 24, g.MarginY := 20
    g.SetFont("s10 c" C_Text, "Segoe UI")
    hwnd := g.Hwnd
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 20, "int*", 1, "uint", 4)      ; dark mode
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 35, "uint*", 0x141110, "uint", 4) ; caption #101114
    return g
}

AddHeader(g, subtitle, w) {
    if FileExist(LogoFile)
        g.AddPicture("x24 y20 w56 h56", LogoFile)
    g.SetFont("s18 bold c" C_Text)
    g.AddText("x96 y22 BackgroundTrans", "Wideside")
    g.SetFont("s9 norm c" C_Muted)
    g.AddText("x96 y56 w" (w - 96) " BackgroundTrans", subtitle)
    g.AddText("x24 y92 w" (w - 24) " h1 Background" C_Card)
    g.SetFont("s10 norm c" C_Text)
}

; Flat accent-coloured button (normal buttons can't be recoloured)
AddButton(g, opts, label, callback, primary := true) {
    g.SetFont("s10 bold c" (primary ? C_Bg : C_Text))
    b := g.AddText(opts " h34 Center +0x200 Background" (primary ? C_Accent : C_Card), label)
    b.OnEvent("Click", callback)
    g.SetFont("s10 norm c" C_Text)
    return b
}

; Checkbox with a separate label, because themed checkboxes ignore text colour
AddToggle(g, y, label, checked, callback) {
    cb := g.AddCheckbox("x24 y" y " w16 h20 Checked" (checked ? 1 : 0))
    t := g.AddText("x46 y" y " h20 +0x200", label)
    cb.OnEvent("Click", (c, *) => callback(c.Value))
    t.OnEvent("Click", (*) => (cb.Value := !cb.Value, callback(cb.Value)))
    return cb
}

DarkControl(ctrl) => DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.Hwnd, "str", "DarkMode_CFD", "ptr", 0)

ShowAbout(welcome := false, *) {
    global AboutGui
    if AboutGui {
        AboutGui.Show()
        return
    }
    W := 440
    g := NewBrandedGui(welcome ? "Welcome to " AppName : "About " AppName)
    AddHeader(g, "Version " AppVersion "  |  Window zones for big monitors", W)

    y := 108
    if welcome {
        g.SetFont("s10 c" C_Text)
        g.AddText("x24 y" y " w" (W - 24), "Wideside is running in your system tray (bottom right, next to the clock). Drag any window and drop it on a zone.")
        y += 60
    }

    keys := [
        ["Drag a window",      "Show zones, drop to snap"],
        ["Drop on a line",     "Span both zones"],
        ["Ctrl + drag",        "Move freely, no snapping"],
        ["Win+Alt+Left/Right", "Previous / next zone"],
        ["Win+Alt+1 to 9",     "Snap to zone number"],
        ["Win+Alt+Up",         "Maximise across the screen"],
        ["Win+Alt+A",          "Arrange all windows"],
        ["Win+Alt+L",          "Next layout"],
        ["Win+Alt+Z",          "Show zones"],
        ["Win+Alt+P",          "Pause / resume snapping"]
    ]
    for k in keys {
        g.SetFont("s10 bold c" C_Accent)
        g.AddText("x24 y" y " w170", k[1])
        g.SetFont("s10 norm c" C_Text)
        g.AddText("x200 y" y " w" (W - 200), k[2])
        y += 26
    }

    y += 14
    g.SetFont("s9 c" C_Muted)
    link := g.AddText("x24 y" (y + 8) " w60", "Website")
    link.OnEvent("Click", (*) => Run(AppUrl))
    guide := g.AddText("x+16 yp w60", "Guide")
    guide.OnEvent("Click", OpenGuide)
    AddButton(g, "x" (W - 236) " y" y " w120", "Settings", (*) => (CloseAbout(), ShowSettings()), false)
    AddButton(g, "x" (W - 104) " y" y " w120", welcome ? "Got it" : "Close", CloseAbout)

    g.OnEvent("Close", CloseAbout)
    g.OnEvent("Escape", CloseAbout)
    AboutGui := g
    g.Show("w" (W + 24))
}

CloseAbout(*) {
    global AboutGui
    if AboutGui
        AboutGui.Destroy()
    AboutGui := 0
}

; Settings window: layouts as clickable diagrams, gap as pills, and the
; options as switches. Native controls are square and flat, so these are
; drawn from plain text controls clipped to rounded shapes.
global SetTiles := [], SetGapPills := []

; Round a control's corners (radius in DIPs)
RoundCtrl(ctrl, radius) {
    rc := Buffer(16)
    DllCall("GetWindowRect", "ptr", ctrl.Hwnd, "ptr", rc)
    w := NumGet(rc, 8, "int") - NumGet(rc, 0, "int"), h := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
    r := Round(radius * A_ScreenDPI / 96) * 2
    rgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", w + 1, "int", h + 1, "int", r, "int", r, "ptr")
    DllCall("SetWindowRgn", "ptr", ctrl.Hwnd, "ptr", rgn, "int", true)
}

; Controls that sit underneath others are created last with WS_CLIPSIBLINGS
; (+0x4000000): the first-created control is on top, and clipping stops a
; background repainting over what sits on it.
SectionLabel(g, y, text) {
    g.SetFont("s8 bold c" C_Muted)
    g.AddText("x28 y" y " BackgroundTrans", text)
}

AddLayoutTile(g, x, y, w, h, layout, idx) {
    click := (*) => SetLayout(idx)
    dx := x + 12, dy := y + 12, dw := w - 24, dh := Round(dw * 9 / 21)
    zones := []
    for z in layout.zones {
        zx := dx + Round(z[1] * dw) + 1, zy := dy + Round(z[2] * dh) + 1
        zw := Round(z[3] * dw) - 2, zh := Round(z[4] * dh) - 2
        zc := g.AddText("x" zx " y" zy " w" zw " h" zh " Background" C_Zone)
        RoundCtrl(zc, 3)
        zones.Push(zc)
    }
    g.SetFont("s9 norm c" C_Muted)
    name := g.AddText("x" (x + 10) " y" (dy + dh + 9) " w" (w - 20) " h18 Center Background" C_Card
        , layout.HasOwnProp("short") ? layout.short : layout.name)
    card := g.AddText("x" (x + 2) " y" (y + 2) " w" (w - 4) " h" (h - 4) " +0x4000000 Background" C_Card)
    edge := g.AddText("x" x " y" y " w" w " h" h " +0x4000000 Background" C_Border)
    RoundCtrl(card, 9), RoundCtrl(edge, 11)
    for c in [edge, card, name]
        c.OnEvent("Click", click)
    for c in zones
        c.OnEvent("Click", click)
    return {edge: edge, card: card, zones: zones, name: name}
}

StyleTile(t, on) {
    t.edge.Opt("+Background" (on ? C_Accent : C_Border))
    for z in t.zones
        z.Opt("+Background" (on ? C_Accent : C_Zone))
    t.name.SetFont((on ? "bold c" C_Text : "norm c" C_Muted))
    t.edge.Redraw(), t.card.Redraw()
    for z in t.zones
        z.Redraw()
    t.name.Redraw()
}

AddSwitch(g, x, y, on, callback) {
    knob := g.AddText("x" (x + (on ? 21 : 3)) " y" (y + 3) " w16 h16 Background" C_Text)
    track := g.AddText("x" x " y" y " w40 h22 +0x4000000 Background" (on ? C_Accent : C_Zone))
    RoundCtrl(knob, 8), RoundCtrl(track, 11)
    sw := {knob: knob, track: track, on: on, x: x, y: y, cb: callback}
    track.OnEvent("Click", (*) => ToggleSwitch(sw))
    knob.OnEvent("Click", (*) => ToggleSwitch(sw))
    return sw
}

ToggleSwitch(sw) {
    sw.on := !sw.on
    sw.track.Opt("+Background" (sw.on ? C_Accent : C_Zone))
    sw.knob.Move(sw.x + (sw.on ? 21 : 3), sw.y + 3)
    sw.track.Redraw(), sw.knob.Redraw()
    sw.cb.Call(sw.on)
}

ShowSettings(*) {
    global SettingsGui, SetTiles, SetGapPills
    if SettingsGui {
        SettingsGui.Show()
        return
    }
    W := 520                    ; content width
    g := NewBrandedGui(AppName " Settings")

    if FileExist(LogoFile)
        g.AddPicture("x28 y24 w40 h40", LogoFile)
    g.SetFont("s15 bold c" C_Text)
    g.AddText("x80 y21 BackgroundTrans", "Settings")
    g.SetFont("s9 norm c" C_Muted)
    g.AddText("x80 y48 BackgroundTrans", "Wideside " AppVersion)

    ; Layouts: a grid of diagram cards
    y := 92
    SectionLabel(g, y, "LAYOUT")
    y += 24
    cols := 4, tw := 118, th := 92
    SetTiles := []
    for i, l in Layouts
        SetTiles.Push(AddLayoutTile(g, 28 + Mod(i - 1, cols) * (tw + 16), y + (i - 1) // cols * (th + 14), tw, th, l, i))
    y += Ceil(Layouts.Length / cols) * (th + 14) + 12

    ; Gap: a row of pills
    SectionLabel(g, y, "GAP BETWEEN WINDOWS")
    y += 24
    SetGapPills := []
    for i, v in GapOptions {
        g.SetFont("s9 norm c" C_Text)
        pill := g.AddText("x" (28 + (i - 1) * 62) " y" y " w54 h30 Center +0x200 Background" C_Card, v " px")
        RoundCtrl(pill, 8)
        pill.OnEvent("Click", ((v, *) => (SetGap(v), RefreshSettings())).Bind(v))
        SetGapPills.Push({ctl: pill, v: v})
    }
    y += 52

    ; Options: switches in one card
    SectionLabel(g, y, "OPTIONS")
    y += 24
    rows := [
        ["Only show zones while holding Shift", "Off: every drag shows zones. Ctrl + drag always moves freely.", RequireShift, SetRequireShift],
        ["Pause Windows Snap", "Stops Windows' own snapping competing with the zones", PauseWinSnap, SetPauseWinSnap],
        ["Remember app zones", "Apps reopen in the zone they were last snapped to", RememberApps, SetRememberApps],
        ["Check for updates", "Looks for new versions on GitHub every few hours", CheckUpdates, SetCheckUpdates],
        ["Start with Windows", "Run Wideside when you sign in", FileExist(StartupLink()) != "", SetStartup]
    ]
    rh := 60
    for i, r in rows {
        ry := y + (i - 1) * rh
        sw := AddSwitch(g, 28 + W - 58, ry + 19, r[3], r[4])
        g.SetFont("s10 norm c" C_Text)
        t := g.AddText("x46 y" (ry + 11) " w" (W - 100) " Background" C_Card, r[1])
        g.SetFont("s9 norm c" C_Muted)
        d := g.AddText("x46 y" (ry + 32) " w" (W - 100) " Background" C_Card, r[2])
        for c in [t, d]
            c.OnEvent("Click", ((sw, *) => ToggleSwitch(sw)).Bind(sw))
        if i > 1
            g.AddText("x46 y" ry " w" (W - 36) " h1 Background" C_Border)
    }
    box := g.AddText("x28 y" y " w" W " h" (rows.Length * rh) " +0x4000000 Background" C_Card)
    RoundCtrl(box, 12)
    y += rows.Length * rh + 22

    g.SetFont("s9 norm c" C_Accent)
    custom := g.AddText("x28 y" (y + 9) " BackgroundTrans", "Edit custom layouts")
    custom.OnEvent("Click", EditCustomLayouts)
    guide := g.AddText("x+20 yp BackgroundTrans", "User guide")
    guide.OnEvent("Click", OpenGuide)
    done := AddButton(g, "x" (28 + W - 110) " y" y " w110", "Done", CloseSettings)
    RoundCtrl(done, 9)

    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)
    SettingsGui := g
    RefreshSettings()
    g.Show("w" (W + 56) " h" (y + 36 + 26))
}

RefreshSettings() {
    if !SettingsGui
        return
    for i, t in SetTiles
        StyleTile(t, i = LayoutIndex)
    for p in SetGapPills {
        on := p.v = Gap
        p.ctl.Opt("+Background" (on ? C_Accent : C_Card))
        p.ctl.SetFont(on ? "bold c" C_Bg : "norm c" C_Text)
        p.ctl.Redraw()
    }
}

CloseSettings(*) {
    global SettingsGui
    if SettingsGui
        SettingsGui.Destroy()
    SettingsGui := 0
}

; ---------------------------------------------------------------- tray menu

BuildTrayMenu() {
    tray := A_TrayMenu
    tray.Delete()

    tray.Add("Settings", ShowSettings)
    layoutMenu := Menu()
    for i, l in Layouts {
        layoutMenu.Add(l.name, SetLayout.Bind(i))
        if i = LayoutIndex
            layoutMenu.Check(l.name)
    }
    tray.Add("Layout", layoutMenu)
    tray.Add("Show zones`tWin+Alt+Z", PreviewZones)
    tray.Add("Arrange all windows`tWin+Alt+A", ArrangeAll)
    tray.Add("Pause snapping`tWin+Alt+P", TogglePause)
    if Paused
        tray.Check("Pause snapping`tWin+Alt+P")
    tray.Add()
    if LatestVersion
        tray.Add("Update to version " LatestVersion, InstallUpdate)
    else
        tray.Add("Check for updates", CheckForUpdates.Bind(true))
    tray.Add("User guide", OpenGuide)
    tray.Add("About and hotkeys", ShowAbout.Bind(false))
    tray.Add("Reload", (*) => Reload())
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Settings"
    tray.ClickCount := 1

    A_IconTip := AppName " - " (Paused ? "paused" : Layouts[LayoutIndex].name)
}
