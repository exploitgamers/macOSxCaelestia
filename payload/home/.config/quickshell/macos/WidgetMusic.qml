import QtQuick
import Quickshell.Widgets
import Quickshell.Services.Mpris

// Now Playing widget. Small: artwork, title, play/pause. Medium: artwork beside
// title, progress and controls. Large: bigger, with a seekable timeline.
// Clicking the widget brings the player app to the front.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""

    // playerctld mirrors another player; skip it to avoid duplicates
    readonly property var players: Mpris.players.values.filter(p => !(p.dbusName ?? "").includes("playerctld"))
    readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players[0] ?? null
    readonly property bool wide: size !== "small"

    function activate(): void {
        Shared.openPlayer(player);
    }

    function time(s: real): string {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // a round button: a soft circle on hover, filled accent for the main one (play/pause).
    // TapHandler, like the other widgets' buttons: it works alongside dragging the widget,
    // and marks the tap so the widget itself doesn't also open the player
    component Control: Item {
        id: ctl

        property string icon
        property bool enabledCtl: true
        property bool primary: false
        property int iconSize: 26
        signal activated

        implicitWidth: iconSize + (primary ? 18 : 14)
        implicitHeight: implicitWidth
        opacity: enabledCtl ? 1 : 0.35

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: ctl.primary ? Theme.primary : Theme.alpha(Theme.fg, tap.pressed ? 0.18 : hover.hovered ? 0.1 : 0)
            scale: tap.pressed ? 0.92 : 1

            Behavior on color {
                ColorAnimation { duration: 120 }
            }
            Behavior on scale {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }

        Symbol {
            anchors.centerIn: parent
            name: ctl.icon
            color: ctl.primary ? Theme.fgOnPrimary : Theme.fg
            size: ctl.iconSize
            fill: true
            weight: 600
        }

        HoverHandler {
            id: hover

            enabled: ctl.enabledCtl
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: tap

            enabled: ctl.enabledCtl
            onTapped: {
                Shared.widgetTapAt = Date.now();
                ctl.activated();
            }
        }
    }

    Column {
        visible: !root.player
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -2 // optical: the note's ink starts 5 px into its em box
        spacing: 6

        // Apple Music's pink note
        Symbol {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "music_note"
            mode: "multicolor"
            fill: true
            size: 42
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Not Playing"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    ClippingRectangle {
        id: art

        visible: root.player
        x: 16
        y: 16
        width: root.size === "small" ? 72 : root.size === "large" ? 150 : root.height - 32
        height: width
        radius: Theme.panelRadius - 16
        color: Theme.alpha(Theme.fg, 0.08)

        Image {
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 280
            sourceSize.height: 280
        }

        Symbol {
            visible: !(root.player?.trackArtUrl)
            anchors.centerIn: parent
            name: "music_note"
            mode: "multicolor"
            fill: true
            size: parent.width * 0.4
        }
    }

    Control {
        visible: root.player && root.size === "small"
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.top: parent.top
        anchors.topMargin: 14
        icon: root.player?.isPlaying ? "pause" : "play_arrow"
        primary: true
        iconSize: 22
        enabledCtl: root.player?.canTogglePlaying ?? false
        onActivated: root.player.togglePlaying()
    }

    Column {
        visible: root.player
        x: root.size === "small" ? 16 : art.x + art.width + 16
        y: root.size === "small" ? art.y + art.height + 10 : root.size === "large" ? 30 : 22
        width: root.width - x - 16
        spacing: 1

        Text {
            width: parent.width
            textFormat: Text.PlainText // untrusted text: never parse markup
            text: root.player?.trackTitle || "Unknown Title"
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: root.size === "large" ? 17 : 14
            font.weight: Font.DemiBold
            wrapMode: root.size === "large" ? Text.Wrap : Text.NoWrap
            maximumLineCount: root.size === "large" ? 2 : 1
        }

        Text {
            width: parent.width
            textFormat: Text.PlainText // untrusted text: never parse markup
            text: root.player?.trackArtist || root.player?.identity || ""
            elide: Text.ElideRight
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: root.size === "large" ? 14 : 12
        }

        Text {
            visible: root.size === "large"
            width: parent.width
            topPadding: 6
            textFormat: Text.PlainText // untrusted text: never parse markup
            text: root.player?.identity ?? ""
            elide: Text.ElideRight
            color: Theme.alpha(Theme.fg, 0.45)
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    // medium / large: progress (click or drag to seek) + controls
    Item {
        visible: root.player && root.wide
        x: root.size === "large" ? 16 : art.x + art.width + 16
        y: root.size === "large" ? art.y + art.height + 26 : 74
        width: root.size === "large" ? root.width - 32 : root.width - x - 18
        height: root.size === "large" ? 150 : 80

        Rectangle {
            id: track

            width: parent.width
            height: 4
            radius: 2
            color: Theme.alpha(Theme.fg, 0.15)

            Rectangle {
                width: root.player && root.player.length > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                height: 4
                radius: 2
                color: Theme.fg
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                enabled: root.player?.canSeek ?? false
                cursorShape: Qt.PointingHandCursor
                function seek(x: real): void {
                    root.player.position = Math.max(0, Math.min(1, (x - 8) / track.width)) * root.player.length;
                }
                onPressed: m => seek(m.x)
                onPositionChanged: m => seek(m.x)
            }
        }

        Text {
            visible: root.size === "large"
            anchors.top: track.bottom
            anchors.topMargin: 5
            text: root.time(root.player?.position ?? 0)
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 11
            font.features: { "tnum": 1 }
        }

        Text {
            visible: root.size === "large"
            anchors.top: track.bottom
            anchors.topMargin: 5
            anchors.right: parent.right
            text: "-" + root.time((root.player?.length ?? 0) - (root.player?.position ?? 0))
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 11
            font.features: { "tnum": 1 }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: track.bottom
            anchors.topMargin: root.size === "large" ? 30 : 14
            spacing: root.size === "large" ? 28 : 16

            Control {
                anchors.verticalCenter: parent.verticalCenter
                icon: "skip_previous"
                iconSize: 24
                enabledCtl: root.player?.canGoPrevious ?? false
                onActivated: root.player.previous()
            }

            Control {
                anchors.verticalCenter: parent.verticalCenter
                icon: root.player?.isPlaying ? "pause" : "play_arrow"
                primary: true
                iconSize: 26
                enabledCtl: root.player?.canTogglePlaying ?? false
                onActivated: root.player.togglePlaying()
            }

            Control {
                anchors.verticalCenter: parent.verticalCenter
                icon: "skip_next"
                iconSize: 24
                enabledCtl: root.player?.canGoNext ?? false
                onActivated: root.player.next()
            }
        }
    }

    // keep progress moving
    Timer {
        running: root.visible && root.wide && (root.player?.isPlaying ?? false) && Shared.widgetsLive
        interval: 1000
        repeat: true
        onTriggered: root.player?.positionChanged()
    }
}
