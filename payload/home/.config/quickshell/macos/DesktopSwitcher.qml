pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// SUPER+Tab desktop switcher (hypr-qol.lua mac_desktop → custom>>macdesks).
// Cards for every desktop in use, most recent first, each showing its apps;
// the last card opens a new empty desktop. Appears only while SUPER is held
// (a quick SUPER+Tab just flips back to the previous desktop).
PanelWindow {
    id: ds

    required property ShellScreen modelData

    // latched while open: focus follows the mouse, so a live binding hopped displays mid-show
    property bool here: false
    Binding on here {
        when: !ds.active
        value: (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === ds.modelData?.name
        restoreMode: Binding.RestoreNone
    }
    property var desks: [] // [{ id, classes: [] }]
    property int index: 0
    property bool active: false
    property bool revealed: false
    readonly property bool shown: active && revealed && here

    function iconFor(cls: string): string {
        const e = DesktopEntries.applications.values.length < 0 ? null
                : (DesktopEntries.byId(cls) ?? DesktopEntries.heuristicLookup(cls));
        return Quickshell.iconPath(e?.icon ?? cls, "application-x-executable");
    }

    Connections {
        target: Shared

        function onDesktopSwitcher(desks: var, index: int): void {
            if (!ds.active) {
                ds.active = true;
                ds.revealed = false;
                reveal.restart();
            }
            ds.desks = desks;
            ds.index = index;
            if (index !== 1)
                ds.revealed = true; // browsing past the first choice: show now
        }

        function onDesktopSwitcherHide(): void {
            ds.active = false;
            ds.revealed = false;
            reveal.stop();
        }
    }

    Timer {
        id: reveal

        interval: 160
        onTriggered: ds.revealed = ds.active
    }

    screen: modelData
    color: "transparent"
    visible: shown || pop.value > 0.01
    // 12 px around the cards, like the app switcher (thumb corners concentric with the panel)
    implicitWidth: Math.min((modelData?.width ?? 0) - 80, row.implicitWidth + 24)
    implicitHeight: 162
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    WlrLayershell.namespace: "macos-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Spring {
        id: pop

        target: ds.shown ? 1 : 0
        response: 0.18
        epsilon: 0.004
    }

    Rectangle {
        anchors.fill: parent
        radius: 26
        color: Theme.glassStrong
        border.width: 1
        border.color: Theme.glassBorder
        opacity: pop.value
        scale: 0.96 + 0.04 * pop.value

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 14

            Repeater {
                model: ds.desks

                Item {
                    id: card

                    required property var modelData
                    required property int index

                    readonly property bool selected: index === ds.index
                    readonly property bool isNew: index === ds.desks.length - 1 && modelData.classes.length === 0

                    width: 168
                    height: 138 // thumb 112 + 10 + label 16

                    Rectangle {
                        id: thumb

                        width: parent.width
                        height: 112
                        radius: 26 - 12
                        color: card.selected ? Theme.alpha(Theme.primary, 0.22) : Theme.alpha(Theme.fg, 0.07)
                        border.width: card.selected ? 2 : 1
                        border.color: card.selected ? Theme.primary : Theme.alpha(Theme.fg, 0.1)

                        Behavior on color {
                            ColorAnimation { duration: 90 }
                        }

                        // apps on this desktop
                        Grid {
                            visible: !card.isNew && card.modelData.classes.length > 0
                            anchors.centerIn: parent
                            columns: card.modelData.classes.length > 2 ? 3 : card.modelData.classes.length
                            spacing: 8

                            Repeater {
                                model: card.modelData.classes

                                IconImage {
                                    required property string modelData

                                    implicitSize: card.modelData.classes.length > 2 ? 34 : 46
                                    source: ds.iconFor(modelData)
                                }
                            }
                        }

                        Text {
                            visible: card.isNew || card.modelData.classes.length === 0
                            anchors.centerIn: parent
                            text: card.isNew ? "add" : "desktop_windows"
                            color: card.selected ? Theme.primary : Theme.fgDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 38
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: thumb.bottom
                        anchors.topMargin: 10
                        text: card.isNew ? "New Desktop" : "Desktop " + card.modelData.id
                        color: card.selected ? Theme.fg : Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: card.selected ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }
}
