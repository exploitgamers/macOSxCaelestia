pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services
import qs.utils

GridLayout {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    required property bool horizontal
    readonly property int axisPadding: Tokens.padding.small // [macos] ends 8 px from the screen edges, like the top

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        for (let i = 0; i < repeater.count; i++) {
            const tray = (repeater.itemAt(i) as EntryWrapper)?.item as Tray;
            if (tray)
                tray.expanded = false;
        }
    }

    function axisCenterOf(item: Item): real {
        const c = item.mapToItem(root, item.implicitWidth / 2, item.implicitHeight / 2);
        return horizontal ? c.x : c.y;
    }

    function entryAt(pos: real): string {
        const ch = (horizontal ? childAt(pos, height / 2) : childAt(width / 2, pos)) as EntryWrapper;
        return ch?.entryId ?? "";
    }

    // [macos] drop-downs open on click (Interactions.qml / the chips); clicking the
    // same one again closes it. Hovering only switches between them while one is open.
    property Item mediaEntry: null // [macos] centred, see the spacer delegate
    property bool mediaCapped: false // [macos] the media pill can't reach the centre (spacer delegate)
    // width of everything right of the pill's trailing spacer (+ the bar's end padding)
    readonly property real afterMedia: {
        let w = axisPadding;
        let spacers = 0;
        for (let i = 0; i < repeater.count; i++) {
            const it = repeater.itemAt(i) as EntryWrapper;
            if (!it)
                continue;
            if (it.entryId === "spacer") {
                spacers++;
                continue;
            }
            if (spacers >= 2 && it.visible)
                w += Math.ceil(it.implicitWidth) + columnSpacing; // [macos] the layout rounds widths up (fractional pills pushed power off screen)
        }
        return w;
    }
    readonly property int firstSpacer: (repeater.model?.values ?? []).findIndex(e => e.id === "spacer")
    readonly property var popoutEntries: ["statusIcons", "clock", "stats", "controls", "activeWindow", "media"]

    function togglePopout(pos: real): void {
        const wasOpen = popouts.hasCurrent;
        const wasName = popouts.currentName;
        controlsFlash = false;
        checkPopout(pos);
        if (wasOpen && popouts.currentName === wasName)
            popouts.hasCurrent = false;
    }

    function centerOf(item: Item): real {
        const p = item.mapToItem(root, item.width / 2, item.height / 2);
        return horizontal ? p.x : p.y;
    }

    // [macos] the volume / brightness keys open the controls drop-down for a moment
    // (Caelestia's left-edge OSD is turned off in shell.json)
    property bool controlsFlash: false
    property bool keysReady: false

    function flashControls(): void {
        if (!keysReady || (popouts.hasCurrent && (popouts.currentName !== "controls" || !controlsFlash)))
            return;
        for (let i = 0; i < children.length; i++) {
            const ch = children[i] as EntryWrapper;
            if (ch?.entryId === "controls") {
                checkPopout(centerOf(ch));
                controlsFlash = true;
                flashTimer.restart();
                return;
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: root.keysReady = true // the first readings at startup aren't key presses
    }

    Timer {
        id: flashTimer

        interval: 1500
        onTriggered: {
            if (root.controlsFlash && root.popouts.currentName === "controls")
                root.popouts.hasCurrent = false;
            root.controlsFlash = false;
        }
    }

    Connections {
        target: Audio

        function onVolumeChanged(): void {
            root.flashControls();
        }

        function onMutedChanged(): void {
            root.flashControls();
        }
    }

    Connections {
        target: Brightness.getMonitorForScreen(root.screen) ?? null
        ignoreUnknownSignals: true

        function onBrightnessChanged(): void {
            root.flashControls();
        }
    }

    function checkPopout(pos: real): void {
        const ch = (horizontal ? childAt(pos, height / 2) : childAt(width / 2, pos)) as EntryWrapper;

        if (ch?.entryId !== "tray")
            closeTray();

        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const id = ch.entryId;
        const start = horizontal ? ch.x : ch.y;

        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const icon = horizontal ? items.childAt(mapToItem(items, pos, 0).x, items.height / 2) : items.childAt(items.width / 2, mapToItem(items, 0, pos).y);
            if (icon) {
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => axisCenterOf(icon));
                popouts.hasCurrent = true;
            }
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            if (!Config.bar.tray.compact || (tray.expanded && !tray.expandIcon.contains(horizontal ? mapToItem(tray.expandIcon, pos, tray.implicitHeight / 2) : mapToItem(tray.expandIcon, tray.implicitWidth / 2, pos)))) {
                const index = Math.floor(((pos - start - tray.padding * 2 + tray.spacing) / (horizontal ? tray.layout.implicitWidth : tray.layout.implicitHeight)) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    popouts.currentName = `traymenu${index}`;
                    popouts.currentCenter = Qt.binding(() => axisCenterOf(trayItem));
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else if (id === "activeWindow" && Config.bar.popouts.activeWindow && Config.bar.activeWindow.showOnHover) {
            popouts.currentName = id.toLowerCase();
            popouts.currentCenter = axisCenterOf(ch.item as Item);
            popouts.hasCurrent = true;
        } else if (id === "controls") {
            // [macos] volume / brightness sliders (popouts/Controls.qml)
            popouts.currentName = "controls";
            popouts.currentCenter = axisCenterOf(ch.item as Item);
            popouts.hasCurrent = true;
        } else if (id === "media") {
            // [macos] the now-playing pill opens its controls on hover (popouts/Media.qml)
            popouts.currentName = "media";
            popouts.currentCenter = axisCenterOf(ch.item as Item);
            popouts.hasCurrent = true;
        } else if (id === "stats") {
            // [macos] hovering the system pill expands it (popouts/SystemMonitor.qml)
            popouts.currentName = "sysmon";
            popouts.currentCenter = axisCenterOf(ch.item as Item);
            popouts.hasCurrent = true;
        } else if (id === "clock") {
            // [macos] hovering the clock expands the calendar tab
            popouts.currentName = "calendar";
            popouts.currentCenter = axisCenterOf(ch.item as Item);
            popouts.hasCurrent = true;
        } else {
            // [macos] entries without a popout (logo, desktops, spacers, power) close
            // the open one: along a long top bar it otherwise lingers until you leave the bar
            popouts.hasCurrent = false;
        }
    }

    function handleWheel(pos: real, angleDelta: point): void {
        const ch = (horizontal ? childAt(pos, height / 2) : childAt(width / 2, pos)) as EntryWrapper;
        if (ch?.entryId === "controls") {
            // [macos] the volume / brightness pill: each half scrolls its own value
            const onVolume = pos - (horizontal ? ch.x : ch.y) < (horizontal ? ch.width : ch.height) / 2;
            const monitor = Brightness.getMonitorForScreen(screen);
            if (onVolume)
                angleDelta.y > 0 ? Audio.incrementVolume() : Audio.decrementVolume();
            else if (monitor)
                monitor.setBrightness(monitor.brightness + (angleDelta.y > 0 ? 1 : -1) * GlobalConfig.services.brightnessIncrement);
        } else if (ch?.entryId === "workspaces" && Config.bar.scrollActions.workspaces) {
            // Workspace scroll
            const mon = Hypr.monitorFor(screen);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`);
            else if (angleDelta.y < 0 || mon.activeWorkspace?.id > 1)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "r${angleDelta.y > 0 ? "-" : "+"}1" })` : `workspace r${angleDelta.y > 0 ? "-" : "+"}1`);
        } else if (pos < (horizontal ? screen.width : screen.height) / 2 && Config.bar.scrollActions.volume) {
            // Volume scroll on top/left half
            if (angleDelta.y > 0)
                Audio.incrementVolume();
            else if (angleDelta.y < 0)
                Audio.decrementVolume();
        } else if (Config.bar.scrollActions.brightness) {
            // Brightness scroll on bottom/right half
            const monitor = Brightness.getMonitorForScreen(screen);
            if (angleDelta.y > 0)
                monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
            else if (angleDelta.y < 0)
                monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
        }
    }

    columns: horizontal ? -1 : 1
    rowSpacing: Tokens.spacing.medium
    columnSpacing: Tokens.spacing.medium

    Repeater {
        id: repeater

        model: ScriptModel {
            // [macos] Caelestia's config rejects unknown entry ids (the whole bar went
            // blank), so the small widgets are added here: media between the two
            // spacers (centre of the bar), system stats after the tray
            values: {
                const out = [];
                let spacers = 0;
                for (const e of root.Config.bar.entries.values.filter(e => e.enabled)) {
                    if (e.id === "spacer" && ++spacers === 2)
                        out.push({ id: "media", enabled: true });
                    if (e.id === "statusIcons")
                        out.push({ id: "controls", enabled: true });
                    out.push({ id: e.id, enabled: true }); // one kind of object for the delegate chooser
                    if (e.id === "tray") // app icons sit just left of the stats
                        out.push({ id: "stats", enabled: true });
                }
                return out;
            }
        }

        DelegateChooser {
            role: "id"

            DelegateChoice {
                roleValue: "spacer"
                delegate: EntryWrapper {
                    // [macos] the spacer before the now-playing pill is sized so the pill
                    // sits in the middle of the screen; both filling evenly left it off to
                    // the left (the right side of the bar is wider)
                    readonly property bool centresMedia: root.horizontal && index === root.firstSpacer && (root.mediaEntry?.visible ?? false)

                    // centred when there's room; otherwise as far right as fits (capped) and the
                    // second spacer drops out, so media → next pill is one gap like every other pair
                    readonly property real centreWidth: root.width / 2 - x - root.columnSpacing - (root.mediaEntry?.implicitWidth ?? 0) / 2
                    readonly property real roomWidth: Math.floor(root.width - x - Math.ceil(root.mediaEntry?.implicitWidth ?? 0) - root.afterMedia - root.columnSpacing)
                    readonly property bool isSecond: root.horizontal && index > root.firstSpacer && (root.mediaEntry?.visible ?? false)

                    readonly property bool capped: centresMedia && roomWidth < centreWidth
                    onCappedChanged: if (index === root.firstSpacer) root.mediaCapped = capped // (a Binding isn't an Item: EntryWrapper's default property)

                    visible: !(isSecond && root.mediaCapped)
                    Layout.fillHeight: !root.horizontal
                    Layout.fillWidth: root.horizontal && !centresMedia
                    Layout.preferredWidth: centresMedia ? Math.max(0, Math.min(centreWidth, roomWidth)) : -1
                }
            }
            DelegateChoice {
                roleValue: "logo"
                delegate: EntryWrapper {
                    OsIcon {
                        objectName: "taskbarLogo"
                        screenState: root.screenState
                    }
                }
            }
            DelegateChoice {
                roleValue: "workspaces"
                delegate: EntryWrapper {
                    Workspaces {
                        objectName: "taskbarWorkspaces"
                        screen: root.screen
                        fullscreen: root.fullscreen
                        horizontal: root.horizontal
                    }
                }
            }
            DelegateChoice {
                roleValue: "activeWindow"
                delegate: EntryWrapper {
                    ActiveWindow {
                        objectName: "taskbarActiveWindow"
                        bar: root
                        monitor: Brightness.getMonitorForScreen(root.screen)
                        horizontal: root.horizontal
                    }
                }
            }
            DelegateChoice {
                roleValue: "tray"
                delegate: EntryWrapper {
                    Tray {
                        objectName: "taskbarTray"
                        horizontal: root.horizontal
                        // [macos] clicked open; the same icon again closes it
                        onMenuRequested: (item, index) => {
                            const name = `traymenu${index}`;
                            if (root.popouts.hasCurrent && root.popouts.currentName === name) {
                                root.popouts.hasCurrent = false;
                                return;
                            }
                            root.popouts.currentName = name;
                            root.popouts.currentCenter = Qt.binding(() => root.axisCenterOf(item));
                            root.popouts.hasCurrent = true;
                        }
                    }
                }
            }
            // [macos] small menu-bar widgets
            DelegateChoice {
                roleValue: "media"
                delegate: EntryWrapper {
                    Component.onCompleted: root.mediaEntry = this
                    BarChip {
                        readonly property var player: Players.active
                        shown: player !== null && (player.trackTitle ?? "") !== ""
                        icon: player?.isPlaying ? "pause" : "play_arrow"
                        label: (player?.trackTitle ?? "") + (player?.trackArtist ? "  ·  " + player.trackArtist : "")
                        maxLabelWidth: 260
                        onActivated: player?.togglePlaying()
                    }
                }
            }
            DelegateChoice {
                roleValue: "weather"
                delegate: EntryWrapper {
                    BarChip {
                        icon: Weather.icon
                        label: Weather.temp
                        onActivated: Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=weather " + (Weather.city || "")])
                        Component.onCompleted: Weather.reload()
                        Timer {
                            running: true
                            repeat: true
                            interval: 15 * 60 * 1000
                            onTriggered: Weather.reload()
                        }
                    }
                }
            }
            DelegateChoice {
                roleValue: "controls"
                delegate: EntryWrapper {
                    ControlsChip {
                        screen: root.screen
                    }
                }
            }
            DelegateChoice {
                roleValue: "stats"
                delegate: EntryWrapper {
                    StatsChip {}
                }
            }
            DelegateChoice {
                roleValue: "clock"
                delegate: EntryWrapper {
                    Clock {
                        objectName: "taskbarClock"
                        horizontal: root.horizontal
                    }
                }
            }
            DelegateChoice {
                roleValue: "statusIcons"
                delegate: EntryWrapper {
                    StatusIcons {
                        objectName: "taskbarStatusIcons"
                        horizontal: root.horizontal
                    }
                }
            }
            DelegateChoice {
                roleValue: "power"
                delegate: EntryWrapper {
                    Power {
                        objectName: "taskbarPowerButton"
                        screenState: root.screenState
                    }
                }
            }
        }
    }

    component EntryWrapper: Item {
        required property var modelData
        required property int index
        default property Item item
        readonly property string entryId: modelData.id

        Layout.topMargin: !root.horizontal && index === 0 ? root.axisPadding : 0
        Layout.bottomMargin: !root.horizontal && index === repeater.count - 1 ? root.axisPadding : 0
        Layout.leftMargin: root.horizontal && index === 0 ? root.axisPadding : 0
        Layout.rightMargin: root.horizontal && index === repeater.count - 1 ? root.axisPadding : 0
        Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0
        // a widget with nothing to show (no music) leaves no gap. Not item.visible:
        // a child's visible follows its parent's, so that hid every entry for good
        // (an empty tray too, so it doesn't leave a double gap)
        visible: item?.shown ?? (entryId === "tray" ? (item?.items?.count ?? 0) > 0 : true)

        children: item
    }

    // [macos] pieces of the system pill (inline components can't nest)
    // [macos] volume and brightness: icon + percentage each; scroll a half to change
    // it, click the speaker to mute, hover for sliders
    component ControlsChip: StyledRect {
        id: controls

        HoverWash {} // [macos] the bar's one hover hint
        BarInk { id: pillInk; pill: controls } // [macos] adaptive text colour

        required property ShellScreen screen
        readonly property var monitor: Brightness.getMonitorForScreen(screen)

        implicitWidth: controlsRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: Tokens.sizes.bar.innerWidth
        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer

        StatLabel { id: pctWidth; text: "88%"; visible: false } // [macos] two digits: "100%" left a wide gap after the icon

        Row {
            id: controlsRow

            readonly property BarInk ink: pillInk // [macos] for StatLabel
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                fontStyle: Tokens.font.icon.builders.small.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.getVolumeIcon(Audio.volume, Audio.muted) // [macos] the same symbols as the drop-down
                color: pillInk.c(Colours.palette.m3tertiary)

                // [macos] click to mute; no hover wash (a translucent blob spilling past the
                // icon and over the pill's edge) — the pointer changes instead
                StateLayer {
                    showHoverBackground: false
                    cursorShape: Qt.PointingHandCursor
                    color: Colours.palette.m3onSurface
                    onClicked: {
                        if (Audio.sink?.audio)
                            Audio.sink.audio.muted = !Audio.muted;
                    }
                }
            }

            // fixed width: "9%" → "10%" → "100%" resized the pill on every step
            StatLabel { text: `${Math.round(Audio.volume * 100)}%`; width: Math.max(implicitWidth, pctWidth.width); horizontalAlignment: Text.AlignRight }

            StatLabel { text: "·"; color: pillInk.c(Colours.palette.m3outline) }

            MaterialIcon {
                fontStyle: Tokens.font.icon.builders.small.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                anchors.verticalCenter: parent.verticalCenter
                text: "brightness_6"
                color: pillInk.c(Colours.palette.m3tertiary)
            }

            StatLabel { text: `${Math.round((controls.monitor?.brightness ?? 0) * 100)}%`; width: Math.max(implicitWidth, pctWidth.width); horizontalAlignment: Text.AlignRight }
        }
    }

    component StatLabel: StyledText {
        anchors.verticalCenter: parent.verticalCenter
        color: parent?.ink?.c(Colours.palette.m3onSurface) ?? Colours.palette.m3onSurface // [macos] the row's BarInk
        font: Tokens.font.body.builders.small.scale(0.9 * Tokens.sizes.bar.innerWidth / 26).build()
    }

    component StatMeter: Rectangle {
        property real value

        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 6
        radius: 3
        readonly property var ink: parent?.ink ?? null // [macos] the row's BarInk
        color: Qt.alpha(ink?.c(Colours.palette.m3onSurface) ?? Colours.palette.m3onSurface, 0.15)

        Rectangle {
            width: Math.max(height, parent.width * Math.min(1, parent.value))
            height: parent.height
            radius: 3
            color: parent.ink?.c(parent.value > 0.9 ? Colours.palette.m3error : Colours.palette.m3tertiary) ?? (parent.value > 0.9 ? Colours.palette.m3error : Colours.palette.m3tertiary)
            // [macos] no width animation: it re-animated on every stats update
        }
    }

    // [macos] system monitor pill: CPU history as little bars + %, temperature,
    // and fill meters for memory and disk; click opens System Monitor
    component StatsChip: StyledRect {
        id: stats

        readonly property int histLen: 14
        property var cpuHist: []
        readonly property color accent: pillInk.c(Colours.palette.m3tertiary)
        readonly property color track: Qt.alpha(pillInk.c(Colours.palette.m3onSurface), 0.15)

        BarInk { id: pillInk; pill: stats } // [macos] adaptive text colour

        implicitWidth: statsRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: Tokens.sizes.bar.innerWidth
        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer

        ServiceRef { service: Cpu }
        ServiceRef { service: Memory }
        ServiceRef { service: Storage }

        // [macos] every reading is taken on the wall-clock second, so the pill repaints once a
        // second in step with the desktop clock widget (one compositor frame, not two or three
        // at the services' own random phases)
        property real cpu: 0
        property real temp: 0
        property real mem: 0
        property real disk: 0

        function sample(): void {
            cpuHist = [...cpuHist.slice(1 - histLen), Cpu.percentage];
            cpu = Cpu.percentage;
            temp = Cpu.temperature;
            mem = Memory.percentage;
            disk = Storage.primaryDisk?.perc ?? 0;
        }

        Component.onCompleted: sample()

        SystemClock {
            precision: SystemClock.Seconds
            onDateChanged: stats.sample()
        }

        Row {
            id: statsRow

            readonly property BarInk ink: pillInk // [macos] for StatLabel / StatMeter
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                fontStyle: Tokens.font.icon.builders.small.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                anchors.verticalCenter: parent.verticalCenter
                text: "memory"
                color: stats.accent
            }

            StatLabel { text: "CPU" }

            // history: one bar per second, newest on the right. [macos] a 12 px box centred on
            // the text line, each bar on a faint track (they used to sit below the baseline)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                height: 12
                spacing: 1

                Repeater {
                    model: stats.histLen

                    Rectangle {
                        required property int index

                        readonly property real v: stats.cpuHist[index - (stats.histLen - stats.cpuHist.length)] ?? 0

                        width: 3
                        height: parent.height
                        radius: 1
                        color: stats.track

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(2, parent.height * Math.min(1, parent.v))
                            radius: 1
                            color: parent.v > 0.9 ? pillInk.c(Colours.palette.m3error) : Qt.alpha(stats.accent, 0.45 + 0.55 * parent.index / stats.histLen)
                            // [macos] no height animation: the history shifts every second
                        }
                    }
                }
            }

            StatLabel { text: `${Math.round(stats.cpu * 100)}%` + (stats.temp > 0 ? `  ${Math.round(stats.temp)}°` : "") }

            StatLabel { text: "·"; color: pillInk.c(Colours.palette.m3outline) }

            StatLabel { text: "RAM" }
            StatMeter { value: stats.mem }
            StatLabel { text: `${Math.round(stats.mem * 100)}%` }

            StatLabel {
                visible: !!Storage.primaryDisk
                text: "·"
                color: pillInk.c(Colours.palette.m3outline)
            }
            StatLabel { visible: !!Storage.primaryDisk; text: "SSD" }
            StatMeter { visible: !!Storage.primaryDisk; value: stats.disk }
            StatLabel { visible: !!Storage.primaryDisk; text: `${Math.round(stats.disk * 100)}%` }
        }

        StateLayer {
            radius: stats.radius
            color: Colours.palette.m3onSurface
            onClicked: root.togglePopout(root.centerOf(stats)) // [macos] its drop-down (Open System Monitor is in it)
        }
    }

    // [macos] a pill like the status icons: symbol + short text, click for its app
    component BarChip: StyledRect {
        id: chip

        property string icon
        property string label
        property int maxLabelWidth: 200
        property bool shown: true
        signal activated

        implicitWidth: root.horizontal ? chipRow.implicitWidth + Tokens.padding.medium * 2 : Tokens.sizes.bar.innerWidth
        implicitHeight: Tokens.sizes.bar.innerWidth
        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer

        BarInk { id: pillInk; pill: chip } // [macos] adaptive text colour

        Row {
            id: chipRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                fontStyle: Tokens.font.icon.builders.small.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                color: pillInk.c(Colours.palette.m3tertiary)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.horizontal
                width: Math.min(implicitWidth, chip.maxLabelWidth)
                elide: Text.ElideRight
                text: chip.label
                color: pillInk.c(Colours.palette.m3onSurface)
                font: Tokens.font.body.builders.small.scale(0.9 * Tokens.sizes.bar.innerWidth / 26).build()
            }
        }

        StateLayer {
            radius: chip.radius
            color: Colours.palette.m3onSurface
            onClicked: chip.activated()
        }
    }
}
