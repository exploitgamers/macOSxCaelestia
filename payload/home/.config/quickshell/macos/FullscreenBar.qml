pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// macOS-style title bar for fullscreen windows: push the pointer to the top
// edge and it slides down with the traffic lights and the window's name; it
// slides away when the pointer leaves. Red closes, green leaves fullscreen,
// yellow is disabled (no minimising in fullscreen, as on macOS).
// Overlay layer, so it's drawn above the fullscreen window.
PanelWindow {
    id: win

    required property ShellScreen modelData

    readonly property var top: ToplevelManager.activeToplevel
    readonly property bool fsActive: top?.fullscreen ?? false
    // apps with their own full-screen toolbar (a browser's tabs and address bar slide
    // down when the pointer reaches the top): this bar stays out of their way — its
    // trigger strip used to catch the pointer there, so Firefox's tabs never appeared
    readonly property bool ownChrome: /firefox|librewolf|zen|chrom|brave|vivaldi|microsoft-edge/i.test(top?.appId ?? "")
    // games: the strip took the pointer from a game whose c‍ursor reached the top edge
    readonly property bool isGame: Shared.gameApps.test(top?.appId ?? "")
    readonly property bool active: fsActive && !ownChrome && !isGame
    readonly property int barHeight: Shared.titleBarHeight
    property bool shown: false

    readonly property var hyprWindow: Hyprland.toplevels.values.find(t => t.wayland === top) ?? null

    function dispatchOnWindow(action: string): void {
        const h = hyprWindow;
        if (!h)
            return;
        const addr = String(h.address).startsWith("0x") ? h.address : "0x" + h.address;
        Hyprland.dispatch(action.replace("%ADDR%", `address:${addr}`));
    }

    onActiveChanged: if (!active) shown = false

    screen: modelData
    color: "transparent"
    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: barHeight + 6

    WlrLayershell.namespace: "macos-fsbar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    // Input only while fullscreen: a 2px trigger strip, or the bar once shown
    mask: Region { item: !win.active ? null : win.shown ? bar : trigger }

    Item {
        id: trigger

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2

        HoverHandler {
            onHoveredChanged: if (hovered) revealDelay.restart(); else revealDelay.stop()
        }
    }

    // A short dwell so flicking past the top edge doesn't pop it open
    Timer {
        id: revealDelay

        interval: 120
        onTriggered: win.shown = true
    }

    Timer {
        id: hideDelay

        interval: 350
        onTriggered: if (!barHover.hovered) win.shown = false
    }

    Spring {
        id: slide

        target: win.shown ? 0 : -win.barHeight - 4
        response: 0.3
    }

    Rectangle {
        id: bar

        anchors.left: parent.left
        anchors.right: parent.right
        y: slide.value
        height: win.barHeight
        color: Theme.alpha(Theme.surface, 0.94)
        opacity: win.active ? 1 : 0

        // hairline under the bar
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.alpha(Theme.fg, 0.1)
        }

        HoverHandler {
            id: barHover

            onHoveredChanged: if (!hovered) hideDelay.restart()
        }

        // double-click the bar leaves full screen (like double-clicking a title bar)
        TapHandler {
            onDoubleTapped: win.dispatchOnWindow('hl.dsp.window.fullscreen({ mode = "fullscreen", window = "%ADDR%" })')
        }

        // ── Traffic lights: 12px, 8px apart, 12px in (same as every title bar) ──
        Row {
            id: lights

            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7 // hyprbars bar_padding 12 / bar_button_padding 7: same lights as the title bars

            HoverHandler { id: lightsHover }

            Repeater {
                model: [
                    { colour: "#ff5f57", glyph: "×", enabled: true, action: () => win.top?.close() },
                    { colour: "#febc2e", glyph: "−", enabled: false, action: () => {} },
                    { colour: "#28c840", glyph: "+", enabled: true, action: () => win.dispatchOnWindow('hl.dsp.window.fullscreen({ mode = "fullscreen", window = "%ADDR%" })') }
                ]

                delegate: Item {
                    id: light

                    required property var modelData

                    width: 12
                    height: 12

                    // halo on the hovered light
                    Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 9
                        color: light.modelData.colour
                        opacity: lightMouse.containsMouse && light.modelData.enabled ? 0.38 : 0
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: light.modelData.enabled ? light.modelData.colour : Theme.alpha(Theme.fg, 0.22)
                        // slightly darker under the pointer, like a pressed-ready light
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "#000000"
                            opacity: lightMouse.containsMouse && light.modelData.enabled ? (lightMouse.pressed ? 0.3 : 0.18) : 0
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: light.modelData.glyph
                        visible: lightsHover.hovered && light.modelData.enabled
                        color: Qt.rgba(0, 0, 0, 0.75)
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: lightMouse

                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        enabled: light.modelData.enabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: light.modelData.action()
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 2 * (lights.width + 40))
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText // untrusted text: never parse markup
            text: win.top?.title ?? ""
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
