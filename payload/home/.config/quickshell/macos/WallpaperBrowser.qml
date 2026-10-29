pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Wallpaper picker, modelled on macOS System Settings → Wallpaper:
//   current wallpaper on top · rows of wallpapers by collection, each with
//   "Show All" · the selected one ringed in the accent colour · search.
// Online collections come from wallhaven.cc (safe-for-work only). Click a
// wallpaper → saved to ~/Pictures/Wallpapers and applied with
// `caelestia wallpaper -f` (colours follow), revealed with the circular
// transition (Caelestia overlay patch).
// Open: desktop right-click → Change Wallpaper…, Spotlight "Change Wallpaper",
// or `qs -c macos ipc call wallpaper open`.
PanelWindow {
    id: wb

    required property ShellScreen modelData

    // latched while open: focus follows the mouse, so a live binding hopped displays mid-show
    property bool here: false
    Binding on here {
        when: !Shared.wallpaperOpen
        value: (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === wb.modelData?.name
        restoreMode: Binding.RestoreNone
    }
    // Loaded in the background (shell.qml WarmLoader) with the local wallpapers and cached
    // collections already in place; `ready` after a few all-but-invisible frames, so building
    // the scene graph and thumbnails doesn't freeze the opening animation.
    property bool ready: false
    Component.onCompleted: {
        // WarmLoader may build this after wallpaperOpen turned on (Binding inactive): latch once here
        here = (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === wb.modelData?.name;
        lister.running = true;
        const c = Object.assign({}, cats);
        for (const col of collections) {
            const hit = cached(col.key);
            if (hit)
                c[col.key] = hit;
        }
        cats = c; // one assignment: each one rebuilds every row's thumbnails
    }

    FrameAnimation {
        running: !wb.ready
        onTriggered: if ((currentFrame >= 3 && frameTime < 0.022) || currentFrame >= 40) wb.ready = true
    }
    readonly property bool shown: Shared.wallpaperOpen && here && ready
    readonly property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    // collections: key → wallhaven query
    readonly property var collections: [
        { key: "top", title: "Top Wallpapers", q: "", sorting: "toplist" },
        { key: "landscape", title: "Landscape", q: "landscape", sorting: "relevance" },
        { key: "city", title: "Cityscape", q: "city", sorting: "relevance" },
        { key: "space", title: "Space", q: "space", sorting: "relevance" },
        { key: "minimal", title: "Minimal", q: "minimalism", sorting: "relevance" },
        { key: "abstract", title: "Abstract", q: "abstract", sorting: "relevance" },
        { key: "latest", title: "Latest", q: "", sorting: "date_added" }
    ]

    property var cats: ({})       // key → { items: [], total, page, lastPage, loading, failed }
    property string showAll: ""   // "" = overview; a collection key, "mine", or "search"
    property string query: ""
    property string applying: ""  // id/path being downloaded / applied
    property string current: ""   // path in use
    property var mine: []         // local files

    readonly property real thumbW: (content.width - 4 * 14) / 5
    readonly property real thumbH: thumbW * 0.625

    function close(): void {
        Shared.wallpaperOpen = false;
    }

    function collection(key: string): var {
        return key === "search" ? { key: "search", title: `Results for “${query}”`, q: query, sorting: "relevance" }
                                : collections.find(c => c.key === key);
    }

    function load(key: string, more: bool): void {
        const c = collection(key);
        const st = cats[key] ?? { items: [], total: 0, page: 0, lastPage: 1, loading: false, failed: false };
        if (!c || st.loading || (more && st.page >= st.lastPage) || (!more && st.page > 0))
            return;
        // first pages are kept for 30 min across opens: the browser is rebuilt on every open,
        // and quick open/close refetched all 7 collections until wallhaven refused (429)
        const res = `${(wb.modelData?.width ?? 0)}x${(wb.modelData?.height ?? 0)}`;
        const ck = key + "@" + res;
        const hit = !more ? cached(key) : null;
        if (hit) {
            setCat(key, hit);
            return;
        }
        setCat(key, Object.assign({}, st, { loading: true, failed: false }));
        const url = "https://wallhaven.cc/api/v1/search?categories=110&purity=100&ratios=landscape&atleast=" + res
            + "&sorting=" + c.sorting + (c.sorting === "toplist" ? "&topRange=1y" : "")
            + "&page=" + (st.page + 1) + (c.q ? "&q=" + encodeURIComponent(c.q) : "");
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || !wb) // closed (destroyed) meanwhile
                return;
            const prev = wb.cats[key] ?? st;
            try {
                const d = JSON.parse(xhr.responseText);
                setCat(key, { items: [...prev.items, ...d.data.filter(w => /^[a-z0-9]+$/.test(w.id) && /^https:\/\/w\.wallhaven\.cc\/[\w\/.-]+\.(jpe?g|png|webp)$/.test(w.path)) // ids and URLs become file paths and curl args
                                       .map(w => ({ id: w.id, thumb: w.thumbs.large, full: w.path, res: w.resolution }))],
                              total: d.meta.total, page: d.meta.current_page, lastPage: d.meta.last_page, loading: false, failed: false });
                if (!more && key !== "search")
                    Shared.wallhavenCache[ck] = { at: Date.now(), st: wb.cats[key] };
            } catch (e) {
                setCat(key, Object.assign({}, prev, { loading: false, failed: true }));
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function cached(key: string): var {
        const hit = key !== "search" ? Shared.wallhavenCache[`${key}@${wb.modelData?.width ?? 0}x${wb.modelData?.height ?? 0}`] : null;
        return hit && Date.now() - hit.at < 1800000 ? hit.st : null;
    }

    function setCat(key: string, v: var): void {
        const c = Object.assign({}, cats);
        c[key] = v;
        cats = c;
    }

    function runSearch(text: string): void {
        query = text.trim();
        const c = Object.assign({}, cats);
        delete c.search;
        cats = c;
        if (query) {
            showAll = "search";
            load("search", false);
        } else if (showAll === "search") {
            showAll = "";
        }
    }

    // download (if needed) and apply
    function applyOnline(w: var): void {
        if (applying)
            return;
        applying = w.id;
        const path = `${dir}/wallhaven-${w.id}.${w.full.split(".").pop()}`;
        fetcher.target = path;
        fetcher.command = ["sh", "-c", 'mkdir -p "$1" && { [ -s "$3" ] || { curl -fsSL --max-time 60 -o "$3.part" "$2" && mv "$3.part" "$3"; }; } && caelestia wallpaper -f "$3"',
                           "sh", dir, w.full, path];
        fetcher.running = true;
    }

    function applyLocal(path: string): void {
        if (applying)
            return;
        applying = path;
        fetcher.target = path;
        fetcher.command = ["caelestia", "wallpaper", "-f", path];
        fetcher.running = true;
    }

    function prettyName(path: string): string {
        const base = path.split("/").pop().replace(/\.[^.]+$/, "");
        if (base.startsWith("wallhaven-"))
            return "Wallhaven " + base.slice(10);
        return base.replace(/[_-]+/g, " ").replace(/\b\d{3,4}x\d{3,4}\b/, "").replace(/\s+\d+\s*$/, "").trim()
            .replace(/\b\w/g, ch => ch.toUpperCase()) || base;
    }

    Process {
        id: fetcher

        property string target

        onExited: code => {
            if (code === 0)
                wb.current = target;
            wb.applying = "";
            lister.running = true;
        }
    }

    Process {
        id: lister

        command: ["sh", "-c", 'find "$1" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) -printf "%T@ %p\\n" 2>/dev/null | sort -rn | cut -d" " -f2-', "sh", wb.dir]
        stdout: StdioCollector {
            // unchanged: keep the array, or the "Your Wallpapers" row is rebuilt mid-animation
            onStreamFinished: if (text.trim() !== wb.mine.join("\n")) wb.mine = text.trim() ? text.trim().split("\n") : []
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/caelestia/wallpaper/path.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: wb.current = text().trim()
    }

    onShownChanged: {
        grabArmed = false;
        if (shown) {
            armGrab.restart();
            searchBox.forceActiveFocus();
            // let the window finish appearing before thumbnails start loading
            loadLater.restart();
        }
    }

    Timer {
        id: loadLater

        interval: 260
        onTriggered: {
            lister.running = true;
            for (const c of wb.collections)
                wb.load(c.key, false);
        }
    }

    screen: modelData
    color: "transparent"
    implicitWidth: Math.min((modelData?.width ?? 0) - 160, 900)
    implicitHeight: Math.min((modelData?.height ?? 0) - 160, 720)
    exclusionMode: ExclusionMode.Ignore
    // Stays mapped while closed (invisible and click-through): creating the
    // surface on every open cost frames right at the start of the animation.
    visible: true
    // closed (but kept loaded): nothing to draw
    updatesEnabled: panel.visible
    // the panel's resting rectangle, not `item: panel`: an item region is mapped through the
    // panel's open animation (scale/offset) when set, and isn't rebuilt as that animation runs
    mask: Region {
        x: panel.x
        y: panel.y
        width: wb.shown ? panel.width : 0
        height: wb.shown ? panel.height : 0
    }

    WlrLayershell.namespace: "macos-gallery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool grabArmed: false

    Timer {
        id: armGrab

        interval: 80
        onTriggered: wb.grabArmed = wb.shown
    }

    HyprlandFocusGrab {
        windows: [wb]
        active: wb.shown && wb.grabArmed
        onCleared: wb.close()
    }


    // ── a wallpaper thumbnail with macOS's selection ring ───────────────
    component Thumb: Item {
        id: th

        property string source
        property string key       // id or path
        property bool selected
        property bool busy
        property string caption: ""
        signal picked

        width: wb.thumbW
        height: wb.thumbH + (caption ? 20 : 0)

        // accent ring with a small gap, like the Wallpaper pane
        Rectangle {
            x: -4
            y: -4
            width: wb.thumbW + 8
            height: wb.thumbH + 8
            radius: 13
            color: "transparent"
            border.width: 3
            border.color: Theme.primary
            visible: th.selected
        }

        ClippingRectangle {
            width: wb.thumbW
            height: wb.thumbH
            radius: 9
            color: Theme.alpha(Theme.fg, 0.07)
            scale: area.pressed ? 0.97 : 1

            Behavior on scale {
                NumberAnimation { duration: 120 }
            }

            Image {
                anchors.fill: parent
                source: th.source
                sourceSize.width: 320
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 220 }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(1, 1, 1, area.containsMouse && !th.selected ? 0.08 : 0)
            }

            Rectangle {
                anchors.fill: parent
                visible: th.busy
                color: Qt.rgba(0, 0, 0, 0.45)

                Text {
                    anchors.centerIn: parent
                    text: "progress_activity"
                    color: "white"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 26

                    RotationAnimation on rotation {
                        running: th.busy
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }
            }
        }

        Text {
            visible: th.caption !== ""
            y: wb.thumbH + 5
            width: wb.thumbW
            horizontalAlignment: Text.AlignHCenter
            text: th.caption
            elide: Text.ElideRight
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 11
        }

        MouseArea {
            id: area

            width: wb.thumbW
            height: wb.thumbH
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: th.picked()
        }
    }

    // ── window ──────────────────────────────────────────────────────────
    Rectangle {
        id: panel

        anchors.fill: parent
        radius: 14
        color: Theme.alpha(Theme.surface, 0.94)
        border.width: 1
        border.color: Theme.glassBorder
        // open/close on the render thread (Animators): smooth even while the
        // thumbnails and collections load
        // 0.004 while priming: drawn (Qt skips anything under 0.001) but invisible
        opacity: wb.shown ? 1 : wb.ready ? 0 : 0.004
        scale: wb.shown ? 1 : 0.95
        visible: opacity > 0.001 || wb.shown
        clip: true

        Behavior on opacity {
            OpacityAnimator { duration: Config.reducedMotion ? 0 : 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            ScaleAnimator { duration: Config.reducedMotion ? 0 : 280; easing.type: Easing.OutCubic }
        }

        Keys.onEscapePressed: wb.showAll ? (wb.showAll = "") : wb.close()

        // title bar: traffic lights · ‹ › · title · search
        Item {
            id: titleBar

            width: parent.width
            height: 52

            Row {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Repeater {
                    model: ["#ff5f57", "#febc2e", "#28c840"]

                    Rectangle {
                        required property string modelData
                        required property int index

                        width: 12
                        height: 12
                        radius: 6
                        color: index === 0 || lightsArea.containsMouse ? modelData : Theme.alpha(Theme.fg, 0.2)

                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.index === 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wb.close()
                        }
                    }
                }
            }

            MouseArea {
                id: lightsArea

                x: 10
                width: 70
                height: parent.height
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            Text {
                id: back

                x: 92
                anchors.verticalCenter: parent.verticalCenter
                text: "chevron_left"
                color: wb.showAll ? Theme.fg : Theme.alpha(Theme.fg, 0.25)
                font.family: "Material Symbols Rounded"
                font.pixelSize: 26

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    enabled: wb.showAll !== ""
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wb.showAll = ""
                }
            }

            Text {
                anchors.left: back.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: wb.showAll === "" ? "Wallpaper" : wb.showAll === "mine" ? "Your Wallpapers" : wb.collection(wb.showAll)?.title ?? ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 16 // mirrors the traffic lights' 16 px
                anchors.verticalCenter: parent.verticalCenter
                width: 220
                height: 28
                radius: 7
                color: Theme.alpha(Theme.fg, 0.08)
                border.width: searchBox.activeFocus ? 2 : 0
                border.color: Theme.alpha(Theme.primary, 0.6)

                Text {
                    id: lens

                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    color: Theme.fgDim
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 16
                }

                TextInput {
                    id: searchBox

                    anchors.left: lens.right
                    anchors.leftMargin: 5
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: Theme.alpha(Theme.primary, 0.4)
                    font.family: Theme.font
                    font.pixelSize: 12
                    clip: true
                    Keys.onReturnPressed: wb.runSearch(text)
                    Keys.onEscapePressed: text ? (text = "", wb.runSearch("")) : wb.close()

                    Text {
                        visible: !searchBox.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search wallpapers"
                        color: Theme.alpha(Theme.fg, 0.4)
                        font: searchBox.font
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.alpha(Theme.fg, 0.08)
            }
        }

        Flickable {
            id: scroller

            y: titleBar.height
            width: parent.width
            height: parent.height - y
            contentHeight: content.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // "Show All" grids keep loading as you scroll
            onAtYEndChanged: if (atYEnd && wb.showAll && wb.showAll !== "mine") wb.load(wb.showAll, true)

            Column {
                id: content

                x: 26
                y: 22
                width: scroller.width - 52
                spacing: 24

                // ── current wallpaper ───────────────────────────────────
                Rectangle {
                    visible: wb.showAll === ""
                    width: content.width
                    height: 150
                    radius: 12
                    color: Theme.alpha(Theme.fg, 0.05)

                    ClippingRectangle {
                        id: currentPreview

                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 190
                        height: 118
                        radius: 9
                        color: Theme.alpha(Theme.fg, 0.07)

                        Image {
                            anchors.fill: parent
                            source: wb.current ? "file://" + wb.current : ""
                            sourceSize.width: 400
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    Column {
                        anchors.left: currentPreview.right
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 240
                        spacing: 4

                        Text {
                            width: parent.width
                            text: wb.current ? wb.prettyName(wb.current) : "No wallpaper"
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            text: wb.current.indexOf("wallhaven-") >= 0 ? "From wallhaven.cc · colours follow the wallpaper" : "Your picture · colours follow the wallpaper"
                            elide: Text.ElideRight
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }

                        Row {
                            topPadding: 10
                            spacing: 8

                            Rectangle {
                                width: folderText.implicitWidth + 24
                                height: 26
                                radius: 6
                                color: folderArea.containsMouse ? Theme.alpha(Theme.fg, 0.16) : Theme.alpha(Theme.fg, 0.1)

                                Text {
                                    id: folderText

                                    anchors.centerIn: parent
                                    text: "Show in Folder"
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: folderArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && thunar "$1"', "sh",
                                        wb.current ? wb.current.replace(/\/[^/]*$/, "") : wb.dir])
                                }
                            }
                        }
                    }
                }

                // ── overview: one row per collection ────────────────────
                Repeater {
                    model: wb.showAll === "" ? [{ key: "mine", title: "Your Wallpapers" }, ...wb.collections] : []

                    Column {
                        id: section

                        required property var modelData

                        readonly property bool local: modelData.key === "mine"
                        readonly property var st: wb.cats[modelData.key]
                        readonly property var items: local ? wb.mine : (st?.items ?? [])
                        readonly property int total: local ? wb.mine.length : (st?.total ?? 0)

                        width: content.width
                        spacing: 10
                        visible: !local || wb.mine.length > 0

                        Item {
                            width: parent.width
                            height: 20

                            Text {
                                text: section.modelData.title
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: section.total > 5
                                width: showText.implicitWidth + 20
                                height: 22
                                radius: 6
                                color: showArea.containsMouse ? Theme.alpha(Theme.fg, 0.16) : Theme.alpha(Theme.fg, 0.09)

                                Text {
                                    id: showText

                                    anchors.centerIn: parent
                                    text: `Show All (${section.total > 999 ? "999+" : section.total})`
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: showArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wb.showAll = section.modelData.key;
                                        scroller.contentY = 0;
                                    }
                                }
                            }
                        }

                        Row {
                            spacing: 14

                            Repeater {
                                model: section.items.slice(0, 5)

                                Thumb {
                                    required property var modelData

                                    source: section.local ? "file://" + modelData : modelData.thumb
                                    key: section.local ? modelData : modelData.id
                                    selected: section.local ? wb.current === modelData : wb.current.indexOf("wallhaven-" + modelData.id) >= 0
                                    busy: wb.applying === key
                                    onPicked: section.local ? wb.applyLocal(modelData) : wb.applyOnline(modelData)
                                }
                            }
                        }

                        Text {
                            visible: !section.local && section.items.length === 0
                            text: section.st?.failed ? "Couldn't reach wallhaven.cc" : "Loading…"
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                    }
                }

                // ── Show All / search: the whole collection ─────────────
                Flow {
                    visible: wb.showAll !== ""
                    width: content.width
                    spacing: 14

                    Repeater {
                        model: wb.showAll === "mine" ? wb.mine : wb.showAll ? (wb.cats[wb.showAll]?.items ?? []) : []

                        Thumb {
                            required property var modelData

                            readonly property bool local: wb.showAll === "mine"

                            source: local ? "file://" + modelData : modelData.thumb
                            key: local ? modelData : modelData.id
                            selected: local ? wb.current === modelData : wb.current.indexOf("wallhaven-" + modelData.id) >= 0
                            busy: wb.applying === key
                            caption: local ? "" : modelData.res
                            onPicked: local ? wb.applyLocal(modelData) : wb.applyOnline(modelData)
                        }
                    }
                }

                Text {
                    visible: wb.showAll !== "" && wb.showAll !== "mine" && (wb.cats[wb.showAll]?.loading ?? true)
                    text: "Loading…"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 12
                }

                Text {
                    width: content.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Online wallpapers from wallhaven.cc — safe for work only. Picked wallpapers are saved to ~/Pictures/Wallpapers."
                    color: Theme.alpha(Theme.fg, 0.4)
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }
        }
    }
}
