import QtQuick
import Quickshell
import Quickshell.Widgets

// Icon for a widget kind: its app's icon when it has one, else a symbol tile.
Item {
    id: ki

    property var kind
    property int size: 22

    implicitWidth: size
    implicitHeight: size

    readonly property var entry: kind?.appId && DesktopEntries.applications.values.length >= 0 ? (DesktopEntries.byId(kind.appId) ?? DesktopEntries.heuristicLookup(kind.appId)) : null

    IconImage {
        visible: ki.entry !== null
        anchors.fill: parent
        source: ki.entry ? Quickshell.iconPath(ki.entry.icon, "application-x-executable") : ""
    }

    SymbolTile { // like the widget gallery's app icons on macOS: the kind's Apple colour
        visible: ki.entry === null
        anchors.centerIn: parent
        size: Math.round(ki.size * 0.86) // the visible square of a WhiteSur app icon in the same box
        name: ki.kind?.glyph ?? "widgets"
        tint: ({ clock: "#2c2c2e", calendar: "red", weather: "blue", conditions: "cyan", battery: "green", system: "teal",
                 network: "blue", profile: "gray", music: "pink", notes: "yellow", shortcuts: "indigo", photos: "orange",
                 reminders: "orange", timer: "orange" })[ki.kind?.type] ?? "blue"
    }
}
