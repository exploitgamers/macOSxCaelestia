pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as C
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Desktop Settings — one macOS-style window for everything on this desktop
// (qs -c macos ipc call settings open; also "Desktop Settings" in the Apps launcher).
// Each control writes where its feature already reads from, so changes apply live:
//   macos.json (Config.qml) · Caelestia's shell.json · `caelestia scheme` ·
//   Hyprland (game mode, hypr-qol.lua) · gsettings (reduce motion) · powerprofilesctl
// Only exists while open (LazyLoader).
LazyLoader {
    id: root

    active: Shared.settingsOpen

    // ── the window ───────────────────────────────────────────────────
    FloatingWindow {
        id: win

        readonly property var pages: [
            { id: "wifi", name: "Wi-Fi", icon: "wifi", color: "blue" },
            { id: "bluetooth", name: "Bluetooth", icon: "bluetooth", color: "blue" },
            { id: "sound", name: "Sound", icon: "volume_up", color: "pink" },
            { id: "appearance", name: "Appearance", icon: "contrast", color: "#2c2c2e" },
            { id: "desktop", name: "Desktop & Dock", icon: "dock_to_bottom", color: "#2c2c2e" },
            { id: "widgets", name: "Widgets", icon: "widgets", color: "blue" },
            { id: "windows", name: "Windows", icon: "web_asset", color: "cyan" },
            { id: "menubar", name: "Menu Bar", icon: "toolbar", color: "gray" },
            { id: "displays", name: "Displays & Battery", icon: "brightness_6", color: "blue" },
            { id: "keyboard", name: "Keyboard", icon: "keyboard", color: "gray" },
            { id: "maintenance", name: "Maintenance", icon: "build", color: "gray" },
            { id: "more", name: "Other Settings", icon: "apps", color: "gray" }
        ]
        readonly property var page: pages.find(p => p.id === Shared.settingsPage) ?? pages[0]

        title: "Desktop Settings"
        implicitWidth: 880
        implicitHeight: 620
        minimumSize: Qt.size(720, 480)
        color: Theme.surface
        visible: true
        onClosed: Shared.settingsOpen = false
        onVisibleChanged: if (!visible) Shared.settingsOpen = false

        // ── state that lives outside macos.json ──────────────────────
        // Caelestia's shell.json: kept whole, so options this window doesn't show survive
        FileView {
            id: cael

            property var data: ({})

            function get(keys: var, fallback: var): var {
                let o = data;
                for (const k of keys)
                    o = o?.[k];
                return o ?? fallback;
            }

            function set(keys: var, value: var): void {
                const d = JSON.parse(JSON.stringify(data));
                let o = d;
                for (const k of keys.slice(0, -1)) {
                    if (typeof o[k] !== "object" || o[k] === null)
                        o[k] = {};
                    o = o[k];
                }
                o[keys[keys.length - 1]] = value;
                data = d;
                setText(JSON.stringify(d, null, 4) + "\n");
            }

            path: Quickshell.env("HOME") + "/.config/caelestia/shell.json"
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                try {
                    data = JSON.parse(text());
                } catch (e) {
                    console.warn("settings: shell.json isn't valid JSON, not touching it:", e);
                }
            }
        }

        // colour scheme (caelestia scheme get/set)
        property string schemeMode: "dark"
        property string schemeVariant: "tonalspot"

        Process {
            running: true
            command: ["caelestia", "scheme", "get"]
            stdout: StdioCollector {
                onStreamFinished: {
                    win.schemeMode = (text.match(/Mode:\s*(\w+)/) ?? [])[1] ?? win.schemeMode;
                    win.schemeVariant = (text.match(/Variant:\s*(\w+)/) ?? [])[1] ?? win.schemeVariant;
                }
            }
        }

        function setScheme(flag: string, value: string): void {
            if (flag === "-m")
                schemeMode = value;
            else
                schemeVariant = value;
            Quickshell.execDetached(["caelestia", "scheme", "set", flag, value]);
        }

        // GTK theme, icon and cursor themes: what's installed and what's in use
        property var gtkThemes: []
        property var iconThemes: []
        property var cursorThemes: []
        property string gtkTheme: ""
        property string iconTheme: ""
        property string cursorTheme: ""

        Process {
            running: true
            command: ["sh", "-c", "for k in gtk-theme icon-theme cursor-theme; do echo \"$k=$(gsettings get org.gnome.desktop.interface $k | tr -d \"'\")\"; done;"
                + " for d in /usr/share/themes/* ~/.themes/* ~/.local/share/themes/*; do [ -d \"$d/gtk-3.0\" ] && echo \"g:${d##*/}\"; done;"
                + " for d in /usr/share/icons/* ~/.icons/* ~/.local/share/icons/*; do [ -f \"$d/index.theme\" ] || continue;"
                + " [ -d \"$d/cursors\" ] && echo \"c:${d##*/}\"; grep -q '^Directories=' \"$d/index.theme\" && echo \"i:${d##*/}\"; done; true"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const lines = text.split("\n");
                    const pick = p => [...new Set(lines.filter(l => l.startsWith(p)).map(l => l.slice(p.length)))].sort((a, b) => a.localeCompare(b));
                    const cur = k => (lines.find(l => l.startsWith(k + "=")) ?? "").slice(k.length + 1);
                    win.gtkThemes = pick("g:");
                    win.iconThemes = pick("i:").filter(t => t !== "hicolor" && t !== "default");
                    win.cursorThemes = pick("c:").filter(t => t !== "default");
                    win.gtkTheme = cur("gtk-theme");
                    win.iconTheme = cur("icon-theme");
                    win.cursorTheme = cur("cursor-theme");
                }
            }
        }

        function setIconTheme(t: string): void {
            iconTheme = t;
            // GTK apps read gsettings; Qt apps (and this shell) read qtengine's config
            Quickshell.execDetached(["sh", "-c", "gsettings set org.gnome.desktop.interface icon-theme \"$1\"; python3 - \"$1\" <<'PY'\n"
                + "import json, os, sys\np = os.path.expanduser('~/.config/qtengine/config.json')\nd = json.load(open(p))\n"
                + "d.setdefault('theme', {})['iconTheme'] = sys.argv[1]\njson.dump(d, open(p, 'w'), indent=4)\nPY", "sh", t]);
        }

        function setCursorTheme(t: string): void {
            if (!/^[\w .+-]+$/.test(t)) // the name is written into hypr-vars.lua (Lua) by sed below
                return;
            cursorTheme = t;
            // now (Hyprland + GTK), and at the next login (hypr-vars.lua sets XCURSOR_THEME)
            Quickshell.execDetached(["sh", "-c", "gsettings set org.gnome.desktop.interface cursor-theme \"$1\"; hyprctl setcursor \"$1\" 24;"
                + " sed -i \"s|^\\(\\s*overrides.cursorTheme = \\).*|\\1\\\"$1\\\"|\" \"$HOME/.config/caelestia/hypr-vars.lua\"", "sh", t]);
        }

        // power profile
        property string powerProfile: ""

        Process {
            id: getPower

            running: true
            command: ["powerprofilesctl", "get"]
            stdout: StdioCollector {
                onStreamFinished: win.powerProfile = text.trim()
            }
        }

        // health check output (rice-doctor)
        property string doctorText: ""

        Process {
            id: doctor

            command: [Quickshell.env("HOME") + "/.local/bin/rice-doctor"]
            stdout: StdioCollector {
                onStreamFinished: win.doctorText = text.replace(/\x1b\[[0-9;]*m/g, "").trim() || "No output."
            }
        }

        // ── layout: sidebar | page ──────────────────────────────────
        Rectangle {
            id: sidebar

            width: 230
            height: parent.height
            color: Theme.alpha(Theme.fg, 0.04)

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.alpha(Theme.fg, 0.08)
            }

            Column {
                x: 10
                y: 16
                width: parent.width - 20
                spacing: 2

                Repeater {
                    model: win.pages

                    Rectangle {
                        id: entry

                        required property var modelData
                        readonly property bool current: win.page.id === modelData.id

                        width: parent.width
                        height: 34
                        radius: 7
                        color: current ? Theme.alpha(Theme.primary, 0.9) : entryMouse.containsMouse ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                        SymbolTile { // System Settings: white symbol on an Apple-colour squircle
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            size: 22
                            name: entry.modelData.icon
                            tint: entry.modelData.color
                        }

                        Text {
                            x: 40
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.name
                            color: entry.current ? Theme.fgOnPrimary : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: entry.current ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            id: entryMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Shared.settingsPage = entry.modelData.id
                        }
                    }
                }
            }
        }

        Flickable {
            id: scroller

            anchors.left: sidebar.right
            anchors.right: parent.right
            height: parent.height
            contentHeight: pageCol.height + 48
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            C.ScrollBar.vertical: C.ScrollBar {}

            Column {
                id: pageCol

                x: 28
                y: 22
                width: scroller.width - 56
                spacing: 22

                Text {
                    text: win.page.name
                    color: Theme.fg
                    font.family: Theme.displayFont
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }

                Loader {
                    id: pageLoader

                    width: parent.width
                    sourceComponent: ({
                            wifi: wifiPage,
                            bluetooth: bluetoothPage,
                            sound: soundPage,
                            more: morePage,
                            keyboard: keyboardPage,
                            appearance: appearancePage,
                            desktop: desktopPage,
                            widgets: widgetsPage,
                            windows: windowsPage,
                            menubar: menubarPage,
                            displays: displaysPage,
                            maintenance: maintenancePage
                        })[win.page.id]
                    onSourceComponentChanged: scroller.contentY = 0
                }
            }
        }

        // ── pages ─────────────────────────────────────────────────────
        Component {
            id: wifiPage

            SettingsWifi {
                width: pageLoader.width
            }
        }

        Component {
            id: bluetoothPage

            SettingsBluetooth {
                width: pageLoader.width
            }
        }

        Component {
            id: keyboardPage

            SettingsKeyboard {
                width: pageLoader.width
            }
        }

        Component {
            id: soundPage

            SettingsSound {
                width: pageLoader.width
            }
        }

        // the specialist apps, for what this window doesn't cover (hidden from the
        // launcher so there's one Settings to look for; they still open from here)
        Component {
            id: morePage

            Column {
                readonly property var apps: [
                    ["systemsettings", "KDE System Settings", "Printers, users, default apps, fonts, file associations"],
                    ["io.github.bluemancz.hyprmod", "HyprMod", "Every Hyprland option, and your monitor layout"],
                    ["thunar-settings", "File Manager Preferences", "Thunar: views, thumbnails, behaviour"],
                    ["appimagelaunchersettings", "AppImage Settings", "Where AppImages are kept and how they're added"],
                    ["uuctl", "Background Services", "Start, stop and enable your user systemd services"],
                    ["nwg-look", "GTK Settings", "Fonts, cursor size and other GTK details"]
                ]

                id: moreCol

                width: pageLoader.width
                spacing: 22

                SettingsUi.Group {
                    note: "Settings these apps handle better. Each opens in its own window."

                    Repeater {
                        model: moreCol.apps

                        SettingsUi.Setting {
                            id: more

                            required property var modelData

                            label: modelData[1]
                            detail: modelData[2]
                            SettingsUi.Button {
                                text: "Open"
                                onClicked: Quickshell.execDetached(["gtk-launch", more.modelData[0]])
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: appearancePage

            Column {
                width: pageLoader.width
                spacing: 22

                SettingsUi.Group {
                    title: "Theme"

                    SettingsUi.Setting {
                        label: "Appearance"
                        SettingsUi.Segmented {
                            options: [["light", "Light"], ["dark", "Dark"]]
                            value: win.schemeMode
                            onPicked: v => win.setScheme("-m", v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Colour style"
                        detail: "Colours are generated from your wallpaper"
                        SettingsUi.Choice {
                            options: [["tonalspot", "Tonal Spot"], ["vibrant", "Vibrant"], ["expressive", "Expressive"], ["fidelity", "Fidelity"], ["content", "Content"], ["fruitsalad", "Fruit Salad"], ["rainbow", "Rainbow"], ["neutral", "Neutral"], ["monochrome", "Monochrome"]]
                            value: win.schemeVariant
                            onPicked: v => win.setScheme("-v", v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Wallpaper"
                        SettingsUi.Button {
                            text: "Choose Wallpaper…"
                            onClicked: Shared.wallpaperOpen = true
                        }
                    }
                }

                SettingsUi.Group {
                    title: "Apps, Icons & Pointer"

                    SettingsUi.Setting {
                        label: "App theme"
                        detail: "How GTK apps draw their windows and controls"
                        SettingsUi.Choice {
                            width: 220
                            options: win.gtkThemes.map(t => [t, t])
                            value: win.gtkTheme
                            onPicked: v => {
                                win.gtkTheme = v;
                                Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", v]);
                            }
                        }
                    }

                    SettingsUi.Setting {
                        label: "Icons"
                        detail: "For every app, the dock and the launcher"
                        SettingsUi.Choice {
                            width: 220
                            options: win.iconThemes.map(t => [t, t])
                            value: win.iconTheme
                            onPicked: v => win.setIconTheme(v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Pointer"
                        SettingsUi.Choice {
                            width: 220
                            options: win.cursorThemes.map(t => [t, t])
                            value: win.cursorTheme
                            onPicked: v => win.setCursorTheme(v)
                        }
                    }
                }

                SettingsUi.Group {
                    title: "Motion"

                    SettingsUi.Setting {
                        label: "Reduce motion"
                        detail: "Slides become instant; fades remain (game mode also turns this on)"
                        SettingsUi.Toggle {
                            checked: Config.reducedMotion
                            onToggled: on => Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "enable-animations", on ? "false" : "true"])
                        }
                    }

                    SettingsUi.Setting {
                        label: "Animation speed"
                        detail: "How long the shell's springs take to settle"
                        SettingsUi.Slider {
                            from: 0.2
                            to: 0.6
                            step: 0.01
                            value: Config.springResponse
                            text: Config.springResponse.toFixed(2) + " s"
                            onMoved: v => Config.set("motion", "response", v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Bounce"
                        SettingsUi.Slider {
                            from: 0
                            to: 0.4
                            step: 0.02
                            value: 1 - Config.springDamping
                            text: Config.springDamping >= 0.999 ? "None" : Math.round((1 - Config.springDamping) * 250) + "%"
                            onMoved: v => Config.set("motion", "dampingRatio", Math.round((1 - v) * 100) / 100)
                        }
                    }
                }
            }
        }

        Component {
            id: desktopPage

            Column {
                readonly property var cornerActions: [["none", "—"], ["launcher", "Apps"], ["overview", "Overview"], ["spotlight", "Spotlight"], ["showdesktop", "Show Desktop"], ["widgets", "Edit Widgets"], ["lock", "Lock Screen"]]

                id: desktopCol

                width: pageLoader.width
                spacing: 22

                SettingsUi.Group {
                    title: "Dock"

                    SettingsUi.Setting {
                        label: "Size"
                        SettingsUi.Slider {
                            from: 36
                            to: 72
                            step: 2
                            value: Config.iconSize
                            text: Config.iconSize + " px"
                            onMoved: v => Config.setDock("iconSize", Math.round(v))
                        }
                    }

                    SettingsUi.Setting {
                        label: "Magnification"
                        SettingsUi.Slider {
                            from: 1
                            to: 2
                            step: 0.05
                            value: Config.magnification
                            text: Config.magnification <= 1.001 ? "Off" : Math.round(Config.magnification * 100) + "%"
                            onMoved: v => Config.setDock("magnification", v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Automatically hide the dock"
                        SettingsUi.Toggle {
                            checked: Config.bottomAutoHide
                            onToggled: on => Config.setDock("autoHide", on)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Show the All Apps button"
                        SettingsUi.Toggle {
                            checked: Config.launchpad
                            onToggled: on => Config.setDock("launchpad", on)
                        }
                    }
                }

                SettingsUi.Group {
                    title: "Hot Corners"
                    note: "Rest the pointer in a corner of the screen to run its action."

                    SettingsUi.Setting {
                        label: "Top left"
                        SettingsUi.Choice {
                            options: desktopCol.cornerActions
                            value: Config.hotCorners.topLeft
                            onPicked: v => Config.set("hotCorners", "topLeft", v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Top right"
                        SettingsUi.Choice {
                            options: desktopCol.cornerActions
                            value: Config.hotCorners.topRight
                            onPicked: v => Config.set("hotCorners", "topRight", v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Bottom left"
                        SettingsUi.Choice {
                            options: desktopCol.cornerActions
                            value: Config.hotCorners.bottomLeft
                            onPicked: v => Config.set("hotCorners", "bottomLeft", v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Bottom right"
                        SettingsUi.Choice {
                            options: desktopCol.cornerActions
                            value: Config.hotCorners.bottomRight
                            onPicked: v => Config.set("hotCorners", "bottomRight", v)
                        }
                    }
                }
            }
        }

        Component {
            id: widgetsPage

            Column {
                width: pageLoader.width
                spacing: 22

                SettingsUi.Group {
                    title: "Desktop Widgets"

                    SettingsUi.Setting {
                        label: "Show widgets on the desktop"
                        SettingsUi.Toggle {
                            checked: Config.widgetsEnabled
                            onToggled: on => Config.setWidgets("enabled", on)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Add, remove and arrange widgets"
                        SettingsUi.Button {
                            text: "Edit Widgets…"
                            onClicked: Quickshell.execDetached(["qs", "-c", "macos", "ipc", "call", "widgets", "edit"])
                        }
                    }

                    SettingsUi.Setting {
                        label: "Frosted glass"
                        detail: "Blurred wallpaper behind each widget"
                        SettingsUi.Toggle {
                            checked: Config.widgetsGlass
                            onToggled: on => Config.setWidgets("glass", on)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Dim widgets while apps are open"
                        SettingsUi.Segmented {
                            options: [["auto", "Automatically"], ["always", "Always"], ["never", "Never"]]
                            value: Config.widgetsDim
                            onPicked: v => Config.setWidgets("dim", v)
                        }
                    }
                }

                SettingsUi.Group {
                    title: "Clock & Weather"

                    SettingsUi.Setting {
                        label: "24-hour clock"
                        SettingsUi.Toggle {
                            checked: Config.clock24
                            onToggled: on => Config.setWidgets("clock24h", on)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Temperature"
                        SettingsUi.Segmented {
                            options: [["C", "°C"], ["F", "°F"]]
                            value: Config.tempUnit
                            onPicked: v => Config.setWidgets("temperatureUnit", v)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Weather location"
                        detail: "A city, or \"lat,lon\". Leave empty to use your approximate location"
                        C.TextField {
                            width: 200
                            height: 28
                            text: Config.weatherLocation
                            placeholderText: "Automatic"
                            color: Theme.fg
                            placeholderTextColor: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 12
                            leftPadding: 10
                            background: Rectangle {
                                radius: 7
                                color: Theme.alpha(Theme.fg, 0.08)
                                border.width: parent.activeFocus ? 2 : 0
                                border.color: Theme.primary
                            }
                            onEditingFinished: Config.setWidgets("weatherLocation", text.trim())
                        }
                    }
                }

                SettingsUi.Group {
                    title: "Now Playing"
                    note: "The card that drops down from the top of the screen when music plays."

                    SettingsUi.Setting {
                        label: "Show"
                        SettingsUi.Segmented {
                            options: [["auto", "When the track changes"], ["always", "Always"], ["off", "Off"]]
                            value: Config.musicMode
                            onPicked: v => Config.setMusicMode(v)
                        }
                    }

                    SettingsUi.Setting {
                        visible: Config.musicMode === "auto"
                        height: visible ? implicitHeight : 0
                        label: "Stay on screen for"
                        SettingsUi.Slider {
                            from: 3
                            to: 15
                            step: 1
                            value: Config.musicShowMs / 1000
                            text: Math.round(Config.musicShowMs / 1000) + " s"
                            onMoved: v => Config.set("nowPlaying", "seconds", Math.round(v))
                        }
                    }
                }
            }
        }

        Component {
            id: windowsPage

            Column {
                width: pageLoader.width
                spacing: 22

                SettingsUi.Group {
                    title: "Windows"

                    SettingsUi.Setting {
                        label: "Open new windows floating"
                        detail: "Like macOS: centred, moved by their title bar. Off tiles them"
                        SettingsUi.Toggle {
                            checked: Config.floatingWindows
                            onToggled: on => Config.setFloating(on)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Window menu on a title-bar click"
                        detail: "Minimize, Zoom, Full Screen, Center, Move to a desktop…"
                        SettingsUi.Segmented {
                            options: [["left", "Left click"], ["right", "Right click"], ["off", "Off"]]
                            value: Config.titlebarMenu
                            onPicked: v => Config.set("windows", "titlebarMenu", v)
                        }
                    }
                }

                SettingsUi.Group {
                    title: "Performance"

                    SettingsUi.Setting {
                        label: "Game mode"
                        detail: "Turns off blur, shadows, animations and gaps for the most FPS (also Super+F1)"
                        SettingsUi.Toggle {
                            checked: Shared.gameMode
                            onToggled: Hyprland.dispatch(`mac_game_mode_toggle() or hl.dsp.event("macack")`)
                        }
                    }
                }
            }
        }

        Component {
            id: menubarPage

            Column {
                width: pageLoader.width
                spacing: 22

                SettingsUi.Group {
                    title: "Menu Bar"
                    note: "The bar across the top of the screen (Caelestia)."

                    SettingsUi.Setting {
                        label: "Show app icons on desktops"
                        detail: "Each desktop button shows the apps open on it"
                        SettingsUi.Toggle {
                            checked: cael.get(["bar", "workspaces", "showWindows"], false)
                            onToggled: on => cael.set(["bar", "workspaces", "showWindows"], on)
                        }
                    }

                    SettingsUi.Setting {
                        label: "Clock background"
                        SettingsUi.Toggle {
                            checked: cael.get(["bar", "clock", "background"], false)
                            onToggled: on => cael.set(["bar", "clock", "background"], on)
                        }
                    }
                }
            }
        }

        Component {
            id: displaysPage

            Column {
                width: pageLoader.width
                spacing: 22

                SettingsDisplays {
                    width: parent.width
                }

                SettingsUi.Group {
                    title: "Night Shift"
                    note: "Warmer colours in the evening are easier on your eyes."

                    SettingsUi.Setting {
                        label: "Schedule"
                        SettingsUi.Segmented {
                            options: [["auto", "Sunset to sunrise"], ["on", "On"], ["off", "Off"]]
                            value: Config.nightShift
                            onPicked: v => Config.setNightShift(v)
                        }
                    }
                }

                SettingsUi.Group {
                    title: "Battery"
                    note: "Low power mode turns on by itself on battery below 30%, and your previous mode comes back when you plug in."

                    SettingsUi.Setting {
                        label: "Power mode"
                        SettingsUi.Segmented {
                            options: [["power-saver", "Low Power"], ["balanced", "Balanced"], ["performance", "High Performance"]]
                            value: win.powerProfile
                            onPicked: v => {
                                win.powerProfile = v;
                                Quickshell.execDetached(["powerprofilesctl", "set", v]);
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: maintenancePage

            Column {
                width: pageLoader.width
                spacing: 22

                SettingsUi.Group {
                    title: "Health"

                    SettingsUi.Setting {
                        label: "Check the desktop for problems"
                        detail: "Crashes, config errors, missing pieces (rice-doctor)"
                        SettingsUi.Button {
                            text: doctor.running ? "Checking…" : "Run Check"
                            accent: true
                            onClicked: if (!doctor.running) {
                                win.doctorText = "";
                                doctor.running = true;
                            }
                        }
                    }

                    Item {
                        visible: win.doctorText !== ""
                        width: parent.width
                        height: visible ? report.implicitHeight + 24 : 0

                        Text {
                            id: report

                            x: 14
                            y: 8
                            width: parent.width - 28
                            wrapMode: Text.WrapAnywhere
                            text: win.doctorText
                            color: Theme.fgDim
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            textFormat: Text.PlainText
                        }
                    }

                    SettingsUi.Setting {
                        label: "Restart the desktop shells"
                        detail: "Fixes a stuck dock, bar or widgets. Closes this window"
                        SettingsUi.Button {
                            text: "Restart"
                            onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rice-restart"])
                        }
                    }
                }

                SettingsUi.Group {
                    title: "Settings Files"
                    note: "Everything here is saved in these files; editing them by hand applies live too."

                    SettingsUi.Setting {
                        label: "Dock, widgets, windows, hot corners"
                        detail: "~/.config/caelestia/macos.json"
                        SettingsUi.Button {
                            text: "Open"
                            onClicked: Config.editFile()
                        }
                    }

                    SettingsUi.Setting {
                        label: "Menu bar and Caelestia panels"
                        detail: "~/.config/caelestia/shell.json"
                        SettingsUi.Button {
                            text: "Open"
                            onClicked: Quickshell.execDetached(["xdg-open", cael.path])
                        }
                    }
                }
            }
        }
    }
}
