-- Colors.lua: each character's color rows, set up from its class and from its
-- range checks, whose ranges already include its talents.
--
-- The rows' limits are distances at which the checks change answer
-- (Range.GetMarks), so the ranges on the nameplates are exactly the rows.
-- A band narrower than MIN_BAND yards (40-41) joins the next one.
-- A 0-5 row, when there is one, is the melee reach; for the target it is the
-- real reach its melee buttons give (see Range.lua).
--   * Hunters shoot from a minimum range: green within melee reach, red in
--     the dead zone between it and that minimum (one row), orange through
--     dark green and back to orange across the shooting range, red past it,
--     and grey past the longest check (Hunter's Mark, 100 yards).
--   * Warriors, rogues, and druids in cat or bear form fight in melee: green
--     within melee reach; with a charge (Charge, Intercept, a druid's in
--     either form), red from there to its minimum range (one row) and light
--     green within its range, then orange up to their longest ability;
--     without one, yellow to orange up to it. Red past it. A druid has a set
--     of rows for each of these forms besides its own (see Colors.GetSet).
--   * Every other class can also fight up close: dark green near, then light
--     green, yellow and orange up to the longest range of its spells, and
--     red past it (items can still tell 35-40 from 40+, both out of reach).
-- Until the player edits a row, the rows are rebuilt whenever the checks
-- change: new spells, talents, or an item answering for the first time.
local _, ns = ...
local Plain = ns.Plain
local P = ns.PALETTE

local Colors = {}
ns.Colors = Colors

local MIN_BAND = 2
local MELEE_RANGE = 5

-- From the edges of the shooting range to its middle.
local SHOOTING = { P.ORANGE, P.YELLOW, P.LIGHT_GREEN, P.DARK_GREEN }
local NEAR_TO_FAR = { P.DARK_GREEN, P.LIGHT_GREEN, P.YELLOW, P.ORANGE }
-- Out of melee, towards the longest reach.
local AWAY = { P.YELLOW, P.ORANGE }

local MELEE_CLASSES = { WARRIOR = true, ROGUE = true }
-- The warrior's charges, Charge and Intercept, by their first rank; the other
-- ranks share the name. (A druid's are found otherwise; see MeleeReach.)
local CHARGES = { 100, 20252 }
-- GetShapeshiftFormID() of the forms with rows of their own (Blizzard's
-- DRUID_CAT_FORM and DRUID_BEAR_FORM), and the spells of the bear forms in
-- case Dire Bear Form reports another ID (Blizzard's SpellFlyout.lua).
local FORM_SETS = { [1] = "cat", [5] = "bear" }
local BEAR_FORM_SPELLS = { [5487] = true, [9634] = true }

local function Row(distance, color)
    return { distance = distance, r = color.r, g = color.g, b = color.b }
end

-- The step of ladder at position, from 0 (the first) to 1 (the last).
local function Step(ladder, position)
    return ladder[1 + math.floor(position * (#ladder - 1) + 0.5)]
end

-- Drops the limits that would leave a band narrower than MIN_BAND: of two
-- limits too close together the farther one stays, unless the nearer one is
-- in keep (the melee reach, the ends of the shooting range or of a charge,
-- the longest reach).
local function DropNarrow(limits, keep)
    local out = {}
    for _, limit in ipairs(limits) do
        local last = out[#out]
        if limit - (last or 0) >= MIN_BAND or (keep[limit] and (not last or keep[last])) then
            out[#out + 1] = limit
        elseif last and not keep[last] then
            out[#out] = limit
        end
    end
    return out
end

local function HunterRows(marks, shotMin, shotMax)
    local inside = 0
    for _, mark in ipairs(marks) do
        if mark > shotMin and mark <= shotMax then
            inside = inside + 1
        end
    end
    local half = math.ceil(inside / 2)
    local rows, k = {}, 0
    for _, mark in ipairs(marks) do
        local color = P.RED
        if mark > shotMin and mark <= shotMax then
            k = k + 1
            local fromEdge = math.min(k, inside + 1 - k)
            color = half > 1 and Step(SHOOTING, (fromEdge - 1) / (half - 1)) or P.DARK_GREEN
        elseif mark <= MELEE_RANGE and mark < shotMin then
            color = P.DARK_GREEN
        end
        rows[#rows + 1] = Row(mark, color)
    end
    local last = marks[#marks]
    return rows, (last and last > shotMax) and P.GREY or P.RED
end

-- reach: the longest spell range, or nil without spells (all rows in reach).
local function OtherRows(marks, reach)
    local inside = 0
    for _, mark in ipairs(marks) do
        if not reach or mark <= reach then
            inside = inside + 1
        end
    end
    local rows = {}
    for i, mark in ipairs(marks) do
        local color = P.RED
        if not reach or mark <= reach then
            color = inside > 1 and Step(NEAR_TO_FAR, (i - 1) / (inside - 1)) or P.DARK_GREEN
        end
        rows[i] = Row(mark, color)
    end
    return rows, P.RED
end

-- window: the range of a charge, as { min, max }, or nil. reach: the longest
-- range of the abilities, or nil without any (all red past melee).
local function MeleeRows(marks, window, reach)
    -- Below the window only the melee reach matters: the longest check within
    -- it ends the green row, and the dead zone after it is one red row.
    local limits, melee = {}, nil
    for _, mark in ipairs(marks) do
        if mark <= MELEE_RANGE then
            melee = mark
        elseif not window or mark >= window.min then
            limits[#limits + 1] = mark
        end
    end
    if melee then
        table.insert(limits, 1, melee)
    else
        -- Without a check within melee reach, the first one ends the green row.
        melee = limits[1]
    end
    local keep = {}
    if melee then
        keep[melee] = true
    end
    if window then
        keep[window.min], keep[window.max] = true, true
    end
    if reach then
        keep[reach] = true
    end
    limits = DropNarrow(limits, keep)

    local from, away = window and window.max or melee or MELEE_RANGE, 0
    for _, limit in ipairs(limits) do
        if limit > from and reach and limit <= reach then
            away = away + 1
        end
    end
    local rows, k = {}, 0
    for _, limit in ipairs(limits) do
        local color = P.RED
        if limit == melee then
            color = P.DARK_GREEN
        elseif window and limit <= window.min then
            color = P.RED
        elseif window and limit <= window.max then
            color = P.LIGHT_GREEN
        elseif reach and limit <= reach then
            k = k + 1
            color = (window or away < 2) and P.ORANGE or Step(AWAY, (k - 1) / (away - 1))
        end
        rows[#rows + 1] = Row(limit, color)
    end
    return rows, P.RED
end

-- In a form the spellbook still lists the caster spells: only the ones that
-- can be cast now, or lack only rage or energy, count there.
local function CanCastNow(spellID)
    local usable, noPower = C_Spell.IsSpellUsable(spellID)
    return Plain(usable) or Plain(noPower) or false
end

-- The window of the charges and the longest range of the abilities, from
-- the spells with a range for enemies; usable, when given, filters them. In
-- a druid form (usable given) the only spells with a minimum range are the
-- charges, in cat form too; elsewhere Shoot or Throw may have one, so the
-- charges are known by name.
local function MeleeReach(usable)
    local charges = {}
    for _, spellID in ipairs(CHARGES) do
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            charges[info.name] = true
        end
    end
    local window, reach
    for _, spell in ipairs(ns.Range.GetSpells("hostile")) do
        if not usable or usable(spell.spellID) then
            if spell.minRange > 0 and (usable or charges[spell.name]) then
                window = window or { min = spell.minRange, max = spell.maxRange }
                window.min, window.max = math.min(window.min, spell.minRange), math.max(window.max, spell.maxRange)
            end
            reach = math.max(reach or 0, spell.maxRange)
        end
    end
    return window, reach
end

local function SameColor(a, b)
    return ns.ColorToHex(a) == ns.ColorToHex(b)
end

-- More rows than the Colors page holds: neighbours of the same color become one.
local function Shorten(rows)
    for i = #rows, 2, -1 do
        if #rows <= ns.MAX_COLORS then
            break
        end
        if SameColor(rows[i - 1], rows[i]) then
            table.remove(rows, i - 1)
        end
    end
    for i = #rows, ns.MAX_COLORS + 1, -1 do
        rows[i] = nil
    end
    return rows
end

local function ClassFile()
    local _, classFile = UnitClass("player")
    return Plain(classFile)
end

-- The set of rows in use: "cat" or "bear" for a druid in those forms, ""
-- otherwise.
function Colors.GetSet()
    if ClassFile() ~= "DRUID" then
        return ""
    end
    local set = FORM_SETS[Plain(GetShapeshiftFormID())]
    if not set then
        local index = Plain(GetShapeshiftForm())
        if index and index > 0 then
            local _, _, _, spellID = GetShapeshiftFormInfo(index)
            set = BEAR_FORM_SPELLS[Plain(spellID)] and "bear" or nil
        end
    end
    return set or ""
end

-- The rows and the color past them for this character, as they are now.
function Colors.Build()
    local marks = ns.Range.GetMarks("hostile")
    local shotMin, shotMax = ns.Range.GetShotRange()
    local classFile, set = ClassFile(), Colors.GetSet()
    local rows, far
    if MELEE_CLASSES[classFile] or set ~= "" then
        rows, far = MeleeRows(marks, MeleeReach(set ~= "" and CanCastNow or nil))
    elseif classFile == "HUNTER" and shotMax then
        -- Below the shooting range only the melee reach matters: the longest
        -- check within it ends the green row, and the dead zone after it is
        -- one red row whatever other checks it holds.
        local limits, melee = {}, nil
        for _, mark in ipairs(marks) do
            if mark <= MELEE_RANGE and mark < shotMin then
                melee = mark
            elseif mark >= shotMin then
                limits[#limits + 1] = mark
            end
        end
        if melee then
            table.insert(limits, 1, melee)
        end
        local keep = { [shotMin] = true, [shotMax] = true }
        if melee then
            keep[melee] = true
        end
        rows, far = HunterRows(DropNarrow(limits, keep), shotMin, shotMax)
    else
        local reach = ns.Range.GetReach("hostile")
        rows, far = OtherRows(DropNarrow(marks, reach and { [reach] = true } or {}), reach)
    end
    return Shorten(rows), CopyTable(far)
end

-- The key of a set of rows in db.characters: "Name-Realm", and for a druid's
-- forms "Name-Realm#cat" and "Name-Realm#bear". set defaults to the one in use.
function Colors.GetKey(set)
    local key = (Plain(UnitName("player")) or "?") .. "-" .. (Plain(GetRealmName()) or "?")
    set = set or Colors.GetSet()
    return set == "" and key or key .. "#" .. set
end

-- The rows saved under key, started empty and automatic when missing.
function Colors.GetEntry(key)
    local entry = ns.db.characters[key]
    if not entry then
        entry = { auto = true }
        ns.SanitizeRows(entry)
        ns.db.characters[key] = entry
    end
    return entry
end

-- Name and class of the character the rows belong to, for the Colors page;
-- in a druid form, the class comes with the form's name.
function Colors.GetOwner()
    local name, className = Plain(UnitName("player")) or "?", Plain(UnitClass("player")) or "?"
    if Colors.GetSet() ~= "" then
        local index = Plain(GetShapeshiftForm())
        local spellID = index and index > 0 and Plain((select(4, GetShapeshiftFormInfo(index))))
        local info = spellID and C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            className = className .. ", " .. info.name
        end
    end
    return name, className
end

local function SameRows(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i].distance ~= b[i].distance or not SameColor(a[i], b[i]) then
            return false
        end
    end
    return true
end

-- Rebuilds rows that follow the checks; true when they changed.
function Colors.Update()
    local entry = ns.char
    if not (entry and entry.auto) then
        return false
    end
    local rows, far = Colors.Build()
    if SameRows(rows, entry.colors) and SameColor(far, entry.farColor) then
        return false
    end
    entry.colors, entry.farColor = rows, far
    return true
end

local currentKey, formEvents

-- At login, after a reset and on a change of form: finds the rows in use,
-- or starts them.
function Colors.Setup()
    currentKey = Colors.GetKey()
    ns.char = Colors.GetEntry(currentKey)
    Colors.Update()
    if not formEvents then
        formEvents = CreateFrame("Frame")
        ns.RegisterEvents(formEvents, "UPDATE_SHAPESHIFT_FORM")
        formEvents:SetScript("OnEvent", Colors.OnFormChanged)
    end
end

-- A druid's cat and bear forms have rows of their own.
function Colors.OnFormChanged()
    if Colors.GetKey() ~= currentKey then
        Colors.Setup()
        ns.SettingsChanged()
        ns.Options.Refresh()
    end
    -- What can be cast in the form may settle a moment later.
    C_Timer.After(0.5, function()
        if Colors.Update() then
            ns.SettingsChanged()
            ns.Options.Refresh()
        end
    end)
end

-- The Colors page button: rows set up again for the class and talents, and
-- following the checks from now on.
function Colors.Adjust()
    ns.char.auto = true
    Colors.Update()
    ns.SettingsChanged()
    ns.Options.Refresh()
end

local pending = false

-- Called by Range when the checks change.
function Colors.OnChecksChanged()
    if pending or not (ns.char and ns.char.auto) then
        return
    end
    pending = true
    -- Deferred, because this can be called from inside a nameplate update.
    C_Timer.After(0, function()
        pending = false
        if Colors.Update() then
            ns.SettingsChanged()
            ns.Options.Refresh()
        end
    end)
end
