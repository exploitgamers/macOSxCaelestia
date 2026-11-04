import QtQuick
import Caelestia.Services

// System widget. Small: usage bars. Medium: rings plus temperature and uptime.
// Click opens System Monitor. GPU comes from Caelestia's Gpu service.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({}) // Edit "System"…: cpu, gpu, memory, disk toggles

    // GpuType lives in Caelestia.Config (whose Config would shadow ours): 3 = None
    readonly property bool hasGpu: Gpu.type !== 3 && !Gpu.detecting
    readonly property var allStats: [
        { key: "cpu", label: "CPU", value: SysStats.cpu },
        ...(hasGpu ? [{ key: "gpu", label: "GPU", value: Gpu.percentage }] : []),
        { key: "memory", label: "Memory", value: SysStats.mem },
        { key: "disk", label: "Disk", value: SysStats.disk }
    ]
    // the ones switched on (all of them if every one is off, so the widget is never blank)
    readonly property var stats: {
        const on = allStats.filter(s => options[s.key] !== false);
        return on.length ? on : allStats;
    }

    ServiceRef {
        service: Gpu
    }

    function tint(v: real): color {
        return v > 0.9 ? Theme.sys.red : v > 0.75 ? Theme.sys.yellow : Theme.primary;
    }

    // small: three labelled bars
    Column {
        visible: root.size === "small"
        x: 16
        width: root.width - 32
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -1 // optical: each label's cap starts ~3 px into its line box
        spacing: root.stats.length > 3 ? 7 : 11

        Repeater {
            model: root.stats

            Column {
                required property var modelData

                width: parent.width
                spacing: 5

                Item {
                    width: parent.width
                    height: 15

                    Text {
                        text: parent.parent.modelData.label
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.right: parent.right
                        text: Math.round(parent.parent.modelData.value * 100) + "%"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Theme.alpha(Theme.fg, 0.12)

                    Rectangle {
                        width: Math.max(6, parent.width * Math.min(1, parent.parent.modelData.value))
                        height: 6
                        radius: 3
                        color: root.tint(parent.parent.modelData.value)
                        // no Behavior: a 500 ms slide every 2 s refresh kept the desktop repainting
                    }
                }
            }
        }
    }

    // medium: three rings + footer
    Row {
        visible: root.size === "medium"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 17 // rings' top = the footer's baseline inset
        spacing: root.stats.length > 3 ? 16 : 34

        Repeater {
            model: root.stats

            Column {
                required property var modelData

                spacing: 6

                Item {
                    width: 66
                    height: 66

                    Ring {
                        anchors.fill: parent
                        value: parent.parent.modelData.value
                        colour: root.tint(parent.parent.modelData.value)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Math.round(parent.parent.modelData.value * 100) + "%"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.modelData.label
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
            }
        }
    }

    Text {
        visible: root.size === "medium"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        text: (SysStats.tempC > 0 ? Math.round(SysStats.tempC) + "°C  ·  " : "") + "Up " + SysStats.uptimeText()
            + "  ·  " + SysStats.gib(SysStats.memUsed) + " of " + SysStats.gib(SysStats.memTotal)
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 11
        font.features: { "tnum": 1 }
    }
}
