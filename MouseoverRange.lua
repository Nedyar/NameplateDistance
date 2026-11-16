-- MouseoverRange.lua: a small mouse icon in the lower left corner of the
-- action buttons that have a key bound, while the mouse is over a unit: in
-- the key's usual color when that unit is within the button's range, red when
-- it is not. It is how Blizzard colors the key for the target, for the unit
-- under the mouse instead, for players who cast on it with their keys.
--
-- Blizzard's action buttons register in ActionBarButtonEventsFrame.frames, and
-- each knows its action slot (button.action). A button without a key shows
-- RANGE_INDICATOR (a dot) as its key text. The icon is Blizzard's own, the
-- portrait of its Click Casting window. Off by default (db.mouseoverIcon).
local _, ns = ...
local Plain = ns.Plain

local MouseoverRange = {}
ns.MouseoverRange = MouseoverRange

local ATLAS = "ClickCast-Icon-Mouse"
local INTERVAL = 0.1     -- seconds between updates while the mouse is over a unit
local SIZE = 0.35        -- of the button's width

local icons = {}         -- [action button] = the icon on it
local shown = false      -- some icon is shown

-- The client makes these colors at startup; Blizzard's buttons use them.
local function KeyColor(inRange)
    local color = inRange and ACTIONBAR_HOTKEY_FONT_COLOR or RED_FONT_COLOR
    if color then
        return color:GetRGB()
    end
    if inRange then
        return 0.6, 0.6, 0.6
    end
    return 1, 0.1, 0.1
end

local function HasKey(button)
    local text = button.HotKey and button.HotKey:GetText()
    return text ~= nil and text ~= "" and text ~= RANGE_INDICATOR
end

local function GetIcon(button)
    local icon = icons[button]
    if not icon then
        icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetAtlas(ATLAS)
        icon:SetDesaturated(true)
        local size = math.floor((Plain(button:GetWidth()) or 36) * SIZE + 0.5)
        icon:SetSize(size, size)
        icon:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
        icons[button] = icon
    end
    return icon
end

-- Whether the button's action reaches the unit under the mouse: true, false,
-- or nil when it cannot tell (no range, or not usable on that unit).
local function InRange(button)
    local action = button.action
    if type(action) ~= "number" or not button:IsVisible() or not HasKey(button) then
        return nil
    end
    local ok, inRange = pcall(C_ActionBar.IsActionInRange, action, "mouseover")
    if ok then
        return Plain(inRange)
    end
end

local function Buttons()
    return ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames or {}
end

function MouseoverRange.Update()
    local active = ns.db.mouseoverIcon and Plain(UnitExists("mouseover"))
    if not active and not shown then
        return
    end
    shown = false
    for _, button in pairs(Buttons()) do
        local inRange
        if active then
            inRange = InRange(button)
        end
        if inRange == nil then
            if icons[button] then
                icons[button]:Hide()
            end
        else
            local icon = GetIcon(button)
            icon:SetVertexColor(KeyColor(inRange))
            icon:Show()
            shown = true
        end
    end
end

-- After a settings change: the option may have been turned off.
function MouseoverRange.Refresh()
    if ns.db then
        MouseoverRange.Update()
    end
end

function MouseoverRange.Init()
    local frame = CreateFrame("Frame")
    ns.RegisterEvents(frame, "UPDATE_MOUSEOVER_UNIT")
    frame:SetScript("OnEvent", MouseoverRange.Update)
    -- The unit moves, and the mouse leaves it without an event.
    local elapsedTotal = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= INTERVAL then
            elapsedTotal = 0
            MouseoverRange.Update()
        end
    end)
end
