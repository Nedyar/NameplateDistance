-- Behavioral tests for Nameplate Distance. run.lua runs them in Lua 5.1, the
-- game's Lua, against mock.lua, a strict stand-in for the WoW Forever API.
--
-- Each session starts a fresh game (NewSession: the mock and the addon's
-- files, loaded in the order of its TOC), logs in and plays a scenario:
-- units walking away from the player, settings changed through the options
-- pages, other classes and languages. The sessions run in order and share
-- the helpers defined along the way.
local failures, passes = 0, 0
local function check(cond, message)
    if cond then
        passes = passes + 1
    else
        failures = failures + 1
        print_real("FAIL: " .. message)
    end
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

-- The addon's files run with this environment: they read the globals as
-- usual, and any global they set other than ADDON_GLOBALS is a leak.
local ADDON_GLOBALS = { NameplateDistanceDB = true, SLASH_NAMEPLATEDISTANCE1 = true, SLASH_NAMEPLATEDISTANCE2 = true }
local leaks, leaked = {}, {}
local ADDON_ENV = setmetatable({}, {
    __index = _G,
    __newindex = function(_, key, value)
        if not ADDON_GLOBALS[key] and not leaked[key] then
            leaked[key] = true
            leaks[#leaks + 1] = tostring(key)
        end
        _G[key] = value
    end,
})

-- opts: saved (the saved settings the client loads) and locale.
local function NewSession(opts)
    opts = opts or {}
    assert(loadstring(SOURCES["mock.lua"], "@mock.lua"))()
    NameplateDistanceDB = opts.saved
    M.locale = opts.locale
    local ns = {}
    for _, file in ipairs(FILES) do
        local chunk = assert(loadstring(SOURCES[file], "@" .. file))
        setfenv(chunk, ADDON_ENV)
        chunk("NameplateDistance", ns)
    end
    return ns
end

local function Login(ns)
    M.Fire("ADDON_LOADED", "NameplateDistance")
    M.Fire("PLAYER_LOGIN")
    M.Fire("PLAYER_ENTERING_WORLD")
end

local function PlateText(unit)
    local plate = M.plates[unit]
    for _, f in ipairs(M.allFrames) do
        if f.parent == plate and f.text then
            return f.text.shown and f.text.textValue or nil, f.text
        end
    end
end

-- The display tests below were written against the version 1 defaults;
-- this puts those settings back so their expectations stay meaningful.
local function UseV1Look(ns)
    local db = ns.db
    db.anchor, db.offsetX, db.offsetY, db.fontSize, db.outline = "LEFT", -4, 0, 11, "OUTLINE"
    ns.char.auto = false
    ns.char.colors = {
        { distance = 5, r = 1, g = 0.25, b = 0.25 }, { distance = 10, r = 1, g = 0.55, b = 0.1 },
        { distance = 20, r = 1, g = 0.9, b = 0.2 }, { distance = 30, r = 0.6, g = 1, b = 0.3 },
        { distance = 40, r = 0.2, g = 0.85, b = 0.3 },
    }
    ns.char.farColor = { r = 0.6, g = 0.6, b = 0.6 }
    ns.SettingsChanged()
    ns.Options.Refresh()
end

local function Contains(text, low, high, d)
    return low <= d and d <= high
end

---------------------------------------------------------------------------
-- Session 1: fresh install, range estimates, display settings.
---------------------------------------------------------------------------
local ns = NewSession()
Login(ns)
eq(#M.errors, 0, "no errors during login: " .. table.concat(M.errors, " | "))
check(ns.db ~= nil and ns.db.anchor == "CENTER", "defaults loaded")
UseV1Look(ns)
check(M.mainCategory and M.mainCategory.name == "Nameplate Distance", "settings category registered")
check(M.subCategory and M.subCategory.name == "Colors", "colors subcategory registered")
check(M.addonCategory == M.mainCategory, "registered as addon category")
check(SlashCmdList.NAMEPLATEDISTANCE ~= nil and SLASH_NAMEPLATEDISTANCE1 == "/npd", "slash command")
eq(ns.db.format, "bands", "color ranges are the default format")
-- The raw-range tests below use the plain range format.
ns.db.format = "range"

-- Sweep: a hostile unit at every distance from 0 to 60 yards must land inside its bracket.
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
for tenth = 0, 600, 5 do
    local d = tenth / 10
    M.units.nameplate1.d = d
    local low, high = ns.Range.GetRange("nameplate1", "hostile")
    check(low ~= nil, "hostile answer at " .. d)
    if low then
        check(low <= d and d <= high, ("hostile %.1f yd inside [%s, %s]"):format(d, tostring(low), tostring(high)))
    end
end
-- Same for a friendly NPC, out of combat and in combat.
M.AddUnit("nameplate2", { d = 0, friendly = true, name = "Guard" })
for _, combat in ipairs({ false, true }) do
    M.combat = combat
    for tenth = 0, 600, 5 do
        local d = tenth / 10
        M.units.nameplate2.d = d
        local low, high = ns.Range.GetRange("nameplate2", "friendly")
        check(low ~= nil, "friendly answer at " .. d .. (combat and " (combat)" or ""))
        if low then
            check(low <= d and d <= high, ("friendly %.1f yd inside [%s, %s]%s"):format(d, tostring(low), tostring(high), combat and " (combat)" or ""))
        end
    end
end
M.combat = false
eq(#M.blocked, 0, "no restricted call on a friendly unit in combat")

-- Melee spells (0-0; Raptor Strike says "in range" at any distance) are not
-- range checks. The 40 yd items answer nil (as on the beta), so the longest
-- working check is 35 yd.
M.units.nameplate1.d = 50
local low, high = ns.Range.GetRange("nameplate1", "hostile")
check(low == 35 and high == math.huge, "far hostile is 35+ (got " .. tostring(low) .. ", " .. tostring(high) .. ")")

-- Exact brackets for known distances.
M.units.nameplate1.d = 22
low, high = ns.Range.GetRange("nameplate1", "hostile")
check(low == 20 and high == 28, "22 yd -> 20-28 (got " .. tostring(low) .. "-" .. tostring(high) .. ")")
M.units.nameplate1.d = 9
low, high = ns.Range.GetRange("nameplate1", "hostile")
check(low == 8 and high == 20, "9 yd -> 8-20 (got " .. tostring(low) .. "-" .. tostring(high) .. ")")
M.units.nameplate1.d = 4
low, high = ns.Range.GetRange("nameplate1", "hostile")
check(low == 0 and high == 8, "4 yd -> 0-8 (got " .. tostring(low) .. "-" .. tostring(high) .. ")")

-- Items the client does not know are skipped; the others were requested.
check(M.requestedItems[10645] and not M.requestedItems[22432], "item data requested only for known items")

-- Nameplate text and color.
M.units.nameplate1.d = 22
M.AddUnit("nameplate3", { d = 12.3, friendly = true, player = true, group = true, name = "Partymate" })
M.AddUnit("nameplate4", { d = 6, friendly = true, name = "Guard" })
M.AddUnit("nameplate5", { d = 5, name = "Neutral" })
M.AddUnit("player", { d = 0, friendly = true, player = true, name = "Me" })
for _, unit in ipairs({ "nameplate2", "nameplate3", "nameplate4", "nameplate5", "player" }) do
    M.Fire("NAME_PLATE_UNIT_ADDED", unit)
end
M.Tick(0.2)
eq(#M.errors, 0, "no errors while updating")
local text, fs = PlateText("nameplate1")
eq(text, "20-28 yd", "hostile text")
check(fs.color and fs.color[1] == 0.6 and fs.color[2] == 1, "hostile color comes from the 30 yd row")
check(fs.points[1][1] == "RIGHT" and fs.points[1][2] == M.plates.nameplate1.UnitFrame.HealthBarsContainer and fs.points[1][3] == "LEFT" and fs.points[1][4] == -4, "anchored left of the health bar")
eq(PlateText("nameplate3"), "12 yd", "group member exact distance")
eq(PlateText("nameplate4"), "0-8 yd", "friendly npc")
eq(PlateText("nameplate5"), "0-8 yd", "neutral unit uses interaction distance")
eq(PlateText("player"), nil, "personal nameplate has no text")
M.units.nameplate2.d = 60
M.Tick(0.2)
eq(PlateText("nameplate2"), "40+ yd", "friendly beyond every check")
check(select(2, PlateText("nameplate2")).color[1] == 0.6 and select(2, PlateText("nameplate2")).color[3] == 0.6, "far color")

-- In combat, a friendly NPC falls back to helpful spells only.
M.combat = true
M.Tick(0.2)
eq(PlateText("nameplate4"), "0-30 yd", "friendly npc in combat uses spells only")
eq(#M.blocked, 0, "no blocked calls during combat updates")
M.combat = false

-- Format options.
ns.db.format = "max"; ns.SettingsChanged()
eq(PlateText("nameplate1"), "28 yd", "max format")
ns.db.format = "mid"; ns.db.showUnit = false; ns.SettingsChanged()
eq(PlateText("nameplate1"), "~24", "mid format without unit")
ns.db.format = "range"; ns.db.showUnit = true
ns.db.hideBeyond = true; ns.SettingsChanged()
eq(PlateText("nameplate2"), nil, "hidden beyond the longest check")
ns.db.hideBeyond = false
ns.db.onlyTarget = true; M.target = "nameplate1"; ns.SettingsChanged()
eq(PlateText("nameplate1"), "20-28 yd", "only target: target keeps its text")
eq(PlateText("nameplate4"), nil, "only target: others hidden")
ns.db.onlyTarget = false
ns.db.showEnemies = false; ns.SettingsChanged()
eq(PlateText("nameplate1"), nil, "enemies can be turned off")
ns.db.showEnemies = true
ns.db.anchor = "TOP"; ns.db.inside = false; ns.db.offsetY = 3; ns.SettingsChanged()
fs = select(2, PlateText("nameplate1"))
check(fs.points[1][1] == "BOTTOM" and fs.points[1][3] == "TOP" and fs.points[1][5] == 3, "above the bar")
ns.db.inside = true; ns.SettingsChanged()
fs = select(2, PlateText("nameplate1"))
check(fs.points[1][1] == "TOP" and fs.points[1][3] == "TOP", "inside the bar")
ns.db.fontSize = 14; ns.db.outline = "THICKOUTLINE"; ns.SettingsChanged()
fs = select(2, PlateText("nameplate1"))
check(fs.font[2] == 14 and fs.font[3] == "THICKOUTLINE", "font settings applied")

-- Removed nameplates stop updating; re-added ones come back.
M.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
M.Tick(0.2)
eq(PlateText("nameplate1"), nil, "removed nameplate hidden")
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.Tick(0.2)
check(PlateText("nameplate1") ~= nil, "re-added nameplate shown")

-- Secret values never reach a comparison.
M.units.nameplate1.secretHostility = true
M.secretRanges = true
M.Tick(0.2)
eq(#M.errors, 0, "secret values handled")
local sawError = false
for _, line in ipairs(M.printed) do if line:find("error while updating") then sawError = true end end
check(not sawError, "no update error with secret values")
M.units.nameplate1.secretHostility = nil
M.secretRanges = nil

-- An API failure is reported once, not every update.
M.throwOnSpell = true
local before = #M.printed
for _ = 1, 5 do M.Tick(0.2) end
local reported = 0
for i = before + 1, #M.printed do if M.printed[i]:find("error while updating") then reported = reported + 1 end end
eq(reported, 1, "update error reported once")
M.throwOnSpell = nil

-- Diagnostics command.
M.target = "nameplate1"
before = #M.printed
SlashCmdList.NAMEPLATEDISTANCE("check")
check(#M.printed > before + 3, "/npd check prints a report")
check(M.printed[#M.printed]:find("result") ~= nil, "report ends with a result: " .. tostring(M.printed[#M.printed]))
SlashCmdList.NAMEPLATEDISTANCE("")
eq(M.openedCategory, M.mainCategory:GetID(), "/npd opens the settings category")

-- Options UI widgets: the slider, radio buttons and color rows drive the settings.
local function FindFrames(pred) local out = {} for _, f in ipairs(M.allFrames) do if pred(f) then out[#out + 1] = f end end return out end
local sliders = FindFrames(function(f) return f.kind == "Slider" end)
eq(#sliders, 4, "four sliders")
local fontSlider
for _, s in ipairs(sliders) do if s.Text.textValue and s.Text.textValue:find("Font size") then fontSlider = s end end
check(fontSlider ~= nil, "font size slider labelled")
fontSlider:SetValue(18, true)
eq(ns.db.fontSize, 18, "slider changes the font size")
check(fontSlider.Text.textValue:find("18") ~= nil, "slider label shows the value")
local radios = FindFrames(function(f) return f.kind == "CheckButton" and f.text ~= nil end)
eq(#radios, 7, "seven radio buttons")
for _, r in ipairs(radios) do if r.value == "max" then r:Click() end end
eq(ns.db.format, "max", "radio sets the format")
local checkedCount = 0
for _, r in ipairs(radios) do if r.checked and (r.value == "bands" or r.value == "range" or r.value == "max" or r.value == "mid") then checkedCount = checkedCount + 1 end end
eq(checkedCount, 1, "exactly one format radio checked")

-- Color rows: edit a distance, which re-sorts.
local edits = FindFrames(function(f) return f.kind == "EditBox" end)
eq(#edits, ns.MAX_COLORS, "one distance box per possible row")
edits[1]:SetFocus(); edits[1]:SetText("33"); edits[1]:ClearFocus()
eq(ns.char.colors[#ns.char.colors].distance, 40, "rows re-sorted after edit (last)")
local found33 = false
for _, c in ipairs(ns.char.colors) do if c.distance == 33 then found33 = true end end
check(found33, "edited distance stored")
for i = 2, #ns.char.colors do check(ns.char.colors[i - 1].distance <= ns.char.colors[i].distance, "colors sorted") end
-- Escape reverts.
edits[1]:SetFocus(); edits[1]:SetText("2"); edits[1].scripts.OnEscapePressed(edits[1])
check(ns.char.colors[1].distance ~= 2, "escape keeps the old distance")
-- Color picker: change, then cancel restores.
local swatches = FindFrames(function(f) return f.kind == "Button" and f.scripts.OnClick and not f.value and not f.point and f.w == 22 end)
check(#swatches >= 2, "swatches exist")
local firstColor = ns.char.colors[1]
local oldR = firstColor.r
swatches[1]:Click()
M.pickerColor = { 0.1, 0.2, 0.3 }
M.picker.swatchFunc()
check(math.abs(ns.char.colors[1].r - 0.1) < 1e-9, "picker applies the color")
M.picker.cancelFunc({ r = M.picker.r, g = M.picker.g, b = M.picker.b })
check(math.abs(ns.char.colors[1].r - oldR) < 1e-9, "cancel restores the color")
-- Add up to the limit.
local addButton
for _, f in ipairs(FindFrames(function(f) return f.kind == "Button" and f.textValue == "Add color" end)) do addButton = f end
for _ = 1, 20 do addButton:Click() end
eq(#ns.char.colors, ns.MAX_COLORS, "rows capped at the maximum")
check(addButton.enabled == false, "add disabled when full")

-- Reset through the popup.
SlashCmdList.NAMEPLATEDISTANCE("reset")
eq(ns.db.fontSize, 20, "reset restores defaults")
check(ns.char.auto, "reset: rows follow the checks again")
eq(#ns.char.colors, 5, "reset: one row per check distance of this character")
UseV1Look(ns)

-- Sanitize garbage.
local junk = { anchor = "NOWHERE", offsetX = "a", fontSize = 99, outline = 3, format = "x", showUnit = "yes", interval = 0.123,
    colors = { { distance = 5, r = 1, g = 0, b = 0 } }, farColor = { r = 1, g = 1, b = 1 },
    characters = {
        ["A-B"] = { colors = { { distance = -5, r = 2, g = 0, b = 0 }, "bad", { distance = 7.6, r = 0, g = 0.5, b = 1 } }, farColor = 7, auto = "yes" },
        [5] = {}, ["C-D"] = "bad",
    },
    knownItems = { [835] = true, x = true, [7] = "yes" } }
ns.Sanitize(junk)
eq(junk.colors, nil, "the old shared rows are dropped")
eq(junk.farColor, nil, "the old shared far color is dropped")
eq(junk.characters[5], nil, "bad character key dropped")
eq(junk.characters["C-D"], nil, "bad character entry dropped")
eq(junk.characters["A-B"].auto, true, "bad auto flag -> automatic")
local knownCount = 0
for _ in pairs(junk.knownItems) do knownCount = knownCount + 1 end
check(knownCount == 1 and junk.knownItems[835], "only valid known items kept")
local junkRows = junk.characters["A-B"]
eq(junk.anchor, "CENTER", "bad anchor replaced")
eq(junk.offsetX, 0, "bad offset replaced")
eq(junk.fontSize, 32, "font size clamped")
eq(junk.outline, "THICKOUTLINE", "bad outline replaced")
eq(junk.showUnit, true, "bad boolean replaced")
check(math.abs(junk.interval - 0.1) < 1e-9, "interval snapped to its step (got " .. tostring(junk.interval) .. ")")
eq(#junkRows.colors, 2, "invalid color rows dropped")
eq(junkRows.colors[1].distance, 1, "distance clamped to 1")
eq(junkRows.colors[2].distance, 8, "distance rounded")
eq(junkRows.colors[1].r, 1, "channel clamped")
check(type(junkRows.farColor) == "table", "far color replaced")

---------------------------------------------------------------------------
-- Saved settings across sessions.
---------------------------------------------------------------------------
-- Final settings of session 1.
ns.db.anchor = "TOPRIGHT"; ns.db.offsetX = 7; ns.db.offsetY = -3; ns.db.fontSize = 13; ns.db.outline = ""
ns.db.format = "mid"; ns.db.showUnit = false; ns.db.showFriendly = false; ns.db.onlyTarget = true; ns.db.hideBeyond = true
ns.db.interval = 0.25; ns.db.inside = true
ns.char.colors = { { distance = 8, r = 1, g = 0, b = 0 }, { distance = 35, r = 0, g = 1, b = 0 } }
ns.char.farColor = { r = 0, g = 0, b = 1 }
ns.char.auto = false
ns.SettingsChanged()
M.Fire("PLAYER_LOGOUT")
local expected = CopyTable(ns.db)

---------------------------------------------------------------------------
-- Session 2: the client loads the saved settings back.
---------------------------------------------------------------------------
ns = NewSession({ saved = CopyTable(expected) })
Login(ns)
for _, key in ipairs({ "anchor", "offsetX", "offsetY", "fontSize", "outline", "format", "showUnit", "showFriendly", "onlyTarget", "hideBeyond", "inside" }) do
    eq(ns.db[key], expected[key], "restored " .. key)
end
check(math.abs(ns.db.interval - 0.25) < 1e-9, "restored interval")
eq(#ns.char.colors, 2, "restored color rows")
eq(ns.char.colors[2].distance, 35, "restored color distance")
check(math.abs(ns.char.colors[1].r - 1) < 1e-9 and ns.char.colors[1].g == 0, "restored color value")
check(ns.char.farColor.b == 1 and ns.char.farColor.r == 0, "restored far color")
check(not ns.char.auto, "restored edited rows stay edited")
eq(#M.errors, 0, "no errors in session 2")

---------------------------------------------------------------------------
-- Session 3: a 40-41 range and the "More than" row on the Colors page.
---------------------------------------------------------------------------
ns = NewSession()
Login(ns)
UseV1Look(ns)
ns.db.format = "range" -- this session is about the plain 40-41 range
local function FontStringWith(pattern)
    for _, r in ipairs(M.allRegions) do
        if r.kind == "FontString" and type(r.textValue) == "string" and r.textValue:find(pattern) then return r end
    end
end
local farLabel = FontStringWith("^More than")
check(farLabel ~= nil, "far row exists")
eq(farLabel and farLabel.textValue, "More than 40 yd", "far row label follows the last row")
check(FontStringWith("^0 %-$") and FontStringWith("^30 %-$"), "rows show where their range starts")
local farRow = farLabel.parent
eq(farRow.points[1][5], -5 * 28, "far row sits right under the last row")

local text41, value41 = ns.FormatDistance(40, 41)
eq(text41, "40-41 yd", "40-41 text")
local r, g, b = ns.GetDistanceColor(value41)
check(r == 0.6 and g == 0.6 and b == 0.6, "40-41 uses the More than 40 color by default")

local farSwatch
for _, f in ipairs(M.allFrames) do if f.kind == "Button" and f.parent == farRow then farSwatch = f end end
check(farSwatch ~= nil, "far row has a swatch")
farSwatch:Click()
M.pickerColor = { 0.9, 0.1, 0.8 }
M.picker.swatchFunc()
r, g, b = ns.GetDistanceColor(value41)
check(math.abs(r - 0.9) < 1e-9 and math.abs(b - 0.8) < 1e-9, "far swatch changes the 40-41 color")
r = ns.GetDistanceColor(math.huge)
check(math.abs(r - 0.9) < 1e-9, "far swatch also colors 41+")

-- A row up to 41 gives 40-41 its own color and moves "More than" to 41.
local add6
for _, f in ipairs(FindFrames(function(f) return f.kind == "Button" and f.textValue == "Add color" end)) do add6 = f end
add6:Click()
local edits6 = FindFrames(function(f) return f.kind == "EditBox" end)
edits6[6]:SetFocus(); edits6[6]:SetText("41"); edits6[6]:ClearFocus()
eq(ns.char.colors[6].distance, 41, "new row set to 41")
eq(FontStringWith("^More than").textValue, "More than 41 yd", "far label moves to 41")
check(FontStringWith("^40 %-$") ~= nil, "new row starts at 40")
r, g, b = ns.GetDistanceColor(value41)
check(r == 1 and g == 1 and b == 1, "40-41 now uses the new row's color")
r = ns.GetDistanceColor(math.huge)
check(math.abs(r - 0.9) < 1e-9, "41+ keeps the More than color")
eq(farRow.points[1][5], -6 * 28, "far row moved under the new row")
check(FontStringWith("40%-41") ~= nil, "examples show the new range")

-- With no rows, the far row covers everything.
for _ = 1, 6 do
    for _, f in ipairs(FindFrames(function(f) return f.kind == "Button" and f.textValue == "Remove" and f.parent.shown end)) do f:Click() break end
end
eq(#ns.char.colors, 0, "all rows removed")
check(FontStringWith("^Any distance$") ~= nil, "far row says Any distance")
eq(#M.errors, 0, "no errors on the Colors page")

---------------------------------------------------------------------------
-- Session 4: "Color ranges" format (the numbers follow the color rows).
---------------------------------------------------------------------------
ns = NewSession()
Login(ns)
eq(ns.db.format, "bands", "bands is the default")
UseV1Look(ns)
local INF = math.huge
local cases = {
    { 0, 8, "0-10 yd", 10 },
    { 8, 20, "5-20 yd", 20 },
    { 20, 28, "20-30 yd", 30 },
    { 28, 35, "20-40 yd", 40 },
    { 35, 40, "30-40 yd", 40 },
    { 40, 41, "40+ yd", INF },
    { 41, INF, "40+ yd", INF },
    { 35, INF, "30+ yd", INF },
    { 8, 8, "5-10 yd", 10 },
    { 0, 5, "0-5 yd", 5 },
    { 5, 10, "5-10 yd", 10 },
}
for _, c in ipairs(cases) do
    local t, v = ns.FormatDistance(c[1], c[2])
    eq(t, c[3], ("bands %s-%s text"):format(c[1], tostring(c[2])))
    eq(v, c[4], ("bands %s-%s value"):format(c[1], tostring(c[2])))
end
for _, c in ipairs({ { 12.3, "10-20 yd" }, { 20, "10-20 yd" }, { 45, "40+ yd" }, { 0, "0-5 yd" }, { 40, "30-40 yd" } }) do
    eq((ns.FormatDistance(nil, nil, c[1])), c[2], "bands exact " .. c[1])
end
-- The color of a band is the color of the row it ends at.
local _, v10 = ns.FormatDistance(0, 8)
local cr, cg, cb = ns.GetDistanceColor(v10)
check(cr == 1 and cg == 0.55 and cb == 0.1, "0-10 uses the 5-10 row's color")

-- Property: along a distance sweep, the band shown always contains the real
-- distance and its limits are 0, a color row, or "N+" of the last row.
local limits = { [0] = true }
for _, c in ipairs(ns.char.colors) do limits[c.distance] = true end
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
M.AddUnit("nameplate2", { d = 0, friendly = true, name = "Guard" })
for _, spec in ipairs({ { "nameplate1", "hostile" }, { "nameplate2", "friendly" } }) do
    for tenth = 0, 600, 5 do
        local d = tenth / 10
        M.units[spec[1]].d = d
        local lo, hi = ns.Range.GetRange(spec[1], spec[2])
        local t = ns.FormatDistance(lo, hi)
        local a, b = t:match("^(%d+)%-(%d+) yd$")
        local plus = t:match("^(%d+)%+ yd$")
        if a then
            a, b = tonumber(a), tonumber(b)
            check(limits[a] and limits[b], "band limits are color rows: " .. t)
            check(a <= d and d <= b, ("band %s contains %.1f"):format(t, d))
        else
            plus = tonumber(plus)
            check(plus and limits[plus] and d >= plus, ("band %s contains %.1f"):format(t, d))
        end
    end
end

-- On the nameplate, and with hideBeyond.
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.units.nameplate1.d = 22
M.Tick(0.2)
eq(PlateText("nameplate1"), "20-30 yd", "nameplate shows the color range")
M.units.nameplate1.d = 50
M.Tick(0.2)
eq(PlateText("nameplate1"), "30+ yd", "35+ checks show as 30+")
ns.db.hideBeyond = true; ns.SettingsChanged()
eq(PlateText("nameplate1"), nil, "hideBeyond hides N+ color ranges")
ns.db.hideBeyond = false; ns.SettingsChanged()

-- A row at 35 makes the far range line up with the longest check.
ns.char.colors[#ns.char.colors + 1] = { distance = 35, r = 1, g = 1, b = 1 }
ns.SortColors(ns.char.colors)
ns.SettingsChanged()
eq(PlateText("nameplate1"), "35+ yd", "rows that match the checks give exact ranges")
M.units.nameplate1.d = 32
M.Tick(0.2)
eq(PlateText("nameplate1"), "30-35 yd", "30-35 row")

-- With no rows the plain range is shown.
ns.char.colors = {}
ns.SettingsChanged()
M.units.nameplate1.d = 22
M.Tick(0.2)
eq(PlateText("nameplate1"), "20-28 yd", "no rows: plain range")

-- The check report shows both.
ns.ResetSettings()
M.target = "nameplate1"
SlashCmdList.NAMEPLATEDISTANCE("check")
check(M.printed[#M.printed]:find("the checks say 20%-28 yd; the nameplate shows 20%-28 yd") ~= nil, "report shows both: " .. M.printed[#M.printed])

-- The preview on the main page follows the format.
local preview = FontStringWith("^20%-28 yd$")
check(preview ~= nil, "preview shows the color range")

-- The saved settings keep the format.
ns = NewSession({ saved = CopyTable(ns.db) })
Login(ns)
eq(ns.db.format, "bands", "bands kept in the saved settings")
eq(#M.errors, 0, "no errors in session 4")

---------------------------------------------------------------------------
-- Session 5: rows per character, from the class and the range checks.
---------------------------------------------------------------------------
local PALETTE_NAMES = {
    FF4040 = "RED", FF8C1A = "ORANGE", FFE633 = "YELLOW", ["99FF4D"] = "LIGHT", ["33D94D"] = "DARK", ["999999"] = "GREY",
}
local function Name(color) return PALETTE_NAMES[ns.ColorToHex(color)] or ns.ColorToHex(color) end
local function Describe(entry)
    local parts = {}
    for _, row in ipairs(entry.colors) do parts[#parts + 1] = row.distance .. " " .. Name(row) end
    return table.concat(parts, ", ") .. " | " .. Name(entry.farColor)
end
local function MarksText(list) return table.concat(list, ",") end
local function ExpectedBand(d)
    local from = 0
    for _, c in ipairs(ns.char.colors) do
        if d <= c.distance then return from .. "-" .. c.distance .. " yd", c end
        from = c.distance
    end
    return from .. "+ yd", ns.char.farColor
end
-- Walks a hostile unit away and checks the nameplate shows its own row, in the row's color.
local function Sweep(unit, maxDistance, label)
    local wrong = 0
    for q = 1, maxDistance * 4 do
        local d = q / 4 - 0.125 -- never exactly on a limit
        M.units[unit].d = d
        M.Tick(0.2)
        local shown, fs = PlateText(unit)
        local want, row = ExpectedBand(d)
        local color = fs.color
        if shown ~= want or ns.ColorToHex({ r = color[1], g = color[2], b = color[3] }) ~= ns.ColorToHex(row) then
            wrong = wrong + 1
            if wrong <= 3 then print_real(("  %s at %.3f yd: shown %s, row %s"):format(label, d, tostring(shown), want)) end
        end
    end
    eq(wrong, 0, label .. ": the nameplate always shows the unit's own row in its color")
end
local function Buttons(text)
    return FindFrames(function(f) return f.kind == "Button" and f.textValue == text end)
end

-- A mage (the mock's default spellbook): green up close to red out of range.
-- Its checks on enemies change at 8 (duel, Auto Shot's minimum), 20, 28 (follow), 30 and 35.
ns = NewSession()
Login(ns)
eq(MarksText(ns.Range.GetMarks("hostile")), "8,20,28,30,35", "mage marks")
eq(Describe(ns.char), "8 DARK, 20 LIGHT, 28 YELLOW, 30 YELLOW, 35 ORANGE | RED", "mage rows: green to red")
check(ns.char.auto, "mage rows are automatic")
check(ns.db.characters["Tester-Mock Realm"] == ns.char, "rows stored under the character")
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Sweep("nameplate1", 45, "mage")

-- The Colors page: one button to set the rows up, none of the old ones.
eq(#Buttons("Adjust to class & talents"), 1, "one adjust button")
eq(#Buttons("Reset colors"), 0, "no Reset colors button")
eq(#Buttons("Fit to my checks"), 0, "no Fit button")
check(FontStringWith("^Rows for Tester %(Mage%), set up automatically") ~= nil, "status: automatic")
check(FontStringWith("change answer at: |cffffffff8, 20, 28, 30, 35 yd|r") ~= nil, "marks listed")

-- Editing a row stops the automatic updates; the button brings them back.
local swatches8 = FindFrames(function(f) return f.kind == "Button" and f.w == 22 and f.parent and f.parent.kind == "Frame" and f.parent.w == 400 end)
swatches8[1]:Click()
M.pickerColor = { 0.1, 0.2, 0.3 }
M.picker.swatchFunc()
check(not ns.char.auto, "a color change makes the rows edited")
check(FontStringWith("^Rows for Tester %(Mage%), edited by you") ~= nil, "status: edited")
M.picker.cancelFunc()
check(ns.char.auto, "cancelling the picker keeps them automatic")
swatches8[1]:Click()
M.picker.swatchFunc() -- the picker opening with the same color is not an edit
check(ns.char.auto, "opening the picker is not an edit")
M.pickerColor = { 0.1, 0.2, 0.3 }
M.picker.swatchFunc()
local edited = Describe(ns.char)
ns.Range.Rebuild(); ns.Colors.OnChecksChanged(); M.Advance(0)
eq(Describe(ns.char), edited, "edited rows are not rebuilt")
Buttons("Adjust to class & talents")[1]:Click()
check(ns.char.auto, "the button makes the rows automatic again")
eq(Describe(ns.char), "8 DARK, 20 LIGHT, 28 YELLOW, 30 YELLOW, 35 ORANGE | RED", "the button sets the rows up again")
-- The settings panel's Defaults button on the Colors page does the same.
edited = nil
ns.char.colors[1].distance = 3; ns.char.auto = false
M.subCategory.frame:OnDefault()
eq(Describe(ns.char), "8 DARK, 20 LIGHT, 28 YELLOW, 30 YELLOW, 35 ORANGE | RED", "Defaults sets the rows up again")
eq(#M.errors, 0, "no errors for the mage")
local mageDB = CopyTable(ns.db)

---------------------------------------------------------------------------
-- Session 6: a hunter with range talents (Auto Shot 8-41, Hunter's Mark 100 yd).
---------------------------------------------------------------------------
local HUNTER_SPELLS = {
    { id = 201, name = "Auto Shot", min = 8, max = 41, harmful = true, shot = true },
    { id = 202, name = "Arcane Shot", min = 0, max = 41, harmful = true },
    { id = 203, name = "Scatter Shot", min = 0, max = 15, harmful = true },
    { id = 204, name = "Hunter's Mark", min = 0, max = 100, harmful = true },
    { id = 205, name = "Wing Clip", min = 0, max = 5, harmful = true },
    { id = 206, name = "Raptor Strike", min = 0, max = 0, harmful = true, melee = true },
    { id = 207, name = "Mend Pet", min = 0, max = 45, helpful = true },
    { id = 208, name = "Flare", min = 0, max = 40, harmful = true }, -- with Auto Shot at 41: a 40-41 band
}
local hunterDB = CopyTable(mageDB)
hunterDB.knownItems = { [10645] = true, [835] = true, [18904] = true } -- the 20, 30 and 35 yard items
ns = NewSession({ saved = hunterDB })
M.class, M.playerName = "HUNTER", "Archer"
M.SetSpells(CopyTable(HUNTER_SPELLS))
Login(ns)
-- The items at 20, 30 and 35 answered in an earlier session: they are known from login on.
eq(MarksText(ns.Range.GetMarks("hostile")), "5,8,15,20,28,30,35,40,41,100", "hunter marks")
eq(Describe(ns.char), "5 DARK, 8 RED, 15 ORANGE, 20 LIGHT, 28 DARK, 30 DARK, 35 LIGHT, 41 ORANGE, 100 RED | GREY",
    "hunter rows: 0-5 green (melee), 5-8 red (dead zone), green in the shooting range, 35-41 without a 40-41 band, red to Hunter's Mark, grey past it")
check(ns.db.characters["Tester-Mock Realm"] ~= nil and ns.db.characters["Archer-Mock Realm"] == ns.char, "each character has its own rows")
eq(Describe(ns.db.characters["Tester-Mock Realm"]), "8 DARK, 20 LIGHT, 28 YELLOW, 30 YELLOW, 35 ORANGE | RED", "the mage's rows are untouched")
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Boar" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Sweep("nameplate1", 110, "hunter")
for _, c in ipairs({ { 3, "0-5 yd" }, { 6.5, "5-8 yd" }, { 38, "35-41 yd" }, { 40.5, "35-41 yd" } }) do
    M.units.nameplate1.d = c[1]
    M.Tick(0.2)
    eq(PlateText("nameplate1"), c[2], ("hunter at %s yd"):format(c[1]))
end
M.units.nameplate1.d = 120
M.Tick(0.2)
eq(PlateText("nameplate1"), "100+ yd", "past Hunter's Mark")
ns.db.hideBeyond = true; ns.SettingsChanged()
eq(PlateText("nameplate1"), nil, "hideBeyond hides 100+")
ns.db.hideBeyond = false; ns.SettingsChanged()

-- A talent that adds range: the rows follow by themselves.
for _, spell in ipairs(M.spells) do
    if spell.id == 201 or spell.id == 202 then spell.max = 44 end
end
M.Fire("PLAYER_TALENT_UPDATE")
M.Advance(0.6); M.Advance(0)
-- 40-44 is wide enough to be a band of its own.
eq(Describe(ns.char), "5 DARK, 8 RED, 15 ORANGE, 20 YELLOW, 28 LIGHT, 30 DARK, 35 LIGHT, 40 YELLOW, 44 ORANGE, 100 RED | GREY", "rows follow a range talent")
check(FontStringWith("change answer at: |cffffffff5, 8, 15, 20, 28, 30, 35, 40, 44, 100 yd|r") ~= nil, "marks line follows too")
Sweep("nameplate1", 110, "hunter after the talent")
eq(#M.errors, 0, "no errors for the hunter")

-- A fresh hunter: items not known yet. The rows grow when they first answer.
ns = NewSession()
M.class = "HUNTER"
M.SetSpells(CopyTable(HUNTER_SPELLS))
Login(ns)
eq(Describe(ns.char), "5 DARK, 8 RED, 15 ORANGE, 28 DARK, 41 ORANGE, 100 RED | GREY", "before any item answered")
M.AddUnit("nameplate1", { d = 50, hostile = true, name = "Boar" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.Tick(0.2)
M.Advance(0)
eq(Describe(ns.char), "5 DARK, 8 RED, 15 ORANGE, 20 LIGHT, 28 DARK, 30 DARK, 35 LIGHT, 41 ORANGE, 100 RED | GREY", "after the items answered")

-- The dead zone is one red row even with a check inside it; melee keeps its own green row.
ns = NewSession()
M.class = "HUNTER"
M.SetSpells(CopyTable({ HUNTER_SPELLS[1], HUNTER_SPELLS[2], HUNTER_SPELLS[5],
    { id = 901, name = "Mongoose Bite", min = 0, max = 3, harmful = true },
    { id = 902, name = "Net", min = 0, max = 7, harmful = true } }))
Login(ns)
eq(MarksText(ns.Range.GetMarks("hostile")), "3,5,7,8,28,41", "checks at 3, 5 and 7 yards")
eq(Describe(ns.char), "5 DARK, 8 RED, 28 DARK, 41 DARK | RED", "0-5 green up to the longest melee check, 5-8 red, 7 left out")
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Boar" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Sweep("nameplate1", 45, "hunter with a check in the dead zone")

-- A hunter without Hunter's Mark yet: red past the shooting range, no grey.
ns = NewSession()
M.class = "HUNTER"
M.SetSpells(CopyTable({ HUNTER_SPELLS[1], HUNTER_SPELLS[2], HUNTER_SPELLS[3] }))
Login(ns)
eq(Describe(ns.char), "8 RED, 15 ORANGE, 28 DARK, 41 ORANGE | RED", "no Hunter's Mark: red past 41")

-- Narrow bands next to the shooting range's ends: the ends stay, the others go.
ns = NewSession()
M.class = "HUNTER"
M.SetSpells(CopyTable({ HUNTER_SPELLS[1], HUNTER_SPELLS[4],
    { id = 501, name = "Point Blank", min = 0, max = 9, harmful = true },
    { id = 502, name = "Long Shot", min = 0, max = 42, harmful = true } }))
Login(ns)
eq(MarksText(ns.Range.GetMarks("hostile")), "8,9,28,41,42,100", "marks next to 8 and 41")
eq(Describe(ns.char), "8 RED, 28 DARK, 41 DARK, 100 RED | GREY", "8 and 41 kept, 9 and 42 joined")

-- Many check distances: rows of the same color are joined to fit the page.
ns = NewSession()
M.class = "HUNTER"
local many = CopyTable({ HUNTER_SPELLS[1], HUNTER_SPELLS[4] })
for i, range in ipairs({ 10, 12, 14, 16, 18, 22, 24, 26, 32, 34, 38 }) do
    many[#many + 1] = { id = 300 + i, name = "Shot " .. range, min = 0, max = range, harmful = true }
end
M.SetSpells(many)
Login(ns)
check(#ns.Range.GetMarks("hostile") > ns.MAX_COLORS, "more check distances than rows")
eq(#ns.char.colors, ns.MAX_COLORS, "rows shortened to the page")
eq(ns.char.colors[#ns.char.colors].distance, 100, "Hunter's Mark row kept")
local has41 = false
for _, row in ipairs(ns.char.colors) do if row.distance == 41 then has41 = true end end
check(has41, "the shooting range limit kept")
for i = 2, #ns.char.colors do
    check(ns.char.colors[i - 1].distance < ns.char.colors[i].distance, "shortened rows in order")
end
eq(#M.errors, 0, "no errors with many distances")

---------------------------------------------------------------------------
-- Session 7: other classes, older settings, reset.
---------------------------------------------------------------------------
-- A shaman: green up close to red out of range.
ns = NewSession()
M.class, M.playerName = "SHAMAN", "Healer"
M.SetSpells({
    { id = 401, name = "Lightning Bolt", min = 0, max = 30, harmful = true },
    { id = 402, name = "Earth Shock", min = 0, max = 20, harmful = true },
    { id = 403, name = "Healing Wave", min = 0, max = 40, helpful = true },
})
Login(ns)
eq(Describe(ns.char), "8 DARK, 20 LIGHT, 28 YELLOW, 30 ORANGE | RED", "shaman rows")
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Sweep("nameplate1", 40, "shaman")

-- A mage whose talents add range (+6 to fire spells, +3 to Frostbolt).
ns = NewSession()
M.class, M.playerName = "MAGE", "Magus"
M.SetSpells({
    { id = 701, name = "Fireball", min = 0, max = 35, harmful = true, school = "fire" },
    { id = 702, name = "Fire Blast", min = 0, max = 20, harmful = true, school = "fire" },
    { id = 703, name = "Scorch", min = 0, max = 30, harmful = true, school = "fire" },
    { id = 704, name = "Frostbolt", min = 0, max = 30, harmful = true, school = "frost" },
    { id = 705, name = "Polymorph", min = 0, max = 30, harmful = true },
})
Login(ns)
eq(Describe(ns.char), "8 DARK, 20 LIGHT, 28 YELLOW, 30 YELLOW, 35 ORANGE | RED", "mage before the talents")
for _, spell in ipairs(M.spells) do
    if spell.school == "fire" then spell.max = spell.max + 6 elseif spell.school == "frost" then spell.max = spell.max + 3 end
end
M.Fire("TRAIT_CONFIG_UPDATED")
M.Advance(0.6); M.Advance(0)
eq(MarksText(ns.Range.GetMarks("hostile")), "8,26,28,30,33,36,41", "mage marks with the talents")
eq(Describe(ns.char), "8 DARK, 26 LIGHT, 28 LIGHT, 30 YELLOW, 33 YELLOW, 36 ORANGE, 41 ORANGE | RED", "mage rows follow the talents")
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Sweep("nameplate1", 50, "mage with range talents")

-- A warrior with no ability at range: green up close, red past it.
ns = NewSession()
M.class = "WARRIOR"
M.SetSpells({})
Login(ns)
eq(Describe(ns.char), "8 DARK, 28 RED | RED", "warrior rows from the interactions")
-- Other classes: a 1-yard band joins the next one as well.
ns = NewSession()
M.class = "WARRIOR"
M.SetSpells({ { id = 601, name = "Throw", min = 0, max = 29, harmful = true } })
Login(ns)
eq(Describe(ns.char), "8 DARK, 29 ORANGE | RED", "28-29 joined into 8-29")
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Sweep("nameplate1", 35, "warrior")

-- Version 4 settings: one shared set of rows. They go; the look stays.
local v4 = {
    version = 4, anchor = "LEFT", offsetX = -4, fontSize = 11, outline = "OUTLINE", format = "bands",
    colors = { { distance = 5, r = 1, g = 0.25, b = 0.25 }, { distance = 40, r = 1, g = 0.55, b = 0.1 } },
    farColor = { r = 1, g = 0.25, b = 0.25 },
}
ns = NewSession({ saved = v4 })
Login(ns)
eq(ns.db.colors, nil, "shared rows removed")
eq(ns.db.farColor, nil, "shared far color removed")
check(ns.char.auto and #ns.char.colors == 5, "the character gets its own rows")
eq(ns.db.anchor, "LEFT", "a version 4 look is the player's choice")
eq(ns.db.fontSize, 11, "a version 4 size is kept")
-- Version 1 look defaults still move.
ns = NewSession({ saved = { version = 1, anchor = "LEFT", offsetX = -4, fontSize = 11, outline = "OUTLINE" } })
Login(ns)
check(ns.db.anchor == "CENTER" and ns.db.offsetX == 0 and ns.db.fontSize == 20 and ns.db.outline == "THICKOUTLINE", "version 1 look defaults move")

-- Reset: all characters' rows go, this one is set up again, known items stay.
ns = NewSession({ saved = CopyTable(mageDB) })
Login(ns)
ns.char.auto = false
ns.char.colors = { { distance = 3, r = 1, g = 1, b = 1 } }
ns.db.characters["Other-Mock Realm"] = { auto = false, colors = {}, farColor = { r = 0, g = 0, b = 0 } }
ns.ResetSettings()
check(ns.db.characters["Other-Mock Realm"] == nil, "reset clears other characters' rows")
eq(Describe(ns.char), "8 DARK, 20 LIGHT, 28 YELLOW, 30 YELLOW, 35 ORANGE | RED", "reset sets this character up again")
check(ns.db.knownItems[18904], "known items survive a reset")

eq(#M.errors, 0, "no errors in session 7")

---------------------------------------------------------------------------
-- Session 8: show or hide the distance text, color it or not, color the name.
---------------------------------------------------------------------------
ns = NewSession()
Login(ns)
check(ns.db.showText == true and ns.db.colorText == true and ns.db.colorName == false, "defaults: text shown and colored, name untouched")
eq(M.hooks.CompactUnitFrame_UpdateName, 1, "one hook on Blizzard's name update")
local function RGB(v) return ("%.2f,%.2f,%.2f"):format(v[1], v[2], v[3]) end
local YELLOW11, LIGHT11, DARK11, BLIZZARD_RED = "1.00,0.90,0.20", "0.60,1.00,0.30", "0.20,0.85,0.30", "1.00,0.00,0.00"
M.AddUnit("nameplate1", { d = 22, hostile = true, name = "Kobold" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.Tick(0.2)
local frame11 = M.plates.nameplate1.UnitFrame
local name11 = frame11.name
text, fs = PlateText("nameplate1")
eq(text, "20-28 yd", "distance text shown")
eq(RGB(fs.color), YELLOW11, "distance text in the 20-28 color")
eq(RGB(name11.vertex), BLIZZARD_RED, "name keeps Blizzard's color by default")

-- Color the name: the distance color wins, also after Blizzard recolors it.
ns.db.colorName = true; ns.SettingsChanged()
eq(RGB(name11.vertex), YELLOW11, "name in the distance color")
CompactUnitFrame_UpdateName(frame11)
eq(RGB(name11.vertex), YELLOW11, "the distance color is put back after Blizzard's update")
M.units.nameplate1.d = 10
M.Tick(0.2)
eq(RGB(name11.vertex), LIGHT11, "name follows the distance")
frame11.blizzardNameColor = { 0.5, 0.5, 0.5 } -- tapped: Blizzard greys it
CompactUnitFrame_UpdateName(frame11)
eq(RGB(name11.vertex), LIGHT11, "the distance color has priority over Blizzard's grey")

-- Distance text white, or hidden: the name keeps coloring.
ns.db.colorText = false; ns.SettingsChanged()
text, fs = PlateText("nameplate1")
eq(RGB(fs.color), "1.00,1.00,1.00", "distance text white")
eq(RGB(name11.vertex), LIGHT11, "name still colored")
ns.db.showText = false; ns.SettingsChanged()
eq(PlateText("nameplate1"), nil, "distance text hidden")
M.units.nameplate1.d = 4
M.Tick(0.2)
eq(RGB(name11.vertex), DARK11, "hidden text: the name still follows the distance")

-- Coloring the name off: Blizzard's latest color comes back.
ns.db.colorName = false; ns.SettingsChanged()
eq(RGB(name11.vertex), "0.50,0.50,0.50", "Blizzard's color given back")
eq(PlateText("nameplate1"), nil, "nothing shown")
ns.db.showText, ns.db.colorText, ns.db.colorName = true, true, true; ns.SettingsChanged()
eq(PlateText("nameplate1"), "0-8 yd", "text back")
eq(RGB(name11.vertex), DARK11, "name colored again")

-- Units left out (only the target) keep Blizzard's color.
M.AddUnit("nameplate2", { d = 22, hostile = true, name = "Gnoll" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
M.target = "nameplate1"
ns.db.onlyTarget = true; ns.SettingsChanged()
local name12 = M.plates.nameplate2.UnitFrame.name
eq(RGB(name12.vertex), BLIZZARD_RED, "not the target: Blizzard's color")
eq(RGB(name11.vertex), DARK11, "the target: distance color")
ns.db.onlyTarget = false; ns.SettingsChanged()
eq(RGB(name12.vertex), YELLOW11, "every unit colored again")

-- A removed nameplate gives the name back; its pooled unit frame is reused elsewhere.
M.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
eq(RGB(name11.vertex), "0.50,0.50,0.50", "removed: Blizzard's color back")
M.AddUnit("nameplate3", { d = 25, hostile = true, name = "Murloc" })
local plate13 = M.plates.nameplate3
plate13.UnitFrame, M.plates.nameplate1.UnitFrame = frame11, nil -- Blizzard's pool hands the frame on
frame11.blizzardNameColor = { 1, 0, 0 }
CompactUnitFrame_UpdateName(frame11) -- Blizzard sets the new unit up
eq(RGB(name11.vertex), BLIZZARD_RED, "the old unit's color does not follow the frame")
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
M.Tick(0.2)
eq(RGB(name11.vertex), YELLOW11, "the reused frame takes its new unit's color")
M.units.nameplate1 = nil

-- Frames that are not our nameplates (raid frames) are left alone.
local raidFrame = { name = NewRegion("FontString") }
raidFrame.name:SetVertexColor(0, 0, 1)
CompactUnitFrame_UpdateName(raidFrame)
eq(RGB(raidFrame.name.vertex), BLIZZARD_RED, "raid frames get only Blizzard's color")

-- A secret color from Blizzard is kept and handed back untouched.
name12.secretVertex = true
ns.db.colorName = false; ns.SettingsChanged()
ns.db.colorName = true; ns.SettingsChanged()
ns.db.colorName = false; ns.SettingsChanged()
check(rawequal(name12.vertex[1], SECRET), "secret color handed back")
eq(#M.errors, 0, "no errors with a secret color")
local updateError = false
for _, line in ipairs(M.printed) do if line:find("error while updating") then updateError = true end end
check(not updateError, "no nameplate update errors")

-- The preview on the main page follows the options.
ns.db.colorName, ns.db.colorText, ns.db.showText = true, false, false; ns.SettingsChanged()
local previewName = FontStringWith("^Enemy$")
check(previewName and RGB(previewName.vertex) == RGB({ ns.GetDistanceColor(select(2, ns.FormatDistance(20, 25))) }), "preview name colored")
local previewText = FontStringWith("^20%-28 yd$")
check(previewText and not previewText.shown, "preview text hidden")

-- The three options are on the page and kept in the saved settings.
local boxes = {}
for _, f in ipairs(M.allFrames) do
    if f.kind == "CheckButton" and rawget(f, "Text") then boxes[f.Text.textValue] = f end
end
check(boxes["Show the distance text"] and boxes["Color the distance text"] and boxes["Color the unit's name"], "three checkboxes")
boxes["Show the distance text"]:SetChecked(true); boxes["Show the distance text"].scripts.OnClick(boxes["Show the distance text"])
eq(ns.db.showText, true, "checkbox turns the text on")
ns = NewSession({ saved = CopyTable(ns.db) })
Login(ns)
check(ns.db.showText == true and ns.db.colorText == false and ns.db.colorName == true, "flags kept in the saved settings")
eq(#M.errors, 0, "no errors in session 8")

---------------------------------------------------------------------------
-- Session 9: two characters on one account: shared settings, rows of their own.
---------------------------------------------------------------------------
local function EditRows(distances)
    ns.char.auto = false
    ns.char.colors = {}
    for i, d in ipairs(distances) do ns.char.colors[i] = { distance = d, r = 1, g = 1, b = 1 } end
    ns.SettingsChanged()
    M.Advance(1.1)
end
local function Limits12()
    local out = {}
    for i, row in ipairs(ns.char.colors) do out[i] = row.distance end
    return table.concat(out, ",")
end
-- The hunter edits its rows and a shared setting.
ns = NewSession()
M.playerName, M.class = "Archer", "HUNTER"
Login(ns)
EditRows({ 8, 25, 41 })
ns.db.fontSize = 24; ns.SettingsChanged()
M.Fire("PLAYER_LOGOUT")
local saved12 = CopyTable(ns.db)
-- The shaman logs in: the shared settings, its own rows automatic.
ns = NewSession({ saved = saved12 })
M.playerName, M.class = "Healer", "SHAMAN"
Login(ns)
eq(ns.db.fontSize, 24, "shaman: shared settings")
check(ns.char.auto, "shaman: its own rows, not the hunter's")
EditRows({ 10, 30 })
ns.db.fontSize = 18; ns.SettingsChanged()
M.Fire("PLAYER_LOGOUT")
saved12 = CopyTable(ns.db)
-- Back on the hunter: its rows survived the shaman; the shared size is the shaman's.
ns = NewSession({ saved = CopyTable(saved12) })
M.playerName, M.class = "Archer", "HUNTER"
Login(ns)
check(not ns.char.auto, "hunter: edited rows kept")
eq(Limits12(), "8,25,41", "hunter: its own rows")
eq(ns.db.fontSize, 18, "hunter: shared settings as last changed")
-- And the shaman's are still there too.
ns = NewSession({ saved = CopyTable(saved12) })
M.playerName, M.class = "Healer", "SHAMAN"
Login(ns)
eq(Limits12(), "10,30", "shaman: its own rows")
eq(#M.errors, 0, "no errors in session 9")

---------------------------------------------------------------------------
-- Session 10: checks that answer nothing when out of range (WoW Forever).
---------------------------------------------------------------------------
-- A level 1 mage with only Fireball (35 yd); the 30 and 40 yard items answer.
ns = NewSession({ saved = { version = 5, knownItems = { [835] = true, [4945] = true } } })
M.class, M.playerName = "MAGE", "Lowbie"
M.items40, M.spellNilOutOfRange, M.itemNilOutOfRange = true, true, true
M.SetSpells({ { id = 801, name = "Fireball", min = 0, max = 35, harmful = true } })
Login(ns)
eq(MarksText(ns.Range.GetMarks("hostile")), "8,28,30,35,40", "lowbie marks")
eq(ns.Range.GetReach("hostile"), 35, "reach: Fireball")
eq(Describe(ns.char), "8 DARK, 28 LIGHT, 30 YELLOW, 35 ORANGE, 40 RED | RED", "red past Fireball's 35 yards")
-- Walking away from an enemy that was in range: every row shows, none joined.
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Sweep("nameplate1", 50, "lowbie walking away")
for _, c in ipairs({ { 33, "30-35 yd" }, { 37, "35-40 yd" }, { 45, "40+ yd" } }) do
    M.units.nameplate1.d = c[1]
    M.Tick(0.2)
    eq(PlateText("nameplate1"), c[2], ("lowbie at %s yd"):format(c[1]))
end
-- An enemy first seen beyond Fireball's range: the nothing of Fireball and of
-- the 30 yard item cannot be read yet, so the rows show joined until the
-- enemy has been in their range once.
M.AddUnit("nameplate2", { d = 37, hostile = true, name = "Gnoll" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
M.Tick(0.2)
eq(PlateText("nameplate2"), "28-40 yd", "first seen at 37 yd: joined")
M.units.nameplate2.d = 20
M.Tick(0.2)
eq(PlateText("nameplate2"), "8-28 yd", "comes closer")
M.units.nameplate2.d = 37
M.Tick(0.2)
eq(PlateText("nameplate2"), "35-40 yd", "at 37 yd again: exact now")
-- /npd check explains it.
M.target = "nameplate2"
SlashCmdList.NAMEPLATEDISTANCE("check")
local explained = false
for _, line in ipairs(M.printed) do if line:find("Fireball: no answer %(out of range: it answered for this unit before%)") then explained = true end end
check(explained, "the report explains the nothing")
eq(#M.errors, 0, "no errors for the lowbie")

-- A spell that cannot apply to the unit (Polymorph on an undead) never pushes it farther.
ns = NewSession()
M.class, M.spellNilOutOfRange = "MAGE", true
M.SetSpells({
    { id = 811, name = "Polymorph", min = 0, max = 30, harmful = true, onlyFor = "humanoid" },
    { id = 812, name = "Fireball", min = 0, max = 35, harmful = true },
})
Login(ns)
M.AddUnit("nameplate1", { d = 5, hostile = true, name = "Skeleton", type = "undead" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
-- (The 30 yard item answers where Polymorph cannot; counting Polymorph's
-- nothing as out of range would show 30-35 at 29 yards.)
for _, c in ipairs({ { 5, "0-8 yd" }, { 20, "8-28 yd" }, { 29, "28-30 yd" }, { 33, "30-35 yd" }, { 37, "35+ yd" }, { 29, "28-30 yd" } }) do
    M.units.nameplate1.d = c[1]
    M.Tick(0.2)
    eq(PlateText("nameplate1"), c[2], ("undead at %s yd"):format(c[1]))
end
-- Without the item, Polymorph's slot cannot answer for the undead: 28-35, joined but true.
ns.db.knownItems[835], ns.db.knownItems[7734] = nil, nil
M.SetSpells({
    { id = 811, name = "Polymorph", min = 0, max = 30, harmful = true, onlyFor = "humanoid" },
    { id = 812, name = "Fireball", min = 0, max = 35, harmful = true },
})
local realItem = C_Item.IsItemInRange
C_Item.IsItemInRange = function(id, unit) if id == 835 or id == 7734 then return nil end return realItem(id, unit) end
ns.Range.Rebuild()
M.units.nameplate1.d = 29
M.Tick(0.2)
eq(PlateText("nameplate1"), "28-35 yd", "undead at 29 yd without the item: joined, not pushed out")
C_Item.IsItemInRange = realItem
-- On a humanoid Polymorph answers, so its 30 yards count.
M.AddUnit("nameplate2", { d = 5, hostile = true, name = "Thug", type = "humanoid" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
for _, c in ipairs({ { 5, "0-8 yd" }, { 29, "28-30 yd" }, { 33, "30-35 yd" }, { 37, "35+ yd" } }) do
    M.units.nameplate2.d = c[1]
    M.Tick(0.2)
    eq(PlateText("nameplate2"), c[2], ("humanoid at %s yd"):format(c[1]))
end

-- The hunter from before: past 41 yards the text says so.
ns = NewSession()
M.class, M.playerName, M.spellNilOutOfRange = "HUNTER", "Archer", true
M.SetSpells(CopyTable(HUNTER_SPELLS))
Login(ns)
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Boar" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Sweep("nameplate1", 110, "hunter with nothing out of range")
M.units.nameplate1.d = 45
M.Tick(0.2)
eq(PlateText("nameplate1"), "41-100 yd", "hunter at 45 yd")
eq(#M.errors, 0, "no errors in session 10")

---------------------------------------------------------------------------
-- Session 11: every client language.
---------------------------------------------------------------------------
-- KEYS: the texts the code looks up in its translations (from run.lua).
local isKey = {}
for _, key in ipairs(KEYS) do isKey[key] = true end
local function Specs(text)
    local out = {}
    for spec in text:gmatch("%%[-0-9.]*[sd%%]") do out[#out + 1] = spec end
    return table.concat(out, " ")
end
local function FontStringPlain(text)
    for _, r in ipairs(M.allRegions) do
        if r.kind == "FontString" and r.textValue == text then return r end
    end
end
local UNITS = {
    deDE = "20-28 m", esES = "20-28 m", esMX = "20-28 m", frFR = "20-28 m", itIT = "20-28 m",
    ptBR = "20-28 m", ruRU = "20-28 м", koKR = "20-28미터", zhCN = "20-28码", zhTW = "20-28碼",
}
check(#KEYS > 50, "the texts the code translates were found: " .. #KEYS)
for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    ns = NewSession({ locale = locale })
    Login(ns)
    local L = ns.L
    -- Complete, no stale keys, same placeholders.
    local missing, badSpecs, stale = {}, {}, {}
    for _, key in ipairs(KEYS) do
        local text = rawget(L, key)
        if text == nil then
            missing[#missing + 1] = key
        elseif Specs(text) ~= Specs(key) then
            badSpecs[#badSpecs + 1] = key .. " => " .. text
        end
    end
    for key in pairs(L) do
        if not isKey[key] then stale[#stale + 1] = key end
    end
    eq(#missing, 0, locale .. ": every text translated" .. (missing[1] and (" (missing: " .. missing[1] .. ")") or ""))
    eq(#badSpecs, 0, locale .. ": placeholders kept" .. (badSpecs[1] and (" (" .. badSpecs[1] .. ")") or ""))
    eq(#stale, 0, locale .. ": no unused texts" .. (stale[1] and (" (" .. stale[1] .. ")") or ""))
    -- Only its own file applied.
    eq(L["%s yd"], (UNITS[locale]:gsub("^20%-28", "%%s")), locale .. ": unit format")
    -- The nameplate, the pages and the report work in this language.
    M.AddUnit("nameplate1", { d = 22, hostile = true, name = "Kobold" })
    M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    M.Tick(0.2)
    eq(PlateText("nameplate1"), UNITS[locale], locale .. ": nameplate text in the client's unit")
    check(FontStringPlain(L["Show the distance text"]) ~= nil, locale .. ": options page translated")
    local name14, class14 = ns.Colors.GetOwner()
    check(FontStringPlain(L["Rows for %s (%s), set up automatically: they follow new spells and talents until you edit one."]:format(name14, class14)) ~= nil,
        locale .. ": Colors page status translated")
    check(FontStringPlain(L["More than %s"]:format(ns.Yards(35))) ~= nil, locale .. ": far row with the client's unit")
    eq(M.subCategory.name, L["Colors"], locale .. ": Colors page name")
    M.target = "nameplate1"
    local before = #M.printed
    SlashCmdList.NAMEPLATEDISTANCE("check")
    SlashCmdList.NAMEPLATEDISTANCE("help")
    check(#M.printed > before + 5, locale .. ": report and help printed")
    local reportLine = M.printed[#M.printed - 3]
    check(reportLine:find(L["result: the checks say %s; the nameplate shows %s"]:format(ns.Yards("20-28"), UNITS[locale]), 1, true) ~= nil,
        locale .. ": report line translated: " .. reportLine)
    -- Buttons fit their translated text.
    for _, f in ipairs(FindFrames(function(f) return f.kind == "Button" and f.textValue == L["Adjust to class & talents"] end)) do
        check(f.w >= #f.textValue * 6 + 24, locale .. ": adjust button fits its text")
    end
    eq(#M.errors, 0, locale .. ": no errors")
end

-- English variants and languages the client does not have.
for _, case in ipairs({ { "enGB", "20-28 yd" }, { "ptPT", "20-28 m" }, { "jaJP", "20-28 yd" } }) do
    ns = NewSession({ locale = case[1] })
    Login(ns)
    M.AddUnit("nameplate1", { d = 22, hostile = true, name = "Kobold" })
    M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    M.Tick(0.2)
    eq(PlateText("nameplate1"), case[2], case[1] .. ": nameplate text")
    eq(#M.errors, 0, case[1] .. ": no errors")
end
eq(ns.L["Text"], "Text", "unknown language falls back to English")

---------------------------------------------------------------------------
-- Session 12: the target's melee reach, from the melee ability's button event.
---------------------------------------------------------------------------
local function SlotLabels(range)
    local out = {}
    for _, line in ipairs(M.printed) do
        local found = line:match("^|cff33ccffNameplate Distance|r:   " .. range .. " yd %- (.*)$")
        if found then out[#out + 1] = found end
    end
    return out[#out]
end
local function Printed(pattern)
    for _, line in ipairs(M.printed) do
        if line:find(pattern) then return line end
    end
end
-- The text of the /npd melee window, "" while it is hidden.
local function ReportText()
    local window = rawget(_G, "NameplateDistanceReport")
    return window and window.shown and window.Edit:GetText() or ""
end
-- Moves a unit and lets the client send the button events, then updates.
local function Step15(unit, d)
    M.units[unit].d = d
    M.RangeEvents()
    M.Tick(0.2)
end
-- Walks the target away, events on every step: its own row every time. The
-- target starts far away, so the button has said "out of range" once.
local function TargetSweep(unit, maxDistance, label)
    M.target = unit
    Step15(unit, 50)
    local wrong = 0
    for q = 1, maxDistance * 4 do
        local d = q / 4 - 0.125
        Step15(unit, d)
        local shown, want = PlateText(unit), ExpectedBand(d)
        if shown ~= want then
            wrong = wrong + 1
            if wrong <= 3 then print_real(("  %s at %.3f yd: shown %s, row %s"):format(label, d, tostring(shown), want)) end
        end
    end
    eq(wrong, 0, label .. ": the target always shows its own row")
end

-- A hunter with Raptor Strike on the bars.
ns = NewSession()
M.class, M.playerName = "HUNTER", "Archer"
M.SetSpells(CopyTable(HUNTER_SPELLS))
M.actions[1] = 206 -- Raptor Strike
M.actions[2] = 202 -- Arcane Shot: not melee, ignored
Login(ns)
check(M.rangeChecks[1] and not M.rangeChecks[2], "button range check enabled for the melee ability only")
eq(Describe(ns.char), "5 DARK, 8 RED, 15 ORANGE, 28 DARK, 41 ORANGE, 100 RED | GREY", "melee row")
M.AddUnit("nameplate1", { d = 9, hostile = true, name = "Boar" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.target = "nameplate1"
M.RangeEvents()
Step15("nameplate1", 4.9)
SlashCmdList.NAMEPLATEDISTANCE("check")
check((SlotLabels("5") or ""):find("^melee %(Raptor Strike%): in range, Wing Clip") ~= nil,
    "the melee ability comes first and decides for the target: " .. tostring(SlotLabels("5")))
-- A normal mob as target: melee reach 5 yards.
for _, c in ipairs({ { 4.9, "0-5 yd" }, { 5.5, "5-8 yd" }, { 9, "8-15 yd" } }) do
    Step15("nameplate1", c[1])
    eq(PlateText("nameplate1"), c[2], ("normal target at %s yd"):format(c[1]))
end
-- A big mob as target: reach 1.5 + 4 + 4/3 = 6.83 yards.
M.AddUnit("nameplate2", { d = 6.5, hostile = true, name = "Ogre", reach = 4 })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
M.target = "nameplate2"
Step15("nameplate2", 6.5)
eq(PlateText("nameplate2"), "0-5 yd", "big target at 6.5 yd: in melee")
check(select(2, PlateText("nameplate2")).color[2] == 0.85, "in the green row's color")
Step15("nameplate2", 7)
eq(PlateText("nameplate2"), "5-8 yd", "big target at 7 yd: dead zone")
-- Both moving: 5 + 8/3 = 7.67 yards for a normal target.
M.target, M.playerMoving, M.units.nameplate1.moving = "nameplate1", true, true
Step15("nameplate1", 7)
eq(PlateText("nameplate1"), "0-5 yd", "both moving at 7 yd: in melee (leeway)")
M.units.nameplate1.moving = false
Step15("nameplate1", 7)
eq(PlateText("nameplate1"), "5-8 yd", "only you moving at 7 yd: no leeway")
M.playerMoving = false
-- Units that are not the target use the fixed checks; the melee answer they
-- had as target never turns into "out of range".
Step15("nameplate1", 3)
M.target = "nameplate2"
Step15("nameplate2", 6.5)
eq(PlateText("nameplate1"), "0-5 yd", "no longer the target at 3 yd: the fixed 5 yard check")
eq(PlateText("nameplate2"), "0-5 yd", "the big mob, now the target, at 6.5 yd")
M.target = nil
M.RangeEvents()
M.Tick(0.2)
eq(PlateText("nameplate2"), "5-8 yd", "no target: the big mob at 6.5 yd falls back to the fixed checks")
-- IsActionInRange with a unit is not used for other units: in the mock it
-- says "in range" at any distance, as Raptor Strike's button does in game.
M.units.nameplate1.d = 20
M.Tick(0.2)
check(PlateText("nameplate1") ~= "0-5 yd", "a far unit is never shown in melee: " .. tostring(PlateText("nameplate1")))
-- Events about other slots are ignored.
M.target = "nameplate1"
M.Fire("ACTION_RANGE_CHECK_UPDATE", 2, true, true)
M.Tick(0.2)
check(PlateText("nameplate1") ~= "0-5 yd", "another slot's event does not count")
-- Taking Raptor Strike off the bars brings back the fixed checks alone.
M.actions[1] = nil
M.Fire("ACTIONBAR_SLOT_CHANGED", 1)
M.Advance(0.6); M.Advance(0)
SlashCmdList.NAMEPLATEDISTANCE("check")
check((SlotLabels("5") or ""):find("^Wing Clip") ~= nil, "without the ability: the fixed checks: " .. tostring(SlotLabels("5")))
-- Putting it back on another slot: it has to say "out of range" again.
M.actions[37] = 206
M.Fire("ACTIONBAR_SLOT_CHANGED", 37)
M.Advance(0.6); M.Advance(0)
check(M.rangeChecks[37], "range check enabled on slot 37")
check(M.rangeChecks[1], "the old slot is never disabled (the flag is shared with Blizzard's buttons)")
M.RangeEvents()
SlashCmdList.NAMEPLATEDISTANCE("check")
check((SlotLabels("5") or ""):find("^melee %(Raptor Strike%): no answer") ~= nil,
    "on slot 37 it starts over, unused until it says both: " .. tostring(SlotLabels("5")))
Step15("nameplate1", 3)
Step15("nameplate1", 20)
SlashCmdList.NAMEPLATEDISTANCE("check")
check((SlotLabels("5") or ""):find("^melee %(Raptor Strike%): out of range") ~= nil, "found again on slot 37: " .. tostring(SlotLabels("5")))
local calls = M.enableCalls
M.Fire("ACTIONBAR_SLOT_CHANGED", 5)
M.Advance(0.6); M.Advance(0)
eq(M.enableCalls, calls, "an unrelated slot change does not enable the check again")
eq(#M.errors, 0, "no errors for the hunter with Raptor Strike")

-- Walking the target away, also with nothing for an answer out of range.
for _, nilMode in ipairs({ false, true }) do
    ns = NewSession()
    M.class, M.spellNilOutOfRange = "HUNTER", nilMode
    M.SetSpells(CopyTable(HUNTER_SPELLS))
    M.actions[1] = 206
    Login(ns)
    M.AddUnit("nameplate1", { d = 2, hostile = true, name = "Boar" })
    M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    TargetSweep("nameplate1", 110, "hunter target" .. (nilMode and " (nothing out of range)" or ""))
end

-- Seen in game (2026-10-03): Raptor Strike, which only changes the next
-- swing, says "in range" at any distance; Mongoose Bite answers right. Also
-- a copy of Raptor Strike on slot 200, a gamepad bar slot.
local MONGOOSE_BITE = { id = 209, name = "Mongoose Bite", min = 0, max = 0, harmful = true, melee = true }
local spells = CopyTable(HUNTER_SPELLS)
spells[#spells + 1] = CopyTable(MONGOOSE_BITE)
ns = NewSession()
M.class = "HUNTER"
M.SetSpells(spells)
M.actions[7], M.actions[8], M.actions[200] = 206, 209, 206
M.alwaysInRange[7], M.alwaysInRange[200] = true, true
Login(ns)
check(M.rangeChecks[7] and M.rangeChecks[8] and M.rangeChecks[200], "every melee button is watched, also past slot 180")
M.AddUnit("nameplate1", { d = 20, hostile = true, name = "Ogre", reach = 4 })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.target = "nameplate1"
Step15("nameplate1", 20)
eq(PlateText("nameplate1"), ExpectedBand(20), "the target at 20 yd is not stuck in melee by Raptor Strike")
Step15("nameplate1", 6.5)
eq(PlateText("nameplate1"), "0-5 yd", "Mongoose Bite, having said both, gives the big target's melee reach at 6.5 yd")
Step15("nameplate1", 7)
eq(PlateText("nameplate1"), "5-8 yd", "and the dead zone at 7 yd")
SlashCmdList.NAMEPLATEDISTANCE("melee")
check(ReportText():find("Melee answer for the target: out of range (trusted: slot 8 Mongoose Bite).\nTarget: Ogre, attackable true, dead false (nameplate1).", 1, true) ~= nil,
    "/npd melee gives the answer and the trusted buttons: " .. ReportText():sub(1, 200))
check(ReportText():find("\n  slot 7, Raptor Strike: said in range yes, out of range no; ", 1, true) ~= nil, "Raptor Strike never said out of range")
check(ReportText():find("\n  slot 8, Mongoose Bite (trusted): said in range yes, out of range yes (first: Ogre, attackable true, dead false); ", 1, true) ~= nil, "Mongoose Bite said both")
check(ReportText():find("\n  slot 200, Raptor Strike: ", 1, true) ~= nil, "slot 200 is listed")
SlashCmdList.NAMEPLATEDISTANCE("check")
check((SlotLabels("5") or ""):find("^melee %(Raptor Strike, Mongoose Bite%): out of range") ~= nil,
    "/npd check names each melee ability once: " .. tostring(SlotLabels("5")))
eq(#M.errors, 0, "no errors with Raptor Strike stuck in range")

-- Seen in game later: Raptor Strike said "out of range" once on a living
-- enemy, so it became trusted; it then held the target at 0-5 at any
-- distance, ahead of Mongoose Bite on the bars.
M.alwaysInRange[7], M.alwaysInRange[200] = nil, nil
M.Fire("ACTION_RANGE_CHECK_UPDATE", 7, false, true)
M.Fire("ACTION_RANGE_CHECK_UPDATE", 200, false, true)
M.alwaysInRange[7], M.alwaysInRange[200] = true, true
M.units.nameplate1.reach = 1.5
for _, d in ipairs({ 20, 9, 6 }) do
    Step15("nameplate1", d)
    eq(PlateText("nameplate1"), ExpectedBand(d), ("Raptor Strike trusted but wrong, Mongoose Bite says out of range, target at %s yd"):format(d))
end
Step15("nameplate1", 3)
eq(PlateText("nameplate1"), "0-5 yd", "both say in range at 3 yd: in melee")
SlashCmdList.NAMEPLATEDISTANCE("melee")
check(ReportText():find("Melee answer for the target: in range (trusted: slot 7 Raptor Strike, slot 8 Mongoose Bite, slot 200 Raptor Strike).", 1, true) ~= nil,
    "/npd melee lists every trusted button: " .. ReportText():sub(1, 200))
Step15("nameplate1", 20)
SlashCmdList.NAMEPLATEDISTANCE("melee")
check(ReportText():find("Melee answer for the target: out of range (trusted: ", 1, true) ~= nil, "one out of range wins")
-- A hunter with only Raptor Strike: the 8 yard check overrules it past 8 yd.
ns = NewSession()
M.class = "HUNTER"
M.SetSpells(CopyTable(HUNTER_SPELLS))
M.actions[1] = 206
Login(ns)
M.AddUnit("nameplate1", { d = 3, hostile = true, name = "Boar" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.target = "nameplate1"
Step15("nameplate1", 3)
M.alwaysInRange[1] = true
M.Fire("ACTION_RANGE_CHECK_UPDATE", 1, false, true)
for _, d in ipairs({ 30, 20, 12, 9 }) do
    Step15("nameplate1", d)
    eq(PlateText("nameplate1"), ExpectedBand(d), ("only a wrong Raptor Strike, target at %s yd: the fixed checks"):format(d))
end
SlashCmdList.NAMEPLATEDISTANCE("melee")
check(ReportText():find("Melee answer for the target: none, the 8 yd check says farther (trusted: slot 1 Raptor Strike).", 1, true) ~= nil,
    "/npd melee says the 8 yd check overruled it: " .. ReportText():sub(1, 200))
Step15("nameplate1", 3)
eq(PlateText("nameplate1"), "0-5 yd", "only Raptor Strike, target at 3 yd: in melee")
eq(#M.errors, 0, "no errors with a wrong but trusted Raptor Strike")

-- Attack first on the bars, Raptor Strike after it: abilities are asked first.
local ATTACK = { id = 950, name = "Attack", min = 0, max = 0, harmful = true, autoAttack = true }
spells = CopyTable(HUNTER_SPELLS)
spells[#spells + 1] = CopyTable(ATTACK)
ns = NewSession()
M.class = "HUNTER"
M.SetSpells(spells)
M.actions[1], M.actions[2] = 950, 206
M.alwaysInRange[1] = true -- a button stuck in range, as Raptor Strike in game
Login(ns)
check(M.rangeChecks[1] and M.rangeChecks[2], "Attack and Raptor Strike are both watched")
M.AddUnit("nameplate1", { d = 20, hostile = true, name = "Boar" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.target = "nameplate1"
Step15("nameplate1", 20)
eq(PlateText("nameplate1"), ExpectedBand(20), "the target at 20 yd is not stuck in melee")
-- A watched button that never says "out of range" is not used: the target
-- keeps the fixed checks, like every other nameplate. (Moving Raptor Strike
-- to another slot starts over.)
M.actions[2], M.actions[3] = nil, 206
M.alwaysInRange[3] = true
M.Fire("ACTIONBAR_SLOT_CHANGED", 3)
M.Advance(0.6); M.Advance(0)
check(M.rangeChecks[3], "Raptor Strike watched on slot 3")
for _, d in ipairs({ 30, 12, 6, 3 }) do
    Step15("nameplate1", d)
    eq(PlateText("nameplate1"), ExpectedBand(d), ("a button always in range is not used, target at %s yd"):format(d))
end
-- Once it has said "out of range", it is used.
M.alwaysInRange[3] = nil
Step15("nameplate1", 30)
M.units.nameplate1.reach = 4
Step15("nameplate1", 6.5)
eq(PlateText("nameplate1"), "0-5 yd", "a button that said out of range once is used: big target at 6.5 yd")

-- /npd melee: a window with what each melee button says about the target.
local count = #M.printed
SlashCmdList.NAMEPLATEDISTANCE("melee")
local report = ReportText()
eq(#M.printed, count, "/npd melee writes nothing in the chat")
check(report:find("^Nameplate Distance %- melee check, 2026%-10%-03 12:00:00\n") ~= nil, "the report starts with the date")
check(report:find("Melee answer for the target: in range (trusted: slot 3 Raptor Strike).\nTarget: Boar, attackable true, dead false (nameplate1). Within 8 yd (interaction 3): true.", 1, true) ~= nil,
    "the report shows the button used: " .. report:sub(1, 200))
local raptorAt = report:find("\n  slot 3, Raptor Strike %(trusted%): said in range yes, out of range yes %(first: Boar, attackable true, dead false%); event in range true, checks range true, 0 s ago, %d+ times; action ")
local attackAt = report:find("\n  slot 1, Attack (auto attack): said in range yes, out of range no; event in range true", 1, true)
check(raptorAt ~= nil, "the report shows the last event: " .. report)
check(attackAt ~= nil and raptorAt ~= nil and raptorAt < attackAt, "abilities are listed before Attack")
check(report:find("; on target: action true, spell true; on nameplate1: action true, spell true\n", 1, true) ~= nil,
    "the report asks through the target's nameplate token too")
check(report:find("No range events recorded yet: /npd melee log", 1, true) ~= nil, "the report says how to record")
check(M.rangeChecks[1], "/npd melee enables the range events of every melee button")
local window = NameplateDistanceReport
eq(window.title, "Nameplate Distance - melee check", "the window's title")
check(window.Edit.focus and window.Edit.multiLine, "the text is in a focused multi-line box, ready to copy")
local closes = false
for _, name in ipairs(UISpecialFrames) do closes = closes or name == "NameplateDistanceReport" end
check(closes, "Escape closes the window")
window.Edit.scripts.OnEscapePressed(window.Edit)
check(not window.shown, "Escape in the text box closes the window")
-- While not recording, the events build no log line (the target's details
-- are only asked for one).
local deadAsked, realUnitIsDead = 0, UnitIsDead
UnitIsDead = function(...) deadAsked = deadAsked + 1 return realUnitIsDead(...) end
M.Fire("PLAYER_TARGET_CHANGED")
M.RangeEvents()
eq(deadAsked, 0, "no log line built while not recording")
UnitIsDead = realUnitIsDead
-- /npd melee log: records the events, then opens the window with them.
SlashCmdList.NAMEPLATEDISTANCE("melee log")
check(Printed("recording range events: walk away from your target and back, then /npd melee log again%.") ~= nil,
    "/npd melee log starts recording")
check(not window.shown, "no window while recording")
M.Advance(2)
Step15("nameplate1", 9)
M.target = nil
M.Fire("PLAYER_TARGET_CHANGED")
SlashCmdList.NAMEPLATEDISTANCE("melee log")
check(window.shown, "/npd melee log again opens the window")
report = ReportText()
check(report:find("Range events recorded:\n", 1, true) ~= nil, "the report lists the recorded events")
check(report:find("\n      2%.0 s  slot 3: in range false, checks range true\n") ~= nil, "each event with its time: " .. report:sub(-300))
check(report:find("2%.0 s  target changed to nil, attackable false, dead false$") ~= nil, "target changes are recorded")
local function Recorded(text) local n = 0 for _ in text:gmatch(" s  slot ") do n = n + 1 end return n end
local recorded = Recorded(report)
M.RangeEvents()
SlashCmdList.NAMEPLATEDISTANCE("melee")
eq(Recorded(ReportText()), recorded, "nothing is recorded once stopped")
SlashCmdList.NAMEPLATEDISTANCE("melee log")
for _ = 1, 200 do M.RangeEvents() end
SlashCmdList.NAMEPLATEDISTANCE("melee")
check(ReportText():find("Range events recorded (still recording):", 1, true) ~= nil, "/npd melee while recording")
SlashCmdList.NAMEPLATEDISTANCE("melee log")
eq(Recorded(ReportText()), 300, "the recording keeps 300 lines")
check(ReportText():find("  (only the first 300 kept)", 1, true) ~= nil, "and says so")
eq(#M.errors, 0, "no errors with Attack and Raptor Strike")

-- Other classes: the Attack button gives the target's melee row too.
ns = NewSession()
M.class, M.playerName = "WARRIOR", "Tank"
M.SetSpells({ CopyTable(ATTACK) })
M.actions[1] = 950
Login(ns)
eq(MarksText(ns.Range.GetMarks("hostile")), "5,8,28", "warrior marks with Attack on the bars")
eq(Describe(ns.char), "5 DARK, 8 RED, 28 RED | RED", "warrior rows: nothing at range")
M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
TargetSweep("nameplate1", 35, "warrior target")
-- With no fixed 5 yard check, other units cannot tell 0-5 from 5-8.
M.AddUnit("nameplate2", { d = 3, hostile = true, name = "Gnoll" })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
M.Tick(0.2)
eq(PlateText("nameplate2"), "0-8 yd", "warrior, not the target, at 3 yd: joined 0-8")
SlashCmdList.NAMEPLATEDISTANCE("melee")
check(ReportText():find("  slot 1, Attack (auto attack) (trusted): said in range yes, out of range yes (first: Kobold, attackable true, dead false); event in range", 1, true) ~= nil,
    "/npd melee for a warrior")
eq(#M.errors, 0, "no errors in session 12")

-- No melee ability on the bars.
ns = NewSession()
M.class = "MAGE"
M.SetSpells({ { id = 301, name = "Fireball", min = 0, max = 35, harmful = true } })
M.actions[1] = 301
Login(ns)
SlashCmdList.NAMEPLATEDISTANCE("melee")
check(ReportText():find("Melee answer for the target: none yet (no button has said both in range and out of range).\nTarget: nil, attackable false, dead false (no nameplate). Within 8 yd (interaction 3): ", 1, true) ~= nil,
    "/npd melee with no target and no melee ability: " .. ReportText():sub(1, 200))
check(ReportText():find("Melee buttons, in the order they are asked:\n  none with a range check.\n", 1, true) ~= nil, "/npd melee says there is none")
eq(#M.errors, 0, "no errors for /npd melee without a melee ability")

---------------------------------------------------------------------------
-- Session 13: warriors, rogues, and druids in cat or bear form.
---------------------------------------------------------------------------
do
    local function Hex(fs) return ns.ColorToHex({ r = fs.color[1], g = fs.color[2], b = fs.color[3] }) end

    -- A warrior: green in melee, red up to Charge, light green within it,
    -- orange up to Shoot Bow, red past it.
    ns = NewSession()
    M.class, M.playerName = "WARRIOR", "Tank"
    M.SetSpells({
        { id = 100, name = "Charge", min = 8, max = 25, harmful = true },
        { id = 20252, name = "Intercept", min = 8, max = 25, harmful = true },
        { id = 2480, name = "Shoot Bow", min = 8, max = 30, harmful = true },
        { id = 772, name = "Rend", min = 0, max = 0, harmful = true, melee = true },
    })
    M.actions[1] = 772
    Login(ns)
    eq(MarksText(ns.Range.GetMarks("hostile")), "5,8,25,28,30", "warrior marks")
    eq(Describe(ns.char), "5 DARK, 8 RED, 25 LIGHT, 28 ORANGE, 30 ORANGE | RED", "warrior: melee, dead zone, Charge, Shoot Bow")
    M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
    M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    TargetSweep("nameplate1", 40, "warrior target")
    -- A stance is a form too, but warriors keep one set of rows.
    local rows = ns.char
    M.forms = { { formID = 17, spellID = 2457 } }
    M.SetForm(1)
    M.Advance(0.6)
    check(rawequal(ns.char, rows), "a warrior's stance does not change the rows")
    eq(#M.errors, 0, "no errors for the warrior")

    -- A rogue: green in melee, then yellow to orange up to Throw.
    ns = NewSession()
    M.class, M.playerName = "ROGUE", "Shadow"
    M.SetSpells({
        { id = 2764, name = "Throw", min = 0, max = 30, harmful = true },
        { id = 2094, name = "Blind", min = 0, max = 10, harmful = true },
        { id = 1752, name = "Sinister Strike", min = 0, max = 0, harmful = true, melee = true },
    })
    M.actions[1] = 1752
    Login(ns)
    eq(MarksText(ns.Range.GetMarks("hostile")), "5,8,10,28,30", "rogue marks")
    eq(Describe(ns.char), "5 DARK, 8 YELLOW, 10 YELLOW, 28 ORANGE, 30 ORANGE | RED", "rogue: melee, then yellow to orange up to Throw")
    M.AddUnit("nameplate1", { d = 0, hostile = true, name = "Kobold" })
    M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    TargetSweep("nameplate1", 40, "rogue target")
    check(FontStringWith("^Rows for Shadow %(Rogue%), set up automatically") ~= nil, "rogue: the Colors page status")
    eq(#M.errors, 0, "no errors for the rogue")

    -- A druid: its own rows, and one set for each of cat and bear form.
    local DRUID_SPELLS = {
        { id = 5176, name = "Wrath", min = 0, max = 30, harmful = true, usableIn = { caster = true } },
        { id = 16979, name = "Feral Charge", min = 8, max = 25, harmful = true, usableIn = { bear = true } },
        -- The cat form's charge, under a name the addon does not know.
        { id = 49376, name = "Feral Charge - Cat", min = 8, max = 25, harmful = true, usableIn = { cat = true } },
        { id = 1082, name = "Claw", min = 0, max = 0, harmful = true, melee = true, usableIn = { cat = true } },
        { id = 768, name = "Cat Form", min = 0, max = 0 },
        { id = 5487, name = "Bear Form", min = 0, max = 0 },
    }
    -- The stance bar: bear, cat, travel, and Dire Bear Form with another form ID.
    local DRUID_FORMS = {
        { formID = 5, spellID = 5487 }, { formID = 1, spellID = 768 },
        { formID = 3, spellID = 783 }, { formID = 8, spellID = 9634 },
    }
    local function Druid(saved)
        ns = NewSession({ saved = saved })
        M.class, M.playerName = "DRUID", "Leaf"
        M.SetSpells(CopyTable(DRUID_SPELLS))
        M.forms = CopyTable(DRUID_FORMS)
        M.actions[73] = 1082 -- Claw, on the cat form's bar
        Login(ns)
    end
    Druid(nil)
    eq(MarksText(ns.Range.GetMarks("hostile")), "5,8,25,28,30", "druid marks")
    -- A unit at 20 yd: the 20 yard item answers for the first time, a new limit.
    M.AddUnit("nameplate1", { d = 20, hostile = true, name = "Kobold" })
    M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    M.Tick(0.2)
    M.Advance(0.1)
    M.Tick(0.2)
    eq(MarksText(ns.Range.GetMarks("hostile")), "5,8,20,25,28,30", "druid marks with the 20 yard item")
    local caster = ns.char
    eq(Describe(caster), "5 DARK, 8 LIGHT, 20 LIGHT, 25 YELLOW, 28 YELLOW, 30 ORANGE | RED", "druid: the rule of the other classes")
    check(FontStringWith("^Rows for Leaf %(Druid%), set up automatically") ~= nil, "druid: the Colors page status")
    eq(Hex(select(2, PlateText("nameplate1"))), "99FF4D", "druid: a unit at 20 yd in light green")
    -- Cat form: its charge gives a window; Wrath cannot be cast in it, so
    -- nothing reaches past the charge.
    M.SetForm(2)
    check(not rawequal(ns.char, caster), "cat form: rows of its own")
    check(ns.db.characters["Leaf-Mock Realm#cat"] == ns.char, "cat form: saved as Name-Realm#cat")
    eq(Describe(ns.char), "5 DARK, 8 RED, 20 LIGHT, 25 LIGHT, 28 RED, 30 RED | RED",
        "cat form: melee, dead zone, the cat's charge, red past it (Wrath does not count)")
    check(FontStringWith("^Rows for Leaf %(Druid, Cat Form%), set up automatically") ~= nil, "cat form: the Colors page names the form")
    M.Tick(0.2)
    eq(Hex(select(2, PlateText("nameplate1"))), "99FF4D", "cat form: the unit at 20 yd, within the charge, in light green")
    M.Advance(0.6)
    eq(Describe(ns.char), "5 DARK, 8 RED, 20 LIGHT, 25 LIGHT, 28 RED, 30 RED | RED", "cat form: the same a moment later")
    -- Without the cat's charge: green in melee, red past it.
    local catCharge
    for _, spell in ipairs(M.spells) do
        if spell.id == 49376 then catCharge = spell end
    end
    catCharge.usableIn = {}
    ns.Colors.OnFormChanged()
    M.Advance(0.6)
    eq(Describe(ns.char), "5 DARK, 8 RED, 20 RED, 25 RED, 28 RED, 30 RED | RED", "cat form without its charge: red past melee")
    catCharge.usableIn = { cat = true }
    ns.Colors.OnFormChanged()
    M.Advance(0.6)
    -- Bear form: Feral Charge gives a window, as Charge does for a warrior.
    M.SetForm(1)
    eq(Describe(ns.char), "5 DARK, 8 RED, 20 LIGHT, 25 LIGHT, 28 RED, 30 RED | RED", "bear form: melee, dead zone, Feral Charge")
    check(FontStringWith("^Rows for Leaf %(Druid, Bear Form%)") ~= nil, "bear form: the Colors page names the form")
    local bear = ns.char
    M.SetForm(4)
    check(rawequal(ns.char, bear), "Dire Bear Form uses the bear rows")
    -- Travel form and no form: the druid's own rows.
    M.SetForm(3)
    check(rawequal(ns.char, caster), "travel form: the druid's own rows")
    M.SetForm(nil)
    check(rawequal(ns.char, caster), "no form: the druid's own rows")
    M.Tick(0.2)
    eq(Hex(select(2, PlateText("nameplate1"))), "99FF4D", "back to light green out of form")
    -- With the cat form's melee ability, the target gets its melee reach in any form.
    M.target = "nameplate1"
    M.units.nameplate1.reach = 4
    Step15("nameplate1", 30)
    Step15("nameplate1", 6.5)
    eq(PlateText("nameplate1"), "0-5 yd", "druid: Claw's button gives the big target's melee reach")

    -- Editing the cat rows leaves the others alone, and the saved settings keep each set.
    M.SetForm(2)
    EditRows({ 3, 6 })
    M.SetForm(nil)
    check(ns.char.auto, "the druid's own rows stay automatic")
    ns.Colors.Adjust()
    M.SetForm(2)
    eq(Limits12(), "3,6", "the cat rows kept the edit")
    check(not ns.char.auto, "the cat rows are edited")
    M.Fire("PLAYER_LOGOUT")
    -- Next session, with the saved settings: the cat rows are still edited.
    Druid(CopyTable(ns.db))
    check(ns.char.auto, "next session: the druid's own rows automatic")
    M.SetForm(2)
    eq(Limits12(), "3,6", "next session: the cat rows")
    check(not ns.char.auto, "next session: the cat rows edited")
    M.SetForm(1)
    check(ns.char.auto, "next session: the bear rows automatic")
    -- Adjusting the cat rows makes them automatic again.
    M.SetForm(2)
    ns.Colors.Adjust()
    check(ns.char.auto, "adjusting: the cat rows automatic again")
    eq(#M.errors, 0, "no errors for the druid")
end

---------------------------------------------------------------------------
-- Release files.
---------------------------------------------------------------------------
-- The changelog's newest entry is the version in the TOC.
local tocVersion = SOURCES["NameplateDistance.toc"]:match("## Version: ([%d%.]+)")
check(tocVersion ~= nil, "the TOC has a version")
eq(SOURCES["CHANGELOG.md"]:match("\n## ([%d%.]+)"), tocVersion, "the changelog's newest entry matches the TOC version")
-- The packager names the folder after package-as; the game needs it to match the TOC.
eq(SOURCES[".pkgmeta"]:match("package%-as: (%S+)"), "NameplateDistance", "packaged under the TOC's folder name")
check(SOURCES[".pkgmeta"]:find("\nignore:\n    %- Tests\n") ~= nil, "the tests are left out of the package")

-- Over every session: the addon set no global of its own besides its saved
-- settings and its slash commands.
eq(table.concat(leaks, ", "), "", "globals the addon set")

print_real(("%d passed, %d failed"):format(passes, failures))
return failures
