pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions
    readonly property alias geometry: geometry

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return hasFullscreenOnNormalWs;
    }
    // [macos] a fullscreen game keeps its side edges: their trigger strips took the pointer from its free c‍ursor
    // (same list as the macos shell's Shared.gameApps)
    readonly property bool hasFullscreenGame: {
        const special = hasSpecialWorkspace ? monitor?.lastIpcObject.specialWorkspace?.name : "";
        const ws = special ? Hypr.workspaces.values.find(w => w.name === special) : monitor?.activeWorkspace;
        return ws?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1 && /^org\.vinegarhq\.Sober$|^steam_app_|^gamescope$/.test(t.lastIpcObject.class ?? "")) ?? false;
    }

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 // [macos] always (upstream: only in fullscreen): with border thickness 0 the edge anti-aliasing drew a 1 px line round the screen
    readonly property real borderThickness: contentItem.Config.border.thickness * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : contentItem.Config.border.thickness

    property color surfaceColour: Colours.tPalette.m3surface

    readonly property int dragMaskPadding: {
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace?.lastIpcObject.windows > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    // [macos] the side panel takes the keyboard while open (with its focus grab), so Esc closes it
    WlrLayershell.keyboardFocus: screenState.launcher || screenState.session || screenState.sidebar || popoutTakesKeys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // [macos] a clicked bar drop-down takes the keyboard like a macOS menu, so Esc closes it;
    // not the hover-only media drop-down nor the volume-key flash (they'd steal typing)
    readonly property bool popoutTakesKeys: panels.popouts.hasCurrent && panels.popouts.currentName !== "media" && !bar.controlsFlash

    Shortcut { // [macos] Esc closes the open bar drop-down (the Wi-Fi password field handles its own Esc)
        sequence: "Escape"
        enabled: root.popoutTakesKeys && panels.popouts.currentName !== "wirelesspassword"
        onActivated: {
            panels.popouts.close();
            root.bar.closeTray();
        }
    }

    Shortcut { // [macos] Esc closes the side panel, like Notification Centre
        sequence: "Escape"
        enabled: root.screenState.sidebar && !root.screenState.launcher && !root.screenState.session
        onActivated: root.screenState.sidebar = false
    }

    // [macos] keep the edge triggers in fullscreen (Regions drops top/bottom there); no
    // input at all while a window is dragged by its title bar: a release landing on this
    // surface (an edge, the top bar) is dropped by the title-bar plugin and the drag
    // never ends. The macos shell announces the drag (custom>>macgrab / macdrag>>0).
    property bool windowDragged: false
    mask: windowDragged ? noInput : regions

    Region {
        id: noInput
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name !== "custom")
                return;
            if (event.data.startsWith("macgrab>>")) {
                root.windowDragged = true;
                dragRelease.stop(); // [macos] a new drag within 300 ms of the last release: don't let that release's timer reopen input mid-drag
                dragSafety.restart();
            } else if (event.data === "macdrag>>0") {
                dragRelease.restart(); // a moment later, so the drop point doesn't open a panel at once
            }
        }
    }

    Timer {
        id: dragRelease

        interval: 300
        onTriggered: root.windowDragged = false
    }

    Timer {
        id: dragSafety // never stay input-less if the end is missed

        interval: 20000
        onTriggered: root.windowDragged = false
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on fsTransitionProg {
        Anim {}
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    EdgeGeometry {
        id: geometry

        bar: bar
        win: root
        configPosition: "top" // [macos] pinned: the installed plugin (2.5) has no bar.position option (PR #1748)
    }

    Regions {
        id: regions

        geometry: geometry
        panels: panels
        win: root
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: {
            const s = root.screenState;
            const conf = root.contentItem.Config;
            if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled))
                return true;
            if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
                return true;
            if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
                return true;
            if (root.popoutTakesKeys) // [macos] gives the drop-down the keyboard (Esc)
                return true;
            return false;
        }
        windows: [root]
        onCleared: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.dashboard = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.surfaceColour.a
        // [macos] the full-screen shadow layer re-renders on every frame a panel moves:
        // only keep it while something is actually shown
        layer.enabled: root.shadowOpacity > 0 && (panels.dashboard.visible || panels.launcher.visible || panels.session.visible || panels.sidebar.visible || panels.osd.visible || panels.notifications.visible || panels.utilities.visible)
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 10 // [macos] was 15
            shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
        }

        BlobGroup {
            id: blobGroup

            color: root.surfaceColour
            smoothing: root.contentItem.Config.border.smoothing
        }

        BlobInvertedRect {
            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: blobGroup
            radius: 0 // [macos] square screen corners: nothing drawn in them
            borderLeft: geometry.insetLeft(root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderRight: root.borderThickness - anchors.margins - root.sdfBorderOffset
            borderTop: root.borderThickness - anchors.margins - root.sdfBorderOffset // [macos] no band behind the bar: the pills float
            borderBottom: geometry.insetBottom(root.borderThickness) - anchors.margins - root.sdfBorderOffset
        }

        PanelBg {
            id: dashBg

            panel: panels.dashboard
            deformAmount: 0.1
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
        }

        PanelBg {
            id: sessionBg

            glass: true
            panel: panels.sessionWrapper
            deformAmount: 0.2
            x: panels.sessionWrapper.x + panels.session.x + geometry.insetLeft(root.borderThickness)
            implicitWidth: panels.session.width
        }

        PanelBg {
            id: sidebarBg

            glass: true
            panel: panels.sidebar
            deformAmount: 0.03
            // [macos] one glass sheet down to the bottom of the utilities attached below it
            implicitHeight: panels.utilities.visible ? panels.utilities.y + panels.utilities.height - panel.y : panel.height
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [utilsBg]
            bottomRightRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius // [macos] left edge
        }

        PanelBg {
            id: osdBg

            glass: true
            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.osdWrapper.x + panels.osd.x + geometry.insetLeft(root.borderThickness)
            implicitWidth: panels.osd.width
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
            group: null // [macos] each notification is its own glass card (notifications/Notification.qml)
        }

        PanelBg {
            id: utilsBg

            glass: !panels.sidebar.visible // [macos] attached to the sidebar it is part of sidebarBg's sheet
            visible: glass
            group: null
            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topRightRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius // [macos] left edge
        }

        // [macos] no popoutBg blob: a drop-down is a floating glass panel of its own (bar/popouts/ClipWrapper.qml)
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
        bar: bar
        geometry: geometry
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen

        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            bar: bar
            geometry: geometry
            borderThickness: root.borderThickness

            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
        }

        BarWrapper {
            id: bar

            // Anchored on one corner and sized by binding: an opposing pair of anchors sizes the
            // item instead, and keeps that size once the pair is dropped
            anchors.left: parent.left
            anchors.top: geometry.barOnBottom ? undefined : parent.top
            anchors.bottom: geometry.barOnBottom ? parent.bottom : undefined

            width: geometry.horizontal ? parent.width : implicitWidth
            height: geometry.horizontal ? implicitHeight : parent.height

            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts
            position: geometry.position

            fullscreen: root.hasFullscreen
        }
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "rootWindow"
        component: root
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "interactionWrapper"
        component: interactions
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "bar"
        component: bar
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "panels"
        component: panels
    }

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15
        // [macos] a floating glass sheet 8 px off the screen edges (like the bar drop-downs)
        // instead of a blob fused to the edge; drawn here so it keeps the panels' shadow
        property bool glass: false

        group: glass ? null : blobGroup
        x: panel.x + geometry.insetLeft(root.borderThickness)
        y: panel.y + geometry.insetTop(root.borderThickness)
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Tokens.rounding.extraLarge
        deformScale: (deformAmount * Config.appearance.deformScale) / 10000

        StyledRect {
            anchors.fill: parent
            visible: parent.glass && parent.width > 0 && parent.height > 0
            radius: 22 // [macos] = macos shell panelRadius, same as the drop-downs
            color: Colours.palette.m3surface // the parent layer applies the glass alpha
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3onSurface, 0.13 / Math.max(0.1, root.surfaceColour.a))
        }
    }
}
