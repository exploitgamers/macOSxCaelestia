pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// [macos] the top bar's volume / brightness pill, expanded (on click, or when the
// volume / brightness keys are pressed — this replaces the left-edge OSD): the
// OSD's filled sliders laid horizontally, scrollable, and a way into Settings → Sound.
Column {
    id: root

    readonly property var monitor: Brightness.getMonitor("active")

    spacing: Tokens.spacing.medium

    // the OSD's filled slider, lying down: drag or click anywhere on it, scroll to step
    component Bar: Rectangle {
        id: bar

        property string icon
        property real iconFill: 1
        property real value
        property real to: 1
        signal moved(real value)
        signal stepped(int dir)

        // while dragging, the fill follows the pointer at once; the real value comes back
        // from the system a moment later and made it lag and jump
        property real dragValue: 0
        readonly property real shown: barMouse.pressed ? dragValue : value
        readonly property real frac: Math.max(0, Math.min(1, shown / to))

        width: 260
        height: Tokens.sizes.osd.sliderWidth
        radius: height / 2
        color: Qt.alpha(Colours.palette.m3onSurface, 0.12) // [macos] Control Center: a translucent track…

        Rectangle {
            width: Math.max(bar.height, bar.width * bar.frac)
            height: parent.height
            radius: parent.radius
            color: Colours.light ? "white" : Qt.rgba(1, 1, 1, 0.92) // [macos] …with a white level

            Behavior on width {
                enabled: !barMouse.pressed
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }

        MaterialIcon {
            x: (bar.height - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            text: bar.icon
            fill: bar.iconFill
            color: Qt.rgba(0, 0, 0, 0.55) // [macos] the symbol sits on the white level, in gray
        }

        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.medium
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(bar.shown * 100) + "%"
            font: Tokens.font.body.small
            color: bar.frac > 0.85 ? Qt.rgba(0, 0, 0, 0.55) : Colours.palette.m3onSurfaceVariant // [macos] over the white level
        }

        CustomMouseArea {
            id: barMouse

            function pick(x: real): void {
                bar.dragValue = Math.max(0, Math.min(1, x / bar.width)) * bar.to;
                bar.moved(bar.dragValue);
            }

            function onWheel(event: WheelEvent): void {
                bar.stepped(event.angleDelta.y > 0 ? 1 : -1);
            }

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: event => pick(event.x)
            onPositionChanged: event => {
                if (pressed)
                    pick(event.x);
            }
        }
    }

    Bar {
        icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
        value: Audio.volume
        to: GlobalConfig.services.maxVolume
        onMoved: v => Audio.setVolume(v)
        onStepped: dir => dir > 0 ? Audio.incrementVolume() : Audio.decrementVolume()
    }

    Bar {
        visible: root.monitor !== undefined && root.monitor !== null
        icon: "light_mode" // [macos] sun.min / sun.max: outline when dim, filled when bright
        iconFill: value >= 0.5 ? 1 : 0
        value: root.monitor?.brightness ?? 0
        onMoved: v => root.monitor?.setBrightness(v)
        onStepped: dir => root.monitor?.setBrightness(root.monitor.brightness + dir * GlobalConfig.services.brightnessIncrement)
    }

    StyledRect {
        anchors.horizontalCenter: parent.horizontalCenter
        width: settingsText.implicitWidth + Tokens.padding.large * 2
        height: settingsText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer

        StyledText {
            id: settingsText

            anchors.centerIn: parent
            text: "Sound…"
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurface
        }

        StateLayer {
            radius: parent.radius
            color: Colours.palette.m3onSurface
            onClicked: Quickshell.execDetached(["qs", "-c", "macos", "ipc", "call", "settings", "page", "sound"])
        }
    }
}
