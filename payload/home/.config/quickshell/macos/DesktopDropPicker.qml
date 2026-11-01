pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// Drag a window by its title bar onto the top bar's desktops (left part): a strip
// of desktop cards (their apps, and "New Desktop") slides down across the top of
// the screen, like macOS Mission Control's Spaces bar.
// The window shrinks to a thumbnail under the pointer; drop it on a card to move
// it to that desktop (and go there with it). Driven by hypr-qol.lua — during a
// window drag the pointer belongs to the compositor, so positions come as events
// and the chosen desktop goes back via `hyprctl eval mac_drop_ws = N`.
// The real window is hidden meanwhile; a copy of it (own unblurred layer, so moving
// it never re-blurs the column) compacts into the thumbnail and back out on leave.
Scope {
    id: picker

    required property ShellScreen modelData

    readonly property var monitor: Hyprland.monitorFor(modelData)
    readonly property bool here: Shared.deskDragOpen && Shared.deskDragX >= (modelData?.x ?? 0) && Shared.deskDragX < (modelData?.x ?? 0) + (modelData?.width ?? 0)
    readonly property real px: Shared.deskDragX - (modelData?.x ?? 0)
    readonly property real py: Shared.deskDragY - (modelData?.y ?? 0)
    readonly property var dragged: Hyprland.toplevels.values.find(t => ("0x" + String(t.address).replace(/^0x/, "")) === Shared.deskDragAddr) ?? null

    // every desktop the top bar shows (1–5, empty or not) and any higher one in use,
    // so you can pick any number; "New Desktop" only once all of those are in use
    readonly property int barDesks: 5 // Caelestia's bar.workspaces.shown (default)
    readonly property var desks: {
        const used = new Set(Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id > 0).map(t => t.workspace.id));
        const cur = monitor?.activeWorkspace?.id ?? 1;
        const n = Math.max(barDesks, cur, ...used);
        const list = [];
        for (let id = 1; id <= n; id++)
            list.push({ id: id, isNew: false, current: id === cur });
        if (list.every(d => used.has(d.id)))
            list.push({ id: n + 1, isNew: true, current: false });
        return list;
    }

    // the strip: cards side by side, centred under the bar (narrower if many desktops)
    readonly property int cardW: Math.min(168, Math.floor(((modelData?.width ?? 1536) - 80 - (desks.length - 1) * cardGap) / desks.length))
    readonly property int cardH: Math.round(cardW * (modelData?.height ?? 960) / Math.max(1, modelData?.width ?? 1536))
    readonly property int cardGap: 14
    readonly property int cardsTop: 56 // below the strip's title
    readonly property int stripH: cardsTop + cardH + 22
    readonly property real cardsW: desks.length * cardW + (desks.length - 1) * cardGap
    readonly property real cardsX: ((modelData?.width ?? 0) - cardsW) / 2
    // card under the pointer (or -1)
    onHereChanged: if (here) Hyprland.refreshToplevels() // fresh window positions for the miniatures
    readonly property int hoverIndex: {
        if (!here)
            return -1;
        const x = px - cardsX, y = py - barH - cardsTop;
        const i = Math.floor(x / (cardW + cardGap));
        return i >= 0 && i < desks.length && x - i * (cardW + cardGap) <= cardW && y >= 0 && y <= cardH ? i : -1;
    }
    onHoverIndexChanged: {

        const ws = hoverIndex >= 0 ? desks[hoverIndex].id : "nil";
        // over the socket: dispatch evaluates the Lua, the event after `or` is the dispatcher it expects
        Hyprland.dispatch(`(function() mac_drop_ws = ${ws} end)() or hl.dsp.event("macack")`);
    }

    readonly property real barW: monitor?.lastIpcObject?.reserved?.[0] ?? 0
    readonly property real barH: monitor?.lastIpcObject?.reserved?.[1] ?? 0 // the top bar

    Component.onCompleted: Hyprland.refreshMonitors()

    PanelWindow {
    screen: picker.modelData
    color: "transparent"
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: picker.barH // slides down below the top bar
    // 1 px while hidden (same surface, so the stacking below the copy's layer holds): the
    // full-height idle strip kept ~7 MB of GPU buffers for nothing [ram]
    implicitHeight: picker.here || slide.opacity > 0.01 ? picker.stripH + 20 : 1
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    // stays mapped (empty, no input): the copy's layer, mapped on each drag, then stacks above it;
    // not over a fullscreen game (direct scanout, FullscreenBar.qml)
    visible: !Shared.gameFullscreenOn(picker.modelData)

    WlrLayershell.namespace: "macos-launcher" // blurred like the launcher
    WlrLayershell.layer: WlrLayer.Overlay

    Rectangle {
        id: slide

        x: picker.cardsX - 22
        y: 10
        width: picker.cardsW + 44
        height: picker.stripH
        radius: Theme.panelRadius
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.glassBorder
        opacity: picker.here ? 1 : 0
        transform: Translate { y: picker.here ? 0 : -24 }

        Behavior on x {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16
            spacing: 10

            Text {
                text: "Move to Desktop"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            Text {
                anchors.baseline: parent.children[0].baseline
                text: "Drop the window on a desktop"
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: 12
            }
        }
    }

    Repeater {
        model: picker.desks

        // a desktop: a miniature of its windows where they sit (blank if none),
        // its number in the top-left corner
        ClippingRectangle {
            id: card

            required property var modelData
            required property int index

            readonly property bool hot: picker.hoverIndex === index
            readonly property real s: width / Math.max(1, picker.modelData?.width ?? 1536)
            readonly property var wins: card.modelData.isNew ? [] : Hyprland.toplevels.values
                .filter(t => t.workspace?.id === card.modelData.id && t !== picker.dragged && t.lastIpcObject?.at)

            x: picker.cardsX + index * (picker.cardW + picker.cardGap)
            y: 10 + picker.cardsTop
            width: picker.cardW
            height: picker.cardH
            radius: 10
            opacity: slide.opacity
            color: Theme.alpha(Theme.fg, card.modelData.current ? 0.12 : 0.07)
            border.width: hot ? 2 : card.modelData.isNew ? 1.5 : card.modelData.current ? 1 : 0
            border.color: hot ? Theme.primary : Theme.alpha(Theme.fg, 0.3)
            scale: hot ? 1.04 : 1

            Behavior on scale {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Repeater {
                model: card.wins

                Rectangle {
                    id: mini

                    required property var modelData

                    x: (modelData.lastIpcObject.at[0] - (picker.modelData?.x ?? 0)) * card.s
                    y: (modelData.lastIpcObject.at[1] - (picker.modelData?.y ?? 0)) * card.s
                    width: Math.max(6, modelData.lastIpcObject.size[0] * card.s)
                    height: Math.max(4, modelData.lastIpcObject.size[1] * card.s)
                    radius: 3
                    color: Theme.alpha(Theme.fg, 0.16)
                    border.width: 1
                    border.color: Theme.alpha(Theme.fg, 0.22)

                    // the app's icon underneath: shows if the window can't be captured
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: Math.min(22, parent.height * 0.6, parent.width * 0.6)
                        source: {
                            const id = mini.modelData.wayland?.appId ?? "";
                            const e = DesktopEntries.applications.values.length < 0 ? null : DesktopEntries.heuristicLookup(id);
                            return Quickshell.iconPath(e?.icon ?? id, "application-x-executable");
                        }
                    }

                    ScreencopyView {
                        anchors.fill: parent
                        captureSource: picker.here ? mini.modelData.wayland ?? null : null
                        live: false // one capture per opening: light on the iGPU
                    }
                }
            }

            // "+" for a new desktop
            Text {
                visible: card.modelData.isNew
                anchors.centerIn: parent
                text: "add"
                color: Theme.fgDim
                font.family: "Material Symbols Rounded"
                font.pixelSize: 26
            }

            // the number, top-left
            Rectangle {
                x: 6
                y: 6
                width: Math.max(height, num.implicitWidth + 10)
                height: 18
                radius: 9
                color: card.hot ? Theme.primary : Qt.rgba(0, 0, 0, 0.45)

                Text {
                    id: num

                    anchors.centerIn: parent
                    text: card.modelData.id
                    color: card.hot ? Theme.fgOnPrimary : "white"
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }
        }
    }

    }

    // the dragged window's copy: compacts from its real place into a thumbnail under
    // the pointer; expands back on leaving the column, shrinks away on a drop
    PanelWindow {
        id: ghostWin

        // the grabbed window (captured as soon as a drag gets going, while it's fully visible)
        readonly property var grabbed: Hyprland.toplevels.values.find(t => ("0x" + String(t.address).replace(/^0x/, "")) === Shared.grabAddr) ?? null

        screen: picker.modelData
        color: "transparent"
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        // mapped for the whole title-bar drag (from macgrab, the first real move), so the capture is
        // taken before the picker hides the window. Not on windowDrag: that is every left press, so
        // each click (even in a fullscreen game) opened and closed this layer
        visible: Shared.titleDrag || picker.here || ghost.p > 0.001 || ghost.opacity > 0.01

        WlrLayershell.namespace: "macos-deskdrag"
        WlrLayershell.layer: WlrLayer.Overlay

        // capture only once this layer has been up a moment: asked for in the same
        // instant it's created, the capture fails (blank copy, stuck screencopy)
        property bool ready: false
        onVisibleChanged: {
            ready = false;
            if (visible)
                readyTimer.restart();
        }

        Timer {
            id: readyTimer

            interval: 60
            onTriggered: ghostWin.ready = true
        }

        Item {
            id: ghost

            // hidden until a drag reaches the column (onHereChanged sets 1): at the default 1
            // ghostWin stayed mapped full-screen from startup, ~110 MB of GPU buffers [ram]
            opacity: 0
            // 0 = the window's own rect, 1 = thumbnail at the pointer
            property real p: 0
            // pointer, smoothed between the 50 Hz position events (thumbnail end only)
            property real sx: picker.px
            property real sy: picker.py
            property real px0: 0
            property real py0: 0
            readonly property var r: Shared.deskDragRect
            // the same scale as the miniatures in the desktop cards: a full-screen window
            // compacts to exactly a card, a smaller one to its size inside a card
            readonly property real k: picker.cardW / Math.max(1, picker.modelData?.width ?? 1536)
            // where the real window is now (it keeps following the pointer while hidden):
            // unsmoothed, so the copy lands exactly on it when expanding back
            readonly property real wx: r[0] - (picker.modelData?.x ?? 0) + picker.px - px0
            readonly property real wy: r[1] - (picker.modelData?.y ?? 0) + picker.py - py0
            readonly property real f: width / Math.max(1, r[2]) // copy scale: 1 = real size

            // bound, never assigned (assigning would cut it off from the pointer); smoothing
            // only once compacting, so a new drag doesn't glide in from the last one
            Behavior on sx { enabled: ghost.p > 0.05; SmoothedAnimation { duration: 60; velocity: -1 } }
            Behavior on sy { enabled: ghost.p > 0.05; SmoothedAnimation { duration: 60; velocity: -1 } }

            // follows the pointer freely (it used to lock into the hovered card, which felt
            // clumsy); the card under the pointer lights up instead
            x: wx + (sx + 14 - wx) * p
            y: wy + (sy + 14 - wy) * p
            width: r[2] + (r[2] * k - r[2]) * p
            height: r[3] + (r[3] * k - r[3]) * p

            Connections {
                target: picker

                function onHereChanged(): void {
                    if (picker.here) {
                        drop.stop();
                        fadeOut.stop();
                        ghost.px0 = picker.px; // window offset is relative to this point
                        ghost.py0 = picker.py;
                        ghost.opacity = 1;
                        ghost.scale = 1;
                        compact.to = 1;
                        compact.restart();
                    } else if (Shared.deskDragHow === "drop") {
                        drop.restart();
                    } else {
                        compact.to = 0;
                        compact.restart();
                    }
                }
            }

            NumberAnimation {
                id: compact

                target: ghost
                property: "p"
                duration: 240
                easing.type: Easing.OutCubic
                onFinished: if (to === 0) fadeOut.restart() // crossfade: the real window is fading back in
            }

            NumberAnimation {
                id: fadeOut

                target: ghost
                property: "opacity"
                to: 0
                duration: 150
            }

            ParallelAnimation {
                id: drop

                NumberAnimation { target: ghost; property: "scale"; to: 0.6; duration: 220; easing.type: Easing.InCubic }
                NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InCubic }
                onFinished: ghost.p = 0
            }

            // the window drawn at its real size, then scaled as a whole: title bar,
            // traffic lights, corners and content stay in proportion
            ClippingRectangle {
                width: ghost.r[2]
                height: ghost.r[3]
                scale: ghost.f
                transformOrigin: Item.TopLeft
                radius: (14 - 6 * ghost.p) / Math.max(0.01, ghost.f) // window corners → thumbnail corners
                color: Theme.surface
                border.width: 1 / Math.max(0.01, ghost.f)
                border.color: Theme.glassBorder

                // title bar like hyprbars': traffic lights left, title centred
                Row {
                    x: 12
                    y: Shared.titleBarHeight / 2 - 6.5
                    spacing: 8

                    Repeater {
                        model: ["#ff5f57", "#febc2e", "#28c840"]

                        Rectangle {
                            required property string modelData

                            width: 13
                            height: 13
                            radius: 6.5
                            color: modelData
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 15 - height / 2
                    width: Math.min(implicitWidth, parent.width - 200)
                    elide: Text.ElideRight
                    textFormat: Text.PlainText // untrusted text: never parse markup
                    text: ghostWin.grabbed?.title ?? ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                ScreencopyView {
                    y: Shared.titleBarHeight
                    width: parent.width
                    height: parent.height - Shared.titleBarHeight
                    captureSource: ghostWin.visible && ghostWin.ready ? ghostWin.grabbed?.wayland ?? null : null
                    live: false // one capture: live capture blacks out screenshots on this setup
                }
            }
        }
    }
}
