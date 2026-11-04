import QtQuick
import Quickshell
import Quickshell.Widgets

// App widget header: the app's icon and name; clicking it opens the app.
// A TapHandler (not a MouseArea) so the widget can still be dragged from here.
Item {
    id: root

    property string appId
    property string title: entry?.name ?? appId
    property var command: null // optional override for opening the app
    // (touching the app list makes this update once apps have loaded)
    readonly property var entry: DesktopEntries.applications.values.length < 0 ? null : DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId)

    function open(): void {
        if (command)
            Quickshell.execDetached(command);
        else
            entry?.execute();
    }

    implicitHeight: 24
    implicitWidth: row.implicitWidth

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter // icon top 15 (was 13) next to the 16 px left inset
        spacing: 7
        opacity: tap.pressed ? 0.6 : 1

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 20
            source: Quickshell.iconPath(root.entry?.icon ?? root.appId, "application-x-executable")
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText // untrusted text: never parse markup
            text: root.title
            color: hover.hovered ? Theme.primary : Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Bold
        }
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tap

        onTapped: { Shared.widgetTapAt = Date.now(); root.open() }
    }
}
