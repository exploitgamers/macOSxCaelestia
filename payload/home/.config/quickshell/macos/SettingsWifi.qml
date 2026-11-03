pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as C
import Quickshell
import Quickshell.Networking

// Desktop Settings → Wi-Fi (SettingsUi.qml): turn Wi-Fi on/off, join networks
// (with a password field right in the row), disconnect, forget. Scans while open.
Column {
    id: page

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
    readonly property var networks: wifi ? [...wifi.networks.values].filter(n => n.name)
        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
        .slice(0, 20) : []
    property string askingFor: "" // the network whose password field is open

    function strength(n: var): real {
        const s = n.signalStrength ?? 0;
        return s > 1 ? s / 100 : s;
    }

    spacing: 22

    Component.onCompleted: if (wifi) wifi.scannerEnabled = true
    Component.onDestruction: if (wifi) wifi.scannerEnabled = false

    SettingsUi.Group {
        SettingsUi.Setting {
            label: "Wi-Fi"
            detail: !Networking.wifiHardwareEnabled ? "Turned off by the hardware switch (or airplane mode)" : ""
            SettingsUi.Toggle {
                checked: Networking.wifiEnabled
                onToggled: on => Networking.wifiEnabled = on
            }
        }
    }

    SettingsUi.Group {
        visible: Networking.wifiEnabled && page.wifi !== null
        title: "Networks"
        note: page.networks.length === 0 ? "Looking for networks…" : ""

        Repeater {
            model: page.networks

            SettingsUi.Setting {
                id: net

                required property var modelData
                readonly property bool asking: page.askingFor === modelData.name
                readonly property bool secured: modelData.security !== WifiSecurityType.Open

                label: modelData.name
                detail: modelData.connected ? "Connected" : modelData.stateChanging ? "Connecting…" : modelData.known ? "Saved" : ""

                Row {
                    spacing: 8

                    // password field, shown after clicking Join on a new secured network
                    C.TextField {
                        id: psk

                        visible: net.asking
                        width: 170
                        height: 26
                        echoMode: TextInput.Password
                        placeholderText: "Password"
                        color: Theme.fg
                        placeholderTextColor: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 12
                        leftPadding: 10
                        background: Rectangle {
                            radius: 7
                            color: Theme.alpha(Theme.fg, 0.08)
                            border.width: 2
                            border.color: Theme.primary
                        }
                        onVisibleChanged: if (visible) forceActiveFocus()
                        onAccepted: {
                            net.modelData.connectWithPsk(text);
                            page.askingFor = "";
                        }
                        Keys.onEscapePressed: page.askingFor = ""
                    }

                    Symbol { // lock.fill, small and dim like macOS
                        visible: net.secured && !net.asking
                        anchors.verticalCenter: parent.verticalCenter
                        name: "lock"
                        fill: true
                        size: 14
                        weight: 400
                        color: Theme.fgDim
                    }

                    Symbol {
                        visible: !net.asking
                        anchors.verticalCenter: parent.verticalCenter
                        name: page.strength(net.modelData) > 0.66 ? "wifi" : page.strength(net.modelData) > 0.33 ? "wifi_2_bar" : "wifi_1_bar"
                        size: 18
                        weight: 400
                        color: Theme.fg
                    }

                    SettingsUi.Button {
                        visible: net.modelData.known && !net.modelData.connected && !net.asking
                        text: "Forget"
                        onClicked: net.modelData.forget()
                    }

                    SettingsUi.Button {
                        text: net.asking ? "Join" : net.modelData.connected ? "Disconnect" : "Connect"
                        accent: net.asking
                        onClicked: {
                            const n = net.modelData;
                            if (net.asking) {
                                n.connectWithPsk(psk.text);
                                page.askingFor = "";
                            } else if (n.connected) {
                                n.disconnect();
                            } else if (n.known || !net.secured) {
                                n.connect();
                            } else {
                                psk.text = "";
                                page.askingFor = n.name;
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsUi.Group {
        visible: page.wired !== null
        title: "Ethernet"

        SettingsUi.Setting {
            label: "Cable"
            detail: page.wired?.connected ? "Connected" + (page.wired.linkSpeed ? " · " + page.wired.linkSpeed + " Mb/s" : "")
                : page.wired?.hasLink ? "Plugged in, not connected" : "Not plugged in"
        }
    }

    SettingsUi.Group {
        title: "More"

        SettingsUi.Setting {
            label: "VPNs, hidden networks, proxies and IP settings"
            SettingsUi.Button {
                text: "Advanced…"
                onClicked: Quickshell.execDetached(["foot", "-T", "Network Connections", "-e", "nmtui"])
            }
        }
    }
}
