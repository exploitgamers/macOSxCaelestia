import QtQuick

// A clickable row in an app widget (recent file, folder, project).
// TapHandler, so dragging the widget from a row still moves the widget.
Item {
    id: root

    property string icon: "draft"
    property string label
    property string detail
    signal activated

    implicitHeight: detail ? 34 : 28

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -6
        anchors.rightMargin: -6
        radius: 8
        color: hover.hovered ? Theme.alpha(Theme.fg, tap.pressed ? 0.16 : 0.09) : "transparent"
    }

    Symbol { // multicolor: folders blue, images purple, PDFs red… (Theme.symbolTints), else the accent
        id: glyph

        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        mode: "multicolor"
        size: 18
        weight: 500
        color: Theme.primary
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            textFormat: Text.PlainText // untrusted text: never parse markup
            text: root.label
            elide: Text.ElideMiddle
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        Text {
            visible: root.detail !== ""
            width: parent.width
            text: root.detail
            elide: Text.ElideLeft
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 10
        }
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tap

        onTapped: { Shared.widgetTapAt = Date.now(); root.activated() }
    }
}
