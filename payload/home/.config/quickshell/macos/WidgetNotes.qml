import QtQuick
import Quickshell
import Quickshell.Io

// Notes widget: click to type, saved automatically to
// ~/.local/share/macos-widgets/note-<id>.txt. Esc, or a click elsewhere, stops editing.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({}) // Edit "Notes"…: textSize s | m | l

    readonly property bool preview: widgetId === ""
    // focus, not activeFocus: activeFocus needs the keyboard, which the layer only
    // takes once Shared.noteEditingId is this note (DesktopWidgets)
    readonly property bool editing: edit.focus
    readonly property color ink: Theme.fg
    onEditingChanged: {
        if (preview)
            return;
        if (editing)
            Shared.noteEditingId = widgetId;
        else if (Shared.noteEditingId === widgetId)
            Shared.noteEditingId = "";
    }

    HoverHandler {
        id: noteHover
    }

    // the pointer is over the text while typing: WidgetCard's DragHandler stays off there
    // (a drag selects). Not editing, a press-and-move on the text drags the card.
    readonly property bool textHovered: !preview && editing && textHover.hovered

    property bool stopOnRelease: false

    Connections {
        target: Shared

        function onStopNoteEditing(): void {
            edit.focus = false;
        }

        // a left press anywhere (custom>>macdrag>>1) that isn't on this note: stop editing.
        // (Not on the keyboard leaving: that also happened by itself just after the grab.)
        // on that press's release: dropping the layer's keyboard focus while the button is
        // held made Hyprland skip the release bind (macdrag>>0 lost, dock hover stuck off)
        function onWindowDragChanged(): void {
            if (Shared.windowDrag)
                root.stopOnRelease = root.editing && !noteHover.hovered;
            else if (root.stopOnRelease) {
                root.stopOnRelease = false;
                edit.focus = false;
            }
        }
    }

    // the folder exists before the first save (made at the same moment as the save, the
    // first notes were lost)
    Component.onCompleted: if (!preview) Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/share/macos-widgets"])

    Text {
        id: title

        x: 16
        y: 13
        text: "Notes"
        color: Theme.primary
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.Bold
    }

    Flickable {
        id: flick

        x: 16
        anchors.top: title.bottom
        anchors.topMargin: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: root.width - 32
        contentHeight: edit.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        HoverHandler {
            id: textHover
        }

        TextEdit {
            id: edit

            width: flick.width
            readOnly: root.preview
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            color: root.ink
            selectionColor: Theme.alpha(Theme.primary, 0.5)
            selectedTextColor: root.ink
            font.family: Theme.font
            font.pixelSize: ({ s: 12, l: 18 })[root.options.textSize] ?? 14
            text: root.preview ? "Groceries\n• Oat milk\n• Coffee beans" : ""
            onTextChanged: if (!root.preview && file.ready) save.restart()
            onCursorRectangleChanged: {
                if (cursorRectangle.y < flick.contentY)
                    flick.contentY = cursorRectangle.y;
                else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                    flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height;
            }
            Keys.onEscapePressed: focus = false

            Text {
                visible: !edit.text && !edit.activeFocus
                text: "Click to write a note…"
                color: Qt.alpha(root.ink, 0.4)
                font: edit.font
            }

            MouseArea {
                anchors.fill: parent
                enabled: !root.preview && !root.editing
                cursorShape: Qt.IBeamCursor
                // on click, not press: taking the keyboard while the button was held lost the
                // release (the card then followed the pointer), and a press-and-move drags the card
                onClicked: mouse => {
                    edit.forceActiveFocus();
                    edit.cursorPosition = edit.positionAt(mouse.x, mouse.y);
                }
            }
        }
    }

    // empty space below the text also starts editing at the end
    MouseArea {
        anchors.fill: flick
        z: -1
        enabled: !root.preview
        cursorShape: Qt.IBeamCursor
        onClicked: {
            edit.forceActiveFocus();
            edit.cursorPosition = edit.length;
        }
    }

    FileView {
        id: file

        property bool ready: false

        path: root.preview ? "" : Quickshell.env("HOME") + `/.local/share/macos-widgets/note-${root.widgetId}.txt`
        atomicWrites: true
        printErrors: false
        onLoaded: {
            edit.text = text();
            ready = true;
        }
        onLoadFailed: ready = true // new note
    }

    Timer {
        id: save

        interval: 500
        onTriggered: file.setText(edit.text)
    }

    Component.onDestruction: {
        if (save.running)
            file.setText(edit.text);
        // destroyed while typing (removed, rebuilt by a config change): onEditingChanged never
        // runs, and the widgets layer would keep asking for the keyboard
        if (!preview && Shared.noteEditingId === widgetId)
            Shared.noteEditingId = "";
    }
}
