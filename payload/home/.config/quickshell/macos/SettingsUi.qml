import QtQuick
import QtQuick.Controls.Basic as C

// The controls of Desktop Settings (Settings.qml and its Settings*.qml pages), in
// their own file so the pages can use them without a cyclic import:
// SettingsUi.Group, .Setting, .Toggle, .Segmented, .Slider, .Choice, .Button
QtObject {
    // ── controls ─────────────────────────────────────────────────────
    // a titled card of rows, like a System Settings group
    component Group: Column {
        id: group

        property string title
        property string note
        default property alias rows: box.data

        width: parent?.width ?? 0
        spacing: 8

        Text {
            visible: group.title !== ""
            x: 4
            text: group.title
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Rectangle {
            width: group.width
            height: box.implicitHeight
            radius: 10
            color: Theme.alpha(Theme.fg, 0.05)
            border.width: 1
            border.color: Theme.alpha(Theme.fg, 0.07)

            Column {
                id: box

                width: parent.width
            }
        }

        Text {
            visible: group.note !== ""
            x: 4
            width: group.width - 8
            wrapMode: Text.WordWrap
            text: group.note
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    // one row: label (and detail) on the left, its control on the right
    component Setting: Item {
        id: row

        property string label
        property string detail
        default property alias control: slot.data

        width: parent?.width ?? 0
        implicitHeight: Math.max(46, texts.implicitHeight + 22)

        Rectangle { // separator from the row above
            visible: row.y > 0
            x: 14
            width: row.width - 14
            height: 1
            color: Theme.alpha(Theme.fg, 0.07)
        }

        Column {
            id: texts

            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: row.width - slot.width - 44
            spacing: 2

            Text {
                width: parent.width
                text: row.label
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 13
            }

            Text {
                visible: row.detail !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: row.detail
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        Item {
            id: slot

            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    component Toggle: Rectangle {
        id: tg

        property bool checked
        signal toggled(bool on)

        width: 40
        height: 24
        radius: 12
        color: checked ? Theme.primary : Theme.alpha(Theme.fg, 0.2)

        Behavior on color {
            ColorAnimation { duration: 160 }
        }

        Rectangle {
            x: tg.checked ? tg.width - width - 2 : 2
            y: 2
            width: 20
            height: 20
            radius: 10
            color: "white"
            border.width: 0.5 // the knob's edge shadow, as on a macOS switch
            border.color: Qt.rgba(0, 0, 0, 0.12)

            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tg.toggled(!tg.checked)
        }
    }

    // options: [[value, label], …]
    component Segmented: Rectangle {
        id: seg

        property var options: []
        property string value
        signal picked(string value)

        width: segRow.width + 4
        height: 26
        radius: 7
        color: Theme.alpha(Theme.fg, 0.08)

        Row {
            id: segRow

            x: 2
            y: 2

            Repeater {
                model: seg.options

                Rectangle {
                    id: opt

                    required property var modelData
                    readonly property bool on: seg.value === modelData[0]

                    width: Math.max(52, optText.implicitWidth + 20)
                    height: 22
                    radius: 5
                    color: on ? Theme.alpha(Theme.fg, 0.2) : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        id: optText

                        anchors.centerIn: parent
                        text: opt.modelData[1]
                        color: opt.on ? Theme.fg : Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: opt.on ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(opt.modelData[0])
                    }
                }
            }
        }
    }

    component Slider: Item {
        id: sl

        property real from: 0
        property real to: 1
        property real value
        property real step: 0
        property string text // the value, shown left of the track
        signal moved(real value)

        readonly property real frac: Math.max(0, Math.min(1, (value - from) / (to - from)))

        width: 230
        height: 24

        function pick(px: real): void {
            let v = from + Math.max(0, Math.min(1, px / track.width)) * (to - from);
            if (step > 0)
                v = Math.round(v / step) * step;
            sl.moved(Math.round(v * 1000) / 1000);
        }

        Text {
            anchors.right: track.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: sl.text
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 12
            font.features: { "tnum": 1 }
        }

        Rectangle {
            id: track

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 160
            height: 4
            radius: 2
            color: Theme.alpha(Theme.fg, 0.15)

            Rectangle {
                width: track.width * sl.frac
                height: parent.height
                radius: 2
                color: Theme.primary
            }

            Rectangle {
                x: track.width * sl.frac - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                radius: 9
                color: "white"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.15)
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                cursorShape: Qt.PointingHandCursor
                onPressed: m => sl.pick(m.x - 10)
                onPositionChanged: m => {
                    if (pressed)
                        sl.pick(m.x - 10);
                }
            }
        }
    }

    // a pop-up menu of options: [[value, label], …]
    component Choice: Rectangle {
        id: ch

        property var options: []
        property string value
        signal picked(string value)

        width: Math.min(260, Math.max(170, chText.implicitWidth + 46))
        height: 26
        radius: 7
        color: Theme.alpha(Theme.fg, chMouse.containsMouse ? 0.12 : 0.08)

        Text {
            id: chText

            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, ch.width - 36) // long device names end in "…"
            elide: Text.ElideRight
            text: (ch.options.find(o => o[0] === ch.value) ?? [ch.value, ch.value])[1]
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 12
        }

        Symbol { // chevron.up.chevron.down
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            name: "unfold_more"
            size: 16
            weight: 600
            color: Theme.fgDim
        }

        MouseArea {
            id: chMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pop.open()
        }

        C.Popup {
            id: pop

            y: ch.height + 4
            width: Math.max(ch.width, 320) // full names in the list
            x: ch.width - width // right-aligned with the button, inside the window
            padding: 4

            background: Rectangle {
                radius: 9
                color: Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.glassBorder
            }

            contentItem: Column {
                Repeater {
                    model: ch.options

                    Rectangle {
                        id: item

                        required property var modelData

                        width: pop.width - 8
                        height: 26
                        radius: 5
                        color: itemMouse.containsMouse ? Theme.primary : "transparent"

                        Text {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: item.width - 16
                            elide: Text.ElideRight
                            text: (ch.value === item.modelData[0] ? "✓  " : "     ") + item.modelData[1]
                            color: itemMouse.containsMouse ? Theme.fgOnPrimary : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: itemMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                ch.picked(item.modelData[0]);
                                pop.close();
                            }
                        }
                    }
                }
            }
        }
    }

    component Button: Rectangle {
        id: btn

        property string text
        property bool accent: false
        signal clicked

        width: btnText.implicitWidth + 28
        height: 26
        radius: 7
        color: accent ? (btnMouse.pressed ? Qt.darker(Theme.primary, 1.15) : Theme.primary)
            : Theme.alpha(Theme.fg, btnMouse.pressed ? 0.18 : btnMouse.containsMouse ? 0.14 : 0.1)

        Text {
            id: btnText

            anchors.centerIn: parent
            text: btn.text
            color: btn.accent ? Theme.fgOnPrimary : Theme.fg
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        MouseArea {
            id: btnMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
