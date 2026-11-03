import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Services

// Network widget: live download/upload speed with a short history graph.
// Medium adds the Wi-Fi network name. Click opens the network manager (nmtui).
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({}) // Edit "Network"…: units bytes (MB/s) | bits (Mbps)

    property var down: [] // last 40 samples, bytes/s
    property var up: []
    property string ssid: ""

    function rate(b: real): string {
        if (options.units === "bits") {
            const bits = b * 8;
            if (bits >= 1e6) return (bits / 1e6).toFixed(1) + " Mbps";
            if (bits >= 1e3) return Math.round(bits / 1e3) + " Kbps";
            return Math.round(bits) + " bps";
        }
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s";
        if (b >= 1024) return Math.round(b / 1024) + " KB/s";
        return Math.round(b) + " B/s";
    }

    ServiceRef {
        service: NetworkUsage
    }

    // samples on the wall-clock second, like the clock's second hand: both land in one frame
    SystemClock {
        enabled: root.widgetId === "" || Shared.widgetsLive
        precision: SystemClock.Seconds
        onDateChanged: {
            const d = NetworkUsage.downloadSpeed ?? 0, u = NetworkUsage.uploadSpeed ?? 0;
            // a full, flat graph that stays flat looks the same: no repaint
            if (root.down.length === 40 && root.down.every(v => v === d) && root.up.every(v => v === u))
                return;
            root.down = [...root.down.slice(-39), d];
            root.up = [...root.up.slice(-39), u];
            graph.requestPaint();
        }
    }

    Process {
        id: wifi

        running: root.size !== "small"
        command: ["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: root.ssid = (text.split("\n").find(l => l.startsWith("yes:")) ?? "").slice(4)
        }
    }

    Timer {
        running: root.size !== "small"
        interval: 30000
        repeat: true
        onTriggered: wifi.running = true
    }

    Text {
        x: 16
        y: 13
        text: root.size !== "small" && root.ssid ? root.ssid : "Network"
        color: Theme.primary
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.Bold
    }

    Column {
        x: 16
        y: 36
        spacing: 2

        Repeater {
            model: [
                { icon: "arrow_downward", value: root.down[root.down.length - 1] ?? 0 },
                { icon: "arrow_upward", value: root.up[root.up.length - 1] ?? 0 }
            ]

            Row {
                required property var modelData

                spacing: 4

                // arrow.down / arrow.up in the graph's colour for each direction (the filled circle variant muddies at 17 px)
                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: parent.modelData.icon
                    fill: false
                    color: parent.modelData.icon === "arrow_downward" ? Theme.primary : Theme.tertiary
                    size: 17
                    weight: 600
                }

                Text {
                    text: root.rate(parent.modelData.value)
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: root.size === "small" ? 17 : 20
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    Canvas {
        id: graph

        x: 12
        width: root.width - 24
        height: root.size === "small" ? 56 : 70
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const max = Math.max(1024, ...root.down, ...root.up);
            const draw = (data, colour, fill) => {
                if (data.length < 2)
                    return;
                const step = width / 39;
                const x0 = width - (data.length - 1) * step;
                ctx.beginPath();
                ctx.moveTo(x0, height);
                data.forEach((v, i) => ctx.lineTo(x0 + i * step, height - 2 - (height - 4) * v / max));
                ctx.lineTo(width, height);
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(colour.r, colour.g, colour.b, fill);
                ctx.fill();
                ctx.beginPath();
                data.forEach((v, i) => {
                    const px = x0 + i * step, py = height - 2 - (height - 4) * v / max;
                    i ? ctx.lineTo(px, py) : ctx.moveTo(px, py);
                });
                ctx.strokeStyle = colour;
                ctx.lineWidth = 1.6;
                ctx.stroke();
            };
            draw(root.down, Theme.primary, 0.22);
            draw(root.up, Theme.tertiary, 0.12);
        }
    }
}
