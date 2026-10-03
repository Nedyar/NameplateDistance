-- Nameplate Distance: shows how far away each unit is on its nameplate.
-- Core.lua holds the settings, the shared helpers, the startup and the slash
-- commands.
local ADDON_NAME, ns = ...

ns.MAX_COLORS = 12

-- WoW Forever runs the Midnight addon API, where some results are "secret":
-- using one in a condition, or even comparing it with nil, raises an error.
-- Anything that might be secret goes through Plain() before it is looked at.
local issecretvalue = issecretvalue or function() return false end

function ns.Plain(value)
    if issecretvalue(value) then
        return nil
    end
    return value
end

function ns.Print(message, ...)
    if select("#", ...) > 0 then
        message = message:format(...)
    end
    print("|cff33ccffNameplate Distance|r: " .. message)
end

-- RegisterEvent raises for an event this client does not have, which would
-- abort the rest of the file, so every registration is wrapped.
function ns.RegisterEvents(frame, ...)
    for i = 1, select("#", ...) do
        pcall(frame.RegisterEvent, frame, (select(i, ...)))
    end
end

-- A distance with the client's unit: "20-25 yd", "20-25 m", "20-25码".
function ns.Yards(text)
    return ns.L["%s yd"]:format(text)
end

function ns.ColorToHex(color)
    return ("%02X%02X%02X"):format(math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
end

-- Settings -----------------------------------------------------------------

-- The colors the rows are built from (see Colors.lua).
ns.PALETTE = {
    RED = { r = 1, g = 0.25, b = 0.25 },
    ORANGE = { r = 1, g = 0.55, b = 0.1 },
    YELLOW = { r = 1, g = 0.9, b = 0.2 },
    LIGHT_GREEN = { r = 0.6, g = 1, b = 0.3 },
    DARK_GREEN = { r = 0.2, g = 0.85, b = 0.3 },
    GREY = { r = 0.6, g = 0.6, b = 0.6 },
}

-- The color rows are not here: each character has its own in db.characters,
-- set up from its class and range checks (see Colors.lua).
ns.DEFAULTS = {
    version = 5,
    anchor = "CENTER",     -- point of the health bar the text sits at
    inside = false,        -- inside the health bar instead of next to it
    offsetX = 0,
    offsetY = 0,
    fontSize = 20,
    outline = "THICKOUTLINE", -- "", "OUTLINE" or "THICKOUTLINE"
    format = "bands",      -- "bands" (the color rows' ranges), "range" (20-25), "max" (25) or "mid" (~23)
    showUnit = true,       -- append " yd"
    showText = true,       -- the distance text on the nameplate
    colorText = true,      -- the distance text takes the distance color (white otherwise)
    colorName = false,     -- the unit's name on the nameplate takes the distance color
    showEnemies = true,
    showFriendly = true,
    onlyTarget = false,
    hideBeyond = false,    -- hide instead of showing "41+" past the last color row
    interval = 0.1,        -- seconds between updates
}

-- Defaults of version 1. Saved values that still equal them were never
-- customized, so they move to the new defaults.
local V1_DEFAULTS = { anchor = "LEFT", offsetX = -4, fontSize = 11, outline = "OUTLINE" }

-- Minimum, maximum and step of the numeric settings.
ns.LIMITS = {
    offsetX = { -100, 100, 1 },
    offsetY = { -100, 100, 1 },
    fontSize = { 6, 32, 1 },
    interval = { 0.05, 0.5, 0.05 },
}

local CHOICES = {
    anchor = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    },
    outline = { [""] = true, OUTLINE = true, THICKOUTLINE = true },
    format = { bands = true, range = true, max = true, mid = true },
}

local function Clamp(value, low, high)
    return math.min(math.max(value, low), high)
end

-- Rounds value to the nearest step inside [low, high].
function ns.Snap(value, low, high, step)
    value = low + math.floor((value - low) / step + 0.5) * step
    return Clamp(math.floor(value * 100 + 0.5) / 100, low, high)
end

local function IsColor(color)
    return type(color) == "table" and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number"
end

function ns.SortColors(colors)
    table.sort(colors, function(a, b) return a.distance < b.distance end)
end

-- A character's rows: colors (sorted by distance), farColor past the last
-- row, and auto, true while the rows follow the class and range checks.
function ns.SanitizeRows(entry)
    local far = entry.farColor
    if IsColor(far) then
        entry.farColor = { r = Clamp(far.r, 0, 1), g = Clamp(far.g, 0, 1), b = Clamp(far.b, 0, 1) }
    else
        entry.farColor = CopyTable(ns.PALETTE.RED)
    end

    local colors = {}
    if type(entry.colors) == "table" then
        for _, color in ipairs(entry.colors) do
            if IsColor(color) and type(color.distance) == "number" and #colors < ns.MAX_COLORS then
                colors[#colors + 1] = {
                    distance = Clamp(math.floor(color.distance + 0.5), 1, 999),
                    r = Clamp(color.r, 0, 1),
                    g = Clamp(color.g, 0, 1),
                    b = Clamp(color.b, 0, 1),
                }
            end
        end
    end
    ns.SortColors(colors)
    entry.colors = colors
    if type(entry.auto) ~= "boolean" then
        entry.auto = true
    end
end

-- Replaces missing or invalid values with the defaults. Runs on the saved
-- settings.
function ns.Sanitize(db)
    for key, default in pairs(ns.DEFAULTS) do
        local value, limits = db[key], ns.LIMITS[key]
        if limits then
            db[key] = type(value) == "number" and ns.Snap(value, limits[1], limits[2], limits[3]) or default
        elseif CHOICES[key] then
            if not CHOICES[key][value] then
                db[key] = default
            end
        elseif type(default) == "boolean" and type(value) ~= "boolean" then
            db[key] = default
        end
    end

    -- Up to version 4 one set of rows was shared by every character. Rows now
    -- follow each character's class and talents, so the shared set goes and
    -- every character starts from its own.
    db.colors, db.farColor = nil, nil
    if type(db.characters) ~= "table" then
        db.characters = {}
    end
    for key, entry in pairs(db.characters) do
        if type(key) == "string" and type(entry) == "table" then
            ns.SanitizeRows(entry)
        else
            db.characters[key] = nil
        end
    end

    -- Items seen answering a range check (see Range.lua). Not a setting: it is
    -- kept so the check distances are known from login on.
    local knownItems = {}
    if type(db.knownItems) == "table" then
        for itemID, answered in pairs(db.knownItems) do
            if type(itemID) == "number" and answered == true then
                knownItems[itemID] = true
            end
        end
    end
    db.knownItems = knownItems

    if (db.version or 1) < 2 then
        for key, old in pairs(V1_DEFAULTS) do
            if db[key] == old then
                db[key] = ns.DEFAULTS[key]
            end
        end
    end
    db.version = ns.DEFAULTS.version
end

-- Every settings change ends here.
function ns.SettingsChanged()
    ns.Nameplates.Refresh()
    ns.Options.UpdatePreview()
end

function ns.ResetSettings()
    local knownItems = ns.db.knownItems
    wipe(ns.db)
    for key, value in pairs(CopyTable(ns.DEFAULTS)) do
        ns.db[key] = value
    end
    ns.Sanitize(ns.db)
    ns.db.knownItems = knownItems
    ns.Colors.Setup()
    ns.SettingsChanged()
    ns.Options.Refresh()
end

-- Startup ------------------------------------------------------------------

local events = CreateFrame("Frame")
ns.RegisterEvents(events, "ADDON_LOADED", "PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        if type(NameplateDistanceDB) ~= "table" then
            NameplateDistanceDB = {}
        end
        ns.Sanitize(NameplateDistanceDB)
        ns.db = NameplateDistanceDB
    elseif event == "PLAYER_LOGIN" then
        -- Each part starts on its own, so a failure in one (reported as a normal
        -- Lua error) does not stop the others.
        for _, init in ipairs({ ns.Range.Init, ns.Colors.Setup, ns.Nameplates.Init, ns.Options.Init }) do
            xpcall(init, geterrorhandler())
        end
    end
end)

-- Slash commands -------------------------------------------------------------

SLASH_NAMEPLATEDISTANCE1 = "/npd"
SLASH_NAMEPLATEDISTANCE2 = "/nameplatedistance"
SlashCmdList.NAMEPLATEDISTANCE = function(message)
    local command = strtrim(message or ""):match("^(%S*)"):lower()
    if command == "" or command == "options" then
        ns.Options.Open()
    elseif command == "check" then
        ns.Range.Report("target")
    elseif command == "melee" then
        -- A diagnostic for the melee range on WoW Forever; see Range.lua.
        ns.Range.MeleeReport(strtrim(message or ""):match("^%S+%s+(%S+)"))
    elseif command == "reset" then
        ns.ResetSettings()
        ns.Print(ns.L["settings reset to the defaults."])
    else
        ns.Print(ns.L["/npd - open the options"])
        ns.Print(ns.L["/npd check - list the range checks that answer for your target"])
        ns.Print(ns.L["/npd reset - restore the default settings"])
    end
end
