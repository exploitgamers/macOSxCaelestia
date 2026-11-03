import QtQuick
import Quickshell
import Quickshell.Io

// Clock widget. Small: analog face. Medium: face plus digital time and date.
// Options (Edit "Clock"…): analog or digital, and a city (world clock: any tz database city,
// e.g. "Tokyo", "New York", or a zone like "Europe/Paris"; empty = local time).
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({})

    readonly property bool digital: options.style === "digital"
    readonly property string city: (options.city ?? "").trim()
    property string zone: ""       // the city's tz database zone, once found
    property int zoneOffset: 0     // its UTC offset now, in minutes
    readonly property bool world: city !== "" && zone !== ""
    readonly property string placeName: world ? zone.split("/").pop().replace(/_/g, " ") : ""
    // the time shown: the city's when one is set
    readonly property date now: world ? new Date(clock.date.getTime() + (zoneOffset + clock.date.getTimezoneOffset()) * 60000) : clock.date

    // city → zone + offset. The text is an argument (never part of the script) and is matched
    // as plain text: the zone's last part exactly, else any zone containing it.
    Process {
        id: zoneLookup

        command: ["sh", "-c", "c=$(printf %s \"$1\" | tr ' ' _); l=$(timedatectl list-timezones 2>/dev/null);"
            + " z=$(printf '%s\\n' \"$l\" | awk -F/ -v c=\"$c\" 'tolower($NF)==tolower(c){print;exit}');"
            + " [ -n \"$z\" ] || z=$(printf '%s\\n' \"$l\" | grep -iF -m1 -- \"$c\");"
            + " [ -n \"$z\" ] && TZ=\"$z\" date \"+%z $z\"", "sh", root.city]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^([+-])(\d\d)(\d\d) (\S+)$/);
                root.zone = m ? m[4] : "";
                root.zoneOffset = m ? (m[1] === "-" ? -1 : 1) * (parseInt(m[2]) * 60 + parseInt(m[3])) : 0;
            }
        }
    }

    onCityChanged: {
        zone = "";
        if (city)
            Qt.callLater(() => zoneLookup.running = true); // after `command` has the new city
    }
    Component.onCompleted: if (city) zoneLookup.running = true

    // daylight saving moves the offset: look again every hour
    Timer {
        running: root.city !== ""
        interval: 3600000
        repeat: true
        onTriggered: zoneLookup.running = true
    }

    SystemClock {
        id: clock

        // seconds only while the desktop is visible (or in the gallery preview)
        precision: root.widgetId === "" || Shared.widgetsLive ? SystemClock.Seconds : SystemClock.Minutes
    }

    Item {
        id: face

        visible: !root.digital
        readonly property real r: width / 2

        width: Math.min(root.height, root.size === "small" ? root.width : root.width / 2) - 20
        height: width
        anchors.verticalCenter: parent.verticalCenter
        x: root.size === "small" ? (root.width - width) / 2 : 14

        // minute ticks
        Repeater {
            model: 60

            Rectangle {
                required property int index

                readonly property bool major: index % 5 === 0

                x: face.r - width / 2
                y: 2
                width: major ? 2 : 1
                height: major ? 7 : 4
                radius: 1
                color: Theme.alpha(Theme.fg, major ? 0.55 : 0.25)
                transform: Rotation { origin.x: width / 2; origin.y: face.r - 2; angle: index * 6 }
            }
        }

        // hour numerals
        Repeater {
            model: 12

            Text {
                required property int index

                readonly property real a: (index + 1) * Math.PI / 6

                x: face.r + Math.sin(a) * (face.r - 21) - width / 2
                y: face.r - Math.cos(a) * (face.r - 21) - height / 2
                text: index + 1
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: face.width * 0.105
                font.weight: Font.Medium
            }
        }

        component Hand: Rectangle {
            id: hand

            property real turn // degrees clockwise from 12
            property real length

            x: face.r - width / 2
            y: face.r - length
            height: length + 6
            radius: width / 2
            antialiasing: true
            transform: Rotation { origin.x: hand.width / 2; origin.y: hand.length; angle: hand.turn }
        }

        Hand {
            width: 5
            length: face.r * 0.5
            color: Theme.fg
            turn: (root.now.getHours() % 12 + root.now.getMinutes() / 60) * 30
        }

        Hand {
            width: 3.5
            length: face.r * 0.76
            color: Theme.fg
            turn: (root.now.getMinutes() + clock.seconds / 60) * 6
        }

        Hand {
            visible: clock.precision === SystemClock.Seconds
            width: 1.5
            length: face.r * 0.84
            color: Theme.sys.orange // Apple's second hand
            turn: clock.seconds * 6
        }

        // world clock: the city, in the lower half of the face
        Text {
            visible: root.world && root.size === "small"
            anchors.horizontalCenter: parent.horizontalCenter
            y: face.r * 1.32
            width: face.r
            horizontalAlignment: Text.AlignHCenter
            text: root.placeName.toUpperCase()
            elide: Text.ElideRight
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 0.5
        }

        Rectangle {
            anchors.centerIn: parent
            width: 7
            height: 7
            radius: 3.5
            color: Theme.sys.orange
            border.width: 1.5
            border.color: Theme.fg
        }
    }

    Column {
        visible: root.size !== "small" && !root.digital
        anchors.left: face.right
        anchors.leftMargin: 18
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: (root.world ? root.placeName : Qt.formatDateTime(root.now, "dddd")).toUpperCase()
            elide: Text.ElideRight
            color: Theme.sys.orange
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6
        }

        Text {
            text: Qt.formatDateTime(root.now, Config.clock24 ? "HH:mm" : "h:mm")
            color: Theme.fg
            font.family: Theme.displayFont
            font.pixelSize: 46
            font.weight: Font.Light
            font.features: { "tnum": 1 }
        }

        Text {
            text: Qt.formatDateTime(root.now, root.world ? "ddd d MMMM" : "d MMMM yyyy") + (Config.clock24 ? "" : "  ·  " + Qt.formatDateTime(root.now, "AP"))
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    // digital style: the time, big, with the day (or city) above and the date below
    Column {
        visible: root.digital
        anchors.centerIn: parent
        width: parent.width - 32
        spacing: root.size === "small" ? 0 : 2

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: (root.world ? root.placeName : Qt.formatDateTime(root.now, "dddd")).toUpperCase()
            elide: Text.ElideRight
            color: Theme.sys.orange
            font.family: Theme.font
            font.pixelSize: root.size === "small" ? 12 : 13
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(root.now, Config.clock24 ? "HH:mm" : "h:mm")
            color: Theme.fg
            font.family: Theme.displayFont
            font.pixelSize: root.size === "small" ? 50 : 64
            font.weight: Font.Light
            font.features: { "tnum": 1 }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(root.now, root.size === "small" ? "ddd d MMM" : "dddd d MMMM") + (Config.clock24 ? "" : "  ·  " + Qt.formatDateTime(root.now, "AP"))
            elide: Text.ElideRight
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 13
        }
    }
}
