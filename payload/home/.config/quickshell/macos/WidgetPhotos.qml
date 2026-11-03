import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Photos widget: your newest pictures and screenshots (~/Pictures, ~/Downloads).
// Small: the latest, full-bleed. Medium: 3. Large: 3×3. Click a photo to open it;
// the header opens the Pictures folder.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({}) // Edit "Photos"…: folder (empty = Pictures & Downloads)

    readonly property int count: size === "small" ? 1 : size === "medium" ? 3 : 9
    // "~/x" and "x" (relative to home) both mean ~/x
    readonly property string folder: {
        const f = String(options.folder ?? "").trim();
        return !f ? "" : f.startsWith("/") ? f : Quickshell.env("HOME") + "/" + f.replace(/^~\/?/, "");
    }
    property var own: []
    readonly property var shown: (folder ? own : AppData.photos).slice(0, count)

    // the chosen folder's newest images (the path is an argument, never part of the script)
    Process {
        id: scan

        command: ["sh", "-c", "find \"$1\" -maxdepth 3 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) -printf '%T@ %p\\n' 2>/dev/null | sort -rn | head -9 | cut -d' ' -f2-", "sh", root.folder]
        stdout: StdioCollector {
            onStreamFinished: root.own = text.trim() ? text.trim().split("\n") : []
        }
    }

    onFolderChanged: {
        own = [];
        if (folder)
            Qt.callLater(() => scan.running = true); // after `command` has the new path
    }
    Component.onCompleted: if (folder) scan.running = true

    Timer {
        running: root.folder !== "" && root.widgetId !== ""
        interval: 30000
        repeat: true
        onTriggered: scan.running = true
    }

    Text {
        visible: root.shown.length === 0
        anchors.centerIn: parent
        width: parent.width - 32
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "No pictures yet\nScreenshots and photos appear here"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 12
    }

    // small: full-bleed latest photo
    ClippingRectangle {
        visible: root.size === "small" && root.shown.length > 0
        anchors.fill: parent
        radius: Theme.panelRadius
        color: "transparent"

        Image {
            anchors.fill: parent
            source: root.size === "small" && root.shown.length ? "file://" + root.shown[0] : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 360
            sourceSize.height: 360
        }

        TapHandler {
            onTapped: { Shared.widgetTapAt = Date.now(); AppData.open(root.shown[0]) }
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
    }

    AppHeader {
        visible: root.size !== "small"
        x: 16
        y: 13
        appId: "thunar"
        title: "Photos"
        command: ["thunar", root.folder || Quickshell.env("HOME") + "/Pictures"]
    }

    Grid {
        visible: root.size !== "small" && root.shown.length > 0
        x: 14
        y: 44
        columns: 3
        spacing: 6

        Repeater {
            model: root.size === "small" ? [] : root.shown

            ClippingRectangle {
                id: thumb

                required property string modelData

                width: (root.width - 28 - 12) / 3
                height: root.size === "medium" ? root.height - 44 - 14 : (root.height - 44 - 14 - 12) / 3
                radius: Theme.panelRadius - 14
                color: Theme.alpha(Theme.fg, 0.08)
                scale: tap.pressed ? 0.95 : 1

                Behavior on scale {
                    NumberAnimation { duration: 140 }
                }

                Image {
                    anchors.fill: parent
                    source: "file://" + thumb.modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 240
                    sourceSize.height: 240
                }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: tap

                    onTapped: { Shared.widgetTapAt = Date.now(); AppData.open(thumb.modelData) }
                }
            }
        }
    }
}
