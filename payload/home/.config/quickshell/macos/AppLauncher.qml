pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Apps launcher opened from the dock's Apps button: a few pinned favourites,
// and everything else only when you search — a list with icon, name and a
// short description (KDE Kickoff's structure, macOS Spotlight's look,
// Caelestia's colours). ↑/↓ select, Enter launches, Esc closes.
PanelWindow {
    id: win

    required property ShellScreen modelData

    readonly property bool open: Shared.launcherOpen
    property string query: ""
    property int selected: 0

    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay)

    // `apps` is referenced so this re-evaluates once desktop entries finish loading
    readonly property var pinnedEntries: apps.length >= 0 ? Config.launcherPinned
        .map(id => DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id))
        .filter(e => !!e) : []

    function score(e: var, q: string): int {
        const n = (e.name ?? "").toLowerCase();
        if (n === q) return 100;
        if (n.startsWith(q)) return 80;
        if (n.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 60;
        if (n.includes(q)) return 40;
        if ((e.genericName ?? "").toLowerCase().includes(q)) return 25;
        if ((e.keywords ?? []).join(" ").toLowerCase().includes(q)) return 20;
        if ((e.comment ?? "").toLowerCase().includes(q)) return 10;
        if ((e.id ?? "").toLowerCase().includes(q)) return 5;
        return 0;
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (!q)
            return [];
        return apps.map(e => ({ e: e, s: score(e, q) }))
            .filter(r => r.s > 0)
            .sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name))
            .slice(0, 8)
            .map(r => r.e);
    }

    function describe(e: var): string {
        return e.comment || e.genericName || "Application";
    }

    function launch(e: var): void {
        if (!e)
            return;
        e.execute();
        Shared.launcherOpen = false;
    }

    onOpenChanged: {
        if (open) parked = false; else parkTimer.restart(); // unpark before the open animation (see margins)
        grabArmed = false;
        if (open)
            armGrab.restart();
        if (open) {
            selected = 0;
            search.text = Shared.launcherQuery; // usually empty
            Shared.launcherQuery = "";
            search.forceActiveFocus();
        }
    }
    onResultsChanged: selected = 0

    // ── Window ───────────────────────────────────────────────────────────
    screen: modelData
    color: "transparent"
    // Stays mapped while closed (invisible + click-through via the empty mask):
    // re-creating the surface on every open cost several late frames at the
    // start of the animation, and keeping it alive also preloads the icons.
    // Parked over a fullscreen game it unmaps (direct scanout, FullscreenBar.qml).
    visible: !parked || !Shared.gameFullscreenOn(modelData)
    anchors.bottom: true
    // Closed: parked below the screen. Hyprland re-blurs a mapped blur layer's whole box on every
    // frame anything beneath it changes, even fully transparent (~20 % of the GPU work of every
    // Caelestia panel animation, measured 2026-10-17); a margin move keeps the surface and buffer.
    margins.bottom: parked ? -implicitHeight - 100 : Shared.dockTop + 20 // 20 px above the dock plate, like the widget gallery
    property bool parked: !open
    Timer {
        id: parkTimer
        interval: 400 // after the 280 ms close animation
        onTriggered: win.parked = !win.open
    }
    exclusionMode: ExclusionMode.Ignore // don't rely on the dock's exclusive zone (0 in fullscreen/auto-hide)
    implicitWidth: 600
    implicitHeight: 600
    exclusiveZone: 0

    WlrLayershell.namespace: "macos-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // On-demand, not exclusive: while any layer holds *exclusive* keyboard focus
    // Hyprland routes all pointer input to it, so clicks on the dock (including
    // the Apps button meant to close this) never arrived. The focus grab below
    // gives this window the keyboard as soon as it opens, so typing still works.
    // Exclusive for a moment after opening just to take the keyboard, then on-demand.
    WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None : grabArmed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

    // the panel's resting rectangle, not `item: panel`: an item region is mapped through the
    // panel's open animation (scale/offset) when set, and isn't rebuilt as that animation runs
    mask: Region {
        x: panel.x
        y: panel.y
        width: win.open ? panel.width : 0
        height: win.open ? panel.height : 0
    }

    // Arm the click-outside grab a moment after opening: the surface stays
    // mapped while closed, and grabbing before Hyprland has moved keyboard
    // focus to it made the grab clear (and close the launcher) instantly.
    property bool grabArmed: false

    Timer {
        id: armGrab

        interval: 80
        onTriggered: win.grabArmed = win.open
    }

    // No HyprlandFocusGrab: it swallowed the click that ended it, so pressing a widget
    // or a title-bar button only closed the launcher. Instead any left press outside
    // the panel (Shared.windowDrag, from Hyprland's mouse bind) closes it and the
    // click goes through to what was pressed.
    // It closes on that click's *release*: closing on the press dropped this layer's
    // keyboard focus while the button was held, and Hyprland then never ran the release
    // bind (no macdrag>>0) — windowDrag stayed stuck, so the dock ignored hover and clicks.
    property bool closeOnRelease: false

    Connections {
        target: Shared

        function onWindowDragChanged(): void {
            if (Shared.windowDrag) {
                win.closeOnRelease = win.open && win.grabArmed && !panelHover.hovered;
            } else if (win.closeOnRelease) {
                win.closeOnRelease = false;
                Shared.launcherOpen = false;
            }
        }
    }


    Rectangle {
        id: panel

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 24
        height: content.implicitHeight + 28
        radius: Theme.panelRadius
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.glassBorder
        // Grows out of the dock (its source). Animators run on the render thread,
        // so building the app grid on the main thread can't make the opening stutter
        // (the old JS-stepped spring did).
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        transformOrigin: Item.Bottom

        HoverHandler {
            id: panelHover
        }
        Behavior on opacity { OpacityAnimator { duration: Config.reducedMotion ? 0 : 200; easing.type: Easing.OutCubic } }
        Behavior on scale { ScaleAnimator { duration: Config.reducedMotion ? 0 : 280; easing.type: Easing.OutQuint } }
        Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }


        // Light catching the top edge of the glass
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - parent.radius * 2
            height: 1
            color: Theme.alpha(Theme.fg, 0.14)
        }

        Column {
            id: content

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 14
            spacing: 12

            // ── Search field ─────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 42
                radius: Theme.panelRadius - 14 // concentric: 14 px inset
                color: Theme.alpha(Theme.fg, 0.07)
                border.width: 1
                border.color: search.activeFocus ? Theme.alpha(Theme.primary, 0.55) : "transparent"
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Symbol {
                    id: glass

                    anchors.left: parent.left
                    anchors.leftMargin: 13
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 18
                    weight: 400
                    color: Theme.fgDim
                }

                TextInput {
                    id: search

                    anchors.left: glass.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: Theme.alpha(Theme.primary, 0.4)
                    font.family: Theme.font
                    font.pixelSize: 16
                    clip: true
                    onTextChanged: win.query = text

                    Keys.onPressed: event => {
                        const n = win.results.length;
                        if (event.key === Qt.Key_Escape) {
                            Shared.launcherOpen = false;
                        } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && n)) {
                            win.selected = n ? (win.selected + 1) % n : 0;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                            win.selected = n ? (win.selected - 1 + n) % n : 0;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            win.launch(win.results[win.selected]);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }

                    Text {
                        visible: !search.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search apps"
                        color: Theme.alpha(Theme.fg, 0.4)
                        font: search.font
                    }
                }
            }

            // ── Pinned favourites (before typing) ────────────────────────
            Column {
                visible: !win.query.trim()
                width: parent.width
                spacing: 8

                Text {
                    text: "Pinned"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    leftPadding: 4
                }

                Grid {
                    id: grid

                    columns: 4
                    width: parent.width
                    rowSpacing: 4
                    columnSpacing: 4

                    Repeater {
                        model: ScriptModel {
                            values: win.pinnedEntries
                        }

                        delegate: Rectangle {
                            id: tile

                            required property var modelData

                            width: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
                            height: 92
                            radius: Theme.panelRadius - 14
                            color: tileMouse.containsMouse ? Theme.alpha(Theme.fg, tileMouse.pressed ? 0.14 : 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            // round / odd-shaped icons on a squircle tile (IconTiles.qml)
                            Rectangle {
                                visible: IconTiles.needsTile(tile.modelData.icon ?? "")
                                anchors.centerIn: tileIcon
                                width: tileIcon.width * 0.88
                                height: width
                                radius: width * 0.225
                                color: Theme.surfaceContainerHigh
                                border.width: 1
                                border.color: Theme.glassBorder
                                scale: tileMouse.pressed ? 0.92 : 1
                                Behavior on scale { NumberAnimation { duration: 90 } }
                            }

                            Image {
                                id: tileIcon

                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 12
                                width: 46
                                height: 46
                                sourceSize.width: 92
                                sourceSize.height: 92
                                asynchronous: true
                                source: Quickshell.iconPath(tile.modelData.icon, true) || Quickshell.iconPath("application-x-executable", true)
                                scale: (IconTiles.needsTile(tile.modelData.icon ?? "") ? 0.7 : 1) * (tileMouse.pressed ? 0.92 : 1)
                                Behavior on scale { NumberAnimation { duration: 90 } }
                            }

                            Text {
                                anchors.top: tileIcon.bottom
                                anchors.topMargin: 7
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: tile.modelData.name
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: tileMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.launch(tile.modelData)
                            }

                            // Unpin (×) appears on hover
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                width: 18
                                height: 18
                                radius: 9
                                color: unpinMouse.containsMouse ? Theme.alpha(Theme.fg, 0.3) : Theme.alpha(Theme.fg, 0.14)
                                opacity: tileMouse.containsMouse || unpinMouse.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: Theme.fg
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: unpinMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Config.toggleLauncherPin(tile.modelData.id)
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Type to search all apps · pin results to keep them here"
                    color: Theme.alpha(Theme.fg, 0.4)
                    font.family: Theme.font
                    font.pixelSize: 11
                    topPadding: 2
                }
            }

            // ── Search results ───────────────────────────────────────────
            Column {
                visible: !!win.query.trim()
                width: parent.width
                spacing: 2

                Repeater {
                    model: ScriptModel {
                        values: win.results
                    }

                    delegate: Rectangle {
                        id: rowItem

                        required property var modelData
                        required property int index

                        readonly property bool isSel: index === win.selected
                        readonly property bool pinned: Config.isLauncherPinned(modelData.id)

                        width: parent.width
                        height: 52
                        radius: Theme.panelRadius - 14
                        color: isSel ? Theme.alpha(Theme.primary, 0.85) : "transparent"
                        Behavior on color { ColorAnimation { duration: 90 } }

                        Rectangle {
                            visible: IconTiles.needsTile(rowItem.modelData.icon ?? "")
                            anchors.centerIn: rowIcon
                            width: rowIcon.width * 0.88
                            height: width
                            radius: width * 0.225
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.glassBorder
                        }

                        Image {
                            id: rowIcon

                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            sourceSize.width: 64
                            sourceSize.height: 64
                            asynchronous: true
                            source: Quickshell.iconPath(rowItem.modelData.icon, true) || Quickshell.iconPath("application-x-executable", true)
                            scale: IconTiles.needsTile(rowItem.modelData.icon ?? "") ? 0.7 : 1
                        }

                        Column {
                            anchors.left: rowIcon.right
                            anchors.leftMargin: 12
                            anchors.right: pinBtn.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: rowItem.modelData.name
                                color: rowItem.isSel ? Theme.fgOnPrimary : Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: win.describe(rowItem.modelData)
                                color: rowItem.isSel ? Theme.alpha(Theme.fgOnPrimary, 0.75) : Theme.fgDim
                                font.family: Theme.font
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: win.selected = rowItem.index
                            onClicked: win.launch(rowItem.modelData)
                        }

                        // Pin to favourites (shown on the selected row, or if pinned)
                        Rectangle {
                            id: pinBtn

                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 8
                            color: pinMouse.containsMouse ? Theme.alpha(rowItem.isSel ? Theme.fgOnPrimary : Theme.fg, 0.15) : "transparent"
                            opacity: rowItem.isSel || rowItem.pinned ? 1 : 0

                            Symbol { // pin / pin.fill
                                anchors.centerIn: parent
                                name: "keep"
                                fill: rowItem.pinned
                                size: 17
                                color: rowItem.isSel ? Theme.fgOnPrimary : rowItem.pinned ? Theme.sys.orange : Theme.fgDim
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            MouseArea {
                                id: pinMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.toggleLauncherPin(rowItem.modelData.id)
                            }
                        }
                    }
                }

                Text {
                    visible: win.results.length === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 18
                    bottomPadding: 18
                    text: `No apps match “${win.query.trim()}”`
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }
        }
    }
}
