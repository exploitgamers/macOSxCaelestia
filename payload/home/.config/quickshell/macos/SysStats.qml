pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU / memory / disk / temperature for the System widget. Polls only while a
// System widget exists (or the widget gallery is open).
Singleton {
    id: root

    readonly property bool active: (Config.widgetItems.some(w => w.type === "system" || w.type === "profile") && Shared.widgetsLive) || Shared.widgetEdit

    property real cpu: 0       // 0..1
    property real memUsed: 0   // bytes
    property real memTotal: 1
    property real diskUsed: 0
    property real diskTotal: 1
    property real tempC: 0     // 0 = unknown
    property real uptime: 0    // seconds

    readonly property real mem: memUsed / memTotal
    readonly property real disk: diskUsed / diskTotal

    property real _lastIdle: 0
    property real _lastTotal: 0

    function gib(bytes: real): string {
        return (bytes / 1073741824).toFixed(bytes >= 107374182400 ? 0 : 1) + " GB";
    }

    function uptimeText(): string {
        const h = Math.floor(uptime / 3600), m = Math.floor(uptime % 3600 / 60);
        return h >= 24 ? `${Math.floor(h / 24)}d ${h % 24}h` : `${h}h ${m}m`;
    }

    // read on the spot (tiny /proc files, well under 1 ms): the values then change in the same
    // frame as the clock's second hand instead of a second frame a few ms later
    function poll(): void {
        for (const f of [stat, meminfo, uptimeFile, ...(root._tempPath ? [tempFile] : [])]) {
            f.reload();
            f.waitForJob();
        }
    }

    // deferred: poll() can flip SmartRotate.busy → evaluate() → Config.widgetItems, which `active`
    // is bound to, while this handler still runs inside that binding (binding loop warning)
    onActiveChanged: if (active) Qt.callLater(poll)
    Component.onCompleted: if (active) poll()

    // every 2 s on the wall-clock second, with the clock's second hand: one repaint, not two
    SystemClock {
        enabled: root.active
        precision: SystemClock.Seconds
        onDateChanged: if (seconds % 2 === 0) root.poll()
    }

    Timer {
        running: root.active
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }

    FileView {
        id: stat


        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] ?? 0);
            const total = f.reduce((a, b) => a + b, 0);
            if (root._lastTotal > 0 && total > root._lastTotal)
                root.cpu = 1 - (idle - root._lastIdle) / (total - root._lastTotal);
            root._lastIdle = idle;
            root._lastTotal = total;
        }
    }

    FileView {
        id: meminfo


        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            const val = key => Number((t.match(new RegExp(`^${key}:\\s+(\\d+)`, "m")) ?? [0, 0])[1]) * 1024;
            root.memTotal = val("MemTotal") || 1;
            root.memUsed = root.memTotal - val("MemAvailable");
        }
    }

    FileView {
        id: uptimeFile


        path: "/proc/uptime"
        onLoaded: root.uptime = parseFloat(text())
    }

    // CPU package temperature (Intel x86_pkg_temp, else the first thermal zone)
    property string _tempPath: ""

    FileView {
        id: tempFile


        path: root._tempPath
        onLoaded: root.tempC = parseInt(text()) / 1000
    }

    Process {
        running: root.active && !root._tempPath
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do [ \"$(cat $z/type)\" = x86_pkg_temp ] && { echo $z/temp; exit; }; done; ls /sys/class/thermal/thermal_zone0/temp 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root._tempPath = text.trim()
        }
    }

    Process {
        id: df

        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n")[1]?.trim().split(/\s+/).map(Number) ?? [];
                if (f.length === 2) {
                    root.diskUsed = f[0];
                    root.diskTotal = f[1] || 1;
                }
            }
        }
    }
}
