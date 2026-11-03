import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

// A widget's glass card with its content (shared by the desktop and the gallery).
// On the desktop, `backdrop` is the blurred wallpaper (DesktopWidgets) and
// `backdropRect` the part of it behind this card — frosted glass without
// Hyprland's layer blur.
Item {
    id: root

    property string type
    property string size: "small"
    property string widgetId: ""
    property Item backdrop: null
    property rect backdropRect
    property real lift: 0          // 0..1: hover / drag elevation (deeper shadow)
    property real contentOpacity: 1
    property bool highlight: false // a dragged widget would stack onto this one
    property var options: null      // the item's saved options (WidgetTypes.options fills defaults)
    property bool flipped: false    // the back side (WidgetEditor) is showing: content hidden at once

    Behavior on lift {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    readonly property var kind: WidgetTypes.kind(type)
    readonly property Item content: loader.item

    implicitWidth: WidgetTypes.width(size)
    implicitHeight: WidgetTypes.height(size)

    RectangularShadow {
        anchors.fill: bg
        radius: bg.radius
        blur: 28 + 16 * root.lift
        offset.y: 8 + 8 * root.lift
        color: Qt.rgba(0, 0, 0, 0.28 + 0.1 * root.lift)
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: bg.radius
        color: "transparent"
        visible: root.backdrop !== null

        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: root.backdrop
            sourceRect: root.backdropRect
        }
    }

    Rectangle {
        id: bg

        anchors.fill: parent
        radius: Theme.panelRadius
        color: Theme.alpha(Theme.surfaceContainer, root.backdrop ? 0.5 : 0.62)
        border.width: root.highlight ? 2 : 1
        border.color: root.highlight ? Theme.primary : Theme.glassBorder

        Behavior on color {
            ColorAnimation { duration: 400 }
        }
    }

    Loader {
        id: loader

        anchors.fill: parent
        source: root.kind ? root.kind.file : ""
        asynchronous: false
        opacity: root.contentOpacity
        visible: !root.flipped && (opacity > 0.01 || root.contentOpacity > 0)

        Behavior on opacity {
            OpacityAnimator { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    Binding {
        target: loader.item
        property: "size"
        value: root.size
        when: loader.item !== null
    }

    Binding {
        target: loader.item
        property: "options"
        value: WidgetTypes.options(root.type, root.options)
        when: loader.item !== null && WidgetTypes.hasOptions(root.type)
    }

    Binding {
        target: loader.item
        property: "widgetId"
        value: root.widgetId
        when: loader.item !== null
    }
}
