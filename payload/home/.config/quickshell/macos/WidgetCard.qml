pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell

// One spot on the desktop: a single widget, or a stack of same-size widgets.
//   drag              move it (snaps to the desktop grid, never overlaps); drop it on a
//                     same-size widget to stack them
//   click             the front widget's action / app, stacked or not (like macOS
//                     Smart Stacks; decided 2026-10-09)
//   scroll / dots     on a stack: next widget (the back edges peeking out below
//                     are the hint)
//   right-click       sizes, Edit "<Name>"…, Edit Stack…, remove
//   Edit "<Name>"…    the front card flips over to its options (WidgetEditor); Done, Esc or a
//                     click elsewhere flips it back
// Card-level opacity/scale run on the render thread (Animators), so they stay smooth even
// while the shell is busy (Hide All, cycling, appearing); x/y can't (see Behavior on x).
Item {
    id: card

    required property var modelData // { id: stack key }
    required property var desk      // DesktopWidgets window

    readonly property var grp: desk.group(modelData.id) ?? { id: modelData.id, members: [] }
    readonly property var members: grp.members
    readonly property var front: members[0] ?? { id: "", type: "clock", size: "small", x: 0, y: 0 }
    readonly property bool stacked: members.length > 1
    readonly property var kind: WidgetTypes.kind(front.type)

    property bool dragging: false
    property real dragX
    property real dragY
    property bool _moved: false // this press became a drag: its release isn't a click
    property bool shown: false
    property bool leaving: false
    property real _lastWheel: 0

    readonly property bool hovered: mouse.containsMouse || hoverAll.hovered

    // Edit Widget: the front card turns over to its options. desk.editId is the item being
    // edited (one per display; DesktopWidgets clears it when that item stops being a front card).
    readonly property bool editing: desk.editId !== "" && front.id === desk.editId
    property string flipId: "" // the item whose card turns (kept while it turns back)
    property bool closeOnRelease: false
    property real flipAngle: editing ? 180 : 0
    Behavior on flipAngle {
        enabled: !Config.reducedMotion
        NumberAnimation { duration: 350; easing.type: Easing.InOutCubic }
    }

    function openEditor(): void {
        card.flipId = card.front.id;
        Shared.touchStack(card.grp.id); // Smart Rotate leaves the stack alone meanwhile
        card.desk.editId = card.front.id;
    }

    function closeEditor(): void {
        if (!card.editing)
            return;
        card.desk.contentItem.forceActiveFocus(); // first: a text field saves as it loses focus
        card.desk.editId = "";
    }

    // Sonoma dimming (see `visual` below)
    readonly property bool dimmed: card.desk.dimmed && !PowerSaver.saving && !hovered && !dragging && !Shared.widgetEdit && !card.isDropTarget && card.flipAngle === 0
    property real dimAmount: dimmed ? 1 : 0
    Behavior on dimAmount {
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }
    readonly property bool isDropTarget: desk.dropTarget === grp.id
    readonly property bool visibleNow: shown && !leaving && Config.widgetsEnabled

    width: WidgetTypes.width(front.size)
    height: WidgetTypes.height(front.size)
    x: dragging ? dragX : Math.max(0, Math.min(desk.gx(front), desk.width - width))
    y: dragging ? dragY : Math.max(0, Math.min(desk.gy(front), desk.height - height))
    // a widget split out of a stack slides out from behind the stack's front card
    z: dragging ? 10 : slideOutAnim.running ? -1 : 0

    // ── card-level motion (render thread) ───────────────────────────────
    opacity: visibleNow ? (dragging && desk.dropTarget ? 0.8 : 1) : 0
    scale: !visibleNow ? 0.94
         : dragging ? 1.035
         : isDropTarget ? 1.04
         : mouse.pressed ? 0.975
         : hovered && !Shared.windowDrag ? 1.015 : 1
    visible: opacity > 0.005 || visibleNow

    // motion only once the card is in place: a card made later (a stack split apart)
    // used to slide in from the desktop's corner, which looked like everything shifting
    property bool placed: false

    Behavior on opacity {
        enabled: card.placed
        OpacityAnimator { duration: Config.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        enabled: card.placed && !Config.reducedMotion
        ScaleAnimator { duration: 220; easing.type: Easing.OutCubic }
    }
    // Main-thread NumberAnimation, not X/YAnimator: an Animator leaves card.x/y at the old
    // value until it ends, so the frosted glass (backdropRect) stayed behind, then jumped.
    // followDrag (not `dragging`) gates it: drop() clears it before `dragging`, otherwise
    // x switched to the grid spot while the Behavior was still off and the card snapped back.
    property bool followDrag: false
    Behavior on x {
        enabled: card.placed && !card.followDrag && !Config.reducedMotion
        NumberAnimation { duration: 360; easing.type: Easing.OutQuint }
    }
    Behavior on y {
        enabled: card.placed && !card.followDrag && !Config.reducedMotion
        NumberAnimation { duration: 360; easing.type: Easing.OutQuint }
    }

    // a widget split out of a stack slides from the stack to its own spot, growing from a
    // back card's size. Main-thread animation: the frosted glass (backdropRect) follows it.
    transform: [
        Scale {
            id: slideScale

            origin.x: card.width / 2
            origin.y: card.height / 2
        },
        Translate {
            id: slideOut
        }
    ]
    ParallelAnimation {
        id: slideOutAnim

        NumberAnimation { target: slideOut; property: "x"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: slideOut; property: "y"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: slideScale; property: "xScale"; to: 1; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: slideScale; property: "yScale"; to: 1; duration: 420; easing.type: Easing.OutCubic }
    }

    Component.onCompleted: {
        const from = Shared.splitOrigin[card.front.id];
        if (desk.settled && from && !Config.reducedMotion) {
            // split out: shown at once, at the stack (where its back card just was), so the
            // stack's back edges hand over to it without a gap
            slideOut.x = from.x - card.x;
            slideOut.y = from.y - card.y;
            slideScale.xScale = slideScale.yScale = 0.94;
            card.shown = true;
            slideOutAnim.start();
        } else if (desk.settled)
            arrive.start(); // made after start (added): no startup cascade
        else
            appearDelay.start(); // cascade in from the top-left on startup
        placedTimer.start();
        Shared.debugCards = [...Shared.debugCards, card];
    }

    // A new card's position settles over its first moments (its stack resolves, its size);
    // motion that switched on straight away animated those jumps — the card flew in from
    // the desktop's corner. So: shown a frame later, where it belongs, and normal motion
    // only after that.
    Timer {
        id: arrive

        interval: 16
        onTriggered: card.shown = true
    }

    Timer {
        id: placedTimer

        interval: 500
        onTriggered: card.placed = true
    }
    Component.onDestruction: Shared.debugCards = Shared.debugCards.filter(c => c !== card)

    function debugState(): var {
        const layers = [];
        for (let i = 0; i < layerRepeater.count; i++) {
            const l = layerRepeater.itemAt(i);
            if (l)
                layers.push({ type: l.entry.type, depth: l.depth, y: Math.round(l.y * 10) / 10, scale: Math.round(l.scale * 1000) / 1000,
                              opacity: Math.round(l.opacity * 100) / 100, z: l.z, visible: l.visible });
        }
        return { key: grp.id, x: x, y: y, opacity: opacity, visible: visible, hovered: hovered, layers: layers };
    }
    Timer {
        id: appearDelay

        interval: Math.min(300, (card.front.x + card.front.y) / 8)
        onTriggered: card.shown = true
    }

    property var _onLeft: null
    function leave(then: var): void {
        _onLeft = then;
        leaving = true;
        leaveTimer.start();
    }
    Timer {
        id: leaveTimer

        interval: 240
        onTriggered: {
            const f = card._onLeft;
            card._onLeft = null;
            f?.();
        }
    }

    function cycle(dir: int): void {
        if (!card.stacked)
            return;
        Shared.touchStack(card.grp.id); // Smart Rotate leaves it alone for a while
        Config.cycleStack(card.grp.id, dir);
    }

    function editStack(): void {
        Shared.editStackScreen = card.desk.modelData.name;
        Shared.editStackKey = card.grp.id;
    }

    function menuEntries(): var {
        const f = card.front;
        const kinds = card.members.map(m => WidgetTypes.kind(m.type)).filter(k => k);
        // sizes every widget in the stack supports
        const sizes = (WidgetTypes.kind(f.type)?.sizes ?? []).filter(s => kinds.every(k => k.sizes.includes(s)));
        const list = [{ header: card.stacked ? `Stack · ${card.members.length} widgets` : (card.kind?.name ?? "Widget") }];

        if (card.stacked)
            list.push({ label: "Edit Stack…", action: () => card.editStack() },
                      { label: "Smart Rotate", checked: Config.smartRotate(card.grp.id),
                        action: () => Config.setSmartRotate(card.grp.id, !Config.smartRotate(card.grp.id)) },
                      { separator: true });

        if (WidgetTypes.hasOptions(f.type))
            list.push({ label: card.editing ? "Done Editing" : `Edit \u201c${card.kind?.name ?? "Widget"}\u201d…`,
                        action: () => card.editing ? card.closeEditor() : card.openEditor() }, { separator: true });

        if (sizes.length > 1)
            for (const s of sizes)
                list.push({ label: WidgetTypes.sizeName(s), checked: f.size === s, action: () => card.desk.resizeWidget(f, s) });

        if (f.type === "weather" || f.type === "conditions")
            list.push({ separator: true }, { label: "Show in Fahrenheit", checked: Config.tempUnit === "F",
                        action: () => Config.setWidgets("temperatureUnit", Config.tempUnit === "F" ? "C" : "F") });
        if (f.type === "profile")
            list.push({ separator: true }, { label: "Choose Profile Picture…", action: () => Shared.chooseProfilePicture() });
        if (f.type === "clock")
            list.push({ separator: true }, { label: "24-Hour Time", checked: Config.clock24, action: () => Config.setWidgets("clock24h", !Config.clock24) });

        list.push({ separator: true });
        if (card.stacked)
            list.push({ label: `Take ${card.kind?.name ?? "Widget"} Out of Stack`, action: () => {
                const spot = card.desk.freeSpot(f.size, card.grp.id);
                Config.unstack(f.id, spot.x, spot.y, card.desk.modelData.name);
            } });
        for (const s of Quickshell.screens)
            if (s.name !== card.desk.screen.name)
                list.push({ label: `Move to ${s.name}`, action: () => Config.updateGroup(card.grp.id, { screen: s.name, x: 24, y: 24, pos: {} }) });
        list.push({ label: card.stacked ? `Remove ${card.kind?.name ?? "Widget"}` : "Remove Widget", action: () => card.removeFront() },
                  { separator: true },
                  { label: "Edit Widgets…", action: () => Shared.widgetEdit = true });
        return list;
    }

    function removeFront(): void {
        const id = card.front.id;
        if (card.stacked)
            Config.removeFromStack(id); // the next one comes forward
        else
            card.leave(() => Config.removeWidget(id));
    }

    HoverHandler {
        id: hoverAll
    }

    // Dragging, from anywhere on the card: a DragHandler takes the press over from
    // the buttons inside a widget once it moves (a MouseArea here only got drags
    // that started on bare card — the Notes widget couldn't be dragged at all).
    function drop(): void {
        const target = card.desk.dropTarget;
        card.desk.dropTarget = "";
        // always leave drag mode, even if placing throws: a throw here used to leave
        // the widget stuck wherever it was let go
        try {
            if (target) {
                Config.stackOnto(card.grp.id, target); // joins it, in front
            } else {
                // the nearest free grid spot. Plain loops: QML's JavaScript has no Array.flatMap.
                const xs = Array.from(WidgetTypes.snaps(card.dragX, card.width, card.desk.width, true));
                const ys = Array.from(WidgetTypes.snaps(card.dragY, card.height, card.desk.height, false));
                const spots = [];
                for (const x of xs)
                    for (const y of ys)
                        spots.push({ x: x, y: y });
                spots.sort((a, b) => Math.hypot(a.x - card.dragX, a.y - card.dragY) - Math.hypot(b.x - card.dragX, b.y - card.dragY));
                const free = spots.find(p => !card.desk.overlaps(p.x, p.y, card.width, card.height, card.grp.id));
                if (free)
                    Config.moveGroup(card.grp.id, card.desk.modelData.name, free.x, free.y);
                // no free spot anywhere: it glides back to where it was
            }
        } finally {
            card.followDrag = false; // first: the jump back to the grid below then glides
            card.dragging = false;
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: card.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: card._moved = false
        onClicked: m => {
            // released after a drag
            if (card.dragging || card._moved)
                return;
            if (m.button === Qt.RightButton) {
                const p = mapToItem(card.desk.contentItem, m.x, m.y);
                card.desk.openMenu(p.x, p.y, card.menuEntries());
                return;
            }
            if (Shared.widgetEdit || card.editing)
                return;
            const at = Date.now();
            Qt.callLater(() => {
                // a button/row inside the widget handled this click already
                if (Shared.widgetTapAt >= at - 400)
                    return;
                // like macOS: clicking a widget (stacked or not) opens its app;
                // scroll over a stack, or click its dots, to flip through it
                if (typeof card.frontBody?.content?.activate === "function")
                    card.frontBody.content.activate();
                else if (card.kind?.click)
                    Quickshell.execDetached(card.kind.click);
            });
        }
        onWheel: w => {
            if (!card.stacked || card.editing || Date.now() - card._lastWheel < 300)
                return;
            card._lastWheel = Date.now();
            card.cycle(w.angleDelta.y < 0 ? 1 : -1);
        }
    }

    // ── the stack: one layer per widget, front on top ───────────────────
    property Item frontBody: null

    // Sonoma: while apps are open on this desktop, widgets fade to tinted,
    // desaturated glass (hover brings one back). The layer is padded so the
    // shadows aren't clipped, and only exists while dimming is in effect.
    Item {
        id: visual

        readonly property int pad: 48

        x: -pad
        y: -pad
        width: card.width + 2 * pad
        height: card.height + 2 * pad
        layer.enabled: card.dimAmount > 0.001
        layer.effect: MultiEffect {
            saturation: -0.9 * card.dimAmount
            brightness: -0.04 * card.dimAmount
            opacity: 1 - 0.3 * card.dimAmount
        }

        Item {
            x: visual.pad
            y: visual.pad
            width: card.width
            height: card.height

            Repeater {
                id: layerRepeater

                model: ScriptModel {
                    values: card.members
                    objectProp: "id"
                }

                Item {
                    id: layer

                    required property var modelData

                    readonly property int depth: Math.max(0, card.members.findIndex(m => m.id === layer.modelData.id))
                    readonly property var entry: card.members.find(m => m.id === layer.modelData.id) ?? layer.modelData
                    property int shownDepth: depth

                    // resting place for a depth: behind cards shrink toward the bottom
                    // edge and peek out a few px (a little more on hover)
                    function peekFor(d: int): real {
                        return Math.min(d, 2) * (card.hovered && card.stacked ? 6 : 4);
                    }
                    function scaleFor(d: int): real {
                        return 1 - 0.06 * Math.min(d, 2);
                    }
                    function opacityFor(d: int): real {
                        return d <= 2 ? 1 : 0;
                    }

                    width: card.width
                    height: card.height
                    // the card sent back stays on top while it lifts away, else the next
                    // card's glass covered it at once and its content just blinked out
                    property bool leaving: false
                    z: leaving ? 101 : 100 - depth
                    transformOrigin: Item.Bottom
                    readonly property bool turning: layer.entry.id === card.flipId
                    // the 3D turn (Qt's Rotation projects it with perspective)
                    transform: Rotation {
                        origin.x: layer.width / 2
                        origin.y: layer.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: layer.turning ? card.flipAngle : 0
                    }

                    Component.onCompleted: {
                        y = peekFor(depth);
                        scale = scaleFor(depth);
                        opacity = opacityFor(depth);
                        if (depth === 0)
                            card.frontBody = body;
                    }

                    // Start an animation with targets computed *now*. (Bindings like
                    // `to: peekFor(depth)` could still hold the old depth when the
                    // animation started, so a widget sent to the back landed in the front
                    // slot and the middle one never moved: a 3-stack showed as 2.)
                    function animate(kind: string): void {
                        const ty = peekFor(depth), ts = scaleFor(depth), to = opacityFor(depth);
                        settle.stop();
                        toFront.stop();
                        toBack.stop();
                        leaving = false;
                        if (Config.reducedMotion) {
                            y = ty; scale = ts; opacity = to;
                        } else if (kind === "front") {
                            toFront.start();
                        } else if (kind === "back") {
                            backSnapY.value = ty;
                            backSnapS.value = ts;
                            backFadeIn.to = to;
                            toBack.start();
                        } else {
                            settleY.to = ty;
                            settleS.to = ts;
                            settleO.to = to;
                            settle.start();
                        }
                    }

                    // When any motion ends, check the card is where it belongs *now*.
                    // The spacing depends on hover; if the pointer came or went while a
                    // card was still moving to the back, it landed at the old spacing
                    // and sat out of line with the others ("second card uneven").
                    function reconcile(): void {
                        if (settle.running || toFront.running || toBack.running)
                            return;
                        if (Math.abs(y - peekFor(depth)) > 0.5 || Math.abs(scale - scaleFor(depth)) > 0.002
                                || Math.abs(opacity - opacityFor(depth)) > 0.02)
                            animate("settle");
                    }

                    onDepthChanged: {
                        const was = shownDepth;
                        shownDepth = depth;
                        if (depth === 0)
                            card.frontBody = body;
                        animate(was === 0 && depth > 0 ? "back" : depth === 0 ? "front" : "settle");
                    }

                    // hover fans the back edges out a little
                    Connections {
                        target: card
                        function onHoveredChanged(): void {
                            if (!toBack.running && !toFront.running && layer.depth > 0)
                                layer.animate("settle");
                            // (a card still moving catches up in reconcile() when it lands)
                        }
                    }

                    // Plain (main-thread) animations here, not Animators: an Animator writes
                    // its final value back after the sequence's snap step, which left the
                    // widget sent to the back parked behind the front card (a 3-stack
                    // showed as 2 until hover re-settled it).
                    // one curve for the whole shuffle (Apple's ease-out); everything moves
                    // together and any click mid-way just retargets from where it is
                    ParallelAnimation {
                        id: settle
                        onFinished: layer.reconcile()

                        NumberAnimation { id: settleY; target: layer; property: "y"; duration: 340; easing.type: Easing.OutQuart }
                        NumberAnimation { id: settleS; target: layer; property: "scale"; duration: 340; easing.type: Easing.OutQuart }
                        NumberAnimation { id: settleO; target: layer; property: "opacity"; duration: 240 }
                    }

                    ParallelAnimation {
                        id: toFront
                        onFinished: layer.reconcile()

                        NumberAnimation { target: layer; property: "y"; to: 0; duration: 380; easing.type: Easing.OutQuart }
                        NumberAnimation { target: layer; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutQuart }
                        NumberAnimation { target: layer; property: "opacity"; to: 1; duration: 200 }
                    }

                    // the widget you were looking at slides up and away while the next one
                    // rises, then fades in at the very back as an edge
                    SequentialAnimation {
                        id: toBack
                        onFinished: layer.reconcile()

                        ScriptAction { script: layer.leaving = true }
                        ParallelAnimation {
                            NumberAnimation { target: layer; property: "y"; to: -22; duration: 230; easing.type: Easing.OutQuad }
                            NumberAnimation { target: layer; property: "scale"; to: 0.97; duration: 230; easing.type: Easing.OutQuad }
                            NumberAnimation { target: layer; property: "opacity"; to: 0; duration: 200; easing.type: Easing.OutQuad }
                        }
                        ScriptAction { script: layer.leaving = false }
                        PropertyAction { id: backSnapY; target: layer; property: "y" }
                        PropertyAction { id: backSnapS; target: layer; property: "scale" }
                        NumberAnimation { id: backFadeIn; target: layer; property: "opacity"; duration: 260; easing.type: Easing.OutCubic }
                    }

                    WidgetBody {
                        id: body

                        anchors.fill: parent
                        type: layer.entry.type
                        size: layer.entry.size
                        widgetId: layer.entry.id
                        backdrop: Config.widgetsGlass && !PowerSaver.saving ? card.desk.backdrop : null
                        backdropRect: Qt.rect(card.x + slideOut.x, card.y + slideOut.y + layer.peekFor(layer.depth), card.width, card.height)
                        lift: layer.depth === 0 ? (card.dragging ? 1 : card.hovered ? 0.5 : 0) : 0
                        highlight: layer.depth === 0 && card.isDropTarget
                        // behind cards are plain glass: only their edges show
                        contentOpacity: layer.depth === 0 ? 1 : 0
                        options: layer.entry.options ?? null
                        flipped: layer.turning && card.flipAngle > 90
                    }

                    // the back side, built when the turn starts and kept until it has turned back
                    Loader {
                        id: editor

                        anchors.fill: parent
                        active: layer.turning && (card.editing || card.flipAngle > 0)
                        visible: card.flipAngle > 90
                        // turned half-way round with the card, it reads the right way
                        transform: Rotation {
                            origin.x: editor.width / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: 180
                        }
                        onLoaded: if (card.editing) item.forceActiveFocus()

                        sourceComponent: WidgetEditor {
                            entry: layer.entry
                            onDone: card.closeEditor()
                        }
                    }
                }
            }
        }
    }

    // page dots (stacks): which widget is in front; on hover
    Column {
        visible: card.stacked
        // inside the card's padding, and only on hover: outside the card they
        // sat in the gap between widgets as stray marks (the peeking back edges
        // are the resting hint that this is a stack)
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5
        z: 200
        opacity: card.hovered || mouse.pressed ? 1 : 0

        Behavior on opacity {
            OpacityAnimator { duration: 180 }
        }

        Repeater {
            model: card.members.length

            Rectangle {
                required property int index

                readonly property bool current: {
                    // dots keep a fixed order; the front widget's dot is long
                    const byId = [...card.members].sort((a, b) => a.id < b.id ? -1 : 1);
                    return byId[index]?.id === card.front.id;
                }

                // parent is null while a dot is being torn down (stack shrinks)
                anchors.horizontalCenter: parent?.horizontalCenter
                width: 6
                height: current ? 14 : 6
                radius: 3
                color: current ? Theme.fg : dotArea.containsMouse ? Theme.alpha(Theme.fg, 0.7) : Theme.alpha(Theme.fg, 0.35)

                // click a dot to bring that widget to the front
                MouseArea {
                    id: dotArea

                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const byId = [...card.members].sort((a, b) => a.id < b.id ? -1 : 1);
                        const target = byId[parent.index];
                        if (target && target.id !== card.front.id) {
                            Shared.touchStack(card.grp.id);
                            Config.bringToFront(target.id);
                        }
                    }
                }

                Behavior on height {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    // Edit Widgets: remove button (removes the front widget)
    Rectangle {
        x: -8
        y: -8
        z: 200
        width: 24
        height: 24
        radius: 12
        color: removeArea.containsMouse ? "#ff5f57" : Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.glassBorder
        scale: Shared.widgetEdit ? (removeArea.pressed ? 0.85 : 1) : 0
        visible: scale > 0.01

        Behavior on scale {
            NumberAnimation { duration: Config.reducedMotion ? 0 : 240; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 2
            radius: 1
            color: removeArea.containsMouse ? "white" : Theme.fg
        }

        MouseArea {
            id: removeArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.removeFront()
        }
    }

    // Split a stack apart: every widget behind the front one goes to its own free spot, in
    // one settings write, so they all slide out together. The front one keeps this card.
    function splitStack(): void {
        const rest = card.members.slice(1);
        const origin = {};
        for (const m of rest)
            origin[m.id] = { x: card.x, y: card.y };
        Shared.splitOrigin = origin;
        clearOrigin.restart();
        Config.splitStack(card.grp.id, card.desk.freeSpots(card.front.size, "", rest.length), card.desk.modelData.name);
    }

    // the slide-out starting points are only for this split
    Timer {
        id: clearOrigin

        interval: 2000
        onTriggered: Shared.splitOrigin = {}
    }

    Item {
        id: splitBadge

        readonly property bool wanted: card.stacked && !card.dragging && (card.hovered || splitArea.containsMouse)

        // a 48 px hit area around the button keeps it up and takes the click: the 24 px button
        // alone was too small to reach before it hid. The button overhangs the top-right
        // corner like a macOS close badge (mirrors the Edit Widgets remove badge: 8 px out);
        // the hit area reaches 40 px into the card, so the pointer never leaves it on the way
        x: card.width - width + 8
        y: -8
        z: 200
        width: 48
        height: 48
        visible: badge.scale > 0.01
        onWantedChanged: if (!wanted) hideDelay.restart()

        // a moment's grace while the pointer crosses from the card to the badge
        Timer {
            id: hideDelay

            interval: 600
        }

        MouseArea {
            id: splitArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.splitStack()
        }

        Rectangle {
            id: badge

            x: parent.width - width
            y: 0
            width: 24
            height: 24
            radius: 12
            color: splitArea.containsMouse ? Theme.primary : Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.glassBorder
            scale: splitBadge.wanted || hideDelay.running ? (splitArea.pressed ? 0.85 : 1) : 0

            Behavior on scale {
                NumberAnimation { duration: Config.reducedMotion ? 0 : 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            }

            Symbol {
                anchors.centerIn: parent
                name: "call_split"
                color: splitArea.containsMouse ? Theme.fgOnPrimary : Theme.fg
                size: 15
                weight: 600
            }

            // name on hover
            Rectangle {
                visible: splitArea.containsMouse
                anchors.right: parent.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: tipText.implicitWidth + 14
                height: 22
                radius: 6
                color: Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.glassBorder

                Text {
                    id: tipText

                    anchors.centerIn: parent
                    text: "Split stack"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }
        }
    }

    // On the card itself, not on an item above its contents: Qt delivers a press to the
    // card's handlers after its children, so a widget's text, rows and buttons still get
    // the press, and this only takes over once it moves. (On a z-100 overlay its press was
    // accepted there and never reached any MouseArea: the Notes widget couldn't be typed in.)
    DragHandler {
        id: dragger

        // never from a note's text while typing (a drag there selects); the
        // rest of the card always drags. `dragging`: passing over the text mid-drag keeps it
        enabled: card.dragging || (!card.editing && !(card.frontBody?.content?.textHovered ?? false))

        property real startX
        property real startY

        target: null
        acceptedButtons: Qt.LeftButton
        dragThreshold: 5
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        function follow(): void {
            const p = centroid.scenePosition, q = centroid.scenePressPosition;
            card.dragX = Math.max(0, Math.min(dragger.startX + p.x - q.x, card.desk.width - card.width));
            card.dragY = Math.max(0, Math.min(dragger.startY + p.y - q.y, card.desk.height - card.height));
            card.desk.dropTarget = card.desk.stackTargetAt(p.x, p.y, card.front.size, card.grp.id);
        }

        onActiveChanged: {
            if (active) {
                startX = card.x;
                startY = card.y;
                card._moved = true;
                card.followDrag = true; // before `dragging`: x follows the pointer unanimated
                follow();
                card.dragging = true;
            } else if (card.dragging) {
                card.drop();
            }
        }
        onCentroidChanged: if (active && card.dragging) follow()
    }

    // safety net: the button went up (Hyprland's release bind) but the release never
    // reached this layer — end the drag anyway instead of following the pointer
    Connections {
        target: Shared

        function onWindowDragChanged(): void {
            if (!Shared.windowDrag && card.dragging)
                card.drop();
            // a left press off the card ends editing, on its release (dropping the layer's
            // keyboard while the button is held lost the release bind, see WidgetNotes)
            if (Shared.windowDrag)
                card.closeOnRelease = card.editing && !card.hovered;
            else if (card.closeOnRelease) {
                card.closeOnRelease = false;
                card.closeEditor();
            }
        }

        // the keyboard couldn't be kept (DesktopWidgets.keyLost)
        function onStopNoteEditing(): void {
            card.closeEditor();
        }
    }
}
