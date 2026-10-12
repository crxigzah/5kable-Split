; Wideside - Easy Arrange style window zones for big / ultrawide monitors
; Built for the MSI MAG C42CQR E2 but works on any monitor (it reads the
; resolution and taskbar position from Windows at runtime).
;
; Requires AutoHotkey v2 to run from source. build.cmd compiles it to an .exe
; and wraps it in an installer.

;@Ahk2Exe-SetName Wideside
;@Ahk2Exe-SetProductName Wideside
;@Ahk2Exe-SetDescription Wideside
;@Ahk2Exe-SetVersion 1.3.1
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
global AppVersion := "1.3.1"
global AppUrl := "https://crxigzah.github.io/wideside/"

; Settings live in %AppData% so it works when installed to Program Files.
global DataDir := A_AppData "\Wideside"
global IniFile := DataDir "\settings.ini"
global LogoFile := DataDir "\logo.png"

; Wideside palette
global C_Bg := "101114", C_Card := "1C1E25", C_Accent := "FF7A3D"
global C_Text := "F4F4F5", C_Muted := "9A9DA8"

; Zones are [x, y, width, height] as fractions of the screen's work area.
global BuiltInLayouts := [
    {name: "Two halves (50/50)",          zones: [[0, 0, 1/2, 1], [1/2, 0, 1/2, 1]]},
    {name: "Wide left (60/40)",           zones: [[0, 0, 0.6, 1], [0.6, 0, 0.4, 1]]},
    {name: "Wide right (40/60)",          zones: [[0, 0, 0.4, 1], [0.4, 0, 0.6, 1]]},
    {name: "Three columns",               zones: [[0, 0, 1/3, 1], [1/3, 0, 1/3, 1], [2/3, 0, 1/3, 1]]},
    {name: "Focus centre (25/50/25)",     zones: [[0, 0, 0.25, 1], [0.25, 0, 0.5, 1], [0.75, 0, 0.25, 1]]},
    {name: "Left half + right stacked",   zones: [[0, 0, 1/2, 1], [1/2, 0, 1/2, 1/2], [1/2, 1/2, 1/2, 1/2]]},
    {name: "Four quarters",               zones: [[0, 0, 1/2, 1/2], [1/2, 0, 1/2, 1/2], [0, 1/2, 1/2, 1/2], [1/2, 1/2, 1/2, 1/2]]}
]
global GapOptions := [0, 4, 8, 12, 16, 24]

global Layouts := []
global LayoutIndex := 1
global Gap := 0
global RequireShift := true
global ZoneOf := Map()          ; hwnd -> {idx, x, y, w, h} of the last snap

global Overlays := [], OverlayMon := 0, OverlayHi := -1, HotFill := 0
global DragHwnd := 0, DragZone := 0, DragMon := 0, DragW := 0, DragH := 0
global MouseDrag := false, WatchHwnd := 0, WatchX := 0, WatchY := 0
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

if FirstRun
    ShowAbout(true)
else
    TrayTip "Running in the system tray`nLayout: " Layouts[LayoutIndex].name, AppName

#!Left::  CycleZone(-1)
#!Right:: CycleZone(1)
#!Up::    MaximiseActive()
#!l::     NextLayout()
#!z::     PreviewZones()

; Track the left mouse button so drags that apps run themselves (see
; WatchMouseDrag) can snap too. ~ lets the click through as normal.
~LButton:: {
    global MouseDrag, WatchHwnd
    MouseDrag := false, WatchHwnd := 0
    SetTimer WatchMouseDrag, 30
}

~LButton Up:: {
    global MouseDrag, DragHwnd
    SetTimer WatchMouseDrag, 0
    if !MouseDrag
        return
    MouseDrag := false
    SetTimer DragTick, 0
    hwnd := DragHwnd, zone := DragZone, mon := DragMon
    DragHwnd := 0
    HideOverlay()
    ; Slightly longer delay than a title-bar drag: browsers finish placing a
    ; torn-off tab's window just after the button comes up.
    if zone && (!RequireShift || GetKeyState("Shift", "P"))
        SetTimer () => SnapToZone(hwnd, mon, zone), -80
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
; 1 = only show zones / snap when Shift is held while dragging, 0 = every drag
RequireShift=1

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
    global Layouts, LayoutIndex, Gap, RequireShift
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
    RequireShift := ReadInt("RequireShift", 1) != 0
}

ReadInt(key, default) {
    try return Integer(IniRead(IniFile, "Settings", key, default))
    return default
}

SaveSettings() {
    IniWrite LayoutIndex, IniFile, "Settings", "Layout"
    IniWrite Gap, IniFile, "Settings", "Gap"
    IniWrite RequireShift ? 1 : 0, IniFile, "Settings", "RequireShift"
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

SnapToZone(hwnd, mon, idx) {
    zones := CurrentZones()
    if !IsSnappable(hwnd) || idx < 1 || idx > zones.Length
        return
    try {
        MoveWindowTo(hwnd, ZoneRect(mon, zones[idx]))
        WinGetPos &x, &y, &w, &h, hwnd
        ZoneOf[hwnd] := {idx: idx, x: x, y: y, w: w, h: h}
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

OnMoveSize(hHook, event, hwnd, idObject, idChild, idThread, time) {
    global DragHwnd, DragZone, DragMon, DragW, DragH, MouseDrag
    if idObject != 0
        return
    if event = 0x000A {
        if !IsSnappable(hwnd)
            return
        MouseDrag := false   ; a normal title-bar drag takes over
        DragHwnd := hwnd, DragZone := 0, DragMon := 0
        try WinGetPos , , &DragW, &DragH, hwnd
        SetTimer DragTick, 25
    } else if event = 0x000B && hwnd = DragHwnd {
        SetTimer DragTick, 0
        zone := DragZone, mon := DragMon
        DragHwnd := 0
        HideOverlay()
        if zone && (!RequireShift || GetKeyState("Shift", "P"))
            SetTimer () => SnapToZone(hwnd, mon, zone), -15
    }
}

DragTick() {
    global DragZone, DragMon, DragHwnd
    if !DragHwnd
        return
    ; Resizing also fires the move event - ignore it if the size is changing.
    try WinGetPos , , &w, &h, DragHwnd
    catch {
        DragHwnd := 0
        HideOverlay()
        return
    }
    if w != DragW || h != DragH || (RequireShift && !GetKeyState("Shift", "P")) {
        DragZone := 0
        HideOverlay()
        return
    }
    MouseGetPos &mx, &my
    mon := MonitorFromPoint(mx, my)
    zone := ZoneAtPoint(mon, mx, my)
    ShowOverlay(mon, zone)
    DragZone := zone, DragMon := mon
}

; Chrome, Edge and Opera move a torn-off tab's new window themselves instead
; of using a normal title-bar drag, so no move event fires. Spot those by
; watching the active window move while the mouse button is held.
WatchMouseDrag() {
    global MouseDrag, WatchHwnd, WatchX, WatchY, DragHwnd, DragZone, DragMon, DragW, DragH
    if MouseDrag || DragHwnd   ; already tracking this drag
        return
    win := WinExist("A")
    if !IsSnappable(win)
        return
    try WinGetPos &x, &y, &w, &h, win
    catch
        return
    if win != WatchHwnd {      ; new active window (e.g. the torn-off tab) - start watching it
        WatchHwnd := win, WatchX := x, WatchY := y
        return
    }
    if x != WatchX || y != WatchY {
        MouseDrag := true
        DragHwnd := win, DragZone := 0, DragMon := 0, DragW := w, DragH := h
        SetTimer DragTick, 25
    }
}

; ---------------------------------------------------------------- overlay

; Easy Arrange style: each zone is an orange outline with a number tag. The
; zone under the mouse gets a thicker outline and a light orange tint.
ShowOverlay(mon, hi) {
    global Overlays, OverlayMon, OverlayHi, HotFill
    if mon != OverlayMon || !Overlays.Length {
        HideOverlay()
        HotFill := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
        HotFill.BackColor := C_Accent
        for i, z in CurrentZones() {
            r := ZoneRect(mon, z)
            ; The key colour is made fully transparent, so only the outline
            ; and number tag are drawn
            g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
            g.BackColor := "010203"
            lines := []
            Loop 4
                lines.Push(g.AddText("x0 y0 w1 h1 Background" C_Accent))
            g.SetFont("s11 bold c" C_Bg, "Segoe UI")
            g.AddText("x14 y14 w30 h30 Center +0x200 Background" C_Accent, i)
            g.Show("NA x" r.x " y" r.y " w" r.w " h" r.h)
            WinSetTransColor "010203 235", g
            o := {gui: g, lines: lines, w: r.w, h: r.h, rect: r}
            SetZoneFrame(o, false)
            Overlays.Push(o)
        }
        OverlayMon := mon, OverlayHi := -1
    }
    if hi != OverlayHi {
        for i, o in Overlays
            SetZoneFrame(o, i = hi)
        if hi >= 1 && hi <= Overlays.Length {
            r := Overlays[hi].rect
            HotFill.Show("NA x" r.x " y" r.y " w" r.w " h" r.h)
            WinSetTransparent 45, HotFill
        } else
            HotFill.Hide()
        OverlayHi := hi
    }
}

SetZoneFrame(o, hot) {
    t := hot ? 6 : 2
    o.lines[1].Move(0, 0, o.w, t)
    o.lines[2].Move(0, o.h - t, o.w, t)
    o.lines[3].Move(0, 0, t, o.h)
    o.lines[4].Move(o.w - t, 0, t, o.h)
    for l in o.lines
        l.Redraw()
}

HideOverlay(*) {
    global Overlays, OverlayMon, OverlayHi, HotFill
    for o in Overlays
        o.gui.Destroy()
    if HotFill
        HotFill.Destroy()
    Overlays := [], OverlayMon := 0, OverlayHi := -1, HotFill := 0
}

PreviewZones(*) {
    MouseGetPos &mx, &my
    HideOverlay()
    ShowOverlay(MonitorFromPoint(mx, my), 0)
    SetTimer HideOverlay, -1500
}

; ---------------------------------------------------------------- applying changes

SetLayout(i, *) {
    global LayoutIndex
    LayoutIndex := i
    ZoneOf.Clear()
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
    SaveSettings()
    PreviewZones()
}

SetRequireShift(on) {
    global RequireShift
    RequireShift := on
    SaveSettings()
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
        g.AddText("x24 y" y " w" (W - 24), "Wideside is running in your system tray (bottom right, next to the clock). Drag any window while holding Shift and drop it on a zone.")
        y += 60
    }

    keys := [
        ["Shift + drag",       "Show zones, drop to snap"],
        ["Win+Alt+Left/Right", "Previous / next zone"],
        ["Win+Alt+1 to 9",     "Snap to zone number"],
        ["Win+Alt+Up",         "Maximise across the screen"],
        ["Win+Alt+L",          "Next layout"],
        ["Win+Alt+Z",          "Show zones"]
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
    link := g.AddText("x24 y" (y + 8) " w200", "Website")
    link.OnEvent("Click", (*) => Run(AppUrl))
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

; Settings window with a live mini-preview of the layout
global PreviewBox := 0, PreviewZonesCtl := [], LayoutDDL := 0, PrevW := 360, PrevH := 150

ShowSettings(*) {
    global SettingsGui, PreviewBox, PreviewZonesCtl, LayoutDDL, PrevH
    if SettingsGui {
        SettingsGui.Show()
        return
    }
    W := 440
    g := NewBrandedGui(AppName " Settings")
    AddHeader(g, "Version " AppVersion, W)

    y := 110
    g.SetFont("s9 bold c" C_Muted)
    g.AddText("x24 y" y, "LAYOUT")
    g.SetFont("s10 norm c" C_Text)
    names := []
    for l in Layouts
        names.Push(l.name)
    LayoutDDL := g.AddDropDownList("x24 y" (y + 22) " w" (W - 24) " Choose" LayoutIndex " Background" C_Card, names)
    DarkControl(LayoutDDL)
    LayoutDDL.OnEvent("Change", (c, *) => SetLayout(c.Value))

    ; Preview matches the shape of the main monitor (ultrawide, 16:9, etc.)
    MonitorGet MonitorGetPrimary(), &L, &T, &R, &B
    PrevH := Max(80, Min(200, Round(PrevW * (B - T) / (R - L))))
    py := y + 64
    px := 24 + ((W - 24) - PrevW) // 2
    PreviewBox := {x: px, y: py}
    g.AddText("x" px " y" py " w" PrevW " h" PrevH " Background" C_Card)
    PreviewZonesCtl := []
    g.SetFont("s14 bold c" C_Bg)
    Loop 12
        PreviewZonesCtl.Push(g.AddText("x" px " y" py " w10 h10 Hidden Center +0x200 Background" C_Accent, A_Index))
    g.SetFont("s10 norm c" C_Text)

    y := py + PrevH + 22
    g.SetFont("s9 bold c" C_Muted)
    g.AddText("x24 y" y, "GAP BETWEEN WINDOWS")
    g.SetFont("s10 norm c" C_Text)
    gaps := [], gapIdx := 1
    for i, v in GapOptions {
        gaps.Push(v " px")
        if v = Gap
            gapIdx := i
    }
    gapDDL := g.AddDropDownList("x24 y" (y + 22) " w120 Choose" gapIdx " Background" C_Card, gaps)
    DarkControl(gapDDL)
    gapDDL.OnEvent("Change", (c, *) => (SetGap(GapOptions[c.Value]), RefreshSettings()))

    y += 68
    AddToggle(g, y, "Only snap when holding Shift while dragging", RequireShift, SetRequireShift)
    AddToggle(g, y + 28, "Start Wideside with Windows", FileExist(StartupLink()) != "", SetStartup)

    y += 72
    g.SetFont("s9 c" C_Accent)
    custom := g.AddText("x24 y" (y + 8) " w220", "Edit custom layouts...")
    custom.OnEvent("Click", EditCustomLayouts)
    AddButton(g, "x" (W - 104) " y" y " w120", "Done", CloseSettings)

    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)
    SettingsGui := g
    RefreshSettings()
    g.Show("w" (W + 24))
}

RefreshSettings() {
    if !SettingsGui
        return
    LayoutDDL.Value := LayoutIndex
    zones := CurrentZones()
    pg := Max(2, Round(Gap / 3))
    aw := PrevW - pg, ah := PrevH - pg
    for i, ctl in PreviewZonesCtl {
        if i > zones.Length {
            ctl.Visible := false
            continue
        }
        z := zones[i]
        x1 := Round(PreviewBox.x + pg / 2 + z[1] * aw + pg / 2)
        y1 := Round(PreviewBox.y + pg / 2 + z[2] * ah + pg / 2)
        x2 := Round(PreviewBox.x + pg / 2 + (z[1] + z[3]) * aw - pg / 2)
        y2 := Round(PreviewBox.y + pg / 2 + (z[2] + z[4]) * ah - pg / 2)
        ctl.Move(x1, y1, x2 - x1, y2 - y1)
        ctl.Visible := true
        ctl.Redraw()
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
    tray.Add()
    tray.Add("About and hotkeys", ShowAbout.Bind(false))
    tray.Add("Reload", (*) => Reload())
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Settings"
    tray.ClickCount := 1

    A_IconTip := AppName " - " Layouts[LayoutIndex].name
}
