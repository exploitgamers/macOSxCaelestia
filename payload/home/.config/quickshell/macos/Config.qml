pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// All dock/widget settings live in ~/.config/caelestia/macos.json.
// Edit that file (changes apply live) or use the right-click menus on the
// docks and the Now Playing card, which write back to the same file.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/caelestia/macos.json"

    // ── Bottom dock ─────────────────────────────────────────────
    readonly property var pinned: s.dock.pinned
    readonly property int iconSize: s.dock.iconSize
    readonly property real magnification: s.dock.magnification
    readonly property bool bottomAutoHide: s.dock.autoHide
    readonly property bool launchpad: s.dock.launchpad

    // ── Apps launcher (dock's Apps button) ──────────────────────
    readonly property var launcherPinned: s.launcher.pinned

    function isLauncherPinned(id: string): bool {
        return s.launcher.pinned.some(p => p.toLowerCase() === id.toLowerCase());
    }

    function toggleLauncherPin(id: string): void {
        s.launcher.pinned = isLauncherPinned(id)
            ? s.launcher.pinned.filter(p => p.toLowerCase() !== id.toLowerCase())
            : [...s.launcher.pinned, id];
    }

    // ── Windows (read by Hyprland, ~/.config/caelestia/hypr-qol.lua) ──
    readonly property bool floatingWindows: s.windows.floating

    // ── Now Playing drop-down ───────────────────────────────────
    readonly property bool musicWidget: s.nowPlaying.mode !== "off"
    readonly property bool musicAlways: s.nowPlaying.mode === "always"
    readonly property string musicMode: s.nowPlaying.mode
    readonly property int musicShowMs: s.nowPlaying.seconds * 1000

    // ── Desktop widgets (DesktopWidgets.qml / WidgetGallery.qml) ──
    readonly property string nightShift: s.nightShift
    function setNightShift(mode: string): void {
        s.nightShift = mode;
    }
    readonly property var hotCorners: ({ topLeft: s.hotCorners.topLeft, topRight: s.hotCorners.topRight, bottomLeft: s.hotCorners.bottomLeft, bottomRight: s.hotCorners.bottomRight })
    readonly property bool widgetsEnabled: s.widgets.enabled
    readonly property var widgetItems: s.widgets.items
    readonly property string weatherLocation: s.widgets.weatherLocation
    readonly property string tempUnit: s.widgets.temperatureUnit
    readonly property bool clock24: s.widgets.clock24h
    readonly property bool widgetsGlass: s.widgets.glass
    readonly property string widgetsDim: s.widgets.dim
    // window menu on a single click of a title bar (WindowMenu.qml): "left", "right" or "off"
    readonly property string titlebarMenu: s.windows.titlebarMenu

    function addWidget(type: string, size: string, screen: string, x: real, y: real): string {
        const id = type + "-" + Date.now().toString(36);
        s.widgets.items = [...s.widgets.items, { id: id, type: type, size: size, screen: screen, x: x, y: y }];
        return id;
    }

    function updateWidget(id: string, changes: var): void {
        s.widgets.items = s.widgets.items.map(w => w.id === id ? Object.assign({}, w, changes) : w);
    }

    function removeWidget(id: string): void {
        s.widgets.items = s.widgets.items.filter(w => w.id !== id);
    }

    // ── Per-display places: x/y is the spot on the widget's own display (`screen`; "" = the
    // home one, DesktopWidgets.homeScreen). Moved on another display (its own is unplugged, or "" shown elsewhere), the
    // spot goes to pos[that display] instead, so each display keeps its layout across hot-plugs.
    function placeOn(w: var, screen: string): var {
        const p = w.screen === screen ? null : (w.pos ?? {})[screen];
        return p ?? { x: w.x, y: w.y };
    }

    function placeChanges(w: var, screen: string, x: real, y: real): var {
        if (w.screen === screen)
            return { x: x, y: y };
        const pos = Object.assign({}, w.pos ?? {});
        pos[screen] = { x: x, y: y };
        return { pos: pos };
    }

    // move a stack (or single widget) to (x, y) as seen on display `screen`
    function moveGroup(key: string, screen: string, x: real, y: real, extra: var): void {
        s.widgets.items = s.widgets.items.map(w => stackKey(w) === key ? Object.assign({}, w, placeChanges(w, screen, x, y), extra ?? {}) : w);
    }

    // ── Stacks: widgets sharing a "stack" key sit in one spot; lowest "order" is in front
    function stackKey(w: var): string {
        return w.stack || w.id;
    }

    // apply changes to every widget in a stack (or the single widget)
    function updateGroup(key: string, changes: var): void {
        s.widgets.items = s.widgets.items.map(w => stackKey(w) === key ? Object.assign({}, w, changes) : w);
    }

    // drop stack/widget `src` onto `dst`: src's widgets join dst, in front
    function stackOnto(src: string, dst: string): void {
        const target = s.widgets.items.filter(w => stackKey(w) === dst);
        if (!target.length || src === dst)
            return;
        const t = target[0];
        const front = Math.min(...target.map(w => w.order ?? 0));
        const moving = s.widgets.items.filter(w => stackKey(w) === src).sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
        s.widgets.items = s.widgets.items.map(w => {
            if (stackKey(w) === dst)
                return Object.assign({}, w, { stack: dst });
            const i = moving.findIndex(m => m.id === w.id);
            return i < 0 ? w : Object.assign({}, w, { stack: dst, order: front - moving.length + i, x: t.x, y: t.y, pos: t.pos ?? {}, size: t.size, screen: t.screen });
        });
    }

    // dir 1: front widget goes to the back; dir -1: back one comes to the front
    function cycleStack(key: string, dir: int): void {
        const members = s.widgets.items.filter(w => stackKey(w) === key).sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
        if (members.length < 2)
            return;
        const moved = dir > 0 ? members[0] : members[members.length - 1];
        const order = dir > 0 ? (members[members.length - 1].order ?? 0) + 1 : (members[0].order ?? 0) - 1;
        updateWidget(moved.id, { order: order });
    }

    // take one widget out of its stack, to (x, y); a stack of one stops being a stack
    function unstack(id: string, x: real, y: real, screen: string): void {
        const w = s.widgets.items.find(i => i.id === id);
        if (!w?.stack)
            return;
        const key = w.stack;
        let items = s.widgets.items.map(i => i.id === id ? Object.assign({}, i, { stack: "", order: 0 }, placeChanges(i, screen, x, y)) : i);
        const rest = items.filter(i => i.stack === key);
        if (rest.length === 1)
            items = items.map(i => i.id === rest[0].id ? Object.assign({}, i, { stack: "", order: 0 }) : i);
        s.widgets.items = items;
    }

    // Split stack: the widgets behind the front one go to `spots` (in order), in one write.
    // The front one keeps the stack key, so its card stays as it is (no blink); one whose id
    // is the key gets a key of its own, or it would group with the front again.
    function splitStack(key: string, spots: var, screen: string): void {
        const rest = s.widgets.items.filter(w => stackKey(w) === key).sort((a, b) => (a.order ?? 0) - (b.order ?? 0)).slice(1).map(w => w.id);
        s.widgets.items = s.widgets.items.map(w => {
            const i = rest.indexOf(w.id);
            return i < 0 ? w : Object.assign({}, w, { stack: w.id === key ? "s-" + w.id : "", order: 0 }, placeChanges(w, screen, spots[i].x, spots[i].y));
        });
    }

    // Edit Stack: put the stack in this order (ids, front first)
    function setStackOrder(key: string, ids: var): void {
        s.widgets.items = s.widgets.items.map(w => {
            const i = ids.indexOf(w.id);
            return stackKey(w) === key && i >= 0 ? Object.assign({}, w, { order: i }) : w;
        });
    }

    function smartRotate(key: string): bool {
        return s.widgets.items.some(w => stackKey(w) === key && w.smartRotate === true);
    }

    function setSmartRotate(key: string, on: bool): void {
        updateGroup(key, { smartRotate: on });
    }

    // bring one widget of a stack to the front
    function bringToFront(id: string): void {
        const w = s.widgets.items.find(i => i.id === id);
        if (!w)
            return;
        const key = stackKey(w);
        const front = Math.min(...s.widgets.items.filter(i => stackKey(i) === key).map(i => i.order ?? 0));
        if ((w.order ?? 0) !== front)
            updateWidget(id, { order: front - 1 });
    }

    // removing a stack's key widget: hand the key to the next one so the stack survives
    function removeFromStack(id: string): void {
        const w = s.widgets.items.find(i => i.id === id);
        removeWidget(id);
        if (!w?.stack)
            return;
        const rest = s.widgets.items.filter(i => i.stack === w.stack);
        if (rest.length === 1)
            updateWidget(rest[0].id, { stack: "", order: 0 });
    }

    // ── Per-app volumes (AppVolumes.qml applies them; Settings → Sound) ──
    readonly property var appVolumes: s.sound.appVolumes

    function setAppVolume(app: string, volume: real): void {
        const v = Object.assign({}, s.sound.appVolumes);
        v[app] = Math.round(volume * 100) / 100;
        s.sound.appVolumes = v;
    }

    function forgetAppVolume(app: string): void {
        const v = Object.assign({}, s.sound.appVolumes);
        delete v[app];
        s.sound.appVolumes = v;
    }

    // ── Keyboard shortcuts changed in Settings → Keyboard: kb var name → "SUPER + X"
    // ("" = none). hypr-vars.lua reads them, so they apply on a Hyprland reload.
    readonly property var keybinds: s.keybinds

    // combo null = back to the default
    function setKeybind(name: string, combo: var): void {
        const k = Object.assign({}, s.keybinds);
        if (combo === null)
            delete k[name];
        else
            k[name] = combo;
        s.keybinds = k;
        root._writing = true; // our own write: don't reload it back
        file.writeAdapter(); // now, before the reload reads it
        echoGuard.restart();
        reloadTimer.restart();
    }

    Timer {
        id: reloadTimer

        interval: 300
        onTriggered: Quickshell.execDetached(["hyprctl", "reload"])
    }

    // any other setting: Config.set("hotCorners", "topLeft", "launcher") (Settings.qml)
    function set(section: string, key: string, value: var): void {
        s[section][key] = value;
    }

    function setWidgets(key: string, value: var): void {
        s.widgets[key] = value;
    }

    // ── Motion (Apple defaults: critically damped, no overshoot) ──
    // Bounce is reserved for momentum, i.e. the dock's launch hop.
    readonly property real springResponse: s.motion.response
    readonly property real springDamping: s.motion.dampingRatio

    // Reduced motion follows the desktop "enable animations" setting
    // (game mode turns it off too). Slides become instant; fades remain.
    property bool reducedMotion: false

    // ── Mutations used by the right-click menus ─────────────────
    function isPinned(id: string): bool {
        return s.dock.pinned.some(p => p.toLowerCase() === id.toLowerCase());
    }

    function pin(id: string): void {
        if (!isPinned(id))
            s.dock.pinned = [...s.dock.pinned, id];
    }

    function unpin(id: string): void {
        s.dock.pinned = s.dock.pinned.filter(p => p.toLowerCase() !== id.toLowerCase());
    }

    function movePinnedTo(id: string, to: int): void {
        const list = s.dock.pinned.filter(p => p.toLowerCase() !== id.toLowerCase());
        list.splice(Math.max(0, Math.min(to, list.length)), 0, id);
        s.dock.pinned = list;
    }

    function pinAt(id: string, at: int): void {
        if (isPinned(id))
            return movePinnedTo(id, at);
        const list = [...s.dock.pinned];
        list.splice(Math.max(0, Math.min(at, list.length)), 0, id);
        s.dock.pinned = list;
    }

    function movePinned(id: string, delta: int): void {
        const list = [...s.dock.pinned];
        const i = list.findIndex(p => p.toLowerCase() === id.toLowerCase());
        const j = i + delta;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        [list[i], list[j]] = [list[j], list[i]];
        s.dock.pinned = list;
    }

    function setDock(key: string, value: var): void {
        s.dock[key] = value;
    }

    function setFloating(on: bool): void {
        s.windows.floating = on;
        // apply to Hyprland's window rule right away (hypr-window-defaults.lua)
        Quickshell.execDetached(["hyprctl", "eval", `mac_set_floating(${on})`]);
    }

    function setMusicMode(mode: string): void {
        s.nowPlaying.mode = mode;
    }

    function editFile(): void {
        Quickshell.execDetached(["xdg-open", path]);
    }

    property bool _writing: false

    // never lose a change still waiting for its batched save (shell restart / logout)
    Component.onDestruction: if (saveTimer.running) file.writeAdapter()

    Timer {
        id: saveTimer

        interval: 450
        onTriggered: {
            root._writing = true;
            file.writeAdapter();
            echoGuard.restart();
        }
    }

    Timer {
        id: echoGuard

        interval: 400
        onTriggered: root._writing = false
    }

    FileView {
        id: file

        path: root.path
        watchChanges: true
        // Our own write echoes back as a file change: ignore it, so a save doesn't
        // reload (and re-evaluate every widget binding) in the middle of an animation.
        onFileChanged: if (!root._writing) reload()
        // Saves are batched a moment after the last change (stack cycling, dragging),
        // once the motion is over. Settings apply in memory immediately.
        onAdapterUpdated: saveTimer.restart()
        // Write once after the first load so new default keys appear in the file
        // (guarded: writing triggers a reload, which must not write again)
        property bool filled: false
        onLoaded: {
            if (!filled) {
                filled = true;
                writeAdapter();
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter(); // first run: write the defaults
        }

        JsonAdapter {
            id: s

            property JsonObject dock: JsonObject {
                // Desktop-entry IDs (file names in /usr/share/applications, no .desktop)
                property list<string> pinned: ["thunar", "firefox", "foot", "codium", "equibop", "com.saivert.pwvucontrol"]
                property int iconSize: 48
                property real magnification: 1.55 // 1.0 disables hover zoom
                property bool autoHide: false
                property bool launchpad: true // "All apps" button at the start of the dock
            }

            property JsonObject launcher: JsonObject {
                // Favourites shown before you type; everything else appears when searching
                property list<string> pinned: ["firefox", "foot", "thunar", "codium", "equibop", "com.saivert.pwvucontrol", "btop", "org.pulseaudio.pavucontrol"]
            }

            property JsonObject windows: JsonObject {
                // macOS-style: new windows open floating & centred (drag title bar / edges)
                property bool floating: true
                property string titlebarMenu: "right" // right-click a title bar → window menu (like macOS)
            }

            property JsonObject nowPlaying: JsonObject {
                property string mode: "auto" // auto = drop down on track change, always, off
                property int seconds: 6
            }

            property JsonObject widgets: JsonObject {
                property bool enabled: true
                // { id, type, size: small|medium|large, screen, x, y } — x/y in pixels from the
                // top-left of the desktop area. Types: clock calendar weather battery system music notes
                property list<var> items: [
                    { id: "clock-1", type: "clock", size: "small", screen: "", x: 24, y: 24 },
                    { id: "calendar-1", type: "calendar", size: "small", screen: "", x: 210, y: 24 },
                    { id: "weather-1", type: "weather", size: "medium", screen: "", x: 24, y: 210 },
                    { id: "battery-1", type: "battery", size: "small", screen: "", x: 24, y: 396 },
                    { id: "system-1", type: "system", size: "small", screen: "", x: 210, y: 396 }
                ]
                property string weatherLocation: "" // "City" or "lat,lon"; empty = from your IP address
                property string temperatureUnit: "C" // C or F
                property bool clock24h: false
                property bool glass: true // frosted wallpaper behind widgets
                property string dim: "auto" // Sonoma: fade widgets while apps are open — auto, always, never
            }

            property string nightShift: "auto" // NightShift.qml: auto (sunset → sunrise), on, off

            property var keybinds: ({})

            property JsonObject sound: JsonObject {
                // app name (as Pipewire reports it) → volume 0–1, set whenever it starts playing
                property var appVolumes: ({})
            }

            // HotCorners.qml: launcher, showdesktop, lock, spotlight, widgets, none
            property JsonObject hotCorners: JsonObject {
                property string topLeft: "launcher"
                property string topRight: "none"
                property string bottomLeft: "lock"
                property string bottomRight: "showdesktop"
            }

            property JsonObject motion: JsonObject {
                property real response: 0.35    // seconds; lower = snappier
                property real dampingRatio: 1.0 // 1.0 = no overshoot, < 1 = bounce
            }
        }
    }

    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "enable-animations"]
        stdout: StdioCollector {
            onStreamFinished: root.reducedMotion = text.trim() === "false"
        }
    }

    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "enable-animations"]
        stdout: SplitParser {
            onRead: line => root.reducedMotion = line.trim().endsWith("false")
        }
    }
}
