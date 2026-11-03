pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Live colours from Caelestia's current scheme (follows the wallpaper when the
// scheme is "dynamic"). Colours ease to a new palette (see `fade` below).
Singleton {
    id: root

    // Note: colour names avoid the "on" + Capital prefix (Material's onSurface etc.),
    // which QML reserves for signal handlers and silently breaks.
    readonly property var scheme: adapter.colours

    function pick(name: string, fallback: string): color {
        const v = scheme[name];
        return v ? "#" + v : fallback;
    }

    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Displayed colours. When the scheme changes (new wallpaper) they ease from
    // the old palette to the new one over ~0.7 s, stepped by a Timer — QML
    // animations/Behaviors inside a Singleton crash Qt 6.12. First load is instant.
    readonly property var roles: ({
        surface: ["surface", "#141418"], surfaceContainer: ["surfaceContainer", "#1e1e24"],
        surfaceContainerHigh: ["surfaceContainerHigh", "#28282f"], fg: ["onSurface", "#e6e4f0"],
        fgDim: ["onSurfaceVariant", "#c7c5d0"], outlineVariant: ["outlineVariant", "#46464f"],
        primary: ["primary", "#c2c3ee"], fgOnPrimary: ["onPrimary", "#2b2d51"],
        primaryContainer: ["primaryContainer", "#42446a"], tertiary: ["tertiary", "#e6bad7"]
    })

    property color surface: "#141418"
    property color surfaceContainer: "#1e1e24"
    property color surfaceContainerHigh: "#28282f"
    property color fg: "#e6e4f0"
    property color fgDim: "#c7c5d0"
    property color outlineVariant: "#46464f"
    property color primary: "#c2c3ee"
    property color fgOnPrimary: "#2b2d51"
    property color primaryContainer: "#42446a"
    property color tertiary: "#e6bad7"

    property var _from: ({})
    property var _to: ({})
    property real _t: 1
    property bool _ready: false

    onSchemeChanged: {
        const to = {}, from = {};
        for (const k in roles) {
            to[k] = pick(roles[k][0], roles[k][1]);
            from[k] = root[k];
        }
        if (!_ready || Object.keys(scheme).length === 0) {
            for (const k in to)
                root[k] = to[k];
            _ready = Object.keys(scheme).length > 0;
            return;
        }
        _from = from;
        _to = to;
        _t = 0;
        fade.restart();
    }

    Timer {
        id: fade

        interval: 16
        repeat: true
        onTriggered: {
            root._t = Math.min(1, root._t + interval / 700);
            const e = root._t * root._t * (3 - 2 * root._t); // ease in-out
            for (const k in root._to) {
                const a = root._from[k], b = root._to[k];
                root[k] = Qt.rgba(a.r + (b.r - a.r) * e, a.g + (b.g - a.g) * e, a.b + (b.b - a.b) * e, a.a + (b.a - a.a) * e);
            }
            if (root._t >= 1)
                stop();
        }
    }

    // Frosted glass tints (Hyprland blurs these layers). Same colour and opacity
    // as Caelestia's side bar and panels (surface at shell.json
    // appearance.transparency.base, 0.1 less in light mode), so every dock and
    // panel matches.
    readonly property real panelAlpha: {
        let t = {};
        try {
            t = JSON.parse(shellFile.text() || "{}").appearance?.transparency ?? {};
        } catch (e) {}
        if (t.enabled === false)
            return 1;
        const base = typeof t.base === "number" ? t.base : 0.85;
        return Math.max(0, Math.min(1, base - (adapter.mode === "light" ? 0.1 : 0)));
    }
    readonly property color glass: alpha(surface, panelAlpha)
    readonly property color glassStrong: glass
    readonly property color glassBorder: alpha(fg, 0.13)

    // Corner radii. Anything sitting in a corner of one of these uses
    // radius − inset (concentric corners), e.g. panelRadius - 14.
    readonly property int panelRadius: 22  // large glass sheets and widgets
    readonly property int windowRadius: 14 // Hyprland decoration.rounding
    readonly property int menuRadius: 12   // menus and small popovers

    // Inter ≈ SF Pro Text; Inter Display (optical size for big text) ≈ SF Pro Display.
    // One family per property: Qt doesn't parse comma lists (that fell back to Noto Sans).
    readonly property string font: "Inter"
    readonly property string displayFont: "Inter Display"
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    // Apple's system colours (HIG), dark and light appearance: tints for Symbol (multicolor mode) and
    // SymbolTile. Fixed hues on purpose: Apple's icons don't follow the wallpaper scheme.
    readonly property var sys: adapter.mode === "light" ? ({
            red: "#ff3b30", orange: "#ff9500", yellow: "#ffcc00", green: "#34c759", mint: "#00c7be", teal: "#30b0c7",
            cyan: "#32ade6", blue: "#007aff", indigo: "#5856d6", purple: "#af52de", pink: "#ff2d55", brown: "#a2845e", gray: "#8e8e93"
        }) : ({
            red: "#ff453a", orange: "#ff9f0a", yellow: "#ffd60a", green: "#30d158", mint: "#63e6e2", teal: "#40c8e0",
            cyan: "#64d2ff", blue: "#0a84ff", indigo: "#5e5ce6", purple: "#bf5af2", pink: "#ff375f", brown: "#ac8e68", gray: "#98989d"
        })

    // The colour a symbol has in Apple's multicolor rendering (sun yellow, rain cyan, heart pink…); "" = none.
    // Extend this table rather than hard-coding tints in components.
    readonly property var symbolTints: ({
            clear_day: "yellow", sunny: "yellow", wb_sunny: "yellow", partly_cloudy_day: "yellow", light_mode: "yellow",
            bedtime: "yellow", clear_night: "yellow", nightlight: "yellow", thunderstorm: "yellow", bolt: "yellow",
            flash_on: "yellow", star: "yellow", lightbulb: "yellow", warning: "yellow", sunny_snowing: "yellow",
            rainy: "cyan", water_drop: "cyan", humidity_percentage: "cyan", ac_unit: "cyan", weather_snowy: "cyan", snowing: "cyan",
            cloud: "gray", foggy: "gray", air: "teal", mist: "gray",
            favorite: "pink", music_note: "pink", library_music: "pink", graphic_eq: "pink",
            battery_full: "green", battery_charging_full: "green", check_circle: "green", task_alt: "green", call: "green",
            wifi: "blue", bluetooth: "blue", folder: "blue", folder_open: "blue", info: "blue", language: "blue", public: "blue",
            error: "red", calendar_month: "red", calendar_today: "red", event: "red", record_voice_over: "red", alarm: "orange",
            timer: "orange", local_fire_department: "orange", thermostat: "orange", whatshot: "orange",
            photo_library: "purple", image: "purple", movie: "indigo", sticky_note_2: "yellow", checklist: "orange",
            memory: "teal", speed: "teal", account_circle: "gray", settings: "gray", delete: "gray",
            picture_as_pdf: "red", folder_zip: "blue", folder_code: "blue", home: "blue", download: "blue", terminal: "gray",
            wb_twilight: "orange", nights_stay: "indigo", schedule: "orange"
        })

    function symbolTint(name: string): string {
        const t = symbolTints[name];
        return t ? sys[t] : "";
    }


    FileView {
        id: shellFile

        path: Quickshell.env("HOME") + "/.config/caelestia/shell.json"
        watchChanges: true
        onFileChanged: reload()
    }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/caelestia/scheme.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: adapter

            property var colours: ({})
            property string mode: "dark"
        }
    }
}
