import QtQuick
import Quickshell

// Timer widget: pick 1 / 5 / 10 / 25 minutes; a ring counts down, and a
// notification fires when it's done. While running: pause/resume and cancel.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({}) // Edit "Timer"…: presets, e.g. "3, 15, 45, 90" (minutes)

    property real total: 0      // seconds
    property real remaining: 0  // seconds
    property bool running: false
    property real endsAt: 0     // ms timestamp while running
    readonly property bool active: total > 0
    // up to four positive numbers from the option, else the usual four
    readonly property var presets: {
        const own = String(options.presets ?? "").split(/[^0-9.]+/).map(Number).filter(n => n > 0 && n <= 1440).slice(0, 4);
        return own.length ? own : [1, 5, 10, 25];
    }

    function start(min: real): void {
        total = min * 60;
        remaining = total;
        endsAt = Date.now() + total * 1000;
        running = true;
    }

    // pause keeps what's left; resume sets a new end time from it
    onRunningChanged: if (running && total > 0) endsAt = Date.now() + remaining * 1000

    function cancel(): void {
        running = false;
        total = 0;
        remaining = 0;
    }

    function fmt(s: real): string {
        s = Math.ceil(s);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    Timer {
        running: root.running
        // computed from the end time, so a slower tick (desktop covered) stays exact
        interval: Shared.widgetsLive ? 250 : 1000
        repeat: true
        onTriggered: {
            root.remaining = Math.max(0, (root.endsAt - Date.now()) / 1000);
            if (root.remaining === 0) {
                root.running = false;
                Quickshell.execDetached(["notify-send", "-a", "Timer", "-i", "alarm", "Timer done", `${+(root.total / 60).toFixed(1)} minute timer finished`]);
                root.total = 0;
            }
        }
    }

    component Chip: Rectangle {
        id: chip

        property string label
        property string glyph: ""
        signal activated

        width: root.size === "small" ? 62 : 70
        height: root.size === "small" ? 30 : 34
        radius: height / 2
        // Apple's Timer orange
        color: area.containsMouse ? Theme.alpha(Theme.sys.orange, area.pressed ? 1 : 0.85) : Theme.alpha(Theme.fg, 0.09)

        Text {
            visible: !chip.glyph
            anchors.centerIn: parent
            text: chip.label
            color: area.containsMouse ? "white" : Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Symbol {
            visible: chip.glyph !== ""
            anchors.centerIn: parent
            name: chip.glyph
            fill: true
            size: 20
            weight: 600
            color: area.containsMouse ? "white" : Theme.fg
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activated()
        }
    }

    Text {
        x: 16
        y: 13
        text: "Timer"
        color: Theme.sys.orange
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.Bold
    }

    // idle: presets
    Grid {
        visible: !root.active
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 10
        columns: root.size === "small" ? 2 : 4
        spacing: 8

        Repeater {
            model: root.presets

            Chip {
                required property real modelData

                label: modelData + " min"
                onActivated: root.start(modelData)
            }
        }
    }

    // running: ring + time (+ controls)
    Item {
        visible: root.active
        anchors.fill: parent

        Item {
            id: dial

            width: root.size === "small" ? 96 : 116
            height: width
            x: root.size === "small" ? (root.width - width) / 2 : 24
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.size === "small" ? -4 : 8

            Ring {
                anchors.fill: parent
                value: root.total > 0 ? root.remaining / root.total : 0
                thickness: 7
                colour: root.running ? Theme.sys.orange : Theme.fgDim
            }

            Text {
                anchors.centerIn: parent
                text: root.fmt(root.remaining)
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: root.size === "small" ? 22 : 26
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
        }

        Row {
            spacing: 8
            anchors.bottom: root.size === "small" ? parent.bottom : undefined
            anchors.bottomMargin: 10
            anchors.horizontalCenter: root.size === "small" ? parent.horizontalCenter : undefined
            anchors.verticalCenter: root.size === "small" ? undefined : parent.verticalCenter
            anchors.left: root.size === "small" ? undefined : dial.right
            anchors.leftMargin: 28

            Chip {
                glyph: root.running ? "pause" : "play_arrow"
                width: root.size === "small" ? 40 : 70
                onActivated: root.running = !root.running
            }

            Chip {
                glyph: "close"
                width: root.size === "small" ? 40 : 70
                onActivated: root.cancel()
            }
        }
    }
}
