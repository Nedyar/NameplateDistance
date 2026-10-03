-- Nameplates.lua: puts the distance text on Blizzard's nameplates.
local _, ns = ...
local Plain = ns.Plain
local L = ns.L

local Nameplates = {}
ns.Nameplates = Nameplates

local INF = math.huge
local holders = {}      -- [nameplate] = our frame on it
local active = {}       -- [unit token] = holder
local byUnitFrame = {}  -- [Blizzard's unit frame on a nameplate] = holder

-- Placing the text next to the health bar: the point of the text that touches
-- the chosen point of the bar.
local OUTSIDE = {
    TOPLEFT = "BOTTOMLEFT", TOP = "BOTTOM", TOPRIGHT = "BOTTOMRIGHT",
    LEFT = "RIGHT", CENTER = "CENTER", RIGHT = "LEFT",
    BOTTOMLEFT = "TOPLEFT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPRIGHT",
}

function ns.StyleText(fontString)
    local db = ns.db
    local font = SystemFont_NamePlate and SystemFont_NamePlate:GetFont() or STANDARD_TEXT_FONT
    if not fontString:SetFont(font, db.fontSize, db.outline) then
        fontString:SetFontObject(SystemFont_NamePlate)
    end
    if db.outline == "" then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

function ns.AnchorText(fontString, target)
    local db = ns.db
    local point = db.inside and db.anchor or OUTSIDE[db.anchor]
    fontString:ClearAllPoints()
    fontString:SetPoint(point, target, db.anchor, db.offsetX, db.offsetY)
end

-- Widens [low, high] to the color rows it touches, so the numbers shown are
-- the ones set on the Colors page. The result still contains the real
-- distance: when the range checks straddle a row's limit, the two rows are
-- joined (8-20 becomes 5-20). to is math.huge past the last row.
local function ToColorRanges(low, high)
    local from, to = 0, INF
    for _, color in ipairs(ns.char.colors) do
        local limit = color.distance
        -- A limit equal to high ends the range; one equal to low starts it
        -- (the check at low failed, so the unit is farther than that).
        if limit >= high then
            to = limit
            break
        elseif limit <= low then
            from = limit
        end
    end
    return from, to
end

-- Returns the text to show and the number that picks its color.
function ns.FormatDistance(low, high, exact)
    local db = ns.db
    local text, value
    if db.format == "bands" and #ns.char.colors > 0 then
        local from, to = ToColorRanges(exact or low, exact or high)
        if to == INF then
            value, text = INF, from .. "+"
        else
            value, text = to, from .. "-" .. to
        end
    elseif exact then
        value = math.floor(exact + 0.5)
        text = tostring(value)
    elseif high == INF then
        value, text = INF, low .. "+"
    elseif db.format == "max" or low == high then
        value, text = high, tostring(high)
    elseif db.format == "mid" then
        value = math.floor((low + high) / 2 + 0.5)
        text = "~" .. value
    else
        value, text = high, low .. "-" .. high
    end
    if db.showUnit then
        text = ns.Yards(text)
    end
    return text, value
end

function ns.GetDistanceColor(value)
    local rows = ns.char
    for _, color in ipairs(rows.colors) do
        if value <= color.distance then
            return color.r, color.g, color.b
        end
    end
    local far = rows.farColor
    return far.r, far.g, far.b
end

local function GetHolder(plate)
    local holder = holders[plate]
    if not holder then
        holder = CreateFrame("Frame", nil, plate)
        holder:SetSize(1, 1)
        holder:SetPoint("CENTER")
        holder.plate = plate
        holder.text = holder:CreateFontString(nil, "OVERLAY")
        ns.StyleText(holder.text)
        holders[plate] = holder
    end
    return holder
end

-- The unit's name on Blizzard's nameplate can take the distance color too.
-- Blizzard colors the name itself (class, reaction, tapped, mouseover) each
-- time it updates it, in CompactUnitFrame_UpdateName, so a hook on that
-- function (OnBlizzardName) puts the distance color back right after. The
-- color Blizzard chose is kept, to give it back when the distance color goes.
-- It can be a secret value: it is only ever handed back to SetVertexColor.
local function SetNameColor(holder, r, g, b)
    local name = holder.unitFrame and holder.unitFrame.name
    if not name then
        return
    end
    if r then
        if not holder.nameColored then
            holder.blizzardColor = { name:GetVertexColor() }
            holder.nameColored = true
        end
        if r ~= holder.nameR or g ~= holder.nameG or b ~= holder.nameB then
            holder.nameR, holder.nameG, holder.nameB = r, g, b
            name:SetVertexColor(r, g, b)
        end
    elseif holder.nameColored then
        holder.nameColored, holder.nameR, holder.nameG, holder.nameB = false, nil, nil, nil
        name:SetVertexColor(unpack(holder.blizzardColor))
    end
end

-- Called after every CompactUnitFrame_UpdateName, for raid frames as well:
-- only the unit frames of our nameplates are touched. Forbidden nameplates
-- are never in byUnitFrame, and looking a frame up does not access it.
local function OnBlizzardName(frame)
    local holder = byUnitFrame[frame]
    if holder and holder.unitFrame == frame and frame.name then
        holder.blizzardColor = { frame.name:GetVertexColor() }
        if holder.nameColored then
            frame.name:SetVertexColor(holder.nameR, holder.nameG, holder.nameB)
        end
    end
end

-- Blizzard's unit frame is pooled and only attached to the nameplate when the
-- unit is added, so it is looked up again on every update.
local function TrackUnitFrame(holder)
    local unitFrame = holder.plate.UnitFrame
    if unitFrame ~= holder.unitFrame then
        if holder.unitFrame and byUnitFrame[holder.unitFrame] == holder then
            byUnitFrame[holder.unitFrame] = nil
        end
        -- A newly attached unit frame shows the color Blizzard gave it.
        holder.unitFrame, holder.nameColored, holder.nameR = unitFrame, false, nil
        if unitFrame then
            byUnitFrame[unitFrame] = holder
        end
    end
    return unitFrame
end

local function Update(holder, targetPlate, playerPlate)
    local db, plate, unit, text = ns.db, holder.plate, holder.unit, holder.text

    local unitFrame = TrackUnitFrame(holder)
    local anchor = unitFrame and unitFrame.HealthBarsContainer or plate
    if anchor ~= holder.anchor then
        holder.anchor = anchor
        ns.AnchorText(text, anchor)
    end

    local label, value
    local wanted = (db.showText or db.colorName) and plate ~= playerPlate and (not db.onlyTarget or plate == targetPlate)
        and not Plain(UnitIsGameObject(unit)) and not Plain(UnitNameplateShowsWidgetsOnly(unit))
    if wanted then
        local category = ns.Range.GetCategory(unit)
        if (category == "hostile" and db.showEnemies) or (category ~= "hostile" and db.showFriendly) then
            local exact = category == "friendly" and Plain(UnitIsPlayer(unit)) and ns.Range.GetExactDistance(unit)
            local low, high
            if not exact then
                low, high = ns.Range.GetRange(unit, category)
            end
            if exact or low then
                label, value = ns.FormatDistance(low, high, exact)
                if db.hideBeyond and value == INF then
                    label = nil
                end
            end
        end
    end

    if not label then
        text:Hide()
        holder.label, holder.value = nil, nil
        SetNameColor(holder)
        return
    end
    if value ~= holder.value then
        holder.value = value
        holder.r, holder.g, holder.b = ns.GetDistanceColor(value)
        if db.colorText then
            text:SetTextColor(holder.r, holder.g, holder.b)
        else
            text:SetTextColor(1, 1, 1)
        end
    end
    if db.colorName then
        SetNameColor(holder, holder.r, holder.g, holder.b)
    else
        SetNameColor(holder)
    end
    if not db.showText then
        text:Hide()
        return
    end
    if label ~= holder.label then
        text:SetText(label)
        holder.label = label
    end
    text:Show()
end

local errorShown = false

function Nameplates.UpdateAll()
    if not next(active) then
        return
    end
    local targetPlate = C_NamePlate.GetNamePlateForUnit("target")
    local playerPlate = C_NamePlate.GetNamePlateForUnit("player")
    for _, holder in pairs(active) do
        -- One bad unit must not stop the others, and an error on every update
        -- would soon use up the client's budget of 100 reported Lua errors.
        local ok, message = pcall(Update, holder, targetPlate, playerPlate)
        if not ok and not errorShown then
            errorShown = true
            ns.Print("|cffff6060" .. L["error while updating a nameplate:"] .. "|r %s", tostring(message))
        end
    end
end

function Nameplates.Add(unit)
    -- Forbidden nameplates (friendly units inside instances) are not returned.
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then
        return
    end
    local holder = GetHolder(plate)
    if holder.unit and active[holder.unit] == holder then
        Nameplates.Remove(holder.unit)
    end
    holder.unit = unit
    holder.anchor, holder.label = nil, nil
    holder:SetFrameLevel(math.min(plate:GetFrameLevel() + 20, 9000))
    holder.text:Hide()
    active[unit] = holder
end

function Nameplates.Remove(unit)
    local holder = active[unit]
    if holder then
        active[unit] = nil
        holder.unit = nil
        holder.text:Hide()
        -- The name gets its own color back (on a rescan the unit frame stays
        -- on the nameplate), and the unit frame goes back to Blizzard's pool.
        SetNameColor(holder)
        if holder.unitFrame and byUnitFrame[holder.unitFrame] == holder then
            byUnitFrame[holder.unitFrame] = nil
        end
        holder.unitFrame = nil
    end
end

-- Picks up nameplates that were shown before the addon was listening.
function Nameplates.Rescan()
    for unit in pairs(active) do
        Nameplates.Remove(unit)
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.GetUnit and plate:GetUnit()
        if unit and C_NamePlate.GetNamePlateForUnit(unit) == plate then
            Nameplates.Add(unit)
        end
    end
end

-- Applies changed settings to every nameplate.
function Nameplates.Refresh()
    for _, holder in pairs(holders) do
        ns.StyleText(holder.text)
        holder.anchor, holder.label, holder.value = nil, nil, nil
    end
    Nameplates.UpdateAll()
end

function Nameplates.Init()
    -- A post-hook: Blizzard's function runs untouched and untainted first.
    if CompactUnitFrame_UpdateName then
        hooksecurefunc("CompactUnitFrame_UpdateName", OnBlizzardName)
    end

    local events = CreateFrame("Frame")
    ns.RegisterEvents(events, "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            Nameplates.Add(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            Nameplates.Remove(unit)
        else
            Nameplates.Rescan()
        end
    end)

    local elapsedTotal = 0
    events:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= ns.db.interval then
            elapsedTotal = 0
            Nameplates.UpdateAll()
        end
    end)

    Nameplates.Rescan()
end
