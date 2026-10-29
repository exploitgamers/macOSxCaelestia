-- Window size memory, like macOS: an app reopens at the size and place you last
-- left it in. When an app's last window closes, its floating geometry is saved
-- (~/.local/state/macos-window-geometry.lua) and turned into a window rule for
-- that app, so the next window is *created* there (no open-then-jump).
--
-- Only the last window of an app counts: closing a dialog or a second window
-- while the main one is still open doesn't overwrite what was saved, and a window
-- titled otherwise than the saved one replaces it only if it is bigger (see window.close).
-- The saved size goes only to the app's main windows, never to its dialogs and
-- pop-ups (Resolve's pickers opened at 1528×815): see apply_rule.
-- Tiled / fullscreen windows and games aren't remembered.
-- Forget everything: delete the state file and `hyprctl reload`.

local path = os.getenv("HOME") .. "/.local/state/macos-window-geometry.lua"

local function load()
    local ok, t = pcall(dofile, path)
    return ok and type(t) == "table" and t or {}
end

mac_geometry = mac_geometry or load()
local rules = {}

local function save()
    local f = io.open(path .. ".tmp", "w")
    if not f then return end
    f:write("-- written by hypr-window-memory.lua\nreturn {\n")
    for class, g in pairs(mac_geometry) do
        local screen = g.mw and string.format(", mx = %d, my = %d, mw = %d, mh = %d", g.mx, g.my, g.mw, g.mh) or ""
        local title = g.title and string.format(", title = %q", g.title) or ""
        f:write(string.format("    [%q] = { w = %d, h = %d, x = %d, y = %d%s%s },\n", class, g.w, g.h, g.x, g.y, screen, title))
    end
    f:write("}\n")
    f:close()
    os.rename(path .. ".tmp", path)
end

-- Where a saved window goes on `mon`. The screen it was saved on is kept with it
-- (mx, my, mw, mh: that monitor's logical origin and size): on a screen of another
-- size it takes the same relative spot, by its centre — a window centred on the
-- laptop opens centred on the monitor, not up in its top-left.
local function place(g, mon)
    if not (g.mw and mon and mon.width) then return g.x, g.y end
    local s = mon.scale or 1
    local W, H = mon.width / s, mon.height / s
    if math.abs(W - g.mw) < 2 and math.abs(H - g.mh) < 2 then
        return mon.x + (g.x - g.mx), mon.y + (g.y - g.my)
    end
    local cx = (g.x - g.mx + g.w / 2) / g.mw
    local cy = (g.y - g.my + g.h / 2) / g.mh
    return math.floor(mon.x + cx * W - g.w / 2), math.floor(mon.y + cy * H - g.h / 2)
end

local function escape(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?|{}\\]", "\\%0"))
end

-- rules for one app; replace the previous ones (later rules win, so they also
-- beat the default 62% × 70% centred size and Caelestia's per-app rules).
-- They give the saved size only to the app's main windows; its dialogs, menus and
-- pickers keep their own: (1) class + float = false, i.e. the app's normal top-level
-- windows (`float` is Hyprland's own guess, made before rules apply: dialogs, menus,
-- transient/child and fixed-size windows already float), and (2) class + the saved
-- window's initial_title, for a main window Hyprland guesses floating. Not by title
-- alone: many apps put the document or folder in it ("@@USER@@ - Thunar"), so their
-- next window, titled otherwise, lost its size.
local function apply_rule(class)
    local g = mac_geometry[class]
    for _, r in ipairs(rules[class] or {}) do
        r:set_enabled(false)
    end
    rules[class] = nil
    if not g then return end
    local mon = hl.get_active_monitor()
    local x, y = place(g, mon)
    -- a rule's move is relative to the monitor the window opens on (Hyprland adds its origin) but
    -- place() is absolute: on HDMI (x 1536) a window that opened fullscreen (Sober) skipped the fix-up
    -- in window.open and came back from fullscreen 1536 px too far right
    if g.mw and mon and mon.width then x, y = x - mon.x, y - mon.y end
    local matches = { { class = "^" .. escape(class) .. "$", float = false, modal = false } }
    if g.title and g.title ~= "" then
        matches[2] = { class = "^" .. escape(class) .. "$", initial_title = "^" .. escape(g.title) .. "$" }
    end
    rules[class] = {}
    for i, match in ipairs(matches) do
        rules[class][i] = hl.window_rule({
            name   = "mac-memory-" .. i .. "-" .. class,
            match  = match,
            size   = g.w .. " " .. g.h,
            move   = x .. " " .. y,
            center = false,
        })
    end
end

-- whether a saved entry belongs to this window: one of the rules above sized it
-- (same size), or it has the saved title (old entries have no title)
local function owns(g, win)
    return g and (not g.title or g.title == win.initial_title
        or (math.abs(win.size.x - g.w) <= 2 and math.abs(win.size.y - g.h) <= 2))
end

-- windows that opened while another window of their app was already open (a dialog,
-- a pop-up, a second window), by address: they don't replace a saved main window
mac_memory_secondary = mac_memory_secondary or {}

-- create the saved rules once the whole config has loaded: rules made later win,
-- and Caelestia's rules.lua (incl. "centre every floating window") loads after this file
-- (kept referenced: an unreferenced timer can be garbage-collected before it fires)
mac_memory_timer = hl.timer(function()
    for class in pairs(mac_geometry) do
        apply_rule(class)
    end
end, { timeout = 50, type = "oneshot" })

local function skip(class)
    return class == "" or class:match("^steam_app_") or class == "gamescope"
end

hl.on("window.close", function(win)
    if not win then return end
    local secondary = mac_memory_secondary[win.address]
    mac_memory_secondary[win.address] = nil
    if not win.class or skip(win.class) then return end
    if not win.floating or (win.fullscreen or 0) ~= 0 then return end
    if win.workspace and win.workspace.name == "special:minimized" then return end
    -- another window of this app still open (a dialog, a second window)? keep the main one's
    for _, other in ipairs(hl.get_windows()) do
        if other.address ~= win.address and other.class == win.class then return end
    end
    -- a dialog closed last (its main window already gone) doesn't replace the main window's
    -- entry. Only when that entry is known: an app whose first window was a splash screen
    -- opens its main window as "secondary", and it must still be saved the first time
    -- (and over entries saved before titles were kept)
    -- Nor does a utility window that is the app's last one (Resolve's Project Manager, a
    -- welcome or settings window): a window titled otherwise than the saved entry replaces
    -- it only when it is strictly larger (area). Same title (or none saved) always saves, so
    -- shrinking the main window is remembered. Limit: an app whose main-window title names the
    -- document ("Downloads - Thunar") keeps the old size until that window is larger.
    local old = mac_geometry[win.class]
    if old and old.title and old.title ~= win.initial_title
        and (secondary or win.size.x * win.size.y <= old.w * old.h) then return end
    local g = { w = math.floor(win.size.x), h = math.floor(win.size.y), x = math.floor(win.at.x), y = math.floor(win.at.y),
        title = win.initial_title }
    if g.w < 120 or g.h < 80 then return end
    local mon = win.monitor
    if mon and type(mon.width) == "number" then
        local s = mon.scale or 1
        g.mx, g.my, g.mw, g.mh = mon.x, mon.y, math.floor(mon.width / s), math.floor(mon.height / s)
    end
    mac_geometry[win.class] = g
    save()
    apply_rule(win.class)
end)

-- The rule sets the size; the position is applied here too, because the "centre
-- floating windows" rules can still win over the rule's move. Must be window.open:
-- in window.open_early the window isn't in the layout yet, and moving it there
-- aborts Hyprland (Layout::CSpace::moveTarget — crashed twice opening Resolve).
-- Only an app's first window goes back to the saved spot; mac_clamp keeps it on screen.
-- Cascade (macOS): a window that would open exactly on top of another one on its
-- desktop (a second window of the app, or two apps at the default size) opens
-- 24 px further down and right, so it never hides the first one completely.
local function covered(win, x, y)
    local ws = win.workspace and win.workspace.id
    for _, o in ipairs(hl.get_windows()) do
        if o.address ~= win.address and o.workspace and o.workspace.id == ws
            and math.abs(o.at.x - x) <= 2 and math.abs(o.at.y - y) <= 2 then
            return true
        end
    end
    return false
end

hl.on("window.open", function(win)
    if not win then return end
    local first = true
    for _, other in ipairs(hl.get_windows()) do
        if other.address ~= win.address and other.class == win.class then first = false break end
    end
    if not first then mac_memory_secondary[win.address] = true end
    if not win.floating or win.mapped == false or (win.fullscreen or 0) ~= 0 then return end
    local g = first and win.class and mac_geometry[win.class]
    if not owns(g, win) then g = nil end
    local x, y = win.at.x, win.at.y
    if g then x, y = place(g, win.monitor or hl.get_active_monitor())
    elseif mac_recentre_spot then
        local cx, cy = mac_recentre_spot(win) -- centred by the rule: centre it with its title bar
        if cx then x, y = cx, cy end
    end
    local cascaded = false
    for _ = 1, 12 do
        if not covered(win, x, y) then break end
        x, y, cascaded = x + 24, y + 24, true
    end
    if math.abs(win.at.x - x) > 2 or math.abs(win.at.y - y) > 2 then
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = win }))
    end
    if (g or cascaded) and mac_clamp then mac_clamp(win) end
end)
