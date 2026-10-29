pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// macOS-style bottom dock: Launchpad + pinned apps + running apps, hover
// magnification, drag to reorder / pin / remove, launch bounce, running
// indicators, name tooltips, right-click menus, spring reveal.
//
// All pointer input goes through one MouseArea on top (`input`). Icons never
// take hover themselves, so magnification tracks the pointer from whichever
// side it enters, and a press can turn into a drag without hand-off.
PanelWindow {
    id: win

    required property ShellScreen modelData

    readonly property int base: Config.iconSize
    // Even rhythm: 8px between icons and around the edge; the separator gets
    // the same breathing room on both sides
    readonly property int spacing: 8
    readonly property int pad: 8
    readonly property int sepWidth: 9
    readonly property real zoomRoom: base * (Config.magnification - 1)
    readonly property real step: base + spacing

    // the windows on the desktop shown on this screen, not the "active" toplevel or the workspace's
    // hasfullscreen flag: both stayed set after Alt+Tab hid a fullscreen game (minimised, still
    // fullscreen), which kept the dock hidden and its space unreserved
    readonly property bool fullscreenActive: Shared.fullscreenOn(modelData)
    readonly property bool hovered: input.containsMouse || dragging
    // Fullscreen apps: the dock hides and reveals from the bottom edge (like
    // macOS), drawn above the app on the Overlay layer.
    // zoomed/maximised windows keep the dock and its reserved space (user, 2026-10-17)
    readonly property bool autoHiding: Config.bottomAutoHide || fullscreenActive
    readonly property bool revealed: !autoHiding || hovered || edge.hovered || hideDelay.running || menu.shown || Shared.launcherOpen // the Apps button must stay reachable to close it

    // ── Model: [Launchpad] pinned… | running-but-unpinned… ────────────────
    function entryFor(id: string): var {
        return DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
    }

    // the app a window belongs to. Desktop Settings is a Quickshell window
    // (app id org.quickshell): count it as its own app, so it lights up its pinned
    // icon instead of showing up as an unknown app at the end of the dock
    function appOf(t: var): string {
        return t.appId === "org.quickshell" && t.title === "Desktop Settings" ? "desktop-settings" : t.appId;
    }

    function keyFor(appId: string): string {
        const e = DesktopEntries.heuristicLookup(appId);
        return (e?.id ?? appId).toLowerCase();
    }

    readonly property var items: {
        // Touch the app list so this re-evaluates once desktop entries finish
        // loading (byId/heuristicLookup aren't reactive on their own).
        void DesktopEntries.applications.values.length;
        const tops = ToplevelManager.toplevels.values;
        const out = [];
        const index = {};

        if (Config.launchpad)
            out.push({ kind: "launchpad", key: "__launchpad", windows: [] });

        for (const id of Config.pinned) {
            const e = entryFor(id);
            const key = (e?.id ?? id).toLowerCase();
            index[key] = out.length;
            out.push({ kind: "app", pinned: true, key: key, appId: id, entry: e, windows: [] });
        }

        let addedSep = false;
        for (const t of tops) {
            if (!t.appId)
                continue;
            const appId = appOf(t);
            const key = keyFor(appId);
            if (index[key] === undefined) {
                if (!addedSep && out.length > 0) {
                    out.push({ kind: "sep", key: "__sep", windows: [] });
                    addedSep = true;
                }
                index[key] = out.length;
                const e = DesktopEntries.heuristicLookup(appId);
                out.push({ kind: "app", pinned: false, key: key, appId: e?.id ?? appId, entry: e, windows: [] });
            }
            out[index[key]].windows.push(t);
        }

        // macOS: minimised windows sit at the right end, after a divider
        const minimised = tops.filter(t => Hyprland.toplevels.values.find(h => h.wayland === t)?.workspace?.name === "special:minimized");
        if (minimised.length > 0)
            out.push({ kind: "sep", key: "__sep_min", windows: [] });
        for (const t of minimised) {
            const h = Hyprland.toplevels.values.find(h => h.wayland === t);
            const e = t.appId ? DesktopEntries.heuristicLookup(appOf(t)) : null;
            out.push({ kind: "min", key: "__min_" + h.address, appId: e?.id ?? appOf(t), entry: e, windows: [], title: t.title,
                       address: "0x" + String(h.address).replace(/^0x/, "") });
        }
        return out;
    }

    readonly property int firstPinned: Config.launchpad ? 1 : 0
    readonly property int pinnedCount: Config.pinned.length

    // Unscaled slot centres; magnification and drop targets are computed
    // against these so zooming never feeds back into itself.
    readonly property var centres: {
        const c = [];
        let x = 0;
        for (const it of items) {
            const w = it.kind === "sep" ? sepWidth : base;
            c.push(x + w / 2);
            x += w + spacing;
        }
        return c;
    }
    readonly property real unscaledWidth: items.length ? centres[centres.length - 1] + (items[items.length - 1].kind === "sep" ? sepWidth : base) / 2 : 0

    // Pointer in unscaled-row coordinates
    property real pointer: -1000
    property int hoverIndex: -1

    // ── Drag state ───────────────────────────────────────────────────────
    property bool dragging: false
    property int dragFrom: -1
    property real dragDX: 0
    property real dragDY: 0
    readonly property bool removing: dragging && (items[dragFrom]?.pinned ?? false) && dragDY < -base * 1.3
    // Insertion index within the pinned list (0…pinnedCount) while dragging
    readonly property int dropAt: {
        if (!dragging)
            return -1;
        const fromPinned = items[dragFrom]?.pinned ?? false;
        const slots = fromPinned ? pinnedCount - 1 : pinnedCount;
        const first = centres[firstPinned] ?? 0;
        const raw = Math.round((pointer - first) / step);
        if (!fromPinned && (raw > pinnedCount || dragDY < -base * 1.3))
            return -1; // not over the pinned area: don't pin
        return Math.max(0, Math.min(slots, raw));
    }

    // How far slot i slides to make room for the dragged icon
    function shiftFor(i: int): real {
        if (!dragging || i === dragFrom || !(items[i]?.pinned ?? false))
            return 0;
        const p = i - firstPinned; // index in pinned list
        if (items[dragFrom].pinned) {
            const from = dragFrom - firstPinned;
            if (removing)
                return p > from ? -step : 0; // close the gap it leaves
            if (from < dropAt && p > from && p <= dropAt)
                return -step;
            if (from > dropAt && p >= dropAt && p < from)
                return step;
            return 0;
        }
        return dropAt >= 0 && p >= dropAt ? step : 0;
    }

    function slotAt(x: real, y: real): Item {
        const pt = input.mapToItem(row, x, y);
        const child = row.childAt(pt.x, row.height - 2);
        return child && child.slotIndex !== undefined ? child : null;
    }

    // Focus through Hyprland rather than an activation request: with
    // on_focus_under_fullscreen = 0 (hypr-qol.lua) activation requests are ignored
    // while another app is fullscreen, but a dock click should always switch.
    function focusWindow(w: var): void {
        const h = Hyprland.toplevels.values.find(t => t.wayland === w);
        if (!h) {
            w.activate();
            return;
        }
        const addr = String(h.address).startsWith("0x") ? h.address : "0x" + h.address;
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${addr}" })`);
        // focusing doesn't raise floating windows — bring it to the front too
        Hyprland.dispatch(`hl.dsp.window.alter_zorder({ mode = "top", window = "address:${addr}" })`);
    }

    function activate(i: int, button: int): void {
        const m = items[i];
        if (!m || m.kind === "sep")
            return;
        if (m.kind === "launchpad") {
            Shared.toggleLauncher();
            return;
        }
        if (m.kind === "min") { // a minimised window: bring it back
            Quickshell.execDetached(["hyprctl", "eval", `mac_restore("${m.address}")`]);
            return;
        }
        Shared.launcherOpen = false; // like Launchpad: picking a dock app closes it
        const wins = m.windows;
        if (button === Qt.MiddleButton || wins.length === 0) {
            const entry = m.entry ?? entryFor(m.appId);
            if (entry)
                entry.execute();
            else // no desktop entry: launch by id/command
                Quickshell.execDetached(["sh", "-c", 'gtk-launch "$1" 2>/dev/null || exec "$1"', "sh", m.appId]); // argv, never interpolate: app ids come from windows
            const slot = Array.prototype.find.call(row.children, c => c.slotIndex === i);
            slot?.bounce();
            return;
        }
        // Click an app's icon:
        //  · all its windows minimised → restore the latest one here, in front
        //  · its window is the one you're using (and it's the only one showing) → minimise it
        //  · otherwise → focus / cycle through its visible windows
        const hypr = w => Hyprland.toplevels.values.find(h => h.wayland === w);
        const addrOf = w => {
            const h = hypr(w);
            return h ? (String(h.address).startsWith("0x") ? h.address : "0x" + h.address) : "";
        };
        const isMin = w => hypr(w)?.workspace?.name === "special:minimized";
        const shown = wins.filter(w => !isMin(w));
        if (shown.length === 0) {
            const w = wins[wins.length - 1];
            addrOf(w) ? Quickshell.execDetached(["hyprctl", "eval", `mac_restore("${addrOf(w)}")`]) : w.activate();
            return;
        }
        const cur = shown.findIndex(w => w.activated);
        if (cur >= 0 && shown.length === 1 && addrOf(shown[0])) {
            Quickshell.execDetached(["hyprctl", "eval", `mac_minimize("${addrOf(shown[0])}")`]);
            return;
        }
        focusWindow(shown[(cur + 1) % shown.length]);
    }

    function finishDrag(commit: bool): void {
        const m = items[dragFrom];
        const rm = removing, at = dropAt, from = dragFrom - firstPinned;
        // end the drag before touching Config: the pin list rebuilds `items` at once, and with
        // dragging still set every slot's shiftFor() read a dragFrom past the shortened list
        // (TypeError at items[dragFrom].pinned when the only unpinned app was pinned)
        dragging = false;
        dragFrom = -1;
        dragDX = 0;
        dragDY = 0;
        if (!commit || m?.kind !== "app")
            return;
        if (rm)
            Config.unpin(m.appId);
        else if (m.pinned && at >= 0 && at !== from)
            Config.movePinnedTo(m.appId, at);
        else if (!m.pinned && at >= 0)
            Config.pinAt(m.appId, at);
    }

    // ── Motion ───────────────────────────────────────────────────────────
    // Zoom eases in/out (critically damped); per-icon magnification then
    // tracks the pointer 1:1. Zoom is off while dragging to keep slots steady.
    readonly property real zoom: zoomSpring.value

    Spring {
        id: zoomSpring

        target: input.containsMouse && !win.dragging && !Shared.windowDrag ? 1 : 0
        response: 0.22
        epsilon: 0.001
    }

    Spring {
        id: revealSpring

        target: win.revealed ? 0 : dock.height + 20
    }

    // ── Right-click menus ────────────────────────────────────────────────
    function appMenu(m: var): var {
        const id = m.entry?.id ?? m.appId;
        const pinned = Config.isPinned(id);
        const n = m.windows.length;
        // macOS: the app's open windows head its menu (the front one ticked); pick one to go to it
        const wins = m.windows.map(w => {
            const h = Hyprland.toplevels.values.find(t => t.wayland === w);
            const addr = h ? "0x" + String(h.address).replace(/^0x/, "") : "";
            const min = h?.workspace?.name === "special:minimized";
            const t = w.title || (m.entry?.name ?? m.appId);
            return { label: t.length > 34 ? t.slice(0, 33) + "…" : t, checked: w.activated,
                     action: () => min && addr ? Quickshell.execDetached(["hyprctl", "eval", `mac_restore("${addr}")`]) : focusWindow(w) };
        });
        return [
            { header: m.entry?.name ?? m.appId },
            ...wins,
            ...(n > 0 ? [{ separator: true }] : []),
            { label: "New Window", enabled: !!m.entry, action: () => m.entry.execute() },
            { separator: true },
            { label: "Keep in Dock", checked: pinned, action: () => pinned ? Config.unpin(id) : Config.pin(id) },
            { label: "Move Left", enabled: pinned, action: () => Config.movePinned(id, -1) },
            { label: "Move Right", enabled: pinned, action: () => Config.movePinned(id, 1) },
            { separator: true },
            { label: n > 1 ? `Quit (${n} windows)` : "Quit", enabled: n > 0, action: () => m.windows.forEach(w => w.close()) }
        ];
    }

    function dockMenu(): var {
        const size = Config.iconSize;
        return [
            { header: "Dock" },
            { label: "Automatically Hide", checked: Config.bottomAutoHide, action: () => Config.setDock("autoHide", !Config.bottomAutoHide) },
            { label: "Magnification", checked: Config.magnification > 1, action: () => Config.setDock("magnification", Config.magnification > 1 ? 1.0 : 1.55) },
            { label: "Show Apps Button", checked: Config.launchpad, action: () => Config.setDock("launchpad", !Config.launchpad) },
            { label: "Small Icons", checked: size < 44, action: () => Config.setDock("iconSize", 40) },
            { label: "Medium Icons", checked: size >= 44 && size < 56, action: () => Config.setDock("iconSize", 48) },
            { label: "Large Icons", checked: size >= 56, action: () => Config.setDock("iconSize", 60) },
            { separator: true },
            { header: "Windows" },
            { label: "Open New Windows Floating", checked: Config.floatingWindows, action: () => Config.setFloating(!Config.floatingWindows) },
            { separator: true },
            { header: "Now Playing" },
            { label: "Drop Down on Track Change", checked: Config.musicMode === "auto", action: () => Config.setMusicMode("auto") },
            { label: "Always Show While Playing", checked: Config.musicMode === "always", action: () => Config.setMusicMode("always") },
            { label: "Off", checked: Config.musicMode === "off", action: () => Config.setMusicMode("off") },
            { separator: true },
            { label: "Dock Settings…", action: () => { Shared.settingsPage = "desktop"; Shared.settingsOpen = true; } },
            { label: "Edit Settings File…", action: () => Config.editFile() }
        ];
    }

    GlassMenu {
        id: menu
    }

    // An app's menu hangs off the dock at rest, over its icon's unzoomed slot. Anchored to
    // the zoomed icon itself it floated ~40 px above the dock once the zoom let go.
    Item {
        id: menuSpot

        property int index: 0

        x: (win.width - win.unscaledWidth) / 2 + (win.centres[index] ?? 0) - width / 2
        y: win.height - 8 - dock.height // the plate's top edge, like the dock menu
        width: win.base
        height: 1
    }

    // ── Window ───────────────────────────────────────────────────────────
    screen: modelData
    color: "transparent"
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    // Head-room for zoomed icons, the name bubble and dragging an icon off
    implicitHeight: base + pad * 2 + zoomRoom + 48 + base * 1.8

    WlrLayershell.namespace: "macos-dock"
    // Always Overlay: on an empty workspace Caelestia widens its edge input zones,
    // and its panels window (Top layer) can end up stacked above the dock after a
    // fullscreen toggle — then it swallowed every dock click. Overlay is always
    // above Top, and is also needed to show over fullscreen apps.
    WlrLayershell.layer: WlrLayer.Overlay
    // the dock's plate plus its 8 px lift (+4): with the 4 px window gap, a window's content ends 8 px
    // above the plate — the same as below the top bar's pills (+11 left it 7, measured 2026-10-17)
    exclusiveZone: autoHiding ? 0 : base + pad * 2 + 12

    // no input while a window is dragged by its title bar (see Shared.titleDrag)
    mask: Region {
        item: Shared.titleDrag ? null : hitArea
        Region { item: Shared.titleDrag ? null : edgeStrip }
    }

    // Input region: the dock, plus head-room while hovered/dragging
    Item {
        id: hitArea

        x: dock.x - 4
        width: dock.width + 8
        // head-room above the dock while hovered: just the zoomed icons + 10 px (was 34),
        // so the zoom lets go as soon as the pointer moves up off the icons
        y: win.revealed ? dock.y - (win.hovered ? win.zoomRoom + 10 : 0) - (win.dragging ? win.base * 1.8 : 0) : win.height
        height: win.height - y
    }

    // 2px strip on the bottom edge reveals an auto-hidden dock
    Item {
        id: edgeStrip

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: win.autoHiding && !Shared.gameFullscreenOn(win.modelData) ? Math.max(dock.width, 400) : 0
        height: 2

        HoverHandler { id: edge }
    }

    Timer {
        id: hideDelay

        interval: 450
    }

    onHoveredChanged: if (!hovered) hideDelay.restart()

    // ── The dock itself ──────────────────────────────────────────────────
    Rectangle {
        id: dock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8 // the same gap from the screen edge as the top bar's pills
        width: row.width + win.pad * 2
        height: win.base + win.pad * 2
        radius: 20
        color: Theme.glass
        border.width: 1
        border.color: Theme.glassBorder
        Behavior on color { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }
        // off while magnified: restarted every frame it trailed the growing icons by ~8 px a side
        Behavior on width { enabled: !win.dragging && win.zoom === 0; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // Light catching the top edge of the glass
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - parent.radius * 2
            height: 1
            color: Theme.alpha(Theme.fg, 0.14)
        }

        transform: Translate { y: revealSpring.value }

        Row {
            id: row

            anchors.bottom: parent.bottom
            anchors.bottomMargin: win.pad
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: win.spacing

            Repeater {
                // ScriptModel keeps existing icons alive (no reload/flicker) and only
                // adds/removes what changed; `live` always reads the current data.
                model: ScriptModel {
                    values: win.items
                    objectProp: "key"
                }

                delegate: Item {
                    id: slot

                    required property var modelData
                    required property int index
                    readonly property var live: win.items[index] ?? modelData

                    readonly property int slotIndex: index
                    readonly property bool isSep: modelData.kind === "sep"
                    readonly property bool isLaunchpad: modelData.kind === "launchpad"
                    readonly property bool isDragged: win.dragging && win.dragFrom === index
                    readonly property real dist: win.pointer - (win.centres[index] ?? 0)
                    readonly property real sigma: win.base * 0.8 // how far the zoom spreads (was 1.15: too many neighbours grew)
                    readonly property real scale: isSep ? 1 : 1 + (Config.magnification - 1) * win.zoom * Math.exp(-(dist * dist) / (2 * sigma * sigma))
                    property real hop: 0

                    function bounce(): void {
                        if (!Config.reducedMotion) // reduced motion: no launch hop
                            bounceAnim.restart();
                    }

                    width: isSep ? win.sepWidth : win.base * scale
                    height: win.base * scale
                    anchors.bottom: parent.bottom
                    z: isDragged ? 10 : 0

                    // Others slide aside with a critically-damped spring;
                    // the dragged icon follows the pointer 1:1.
                    Spring {
                        id: shiftSpring

                        target: win.shiftFor(slot.index)
                        response: 0.28
                    }

                    transform: Translate {
                        x: slot.isDragged ? win.dragDX : shiftSpring.value
                        y: slot.isDragged ? Math.min(0, win.dragDY) : 0
                    }

                    // Separator
                    Rectangle {
                        visible: slot.isSep
                        anchors.centerIn: parent
                        width: 1
                        height: win.base * 0.8
                        color: Theme.alpha(Theme.fg, 0.25)
                    }

                    // round / odd-shaped icons get a squircle tile so they match
                    // WhiteSur's (IconTiles.qml); inset like WhiteSur's own padding
                    readonly property bool tiled: !slot.isSep && !slot.isLaunchpad && IconTiles.needsTile(slot.live.entry?.icon ?? "")

                    Rectangle {
                        visible: slot.tiled
                        x: parent.width * 0.06
                        y: parent.height * 0.06 - slot.hop
                        width: parent.width * 0.88
                        height: parent.height * 0.88
                        radius: width * 0.225
                        color: Theme.surfaceContainerHigh
                        border.width: 1
                        border.color: Theme.glassBorder
                        opacity: icon.opacity
                    }

                    // Icon
                    Image {
                        id: icon

                        visible: !slot.isSep
                        anchors.fill: parent
                        anchors.margins: slot.tiled ? parent.width * 0.15 : 0
                        anchors.bottomMargin: (slot.tiled ? parent.width * 0.15 : 0) + slot.hop
                        sourceSize.width: win.base * Config.magnification * 2
                        sourceSize.height: win.base * Config.magnification * 2
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        source: {
                            const name = slot.isLaunchpad ? "view-app-grid" : (slot.live.entry?.icon ?? slot.live.appId ?? "");
                            return Quickshell.iconPath(name, true) || Quickshell.iconPath("application-x-executable", true);
                        }
                        // Feedback on pointer-down; ghosted while being pulled off
                        opacity: win.removing && slot.isDragged ? 0.45 : input.pressed && input.pressIndex === slot.index && !win.dragging ? 0.62 : 1
                    }

                    // minimised window: small yellow badge, like the title-bar button
                    Rectangle {
                        visible: slot.live.kind === "min"
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: slot.hop
                        width: parent.width * 0.36
                        height: width
                        radius: width / 2
                        color: "#febc2e"
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.25)

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.5
                            height: Math.max(1.5, parent.width * 0.12)
                            radius: height / 2
                            color: Qt.rgba(0, 0, 0, 0.6)
                        }
                    }

                    // Launch hop: the one place a bounce is earned (momentum)
                    SequentialAnimation {
                        id: bounceAnim

                        loops: 2
                        NumberAnimation { target: slot; property: "hop"; to: win.base * 0.42; duration: 260; easing.type: Easing.OutQuad }
                        NumberAnimation { target: slot; property: "hop"; to: 0; duration: 300; easing.type: Easing.OutBounce }
                    }

                    // Name bubble (or "Remove" while pulling an icon off the dock)
                    Rectangle {
                        readonly property bool show: !menu.shown && !Shared.launcherOpen && (slot.isDragged ? win.removing : !win.dragging && win.hoverIndex === slot.index && !slot.isSep)

                        anchors.bottom: parent.top
                        anchors.bottomMargin: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: label.implicitWidth + 20
                        height: label.implicitHeight + 10 // 5 px top and bottom (was 4.5)
                        radius: 8
                        color: Theme.glassStrong
                        border.width: 1
                        border.color: Theme.glassBorder
                        opacity: show ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        Text {
                            id: label

                            anchors.centerIn: parent
                            textFormat: Text.PlainText // untrusted text: never parse markup
                            text: slot.isDragged ? "Remove" : slot.isLaunchpad ? "Apps" : slot.live.kind === "min" ? (slot.live.title || slot.live.entry?.name || "Window")
                                : (slot.live.entry?.name ?? slot.live.appId ?? "")
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            font.letterSpacing: 0.1
                        }
                    }

                    // Running indicator
                    Rectangle {
                        visible: !slot.isSep && slot.live.windows.length > 0
                        anchors.top: parent.bottom
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 4
                        height: 4
                        radius: 2
                        color: Theme.alpha(Theme.fg, 0.85)
                    }
                }
            }
        }
    }

    // ── Single input layer over the whole dock ───────────────────────────
    MouseArea {
        id: input

        property int pressIndex: -1
        property real pressX: 0
        property real pressY: 0

        anchors.fill: hitArea
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: win.dragging ? Qt.ClosedHandCursor : win.hoverIndex >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
        preventStealing: true
        z: 100

        function track(): void {
            win.pointer = x + mouseX - (win.width - win.unscaledWidth) / 2;
            if (!win.dragging) {
                const s = win.slotAt(mouseX, mouseY);
                win.hoverIndex = s && !Shared.windowDrag ? s.slotIndex : -1;
            }
        }

        onPositionChanged: {
            track();
            if (!pressed || pressedButtons !== Qt.LeftButton)
                return;
            const dx = mouseX - pressX;
            const dy = mouseY - pressY;
            if (!win.dragging) {
                const m = win.items[pressIndex];
                // ~8px hysteresis before a press becomes a drag
                if (m?.kind === "app" && Math.hypot(dx, dy) > 8) {
                    win.dragFrom = pressIndex;
                    win.dragging = true;
                }
            }
            if (win.dragging) {
                win.dragDX = dx;
                win.dragDY = dy;
            }
        }

        onContainsMouseChanged: if (containsMouse) track(); else win.hoverIndex = -1

        onPressed: event => {
            track();
            const s = win.slotAt(event.x, event.y);
            pressIndex = s ? s.slotIndex : -1;
            pressX = event.x;
            pressY = event.y;
        }

        onReleased: event => {
            if (win.dragging) {
                win.finishDrag(true);
                return;
            }
            const s = win.slotAt(event.x, event.y);
            if (!s || s.slotIndex !== pressIndex)
                return; // moved off the icon: cancel, like a real button
            const m = win.items[pressIndex];
            if (event.button === Qt.RightButton) {
                if (m.kind === "app") {
                    menuSpot.index = pressIndex;
                    menu.open(menuSpot, win.appMenu(m), Edges.Top);
                }
                else
                    menu.open(dock, win.dockMenu(), Edges.Top);
                return;
            }
            win.activate(pressIndex, event.button);
        }

        onCanceled: win.finishDrag(false) // the grab was taken away: drop the drag, don't pin/move/remove

        // Right-click on empty dock space
        onClicked: event => {
            if (event.button === Qt.RightButton && !win.slotAt(event.x, event.y))
                menu.open(dock, win.dockMenu(), Edges.Top);
        }
    }
}
