pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Widget gallery (Edit Widgets) — modelled on macOS Sonoma's:
//   ┌ 🔍 Search Widgets ┬────────────────────────────────────────────┐
//   │ ▣ All Widgets      │ Suggestions   (mixed-size live previews)   │
//   │ 🔋 Batteries        │ Batteries     (each widget in every size)  │
//   │ 📅 Calendar  …      │ Calendar …                                 │
//   ├────────────────────┴────────────────────────────────────────────┤
//   │ Drag a widget to place it on the desktop…                 [Done] │
//   └──────────────────────────────────────────────────────────────────┘
// Drag a preview onto the desktop to place it (onto a same-size widget to
// stack it), or click it to add it to the first free spot. Esc / Done close.
// The window spans the whole display so a drag can carry the widget out of
// the panel; only the panel takes input unless a drag is under way.
PanelWindow {
    id: gallery

    required property ShellScreen modelData

    // latched while open: focus follows the mouse, so a live binding hopped displays mid-show
    property bool here: false
    Binding on here {
        when: !Shared.widgetEdit
        value: (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === gallery.modelData?.name
        restoreMode: Binding.RestoreNone
    }
    // WarmLoader may build this after widgetEdit turned on (Binding inactive): latch once here
    Component.onCompleted: here = (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === gallery.modelData?.name
    // Loaded in the background (shell.qml WarmLoader) and kept mapped while loaded: re-mapping
    // rebuilt the whole scene graph (~300 ms). Before each opening it draws a few frames all but
    // invisible (`primed`): the first time that builds shaders, glyphs and textures, later it
    // refreshes the panel's cached layer, which then stays frozen while the panel animates.
    readonly property bool wanted: Shared.widgetEdit && here
    property bool primed: false
    readonly property bool shown: wanted && primed
    onWantedChanged: if (wanted && rise.value < 0.01) primed = false

    property bool everPrimed: false

    FrameAnimation {
        property int calm: 0

        running: !gallery.primed
        onRunningChanged: calm = 0
        // until frames come quickly again: right after loading, images, glyphs and shapes
        // settle over several frames; a reopen only needs one fresh frame
        onTriggered: {
            calm = frameTime < 0.022 ? calm + 1 : 0;
            if (calm >= (gallery.everPrimed ? 1 : 4) || currentFrame >= 60) {
                gallery.primed = true;
                gallery.everPrimed = true;
            }
        }
    }

    property string query: ""
    property string section: "all" // "all" or a widget type
    readonly property var kinds: [...WidgetTypes.kinds].sort((a, b) => a.name.localeCompare(b.name))
    readonly property var filtered: kinds.filter(k => WidgetTypes.matches(k, query))
    readonly property var current: section === "all" ? null : kinds.find(k => k.type === section) ?? null

    // a good first look, like Sonoma's Suggestions row
    readonly property var suggestions: [
        { type: "clock", size: "small" }, { type: "calendar", size: "small" }, { type: "weather", size: "medium" },
        { type: "battery", size: "small" }, { type: "notes", size: "small" }, { type: "music", size: "medium" },
        { type: "photos", size: "small" }, { type: "system", size: "small" }
    ]

    // drag state (screen-local coordinates of the window)
    property var dragging: null // { type, size }
    property real dragX
    property real dragY
    property real grabDX
    property real grabDY
    property string justAdded: ""

    function add(type: string, size: string): void {
        Shared.addWidget(type, size);
        flash(type, size);
    }

    function flash(type: string, size: string): void {
        justAdded = type + ":" + size;
        addedFlash.restart();
    }

    function drop(): void {
        const d = dragging;
        dragging = null;
        if (!d)
            return;
        // let go over the panel: cancelled
        const p = panel.mapFromItem(gallery.contentItem, dragX, dragY);
        if (!panelAway && p.x >= 0 && p.y >= 0 && p.x <= panel.width && p.y <= panel.height)
            return;
        const s = gallery.modelData;
        Shared.placeWidget(d.type, d.size, s.name, s.x + dragX - grabDX, s.y + dragY - grabDY);
        flash(d.type, d.size);
        // the drag took the panel away: the gallery stays closed after the drop
        if (panelAway)
            Shared.widgetEdit = false;
    }

    // Set when a dragged preview leaves the panel: the panel slides away (window, mask and drag
    // stay alive) and the drop then closes the gallery. Once away it stays away until closed.
    property bool panelAway: false

    function checkAway(): void {
        const p = panel.mapFromItem(gallery.contentItem, dragX, dragY);
        if (p.x < 0 || p.y < 0 || p.x > panel.width || p.y > panel.height)
            panelAway = true;
    }

    onShownChanged: {
        grabArmed = false;
        dragging = null;
        panelAway = false;
        if (shown) {
            search.text = "";
            section = "all";
            scroller.contentY = 0;
            armGrab.restart();
            search.forceActiveFocus();
        }
    }

    screen: modelData
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    visible: true
    // closed (but kept loaded): the live previews mustn't keep repainting the invisible window
    // (+ a few frames after it hides: a drop or Esc that closes the gallery hides the dragged
    // copy in the same tick, and without one more frame it stayed frozen on screen)
    updatesEnabled: panel.visible || lastFrames.running

    Timer {
        id: lastFrames

        interval: 100
    }
    // the panel's resting rectangle, not `item: panel`: an item region is mapped through the
    // panel's open animation (scale/offset) when set, and isn't rebuilt as that animation runs
    mask: Region {
        x: gallery.dragging ? 0 : panel.x
        y: gallery.dragging ? 0 : panel.y
        width: !gallery.shown ? 0 : gallery.dragging ? gallery.width : panel.width
        height: !gallery.shown ? 0 : gallery.dragging ? gallery.height : panel.height
    }

    WlrLayershell.namespace: "macos-gallery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: !shown ? WlrKeyboardFocus.None : grabArmed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

    // Exclusive focus for the first 80 ms sends typing straight to search, then OnDemand. No
    // HyprlandFocusGrab: it swallowed the press that cleared it, so a title-bar button (or any
    // other click) only closed the gallery. Instead a left press outside the panel
    // (Shared.windowDrag) closes it on release and the click goes through (as AppLauncher does).
    // Plugin-swallowed title-bar presses (traffic lights) emit no macdrag: they act, gallery stays.
    property bool grabArmed: false

    Timer {
        id: armGrab

        interval: 80
        onTriggered: {
            gallery.grabArmed = gallery.shown;
        }
    }

    Timer {
        id: addedFlash

        interval: 1100
        onTriggered: gallery.justAdded = ""
    }

    property bool closeOnRelease: false

    Connections {
        target: Shared

        function onWindowDragChanged(): void {
            if (Shared.windowDrag) {
                gallery.closeOnRelease = gallery.shown && gallery.grabArmed && !gallery.dragging && !panelHover.hovered;
            } else if (gallery.closeOnRelease) {
                gallery.closeOnRelease = false;
                Shared.widgetEdit = false;
            }
        }
    }

    Spring {
        id: rise

        target: gallery.shown && !gallery.panelAway ? 1 : 0
        response: 0.34
        epsilon: 0.002
    }

    // ── a draggable / clickable widget preview ──────────────────────────
    component Preview: Item {
        id: pv

        property string type
        property string size
        property real factor: 0.62
        readonly property bool added: gallery.justAdded === type + ":" + size
        readonly property bool lifted: gallery.dragging !== null && gallery.dragging.type === type && gallery.dragging.size === size

        implicitWidth: WidgetTypes.width(size) * factor
        implicitHeight: WidgetTypes.height(size) * factor

        WidgetBody {
            width: WidgetTypes.width(pv.size)
            height: WidgetTypes.height(pv.size)
            transformOrigin: Item.TopLeft
            scale: pv.factor * (area.pressed && !pv.lifted ? 0.97 : 1)
            opacity: pv.lifted ? 0.35 : 1
            type: pv.type
            size: pv.size
            lift: area.containsMouse ? 0.8 : 0

            Behavior on scale {
                NumberAnimation { duration: 120 }
            }
        }

        // Sonoma's green ＋ on the top-left corner (✓ once added)
        Rectangle {
            x: -8
            y: -8
            width: 22
            height: 22
            radius: 11
            color: pv.added ? "#30d158" : "#34c759"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.15)
            scale: (area.containsMouse && !gallery.dragging) || pv.added ? 1 : 0

            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutBack }
            }

            Text {
                anchors.centerIn: parent
                text: pv.added ? "check" : "add"
                color: "white"
                font.family: "Material Symbols Rounded"
                font.weight: Font.Bold
                font.pixelSize: 17
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pv.lifted ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real pressX
            property real pressY

            onPressed: m => {
                pressX = m.x;
                pressY = m.y;
            }
            onPositionChanged: m => {
                if (!pressed)
                    return;
                const p = mapToItem(gallery.contentItem, m.x, m.y);
                if (!gallery.dragging) {
                    if (Math.hypot(m.x - pressX, m.y - pressY) < 6)
                        return;
                    // full-size widget follows the pointer, held where it was grabbed
                    gallery.grabDX = pressX / pv.factor;
                    gallery.grabDY = pressY / pv.factor;
                    gallery.dragging = { type: pv.type, size: pv.size };
                }
                gallery.dragX = p.x;
                gallery.dragY = p.y;
                gallery.checkAway();
            }
            onReleased: if (gallery.dragging) gallery.drop()
            onCanceled: if (gallery.dragging) {
                gallery.dragging = null;
                if (gallery.panelAway)
                    Shared.widgetEdit = false;
            }
            onClicked: if (!gallery.dragging) gallery.add(pv.type, pv.size)
        }
    }

    // ── panel ───────────────────────────────────────────────────────────
    Rectangle {
        id: panel

        readonly property int sideW: 236
        readonly property int footerH: 54

        HoverHandler {
            id: panelHover
        }

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Shared.dockTop + 20 // 20 px above the dock plate
        width: Math.min(parent.width - 120, 1120)
        height: Math.min(parent.height * 0.56, 600)
        radius: Theme.panelRadius
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.glassBorder
        // fades back while a widget is carried out to the desktop
        // opening/closing moves one cached texture instead of redrawing ~50 live previews a
        // frame; always on (switching it off when settled rebuilt every node: a 3-frame stall)
        layer.enabled: true
        layer.smooth: true
        // frozen while it moves: a preview's once-a-second tick re-rendered all ~50 previews
        // in the middle of the animation (a 3-4 frame stall)
        layer.live: !gallery.primed || rise.value > 0.999
        // hidden while closed: its live previews then don't repaint the (mapped) window
        visible: gallery.shown || rise.value > 0.01 || !gallery.primed
        onVisibleChanged: if (!visible) lastFrames.restart()
        // 0.004 while priming: drawn (Qt skips anything under 0.001) but invisible
        opacity: Math.max(gallery.primed ? 0 : 0.004, rise.value * (gallery.dragging ? 0.3 : 1))
        transform: [
            Translate { y: (1 - rise.value) * 36 },
            Scale { origin.x: panel.width / 2; origin.y: panel.height; xScale: 0.96 + 0.04 * rise.value; yScale: xScale }
        ]

        Behavior on opacity {
            enabled: rise.value > 0.99
            NumberAnimation { duration: 180 }
        }

        // ── sidebar ─────────────────────────────────────────────────────
        Rectangle {
            id: side

            width: panel.sideW
            height: parent.height - panel.footerH
            topLeftRadius: Theme.panelRadius // one shape: stacked translucent corner patches doubled the alpha where they overlapped
            color: Theme.alpha(Theme.fg, 0.04)
        }

        Rectangle {
            x: panel.sideW
            width: 1
            height: parent.height - panel.footerH
            color: Theme.alpha(Theme.fg, 0.1)
        }

        Rectangle {
            id: searchBox

            x: 12
            y: 12
            width: panel.sideW - 24
            height: 30
            radius: Theme.panelRadius - 12 // concentric with the sidebar corner
            color: Theme.alpha(Theme.fg, 0.08)
            border.width: search.activeFocus ? 2 : 0
            border.color: Theme.alpha(Theme.primary, 0.6)

            Text {
                id: glass

                x: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "search"
                color: Theme.fgDim
                font.family: "Material Symbols Rounded"
                font.pixelSize: 17
            }

            TextInput {
                id: search

                anchors.left: glass.right
                anchors.leftMargin: 5
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                selectionColor: Theme.alpha(Theme.primary, 0.4)
                font.family: Theme.font
                font.pixelSize: 13
                clip: true
                onTextChanged: {
                    gallery.query = text;
                    gallery.section = "all";
                    scroller.contentY = 0;
                }

                Keys.onPressed: event => {
                    const list = ["all", ...gallery.filtered.map(k => k.type)];
                    const i = Math.max(0, list.indexOf(gallery.section));
                    if (event.key === Qt.Key_Escape) {
                        if (text) text = ""; else Shared.widgetEdit = false;
                    } else if (event.key === Qt.Key_Down) {
                        gallery.section = list[(i + 1) % list.length];
                    } else if (event.key === Qt.Key_Up) {
                        gallery.section = list[(i - 1 + list.length) % list.length];
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && gallery.filtered.length) {
                        const k = gallery.current ?? gallery.filtered[0];
                        gallery.add(k.type, k.sizes[0]);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Text {
                    visible: !search.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search Widgets"
                    color: Theme.alpha(Theme.fg, 0.4)
                    font: search.font
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                visible: search.text !== ""
                text: "cancel"
                color: Theme.fgDim
                font.family: "Material Symbols Rounded"
                font.variableAxes: { "FILL": 1 }
                font.pixelSize: 16

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: search.text = ""
                }
            }
        }

        component SideRow: Rectangle {
            id: sr

            property string key
            property string label
            property var kind: null
            readonly property bool current: gallery.section === key

            width: sideList.width
            height: 34
            radius: 8
            // Sonoma highlights the selection in neutral grey, not the accent
            color: current ? Theme.alpha(Theme.fg, 0.14) : srArea.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"

            KindIcon {
                visible: sr.kind !== null
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                kind: sr.kind
                size: 22
            }

            Text {
                visible: sr.kind === null
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "space_dashboard"
                color: Theme.fg
                font.family: "Material Symbols Rounded"
                font.pixelSize: 22
            }

            Text {
                x: 40
                anchors.verticalCenter: parent.verticalCenter
                text: sr.label
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: sr.current ? Font.DemiBold : Font.Normal
            }

            MouseArea {
                id: srArea

                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    gallery.section = sr.key;
                    scroller.contentY = 0;
                }
            }
        }

        Flickable {
            id: sideList

            x: 12 // rows line up with the search field above
            y: searchBox.y + searchBox.height + 10
            width: panel.sideW - 24
            height: side.height - y - 12 // stops short of the footer instead of running into it
            contentHeight: sideCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: sideCol

                width: sideList.width
                spacing: 1

                SideRow {
                    key: "all"
                    label: "All Widgets"
                }

                Repeater {
                    model: gallery.filtered

                    SideRow {
                        required property var modelData

                        key: modelData.type
                        label: modelData.name
                        kind: modelData
                    }
                }
            }
        }

        // ── main: Suggestions + every app's widgets (or one app's) ──────
        Flickable {
            id: scroller

            x: panel.sideW + 1
            width: parent.width - x
            height: parent.height - panel.footerH - 8
            contentHeight: mainCol.implicitHeight + 24
            clip: true
            interactive: !gallery.dragging
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: mainCol

                x: 22
                y: 16
                width: scroller.width - 44
                spacing: 18

                Text {
                    visible: gallery.filtered.length === 0
                    text: "No widgets match “" + gallery.query + "”"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 14
                }

                // Suggestions (All Widgets, not searching)
                Column {
                    visible: gallery.section === "all" && !gallery.query
                    width: mainCol.width
                    spacing: 10

                    Text {
                        text: "Suggestions"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    Flow {
                        width: parent.width
                        spacing: 18

                        Repeater {
                            model: gallery.suggestions

                            Preview {
                                required property var modelData

                                type: modelData.type
                                size: modelData.size
                                factor: 0.62
                            }
                        }
                    }
                }

                // one section per app, or just the selected one. Built once for every kind and
                // only shown/hidden: rebuilding ~50 live previews on a section or search change
                // froze the panel for half a second
                Repeater {
                    model: gallery.kinds

                    Column {
                        id: sec

                        required property var modelData

                        // by type: a Repeater hands out copies of the array's objects
                        visible: gallery.current ? modelData.type === gallery.current.type : gallery.filtered.some(k => k.type === modelData.type)
                        width: mainCol.width
                        spacing: 10

                        Rectangle {
                            visible: gallery.current === null
                            width: parent.width
                            height: 1
                            color: Theme.alpha(Theme.fg, 0.08)
                        }

                        Row {
                            spacing: 8

                            KindIcon {
                                visible: gallery.current !== null
                                anchors.verticalCenter: parent.verticalCenter
                                kind: sec.modelData
                                size: 28
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    text: sec.modelData.name
                                    color: gallery.current ? Theme.fg : Theme.fgDim
                                    font.family: Theme.font
                                    font.pixelSize: gallery.current ? 18 : 13
                                    font.weight: Font.Bold
                                }

                                Text {
                                    visible: gallery.current !== null
                                    text: sec.modelData.description
                                    color: Theme.fgDim
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 18

                            Repeater {
                                model: sec.modelData.sizes

                                Column {
                                    id: cell

                                    required property string modelData

                                    spacing: 6

                                    Preview {
                                        type: sec.modelData.type
                                        size: cell.modelData
                                        factor: gallery.current ? 0.72 : 0.56
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: WidgetTypes.sizeName(cell.modelData)
                                        color: Theme.fgDim
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── footer ──────────────────────────────────────────────────────
        Rectangle {
            y: parent.height - panel.footerH
            width: parent.width
            height: 1
            color: Theme.alpha(Theme.fg, 0.1)
        }

        Text {
            x: 16 // same inset as the Done button on the right
            y: parent.height - panel.footerH / 2 - height / 2
            text: "Drag a widget to place it on the desktop, or click to add it…"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 13
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: parent.height - panel.footerH / 2 - height / 2
            width: doneText.implicitWidth + 32
            height: 28
            radius: 7
            color: doneArea.pressed ? Qt.darker("#0a84ff", 1.15) : "#0a84ff"

            Text {
                id: doneText

                anchors.centerIn: parent
                text: "Done"
                color: "white"
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            MouseArea {
                id: doneArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Shared.widgetEdit = false
            }
        }
    }

    // the widget being dragged out, full size, under the pointer
    WidgetBody {
        visible: gallery.dragging !== null
        x: gallery.dragX - gallery.grabDX
        y: gallery.dragY - gallery.grabDY
        width: WidgetTypes.width(gallery.dragging?.size ?? "small")
        height: WidgetTypes.height(gallery.dragging?.size ?? "small")
        type: gallery.dragging?.type ?? "clock"
        size: gallery.dragging?.size ?? "small"
        lift: 1
        scale: 1.03
        opacity: 0.92
    }
}
