import QtQuick
import Quickshell

// Calendar widget. Small: weekday and date. Medium: date beside the month.
// Large: the month, big.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({}) // Edit "Calendar"…: firstDay auto|sun|mon, weekNumbers

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    readonly property date today: clock.date
    readonly property int firstDay: options.firstDay === "sun" ? 0 : options.firstDay === "mon" ? 1 : Qt.locale().firstDayOfWeek % 7 // 0 = Sunday
    readonly property bool weekNumbers: options.weekNumbers === true && size !== "small"
    readonly property int columns: weekNumbers ? 8 : 7

    // ISO 8601 week number of the week holding `d`
    function isoWeek(d: date): int {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7);
    }
    property int monthOffset: 0 // large size: ‹ › browse months
    readonly property date shown: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)
    readonly property bool thisMonth: monthOffset === 0

    // 42 cells (6 weeks) for the shown month; day 0 = outside the month
    readonly property var cells: {
        const y = shown.getFullYear(), m = shown.getMonth();
        const lead = (new Date(y, m, 1).getDay() - firstDay + 7) % 7;
        const days = new Date(y, m + 1, 0).getDate();
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = i - lead + 1;
            out.push(d >= 1 && d <= days ? d : 0);
        }
        // drop a trailing empty week
        const weeks = out.slice(35).every(d => d === 0) ? out.slice(0, 35) : out;
        if (!weekNumbers)
            return weeks;
        // a leading cell per week holds its number, stored negative (-1…-53)
        const rows = [];
        for (let w = 0; w < weeks.length; w += 7) {
            const d = weeks.slice(w, w + 7).find(v => v > 0);
            rows.push(-isoWeek(new Date(y, m, d)));
            for (let i = 0; i < 7; i++)
                rows.push(weeks[w + i]);
        }
        return rows;
    }

    // Weekday + big date (small, and the left half of medium)
    Column {
        visible: root.size !== "large"
        x: 16
        y: 14
        width: root.size === "small" ? root.width - 32 : root.width / 2 - 40
        spacing: -4

        Text {
            text: Qt.formatDateTime(root.today, "dddd").toUpperCase()
            color: Theme.sys.red // Apple Calendar's red
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 0.6
        }

        Text {
            text: root.today.getDate()
            color: Theme.fg
            font.family: Theme.displayFont
            font.pixelSize: 64
            font.weight: Font.Light
        }

        Text {
            topPadding: 8
            text: Qt.formatDateTime(root.today, "MMMM yyyy")
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    // Month grid (medium: right half, large: whole widget)
    Column {
        id: month

        visible: root.size !== "small"
        x: root.size === "medium" ? root.width / 2 - 14 : 18
        y: root.size === "medium" ? 14 : 16
        width: root.size === "medium" ? root.width / 2 : root.width - 36
        spacing: root.size === "large" ? 8 : 2

        readonly property real cellW: width / root.columns
        readonly property real cellH: root.size === "large" ? 38 : 17

        Item {
            width: parent.width
            height: monthName.height

            Text {
                id: monthName

                text: Qt.formatDateTime(root.size === "large" ? root.shown : root.today, root.size === "large" ? "MMMM yyyy" : "MMMM").toUpperCase()
                color: Theme.sys.red
                font.family: Theme.font
                font.pixelSize: root.size === "large" ? 15 : 11
                font.weight: Font.Bold
                font.letterSpacing: 0.6
                bottomPadding: root.size === "large" ? 4 : 1
            }

            Row {
                visible: root.size === "large"
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: -4
                spacing: 2

                Repeater {
                    model: [{ icon: "chevron_left", step: -1 }, { icon: "today", step: 0 }, { icon: "chevron_right", step: 1 }]

                    Rectangle {
                        required property var modelData

                        width: 28
                        height: 28
                        radius: 8
                        visible: modelData.step !== 0 || !root.thisMonth
                        color: navArea.containsMouse ? Theme.alpha(Theme.fg, 0.12) : "transparent"

                        Symbol {
                            anchors.centerIn: parent
                            name: parent.modelData.icon
                            size: 20
                            weight: 600 // next to the bold month name
                            color: parent.modelData.step === 0 ? Theme.sys.red : Theme.fg
                        }

                        MouseArea {
                            id: navArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.monthOffset = parent.modelData.step === 0 ? 0 : root.monthOffset + parent.modelData.step
                        }
                    }
                }
            }
        }

        Row {
            Item {
                visible: root.weekNumbers
                width: month.cellW
                height: 1
            }

            Repeater {
                model: 7

                Text {
                    required property int index

                    width: month.cellW
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((index + root.firstDay) % 7, Locale.NarrowFormat)
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: root.size === "large" ? 13 : 9
                    font.weight: Font.DemiBold
                }
            }
        }

        Grid {
            columns: root.columns

            Repeater {
                model: root.cells

                Item {
                    required property int modelData

                    readonly property bool isToday: root.thisMonth && modelData === root.today.getDate()
                    readonly property bool weekCell: modelData < 0

                    width: month.cellW
                    height: month.cellH

                    Rectangle {
                        visible: parent.isToday
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - (root.size === "large" ? 4 : 1)
                        height: width
                        radius: width / 2
                        color: Theme.sys.red
                    }

                    Text {
                        anchors.centerIn: parent
                        text: parent.weekCell ? -parent.modelData : parent.modelData || ""
                        color: parent.isToday ? "white" : parent.weekCell ? Theme.alpha(Theme.fg, 0.4) : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: (root.size === "large" ? 16 : 10) - (parent.weekCell ? 3 : 0)
                        font.weight: parent.isToday ? Font.Bold : parent.weekCell ? Font.DemiBold : Font.Normal
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
}
