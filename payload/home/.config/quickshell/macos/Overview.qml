pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// Mission Control-style overview (SUPER+`, Spotlight "Mission Control", or a hot
// corner set to "overview"): every window on this desktop flies from where it is
// into a tidy grid of live thumbnails. Click one to go to it; Esc, a click on the
// background, or the key again returns.
PanelWindow {
    id: ov

    required property ShellScreen modelData

    readonly property var monitor: Hyprland.monitorFor(modelData)
    // latched while open: focus follows the mouse, so a live binding hopped displays mid-show
    property bool here: false
    Binding on here {
        when: !Shared.overviewOpen
        value: (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === ov.modelData?.name
        restoreMode: Binding.RestoreNone
    }
    readonly property bool shown: Shared.overviewOpen && here

    property var wins: []      // [{ top, sx, sy, sw, sh }] captured when opening
    property real t: 0         // 0 = windows where they are, 1 = in the grid
    property var picked: null  // the window clicked (focused once closed)

    function open(): void {
        Hyprland.refreshToplevels();
        snapshot.restart(); // read positions once the refresh lands
    }

    function close(pick: var): void {
        picked = pick ?? null;
        Shared.overviewOpen = false;
    }

    onShownChanged: {
        grabArmed = false;
        if (shown) {
            open();
            armGrab.restart();
        } else {
            snapshot.stop(); // closed before the snapshot: don't fly into the grid afterwards
            toGrid.stop();
            // interrupted early: return in proportion to how far it got (no windows: unmap at once)
            fromGrid.duration = Config.reducedMotion || n === 0 ? 0 : Math.round(320 * Math.max(0.35, t));
            fromGrid.start();
        }
    }

    Timer {
        id: snapshot

        interval: 60
        onTriggered: {
            const ws = ov.monitor?.activeWorkspace;
            ov.wins = Hyprland.toplevels.values
                .filter(t => t.workspace === ws && t.wayland && t.lastIpcObject?.at)
                .map(t => ({ top: t, sx: t.lastIpcObject.at[0] - (ov.modelData?.x ?? 0), sy: t.lastIpcObject.at[1] - (ov.modelData?.y ?? 0),
                             sw: t.lastIpcObject.size[0], sh: t.lastIpcObject.size[1] }));
            fromGrid.stop();
            ov.t = 0;
            toGrid.start();
        }
    }

    NumberAnimation {
        id: toGrid

        target: ov
        property: "t"
        to: 1
        duration: Config.reducedMotion ? 0 : 420
        easing.type: Easing.OutQuint
    }

    NumberAnimation {
        id: fromGrid

        target: ov
        property: "t"
        to: 0
        duration: 320
        easing.type: Easing.InOutCubic
        onFinished: {
            if (ov.picked) {
                const addr = "0x" + String(ov.picked.address).replace(/^0x/, "");
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:${addr}" })`);
                Hyprland.dispatch(`hl.dsp.window.alter_zorder({ mode = "top", window = "address:${addr}" })`);
                ov.picked = null;
            }
            ov.wins = [];
        }
    }

    // grid: columns for n windows, cells keep the screen's proportions
    readonly property int n: wins.length
    readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(n * 1.2)))
    readonly property int rows: Math.max(1, Math.ceil(n / cols))
    readonly property real gridW: width - 160
    readonly property real gridH: height - 200
    readonly property real cellW: gridW / cols
    readonly property real cellH: gridH / rows

    screen: modelData
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    visible: shown || t > 0.001 || fromGrid.running

    WlrLayershell.namespace: "macos-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool grabArmed: false

    Timer {
        id: armGrab

        interval: 80
        onTriggered: ov.grabArmed = ov.shown
    }

    HyprlandFocusGrab {
        windows: [ov]
        active: ov.shown && ov.grabArmed
        onCleared: ov.close(null)
    }

    // dimmed backdrop; a click on it goes back. Constant alpha: Hyprland fades the
    // layer in/out (hypr-user.lua), so dim and blur arrive together instead of the
    // blur switching on in one frame once a QML fade crossed ignore_alpha.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)

        MouseArea {
            anchors.fill: parent
            onClicked: ov.close(null)
        }

        focus: ov.shown
        Keys.onEscapePressed: ov.close(null)
    }

    Text {
        visible: ov.shown && ov.n === 0 && !snapshot.running
        anchors.centerIn: parent
        text: "No windows on this desktop"
        color: "white"
        opacity: 0.8
        font.family: Theme.font
        font.pixelSize: 18
    }

    Repeater {
        model: ov.wins

        Item {
            id: thumb

            required property var modelData
            required property int index

            // target: fit the window's shape into its grid cell
            readonly property int col: index % ov.cols
            readonly property int row: Math.floor(index / ov.cols)
            readonly property real fit: Math.min((ov.cellW - 40) / modelData.sw, (ov.cellH - 60) / modelData.sh, 1)
            readonly property real tw: modelData.sw * fit
            readonly property real th: modelData.sh * fit
            // last row centred when it isn't full
            readonly property int inRow: row === ov.rows - 1 ? ov.n - row * ov.cols : ov.cols
            readonly property real tx: 80 + (ov.gridW - inRow * ov.cellW) / 2 + col * ov.cellW + (ov.cellW - tw) / 2
            readonly property real ty: 90 + row * ov.cellH + (ov.cellH - 30 - th) / 2

            x: modelData.sx + (tx - modelData.sx) * ov.t
            y: modelData.sy + (ty - modelData.sy) * ov.t
            width: modelData.sw + (tw - modelData.sw) * ov.t
            height: modelData.sh + (th - modelData.sh) * ov.t
            scale: area.containsMouse && ov.t > 0.9 ? 1.03 : 1

            Behavior on scale {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            ClippingRectangle {
                anchors.fill: parent
                // window corners scaled with the thumbnail: no corner jump as it flies in
                radius: Math.max(6, Theme.windowRadius * thumb.width / Math.max(1, thumb.modelData.sw))
                // clear until the capture lands: the real window right behind it shows instead of a tinted flash
                color: shot.hasContent ? Theme.surfaceContainer : "transparent"
                border.width: area.containsMouse ? 3 : 0
                border.color: Theme.primary

                ScreencopyView {
                    id: shot

                    anchors.fill: parent
                    captureSource: thumb.modelData.top.wayland
                    live: false // one capture when it opens: light on the iGPU
                }
            }

            Text {
                anchors.top: parent.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, parent.width)
                textFormat: Text.PlainText // untrusted text: never parse markup
                text: thumb.modelData.top.title
                elide: Text.ElideRight
                opacity: ov.t
                color: "white"
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            MouseArea {
                id: area

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ov.close(thumb.modelData.top)
            }
        }
    }
}
