import QtQuick
import Quickshell.Services.UPower

// Batteries widget: the laptop plus any Bluetooth devices that report charge.
// Small: up to four rings. Medium: rings with names and percentages.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({}) // Edit "Batteries"…: show all | laptop | devices

    readonly property var devices: {
        const show = options.show ?? "all";
        const list = UPower.devices.values.filter(d => d.isPresent && (d.isLaptopBattery ? show !== "devices"
            : show !== "laptop" && d.type !== UPowerDeviceType.LinePower && d.percentage > 0 && d.nativePath !== ""));
        list.sort((a, b) => (b.isLaptopBattery ? 1 : 0) - (a.isLaptopBattery ? 1 : 0));
        return list.slice(0, 4);
    }

    function iconFor(d: var): string {
        if (d.isLaptopBattery) return "laptop_mac";
        switch (d.type) {
        case UPowerDeviceType.Mouse: return "mouse";
        case UPowerDeviceType.Keyboard: return "keyboard";
        case UPowerDeviceType.Headset:
        case UPowerDeviceType.Headphones: return "headphones";
        case UPowerDeviceType.Phone: return "smartphone";
        case UPowerDeviceType.GamingInput: return "sports_esports";
        case UPowerDeviceType.Tablet: return "tablet";
        case UPowerDeviceType.Speakers: return "speaker";
        default: return "battery_full";
        }
    }

    function charging(d: var): bool {
        return d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged
            || d.state === UPowerDeviceState.PendingCharge;
    }

    function nameOf(d: var): string {
        return d.isLaptopBattery ? "This Laptop" : (d.model || "Device");
    }

    Text {
        visible: root.devices.length === 0
        anchors.centerIn: parent
        text: "No batteries"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 13
    }

    Grid {
        anchors.centerIn: parent
        // optical: the name line's descent left the inks 1–2 px high (measured 2026-11-04)
        anchors.verticalCenterOffset: root.size !== "small" ? 1 : root.devices.length === 1 ? 2 : 0
        // never more columns than rings: an empty column still adds its spacing (ring sat 7 px off centre)
        columns: Math.max(1, Math.min(root.devices.length, root.size === "small" ? 2 : 4))
        rowSpacing: 12
        columnSpacing: root.size === "small" ? 14 : 26

        Repeater {
            model: root.devices

            Column {
                id: cell

                required property var modelData

                readonly property real level: modelData.percentage
                readonly property bool low: level <= 0.2 && !root.charging(modelData)
                // Apple's battery colours: green, yellow when getting low, red at 20 % (charging = green)
                readonly property color tint: root.charging(modelData) ? Theme.sys.green : low ? Theme.sys.red : level <= 0.4 ? Theme.sys.yellow : Theme.sys.green

                spacing: 6

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.size === "small" ? (root.devices.length > 1 ? 58 : 96) : 66
                    height: width

                    Ring {
                        anchors.fill: parent
                        value: cell.level
                        thickness: root.size === "small" && root.devices.length === 1 ? 9 : 6
                        colour: cell.tint
                    }

                    Symbol {
                        anchors.centerIn: parent
                        name: root.iconFor(cell.modelData)
                        fill: true
                        size: parent.width * 0.38
                        weight: 400
                    }

                    // charging bolt badge
                    Symbol {
                        visible: root.charging(cell.modelData)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: parent.width * 0.12
                        name: "bolt"
                        fill: true
                        color: Theme.sys.green
                        size: parent.width * 0.2
                        weight: 600
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.size !== "small" || root.devices.length === 1
                    text: Math.round(cell.level * 100) + "%"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.size !== "small"
                    width: 78
                    horizontalAlignment: Text.AlignHCenter
                    text: root.nameOf(cell.modelData)
                    elide: Text.ElideRight
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }
        }
    }
}
