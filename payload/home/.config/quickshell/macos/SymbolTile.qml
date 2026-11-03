import QtQuick

// macOS System Settings / Control Center style icon: a white filled symbol on a squircle of an Apple
// system colour, lit from the top (gradient + hairline highlight).
// `tint` is a colour or a Theme.sys name ("blue", "orange"…).
Rectangle {
    id: t

    property string name
    property var tint: "blue"
    property real size: 26
    property real glyphScale: 0.64

    readonly property color base: typeof tint === "string" && Theme.sys[tint] ? Theme.sys[tint] : tint

    implicitWidth: size
    implicitHeight: size
    radius: size * 0.2237 // Apple's icon corner ratio
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

    Symbol {
        anchors.centerIn: parent
        name: t.name
        size: t.size * t.glyphScale
        color: "white"
        fill: true
        weight: 500
    }
}
