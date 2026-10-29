pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// The desktop layer for macOS-style widgets: above the wallpaper, below every
// window. Widgets are listed in ~/.config/caelestia/macos.json (widgets.items)
// with their position relative to the usable desktop area of their display.
// Right-click the desktop for "Edit Widgets…" (the gallery) or to hide them.
// Widgets of the same size stack when dropped on each other (WidgetCard.qml).
// The frosted glass is drawn here from a blurred copy of the wallpaper, not by
// Hyprland's layer blur — that bled through title bars of windows above.
PanelWindow {
    id: desk

    required property ShellScreen modelData

    // widgets for this display; ones whose display isn't connected go to the home display:
    // an external one if plugged in, else the laptop. Not screens[0]: its order changes after
    // a suspend/resume, which sent every widget to the other display.
    // (modelData?: it turns null for a moment while an unplugged display's copy is torn down)
    readonly property string homeScreen: (Quickshell.screens.find(s => !s.name.startsWith("eDP")) ?? Quickshell.screens[0])?.name ?? ""
    readonly property var items: Config.widgetItems.filter(w => w.screen === modelData?.name
        || (!Quickshell.screens.some(s => s.name === w.screen) && homeScreen === modelData?.name))

    // one entry per spot: { id: stack key, members: [front, …] }
    // set a moment after start: cards made later (a stack split apart, a widget added)
    // skip the startup cascade instead of popping in from the corner
    property bool settled: false
    Timer {
        running: true
        interval: 1500
        onTriggered: desk.settled = true
    }

    readonly property var groups: {
        const map = new Map();
        for (const w of items) {
            const k = Config.stackKey(w);
            if (!map.has(k))
                map.set(k, []);
            map.get(k).push(w);
        }
        return [...map.entries()].map(([k, ms]) => ({ id: k, members: ms.sort((a, b) => (a.order ?? 0) - (b.order ?? 0)) }));
    }

    function group(key: string): var {
        return groups.find(g => g.id === key) ?? null;
    }

    // Sonoma: widgets dim while windows are open on the desktop this display
    // shows (minimised ones live elsewhere, so they don't count)
    readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
    readonly property bool windowsOpen: Hyprland.toplevels.values.some(t =>
        t.workspace !== null && t.workspace === hyprMonitor?.activeWorkspace)
    readonly property bool dimmed: Config.widgetsDim === "always" || (Config.widgetsDim === "auto" && windowsOpen)
    readonly property bool live: !windowsOpen && Config.widgetsEnabled && !PowerSaver.saving

    // while dragging: the stack the dragged card would join on release
    property string dropTarget: ""

    // where a saved widget is shown: always on this screen's grid (positions saved on
    // another screen, or before the gap adapted, land on the nearest grid spot)
    // (display-only: the saved spot is never rewritten here — see Config.placeOn)
    function gx(w: var): real {
        return spots[Config.stackKey(w)]?.x ?? WidgetTypes.snap(Config.placeOn(w, modelData?.name ?? "").x, WidgetTypes.width(w.size), width, true);
    }

    function gy(w: var): real {
        return spots[Config.stackKey(w)]?.y ?? WidgetTypes.snap(Config.placeOn(w, modelData?.name ?? "").y, WidgetTypes.height(w.size), height, false);
    }

    // stack key → { x, y } drawn on this display. Spots saved on a wider display can snap
    // onto the same spot here (1730 and 1540 both → the right column of the laptop), which
    // hid one stack under another; those take the nearest free spot instead. Stacks that
    // fit where they are go first, so only the ones that collide move. Display-only.
    readonly property var spots: {
        const out = {}, placed = [], later = [], g = WidgetTypes.gap - 1, name = modelData?.name ?? "";
        const free = (x, y, w, h) => !placed.some(p => x < p.x + p.w + g && x + w + g > p.x && y < p.y + p.h + g && y + h + g > p.y);
        const put = (grp, x, y, w, h) => {
            out[grp.id] = { x: x, y: y };
            placed.push({ x: x, y: y, w: w, h: h });
        };
        for (const grp of groups) {
            const f = grp.members[0], w = WidgetTypes.width(f.size), h = WidgetTypes.height(f.size), p = Config.placeOn(f, name);
            const x = WidgetTypes.snap(p.x, w, width, true), y = WidgetTypes.snap(p.y, h, height, false);
            if (free(x, y, w, h))
                put(grp, x, y, w, h);
            else
                later.push({ grp: grp, x: x, y: y, w: w, h: h });
        }
        for (const c of later) {
            let best = null;
            for (const x of WidgetTypes.snaps(c.x, c.w, width, true))
                for (const y of WidgetTypes.snaps(c.y, c.h, height, false))
                    if (free(x, y, c.w, c.h) && (!best || Math.abs(x - c.x) + Math.abs(y - c.y) < best.d))
                        best = { x: x, y: y, d: Math.abs(x - c.x) + Math.abs(y - c.y) };
            if (best)
                put(c.grp, best.x, best.y, c.w, c.h);
        }
        return out;
    }

    function stackTargetAt(cx: real, cy: real, size: string, exceptKey: string): string {
        const g = groups.find(g => {
            const f = g.members[0];
            const fx = gx(f), fy = gy(f);
            return g.id !== exceptKey && f.size === size && cx > fx && cx < fx + WidgetTypes.width(f.size)
                && cy > fy && cy < fy + WidgetTypes.height(f.size);
        });
        return g ? g.id : "";
    }

    // keeps at least a full gap between widgets
    function overlaps(x: real, y: real, w: real, h: real, exceptKey: string): bool {
        const g = WidgetTypes.gap - 1;
        return groups.some(grp => {
            if (grp.id === exceptKey)
                return false;
            const o = grp.members[0];
            const ox = gx(o), oy = gy(o);
            const ow = WidgetTypes.width(o.size), oh = WidgetTypes.height(o.size);
            return x < ox + ow + g && x + w + g > ox && y < oy + oh + g && y + h + g > oy;
        });
    }

    // First free spot, filling columns from the top-right like macOS
    function freeSpot(size: string, exceptId: string): var {
        return freeSpots(size, exceptId, 1)[0];
    }

    // n free spots that don't overlap each other either (a stack split apart)
    function freeSpots(size: string, exceptId: string, n: int): var {
        const w = WidgetTypes.width(size), h = WidgetTypes.height(size), g = WidgetTypes.gap - 1;
        // the desktop grid, from the top-right corner down each column (like macOS)
        const xs = Array.from(WidgetTypes.snaps(width, w, width, true));
        const ys = Array.from(WidgetTypes.snaps(0, h, height, false));
        const out = [];
        for (const x of xs)
            for (const y of ys)
                if (out.length < n && !overlaps(x, y, w, h, exceptId)
                        && !out.some(p => x < p.x + w + g && x + w + g > p.x && y < p.y + h + g && y + h + g > p.y))
                    out.push({ x: x, y: y });
        while (out.length < n)
            out.push({ x: xs[0] ?? WidgetTypes.edge, y: WidgetTypes.edgeTop });
        return out;
    }

    // resizes the whole stack
    function resizeWidget(entry: var, size: string): void {
        const key = Config.stackKey(entry);
        const w = WidgetTypes.width(size), h = WidgetTypes.height(size);
        const ex = gx(entry), ey = gy(entry);
        const fits = ex + w <= width && ey + h <= height && !overlaps(ex, ey, w, h, key);
        if (fits)
            Config.updateGroup(key, { size: size });
        else {
            const spot = freeSpot(size, key);
            Config.moveGroup(key, modelData.name, spot.x, spot.y, { size: size });
        }
    }

    // ── frosted glass: the wallpaper, blurred, under each card (WidgetBody.backdrop)
    readonly property var reserved: Hyprland.monitorFor(modelData)?.lastIpcObject?.reserved ?? [0, 0, 0, 0] // left, top, right, bottom
    Component.onCompleted: {
        WidgetTypes.deskHeight = height;
        Hyprland.refreshMonitors();
        Shared.deskWindows = [...Shared.deskWindows, desk];
    }
    Component.onDestruction: {
        Shared.deskWindows = Shared.deskWindows.filter(w => w !== desk);
        // a display went away: the grid gap follows a display that's still there (else the
        // remaining one's widgets re-snapped to the unplugged display's gap)
        const rest = Shared.deskWindows.find(w => w.height > 0);
        if (rest)
            WidgetTypes.deskHeight = rest.height;
    }
    onWidthChanged: Hyprland.refreshMonitors()
    onHeightChanged: {
        WidgetTypes.deskHeight = height; // the widget grid fits its gap to this
        Hyprland.refreshMonitors();
    }

    FileView {
        id: wallPath

        path: Quickshell.env("HOME") + "/.local/state/caelestia/wallpaper/path.txt"
        watchChanges: true
        onFileChanged: reload()
    }

    readonly property Item backdrop: wallSource

    Item {
        id: wallSource

        width: desk.width
        height: desk.height

        // two images: on a wallpaper change the new one loads underneath, then
        // fades in over the old one when Caelestia's reveal starts (it sends
        // custom>>macwall>>ms, see the overlay's Wallpaper.qml), so the glass
        // changes in step with the desktop. At login it just fades in once loaded;
        // with no reveal event within 2.5 s it fades anyway.
        property string wall: Config.widgetsGlass && !PowerSaver.saving && wallPath.text().trim() ? "file://" + wallPath.text().trim() : ""
        property bool frontIsA: true
        property Item incoming: null
        property bool firstWall: true

        onWallChanged: {
            const img = frontIsA ? wallB : wallA;
            img.stopFade();
            img.opacity = 0;
            img.source = wall;
            frontIsA = !frontIsA;
            incoming = img;
            if (firstWall) {
                firstWall = false;
                reveal(600);
            } else {
                revealFallback.restart();
            }
        }

        function reveal(ms: int): void {
            revealFallback.stop();
            incoming?.fade(ms);
            incoming = null;
        }

        Timer {
            id: revealFallback

            interval: 2500
            onTriggered: wallSource.reveal(1000)
        }

        Connections {
            target: Shared

            function onWallpaperReveal(ms: int): void {
                wallSource.reveal(ms);
            }
        }

        component WallImage: Image {
            id: wi

            signal faded()

            function fade(ms: int): void {
                fadeIn.duration = ms;
                fadeIn.restart();
            }
            function stopFade(): void {
                fadeIn.stop();
            }

            x: -(desk.reserved[0] ?? 0)
            y: -(desk.reserved[1] ?? 0)
            width: desk.modelData?.width ?? 0
            height: desk.modelData?.height ?? 0
            fillMode: Image.PreserveAspectCrop // as Caelestia draws it
            asynchronous: true
            sourceSize.width: 640 // it's blurred anyway

            NumberAnimation {
                id: fadeIn

                target: wi
                property: "opacity"
                to: 1
                easing.type: Easing.InOutCubic // like the reveal
                onFinished: wi.faded()
            }

            // Blurred once into a cached half-size texture when the image loads;
            // the crossfade then only blends two finished textures. (Blurring the
            // pair on every frame of the fade lagged the wallpaper reveal.)
            layer.enabled: status === Image.Ready // no blur buffers for an empty (freed) image
            layer.textureSize: Qt.size(width / 2, height / 2)
            layer.smooth: true
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1
                blurMax: 32
                saturation: 0.15
            }
        }

        WallImage {
            id: wallA

            z: wallSource.frontIsA ? 1 : 0
            // faded in over the old wallpaper: free that one. Only while this is still the
            // newest image (a later change may already be fading the other one in) and it
            // loaded (else the old one is all that shows)
            onFaded: if (wallSource.frontIsA && status === Image.Ready) wallB.source = ""
        }

        WallImage {
            id: wallB

            z: wallSource.frontIsA ? 0 : 1
            onFaded: if (!wallSource.frontIsA && status === Image.Ready) wallA.source = ""
        }
    }

    // keeps the blurred wallpaper itself out of sight; cards sample it
    ShaderEffectSource {
        sourceItem: wallSource
        hideSource: true
        width: 0
        height: 0
    }

    // build the galleries only once the menu has finished opening: building them in the same
    // frames froze the menu's first open for ~300 ms (stress test 2026-10-13)
    Timer {
        id: prewarmSoon

        interval: 400
        onTriggered: Shared.prewarm()
    }

    function openMenu(x: real, y: real, entries: var): void {
        prewarmSoon.restart();
        menuPoint.x = x;
        menuPoint.y = y;
        menu.open(menuPoint, entries, Edges.Bottom | Edges.Right);
    }

    screen: modelData
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Normal // stay inside the bars and dock
    exclusiveZone: 0

    WlrLayershell.namespace: "macos-widgets"
    WlrLayershell.layer: WlrLayer.Bottom
    // Keyboard only when there's a note to type in. Starting to edit takes it with a
    // moment of exclusive focus (clicking a Bottom-layer surface doesn't reliably hand
    // it the keyboard) — only until it arrives, as an exclusive layer gets all pointer
    // input — then on-demand so clicks elsewhere still go through. Editing ends on a press
    // outside the note or Esc (WidgetNotes). If the keyboard slips away with no such press,
    // it's taken back (twice at most). No HyprlandFocusGrab: it swallowed the first click
    // outside (e.g. the dock icon you meant to open). Only the display with that note asks.
    readonly property bool editingHere: Shared.noteEditingId !== "" && items.some(w => w.id === Shared.noteEditingId)
    property bool noteKeyArmed: false // false while editing: the exclusive grab
    property int noteRegrabs: 0
    // None unless editing: an on-demand layer keeps the keyboard after any desktop click,
    // and Hyprland then opened new windows (Open Terminal, dock launches) unfocused
    WlrLayershell.keyboardFocus: !editingHere ? WlrKeyboardFocus.None
        : !noteKeyArmed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    onEditingHereChanged: {
        noteRegrabs = 0;
        grabNoteKey();
    }

    function grabNoteKey(): void {
        noteKeyArmed = false;
        if (editingHere)
            armNoteKey.restart();
    }

    // never hold the exclusive grab longer than this, even if focus isn't reported
    Timer {
        id: armNoteKey

        interval: 300
        onTriggered: desk.noteKeyArmed = true
    }

    Item {
        id: keyProbe

        readonly property bool active: Window.active

        onActiveChanged: {
            if (active && desk.editingHere && !desk.noteKeyArmed) {
                armNoteKey.stop();
                desk.noteKeyArmed = true;
            } else if (!active && desk.editingHere) {
                keyLost.restart();
            }
        }
    }

    // a press outside (custom>>macdrag over IPC) may land just after the keyboard moves:
    // wait for it before taking the keyboard back
    Timer {
        id: keyLost

        interval: 150
        onTriggered: {
            if (!desk.editingHere || keyProbe.active)
                return;
            // never change keyboard focus while a button is down: the release got lost
            if (Shared.windowDrag) {
                keyLost.restart();
                return;
            }
            if (desk.noteRegrabs++ < 2)
                desk.grabNoteKey();
            else
                Shared.stopNoteEditing();
        }
    }

    // add requests from the gallery go to the display you're on
    Connections {
        target: Shared

        // dropped from the gallery: onto a same-size widget → joins its stack;
        // elsewhere → placed there (snapped), or the nearest free spot if taken
        function onPlaceWidget(type: string, size: string, screen: string, sx: real, sy: real): void {
            if (screen !== desk.modelData.name)
                return;
            const w = WidgetTypes.width(size), h = WidgetTypes.height(size);
            const x = sx - desk.modelData.x - (desk.reserved[0] ?? 0);
            const y = sy - desk.modelData.y - (desk.reserved[1] ?? 0);
            const target = desk.stackTargetAt(x + w / 2, y + h / 2, size, "");
            if (target) {
                const id = Config.addWidget(type, size, desk.modelData.name, 0, 0);
                Config.stackOnto(id, target);
                return;
            }
            const nx = WidgetTypes.snap(x, w, desk.width, true);
            const ny = WidgetTypes.snap(y, h, desk.height, false);
            const spot = desk.overlaps(nx, ny, w, h, "") ? desk.freeSpot(size, "") : { x: nx, y: ny };
            Config.addWidget(type, size, desk.modelData.name, spot.x, spot.y);
        }

        function onAddWidget(type: string, size: string): void {
            if ((Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) !== desk.modelData.name)
                return;
            const spot = desk.freeSpot(size, "");
            Config.addWidget(type, size, desk.modelData.name, spot.x, spot.y);
        }
    }

    GlassMenu {
        id: menu
    }

    Item {
        id: menuPoint

        width: 1
        height: 1
    }

    // empty desktop: right-click menu; left-click ends note editing
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => {
            desk.contentItem.forceActiveFocus();
            if (m.button !== Qt.RightButton)
                return;
            desk.openMenu(m.x, m.y, [
                { label: "Open Terminal", action: () => Quickshell.execDetached(["foot", "-D", Quickshell.env("HOME")]) },
                { separator: true },
                { label: "Change Wallpaper…", action: () => Shared.wallpaperOpen = true },
                { label: "Edit Widgets…", action: () => Shared.widgetEdit = true },
                { separator: true },
                { label: "Widgets", submenu: [
                    { label: Config.widgetsEnabled ? "Hide Widgets" : "Show Widgets", action: () => Config.setWidgets("enabled", !Config.widgetsEnabled) },
                    { label: "Frosted Glass", checked: Config.widgetsGlass, action: () => Config.setWidgets("glass", !Config.widgetsGlass) },
                    { separator: true },
                    { header: "Dim Widgets" },
                    { label: "Automatically", checked: Config.widgetsDim === "auto", action: () => Config.setWidgets("dim", "auto") },
                    { label: "Always", checked: Config.widgetsDim === "always", action: () => Config.setWidgets("dim", "always") },
                    { label: "Never", checked: Config.widgetsDim === "never", action: () => Config.setWidgets("dim", "never") }
                ] },
                { label: "Display", submenu: [
                    { header: "Night Shift" + (NightShift.installed ? "" : " (install hyprsunset)") },
                    { label: "Automatically", checked: Config.nightShift === "auto", action: () => Config.setNightShift("auto") },
                    { label: "On", checked: Config.nightShift === "on", action: () => Config.setNightShift("on") },
                    { label: "Off", checked: Config.nightShift === "off", action: () => Config.setNightShift("off") }
                ] },
                { label: "Units & Time", submenu: [
                    { label: "Show Temperatures in °F", checked: Config.tempUnit === "F", action: () => Config.setWidgets("temperatureUnit", Config.tempUnit === "F" ? "C" : "F") },
                    { label: "24-Hour Time", checked: Config.clock24, action: () => Config.setWidgets("clock24h", !Config.clock24) }
                ] },
                { separator: true },
                { label: "Desktop Settings…", action: () => { Shared.settingsPage = "desktop"; Shared.settingsOpen = true; } } // the raw file: dock menu → Edit Settings File…
            ]);
        }
    }

    Repeater {
        model: ScriptModel {
            values: desk.groups
            objectProp: "id"
        }

        WidgetCard {
            desk: desk
        }
    }
}
