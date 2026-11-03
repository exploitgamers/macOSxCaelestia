pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

// macOS-style context menu. Call open(item, entries, edge) where entries are
//   { label, action, checked?, enabled?, submenu?: [entries] }  |  { separator: true }  |  { header: "Title" }
// and edge is Edges.Top / Edges.Left / Edges.Bottom — the side of `item`
// the menu grows out of (it scales from that anchor, per Apple's spatial rules).
PopupWindow {
    id: menu

    property var entries: []
    property int edge: Edges.Top
    property bool shown: false
    property bool isSub: false // flyout instance owned by a parent menu (no focus grab of its own)
    property var parentMenu: null
    property int subIndex: -1 // row whose flyout is open
    property var pendingRow: null

    function openSub(row: var): void {
        const s = subLoader.item;
        if (!s)
            return;
        subIndex = row.index;
        s.open(row, row.modelData.submenu, Edges.Right);
    }

    function closeSub(): void {
        hoverOpen.stop();
        subIndex = -1;
        subLoader.item?.close();
    }

    function open(item: Item, list: var, side: int): void {
        closeSub();
        entries = list;
        edge = side;
        anchor.item = item;
        shown = true;
        visible = true;
    }

    function close(): void {
        closeSub();
        shown = false;
    }

    // a flyout hangs off the top-right corner of its row, growing right/down (Flip handles the screen edge)
    anchor.edges: isSub ? (Edges.Right | Edges.Top) : edge
    anchor.gravity: isSub ? (Edges.Right | Edges.Bottom) : edge
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.Flip
    // 8 px from its anchor: the gap the bar's drop-downs keep below the pills
    anchor.margins.top: edge === Edges.Top ? -8 : 0
    anchor.margins.left: edge === Edges.Left ? -8 : 0
    anchor.margins.bottom: edge === Edges.Bottom ? -8 : 0
    anchor.margins.right: edge === Edges.Right && !isSub ? -8 : 0

    color: "transparent"
    implicitWidth: 220
    implicitHeight: list.implicitHeight + 10

    HyprlandFocusGrab {
        windows: subLoader.item ? [menu, subLoader.item] : [menu]
        active: menu.shown && !menu.isSub
        onCleared: menu.close()
    }

    // Esc closes it (the focus grab hands the popup the keyboard)
    Item {
        focus: menu.shown
        Keys.onEscapePressed: menu.subIndex >= 0 ? menu.closeSub() : menu.close()
    }

    // [macos] flyout panel: a second GlassMenu, one level deep only
    Loader {
        id: subLoader

        // isSub/parentMenu go in as initial properties: set in onLoaded they arrive after the
        // flyout's own Loader already ran (isSub still false) and the menus nest forever
        Component.onCompleted: if (!menu.isSub)
            setSource("GlassMenu.qml", { isSub: true, parentMenu: menu })
    }

    Timer {
        id: hoverOpen

        interval: 150
        onTriggered: if (menu.pendingRow) menu.openSub(menu.pendingRow)
    }

    // Materialise from the anchor: scale + opacity together, no overshoot
    Spring {
        id: grow

        target: menu.shown ? 1 : 0
        response: 0.22
        epsilon: 0.002
        onValueChanged: if (value === 0 && !menu.shown) menu.visible = false
    }

    Rectangle {
        id: bg

        anchors.fill: parent
        radius: Theme.menuRadius
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.glassBorder
        opacity: grow.value
        transform: Scale {
            origin.x: menu.edge === Edges.Left ? bg.width : menu.edge === Edges.Right ? 0 : bg.width / 2
            origin.y: menu.edge === Edges.Top ? bg.height : menu.edge === Edges.Bottom ? 0 : bg.height / 2
            xScale: 0.9 + 0.1 * grow.value
            yScale: 0.9 + 0.1 * grow.value
        }

        Column {
            id: list

            anchors.fill: parent
            anchors.margins: 5

            Repeater {
                model: menu.entries

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property bool isSep: modelData.separator === true
                    readonly property bool isHeader: modelData.header !== undefined
                    readonly property bool enabled: !isSep && !isHeader && modelData.enabled !== false
                    readonly property bool hasSub: modelData.submenu !== undefined
                    readonly property bool hot: enabled && (rowMouse.containsMouse || menu.subIndex === index)

                    width: list.width
                    height: isSep ? 7 : 22 // macOS menu metrics: 22 px rows, thin separators

                    Rectangle {
                        visible: row.isSep
                        anchors.centerIn: parent
                        width: parent.width - 18 // lines up with the 9 px text inset
                        height: 1
                        color: Theme.alpha(Theme.fg, 0.12)
                    }

                    Rectangle {
                        visible: !row.isSep
                        anchors.fill: parent
                        radius: Theme.menuRadius - 5 // concentric with the menu (5 px inset)
                        color: row.hot ? Theme.alpha(Theme.primary, rowMouse.pressed ? 0.85 : 0.7) : "transparent"
                    }

                    Symbol { // checkmark, semibold like macOS menus
                        visible: !row.isSep && row.modelData.checked === true
                        x: 7
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        size: 14
                        weight: 600
                        color: row.hot ? Theme.fgOnPrimary : Theme.fg
                    }

                    Text {
                        visible: !row.isSep
                        anchors.left: parent.left
                        anchors.leftMargin: 24 // headers line up with the item labels
                        anchors.right: parent.right
                        anchors.rightMargin: row.hasSub ? 22 : 9
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText // untrusted text: never parse markup
                        text: row.isHeader ? row.modelData.header : (row.modelData.label ?? "")
                        elide: Text.ElideRight
                        color: row.isHeader ? Theme.fgDim : !row.enabled ? Theme.alpha(Theme.fg, 0.4) : row.hot ? Theme.fgOnPrimary : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: row.isHeader ? 11 : 12
                        font.weight: row.isHeader ? Font.DemiBold : Font.Normal
                        font.letterSpacing: 0.1
                    }

                    Symbol { // chevron.right
                        visible: row.hasSub
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron_right"
                        size: 15
                        weight: 600
                        color: row.hot ? Theme.fgOnPrimary : Theme.fgDim
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.enabled
                        onEntered: {
                            if (row.hasSub) {
                                if (menu.subIndex !== row.index) {
                                    menu.pendingRow = row;
                                    hoverOpen.restart();
                                }
                            } else {
                                menu.closeSub();
                            }
                        }
                        onClicked: {
                            if (row.hasSub) {
                                menu.openSub(row);
                                return;
                            }
                            menu.parentMenu?.close();
                            menu.close();
                            row.modelData.action?.();
                        }
                    }
                }
            }
        }
    }
}
