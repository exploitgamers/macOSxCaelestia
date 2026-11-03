import QtQuick
import QtQuick.Templates
import Caelestia.Config
import qs.components
import qs.services

// [macos] a macOS Control Center toggle: a circle, Apple blue with a white filled symbol when on,
// translucent gray with an outline symbol when off; the colour and fill cross-fade in 180 ms.
// A drop-in for StyledSwitch (checkable: `checked`, `toggled()`).
AbstractButton {
    id: root

    property string symbol
    property real size: 28

    checkable: true
    implicitWidth: size
    implicitHeight: size

    scale: pressed ? 0.92 : 1

    Behavior on scale {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    background: Rectangle {
        radius: height / 2
        color: root.checked ? Colours.sys.blue : Qt.alpha(Colours.palette.m3onSurface, root.hovered ? 0.18 : 0.12)

        Behavior on color {
            ColorAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
    }

    contentItem: MaterialIcon {
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.symbol
        color: root.checked ? "white" : Colours.palette.m3onSurface
        fill: root.checked ? 1 : 0

        Behavior on fill {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
}
