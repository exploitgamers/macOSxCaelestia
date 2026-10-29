pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config

Region {
    id: root

    required property EdgeGeometry geometry
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness

    // [macos] no edge strips at all over a fullscreen game (open panels stay clickable)
    x: win.hasFullscreenGame ? 0 : geometry.insetLeft(clampedThickness, true) + win.dragMaskPadding
    // [macos] in fullscreen only the side edges trigger; the top edge belongs to the
    // fullscreen title bar and the bottom to the dock
    // [macos] drag-to-open band only on the left edge (side panels); top/right/bottom stay click-through
    y: win.hasFullscreen ? 0 : geometry.insetTop(clampedThickness, true)
    width: win.hasFullscreenGame ? win.width : win.width - geometry.insetLeft(clampedThickness, true) - clampedThickness - win.dragMaskPadding
    height: win.hasFullscreen ? win.height : win.height - geometry.insetTop(clampedThickness, true) - geometry.insetBottom(clampedThickness, true)
    intersection: Intersection.Xor

    R {
        panel: root.panels.dashboard
        y: 0
        height: panel.height * (1 - root.panels.dashboard.offsetScale) + root.geometry.insetTop(root.borderThickness)
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.geometry.insetBottom(root.borderThickness)
    }

    R {
        id: sessionRegion

        panel: root.panels.sessionWrapper
        x: 0 // [macos] left edge
        width: panel.width * (1 - root.panels.session.offsetScale) + root.borderThickness + sidebarRegion.width
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: 0 // [macos] left edge
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.osdWrapper
        x: 0 // [macos] left edge
        width: panel.width * (1 - root.panels.osd.offsetScale) + root.borderThickness + sessionRegion.width
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.geometry.insetTop(root.borderThickness)
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.geometry.insetBottom(root.borderThickness)
    }

    R {
        panel: root.panels.popoutsWrapper
        width: root.geometry.horizontal ? panel.width : panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
        height: root.geometry.horizontal ? panel.height * (1 - root.panels.popoutsWrapper.offsetScale) : panel.height
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.geometry.insetLeft(root.borderThickness)
        y: panel.y + root.geometry.insetTop(root.borderThickness)
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }
}
