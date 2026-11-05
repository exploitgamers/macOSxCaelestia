import QtQuick
import Quickshell
import Quickshell.Io

// Reminders widget: a checklist. Type in "New Reminder" and press Enter to add;
// click a circle to complete (it fades out after a moment). Saved per widget in
// ~/.local/share/macos-widgets/reminders-<id>.json.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""

    readonly property bool preview: widgetId === ""
    property var items: preview ? [{ text: "Book dentist", done: false }, { text: "Export the edit", done: false }, { text: "Call mum", done: true }] : []
    readonly property int open: items.filter(i => !i.done).length
    // typing goes through the same keyboard hand-off as Notes (DesktopWidgets)
    readonly property bool editing: input.focus
    onEditingChanged: {
        if (preview)
            return;
        if (editing)
            Shared.noteEditingId = widgetId;
        else if (Shared.noteEditingId === widgetId)
            Shared.noteEditingId = "";
    }
    // destroyed while typing (removed, rebuilt by a config change): onEditingChanged never runs,
    // and the widgets layer would keep asking for the keyboard
    Component.onDestruction: if (!preview && Shared.noteEditingId === widgetId) Shared.noteEditingId = ""

    HoverHandler {
        id: remHover
    }

    property bool stopOnRelease: false

    Connections {
        target: Shared

        function onStopNoteEditing(): void {
            input.focus = false;
        }

        // a left press anywhere else ends typing (as in Notes)
        // on that press's release: dropping the layer's keyboard focus while the button is
        // held made Hyprland skip the release bind (macdrag>>0 lost, dock hover stuck off)
        function onWindowDragChanged(): void {
            if (Shared.windowDrag)
                root.stopOnRelease = root.editing && !remHover.hovered;
            else if (root.stopOnRelease) {
                root.stopOnRelease = false;
                input.focus = false;
            }
        }
    }

    function save(): void {
        if (root.preview)
            return;
        Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/share/macos-widgets"]);
        file.setText(JSON.stringify(items));
    }

    function add(text: string): void {
        text = text.trim();
        if (!text)
            return;
        items = [...items, { text: text, done: false }];
        save();
    }

    function toggle(i: int): void {
        items = items.map((it, j) => j === i ? { text: it.text, done: !it.done } : it);
        save();
        sweep.restart();
    }

    FileView {
        id: file

        path: root.preview ? "" : Quickshell.env("HOME") + `/.local/share/macos-widgets/reminders-${root.widgetId}.json`
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                root.items = JSON.parse(text() || "[]");
            } catch (e) {}
        }
    }

    // completed ones leave the list a moment after you tick them
    Timer {
        id: sweep

        interval: 1800
        onTriggered: {
            if (root.items.some(i => i.done) && !root.preview) {
                root.items = root.items.filter(i => !i.done);
                root.save();
            }
        }
    }

    Row {
        x: 16
        y: 13
        spacing: 6

        Text {
            text: "Reminders"
            color: Theme.sys.orange
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Bold
        }

        Text {
            text: root.open
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    Flickable {
        id: list

        x: 16 // check circles in line with the title
        y: 38
        width: root.width - 32
        height: root.height - y - 46 // 8 px above the new-reminder field
        contentHeight: col.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col

            width: list.width

            Repeater {
                model: root.items

                Item {
                    id: row

                    required property var modelData
                    required property int index

                    width: col.width
                    height: 26
                    opacity: modelData.done ? 0.45 : 1

                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    Rectangle {
                        id: check

                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 8
                        // Apple Reminders' orange
                        color: row.modelData.done ? Theme.sys.orange : "transparent"
                        border.width: 1.5
                        border.color: row.modelData.done ? Theme.sys.orange : Theme.fgDim

                        Symbol {
                            anchors.centerIn: parent
                            visible: row.modelData.done
                            name: "check"
                            color: "white"
                            size: 12
                            weight: 700
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggle(row.index)
                        }
                    }

                    Text {
                        anchors.left: check.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.text
                        elide: Text.ElideRight
                        font.strikeout: row.modelData.done
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    Text {
        visible: root.items.length === 0
        x: 16
        y: 44
        text: "All done 🎉"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 12
    }

    // new reminder
    Rectangle {
        x: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: root.width - 24
        height: 26
        radius: Theme.panelRadius - 12
        color: Theme.alpha(Theme.surfaceContainerHigh, input.activeFocus ? 0.85 : 0.75)

        Symbol {
            id: plus

            x: 7
            anchors.verticalCenter: parent.verticalCenter
            name: "add_circle"
            fill: true
            color: Theme.sys.orange
            size: 16
            weight: 600
        }

        TextInput {
            id: input

            anchors.left: plus.right
            anchors.leftMargin: 5 // text starts where the reminders' text does (40)
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            readOnly: root.preview
            color: Theme.fg
            selectionColor: Theme.alpha(Theme.primary, 0.4)
            font.family: Theme.font
            font.pixelSize: 12
            clip: true
            onAccepted: {
                root.add(text);
                text = "";
            }
            Keys.onEscapePressed: focus = false

            Text {
                visible: !input.text
                anchors.verticalCenter: parent.verticalCenter
                text: "New Reminder"
                color: Theme.alpha(Theme.fgDim, 0.72)
                font: input.font
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !root.preview && !input.activeFocus
            cursorShape: Qt.IBeamCursor
            onClicked: input.forceActiveFocus()
        }
    }
}
