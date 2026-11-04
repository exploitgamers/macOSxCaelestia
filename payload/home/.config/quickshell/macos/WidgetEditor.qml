import QtQuick

// The back of a widget card (macOS Sonoma "Edit Widget"): the kind's options from
// WidgetTypes.optionSpecs, saved to the item's `options` as they change. WidgetCard flips the
// card to show it; Done, Esc or a click elsewhere flips back (WidgetCard.closeEditor).
Item {
    id: ed

    property var entry: ({}) // the saved item { id, type, options, … }
    signal done()

    readonly property var kind: WidgetTypes.kind(entry.type ?? "")
    readonly property var specs: WidgetTypes.optionSpecs[entry.type ?? ""] ?? []
    readonly property var values: WidgetTypes.options(entry.type ?? "", entry.options)
    readonly property bool small: width < 200

    function set(key: string, value: var): void {
        const spec = specs.find(o => o.key === key);
        const raw = entry.options && typeof entry.options === "object" && !Array.isArray(entry.options) ? entry.options : {};
        const cur = Object.assign({}, raw);
        if (!spec || value === spec.def)
            delete cur[key];
        else
            cur[key] = value;
        if (JSON.stringify(cur) !== JSON.stringify(raw))
            Config.updateWidget(entry.id, { options: cur });
    }

    Keys.onEscapePressed: ed.done()

    // the back side swallows clicks: nothing behind it (the widget's app) opens
    MouseArea {
        anchors.fill: parent
        onClicked: ed.forceActiveFocus() // a click off a text field ends typing there
    }

    Row {
        id: header

        x: 14
        y: 14
        height: 24 // = Done: tile, name and Done share one centre line on every size
        spacing: 7

        // small cards: room for the name instead (Done takes the rest)
        SymbolTile {
            visible: !ed.small
            anchors.verticalCenter: parent.verticalCenter
            name: ed.kind?.glyph ?? "widgets"
            tint: Theme.symbolTints[ed.kind?.glyph ?? ""] ?? "blue"
            size: 22
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: ed.width - 28 - (ed.small ? 0 : 22 + header.spacing) - doneButton.width - 8
            text: ed.kind?.name ?? "Widget"
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Bold
        }
    }

    Rectangle {
        id: doneButton

        anchors.right: parent.right
        anchors.rightMargin: 14 // = header.x
        anchors.verticalCenter: header.verticalCenter
        width: doneText.implicitWidth + 22
        height: 24
        radius: 12
        color: doneArea.pressed ? Qt.darker(Theme.primary, 1.15) : Theme.primary
        scale: doneArea.pressed ? 0.95 : 1

        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Text {
            id: doneText

            anchors.centerIn: parent
            text: "Done"
            color: Theme.fgOnPrimary
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: doneArea

            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: ed.done()
        }
    }

    Flickable {
        id: flick

        x: 14
        y: header.y + 32
        width: ed.width - 28
        height: ed.height - y - 10
        contentHeight: rows.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: rows

            width: flick.width
            spacing: ed.small ? 7 : 10

            Repeater {
                model: ed.specs

                Item {
                    id: row

                    required property var modelData

                    readonly property var value: ed.values[modelData.key]
                    readonly property bool inline: modelData.type === "toggle"

                    width: rows.width
                    height: inline ? 24 : label.height + 4 + control.height

                    Text {
                        id: label

                        anchors.verticalCenter: row.inline ? parent.verticalCenter : undefined
                        width: parent.width - (row.inline ? 44 : 0)
                        text: row.modelData.label
                        elide: Text.ElideRight
                        color: row.inline ? Theme.fg : Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: row.inline ? 12 : 11
                        font.weight: row.inline ? Font.Medium : Font.DemiBold
                    }

                    Loader {
                        id: control

                        readonly property var spec: row.modelData
                        readonly property var value: row.value

                        anchors.right: parent.right
                        anchors.verticalCenter: row.inline ? parent.verticalCenter : undefined
                        y: row.inline ? 0 : label.height + 4
                        width: row.inline ? 36 : parent.width
                        sourceComponent: row.modelData.type === "toggle" ? toggleC : row.modelData.type === "text" ? textC : segmentedC
                    }
                }
            }
        }
    }

    // ── controls (`parent` is the row's Loader: spec, value) ───────────────

    Component {
        id: segmentedC

        Rectangle {
            id: seg

            readonly property var spec: parent.spec
            readonly property var choices: spec.choices
            readonly property int current: Math.max(0, choices.findIndex(c => c[0] === parent.value))
            readonly property real cellW: (width - 4) / choices.length

            width: parent.width
            height: 24
            radius: 7
            color: Theme.alpha(Theme.fg, 0.09)

            // the selected segment's raised thumb glides between choices
            Rectangle {
                x: 2 + seg.current * seg.cellW
                y: 2
                width: seg.cellW
                height: seg.height - 4
                radius: 5
                color: Theme.alpha(Theme.fg, 0.2)
                border.width: 1
                border.color: Theme.alpha(Theme.fg, 0.08)

                Behavior on x {
                    NumberAnimation { duration: Config.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
                }
            }

            Row {
                x: 2

                Repeater {
                    model: seg.choices

                    Item {
                        required property var modelData
                        required property int index

                        width: seg.cellW
                        height: seg.height

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 4
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.modelData[1]
                            elide: Text.ElideRight
                            color: parent.index === seg.current ? Theme.fg : Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: parent.index === seg.current ? Font.DemiBold : Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ed.set(seg.spec.key, parent.modelData[0])
                        }
                    }
                }
            }
        }
    }

    Component {
        id: toggleC

        // Apple's switch: green when on, the knob slides across
        Rectangle {
            id: sw

            readonly property bool on: parent.value === true

            width: 36
            height: 22
            radius: 11
            color: on ? Theme.sys.green : Theme.alpha(Theme.fg, 0.16)

            Behavior on color {
                ColorAnimation { duration: 180 }
            }

            Rectangle {
                x: sw.on ? sw.width - width - 2 : 2
                y: 2
                width: 18
                height: 18
                radius: 9
                color: "white"

                Behavior on x {
                    NumberAnimation { duration: Config.reducedMotion ? 0 : 200; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: ed.set(sw.parent.spec.key, !sw.on)
            }
        }
    }

    Component {
        id: textC

        Rectangle {
            id: field

            readonly property var spec: parent.spec

            function commit(): void {
                ed.set(spec.key, input.text.trim());
            }

            width: parent.width
            height: 26
            radius: 7
            color: Theme.alpha(Theme.fg, input.activeFocus ? 0.14 : 0.08)
            border.width: input.activeFocus ? 1.5 : 0
            border.color: Theme.alpha(Theme.primary, 0.8)

            TextInput {
                id: input

                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                text: field.parent.value ?? ""
                color: Theme.fg
                selectionColor: Theme.alpha(Theme.primary, 0.45)
                selectByMouse: true
                clip: true
                font.family: Theme.font
                font.pixelSize: 12
                onAccepted: ed.forceActiveFocus() // commits below
                onActiveFocusChanged: if (!activeFocus) field.commit()

                Text {
                    visible: !input.text && !input.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    text: field.spec.placeholder ?? ""
                    elide: Text.ElideRight
                    color: Theme.alpha(Theme.fg, 0.4)
                    font: input.font
                }
            }
        }
    }
}
