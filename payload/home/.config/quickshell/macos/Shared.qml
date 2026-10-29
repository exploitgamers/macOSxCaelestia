pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    // A true fullscreen window (Hyprland mode 2, F11 or app-requested) on the desktop shown on `screen`.
    // Uses the live Wayland toplevel flag + workspace id + monitor by name: the old monitorFor()/
    // lastIpcObject.fullscreen path went stale after a monitor hotplug and kept the dock over fullscreen
    // windows. Maximised (mode 1) windows are not fullscreen here; Alt+Tab-minimised ones are on
    // special:minimized, not the shown desktop. A special desktop shown over it (special:communication,
    // where games like Sober land) counts too: Quickshell doesn't track it, so read lastIpcObject.
    function fullscreenOn(screen: var): bool {
        return fullscreenMatching(screen, /./);
    }

    // games keep their screen edges: the dock's and the fullscreen title bar's hover strips took the
    // pointer from a game whose free c‍ursor reached the edge (same list as GAME_CLASSES in hypr-qol.lua)
    readonly property var gameApps: /^org\.vinegarhq\.Sober$|^steam_app_|^gamescope$/
    function gameFullscreenOn(screen: var): bool {
        return fullscreenMatching(screen, gameApps);
    }

    function fullscreenMatching(screen: var, apps: var): bool {
        const mon = Hyprland.monitors.values.find(m => m.name === screen?.name);
        const id = mon?.activeWorkspace?.id;
        const special = mon?.lastIpcObject?.specialWorkspace?.name ?? "";
        return id !== undefined && Hyprland.toplevels.values.some(h =>
            (h.workspace?.id === id || (special !== "" && h.workspace?.name === special)) && (h.wayland?.fullscreen ?? false)
            && apps.test(h.wayland?.appId ?? ""));
    }

    // Now Playing click: bring the player's app forward — its window if it has
    // one (restored if minimised; MPRIS raise() often doesn't work, e.g. Spotify),
    // else MPRIS raise, else launch it. With nothing playing it opens Spotify.
    function openPlayer(player: var): void {
        const id = (player?.desktopEntry || "spotify").replace(/\.desktop$/, "");
        const names = [id, player?.identity ?? ""].map(n => n.toLowerCase()).filter(n => n);
        const win = Hyprland.toplevels.values.find(t =>
            names.includes((t.wayland?.appId ?? t.lastIpcObject?.class ?? "").toLowerCase()));
        if (win) {
            const addr = "0x" + String(win.address).replace(/^0x/, "");
            if (win.workspace?.name === "special:minimized")
                Quickshell.execDetached(["hyprctl", "eval", `mac_restore("${addr}")`]);
            else
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:${addr}" })`);
            return;
        }
        if (player?.canRaise) {
            player.raise();
            return;
        }
        (DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id))?.execute();
    }

    // Split stack: where each widget leaving a stack starts its slide (widget id → { x, y })
    property var splitOrigin: ({})

    // the desktop note being typed in ("" = none): its display's widgets layer takes the
    // keyboard (DesktopWidgets) until a press outside the note or Esc (WidgetNotes)
    property string noteEditingId: ""
    signal stopNoteEditing()
    // the desktop menu opened: build the gallery and wallpaper browser in the background (shell.qml)
    signal prewarm()

    property bool musicPinned: false // toggled by `qs -c macos ipc call music toggle`
    // height of the dock plate's top above the screen bottom (8 px lift + plate). Panels that
    // sit above the dock use it instead of the dock's exclusive zone, which is 0 with a
    // fullscreen window or auto-hide (the launcher then dropped onto the dock)
    readonly property int dockTop: Config.iconSize + 24
    property bool launcherOpen: false // dock Apps button / `qs -c macos ipc call launcher toggle`
    // When the launcher last closed. Clicking the Apps button while the launcher
    // is open first closes it via its click-outside grab, then the same click
    // reaches the button — which must not reopen it.
    property real launcherClosedAt: 0
    onLauncherOpenChanged: if (!launcherOpen) launcherClosedAt = Date.now()

    function toggleLauncher(): void {
        if (!launcherOpen && Date.now() - launcherClosedAt < 300)
            return; // this click already closed it
        launcherOpen = !launcherOpen;
    }
    property string launcherQuery: "" // consumed when the launcher opens
    // windows zoomed with the green button (custom>>maczoom>>addr,… from hypr-qol.lua),
    // addresses without "0x": the dock auto-hides while one is on the shown desktop
    property var zoomedWindows: []
    // a restarted shell forgot them: ask again once the Hyprland event socket is up (at load it missed the reply)
    property Timer zoomAsk: Timer {
        running: true
        interval: 1500
        onTriggered: Quickshell.execDetached(["hyprctl", "eval", "mac_zoom_announce()"])
    }
    property Connections hyprEvents: Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "closewindow") {
                // a window closed (red light, Super+Q, app quit): the Apps launcher goes too
                Shared.launcherOpen = false;
                const a = event.data.replace(/^0x/, "");
                if (Shared.zoomedWindows.includes(a))
                    Shared.zoomedWindows = Shared.zoomedWindows.filter(z => z !== a);
            } else if (event.name === "custom" && event.data.startsWith("maczoom>>")) {
                Shared.zoomedWindows = event.data.slice(9).split(",").filter(a => a).map(a => a.replace(/^0x/, ""));
            } else if (event.name === "fullscreen") {
                // keeps lastIpcObject.fullscreen fresh (Quickshell only refreshes workspaces on this event)
                Hyprland.refreshToplevels();
            } else if (event.name === "activespecialv2") {
                // a special desktop opened/closed: refresh lastIpcObject.specialWorkspace for fullscreenOn
                Hyprland.refreshMonitors();
            }
        }
    }
    property var wallhavenCache: ({}) // WallpaperBrowser: collection key → { at, st } (first page)
    // Left mouse button held (Hyprland emits custom>>macdrag>>1/0, see hypr-qol.lua):
    // edge pop-outs and dock zoom stay quiet while a window is being dragged
    property bool windowDrag: false
    // Edit Widgets mode: gallery open, remove buttons on the desktop widgets
    property bool widgetEdit: false

    // Choose Profile Picture…: copies the picked image to ~/.face (used by the
    // Profile widget and Caelestia's lock screen); faceVersion makes images reload
    property int faceVersion: 0
    function chooseProfilePicture(): void {
        facePicker.running = true;
    }
    property Process facePicker: Process {
        command: ["sh", "-c", "f=$(kdialog --title 'Choose Profile Picture' --getopenfilename \"$HOME/Pictures\" 'image/png image/jpeg image/webp') && [ -n \"$f\" ] && cp -f \"$f\" \"$HOME/.face\""]
        onExited: code => { if (code === 0) faceVersion++; }
    }
    // some display's desktop widgets are actually visible (no windows over them,
    // widgets shown) — per-second widget updates pause otherwise (idle CPU).
    // A binding: set from DesktopWidgets.onLiveChanged it raced the deskWindows list at start-up
    // and stayed false (no second hand) until the next workspace switch.
    readonly property bool widgetsLive: deskWindows.some(d => d.live)
    // edge-snapping preview target while dragging a window ({ x, y, w, h } or null)
    property var snapRect: null
    // = title bars' height (hypr-qol.lua mac_bar_height)
    readonly property int titleBarHeight: 28
    // Desktop Settings window (Settings.qml)
    property bool settingsOpen: false
    property string settingsPage: "appearance"
    // Hyprland's game mode (custom>>macgame>>1|0 from hypr-qol.lua)
    property bool gameMode: false
    // a title-bar drag got going (custom>>macgrab>>addr,x,y): grab ripple + the picker's capture
    property string grabAddr: ""
    property real grabX: 0
    property real grabY: 0
    signal grabbed()
    // a window is being dragged by its title bar (macgrab … macdrag>>0): surfaces above
    // windows take no input then — the title-bar plugin drops a release that lands on
    // one, and the drag never ends
    property bool titleDrag: false
    // drag a window onto the top bar's desktops → desktop picker (DesktopDropPicker.qml)
    property bool deskDragOpen: false
    property string deskDragAddr: ""
    property real deskDragX: 0
    property real deskDragY: 0
    property var deskDragRect: [0, 0, 0, 0] // the window when the picker opened (x, y, w, h incl. title bar)
    property string deskDragHow: "" // how it closed: "cancel" | "drop"
    // when a button/row inside a desktop widget last handled a tap — the card
    // underneath then skips its own click (cycle stack / open app)
    property real widgetTapAt: 0
    // Edit Stack sheet (StackEditor.qml): which stack, on which display; "" = closed
    property string editStackKey: ""
    property string editStackScreen: ""
    // when each stack was last cycled by hand ({ key: ms }) — Smart Rotate waits after that
    property var stackTouched: ({})
    function touchStack(key: string): void {
        const t = Object.assign({}, stackTouched);
        t[key] = Date.now();
        stackTouched = t;
    }
    // Spotlight (SUPER+Space)
    property bool spotlightOpen: false
    property bool overviewOpen: false // Mission Control-style overview (Overview.qml)
    property bool wallpaperOpen: false // WallpaperBrowser.qml
    // Caelestia's wallpaper reveal just started (custom>>macwall>>ms) — DesktopWidgets syncs to it
    signal wallpaperReveal(int ms)
    // Alt+Tab switcher / SUPER+Tab desktop indicator (events from hypr-qol.lua)
    signal appSwitcher(var addresses, int index)
    signal appSwitcherHide()
    signal desktopChanged(int current, var desktops)
    signal desktopSwitcher(var desks, int index)
    signal desktopSwitcherHide()
    property var debugCards: [] // WidgetCard items (diagnostics: ipc widgets layers)
    property string spotlightQuery: "" // consumed when Spotlight opens
    // desktop widget layers (DesktopWidgets.qml), so the gallery's focus grab
    // can include them: clicking the desktop while editing doesn't close it
    property list<QtObject> deskWindows: []
    // a title-bar click asked for the window menu (WindowMenu.qml)
    signal windowMenu(string address, real x, real y, bool floating, bool pinned)
    // gallery → the desktop of the focused display
    signal addWidget(string type, string size)
    // gallery drag-and-drop: drop at (x, y) in screen coordinates on a display
    signal placeWidget(string type, string size, string screen, real x, real y)
}
