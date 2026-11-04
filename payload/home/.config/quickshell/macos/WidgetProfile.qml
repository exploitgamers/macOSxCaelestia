import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Profile widget (replaces the dashboard's user card): picture, name, uptime.
// Medium adds the system line and Lock / Session buttons.
// Picture: ~/.face (any image) — otherwise your initial.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""

    property string fullName: Quickshell.env("USER")
    property string host: ""
    property string os: ""
    // only load ~/.face if it exists (a missing one logged "Cannot open" at every start);
    // Choose Profile Picture… (faceVersion) always leaves one behind
    property bool hasFace: false

    Process {
        running: true
        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1; cat /proc/sys/kernel/hostname; . /etc/os-release; echo \"$NAME\"; [ -e \"$HOME/.face\" ] && echo face"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                root.fullName = l[0] || Quickshell.env("USER");
                root.host = l[1] ?? "";
                root.os = l[2] ?? "";
                root.hasFace = l[3] === "face";
            }
        }
    }

    component Action: Rectangle {
        id: act

        property string icon
        property string label
        signal activated

        width: (root.width - 16 * 2 - 8) / 2
        height: 34
        radius: Theme.panelRadius - 16 // concentric: 16 px into the card corner
        color: area.containsMouse ? Theme.alpha(Theme.fg, 0.16) : Theme.alpha(Theme.fg, 0.08)

        Row {
            anchors.centerIn: parent
            spacing: 6

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: act.icon
                fill: true
                size: 17
                weight: 500
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: act.label
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.activated()
        }
    }

    ClippingRectangle {
        id: avatar

        x: 16
        y: 16
        width: root.size === "small" ? 62 : 72
        height: width
        radius: width / 2
        color: Theme.primary

        Text {
            anchors.centerIn: parent
            visible: face.status !== Image.Ready
            text: root.fullName.charAt(0).toUpperCase()
            color: Theme.fgOnPrimary
            font.family: Theme.font
            font.pixelSize: parent.width * 0.45
            font.weight: Font.DemiBold
        }

        Image {
            id: face

            anchors.fill: parent
            source: root.hasFace || Shared.faceVersion > 0 ? "file://" + Quickshell.env("HOME") + "/.face?v=" + Shared.faceVersion : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(144, 144) // a camera photo would otherwise decode at full size
            asynchronous: true
            cache: false
        }
    }

    Column {
        x: root.size === "small" ? 16 : avatar.x + avatar.width + 16
        y: root.size === "small" ? avatar.y + avatar.height + 10 : 22
        width: root.width - x - 16
        spacing: 1

        Text {
            width: parent.width
            text: root.fullName
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: root.size === "small" ? 15 : 18
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            text: root.size === "small" ? "Up " + SysStats.uptimeText()
                : `${Quickshell.env("USER")}@${root.host}  ·  up ${SysStats.uptimeText()}`
            elide: Text.ElideRight
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 12
        }

        Text {
            visible: root.size !== "small"
            width: parent.width
            text: root.os + "  ·  Hyprland"
            elide: Text.ElideRight
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 12
        }
    }

    Row {
        visible: root.size !== "small"
        x: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        spacing: 8

        Action {
            icon: "lock"
            label: "Lock"
            onActivated: Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "lock", "lock"])
        }

        Action {
            icon: "power_settings_new"
            label: "Session"
            onActivated: Quickshell.execDetached(["caelestia", "shell", "drawers", "toggle", "session"])
        }
    }
}
