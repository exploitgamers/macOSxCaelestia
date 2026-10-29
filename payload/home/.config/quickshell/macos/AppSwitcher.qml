pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// Alt+Tab switcher (hypr-qol.lua drives it: mac_switch / custom>>macswitch).
// A row of the windows you can switch to — this desktop's and minimised ones,
// most recently used first — with the selected one highlighted and named.
// A quick Alt+Tab tap switches without flashing the panel (it appears after
// a short hold, like macOS).
PanelWindow {
    id: sw

    required property ShellScreen modelData

    // latched while open: focus follows the mouse, so a live binding hopped displays mid-show
    property bool here: false
    Binding on here {
        when: !sw.active
        value: (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === sw.modelData?.name
        restoreMode: Binding.RestoreNone
    }
    property var addresses: []
    property int index: 0
    property bool active: false
    property bool revealed: false
    readonly property bool shown: active && revealed && here

    function toplevel(addr: string): var {
        return Hyprland.toplevels.values.find(t => ("0x" + String(t.address).replace(/^0x/, "")) === addr) ?? null;
    }

    function entryFor(t: var): var {
        const cls = t?.lastIpcObject?.class ?? t?.wayland?.appId ?? "";
        return DesktopEntries.applications.values.length < 0 ? null
             : (DesktopEntries.byId(cls) ?? DesktopEntries.heuristicLookup(cls));
    }

    Connections {
        target: Shared

        function onAppSwitcher(addresses: var, index: int): void {
            if (!sw.active) {
                sw.active = true;
                sw.revealed = false;
                reveal.restart();
                Hyprland.refreshToplevels();
            }
            sw.addresses = addresses;
            sw.index = index;
            // a second Tab means they're browsing: show it now
            if (addresses.length > 1 && index !== 1)
                sw.revealed = true;
        }

        function onAppSwitcherHide(): void {
            sw.active = false;
            sw.revealed = false;
            reveal.stop();
        }
    }

    Timer {
        id: reveal

        interval: 140
        onTriggered: sw.revealed = sw.active
    }

    screen: modelData
    color: "transparent"
    visible: shown || pop.value > 0.01
    // 12 px around the tiles (tile corners concentric with the panel), title 14 px from the bottom
    implicitWidth: Math.min((modelData?.width ?? 0) - 80, row.implicitWidth + 24)
    implicitHeight: 168
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    WlrLayershell.namespace: "macos-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Spring {
        id: pop

        target: sw.shown ? 1 : 0
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
            anchors.verticalCenterOffset: -16 // row top 12 px from the panel edge
            spacing: 10

            Repeater {
                model: sw.addresses

                Item {
                    id: tile

                    required property string modelData
                    required property int index

                    readonly property var win: sw.toplevel(modelData)
                    readonly property var appEntry: sw.entryFor(win)
                    readonly property bool selected: index === sw.index
                    readonly property bool minimized: win?.workspace?.name === "special:minimized"

                    width: 112
                    height: 112

                    Rectangle {
                        anchors.fill: parent
                        radius: 26 - 12
                        color: tile.selected ? Theme.alpha(Theme.fg, 0.16) : "transparent"
                        border.width: tile.selected ? 1 : 0
                        border.color: Theme.alpha(Theme.fg, 0.2)

                        Behavior on color {
                            ColorAnimation { duration: 90 }
                        }
                    }

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 80
                        source: Quickshell.iconPath(tile.appEntry?.icon ?? (tile.win?.lastIpcObject?.class ?? ""), "application-x-executable")
                        opacity: tile.minimized && !tile.selected ? 0.55 : 1
                        scale: tile.selected ? 1.04 : 1

                        Behavior on scale {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }

                    // minimised: a small badge, like the dock's minimised windows
                    Rectangle {
                        visible: tile.minimized
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        width: 24
                        height: 24
                        radius: 12
                        color: "#febc2e"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 10
                            height: 2
                            radius: 1
                            color: Qt.rgba(0, 0, 0, 0.7)
                        }
                    }
                }
            }
        }

        // name of the selected window
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            readonly property var current: sw.toplevel(sw.addresses[sw.index] ?? "")
            textFormat: Text.PlainText // untrusted text: never parse markup
            text: (current?.title ?? "") + (current?.workspace?.name === "special:minimized" ? "  —  minimized" : "")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Medium
        }
    }
}
