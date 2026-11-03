import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components.effects
import qs.services

// [macos] an app's icon the macOS way (mirrors the macos shell's SymbolTile): a full-colour app icon as
// it is (WhiteSur icons are already squircles); a symbolic icon or no icon becomes a white symbol on a
// squircle of an Apple system colour, lit from the top (gradient + hairline highlight).
Item {
    id: t

    property string icon // freedesktop icon name or path; "" = draw `name`
    property string name: "notifications" // Material Symbols fallback glyph
    property var tint: "blue" // a Colours.sys name or a colour
    property real size: 32

    // a path is used as is; a theme name the icon theme lacks falls back to the glyph tile (no checkerboard)
    readonly property string path: icon === "" ? "" : icon.startsWith("/") || icon.includes("://") ? icon : Quickshell.iconPath(icon, true)
    readonly property bool tile: path === "" || icon.endsWith("symbolic")
    readonly property color base: typeof tint === "string" && Colours.sys[tint] ? Colours.sys[tint] : tint

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        visible: t.tile
        radius: t.size * 0.2237 // Apple's icon corner ratio
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(t.base, 1.2) }
            GradientStop { position: 1; color: Qt.darker(t.base, 1.1) }
        }

        Rectangle { // top highlight
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
        }
    }

    Loader {
        anchors.centerIn: parent
        active: t.path !== ""
        sourceComponent: t.tile ? symbolicIcon : appIcon
    }

    Loader {
        anchors.centerIn: parent
        active: t.path === ""
        sourceComponent: MaterialIcon {
            text: t.name
            color: "white"
            fill: 1
            fontStyle: Tokens.font.icon.builders.small.size(Math.max(1, Math.round(t.size * 0.6 * 0.75))).build() // px → pt
        }
    }

    Component {
        id: appIcon

        IconImage {
            implicitSize: t.size
            source: t.path
            asynchronous: true
        }
    }

    Component {
        id: symbolicIcon

        ColouredIcon {
            implicitSize: Math.round(t.size * 0.6)
            source: t.path
            colour: "white"
        }
    }
}
