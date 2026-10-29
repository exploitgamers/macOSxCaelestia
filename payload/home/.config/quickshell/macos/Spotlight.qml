pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Spotlight (SUPER+Space): one search bar for everything —
//   apps · open windows · calculator (2+2, 15% of 80…) · system actions
//   (lock, sleep, Do Not Disturb, edit widgets…) · files in your home (fd) ·
//   web search as the fallback.
// ↑/↓ choose, Enter opens, Esc closes. Restart / Shut Down ask for a second Enter.
PanelWindow {
    id: spot

    required property ShellScreen modelData

    // latched while open: focus follows the mouse, so a live binding hopped displays mid-show
    property bool here: false
    Binding on here {
        when: !Shared.spotlightOpen
        value: (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === spot.modelData?.name
        restoreMode: Binding.RestoreNone
    }
    readonly property bool open: Shared.spotlightOpen && here

    property string query: ""
    property int selected: 0
    property var files: []

    // file preview (selected file result): image thumbnail, first lines of text,
    // or a folder's first entries — plus size and date
    readonly property string previewPath: results[selected]?.path ?? ""
    readonly property bool previewIsImage: /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(previewPath)
    property string previewText: ""
    property string previewInfo: ""

    onPreviewPathChanged: {
        previewText = "";
        previewInfo = "";
        previewProc.running = false;
        if (previewPath)
            previewDebounce.restart();
    }

    Timer {
        id: previewDebounce

        interval: 120
        onTriggered: previewProc.running = true
    }

    Process {
        id: previewProc

        // line 1: "size<TAB>mtime<TAB>kind"; then a folder listing or the start of a text file
        command: ["sh", "-c", 'p="$1"; s=$(stat -c "%s\t%Y" "$p" 2>/dev/null) || exit 0; if [ -d "$p" ]; then printf "%s\tdir\n" "$s"; ls -Ap "$p" | head -12; else m=$(file -b --mime-type "$p"); printf "%s\t%s\n" "$s" "$m"; case "$m" in text/*|application/json|application/xml|application/x-shellscript) head -c 1200 "$p";; esac; fi', "sh", spot.previewPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n");
                const [size, mtime, kind] = (nl < 0 ? text : text.slice(0, nl)).split("\t");
                const body = nl < 0 ? "" : text.slice(nl + 1);
                const n = Number(size);
                const human = kind === "dir" ? "Folder" : n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : n >= 1024 ? Math.round(n / 1024) + " KB" : n + " bytes";
                spot.previewInfo = mtime ? human + "  ·  " + Qt.formatDateTime(new Date(Number(mtime) * 1000), "d MMM yyyy, h:mm AP") : "";
                spot.previewText = body;
            }
        }
    }
    property string confirming: "" // id of an action waiting for a second Enter

    readonly property string home: Quickshell.env("HOME")

    function close(): void {
        Shared.spotlightOpen = false;
    }

    // ── sources ──────────────────────────────────────────────────────────
    function calc(q: string): var {
        const expr = q.replace(/,/g, "").replace(/(\d+(?:\.\d+)?)\s*%\s*of\s*/gi, "($1/100)*").replace(/\^/g, "**").replace(/×/g, "*").replace(/÷/g, "/");
        if (!/^[\d\s+\-*/().%]+$/.test(expr) || !/\d/.test(expr) || !/[+\-*/%]/.test(expr.replace(/^-/, "")))
            return null;
        try {
            const v = Function(`"use strict"; return (${expr.replace(/(\d+(?:\.\d+)?)%/g, "($1/100)")});`)();
            if (typeof v !== "number" || !isFinite(v))
                return null;
            return Math.round(v * 1e10) / 1e10;
        } catch (e) {
            return null;
        }
    }

    readonly property var actions: [
        { id: "lock", title: "Lock Screen", words: "lock screen away", glyph: "lock", run: () => Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "lock", "lock"]) },
        { id: "sleep", title: "Sleep", words: "sleep suspend", glyph: "bedtime", run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        { id: "restart", title: "Restart", words: "restart reboot", glyph: "restart_alt", confirm: true, run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
        { id: "shutdown", title: "Shut Down", words: "shut down shutdown power off poweroff", glyph: "power_settings_new", confirm: true, run: () => Quickshell.execDetached(["systemctl", "poweroff"]) },
        { id: "nightshift", title: "Night Shift: " + (Config.nightShift === "auto" ? "Automatic" : Config.nightShift === "on" ? "On" : "Off"),
          words: "night shift light warm blue light filter sunset", glyph: "nightlight", run: () => NightShift.cycle() },
        { id: "overview", title: "Mission Control", words: "mission control overview expose windows all", glyph: "grid_view", run: () => Shared.overviewOpen = true },
        { id: "face", title: "Choose Profile Picture", words: "profile picture avatar photo face user", glyph: "account_circle", run: () => Shared.chooseProfilePicture() },
        { id: "dnd", title: "Do Not Disturb", words: "do not disturb dnd notifications focus", glyph: "do_not_disturb_on", run: () => Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "notifs", "toggleDnd"]) },
        { id: "game", title: "Game Mode", words: "game mode gaming performance", glyph: "sports_esports", run: () => Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "gameMode", "toggle"]) },
        { id: "wallpaper", title: "Change Wallpaper", words: "change wallpaper background desktop picture wallhaven", glyph: "wallpaper", run: () => Shared.wallpaperOpen = true },
        { id: "widgets", title: "Edit Widgets", words: "edit widgets add widget gallery desktop", glyph: "widgets", run: () => Shared.widgetEdit = true },
        { id: "hidew", title: Config.widgetsEnabled ? "Hide Widgets" : "Show Widgets", words: "hide show widgets desktop", glyph: "visibility", run: () => Config.setWidgets("enabled", !Config.widgetsEnabled) },
        { id: "apps", title: "Apps Launcher", words: "apps launcher launchpad all applications", glyph: "apps", run: () => Shared.toggleLauncher() },
        { id: "settings", title: "Desktop Settings File", words: "settings preferences config dock widgets", glyph: "settings", run: () => Config.editFile() }
    ]

    readonly property var results: {
        const q = query.trim();
        const ql = q.toLowerCase();
        if (!q)
            return [];
        const out = [];

        const v = calc(q);
        if (v !== null)
            out.push({ section: "Calculator", title: String(v), subtitle: q + "  ·  Enter copies the result", glyph: "calculate",
                       run: () => Quickshell.execDetached(["wl-copy", String(v)]) });

        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay && [e.name, e.genericName, e.comment, ...(e.keywords ?? [])]
            .some(s => (s ?? "").toLowerCase().includes(ql)));
        apps.sort((a, b) => (b.name.toLowerCase().startsWith(ql) ? 1 : 0) - (a.name.toLowerCase().startsWith(ql) ? 1 : 0)
                          || a.name.localeCompare(b.name));
        for (const e of apps.slice(0, 5))
            out.push({ section: "Applications", title: e.name, subtitle: e.genericName || e.comment || "", icon: e.icon, run: () => e.execute() });

        for (const t of Hyprland.toplevels.values.filter(t => ((t.title ?? "") + " " + (t.lastIpcObject?.class ?? "")).toLowerCase().includes(ql)).slice(0, 3)) {
            const addr = "0x" + String(t.address).replace(/^0x/, "");
            const minimized = t.workspace?.name === "special:minimized";
            out.push({ section: "Windows", title: t.title || "Window", subtitle: minimized ? "Minimized — restore" : "Switch to window", glyph: "select_window",
                       run: () => minimized ? Quickshell.execDetached(["hyprctl", "eval", `mac_restore("${addr}")`])
                                            : Hyprland.dispatch(`hl.dsp.focus({ window = "address:${addr}" })`) });
        }

        for (const a of actions.filter(a => a.title.toLowerCase().includes(ql) || a.words.split(" ").some(w => w.startsWith(ql))).slice(0, 3))
            out.push({ section: "Actions", title: a.title, subtitle: confirming === a.id ? "Press Enter again to confirm" : (a.confirm ? "System" : "Action"),
                       glyph: a.glyph, actionId: a.id, confirm: a.confirm === true, run: a.run });

        for (const f of files.slice(0, 5)) {
            const name = f.replace(/\/$/, "").split("/").pop();
            out.push({ section: "Files", path: f.replace(/\/$/, ""), title: name, subtitle: f.replace(home, "~"), glyph: f.endsWith("/") ? "folder" : "draft",
                       run: () => Quickshell.execDetached(["xdg-open", f]) });
        }

        out.push({ section: "Web", title: `Search the web for “${q}”`, subtitle: "Opens your browser", glyph: "travel_explore",
                   run: () => Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(q)]) });
        return out;
    }

    onResultsChanged: selected = Math.min(selected, Math.max(0, results.length - 1))
    onQueryChanged: {
        selected = 0;
        confirming = "";
        files = [];
        fileSearch.running = false;
        if (query.trim().length >= 2)
            fileDebounce.restart();
    }

    function activate(i: int): void {
        const r = results[i];
        if (!r)
            return;
        if (r.confirm && confirming !== r.actionId) {
            confirming = r.actionId; // ask once more
            return;
        }
        close();
        r.run();
    }

    Timer {
        id: fileDebounce

        interval: 180
        onTriggered: fileSearch.running = true
    }

    Process {
        id: fileSearch

        command: ["fd", "--ignore-case", "--max-results", "8", "--max-depth", "6", "--exclude", ".git", "--exclude", ".cache",
                  "--exclude", ".local", "--exclude", "node_modules", "--", spot.query.trim(), spot.home]
        stdout: StdioCollector {
            onStreamFinished: spot.files = text.trim() ? text.trim().split("\n") : []
        }
    }

    // `ipc call spotlight search …` while already open: take the new query too
    Connections {
        target: Shared

        function onSpotlightQueryChanged(): void {
            if (spot.open && Shared.spotlightQuery) {
                input.text = Shared.spotlightQuery;
                Shared.spotlightQuery = "";
            }
        }
    }

    onOpenChanged: {
        if (open) parked = false; else parkTimer.restart(); // unpark before the open animation (see margins)
        grabArmed = false;
        if (open) {
            input.text = Shared.spotlightQuery; // usually empty
            Shared.spotlightQuery = "";
            armGrab.restart();
            input.forceActiveFocus();
        }
    }

    // ── window ───────────────────────────────────────────────────────────
    screen: modelData
    color: "transparent"
    anchors.top: true
    // Closed: parked above the screen, so Hyprland stops re-blurring the invisible box (see AppLauncher.qml)
    margins.top: parked ? -implicitHeight - 100 : Math.round((modelData?.height ?? 0) * 0.2)
    property bool parked: !open
    Timer {
        id: parkTimer
        interval: 400 // after the close fade
        onTriggered: spot.parked = !spot.open
    }
    implicitWidth: 860
    implicitHeight: 540
    exclusionMode: ExclusionMode.Ignore
    // Always mapped (click-through via the mask while closed), like the Apps
    // launcher: unmapping as soon as the render-thread fade began destroyed the
    // window mid-animation and crashed the shell (QQuickAnimatorProxyJob).
    visible: true
    // the panel's resting rectangle, not `item: panel`: an item region is mapped through the
    // panel's open animation (scale/offset) when set, and isn't rebuilt as that animation runs
    mask: Region {
        x: panel.x
        y: panel.y
        width: spot.open ? panel.width : 0
        height: spot.open ? panel.height : 0
    }

    WlrLayershell.namespace: "macos-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool grabArmed: false

    Timer {
        id: armGrab

        interval: 80
        onTriggered: spot.grabArmed = spot.open
    }

    HyprlandFocusGrab {
        windows: [spot]
        active: spot.open && spot.grabArmed
        onCleared: spot.close()
    }


    Rectangle {
        id: panel

        width: parent.width
        height: Math.min(parent.height, Math.max(searchRow.height + (spot.results.length ? resultList.contentHeight + 14 : 0),
                                                 spot.previewPath ? searchRow.height + 290 : 0)) // list: 6 px under the field, 8 px sides and bottom
        radius: Theme.panelRadius // same corner as every large glass sheet (launcher, widgets)
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.glassBorder
        // render-thread Animators: searching/filtering on the main thread can't
        // stall the open animation (the old JS-stepped spring did)
        opacity: spot.open ? 1 : 0
        scale: spot.open ? 1 : 0.96
        transformOrigin: Item.Top
        Behavior on opacity { OpacityAnimator { duration: Config.reducedMotion ? 0 : 180; easing.type: Easing.OutCubic } }
        Behavior on scale { ScaleAnimator { duration: Config.reducedMotion ? 0 : 240; easing.type: Easing.OutQuint } }
        clip: true

        Behavior on height {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Item {
            id: searchRow

            width: parent.width
            height: 60

            Text {
                id: glass

                x: 20
                anchors.verticalCenter: parent.verticalCenter
                text: "search"
                color: Theme.fgDim
                font.family: "Material Symbols Rounded"
                font.pixelSize: 26
            }

            TextInput {
                id: input

                anchors.left: glass.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                selectionColor: Theme.alpha(Theme.primary, 0.4)
                font.family: Theme.displayFont
                font.pixelSize: 22
                font.weight: Font.Light
                clip: true
                onTextChanged: spot.query = text

                Keys.onPressed: event => {
                    const n = spot.results.length;
                    if (event.key === Qt.Key_Escape) {
                        spot.close();
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                        spot.selected = n ? (spot.selected + 1) % n : 0;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                        spot.selected = n ? (spot.selected - 1 + n) % n : 0;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        spot.activate(spot.selected);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Text {
                    visible: !input.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Spotlight Search"
                    color: Theme.alpha(Theme.fg, 0.4)
                    font: input.font
                }
            }

            Rectangle {
                visible: spot.results.length > 0
                anchors.bottom: parent.bottom
                x: 14
                width: parent.width - 28
                height: 1
                color: Theme.alpha(Theme.fg, 0.1)
            }
        }

        ListView {
            id: resultList

            anchors.top: searchRow.bottom
            anchors.topMargin: 6
            x: 8
            width: (spot.previewPath ? parent.width - preview.width - 8 : parent.width) - 16
            height: Math.min(contentHeight, spot.height - searchRow.height - 14)
            model: spot.results
            currentIndex: spot.selected
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property bool firstOfSection: index === 0 || spot.results[index - 1]?.section !== modelData.section

                width: resultList.width
                height: item.height + (firstOfSection ? 24 : 0)

                Text {
                    visible: row.firstOfSection
                    leftPadding: 12
                    topPadding: 8
                    text: row.modelData.section.toUpperCase()
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 0.6
                }

            Rectangle {
                id: item

                readonly property var modelData: row.modelData
                readonly property int index: row.index
                readonly property bool current: index === spot.selected

                anchors.bottom: parent.bottom
                width: resultList.width
                height: 44
                radius: Theme.panelRadius - 8 // concentric: 8 px inset
                color: current ? Theme.alpha(Theme.primary, 0.9) : "transparent"

                Item {
                    id: iconBox

                    x: 10
                    width: 28
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter

                    IconImage {
                        visible: item.modelData.icon !== undefined
                        anchors.fill: parent
                        source: item.modelData.icon !== undefined ? Quickshell.iconPath(item.modelData.icon, "application-x-executable") : ""
                    }

                    Text {
                        visible: item.modelData.icon === undefined
                        anchors.centerIn: parent
                        text: item.modelData.glyph ?? "search"
                        color: item.current ? Theme.fgOnPrimary : Theme.primary
                        font.family: "Material Symbols Rounded"
                        font.variableAxes: { "FILL": 1 }
                        font.pixelSize: 22
                    }
                }

                Text {
                    id: title

                    anchors.left: iconBox.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width * 0.55)
                    textFormat: Text.PlainText // untrusted text: never parse markup
                    text: item.modelData.title
                    elide: Text.ElideRight
                    color: item.current ? Theme.fgOnPrimary : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: item.modelData.section === "Calculator" ? 18 : 14
                    font.weight: Font.Medium
                }

                Text {
                    anchors.left: title.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText // untrusted text: never parse markup
                    text: item.modelData.subtitle
                    elide: Text.ElideMiddle
                    color: item.current ? Theme.alpha(Theme.fgOnPrimary, 0.8)
                         : spot.confirming && item.modelData.actionId === spot.confirming ? "#ff5f57" : Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 12
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: spot.selected = item.index
                    onClicked: spot.activate(item.index)
                }
            }
            }
        }

        // file preview pane
        Item {
            id: preview

            visible: spot.previewPath !== ""
            anchors.top: searchRow.bottom
            anchors.topMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: 290

            Rectangle {
                anchors.fill: parent
                radius: Theme.panelRadius - 8 // concentric with the panel, like the result rows
                color: Theme.alpha(Theme.fg, 0.05)
            }

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                ClippingRectangle {
                    visible: spot.previewIsImage
                    width: parent.width
                    height: 170
                    radius: 8
                    color: Theme.alpha(Theme.fg, 0.06)

                    Image {
                        anchors.fill: parent
                        source: spot.previewIsImage ? "file://" + spot.previewPath : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize.width: 560
                    }
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText // untrusted text: never parse markup
                    text: spot.previewPath.split("/").pop()
                    elide: Text.ElideMiddle
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText // untrusted text: never parse markup
                    text: spot.previewInfo
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 11
                }

                Text {
                    visible: !spot.previewIsImage && spot.previewText !== ""
                    width: parent.width
                    height: Math.min(implicitHeight, preview.height - 80)
                    textFormat: Text.PlainText // untrusted text: never parse markup
                    text: spot.previewText
                    wrapMode: Text.WrapAnywhere
                    clip: true
                    color: Theme.fgDim
                    font.family: Theme.iconFont // one family: Qt ignores comma lists
                    font.pixelSize: 10
                }
            }
        }
    }
}
