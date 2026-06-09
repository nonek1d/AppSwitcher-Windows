#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true
#MaxThreadsPerHotkey 3

; macOS-ish task switcher. Hold Shift, tap Alt to step through apps, let Shift
; go to jump to the one you landed on. Arrows move by hand, backtick cycles an
; app's windows, Esc bails.

SetWinDelay(-1)
SetControlDelay(-1)

global gdip := 0

killLangToggle()
gdipUp()

global ICON   := 56
global GAP    := 18
global PADX   := 20
global PADY   := 18
global BARH   := 5
global NAMEH  := 22
global RADIUS := 18
global GLOW   := 24
global TILE   := "34353A"
global FG     := "FFFFFF"
global Accent := accentColor()
global KEY    := "010203"
global KEYCR  := 0x030201

global PVW   := 560
global PVH   := 340
global PVPAD := 8
global PVGAP := 22

global Apps       := []
global Sel        := 1
global Sw         := 0
global Bg         := 0
global Bar        := 0
global NameTxt    := 0
global Icons      := []
global IconH      := []
global PanelW     := 0
global panelH     := 0
global Active     := false
global TapHeld    := false
global Miss       := 0
global BarReady   := false
global BarCurX    := 0
global BarTargetX := 0
global gMX        := -1
global gMY        := -1

global Pv         := 0
global PvThumb    := 0
global PvOut      := 0
global PvOutThumb := 0
global PvRestX    := 0
global PvRestY    := 0
global PvDir      := 0
global PvStep     := 0
global PvSteps    := 8
global PvSlide    := 80
global gDir       := 0

global gPadX := 0, gStepX := 0, gIconY := 0, gBarY := 0, gNameY := 0, gBarW := 0

global BgMode := "", BgAllocated := false
global BgHScreen := 0, BgHdc := 0, BgHbm := 0, BgObm := 0
global BgW := 0, BgH := 0, BgX := 0, BgY := 0
global SwX := 0, SwY := 0, gAnim := 0, PopOff := 14

; We swallow Alt entirely (no "~") while Shift is down so Windows never sees the
; Alt+Shift combo and can't flip the input language on us.
#HotIf GetKeyState("Shift", "P")
*LAlt::step()
*RAlt::step()
*LAlt up::rearm()
*RAlt up::rearm()
#HotIf

#HotIf Active
Right::nav(1)
Left::nav(-1)
Enter::commit()
NumpadEnter::commit()
vkC0::cycle()
Escape::closeUI()
#HotIf

step() {
    global
    if TapHeld
        return
    TapHeld := true
    nav(1)
}

rearm() {
    global
    TapHeld := false
}

nav(dir) {
    global
    if !Active {
        build()
        if !Apps.Length {
            closeUI()
            return
        }
        Sel := 1
        SetTimer(watchShift, 20)
    }
    Sel += dir
    if (Sel > Apps.Length)
        Sel := 1
    else if (Sel < 1)
        Sel := Apps.Length
    gDir := dir
    refresh()
}

watchShift() {
    global
    if GetKeyState("Shift", "P") {
        Miss := 0
        return
    }
    if (++Miss < 3)
        return
    Miss := 0
    SetTimer(watchShift, 0)
    commit()
}

build() {
    global
    Apps := [], Icons := [], IconH := [], Sel := 1, BarReady := false

    for hwnd in WinGetList() {
        if !inAltTab(hwnd)
            continue
        pid := 0
        try pid := WinGetPID(hwnd)
        catch
            continue
        exe := ""
        try exe := ProcessGetPath(pid)
        name := shortTitle(WinGetTitle(hwnd))
        if (name = "" && exe != "")
            SplitPath(exe, , , , &name)
        Apps.Push({ exe: exe, name: name, windows: [hwnd] })
    }
    if !Apps.Length
        return

    n := Apps.Length
    gPadX  := PADX
    gStepX := ICON + GAP
    gIconY := PADY
    gBarY  := PADY + ICON + 8
    gNameY := gBarY + BARH + 4
    gBarW  := ICON
    PanelW := PADX * 2 + n * ICON + (n - 1) * GAP
    panelH := gNameY + NAMEH + PADY

    px := (A_ScreenWidth  - PanelW) // 2
    py := (A_ScreenHeight - panelH) // 2
    SwX := px, SwY := py

    backdrop(PanelW, panelH, px, py)

    Sw := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x80000", "AppSwitcher")
    Sw.BackColor := KEY
    Sw.MarginX := 0, Sw.MarginY := 0

    Bar := Sw.Add("Text", Format("x{} y{} w{} h{} Background{}", gPadX, gBarY, gBarW, BARH, Accent))
    brgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", gBarW + 1, "int", BARH + 1, "int", BARH, "int", BARH, "ptr")
    DllCall("SetWindowRgn", "ptr", Bar.Hwnd, "ptr", brgn, "int", true)

    for i, app in Apps {
        x := gPadX + (i - 1) * gStepX
        spec := appIcon(app.windows[1], app.exe)
        opt := Format("x{} y{} w{} h{}", x, gIconY, ICON, ICON)
        if (spec != "") {
            ctrl := Sw.Add("Picture", opt, spec)
        } else {
            ctrl := Sw.Add("Text", opt " Center 0x200 Background" TILE " c" FG, StrUpper(SubStr(app.name, 1, 1)))
            ctrl.SetFont("s24", "Segoe UI")
        }
        try ctrl.OnEvent("Click", iconClick.Bind(i))
        Icons.Push(ctrl)
    }

    NameTxt := Sw.Add("Text", Format("x0 y{} w160 h{} Center BackgroundTrans c{}", gNameY, NAMEH, FG), "")
    NameTxt.SetFont("s10", "Segoe UI")

    gAnim := 0
    blit(0, PopOff)
    Sw.Show(Format("x{} y{} w{} h{} NoActivate", px, py + PopOff, PanelW, panelH))
    DllCall("SetLayeredWindowAttributes", "ptr", Sw.Hwnd, "uint", KEYCR, "uchar", 0, "uint", 3)
    Active := true
    SetTimer(popAnim, 8)
    gMX := -1, gMY := -1
    SetTimer(hoverWatch, 30)
}

popAnim() {
    global
    steps := 5
    if (++gAnim >= steps) {
        SetTimer(popAnim, 0)
        blit(255, 0)
        blitDone()
        if Sw
            DllCall("SetLayeredWindowAttributes", "ptr", Sw.Hwnd, "uint", KEYCR, "uchar", 255, "uint", 3)
        return
    }
    t := gAnim / steps
    a := Round(255 * t)
    off := Round(PopOff * (1 - t))
    blit(a, off)
    if !Sw
        return
    WinMove(SwX, SwY + off, , , "ahk_id " Sw.Hwnd)
    DllCall("SetLayeredWindowAttributes", "ptr", Sw.Hwnd, "uint", KEYCR, "uchar", (a < 40 ? 40 : a), "uint", 3)
}

refresh() {
    global
    if !Active
        return
    BarTargetX := gPadX + (Sel - 1) * gStepX
    if !BarReady {
        BarCurX := BarTargetX
        BarReady := true
        Bar.Move(BarCurX, gBarY, gBarW, BARH)
    } else {
        SetTimer(barAnim, 10)
    }

    nameW := 160
    nx := gPadX + (Sel - 1) * gStepX + (ICON - nameW) // 2
    if (nx < 4)
        nx := 4
    else if (nx + nameW > PanelW - 4)
        nx := PanelW - 4 - nameW
    NameTxt.Move(nx, , nameW)

    app := Apps[Sel]
    cur := shortTitle(WinGetTitle("ahk_id " app.windows[1]))
    NameTxt.Value := (cur != "") ? cur : app.name
    preview(app.windows[1], gDir)
}

barAnim() {
    global
    if (!Active || !Bar) {
        SetTimer(barAnim, 0)
        return
    }
    d := BarTargetX - BarCurX
    if (Abs(d) <= 2) {
        BarCurX := BarTargetX
        SetTimer(barAnim, 0)
    } else {
        BarCurX += (d > 0 ? 1 : -1) * Max(1, Abs(d) // 2)
    }
    Bar.Move(BarCurX, gBarY, gBarW, BARH)
}

iconClick(idx, *) {
    global Sel, Active
    if !Active
        return
    Sel := idx
    commit()
}

; Point at an icon to select it. Only react to actual movement, otherwise a
; cursor parked on a tile would keep stealing the selection from the keyboard.
hoverWatch() {
    global
    if !Active
        return
    MouseGetPos(&mx, &my, , &ctrl, 2)
    if (mx = gMX && my = gMY)
        return
    gMX := mx, gMY := my
    if !ctrl
        return
    for i, c in Icons {
        if (c.Hwnd != ctrl)
            continue
        if (i != Sel) {
            Sel := i
            gDir := 0
            refresh()
        }
        return
    }
}

cycle() {
    global
    if !Active
        return
    app := Apps[Sel]
    if (app.windows.Length < 2)
        return
    app.windows.Push(app.windows.RemoveAt(1))
    gDir := 0
    refresh()
}

commit() {
    global
    if !Active
        return
    target := (Sel >= 1 && Sel <= Apps.Length) ? Apps[Sel].windows[1] : 0
    closeUI()
    if !(target && WinExist("ahk_id " target))
        return
    try {
        if (WinGetMinMax("ahk_id " target) = -1)
            WinRestore("ahk_id " target)
        WinActivate("ahk_id " target)
    }
}

closeUI() {
    global
    Active := false
    TapHeld := false
    BarReady := false
    SetTimer(watchShift, 0)
    SetTimer(barAnim, 0)
    SetTimer(popAnim, 0)
    SetTimer(hoverWatch, 0)
    blitDone()
    killPreview()
    if Sw {
        try Sw.Destroy()
        Sw := 0
    }
    if Bg {
        try Bg.Destroy()
        Bg := 0
    }
    for h in IconH
        try DllCall("DestroyIcon", "ptr", h)
    IconH := []
}

backdrop(panelW, panelH, px, py) {
    global
    BW := panelW + GLOW * 2
    BH := panelH + GLOW * 2
    BgW := BW, BgH := BH, BgX := px - GLOW, BgY := py - GLOW

    Bg := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x80000", "AppSwitcherBG")
    Bg.Show(Format("x{} y{} w{} h{} NoActivate", BgX, BgY, BW, BH))

    ; no GDI+? fall back to a plain rounded panel
    if !gdipUp() {
        BgMode := "plain", BgAllocated := false
        Bg.BackColor := "1F2024"
        rgn := DllCall("CreateRoundRectRgn", "int", GLOW, "int", GLOW, "int", GLOW + panelW + 1, "int", GLOW + panelH + 1, "int", RADIUS * 2, "int", RADIUS * 2, "ptr")
        DllCall("SetWindowRgn", "ptr", Bg.Hwnd, "ptr", rgn, "int", true)
        WinSetTransparent(1, "ahk_id " Bg.Hwnd)
        return
    }
    BgMode := "gdip"

    aInt := Integer("0x" Accent)
    ar := (aInt >> 16) & 0xFF, ag := (aInt >> 8) & 0xFF, ab := aInt & 0xFF

    BgHScreen := DllCall("GetDC", "ptr", 0, "ptr")
    BgHdc := DllCall("CreateCompatibleDC", "ptr", BgHScreen, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", BW, bi, 4)
    NumPut("int", -BH, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    BgHbm := DllCall("CreateDIBSection", "ptr", BgHdc, "ptr", bi, "uint", 0, "ptr*", &pBits := 0, "ptr", 0, "uint", 0, "ptr")
    BgObm := DllCall("SelectObject", "ptr", BgHdc, "ptr", BgHbm, "ptr")
    BgAllocated := true

    DllCall("gdiplus\GdipCreateFromHDC", "ptr", BgHdc, "ptr*", &G := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", G, "int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "ptr", G, "uint", 0x00000000)

    loop GLOW {
        inf := GLOW - A_Index
        a := Round(26 * A_Index / GLOW)
        roundRect(G, GLOW - inf, GLOW - inf, panelW + inf * 2, panelH + inf * 2, RADIUS + inf, premul(a, ar, ag, ab))
    }
    roundRect(G, GLOW, GLOW, panelW, panelH, RADIUS, premul(210, 0x1F, 0x20, 0x24))

    DllCall("gdiplus\GdipDeleteGraphics", "ptr", G)
}

blit(sca, yoff) {
    global
    if (BgMode = "gdip") {
        if !BgAllocated
            return
        ptDst := Buffer(8, 0), NumPut("int", BgX, ptDst, 0), NumPut("int", BgY + yoff, ptDst, 4)
        sz    := Buffer(8, 0), NumPut("int", BgW, sz, 0), NumPut("int", BgH, sz, 4)
        ptSrc := Buffer(8, 0)
        blend := Buffer(4, 0)
        NumPut("uchar", 0, blend, 0)
        NumPut("uchar", 0, blend, 1)
        NumPut("uchar", sca, blend, 2)
        NumPut("uchar", 1, blend, 3)
        DllCall("UpdateLayeredWindow", "ptr", Bg.Hwnd, "ptr", BgHScreen, "ptr", ptDst, "ptr", sz, "ptr", BgHdc, "ptr", ptSrc, "uint", 0, "ptr", blend, "uint", 2)
        return
    }
    if (BgMode = "plain" && Bg) {
        WinMove(BgX, BgY + yoff, , , "ahk_id " Bg.Hwnd)
        WinSetTransparent(Max(1, Round(210 * sca / 255)), "ahk_id " Bg.Hwnd)
    }
}

blitDone() {
    global
    if !(BgMode = "gdip" && BgAllocated)
        return
    DllCall("SelectObject", "ptr", BgHdc, "ptr", BgObm)
    DllCall("DeleteObject", "ptr", BgHbm)
    DllCall("DeleteDC", "ptr", BgHdc)
    DllCall("ReleaseDC", "ptr", 0, "ptr", BgHScreen)
    BgAllocated := false
}

roundRect(G, x, y, w, h, r, argb) {
    if (r < 1)
        r := 1
    d := r * 2
    if (d > w)
        d := w
    if (d > h)
        d := h
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &path := 0)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x,         "float", y,         "float", d, "float", d, "float", 180, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y,         "float", d, "float", d, "float", 270, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y + h - d, "float", d, "float", d, "float", 0,   "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x,         "float", y + h - d, "float", d, "float", d, "float", 90,  "float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", path)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &brush := 0)
    DllCall("gdiplus\GdipFillPath", "ptr", G, "ptr", brush, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
    DllCall("gdiplus\GdipDeletePath", "ptr", path)
}

; premultiplied ARGB, required by UpdateLayeredWindow + AC_SRC_ALPHA
premul(a, r, g, b) {
    r := (r * a) // 255
    g := (g * a) // 255
    b := (b * a) // 255
    return (a << 24) | (r << 16) | (g << 8) | b
}

gdipUp() {
    global gdip
    if gdip
        return true
    if !DllCall("GetModuleHandle", "str", "gdiplus", "ptr")
        DllCall("LoadLibrary", "str", "gdiplus", "ptr")
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("uint", 1, si, 0)
    if DllCall("gdiplus\GdiplusStartup", "ptr*", &tok := 0, "ptr", si, "ptr", 0)
        return false
    gdip := tok
    return true
}

; "YouTube - Google Chrome" -> "YouTube"; drops a leading "(5)" unread count too.
shortTitle(t) {
    t := Trim(t)
    if (t = "")
        return ""
    t := RegExReplace(t, "^\(\d+\)\s*", "")
    for sep in [" " Chr(0x2014) " ", " " Chr(0x2013) " ", " - "] {
        p := InStr(t, sep, false, -1)
        if (p > 1) {
            t := SubStr(t, 1, p - 1)
            break
        }
    }
    return Trim(t)
}

; dir flips the slide: tap right and the new preview flies in from the left while
; the old one leaves to the right (dir 0 = plain crossfade, used when cycling).
preview(hwnd, dir := 0) {
    global
    if (!hwnd || !WinExist("ahk_id " hwnd))
        return

    PvRestX := SwX + PanelW // 2 - PVW // 2
    PvRestY := SwY + panelH + PVGAP
    if (PvRestY + PVH > A_ScreenHeight - 10)
        PvRestY := SwY - PVGAP - PVH
    if (PvRestX < 8)
        PvRestX := 8
    else if (PvRestX + PVW > A_ScreenWidth - 8)
        PvRestX := A_ScreenWidth - 8 - PVW

    dropOld()
    PvOut := Pv, PvOutThumb := PvThumb
    Pv := 0, PvThumb := 0

    PvDir := -dir
    PvStep := 0
    mkPreview(hwnd, PvRestX + PvDir * PvSlide, PvRestY)
    pvAlpha(Pv, PvThumb, 0)
    SetTimer(pvAnim, 10)
}

mkPreview(hwnd, x, y) {
    global
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x80000", "AppSwitcherPV")
    g.BackColor := "0E0F12"
    g.MarginX := 0, g.MarginY := 0
    g.Show(Format("x{} y{} w{} h{} NoActivate", x, y, PVW, PVH))
    rgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", PVW + 1, "int", PVH + 1, "int", 20, "int", 20, "ptr")
    DllCall("SetWindowRgn", "ptr", g.Hwnd, "ptr", rgn, "int", true)

    rc := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
    srcW := NumGet(rc, 8, "int") - NumGet(rc, 0, "int")
    srcH := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
    if (srcW <= 0 || srcH <= 0)
        srcW := 16, srcH := 9
    innerW := PVW - PVPAD * 2, innerH := PVH - PVPAD * 2
    scale := Min(innerW / srcW, innerH / srcH)
    tw := Max(1, Round(srcW * scale)), th := Max(1, Round(srcH * scale))
    dx := (PVW - tw) // 2, dy := (PVH - th) // 2

    thumb := 0
    if (DllCall("dwmapi\DwmRegisterThumbnail", "ptr", g.Hwnd, "ptr", hwnd, "ptr*", &tid := 0) = 0) {
        thumb := tid
        props := Buffer(48, 0)
        NumPut("uint", 0x1 | 0x4 | 0x8 | 0x10, props, 0)
        NumPut("int", dx,      props, 4)
        NumPut("int", dy,      props, 8)
        NumPut("int", dx + tw, props, 12)
        NumPut("int", dy + th, props, 16)
        NumPut("uchar", 255, props, 36)
        NumPut("int",   1,   props, 40)
        NumPut("int",   1,   props, 44)
        DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", thumb, "ptr", props)
    }
    Pv := g, PvThumb := thumb
}

pvAnim() {
    global
    if !Active {
        SetTimer(pvAnim, 0)
        dropOld()
        return
    }
    pt := Min(1, ++PvStep / PvSteps)
    pe := 1 - (1 - pt) ** 3

    if Pv {
        WinMove(PvRestX + Round(PvDir * PvSlide * (1 - pe)), PvRestY, , , "ahk_id " Pv.Hwnd)
        pvAlpha(Pv, PvThumb, Round(255 * pe))
    }
    if PvOut {
        WinMove(PvRestX - Round(PvDir * PvSlide * pe), PvRestY, , , "ahk_id " PvOut.Hwnd)
        pvAlpha(PvOut, PvOutThumb, Round(255 * (1 - pe)))
    }

    if (PvStep < PvSteps)
        return
    SetTimer(pvAnim, 0)
    if Pv {
        WinMove(PvRestX, PvRestY, , , "ahk_id " Pv.Hwnd)
        pvAlpha(Pv, PvThumb, 255)
    }
    dropOld()
}

pvAlpha(g, thumb, a) {
    if !g
        return
    try DllCall("SetLayeredWindowAttributes", "ptr", g.Hwnd, "uint", 0, "uchar", a, "uint", 2)
    if !thumb
        return
    props := Buffer(48, 0)
    NumPut("uint", 0x4 | 0x8, props, 0)
    NumPut("uchar", a, props, 36)
    NumPut("int", 1, props, 40)
    try DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", thumb, "ptr", props)
}

dropOld() {
    global
    if PvOutThumb {
        try DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", PvOutThumb)
        PvOutThumb := 0
    }
    if PvOut {
        try PvOut.Destroy()
        PvOut := 0
    }
}

killPreview() {
    global
    SetTimer(pvAnim, 0)
    dropOld()
    if PvThumb {
        try DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", PvThumb)
        PvThumb := 0
    }
    if Pv {
        try Pv.Destroy()
        Pv := 0
    }
}

appIcon(hwnd, exe) {
    global ICON, IconH
    if (exe != "" && FileExist(exe)) {
        try {
            ph := LoadPicture(exe, "Icon1 w" ICON " h" ICON, &it)
            if ph {
                IconH.Push(ph)
                return "HICON:" ph
            }
        }
    }
    h := 0
    try h := SendMessage(0x7F, 1, 0, , "ahk_id " hwnd)
    if !h
        h := DllCall("GetClassLongPtr", "ptr", hwnd, "int", -14, "ptr")
    if !h
        try h := SendMessage(0x7F, 0, 0, , "ahk_id " hwnd)
    if !h
        h := DllCall("GetClassLongPtr", "ptr", hwnd, "int", -34, "ptr")
    return h ? "HICON:" h : ""
}

; Raymond Chen's alt-tab visibility test, plus a DWM cloak check for UWP ghosts.
inAltTab(hwnd) {
    if !DllCall("IsWindowVisible", "ptr", hwnd)
        return false
    walk := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr")
    loop {
        pop := DllCall("GetLastActivePopup", "ptr", walk, "ptr")
        if (pop = walk || DllCall("IsWindowVisible", "ptr", pop))
            break
        walk := pop
    }
    if (walk != hwnd)
        return false
    if (WinGetExStyle(hwnd) & 0x80)
        return false
    if (WinGetTitle(hwnd) = "")
        return false
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "int*", &cloaked, "uint", 4)
    return !cloaked
}

accentColor() {
    try {
        abgr := RegRead("HKCU\Software\Microsoft\Windows\DWM", "AccentColor")
        return Format("{:02X}{:02X}{:02X}", abgr & 0xFF, (abgr >> 8) & 0xFF, (abgr >> 16) & 0xFF)
    } catch {
        return "3478F6"
    }
}

; Kill the Alt+Shift language toggle so our hotkey doesn't flip the layout.
; Win+Space still switches; takes full effect after the next sign-out.
killLangToggle() {
    try {
        RegWrite("3", "REG_SZ", "HKCU\Keyboard Layout\Toggle", "Hotkey")
        RegWrite("3", "REG_SZ", "HKCU\Keyboard Layout\Toggle", "Language Hotkey")
        RegWrite("3", "REG_SZ", "HKCU\Keyboard Layout\Toggle", "Layout Hotkey")
    }
}
