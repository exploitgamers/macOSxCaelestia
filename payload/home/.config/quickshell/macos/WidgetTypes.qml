pragma Singleton

import QtQuick
import Quickshell

// Registry of desktop widget kinds: names, supported sizes, the QML file that
// draws them, and what a plain click does. Sizes follow macOS proportions:
// small is a square, medium two squares wide, large two by two.
Singleton {
    id: root

    readonly property int cell: 170
    // the widget area's height (DesktopWidgets sets it; one screen shows widgets at a time)
    property real deskHeight: 0
    // margins from the widget area's edges, on the same lines as windows, the bar pills
    // and the dock: 8 px from the screen's sides and bottom; at the top the area already
    // starts at the bar's exclusive zone (pills + 4), so 4 more = 8 px under the pills
    readonly property int edge: 8
    readonly property int edgeTop: 4
    // space between widgets: 24, or — when whole rows nearly fit between the margins —
    // the gap that makes them fit exactly (laptop, dock hidden: 926 px → 5 rows, gap 16)
    readonly property int gap: {
        const room = deskHeight - edgeTop - edge;
        if (deskHeight <= 0)
            return 24;
        const rows = Math.floor((room + 16) / (cell + 16));
        const fitted = rows > 1 ? Math.floor((room - rows * cell) / (rows - 1)) : 0;
        return fitted >= 16 && fitted <= 28 ? fitted : 24;
    }

    // click: what clicking the widget opens — its app, or a fallback when the
    // app isn't installed (content may instead define activate(), e.g. Now Playing)
    readonly property var kinds: [
        { type: "clock", category: "Essentials", glyph: "schedule", appId: "", name: "Clock", description: "Analog clock with the date", sizes: ["small", "medium"], click: ["sh", "-c", "command -v gnome-clocks >/dev/null && exec gnome-clocks || xdg-open https://time.is"], file: "WidgetClock.qml" },
        { type: "calendar", category: "Essentials", glyph: "calendar_month", appId: "", name: "Calendar", description: "Today and the month — browse months in Large", sizes: ["small", "medium", "large"], click: ["sh", "-c", "command -v gnome-calendar >/dev/null && exec gnome-calendar || xdg-open https://calendar.google.com"], file: "WidgetCalendar.qml" },
        { type: "weather", category: "Essentials", glyph: "partly_cloudy_day", appId: "", name: "Weather", description: "Conditions and forecast for your location", sizes: ["small", "medium", "large"], click: ["sh", "-c", "command -v gnome-weather >/dev/null && exec gnome-weather || xdg-open https://www.google.com/search?q=weather"], file: "WidgetWeather.qml" },
        { type: "conditions", category: "Essentials", glyph: "thermostat", appId: "", name: "Conditions", description: "Feels like, humidity, wind, UV, sunrise", sizes: ["small", "medium"], click: ["sh", "-c", "command -v gnome-weather >/dev/null && exec gnome-weather || xdg-open https://www.google.com/search?q=weather"], file: "WidgetConditions.qml" },
        { type: "battery", category: "System", glyph: "battery_charging_full", appId: "", name: "Batteries", description: "Laptop and Bluetooth device charge", sizes: ["small", "medium"], click: ["sh", "-c", "command -v gnome-power-statistics >/dev/null && exec gnome-power-statistics || plasma-systemmonitor"], file: "WidgetBattery.qml" },
        { type: "system", category: "System", glyph: "memory", appId: "", name: "System", description: "CPU, GPU, memory and disk — opens System Monitor", sizes: ["small", "medium"], click: ["plasma-systemmonitor"], file: "WidgetSystem.qml" },
        { type: "network", category: "System", glyph: "wifi", appId: "", name: "Network", description: "Live download and upload speed", sizes: ["small", "medium"], click: ["foot", "-e", "nmtui"], file: "WidgetNetwork.qml" },
        { type: "profile", category: "System", glyph: "account_circle", appId: "", name: "Profile", description: "You, uptime, lock and session", sizes: ["small", "medium"], click: ["caelestia", "shell", "drawers", "toggle", "session"], file: "WidgetProfile.qml" },
        { type: "music", category: "Media", glyph: "music_note", appId: "", name: "Now Playing", description: "Control what's playing — click to open the player", sizes: ["small", "medium", "large"], file: "WidgetMusic.qml" },
        { type: "notes", category: "Productivity", glyph: "sticky_note_2", appId: "", name: "Notes", description: "A note that stays on your desktop", sizes: ["small", "medium", "large"], file: "WidgetNotes.qml" },
        { type: "shortcuts", category: "Productivity", glyph: "apps", appId: "", name: "Apps", description: "Your favourite apps, one click away", sizes: ["small", "medium", "large"], file: "WidgetShortcuts.qml" },
        { type: "files", category: "Productivity", glyph: "folder", appId: "thunar", name: "Files", description: "Folders and recent files in Thunar", sizes: ["small", "medium", "large"], click: ["thunar"], file: "WidgetFiles.qml" },
        { type: "photos", category: "Media", glyph: "photo_library", appId: "", name: "Photos", description: "Your newest pictures and screenshots", sizes: ["small", "medium", "large"], click: ["sh", "-c", "thunar \"$HOME/Pictures\""], file: "WidgetPhotos.qml" },
        { type: "vscodium", category: "Productivity", glyph: "code", appId: "codium", name: "VSCodium", description: "Jump back into recent folders", sizes: ["small", "medium", "large"], click: ["codium"], file: "WidgetCode.qml" },
        { type: "firefox", category: "Productivity", glyph: "public", appId: "firefox", name: "Firefox", description: "Your most visited sites", sizes: ["small", "medium", "large"], click: ["firefox"], file: "WidgetFirefox.qml" },
        { type: "claude", category: "Productivity", glyph: "chat", appId: "com.anthropic.Claude", name: "Claude", description: "New chat or Claude Code session", sizes: ["small", "medium"], file: "WidgetClaude.qml" },
        { type: "reminders", category: "Productivity", glyph: "checklist", appId: "", name: "Reminders", description: "A checklist — type to add, tick to finish", sizes: ["small", "medium", "large"], file: "WidgetReminders.qml" },
        { type: "timer", category: "Essentials", glyph: "timer", appId: "", name: "Timer", description: "Quick countdowns with a notification", sizes: ["small", "medium"], file: "WidgetTimer.qml" },
        { type: "kdenlive", category: "Productivity", glyph: "movie", appId: "org.kde.kdenlive", name: "Kdenlive", description: "Recent video projects", sizes: ["small", "medium", "large"], click: ["kdenlive"], file: "WidgetKdenlive.qml" }
    ]

    readonly property var categories: ["Essentials", "System", "Media", "Productivity"]

    // Per-widget options (right-click → Edit "<Name>"…, WidgetEditor on the card's back), saved
    // as items[i].options; a missing or malformed value means the default, so old layouts are unchanged.
    //   segmented: choices [[value, label], …]   toggle: bool   text: string (placeholder when empty)
    readonly property var weatherOptions: [
        { key: "location", label: "Location", type: "text", def: "", placeholder: Config.weatherLocation || "My Location" },
        { key: "unit", label: "Temperature", type: "segmented", def: "auto", choices: [["auto", "Default"], ["C", "°C"], ["F", "°F"]] }
    ]
    readonly property var optionSpecs: ({
        clock: [
            { key: "style", label: "Style", type: "segmented", def: "analog", choices: [["analog", "Analog"], ["digital", "Digital"]] },
            { key: "city", label: "City", type: "text", def: "", placeholder: "Local Time" }
        ],
        calendar: [
            { key: "firstDay", label: "Week Starts On", type: "segmented", def: "auto", choices: [["auto", "Default"], ["sun", "Sun"], ["mon", "Mon"]] },
            { key: "weekNumbers", label: "Week Numbers", type: "toggle", def: false }
        ],
        weather: weatherOptions,
        conditions: weatherOptions,
        battery: [
            { key: "show", label: "Show", type: "segmented", def: "all", choices: [["all", "All"], ["laptop", "Laptop"], ["devices", "Devices"]] }
        ],
        system: [
            { key: "cpu", label: "CPU", type: "toggle", def: true },
            { key: "gpu", label: "GPU", type: "toggle", def: true },
            { key: "memory", label: "Memory", type: "toggle", def: true },
            { key: "disk", label: "Disk", type: "toggle", def: true }
        ],
        network: [
            { key: "units", label: "Speed In", type: "segmented", def: "bytes", choices: [["bytes", "MB/s"], ["bits", "Mbps"]] }
        ],
        notes: [
            { key: "textSize", label: "Text Size", type: "segmented", def: "m", choices: [["s", "Small"], ["m", "Medium"], ["l", "Large"]] }
        ],
        timer: [
            { key: "presets", label: "Presets (minutes)", type: "text", def: "", placeholder: "1, 5, 10, 25" }
        ],
        photos: [
            { key: "folder", label: "Folder", type: "text", def: "", placeholder: "Pictures & Downloads" }
        ]
    })

    function hasOptions(type: string): bool {
        return (optionSpecs[type] ?? []).length > 0;
    }

    // every option of `type`, from saved `raw` (any shape: wrong types fall back to the default)
    function options(type: string, raw: var): var {
        const src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}, out = {};
        for (const o of optionSpecs[type] ?? []) {
            const v = src[o.key];
            out[o.key] = o.type === "toggle" ? (typeof v === "boolean" ? v : o.def)
                : o.type === "segmented" ? (o.choices.some(c => c[0] === v) ? v : o.def)
                : (typeof v === "string" ? v : o.def);
        }
        return out;
    }

    function matches(k: var, q: string): bool {
        q = q.trim().toLowerCase();
        return !q || [k.name, k.description, k.category, k.type].some(s => s.toLowerCase().includes(q));
    }

    function kind(type: string): var {
        return kinds.find(k => k.type === type) ?? null;
    }

    // the desktop grid: widgets sit `edge` from the edges and one gap apart
    readonly property int pitch: cell + gap

    // The desktop grid's spots for a widget of length `len` along one axis of `room`,
    // nearest to v first. ONE grid: fromEnd counts it back from the far edge (columns
    // from the right, so widgets sit flush against it), otherwise from the near edge
    // (rows from the top). Every size uses the same lines, so they all line up — two
    // grids at once (one from each edge) left widgets in columns that didn't match.
    function snaps(v: real, len: real, room: real, fromEnd: bool): var {
        const spots = [], near = fromEnd ? edge : edgeTop; // x: left/right; y: top/bottom
        for (let i = 0; ; i++) {
            const s = fromEnd ? Math.floor(room - edge - len) - i * pitch : near + i * pitch;
            if (s < near - 1 || s + len > room - edge + 1)
                break;
            spots.push(s);
        }
        return spots.sort((a, b) => Math.abs(v - a) - Math.abs(v - b));
    }

    function snap(v: real, len: real, room: real, fromEnd: bool): int {
        return snaps(v, len, room, fromEnd)[0] ?? (fromEnd ? edge : edgeTop);
    }

    function width(size: string): int {
        return size === "small" ? cell : cell * 2 + gap;
    }

    function height(size: string): int {
        return size === "large" ? cell * 2 + gap : cell;
    }

    function sizeName(size: string): string {
        return size.charAt(0).toUpperCase() + size.slice(1);
    }
}
