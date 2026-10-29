pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// SUPER+Tab desktop indicator (hypr-qol.lua mac_desktop → custom>>macdesk):
// a small pill near the top — "Desktop 2" over a row of dots, one per desktop,
// the current one long. Fades out after a moment.
PanelWindow {
    id: ind

    required property ShellScreen modelData

    property bool here: false // set per desktop change: a binding to the focused display followed the pointer
    property int current: 1
    property var desktops: []
    property bool active: false
    readonly property bool shown: active && here

    Connections {
        target: Shared

        function onDesktopChanged(current: int, desktops: var): void {
            ind.current = current;
            ind.desktops = desktops;
            ind.here = (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === ind.modelData?.name;
            ind.active = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer

        interval: 1100
        onTriggered: ind.active = false
    }

    screen: modelData
    color: "transparent"
    anchors.top: true
    margins.top: 70
    visible: shown || pop.value > 0.01
    implicitWidth: Math.max(170, dots.implicitWidth + 48)
    implicitHeight: 70
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    WlrLayershell.namespace: "macos-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Spring {
        id: pop

        target: ind.shown ? 1 : 0
        response: 0.25
        epsilon: 0.004
    }

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.glassBorder
        opacity: pop.value
        scale: 0.94 + 0.06 * pop.value
        transform: Translate { y: (1 - pop.value) * -10 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 10 // cap height then sits 14 px from the top, like the dots from the bottom
            text: "Desktop " + ind.current
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        Row {
            id: dots

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 6

            Repeater {
                model: ind.desktops

                Rectangle {
                    required property int modelData

                    width: modelData === ind.current ? 20 : 7
                    height: 7
                    radius: 3.5
                    color: modelData === ind.current ? Theme.primary : Theme.alpha(Theme.fg, 0.35)

                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
