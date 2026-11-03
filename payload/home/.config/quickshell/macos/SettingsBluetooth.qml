pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Desktop Settings → Bluetooth (SettingsUi.qml): on/off, your devices (connect,
// disconnect, forget, battery) and nearby ones to pair. Searches while open.
Column {
    id: page

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? [...adapter.devices.values] : []
    readonly property var mine: devices.filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || (a.name ?? "").localeCompare(b.name ?? ""))
    // nameless devices show their address as the name: not worth listing
    readonly property var nearby: devices.filter(d => !d.paired && !d.bonded && d.deviceName && d.deviceName.replace(/[-:]/g, "") !== d.address.replace(/[-:]/g, ""))

    function glyph(icon: string): string {
        const map = { "audio-headset": "headset_mic", "audio-headphones": "headphones", "audio-card": "speaker", "input-mouse": "mouse",
            "input-keyboard": "keyboard", "input-gaming": "sports_esports", "input-tablet": "stylus", "phone": "smartphone", "computer": "computer" };
        return map[icon] ?? "bluetooth";
    }

    spacing: 22

    Component.onCompleted: if (adapter?.enabled) adapter.discovering = true
    Component.onDestruction: if (adapter) adapter.discovering = false

    component Device: SettingsUi.Setting {
        id: dev

        required property var modelData

        label: modelData.name || modelData.deviceName
        detail: modelData.pairing ? "Pairing…"
            : modelData.state === BluetoothDeviceState.Connecting ? "Connecting…"
            : modelData.connected ? "Connected" + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "% battery" : "")
            : modelData.paired || modelData.bonded ? "Not connected" : ""

        Row {
            spacing: 8

            Rectangle { // macOS device badge: blue circle when connected, grey when not
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                radius: 13
                color: dev.modelData.connected ? Theme.sys.blue : Theme.alpha(Theme.fg, 0.12)
                Behavior on color { ColorAnimation { duration: 180 } }

                Symbol {
                    anchors.centerIn: parent
                    name: page.glyph(dev.modelData.icon)
                    size: 16
                    fill: true
                    color: dev.modelData.connected ? "white" : Theme.fg
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
            }

            SettingsUi.Button {
                visible: dev.modelData.paired || dev.modelData.bonded
                text: "Forget"
                onClicked: dev.modelData.forget()
            }

            SettingsUi.Button {
                text: dev.modelData.connected ? "Disconnect" : dev.modelData.paired || dev.modelData.bonded ? "Connect" : "Pair"
                accent: !(dev.modelData.paired || dev.modelData.bonded)
                onClicked: {
                    const d = dev.modelData;
                    if (d.connected) {
                        d.disconnect();
                    } else if (d.paired || d.bonded) {
                        d.connect();
                    } else {
                        d.trusted = true; // reconnects on its own next time
                        d.pair();
                    }
                }
            }
        }

        // a newly paired device connects right away
        Connections {
            target: dev.modelData

            function onPairedChanged(): void {
                if (dev.modelData.paired && !dev.modelData.connected)
                    dev.modelData.connect();
            }
        }
    }

    SettingsUi.Group {
        SettingsUi.Setting {
            label: "Bluetooth"
            detail: !page.adapter ? "No Bluetooth adapter found" : page.adapter.enabled ? "Discoverable as \"" + page.adapter.name + "\"" : ""
            SettingsUi.Toggle {
                visible: page.adapter !== null
                checked: page.adapter?.enabled ?? false
                onToggled: on => {
                    page.adapter.enabled = on;
                    if (on)
                        page.adapter.discovering = true;
                }
            }
        }
    }

    SettingsUi.Group {
        visible: (page.adapter?.enabled ?? false) && page.mine.length > 0
        title: "My Devices"

        Repeater {
            model: page.mine

            Device {}
        }
    }

    SettingsUi.Group {
        visible: page.adapter?.enabled ?? false
        title: "Nearby Devices"
        note: page.nearby.length === 0 ? "Searching… Make sure the device is in pairing mode." : ""

        Repeater {
            model: page.nearby

            Device {}
        }
    }
}
