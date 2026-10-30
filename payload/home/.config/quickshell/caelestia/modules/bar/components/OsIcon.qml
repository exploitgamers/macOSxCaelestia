import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property ScreenState screenState

    // [macos] as tall as the other pills (the bar's inner width)
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: Tokens.sizes.bar.innerWidth

    BarInk { id: pillInk; pill: root }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // [macos] the power menu (session), like the Apple menu; the power button became notifications
        onClicked: root.screenState.session = !root.screenState.session
    }

    Loader {
        asynchronous: true
        anchors.centerIn: parent
        sourceComponent: SysInfo.isDefaultLogo ? caelestiaLogo : distroIcon
    }

    Component {
        id: caelestiaLogo

        Logo {
            topColour: pillInk.c(Colours.palette.m3primary) // [macos] adaptive (BarInk)
            bottomColour: pillInk.c(Colours.palette.m3onSurface)
            implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.6)
            implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.6)
        }
    }

    Component {
        id: distroIcon

        ColouredIcon {
            source: SysInfo.osLogo
            implicitSize: Math.round(Tokens.font.body.large.pointSize * 1.2 * Tokens.sizes.bar.innerWidth / 26) // [macos] with the bar
            colour: pillInk.c(Colours.palette.m3tertiary) // [macos] adaptive (BarInk)
        }
    }

    HoverWash {} // [macos] the bar's one hover hint
}
