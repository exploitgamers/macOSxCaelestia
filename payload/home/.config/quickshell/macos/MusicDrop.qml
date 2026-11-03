pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris

// macOS-style "Now Playing" card. Drops down under the menu bar when a track
// starts or changes, stays while hovered, then springs back up.
// Click the artwork to bring the player app to the front.
PanelWindow {
    id: win

    required property ShellScreen modelData

    // playerctld is a proxy that mirrors another player; skip it to avoid duplicates
    readonly property var players: Mpris.players.values.filter(p => !(p.dbusName ?? "").includes("playerctld"))
    readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players[0] ?? null
    readonly property bool shown: player !== null && Config.musicWidget
        && !(ToplevelManager.activeToplevel?.fullscreen ?? false) // never over fullscreen apps
        && (Shared.musicPinned || hover.hovered || showTimer.running || menu.shown
            || (Config.musicAlways && player.isPlaying))

    function cardMenu(): var {
        return [
            { header: "Now Playing" },
            { label: "Drop Down on Track Change", checked: Config.musicMode === "auto", action: () => Config.setMusicMode("auto") },
            { label: "Always Show While Playing", checked: Config.musicMode === "always", action: () => Config.setMusicMode("always") },
            { label: "Keep Open", checked: Shared.musicPinned, action: () => Shared.musicPinned = !Shared.musicPinned },
            { separator: true },
            { label: "Open " + (win.player?.identity ?? "Player"), action: () => Shared.openPlayer(win.player) },
            { label: "Turn Off", action: () => Config.setMusicMode("off") }
        ];
    }

    function poke(): void {
        if (Config.musicWidget)
            showTimer.restart();
    }

    screen: modelData
    color: "transparent"
    anchors.top: true
    implicitWidth: 380
    implicitHeight: 128
    exclusiveZone: 0

    WlrLayershell.namespace: "macos-music"
    WlrLayershell.layer: WlrLayer.Overlay

    // the card's resting rectangle, not the card item: a Region tracking an item maps it
    // through its transforms once, when the item is set — the card was still tucked up
    // under the bar (drop spring), so the input region stayed there and no click landed
    mask: Region {
        x: card.x + (1 - scaleSpring.value) * card.width / 2
        y: card.y + dropSpring.value
        width: win.shown ? card.width * scaleSpring.value : 0
        height: win.shown ? card.height * scaleSpring.value : 0
    }

    GlassMenu {
        id: menu
    }

    Timer {
        id: showTimer

        interval: Config.musicShowMs
    }

    // Show on new track / play
    Connections {
        target: win.player
        ignoreUnknownSignals: true

        function onTrackTitleChanged(): void { win.poke(); }
        function onIsPlayingChanged(): void { if (win.player?.isPlaying) win.poke(); }
    }

    // Keep position fresh while visible
    Timer {
        running: win.shown && (win.player?.isPlaying ?? false)
        interval: 1000
        repeat: true
        onTriggered: win.player?.positionChanged()
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: parent.width - 16
        height: 104
        radius: Theme.panelRadius
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.glassBorder
        Behavior on color { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }

        // Light catching the top edge of the glass
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - parent.radius * 2
            height: 1
            color: Theme.alpha(Theme.fg, 0.14)
        }

        opacity: win.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // Materialises from the menu bar (its origin) and returns the same way:
        // position, scale and opacity move together, critically damped.
        Spring {
            id: dropSpring

            target: win.shown ? 0 : -card.height - 20
            response: 0.4
        }

        Spring {
            id: scaleSpring

            target: win.shown ? 1 : 0.86
            response: 0.4
            epsilon: 0.001
        }

        transform: [
            Translate { y: dropSpring.value },
            Scale {
                origin.x: card.width / 2
                origin.y: 0
                xScale: scaleSpring.value
                yScale: scaleSpring.value
            }
        ]

        HoverHandler { id: hover }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: menu.open(card, win.cardMenu(), Edges.Bottom)
        }

        Row {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            // Album art
            ClippingRectangle {
                width: 80
                height: 80
                radius: Theme.panelRadius - 12
                color: Theme.primaryContainer

                Image {
                    anchors.fill: parent
                    source: win.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 160
                    sourceSize.height: 160
                }

                Symbol { // no artwork: the Music app's pink note
                    anchors.centerIn: parent
                    visible: !(win.player?.trackArtUrl)
                    name: "music_note"
                    mode: "multicolor"
                    size: 36
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Shared.openPlayer(win.player)
                }
            }

            Column {
                width: parent.width - 80 - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    width: parent.width
                    textFormat: Text.PlainText // untrusted text: never parse markup
                    text: win.player?.trackTitle || "Not playing"
                    color: Theme.fg
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText // untrusted text: never parse markup
                    text: win.player?.trackArtist || win.player?.identity || ""
                    color: Theme.fgDim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 13
                }

                // Progress
                Item {
                    width: parent.width
                    height: 14

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.alpha(Theme.fg, 0.18)

                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: Theme.primary
                            width: {
                                const p = win.player;
                                if (!p || !p.lengthSupported || p.length <= 0)
                                    return 0;
                                return parent.width * Math.min(1, p.position / p.length);
                            }
                            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: win.player?.canSeek ?? false
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: event => win.player.position = (event.x / width) * win.player.length
                    }
                }

                // Controls
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 22

                    Repeater {
                        model: [
                            { icon: "fast_rewind", act: () => win.player?.previous(), ok: win.player?.canGoPrevious ?? false },
                            { icon: win.player?.isPlaying ? "pause" : "play_arrow", act: () => win.player?.togglePlaying(), ok: win.player?.canTogglePlaying ?? false },
                            { icon: "fast_forward", act: () => win.player?.next(), ok: win.player?.canGoNext ?? false }
                        ]

                        delegate: Symbol { // backward.fill / play.fill / forward.fill
                            id: btn

                            required property var modelData

                            name: modelData.icon
                            fill: true
                            size: modelData.icon === "pause" || modelData.icon === "play_arrow" ? 30 : 26
                            color: btnMouse.containsMouse ? Theme.primary : Theme.fg
                            opacity: modelData.ok ? 1 : 0.35
                            scale: btnSpring.value
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Spring {
                                id: btnSpring

                                target: btnMouse.pressed ? 0.85 : 1
                                response: 0.2
                                epsilon: 0.001
                            }

                            MouseArea {
                                id: btnMouse

                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: btn.modelData.act()
                            }
                        }
                    }
                }
            }
        }
    }
}
