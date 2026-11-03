import QtQuick
import Quickshell

// Files widget (Thunar): favourite folders and recently used files.
// Header opens Thunar; folders open in Thunar; files open in their app.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""

    readonly property string home: Quickshell.env("HOME")
    readonly property var folders: [
        { icon: "home", name: "Home", path: home },
        { icon: "description", name: "Documents", path: home + "/Documents" },
        { icon: "download", name: "Downloads", path: home + "/Downloads" },
        { icon: "image", name: "Pictures", path: home + "/Pictures" },
        { icon: "movie", name: "Videos", path: home + "/Videos" },
        { icon: "music_note", name: "Music", path: home + "/Music" }
    ]

    function fileIcon(name: string): string {
        const ext = name.split(".").pop().toLowerCase();
        if (["png", "jpg", "jpeg", "webp", "gif", "svg"].includes(ext)) return "image";
        if (["mp4", "mkv", "mov", "webm", "kdenlive"].includes(ext)) return "movie";
        if (["mp3", "flac", "wav", "ogg", "m4a"].includes(ext)) return "music_note";
        if (["pdf"].includes(ext)) return "picture_as_pdf";
        if (["zip", "tar", "gz", "xz", "zst", "7z"].includes(ext)) return "folder_zip";
        return "draft";
    }

    function openFolder(path: string): void {
        Quickshell.execDetached(["thunar", path]);
    }

    AppHeader {
        x: 16
        y: 13
        appId: "thunar"
        title: "Files"
    }

    // small: 2×2 folder tiles
    Grid {
        visible: root.size === "small"
        x: 14
        y: 46
        columns: 2
        spacing: 6

        Repeater {
            model: root.folders.slice(0, 4)

            Rectangle {
                id: tile

                required property var modelData

                width: (root.width - 28 - 6) / 2
                height: 52
                radius: Theme.panelRadius - 14 // bottom tiles sit 14 px into the card corners
                color: Theme.alpha(Theme.fg, hover.hovered ? (tap.pressed ? 0.18 : 0.13) : 0.07)

                Column {
                    anchors.centerIn: parent
                    spacing: 1

                    // folders in Finder blue, other places multicolor where Apple tints them
                    Symbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: tile.modelData.icon
                        mode: "multicolor"
                        fill: true
                        color: Theme.sys.blue
                        size: 20
                        weight: 500
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText // untrusted text: never parse markup
                        text: tile.modelData.name
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }

                HoverHandler {
                    id: hover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: tap

                    onTapped: { Shared.widgetTapAt = Date.now(); root.openFolder(tile.modelData.path) }
                }
            }
        }
    }

    // medium / large: folders | recent files
    Column {
        visible: root.size !== "small"
        x: 16
        y: 44
        width: root.size === "large" ? root.width - 32 : root.width / 2 - 24

        Repeater {
            model: root.size === "large" ? [] : root.folders.slice(0, 4)

            AppRow {
                required property var modelData

                width: parent.width
                icon: modelData.icon
                label: modelData.name
                onActivated: root.openFolder(modelData.path)
            }
        }
    }

    // large: folder strip
    Row {
        visible: root.size === "large"
        x: 16
        y: 46
        spacing: 6

        Repeater {
            model: root.size === "large" ? root.folders : []

            Rectangle {
                id: chip

                required property var modelData

                width: (root.width - 32 - 5 * 6) / 6
                height: 50
                radius: 12
                color: Theme.alpha(Theme.fg, chipHover.hovered ? 0.13 : 0.07)

                Column {
                    anchors.centerIn: parent

                    Symbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: chip.modelData.icon
                        mode: "multicolor"
                        fill: true
                        color: Theme.sys.blue
                        size: 19
                        weight: 500
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: chip.width - 6
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText // untrusted text: never parse markup
                        text: chip.modelData.name
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 10
                    }
                }

                HoverHandler {
                    id: chipHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: { Shared.widgetTapAt = Date.now(); root.openFolder(chip.modelData.path) }
                }
            }
        }
    }

    Column {
        visible: root.size !== "small"
        x: root.size === "large" ? 16 : root.width / 2 + 8
        y: root.size === "large" ? 112 : 44
        width: root.size === "large" ? root.width - 32 : root.width / 2 - 24

        Text {
            text: "RECENT"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.5
            bottomPadding: 2
        }

        Text {
            visible: AppData.recentFiles.length === 0
            text: "No recent files"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 12
        }

        Repeater {
            model: AppData.recentFiles.slice(0, root.size === "large" ? 6 : 3)

            AppRow {
                required property var modelData

                width: parent.width
                icon: root.fileIcon(modelData.name)
                label: modelData.name
                detail: root.size === "large" ? modelData.path.replace(root.home, "~") : ""
                onActivated: AppData.open(modelData.path)
            }
        }
    }
}
