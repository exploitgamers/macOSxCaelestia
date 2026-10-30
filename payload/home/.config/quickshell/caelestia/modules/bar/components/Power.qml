import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    BarInk { id: pillInk; pill: root }

    // [macos] as tall as the other pills (the bar's inner width)
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: Tokens.sizes.bar.innerWidth

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: Tokens.sizes.bar.innerWidth
        radius: Tokens.rounding.full
        // [macos] the "power" entry is the notifications button now (the logo opens the power menu)
        onClicked: root.screenState.sidebar = !root.screenState.sidebar
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "notifications"
        color: pillInk.c(Colours.palette.m3secondary) // [macos] adaptive (BarInk), like the status icons
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
    }
}
