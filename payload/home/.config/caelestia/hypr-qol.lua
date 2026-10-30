-- Quality-of-life: multi-monitor, gaming and video-editing tweaks.
-- Loaded from hypr-user.lua. Laptop: ThinkPad, Intel Iris Xe, panel eDP-1.

-- Title-bar height (hyprbars, hypr-titlebars.lua) — everything that lines up with
-- the bar uses this; the macos shell has the same in Shared.titleBarHeight
mac_bar_height = 28

-- Configurable shortcuts (Desktop Settings → Keyboard; defaults in hypr-vars.lua).
-- mac_bind replaces whatever else is bound to that key; "" means no shortcut.
local kb = require("variables")
function mac_bind(key, action)
    if type(key) ~= "string" or key == "" then return end
    pcall(hl.unbind, key)
    hl.bind(key, action)
end

local laptop = "eDP-1"
local laptop_mode = "1920x1200@60.00Hz"
-- 125 %: at 100 % the 14" panel's text and panels were too small to read.
-- (1920×1200 ÷ 1.25 = 1536×960 exactly, so no blurry fractional edges.)
local laptop_scale = 1.25

-----------------
---- WINDOWS ----
-----------------

-- Move and resize without keybinds:
--   resize → drag any window edge or corner (cursor changes on the border)
--   move   → drag the app's own title bar, or three-finger drag on the touchpad
hl.config({
    general = {
        resize_on_border        = true,
        extend_border_grab_area = 15, -- generous grab zone outside the 1px border
        hover_icon_on_border    = true,
    },
})

hl.gesture({ fingers = 3, direction = "swipe", action = "move" })

-- macOS window mode (new windows open floating & centred) is a window rule in
-- hypr-window-defaults.lua, loaded before Caelestia's rules. Caelestia's
-- special-workspace apps (music, chat, to-do, system monitor) stay tiled:
for _, tag in ipairs({ "music_player", "communication_app", "todo_app", "system_monitor" }) do
    hl.window_rule({ match = { tag = tag }, float = false })
end

-- macOS zoom (green title-bar button / title-bar double-click). Hyprland allows
-- only one maximised window per workspace — maximising a second one silently
-- un-maximises the first, so closing the second left the first at its old size.
-- Zoom instead floats the window and sizes it to the free screen area (inside
-- the dock/side bar, with the normal gaps), remembering its previous geometry,
-- so any number of windows can be zoomed independently. Press again to restore.
-- window address → geometry before zooming. Kept in a file because `hyprctl reload` (wallpaper
-- changes reload too) starts a fresh Lua state: the restore size was lost while the shell kept
-- its list, so the dock stayed hidden. In XDG_RUNTIME_DIR: addresses mean nothing after log-out.
-- One "addr x y w h floating" line per window, parsed as data (never run as Lua). No /tmp
-- fallback: a shared dir would let another user feed it.
local ZOOM_FILE = os.getenv("XDG_RUNTIME_DIR") and os.getenv("XDG_RUNTIME_DIR") .. "/macos-zoomed"
local zoomed = {}
do
    local f = ZOOM_FILE and io.open(ZOOM_FILE)
    if f then
        for line in f:lines() do
            local a, x, y, w, h, fl = line:match("^(%w+) (%S+) (%S+) (%S+) (%S+) (%a+)$")
            if a then
                x, y, w, h = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
                if x and y and w and h then zoomed[a] = { x = x, y = y, w = w, h = h, floating = fl == "true" } end
            end
        end
        f:close()
    end
end

-- the usable area with the usual gaps; zoom, the top-edge snap preview and mac_clamp all use it,
-- so a zoomed window stops 8 px above the permanent dock (user, 2026-10-17)
local function zoom_rect(win)
    local mon   = win.monitor or hl.get_active_monitor()
    local r     = type(mon.reserved) == "table" and mon.reserved or {}
    local scale = mon.scale or 1
    local gap   = require("variables").windowGapsOut or 0
    -- a floating window's 1 px border is drawn outside its box: without it the visible gap was 7
    -- (tiled windows already get it: Hyprland's layout reserves the border)
    local bs    = require("variables").windowBorderSize or 0
    local bar   = hl.plugin.hyprbars and mac_bar_height or 0 -- title bar sits above the content box
    local left, top = r.left or 0, r.top or 0
    -- a bare screen edge (no bar/dock/panel reserving it, e.g. the auto-hiding dock): 8 px,
    -- the line the bar pills and the dock sit on; next to a reserved zone the normal gap
    -- (those zones already include their share of the 8 px: bar = pills + 4, dock = plate + 12)
    local function m(res) return ((res or 0) > 0 and gap or 8) + bs end
    return {
        x = mon.x + left + m(r.left),
        y = mon.y + top + gap + bs + bar,
        w = math.floor(mon.width / scale - left - (r.right or 0) - m(r.left) - m(r.right)),
        h = math.floor(mon.height / scale - top - (r.bottom or 0) - gap - bs - m(r.bottom) - bar),
    }
end

-- Caelestia's "centre floating windows" rule centres the content box in the work area,
-- ignoring the title bar above it, so a new window sat 12-14 px high. For a window that
-- is still on that spot: where it goes when the whole window (bar included) is centred
-- in the usable area (hypr-window-memory.lua's window.open). nil = leave it.
function mac_recentre_spot(win)
    local mon = win.monitor or hl.get_active_monitor()
    local r = type(mon.reserved) == "table" and mon.reserved or {}
    local s = mon.scale or 1
    local W, H = mon.width / s - (r.left or 0) - (r.right or 0), mon.height / s - (r.top or 0) - (r.bottom or 0)
    local rx = mon.x + (r.left or 0) + (W - win.size.x) / 2
    local ry = mon.y + (r.top or 0) + (H - win.size.y) / 2
    if math.abs(win.at.x - rx) > 2 or math.abs(win.at.y - ry) > 2 then return nil end
    local z = zoom_rect(win)
    return z.x + math.floor((z.w - win.size.x) / 2), z.y + math.floor((z.h - win.size.y) / 2)
end

local function near(a, b) return math.abs(a - b) <= 3 end

-- Special-desktop apps (Discord, Spotify… tiled above) stay tiled only on their special desktop.
-- Restored from Minimise onto a normal desktop they stayed tiled: under every floating window,
-- so Alt+Tab/dock focus couldn't bring them forward, and with tiling gaps instead of ours.
local SPECIAL_APP_TAGS = { music_player = true, communication_app = true, todo_app = true, system_monitor = true }
hl.on("window.move_to_workspace", function(win)
    if not (mac_floating_mode and win and not win.floating
            and win.workspace and win.workspace.id > 0) then return end
    for _, t in ipairs(win.tags or {}) do
        if SPECIAL_APP_TAGS[(t:gsub("%*$", ""))] then
            local addr = win.address
            -- after the move finishes: Hyprland re-places it on the new desktop after this event
            mac_special_float_timers = mac_special_float_timers or {} -- global: local timers get collected
            mac_special_float_timers[addr] = hl.timer(function()
                mac_special_float_timers[addr] = nil
                local w0 = hl.get_window("address:" .. addr)
                -- fullscreen checked here, not in the event: Hyprland clears it during the move and
                -- sets it back right after, so the event always saw 0 and this floated a fullscreen game
                if not w0 or w0.floating or (w0.fullscreen or 0) ~= 0 then return end
                local z = zoom_rect(w0)
                local w, h = math.floor(z.w * 0.62), math.floor(z.h * 0.7)
                hl.dispatch(hl.dsp.window.float({ action = "on", window = w0 }))
                hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = w0 }))
                hl.dispatch(hl.dsp.window.move({ x = z.x + math.floor((z.w - w) / 2), y = z.y + math.floor((z.h - h) / 2), window = w0 }))
            end, { timeout = 30, type = "oneshot" })
            return
        end
    end
end)

-- zoom animation: ~220 ms ease-out whose curve never passes 1 (no overshoot past the
-- target rect). WINDOWS_MOVE must match windowsMove in ~/.config/hypr/hyprland/animations.lua.
ZOOM_MS = 220
WINDOWS_MOVE = { leaf = "windowsMove", enabled = true, speed = 5.5, bezier = "macOS" }
hl.curve("macZoom", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })

-- tell the shell which windows are zoomed (custom>>maczoom>>addr,addr…; Shared.zoomedWindows)
local function announce_zoom()
    local list = {}
    local f = ZOOM_FILE and io.open(ZOOM_FILE .. ".tmp", "w")
    for addr, g in pairs(zoomed) do
        list[#list + 1] = addr
        if f then f:write(string.format("%s %s %s %s %s %s\n", addr, g.x, g.y, g.w, g.h, tostring(g.floating))) end
    end
    if f then f:close(); os.rename(ZOOM_FILE .. ".tmp", ZOOM_FILE) end
    hl.dispatch(hl.dsp.event("maczoom>>" .. table.concat(list, ",")))
end

local function zoom_apply(addr)
    local win = addr and hl.get_window("address:" .. addr) or hl.get_active_window()
    if not win or (win.fullscreen or 0) ~= 0 then return end
    local key, z = win.address, zoom_rect(win)
    local saved  = zoomed[key]
    local is_zoomed = saved and win.floating and near(win.at.x, z.x) and near(win.at.y, z.y)
        and near(win.size.x, z.w) and near(win.size.y, z.h)

    -- animated (the user asked for it, 2026-10-13): Hyprland's own move/resize animation,
    -- sped up to ZOOM_MS with a no-overshoot ease-out just for the zoom, then put back
    local function set_box(x, y, w, h)
        hl.animation({ leaf = "windowsMove", enabled = true, speed = ZOOM_MS / 100, bezier = "macZoom" })
        hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = win }))
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = win }))
        -- a second press within ZOOM_MS: drop the first timer, or it puts the normal speed back mid-animation
        if mac_zoom_anim_timer then mac_zoom_anim_timer:set_enabled(false) end
        mac_zoom_anim_timer = hl.timer(function() -- global: a local timer is collected before firing
            mac_zoom_anim_timer = nil
            hl.animation(WINDOWS_MOVE) -- back to the normal window motion
        end, { timeout = ZOOM_MS + 60, type = "oneshot" })
    end

    -- already filling the screen with nothing to go back to (the size from before was
    -- lost in a config reload, or never known): back to a normal centred window,
    -- instead of "restoring" to the same full size (the button did nothing)
    -- (tiled too: a lone tiled window, e.g. Spotify/Discord on their special desktops, already
    -- fills the area — zooming it only floated it in place, so the button seemed dead)
    local full = near(win.at.x, z.x) and near(win.at.y, z.y) and near(win.size.x, z.w) and near(win.size.y, z.h)
    if full and (not saved or (near(saved.w, z.w) and near(saved.h, z.h))) then
        zoomed[key] = nil
        if not win.floating then
            hl.dispatch(hl.dsp.window.float({ action = "on", window = win }))
        end
        local w, h = math.floor(z.w * 0.62), math.floor(z.h * 0.7)
        set_box(z.x + math.floor((z.w - w) / 2), z.y + math.floor((z.h - h) / 2), w, h)
        return
    end

    if is_zoomed then
        zoomed[key] = nil
        if saved.floating then
            set_box(saved.x, saved.y, saved.w, saved.h)
        else
            hl.dispatch(hl.dsp.window.float({ action = "off", window = win }))
        end
        return
    end

    zoomed[key] = { x = win.at.x, y = win.at.y, w = win.size.x, h = win.size.y, floating = win.floating }
    if not win.floating then
        hl.dispatch(hl.dsp.window.float({ action = "on", window = win }))
    end
    set_box(z.x, z.y, z.w, z.h)
end

-- mac_zoom() zooms the focused window, mac_zoom("0x…") a given one (no focus needed)
function mac_zoom(addr)
    zoom_apply(addr)
    announce_zoom()
end
mac_zoom_announce = announce_zoom -- the shell asks again after a restart (Shared.qml)

-- forget zoomed windows that are gone or no longer on their zoom rect (resized by a border
-- drag, Super+drag or the keyboard). Skipped while a zoom animates.
function mac_zoom_prune()
    if mac_zoom_anim_timer then return end
    local changed = false
    for addr in pairs(zoomed) do
        local w = hl.get_window("address:" .. addr)
        local z = w and zoom_rect(w)
        if not (w and w.floating and near(w.at.x, z.x) and near(w.at.y, z.y)
                and near(w.size.x, z.w) and near(w.size.y, z.h)) then
            zoomed[addr] = nil
            changed = true
        end
    end
    if changed then announce_zoom() end
end
-- after a reload: drop stale entries and tell the shell the current list
mac_zoom_reload_timer = hl.timer(function() mac_zoom_prune(); announce_zoom() end, { timeout = 500, type = "oneshot" })
-- keyboard resizes (Caelestia's resize binds): re-check shortly after a key while anything is zoomed
hl.on("input.keyboard.key", function(_, _, state)
    if state ~= 0 or not next(zoomed) then return end
    if mac_zoom_key_timer then mac_zoom_key_timer:set_enabled(false) end
    mac_zoom_key_timer = hl.timer(mac_zoom_prune, { timeout = 150, type = "oneshot" })
end)

hl.on("window.close", function(win)
    if win and win.address then
        zoomed[win.address] = nil
        if mac_switch_fs then mac_switch_fs[win.address] = nil end
        if mac_hidden then mac_hidden[win.address] = nil end -- addresses get reused by new windows
    end
end)

-- macOS minimise: park the window on a hidden workspace without showing it.
-- The dock brings it back (click its icon). Called by the yellow title-bar
-- button via `hyprctl eval 'mac_minimize()'`.
-- mac_minimize() minimises the focused window; mac_minimize("0x…") a given one
-- (the dock minimises an app's focused window when you click its icon).
function mac_minimize(addr)
    -- a given window that has closed meanwhile is NOT replaced by the focused one
    local win
    if addr then win = hl.get_window("address:" .. addr) else win = hl.get_active_window() end
    if not win then return end
    -- follow = false: a following move opens special:minimized, focuses the window and warps
    -- the pointer to it (closed again just below, but a fullscreen game kept it open)
    hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", window = win, follow = false }))
    local mon = hl.get_active_monitor()
    local special = mon and mon.active_special_workspace
    if special and special.name == "special:minimized" then
        hl.dispatch(hl.dsp.workspace.toggle_special("minimized"))
    end
end
-- Focusing a window on a hidden special workspace opens that workspace, so a minimised app
-- asking for activation (misc.focus_on_activate) would pop special:minimized open by itself.
-- It still turns urgent; only the dock / Alt+Tab (mac_restore) bring it back.
mac_minimized_rule = hl.window_rule({
    name  = "mac-minimized-no-activate",
    match = { workspace = "special:minimized" },
    focus_on_activate = false,
})

-- Bring a minimised window back onto the workspace you're on, focused and in front
-- (dock icon click / Now Playing, see ~/.config/quickshell/macos/BottomDock.qml)
function mac_restore(addr)
    local win = hl.get_window("address:" .. addr)
    if not win then return end
    -- hidden with Super+H: the app's other windows hidden with it come back too
    local group = mac_hidden and mac_hidden[win.address]
    if group then
        for _, a in ipairs(group) do
            mac_hidden[a] = nil
            local other = a ~= win.address and hl.get_window("address:" .. a)
            if other and other.workspace and other.workspace.name == "special:minimized" then mac_restore(a) end
        end
    end
    if mac_switch_fs then mac_switch_fs[win.address] = nil end -- brought back some other way: forget Alt+Tab's fullscreen
    local ws = hl.get_active_workspace()
    if ws and (not win.workspace or win.workspace.id ~= ws.id) then
        hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws.id), window = win }))
    end
    local mon = hl.get_active_monitor()
    local special = mon and mon.active_special_workspace
    if special and special.name == "special:minimized" then
        hl.dispatch(hl.dsp.workspace.toggle_special("minimized"))
    end
    hl.dispatch(hl.dsp.focus({ window = win }))
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = win }))
end

-- Show Desktop (SUPER+F3, like macOS Cmd+F3; also the bottom-right hot corner):
-- every window on the current desktop goes to a hidden workspace, revealing the
-- widgets; the same again brings them all back (the one you were in, focused).
-- Kept apart from special:minimized so the dock doesn't call them minimised.
local shown = nil -- { addrs = {...}, focus = addr, ws = id } while the desktop is shown
-- a config reload restarts this Lua state: pick up windows a Show Desktop left hidden,
-- or they'd be stranded there (alt-tab and title-bar drags skip special workspaces)
for _, win in ipairs(hl.get_windows()) do
    if win.workspace and win.workspace.name == "special:showdesktop" then
        shown = shown or { addrs = {} }
        table.insert(shown.addrs, win.address)
    end
end

function mac_show_desktop()
    if shown then
        local cur = hl.get_active_workspace()
        -- back to the desktop they were hidden from (pressed again on another desktop,
        -- they used to land on that one); unknown after a config reload: this one
        local home = shown.ws or (cur and cur.id)
        for _, addr in ipairs(shown.addrs) do
            local win = hl.get_window("address:" .. addr)
            if win and home then
                hl.dispatch(hl.dsp.window.move({ workspace = tostring(home), window = win, follow = false }))
            end
        end
        local mon = hl.get_active_monitor()
        local special = mon and mon.active_special_workspace
        if special and special.name == "special:showdesktop" then
            hl.dispatch(hl.dsp.workspace.toggle_special("showdesktop"))
        end
        local f = shown.focus and hl.get_window("address:" .. shown.focus)
        if f and cur and home == cur.id then hl.dispatch(hl.dsp.focus({ window = f })) end
        shown = nil
        return
    end
    local ws = hl.get_active_workspace()
    if not ws or ws.special then return end
    local active = hl.get_active_window()
    local addrs = {}
    for _, win in ipairs(hl.get_windows()) do
        if win.workspace and win.workspace.id == ws.id and win.mapped ~= false then
            table.insert(addrs, win.address)
            hl.dispatch(hl.dsp.window.move({ workspace = "special:showdesktop", window = win }))
        end
    end
    if #addrs == 0 then return end
    local mon = hl.get_active_monitor()
    local special = mon and mon.active_special_workspace
    if special and special.name == "special:showdesktop" then
        hl.dispatch(hl.dsp.workspace.toggle_special("showdesktop"))
    end
    shown = { addrs = addrs, focus = active and active.address or nil, ws = ws.id }
end

mac_bind(kb.kbShowDesktop, function() mac_show_desktop() end)
mac_bind(kb.kbMinimize, function() mac_minimize() end)

-- macOS Hide (Cmd+H): minimise every window of the focused app on this desktop, then
-- focus the most recently used window left. A dock click on the app brings them all
-- back (mac_restore restores the whole group). Global so a reload doesn't strand groups.
mac_hidden = mac_hidden or {}
function mac_hide()
    local active = hl.get_active_window()
    local ws = hl.get_active_workspace()
    if not (active and ws) or ws.special then return end
    local group, rest = {}, {}
    for _, w in ipairs(hl.get_windows()) do
        if w.workspace and w.workspace.id == ws.id then
            table.insert(w.class == active.class and group or rest, w)
        end
    end
    local addrs = {}
    for _, w in ipairs(group) do
        table.insert(addrs, w.address)
        mac_hidden[w.address] = addrs
        mac_minimize(w.address)
    end
    table.sort(rest, function(a, b) return (a.focus_history_id or 99) < (b.focus_history_id or 99) end)
    if rest[1] then
        hl.dispatch(hl.dsp.focus({ window = rest[1] }))
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = rest[1] }))
    end
end
mac_bind(kb.kbHide, function() mac_hide() end)

-- macOS muscle memory, on keys nothing else uses (Cmd → SUPER, as everywhere here):
-- Cmd+Shift+3 / 4 / 5 screenshots, Ctrl+Cmd+Q lock. Ctrl+Up (Mission Control) is
-- CTRL+SUPER+Up, next to CTRL+SUPER+Left/Right for the desktops (see kbOverview below).
hl.bind("SUPER + SHIFT + 3", hl.dsp.exec_cmd("caelestia screenshot"))
hl.bind("SUPER + SHIFT + 4", hl.dsp.global("caelestia:screenshot"))
hl.bind("SUPER + SHIFT + 5", hl.dsp.global("caelestia:screenshotFreeze"))
hl.bind("CTRL + SUPER + Q", hl.dsp.global("caelestia:lock"))
-- Hot corners (macOS): rest the pointer in a screen corner for ~0.2 s. Detected
-- here by polling the pointer (10×/s), so no window or layer can cover them.
-- The actions come from macos.json → hotCorners; the macos shell passes them in
-- via mac_hot_corners{…} whenever they change (HotCorners.qml).
mac_mouse_down = false -- left button held (set by the press/release binds below)
local corner_actions = { tl = "launcher", tr = "none", bl = "lock", br = "showdesktop" }
local corner_state = { at = nil, n = 0, fired = false }

function mac_hot_corners(t)
    for k, v in pairs(t or {}) do corner_actions[k] = v end
end

-- at config load, take the saved choices from macos.json (the shell pushes live changes)
do
    local f = io.open(os.getenv("HOME") .. "/.config/caelestia/macos.json")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    local block = text:match('"hotCorners"%s*:%s*(%b{})')
    if block then
        for key, short in pairs({ topLeft = "tl", topRight = "tr", bottomLeft = "bl", bottomRight = "br" }) do
            local v = block:match('"' .. key .. '"%s*:%s*"(%a+)"')
            if v then corner_actions[short] = v end
        end
    end
end

local function corner_run(action)
    local qs = "qs -c macos ipc call "
    local cmds = {
        launcher = qs .. "launcher toggle", overview = qs .. "overview toggle",
        spotlight = qs .. "spotlight toggle", widgets = qs .. "widgets edit",
        lock = "qs -c caelestia ipc call lock lock",
    }
    if action == "showdesktop" then
        mac_show_desktop()
    elseif cmds[action] then
        hl.dispatch(hl.dsp.exec_cmd(cmds[action]))
    end
end

-- A corner that touches another monitor isn't a corner (the pointer passes through it,
-- e.g. along the dock to the next screen): false when the point just past either of its
-- edges lies on another monitor. mons: for testing, defaults to the real ones.
function mac_corner_open(mon, p, which, mons)
    local dx = which:sub(2) == "l" and -4 or 4
    local dy = which:sub(1, 1) == "t" and -4 or 4
    for _, m in ipairs(mons or hl.get_monitors()) do
        if m.name ~= mon.name and not m.disabled then
            local s = m.scale or 1
            local function inside(x, y)
                return x >= m.x and x < m.x + m.width / s and y >= m.y and y < m.y + m.height / s
            end
            if inside(p.x + dx, p.y) or inside(p.x, p.y + dy) then return false end
        end
    end
    return true
end

-- kept in a global: an unreferenced repeating timer gets garbage-collected and stops
mac_corner_timer = hl.timer(function()
    local p = hl.get_cursor_pos()
    local mon = p and hl.get_monitor_at(p.x, p.y)
    local which = nil
    if mon and not mac_mouse_down then
        local w, h = mon.width / (mon.scale or 1), mon.height / (mon.scale or 1)
        local left, top = p.x <= mon.x + 2, p.y <= mon.y + 2
        local right, bottom = p.x >= mon.x + w - 3, p.y >= mon.y + h - 3
        which = (top and left and "tl") or (top and right and "tr") or (bottom and left and "bl") or (bottom and right and "br") or nil
        if which and not mac_corner_open(mon, p, which) then which = nil end
    end
    local active = hl.get_active_window()
    if active and (active.fullscreen or 0) ~= 0 then which = nil end
    if which ~= corner_state.at then
        corner_state = { at = which, n = 0, fired = false }
        return
    end
    if not which or corner_state.fired then return end
    corner_state.n = corner_state.n + 1
    if corner_state.n >= 2 then -- ~0.2 s in the corner; once until it leaves
        corner_state.fired = true
        corner_run(corner_actions[which] or "none")
    end
end, { timeout = 100, type = "repeat" })

-- Force Quit Applications (ForceQuit.qml), macOS Cmd+Option+Esc
mac_bind(kb.kbForceQuit, hl.dsp.exec_cmd("qs -c macos ipc call forcequit toggle"))

-- Mission Control-style overview of this desktop's windows (Overview.qml)
mac_bind(kb.kbOverview, hl.dsp.exec_cmd("qs -c macos ipc call overview toggle"))
hl.bind("CTRL + SUPER + Up", hl.dsp.exec_cmd("qs -c macos ipc call overview toggle")) -- macOS Ctrl+Up

-- The side panel (notifications, quick toggles, recordings). Caelestia binds this key
-- to its "caelestia:sidebar" shortcut, which no longer opens anything on 2.5.
mac_bind(kb.kbShowSidebar, hl.dsp.exec_cmd("qs -c caelestia ipc call drawers toggle sidebar"))

mac_bind(kb.kbDesktopSettings, hl.dsp.exec_cmd("qs -c macos ipc call settings toggle"))

-- Alt+Tab / Shift+Alt+Tab: switch AND bring to the front. Hyprland's cycle
-- only moves focus, so with floating windows the focused one stayed hidden
-- behind the others. mouse_refocus = false keeps that focus unless the pointer
-- actually crosses into another window (otherwise the slightest mouse movement
-- handed focus straight back to the window under the pointer).
-- Alt+Tab app switcher (macOS / Windows style). Holding Alt, each Tab moves
-- through this desktop's windows AND minimised ones, most recently used first;
-- the macos shell draws the switcher (AppSwitcher.qml). Releasing Alt switches
-- (a minimised window is restored onto this desktop), Esc cancels.
-- Hyprland's own cycle_next never saw minimised windows: they live on the
-- hidden special:minimized workspace.
local switcher = nil -- { list = { addresses }, idx }
local ALT_KEYS = { [64] = true, [108] = true } -- Alt_L, Alt_R (xkb)

local function switcher_show()
    hl.dispatch(hl.dsp.event("macswitch>>show|" .. switcher.idx .. "|" .. table.concat(switcher.list, ",")))
end

function mac_switch(dir)
    if not switcher then
        local ws = hl.get_active_workspace()
        local wins = {}
        for _, w in ipairs(hl.get_windows()) do
            local name = w.workspace and w.workspace.name or ""
            -- special:showdesktop: this desktop's windows while Show Desktop hides them
            -- (Alt+Tab did nothing at all after the bottom-right hot corner); special app desktops
            -- (Discord on special:communication, Spotify on special:music…): focusing opens them
            if w.mapped ~= false and ((ws and w.workspace and w.workspace.id == ws.id) or name:match("^special:")) then
                table.insert(wins, w)
            end
        end
        if #wins == 0 then return end
        table.sort(wins, function(a, b) return (a.focus_history_id or 99) < (b.focus_history_id or 99) end)
        local list = {}
        for _, w in ipairs(wins) do table.insert(list, w.address) end
        switcher = { list = list, idx = 1 }
        -- Esc cancels; bound only while open so it's swallowed (the key event can't
        -- stop it reaching the app — it used to cancel the switcher AND the app's dialog)
        hl.bind("ALT + Escape", function() mac_switch_end(false) end)
    end
    local n = #switcher.list
    switcher.idx = ((switcher.idx - 1 + dir) % n) + 1
    switcher_show()
end

mac_switch_fs = {} -- address → fullscreen mode (1 maximised, 2 fullscreen) Alt+Tab took away

function mac_switch_end(commit)
    if not switcher then return end
    local addr = switcher.list[switcher.idx]
    switcher = nil
    hl.unbind("ALT + Escape")
    hl.dispatch(hl.dsp.event("macswitch>>hide"))
    if not commit or not addr then return end
    local win = hl.get_window("address:" .. addr)
    if not win then return end
    -- A fullscreen window always draws above its desktop's other windows, so picking
    -- another one hides it like macOS (minimised, fullscreen remembered, no resize seen);
    -- picking it again in Alt+Tab brings it back fullscreen.
    -- on_focus_under_fullscreen = 0 still protects fullscreen from windows that open or ask for focus.
    local ws = hl.get_active_workspace()
    for _, o in ipairs(hl.get_windows()) do
        if o.address ~= win.address and (o.fullscreen or 0) ~= 0 and ws and o.workspace and o.workspace.id == ws.id then
            mac_switch_fs[o.address] = o.fullscreen
            mac_minimize(o.address)
        end
    end
    local fs = mac_switch_fs[win.address]
    mac_switch_fs[win.address] = nil
    if win.workspace and win.workspace.name == "special:minimized" then
        mac_restore(addr)
    else
        if shown and win.workspace and win.workspace.name == "special:showdesktop" then
            mac_show_desktop() -- like macOS: picking a window ends Show Desktop
        end
        hl.dispatch(hl.dsp.focus({ window = win }))
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = win }))
    end
    if fs then
        hl.dispatch(hl.dsp.window.fullscreen({ window = win, action = "set", mode = fs == 1 and "maximized" or "fullscreen" }))
    end
end

hl.on("input.keyboard.key", function(keycode, _, state)
    if not switcher then return end
    if state == 0 and ALT_KEYS[keycode] then
        mac_switch_end(true)
    end -- Esc: the ALT + Escape bind (mac_switch), which swallows it
end)

do
    local v = require("variables")
    hl.unbind(v.kbWindowCycleNext)
    hl.unbind(v.kbWindowCyclePrev)
    hl.bind(v.kbWindowCycleNext, function() mac_switch(1) end, { repeating = true })
    hl.bind(v.kbWindowCyclePrev, function() mac_switch(-1) end, { repeating = true })
end

hl.config({ input = { mouse_refocus = false } })
-- Closing a window focuses the one used before it (like macOS), not whatever is under
-- the pointer: over the desktop that left nothing focused (Caelestia sets 1)
hl.config({ input = { focus_on_close = 0 } })

-- Fullscreen stays fullscreen: a window that opens (or asks for focus) while
-- another is fullscreen opens behind it instead of un-fullscreening it
-- (Caelestia's misc.lua uses 2 = "unfullscreen"). The dock focuses explicitly,
-- so clicking an app there still switches to it.
hl.config({ misc = { on_focus_under_fullscreen = 0 } })

-- F11 toggles real fullscreen for whatever window is focused. Before, F11 only
-- worked in apps that implement it themselves (Firefox, VSCodium); terminals,
-- file managers etc. ignored it. Apps are told they're fullscreen, so Firefox
-- still enters its own fullscreen mode. The side bar and dock hide while a
-- window is fullscreen and come back when F11 is pressed again.
hl.bind("F11", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

-- Tell the dock/widgets (qs -c macos) when the left button is held, so edge
-- pop-outs and dock zoom stay quiet while a window is being dragged.
-- Non-consuming: clicks still reach apps. ignore_mods: covers SUPER+drag too.
-- hl.dsp.event emits "custom>>macdrag>>N" on the event socket (no process spawn).
--
-- The same press/release also keeps resized windows clear of the widgets: if a
-- floating window was resized past the usable area (side bar, dock, screen-edge
-- gaps), it slides back inside on release — so its edges never sit in the
-- side bar / dock / edge-panel zones.
local press = nil

-- Title-bar window menu: a single left click on a window's title bar — not a
-- drag, not a double-click (that zooms), not on the traffic lights — asks the
-- macos shell to show the window menu (WindowMenu.qml) at the pointer, via a
-- custom>>macwinmenu>>address,x,y,floating,pinned event. Whether it opens (or
-- needs a right click instead) is the shell's setting: macos.json windows.titlebarMenu.
local BAR_H, LIGHTS_W = mac_bar_height, 84
local bar_press = nil -- { addr, x, y } of a press on a title bar
local bar_timer = nil

local function bar_window_at(p)
    local active = hl.get_active_window()
    local wins = active and { active } or {}
    for _, w in ipairs(wins) do
        if w.visible ~= false and (w.fullscreen or 0) == 0
            and p.x >= w.at.x + LIGHTS_W and p.x <= w.at.x + w.size.x
            and p.y >= w.at.y - BAR_H and p.y < w.at.y then
            return w
        end
    end
    return nil
end

function mac_bar_press()
    if bar_timer then -- second click: a double-click, not a menu
        bar_timer:set_enabled(false)
        bar_timer = nil
        bar_press = nil
        return
    end
    local p = hl.get_cursor_pos()
    bar_press = p and { x = p.x, y = p.y } or nil
end

function mac_bar_release(button)
    local start = bar_press
    bar_press = nil
    local p = hl.get_cursor_pos()
    if not start or not p or math.abs(p.x - start.x) > 4 or math.abs(p.y - start.y) > 4 then return end
    local win = bar_window_at(p)
    if not win then return end
    local data = string.format("macwinmenu>>%s,%d,%d,%d,%d,%s", win.address, math.floor(p.x), math.floor(p.y),
        win.floating and 1 or 0, win.pinned and 1 or 0, button)
    if button == "right" then
        hl.dispatch(hl.dsp.event(data))
        return
    end
    -- wait out the double-click window first
    bar_timer = hl.timer(function()
        bar_timer = nil
        hl.dispatch(hl.dsp.event(data))
    end, { timeout = 280, type = "oneshot" })
end

-- The title-bar plugin consumes presses on its bar, so the mouse binds below never
-- see title-bar clicks; it announces them instead (custom>>macbarclick>>left|right|
-- double) and the macos shell calls this. A double-click (zoom) cancels a pending menu.
function mac_bar_click(button)
    if button == "double" then
        if bar_timer then
            bar_timer:set_enabled(false)
            bar_timer = nil
        end
        return
    end
    local p = hl.get_cursor_pos()
    bar_press = p and { x = p.x, y = p.y } or nil
    mac_bar_release(button)
end

-- Window menu actions (called by WindowMenu.qml through hyprctl eval)
-- the zoom preview's rect (title bar included: the bar sits SNAP_BAR px above the content)
local SNAP_BAR = mac_bar_height
function mac_snap_rect(win)
    local z = zoom_rect(win)
    return { x = z.x, y = z.y - SNAP_BAR, w = z.w, h = z.h + SNAP_BAR }
end

-- mac_snap(addr, "center"): the window menu's Center, at the default size
function mac_snap(addr, where)
    local win = hl.get_window("address:" .. addr)
    if where ~= "center" or not win or (win.fullscreen or 0) ~= 0 then return end
    if not win.floating then
        hl.dispatch(hl.dsp.window.float({ action = "on", window = win }))
    end
    local z = zoom_rect(win)
    local w, h = math.floor(z.w * 0.62), math.floor(z.h * 0.75)
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = win }))
    hl.dispatch(hl.dsp.window.move({ x = z.x + math.floor((z.w - w) / 2), y = z.y + math.floor((z.h - h) / 2), window = win }))
end

-- Top-edge zoom: drag a window by its title bar to the top edge → zoom. While such a drag is on,
-- a 50 ms timer watches the pointer (Lua has no pointer-motion event) and tells
-- the shell where the window would land (custom>>macsnap>>x,y,w,h | none) so it
-- can draw a preview (SnapPreview.qml). Applied just after release.
local BAR = mac_bar_height
local snapdrag = nil -- { addr, zone, timer }

-- The top zone: the very top edge, or the top bar except its left part over the
-- desktops, which opens the desktop picker instead. (It was only the bar's upper
-- half while split view existed; dragging up to the bar's lower edge then missed.)
local function snap_zone(p)
    local mon = hl.get_monitor_at(p.x, p.y)
    if not mon then return nil end
    local r = type(mon.reserved) == "table" and mon.reserved or {}
    local barH, barW = r.top or 0, r.left or 0
    if p.y <= mon.y + 3 then return "top" end
    if barH > 0 and p.y < mon.y + barH and p.x >= mon.x + barW + 320 then return "top" end
    return nil
end

-- Started/ended two ways: by the left-button binds below, and — for title-bar
-- drags, where the hyprbars plugin cancels the click so those binds never run —
-- by the macos shell when the plugin announces custom>>macdrag>>1 / >>0.
-- fromTitleBar: called by the macos shell when the hyprbars plugin announces a
-- drag (custom>>macdrag>>1). The plugin swallows title-bar presses, so the
-- press bind never ran for them (mac_mouse_down stays false). That call arrives
-- once the drag is already under way — the pointer may be far from where it
-- grabbed the bar, so its position can't identify the window. It doesn't need
-- to: a title-bar press focuses its window, so the dragged one is the active one.
-- (Matching by pointer position missed quick drags.)
function mac_snap_drag_start(fromTitleBar)
    if snapdrag then return end -- already tracking this drag
    if fromTitleBar and mac_mouse_down then return end -- a normal press: the bind handled it
    local p = hl.get_cursor_pos()
    if not p then return end
    local win = nil
    local function draggable(w)
        return w.floating and w.visible ~= false and (w.fullscreen or 0) == 0 and w.workspace and not w.workspace.special
    end
    local active = hl.get_active_window()
    if fromTitleBar and active and draggable(active) then
        win = active
    end
    local candidates = active and { active } or {}
    for _, w in ipairs(hl.get_windows()) do table.insert(candidates, w) end
    for _, w in ipairs(win and {} or candidates) do
        if draggable(w) and p.x >= w.at.x + 84 and p.x <= w.at.x + w.size.x and p.y >= w.at.y - BAR and p.y < w.at.y then
            win = w
            break
        end
    end
    if not win then
        -- a title-bar drag we couldn't match to a window gets no snapping:
        -- report it (custom>>macerr → the macos shell's log). Ordinary presses in a
        -- window or on the desktop land here too; those are expected, not reported.
        if fromTitleBar then
            hl.dispatch(hl.dsp.event(string.format("macerr>>drag start: no window for the title-bar drag at %d,%d (active: %s floating=%s fs=%s ws=%s)",
                math.floor(p.x), math.floor(p.y), active and active.class or "none", tostring(active and active.floating),
                tostring(active and active.fullscreen), tostring(active and active.workspace and active.workspace.name))))
        end
        return
    end
    snapdrag = { addr = win.address, zone = nil, picker = false, barTicks = 0, lastq = nil,
                 start = { x = p.x, y = p.y }, moving = false, ghostTicks = 0,
                 from = { x = win.at.x, y = win.at.y } }
    mac_drop_ws = nil
    snapdrag.timer = hl.timer(function()
        if not snapdrag then return end
        -- errors in timer callbacks are silent: report them (custom>>macerr>>…)
        local ok, err = pcall(mac_drag_tick)
        if not ok then hl.dispatch(hl.dsp.event("macerr>>drag tick: " .. tostring(err):gsub("\n", " "))) end
    end, { timeout = 20, type = "repeat" }) -- 50×/s while dragging: smooth previews
end

-- what the pointer is over while a window is dragged by its title bar:
--   the top edge → zoom (macsnap preview)
--   the left bar (Caelestia's desktops) → desktop picker: drop on a desktop to
--     move the window there and go with it (DesktopDropPicker.qml; it sets mac_drop_ws)
local function set_opacity(addr, v)
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = tostring(v), window = "address:" .. addr }))
end

-- close the picker: "cancel" (pointer left the column) or "drop" (released on a
-- desktop). The shell expands / shrinks its copy of the window first, so the real
-- window only reappears once that animation is done.
local function picker_close(d, how)
    if not d.picker then return end
    d.picker = false
    hl.dispatch(hl.dsp.event("macdeskdrag>>close," .. (how or "cancel")))
    local addr = d.addr
    d.ghostTicks = 15 -- keep reporting the pointer while the shell's copy expands back
    mac_opacity_timer = hl.timer(function()
        if snapdrag and snapdrag.picker and snapdrag.addr == addr then return end -- reopened meanwhile
        set_opacity(addr, 1)
    end, { timeout = 200, type = "oneshot" })
end

function mac_drag_tick()
    local d = snapdrag
    local q = hl.get_cursor_pos()
    local w = hl.get_window("address:" .. d.addr)
    if not q or not w then return end
    local mon = hl.get_monitor_at(q.x, q.y)
    local barW = (mon and type(mon.reserved) == "table" and mon.reserved.left) or 0
    local step = d.lastq and math.abs(q.x - d.lastq.x) + math.abs(q.y - d.lastq.y) or 0
    local moved = not d.lastq or step > 1
    d.lastq = { x = q.x, y = q.y }

    -- the first real movement (not just a click on the title bar): show the grab ripple
    if not d.moving and math.abs(q.x - d.start.x) + math.abs(q.y - d.start.y) > 6 then
        d.moving = true
        hl.dispatch(hl.dsp.event(string.format("macgrab>>%s,%d,%d", d.addr, math.floor(d.start.x), math.floor(d.start.y))))
        -- dragged off its zoomed spot: no longer zoomed (the green button zooms it afresh)
        if zoomed[w.address] then zoomed[w.address] = nil; announce_zoom() end
    end
    if d.ghostTicks > 0 then
        d.ghostTicks = d.ghostTicks - 1
        if moved then hl.dispatch(hl.dsp.event(string.format("macdeskdrag>>pos,%d,%d", math.floor(q.x), math.floor(q.y)))) end
    end

    -- desktop picker: opens after resting on the top bar's desktops (its left part, below
    -- the very top edge, which snaps to zoom), stays while over it or its cards
    local barH = (mon and type(mon.reserved) == "table" and mon.reserved.top) or 0
    local overBar = mon and barH > 0 and q.y > mon.y + 3 and q.y < mon.y + barH and q.x < mon.x + barW + 320
    if d.picker then
        -- the picker is a strip across the top (DesktopDropPicker.qml): it stays open
        -- while the pointer is over it, and closes once it goes below the strip
        if mon and q.y > mon.y + barH + 200 then -- left the strip: back to a normal drag
            picker_close(d, "cancel")
        elseif moved then
            hl.dispatch(hl.dsp.event(string.format("macdeskdrag>>pos,%d,%d", math.floor(q.x), math.floor(q.y))))
        end
        if d.picker then return end
    elseif overBar then
        d.barTicks = d.barTicks + 1
        if d.barTicks >= 5 then -- ~0.1 s on the bar
            d.picker = true
            if d.zone then d.zone = nil; hl.dispatch(hl.dsp.event("macsnap>>none")) end
            -- the real window hides; the shell shows a copy compacting into a thumbnail
            -- hidden a moment later, once the shell has captured it and covers it exactly
            local addr = d.addr
            mac_opacity_timer = hl.timer(function()
                if snapdrag and snapdrag.picker and snapdrag.addr == addr then set_opacity(addr, 0) end
            end, { timeout = 90, type = "oneshot" })
            -- position first: the shell anchors the window's copy to it on open
            hl.dispatch(hl.dsp.event(string.format("macdeskdrag>>pos,%d,%d", math.floor(q.x), math.floor(q.y))))
            hl.dispatch(hl.dsp.event(string.format("macdeskdrag>>open,%s,%d,%d,%d,%d", d.addr,
                math.floor(w.at.x), math.floor(w.at.y - BAR), math.floor(w.size.x), math.floor(w.size.y + BAR))))
            return
        end
    else
        d.barTicks = 0
    end

    -- top-edge zoom
    local zone = snap_zone(q)
    if zone ~= d.zone then
        d.zone = zone
        if zone then
            local r = mac_snap_rect(w)
            hl.dispatch(hl.dsp.event(string.format("macsnap>>%d,%d,%d,%d", math.floor(r.x), math.floor(r.y), math.floor(r.w), math.floor(r.h))))
        else
            hl.dispatch(hl.dsp.event("macsnap>>none"))
        end
    end
end

function mac_snap_drag_end()
    if not snapdrag then
        -- a title-bar drag whose start couldn't be matched to a window (its press focused
        -- it, so it's the active one): still pull it back inside the usable area
        mac_drop_timer = hl.timer(function()
            mac_clamp(hl.get_active_window())
        end, { timeout = 90, type = "oneshot" })
        return
    end
    local d = snapdrag
    snapdrag = nil
    d.timer:set_enabled(false)

    if d.picker then
        local ws = mac_drop_ws
        picker_close(d, ws and "drop" or "cancel")
        mac_drop_ws = nil
        local w = hl.get_window("address:" .. d.addr)
        if ws and w then
            -- go along with it (a plain move follows), and keep it focused there
            hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws), window = w }))
            hl.dispatch(hl.dsp.focus({ window = w }))
        end
        -- dropped on a desktop: it lands where it was before the drag (not where it
        -- was let go, up by the bar); either way kept inside the usable area
        mac_clamp_timer = hl.timer(function()
            local win = hl.get_window("address:" .. d.addr)
            if ws and win and win.floating and (win.fullscreen or 0) == 0 then
                hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = win }))
                hl.dispatch(hl.dsp.window.move({ x = d.from.x, y = d.from.y, window = win }))
                hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = win }))
                win = hl.get_window("address:" .. d.addr)
            end
            mac_clamp(win)
        end, { timeout = 90, type = "oneshot" })
        return
    end

    -- let go on the top edge before a 20 ms tick saw it there (a quick flick up): still zoom
    local q = hl.get_cursor_pos()
    if not d.zone and q then d.zone = snap_zone(q) end
    if not d.zone then
        -- a plain move: keep it inside the usable area (title-bar drags never
        -- reach the release bind that does this for other drags)
        -- own timer variable: the release bind reuses mac_clamp_timer, which would drop this one
        mac_drop_timer = hl.timer(function()
            mac_clamp(hl.get_window("address:" .. d.addr))
        end, { timeout = 90, type = "oneshot" })
        return
    end
    hl.dispatch(hl.dsp.event("macsnap>>none"))
    -- once Hyprland has finished its own drag (kept referenced so it isn't collected)
    mac_snap_apply_timer = hl.timer(function()
        local w = hl.get_window("address:" .. d.addr)
        if not w then return end
        hl.dispatch(hl.dsp.focus({ window = w }))
        mac_zoom()
    end, { timeout = 80, type = "oneshot" })
end

function mac_clamp(win)
    if not win or not win.floating or (win.fullscreen or 0) ~= 0 then return end
    -- never move a window that isn't laid out yet: that aborts Hyprland (2026-10-10)
    if win.mapped == false or win.hidden then return end
    local z = zoom_rect(win)
    local w = math.min(win.size.x, z.w)
    local h = math.min(win.size.y, z.h)
    local x = math.max(z.x, math.min(win.at.x, z.x + z.w - w))
    local y = math.max(z.y, math.min(win.at.y, z.y + z.h - h))
    if w == win.size.x and h == win.size.y and x == win.at.x and y == win.at.y then return end
    -- glides back inside with the normal window motion (windowsMove, the macOS curve —
    -- the same as a zoom from the top edge); the instant jump looked like a snap
    if w ~= win.size.x or h ~= win.size.y then
        hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = win }))
    end
    if x ~= win.at.x or y ~= win.at.y then
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = win }))
    end
end

function mac_clamp_active()
    mac_clamp(hl.get_active_window())
end

-- errors inside bind callbacks vanish silently; report them as custom>>macerr>>…
-- events instead (visible with: socat - UNIX:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock)
local function guarded(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then hl.dispatch(hl.dsp.event("macerr>>" .. name .. ": " .. tostring(err):gsub("\n", " "))) end
    end
end

hl.bind("mouse:272", guarded("press", function()
    mac_super_tap = false -- SUPER+click (e.g. SUPER+drag) isn't a launcher tap
    hl.dispatch(hl.dsp.event("macdrag>>1"))
    local win = hl.get_active_window()
    press = win and { addr = win.address, w = win.size.x, h = win.size.y } or nil
    mac_mouse_down = true
    mac_bar_press()
    mac_snap_drag_start()
end), { non_consuming = true, ignore_mods = true })

hl.bind("mouse:272", guarded("release", function()
    hl.dispatch(hl.dsp.event("macdrag>>0"))
    -- keep the window inside the usable area after any drag (move, resize or
    -- SUPER+drag): let go past the screen edge, the side bar or the dock and it
    -- slides back in. A moment later, once Hyprland has finished its own drag.
    -- (A window that's already inside is left alone; kept referenced so the timer
    -- isn't garbage-collected.)
    local win = hl.get_active_window()
    if win and win.floating then
        local addr = win.address
        mac_clamp_timer = hl.timer(function()
            mac_clamp(hl.get_window("address:" .. addr))
            mac_zoom_prune() -- a border or Super+drag resize of a zoomed window
        end, { timeout = 90, type = "oneshot" })
    end
    press = nil
    mac_mouse_down = false
    mac_bar_release("left")
    mac_snap_drag_end()
end), { non_consuming = true, ignore_mods = true, release = true })

-- right-click on a title bar: the window menu straight away
hl.bind("mouse:273", function() mac_bar_press() end, { non_consuming = true })
hl.bind("mouse:273", function() mac_bar_release("right") end, { non_consuming = true, release = true })

-- SUPER+Tab / SUPER+Shift+Tab: next / previous desktop (workspace), looping
-- through the ones in use. (Alt+Tab still switches between windows.)
-- SUPER+Tab desktop switcher, like Alt+Tab but for desktops (workspaces).
-- A quick SUPER+Tab jumps back to the desktop you were on before (toggle between
-- two with one press each way). Holding SUPER shows every desktop in use, most
-- recent first, plus a "New Desktop" card (DesktopSwitcher.qml); Tab / Shift+Tab
-- move, releasing SUPER goes there, Esc cancels. A pill confirms where you are.
local desk_mru = {} -- workspace ids, most recently visited first

local function desk_touch(id)
    for i = #desk_mru, 1, -1 do
        if desk_mru[i] == id then table.remove(desk_mru, i) end
    end
    table.insert(desk_mru, 1, id)
end

do
    local cur = hl.get_active_workspace()
    if cur and not cur.special then desk_touch(cur.id) end
end

hl.on("workspace.active", function()
    local ws = hl.get_active_workspace()
    if ws and not ws.special and ws.id > 0 then desk_touch(ws.id) end
end)

-- An open special desktop (Equibop on special:communication…) overlays every desktop, so its
-- window seemed to follow you: close it when that display's normal desktop changes (Super+1-9,
-- swipes, Super+Tab…). Keyed per display, so moving between displays closes nothing.
local desk_by_mon = {} -- monitor name -> regular desktop id
hl.on("workspace.active", function()
    local mon = hl.get_active_monitor()
    local ws = mon and mon.active_workspace
    if not ws then return end
    local prev = desk_by_mon[mon.name]
    desk_by_mon[mon.name] = ws.id
    local special = mon.active_special_workspace
    if prev and prev ~= ws.id and special and special.name and special.name ~= "" then
        hl.dispatch(hl.dsp.workspace.toggle_special((special.name:gsub("^special:", ""))))
    end
end)

local deskswitch = nil -- { list = { ids }, idx }
local SUPER_KEYS = { [133] = true, [134] = true }

local function desk_windows(id)
    local classes = {}
    for _, w in ipairs(hl.get_windows()) do
        if w.workspace and w.workspace.id == id and #classes < 6 then table.insert(classes, w.class or "") end
    end
    return classes
end

local function deskswitch_show()
    local parts = {}
    for _, id in ipairs(deskswitch.list) do
        table.insert(parts, id .. ":" .. table.concat(desk_windows(id), ","))
    end
    hl.dispatch(hl.dsp.event("macdesks>>show|" .. deskswitch.idx .. "|" .. table.concat(parts, ";")))
end

function mac_desktop(dir)
    if not deskswitch then
        local cur = hl.get_active_workspace()
        if not cur then return end
        local used, list, seen = {}, {}, {}
        for _, ws in ipairs(hl.get_workspaces()) do
            if not ws.special and ws.id > 0 and (ws.windows or 0) > 0 then used[ws.id] = true end
        end
        used[cur.id] = true
        -- most recent first, then any used desktop never visited (by number)
        for _, id in ipairs(desk_mru) do
            if used[id] and not seen[id] then table.insert(list, id); seen[id] = true end
        end
        local rest = {}
        for id in pairs(used) do if not seen[id] then table.insert(rest, id) end end
        table.sort(rest)
        for _, id in ipairs(rest) do table.insert(list, id) end
        -- the current desktop leads (MRU), then a fresh empty desktop at the end
        local free = 1
        while used[free] do free = free + 1 end
        table.insert(list, free)
        deskswitch = { list = list, idx = 1 }
        hl.bind("SUPER + Escape", function() mac_desktop_end(false) end) -- swallowed while open (see mac_switch)
    end
    local n = #deskswitch.list
    deskswitch.idx = ((deskswitch.idx - 1 + dir) % n) + 1
    deskswitch_show()
end

function mac_desktop_end(commit)
    if not deskswitch then return end
    local target = deskswitch.list[deskswitch.idx]
    local list = deskswitch.list
    deskswitch = nil
    hl.unbind("SUPER + Escape")
    hl.dispatch(hl.dsp.event("macdesks>>hide"))
    local cur = hl.get_active_workspace()
    if not commit or not target or (cur and cur.id == target) then return end
    hl.dispatch(hl.dsp.focus({ workspace = tostring(target) }))
    -- pill: the used desktops in number order, plus the one we land on
    local shown, seen = {}, {}
    for _, id in ipairs(list) do
        local ws = hl.get_workspace(tostring(id))
        if (id == target or (ws and (ws.windows or 0) > 0)) and not seen[id] then
            table.insert(shown, id); seen[id] = true
        end
    end
    table.sort(shown)
    hl.dispatch(hl.dsp.event("macdesk>>" .. target .. "|" .. table.concat(shown, ",")))
end

hl.on("input.keyboard.key", function(keycode, _, state)
    if not deskswitch then return end
    if state == 0 and SUPER_KEYS[keycode] then
        mac_desktop_end(true)
    end -- Esc: the SUPER + Escape bind (mac_desktop), which swallows it
end)

hl.bind("SUPER + Tab", function() mac_desktop(1) end, { repeating = true })
hl.bind("SUPER + SHIFT + Tab", function() mac_desktop(-1) end, { repeating = true })

-- Tap SUPER on its own → toggle the Apps launcher (same one as the dock).
-- Pressing SUPER arms it; any other key or a click while it's held cancels it,
-- so SUPER+Q, SUPER+T, SUPER+drag etc. never open the launcher.
mac_super_tap = false
local SUPER_KEYCODES = { [133] = true, [134] = true } -- Super_L, Super_R (xkb)

hl.on("input.keyboard.key", function(keycode, _, state)
    if state ~= 1 then return end -- presses only
    mac_super_tap = SUPER_KEYCODES[keycode] == true
end)

for _, key in ipairs({ "SUPER + Super_L", "SUPER + Super_R" }) do
    hl.bind(key, function()
        if mac_super_tap then
            hl.dispatch(hl.dsp.exec_cmd("qs -c macos ipc call launcher toggle"))
        end
        mac_super_tap = false
    end, { release = true })
end

------------------
---- MONITORS ----
------------------

-- Any external monitor: highest refresh rate, placed to the right of the laptop.
-- (eDP-1 keeps its own rule from HyprMod in hyprland-gui.lua.)
hl.monitor({ output = "", mode = "highrr", position = "auto-right", scale = 1 })
hl.monitor({ output = laptop, mode = laptop_mode, position = "auto", scale = laptop_scale })

local function external_count()
    local n = 0
    for _, m in ipairs(hl.get_monitors()) do
        if m.name ~= laptop then n = n + 1 end
    end
    return n
end

-- HyprMod (hyprland-gui.lua, loaded after this file) saves "eDP-1 disabled" for use
-- with the external monitor. Re-applied on a reload with no external monitor (every
-- wallpaper change reloads the config) it switched off the only screen: blank screen,
-- then monitor.removed turned it back on and every window/panel was rebuilt.
-- So that rule only applies while an external monitor is connected.
hl._monitor_raw = hl._monitor_raw or hl.monitor -- config state survives reloads: wrap once

-- Desktop Settings → Displays saves per-monitor choices in hypr-displays.lua. They're
-- applied here, over every other rule for that monitor (HyprMod's loads later), except
-- that turning the laptop panel back on (lid opened, last external unplugged) always wins.
local DISPLAYS_FILE = os.getenv("HOME") .. "/.config/caelestia/hypr-displays.lua"
do
    local ok, t = pcall(dofile, DISPLAYS_FILE)
    mac_displays = ok and type(t) == "table" and t or {}
end

local function with_saved(spec)
    local saved = mac_displays[spec.output or ""]
    if not saved then return spec end
    local out = {}
    for k, v in pairs(spec) do out[k] = v end
    for k, v in pairs(saved) do
        if not (k == "disabled" and spec.disabled == false) then out[k] = v end
    end
    return out
end

hl.monitor = function(spec)
    spec = with_saved(spec)
    if spec.output == laptop and spec.disabled and external_count() == 0 then return end
    return hl._monitor_raw(spec)
end

-- Desktop Settings: try a change live (it asks to keep it, else reverts) …
function mac_display_set(name, mode, scale, position, disabled)
    -- never switch off the last screen
    if disabled and #hl.get_monitors() <= 1 then return end
    hl._monitor_raw({ output = name, mode = mode, scale = scale, position = position, disabled = disabled })
end

-- … and keep it
function mac_display_save(name, mode, scale, position, disabled)
    mac_displays[name] = { mode = mode, scale = scale, position = position, disabled = disabled or nil }
    local f = io.open(DISPLAYS_FILE .. ".tmp", "w") -- renamed into place: a cut-off write can't lose the file
    if not f then return end
    f:write("-- written by Desktop Settings → Displays; applied by hypr-qol.lua\nreturn {\n")
    for n, d in pairs(mac_displays) do
        f:write(string.format("    [%q] = { mode = %q, scale = %s, position = %q%s },\n",
            n, tostring(d.mode), tostring(d.scale), tostring(d.position), d.disabled and ", disabled = true" or ""))
    end
    f:write("}\n")
    f:close()
    os.rename(DISPLAYS_FILE .. ".tmp", DISPLAYS_FILE)
end

-- saved choices for monitors that no other rule names (an external one, by its port)
for name, _ in pairs(mac_displays) do hl.monitor({ output = name }) end

local function laptop_on()
    hl.monitor({ output = laptop, disabled = false, mode = laptop_mode, position = "auto", scale = laptop_scale })
end

-- Clamshell: closing the lid with an external monitor turns the panel off
-- (windows move to the external screen); opening it brings the panel back.
-- Without an external monitor the lid is left to logind (suspend).
hl.bind("switch:on:Lid Switch", function()
    if external_count() > 0 then
        hl.monitor({ output = laptop, disabled = true })
    end
end, { locked = true })

hl.bind("switch:off:Lid Switch", laptop_on, { locked = true })

-- Unplugging the last external monitor while the lid is closed would leave
-- no screen at all; always fall back to the laptop panel.
hl.on("monitor.removed", function()
    if external_count() == 0 then laptop_on() end
end)

-- After any monitor change (plugging the laptop in/out, lid, layout): floating
-- windows can be left at coordinates no screen shows anymore (the install terminal
-- ended up at x = -1541), and Caelestia has exited. So a moment later, pull
-- off-screen floating windows back into view and restart any shell that died.
function mac_rescue_windows()
    for _, win in ipairs(hl.get_windows()) do
        local mon = win.monitor
        if win.floating and mon and type(mon.width) == "number" then
            local scale = mon.scale or 1
            local cx, cy = win.at.x + win.size.x / 2, win.at.y + win.size.y / 2
            local inside = cx >= mon.x and cx <= mon.x + mon.width / scale
                and cy >= mon.y and cy <= mon.y + mon.height / scale
            if not inside then mac_clamp(win) end
        end
    end
end

for _, ev in ipairs({ "monitor.added", "monitor.removed", "monitor.layout_changed" }) do
    hl.on(ev, function()
        hl.dispatch(hl.dsp.exec_cmd("sleep 1.5 && hyprctl eval 'mac_rescue_windows()'; rice-ensure-shells"))
    end)
end

hl.config({
    -- Sharp XWayland apps on scaled monitors (Hyprland scales them itself)
    xwayland = { force_zero_scaling = true },
    -- Never warp the cursor when focus changes (Alt+Tab, dock clicks…). It used
    -- to jump to the centre of every newly focused window. (no_warps = true is
    -- "no warping"; this was mistakenly false.)
    cursor = { no_warps = true, hide_on_key_press = true },
})

----------------
---- GAMING ----
----------------

hl.config({
    -- Lets the existing "game" window tag (rules.lua: immediate = true) actually tear,
    -- removing a frame of input latency in fullscreen games
    general = { allow_tearing = true },
    -- Variable refresh only for fullscreen apps (avoids desktop flicker)
    misc = { vrr = 2 },
    -- Direct scanout for fullscreen games: skip compositing entirely
    render = { direct_scanout = 2 },
})

-- Smoother animations: lets Hyprland buffer one extra frame when a client
-- (Caelestia's panels, the dock/launcher) delivers a frame slightly late,
-- instead of halving that client's frame rate. Measured on the 100 Hz monitor:
-- Caelestia's dashboard animation 51 → 84 FPS.
hl.config({ render = { new_render_scheduling = true } })

-- Game mode toggle (SUPER + F1): drops blur, shadows, animations and gaps
-- for maximum FPS on the iGPU; press again to restore.
local vars = require("variables")
local game_mode = false
local auto_blur_off = false -- blur dropped because a game is focused (below)
local game_blur -- defined below

-- also from Desktop Settings (Settings.qml); custom>>macgame>>1|0 tells the shell
function mac_game_mode_toggle()
    game_mode = not game_mode
    auto_blur_off = false
    hl.dispatch(hl.dsp.event("macgame>>" .. (game_mode and "1" or "0")))
    if game_mode then
        hl.config({
            animations = { enabled = false },
            decoration = { blur = { enabled = false }, shadow = { enabled = false }, rounding = 0 },
            general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
        })
        -- Also tells the docks (and GTK apps) to use reduced motion
        hl.dispatch(hl.dsp.exec_cmd("gsettings set org.gnome.desktop.interface enable-animations false"))
        hl.dispatch(hl.dsp.exec_cmd("notify-send -a Hyprland -i input-gaming 'Game mode on' 'Effects off for maximum performance'"))
    else
        hl.config({
            animations = { enabled = true },
            decoration = {
                blur = { enabled = vars.blurEnabled },
                shadow = { enabled = vars.shadowEnabled },
                rounding = vars.windowRounding,
            },
            general = { gaps_in = vars.windowGapsIn, gaps_out = vars.windowGapsOut, border_size = vars.windowBorderSize },
        })
        hl.dispatch(hl.dsp.exec_cmd("gsettings set org.gnome.desktop.interface enable-animations true"))
        hl.dispatch(hl.dsp.exec_cmd("notify-send -a Hyprland -i input-gaming 'Game mode off' 'Effects restored'"))
        game_blur(hl.get_active_window()) -- a game still focused keeps blur off
    end
end

mac_bind(kb.kbGameMode, function() mac_game_mode_toggle() end)
hl.dispatch(hl.dsp.event("macgame>>0")) -- a reload restores every effect

-- Games are GPU-bound on the iGPU: while one is focused, blur is off, so the bar, dock and
-- widgets over a windowed game aren't re-blurred on every game frame. Comes back on switching away.
local GAME_CLASSES = { "^org%.vinegarhq%.Sober$", "^steam_app_", "^gamescope$" }
game_blur = function(win) -- the local declared above
    if game_mode then return end
    local cls = win and win.class or ""
    local is_game = false
    for _, p in ipairs(GAME_CLASSES) do
        if cls:match(p) then is_game = true break end
    end
    if is_game ~= auto_blur_off then
        auto_blur_off = is_game
        hl.config({ decoration = { blur = { enabled = (not is_game) and vars.blurEnabled } } })
    end
end
hl.on("window.active", game_blur)
game_blur(hl.get_active_window()) -- a reload while a game is focused

-- A minimised game (yellow button, dock, Alt+Tab away from fullscreen) keeps simulating
-- and rendering at full speed: Sober measured ~146 % CPU hidden vs ~148 % focused. While it
-- sits on special:minimized its systemd scope is capped at 40 % (its FIFO render thread is
-- exempt, total ~60 %). Throttled, never stopped, so it stays connected to the server.
mac_game_throttled = {} -- pid -> true; a reload starts a fresh Lua state, the loop below re-syncs
function mac_game_throttle(win, closing)
    if not (win and win.pid and (win.class or ""):match("^org%.vinegarhq%.Sober$")) then return end
    local hide = not closing and win.workspace ~= nil and win.workspace.name == "special:minimized"
    if (mac_game_throttled[win.pid] or false) == hide then return end
    mac_game_throttled[win.pid] = hide or nil
    hl.dispatch(hl.dsp.exec_cmd(string.format(
        "s=$(basename \"$(cut -d: -f3 /proc/%d/cgroup)\"); case $s in app-flatpak-org.vinegarhq.Sober-*.scope) systemctl --user set-property --runtime \"$s\" CPUQuota=%s;; esac",
        win.pid, hide and "40%" or "")))
end
hl.on("window.move_to_workspace", function(w) mac_game_throttle(w) end)
-- closed while minimised (Sober returning to its app window, or quitting): lift the cap
hl.on("window.close", function(w) mac_game_throttle(w, true) end)
for _, w in ipairs(hl.get_windows()) do mac_game_throttle(w) end

-- A focused fullscreen game keeps the pointer on its screen: with a free c‍ursor (Roblox menus,
-- third-person camera) it slid onto the other display, where a click lost the game its focus.
-- Only while the game is (or just was) the active window, so keyboard switches still leave it.
local function is_game(win)
    for _, p in ipairs(GAME_CLASSES) do
        if win and (win.class or ""):match(p) then return true end
    end
    return false
end
mac_active_now, mac_active_prev = nil, nil -- addresses; monitor.focused may fire before or after window.active
hl.on("window.active", function(win)
    mac_active_prev, mac_active_now = mac_active_now, win and win.address
end)
hl.on("monitor.focused", function()
    local p = hl.get_cursor_pos()
    local here = p and hl.get_monitor_at(p.x, p.y)
    if not here then return end
    for _, m in ipairs(hl.get_monitors()) do
        local ws = m.active_workspace
        local fw = m.id ~= here.id and ws and ws.has_fullscreen and ws.fullscreen_window
        if fw and is_game(fw) and (fw.address == mac_active_now or fw.address == mac_active_prev) then
            local s = m.scale or 1
            hl.dispatch(hl.dsp.cursor.move({
                x = math.max(m.x + 1, math.min(m.x + m.width / s - 2, p.x)),
                y = math.max(m.y + 1, math.min(m.y + m.height / s - 2, p.y)),
            }))
            hl.dispatch(hl.dsp.focus({ window = fw }))
            return
        end
    end
end)

-----------------------
---- VIDEO EDITING ----
-----------------------

-- Intel VA-API driver for hardware decode/encode (Firefox, mpv, OBS, Kdenlive)
hl.env("LIBVA_DRIVER_NAME", "iHD")

hl.config({
    -- Tell the compositor when content is video/game (better scheduling, VRR, scanout)
    render = { send_content_type = true },
    -- Launching mpv/imv from foot replaces the terminal instead of stacking a window
    misc = { enable_swallow = true, swallow_regex = "^(foot)$" },
})

-- Don't dim, lock or sleep while an editor/recorder is focused (long renders,
-- timeline playback) or while any video plays fullscreen.
hl.window_rule({ match = { class = "resolve|kdenlive|shotcut|com.obsproject.Studio|obs" }, idle_inhibit = "focus" })
hl.window_rule({ match = { class = "mpv|vlc|celluloid" }, idle_inhibit = "fullscreen" })
hl.window_rule({ match = { class = "firefox|chromium|brave-browser" }, idle_inhibit = "fullscreen" })

-- Render/export progress dialogs float instead of tiling over the timeline
hl.window_rule({ match = { class = "kdenlive|resolve|shotcut", title = ".*([Rr]ender|[Ee]xport).*" }, float = true, center = true })

-- Resolve's start-up splash and its right-click menus are one reused X11 window titled just
-- "resolve" (the main window and dialogs have real titles). Undecorated, and left where Resolve
-- puts it: mac-float-default centred it (menus opened mid-screen, not at the click), and the
-- "opaque" tag + rounding + shadow drew the splash's transparent shadow margin as a grey box.
hl.window_rule({
    name     = "mac-resolve-popups",
    match    = { class = "^resolve$", title = "^resolve$", xwayland = true },
    center   = false,
    opaque   = false,
    no_shadow = true,
    no_blur  = true,
    rounding = 0,
    border_size = 0,
    ["hyprbars:no_bar"] = true,
})

-- Max fps for Roblox (Sober, Vulkan): tear instead of waiting for vsync when fullscreen (allow_tearing
-- is on above), like Caelestia's "game" tag does for Steam games; and never dim or idle it.
mac_sober_rule = hl.window_rule({
    name = "mac-sober-maxfps",
    match = { class = "^org\\.vinegarhq\\.Sober$" },
    immediate = true,
    idle_inhibit = "fullscreen",
})
