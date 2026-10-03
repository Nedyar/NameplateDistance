-- Strict mock of the WoW Forever (1.60.1 / Midnight API) surface used by the addon.
-- Unknown widget methods raise, so typos are caught instead of silently ignored.
-- M holds the simulated world: units and their distances, the clock, the
-- target, the action bars, and what the addon printed.
M = {
    printed = {}, errors = {}, time = 0, timers = {}, combat = false,
    units = {}, plates = {}, target = nil, eventFrames = {}, updateFrames = {},
    calls = {}, blocked = {},
}

-- Secret sentinel: any comparison, arithmetic or concatenation raises.
local function secretError() error("attempt to use a secret value", 2) end
SECRET = setmetatable({}, {
    __eq = secretError, __lt = secretError, __le = secretError, __concat = secretError,
    __add = secretError, __sub = secretError, __mul = secretError, __div = secretError,
    __tostring = function() return "SECRET" end,
})
function issecretvalue(v) return rawequal(v, SECRET) end
function GetTime() return M.time end

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    M.printed[#M.printed + 1] = table.concat(parts, " ")
end
function geterrorhandler() return function(e) M.errors[#M.errors + 1] = tostring(e) end end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
    return c
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Widgets ----------------------------------------------------------------------

local KNOWN_EVENTS = {}
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "ACTIONBAR_SLOT_CHANGED", "ACTION_RANGE_CHECK_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
    KNOWN_EVENTS[e] = true
end

local Common = {}
function Common:SetSize(w, h) self.w, self.h = w, h end
function Common:SetWidth(w) self.w = w end
function Common:SetHeight(h) self.h = h end
function Common:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
function Common:ClearAllPoints() self.points = {} end
function Common:SetAllPoints(target) self.points = { { "ALL", target } } end
function Common:Show() self.shown = true end
function Common:Hide() self.shown = false end
function Common:SetShown(s) self.shown = not not s end
function Common:IsShown() return self.shown end
function Common:IsVisible() return self.shown end

local Frame = setmetatable({}, { __index = Common })
function Frame:SetScript(name, fn)
    self.scripts[name] = fn
    if name == "OnUpdate" then M.updateFrames[self] = fn or nil end
end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function Frame:RegisterEvent(event)
    if not KNOWN_EVENTS[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
    M.eventFrames[self] = M.eventFrames[self] or {}
    M.eventFrames[self][event] = true
end
function Frame:UnregisterEvent(event) if M.eventFrames[self] then M.eventFrames[self][event] = nil end end
function Frame:SetFrameLevel(l) assert(type(l) == "number" and l >= 0 and l <= 10000, "bad frame level") self.level = l end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetClipsChildren() end
function Frame:SetParent(p) self.parent = p end
function Frame:GetParent() return self.parent end
function Frame:EnableMouseWheel() end
function Frame:SetHitRectInsets(l, r, t, b) assert(type(r) == "number") end
function Frame:CreateFontString(name, layer, template) return NewRegion("FontString", self, template) end
function Frame:CreateTexture(name, layer) return NewRegion("Texture", self) end
function Frame:SetEnabled(e) self.enabled = not not e end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:Click() local s = self.scripts.OnClick if s and self.enabled ~= false then s(self, "LeftButton") end end
function Frame:SetText(t) self.textValue = t end
function Frame:GetText() return self.textValue end
-- A button's label: about 6 pixels per character (bytes, close enough for tests).
function Frame:GetFontString()
    local text = self.textValue or ""
    return { GetStringWidth = function() return #text * 6 end }
end
-- CheckButton
function Frame:SetChecked(c) self.checked = not not c end
function Frame:GetChecked() return self.checked end
-- Slider
function Frame:SetMinMaxValues(a, b) self.min, self.max = a, b end
function Frame:SetValueStep(s) self.step = s end
function Frame:SetObeyStepOnDrag() end
function Frame:SetValue(v, userInput)
    self.value = v
    local s = self.scripts.OnValueChanged
    if s then s(self, v, userInput or false) end
end
function Frame:GetValue() return self.value end
-- EditBox
function Frame:SetAutoFocus() end
function Frame:SetNumeric() end
function Frame:SetMaxLetters() end
function Frame:SetJustifyH() end
function Frame:HasFocus() return self.focus == true end
function Frame:SetFocus() self.focus = true; if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end end
function Frame:ClearFocus()
    if self.focus then
        self.focus = false
        if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
    end
end
function Frame:HighlightText() end
function Frame:SetMultiLine(multi) self.multiLine = multi end
function Frame:SetFontObject(o) self.fontObject = o end
function Frame:SetMaxBytes() end
-- ScrollFrame
function Frame:SetScrollChild(child) self.scrollChild = child end
-- Movable windows
function Frame:SetMovable(movable) self.movable = movable end
function Frame:EnableMouse() end
function Frame:RegisterForDrag() end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:SetFrameStrata(strata) self.strata = strata end
function Frame:GetName() return self.name end
-- PortraitFrameTemplate
function Frame:SetPortraitToAsset(path) assert(self.template == "PortraitFrameTemplate") self.portrait = path end
function Frame:SetTitle(title) assert(self.template == "PortraitFrameTemplate") self.title = title end

-- Widget API methods are PascalCase; reading an unknown one is a typo in the
-- addon. Lowercase keys are plain data fields and may be nil.
local function strictIndex(class, kind)
    return function(t, k)
        local v = class[k]
        if v == nil and type(k) == "string" and k:match("^%u") then
            error(kind .. " has no method '" .. k .. "'", 2)
        end
        return v
    end
end
local FrameMeta = { __index = strictIndex(Frame, "Frame") }

local FontString = setmetatable({}, { __index = Common })
function FontString:SetText(t) self.textValue = t end
function FontString:GetText() return self.textValue end
function FontString:SetFont(path, size, flags)
    assert(type(path) == "string" and type(size) == "number" and type(flags) == "string", "bad SetFont args")
    self.font = { path, size, flags }
    return true
end
function FontString:SetFontObject(o) self.fontObject = o end
function FontString:SetTextColor(r, g, b) self.color = { r, g, b } end
-- Vertex color: may be set to secret values; a region marked secretVertex returns secrets.
function FontString:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
function FontString:GetVertexColor()
    if self.secretVertex then return SECRET, SECRET, SECRET, SECRET end
    local v = self.vertex or { 1, 1, 1, 1 }
    return v[1], v[2], v[3], v[4]
end
function FontString:SetShadowColor() end
function FontString:SetShadowOffset() end
function FontString:SetJustifyH() end
function FontString:GetStringWidth() return #(self.textValue or "") * 6 end
local FontStringMeta = { __index = strictIndex(FontString, "FontString") }

local Texture = setmetatable({}, { __index = Common })
function Texture:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
local TextureMeta = { __index = strictIndex(Texture, "Texture") }

function NewRegion(kind, parent, template)
    local r = { kind = kind, parent = parent, shown = true, template = template }
    M.allRegions = M.allRegions or {}
    M.allRegions[#M.allRegions + 1] = r
    return setmetatable(r, kind == "FontString" and FontStringMeta or TextureMeta)
end

local templates = {
    UICheckButtonTemplate = function(f) f.Text = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall") end,
    UIRadioButtonTemplate = function(f) f.text = f:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall") end,
    UISliderTemplateWithLabels = function(f)
        f.Text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        f.Low = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        f.High = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        f.Thumb = f:CreateTexture()
    end,
    UIPanelButtonTemplate = function(f) end,
    PortraitFrameTemplate = function(f) end,
    UIPanelScrollFrameTemplate = function(f) end,
    InputBoxTemplate = function(f)
        f.scripts.OnEscapePressed = function(self) self:ClearFocus() end
        f.scripts.OnEditFocusLost = function(self) self:HighlightText(0, 0) end
        f.scripts.OnEditFocusGained = function(self) self:HighlightText() end
    end,
}
M.allFrames = {}
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ kind = kind, name = name, parent = parent, template = template, scripts = {}, shown = true }, FrameMeta)
    if name then _G[name] = f end
    if template then
        local init = templates[template]
        assert(init, "unknown template " .. tostring(template))
        init(f)
    end
    M.allFrames[#M.allFrames + 1] = f
    return f
end

function M.Fire(event, ...)
    for frame, events in pairs(M.eventFrames) do
        if events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end
function M.Tick(elapsed)
    for frame, fn in pairs(M.updateFrames) do fn(frame, elapsed) end
end
function M.Advance(seconds)
    M.time = M.time + seconds
    local due = {}
    for i = #M.timers, 1, -1 do
        if M.timers[i].at <= M.time then due[#due + 1] = table.remove(M.timers, i) end
    end
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, t in ipairs(due) do t.fn() end
end

-- Globals and namespaces ------------------------------------------------------------

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
SystemFont_NamePlate = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 9, "" end }
YES, NO = "Yes", "No"
SlashCmdList = {}
StaticPopupDialogs = {}
function StaticPopup_Show(name) M.popup = name end
UIParent = CreateFrame("Frame", "UIParent")
UISpecialFrames = {}
tinsert = table.insert
ChatFontNormal = {}
function date(format) assert(format == "%Y-%m-%d %H:%M:%S") return "2026-10-03 12:00:00" end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
Enum = {
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
}

C_AddOns = {
    LoadAddOn = function() end,
}
C_Timer = { After = function(delay, fn) M.timers[#M.timers + 1] = { at = M.time + delay, fn = fn } end }

function GetLocale() return M.locale or "enUS" end
function InCombatLockdown() return M.combat end

-- Units: M.units[token] = { d = yards, hostile, friendly, player, group, name }
local function U(unit)
    if unit == "target" then unit = M.target end
    return unit and M.units[unit]
end
function UnitExists(unit) return U(unit) ~= nil end
function UnitName(unit) if unit == "player" then return M.playerName, nil end local u = U(unit) return u and u.name, nil end
function UnitRace(unit) return "Human", "Human", 1 end
M.class = "MAGE"
local CLASS_NAMES = { MAGE = "Mage", HUNTER = "Hunter", SHAMAN = "Shaman", WARRIOR = "Warrior", ROGUE = "Rogue", DRUID = "Druid" }
function UnitClass(unit) return CLASS_NAMES[M.class], M.class, 1 end
function GetRealmName() return M.realm or "Mock Realm" end
M.playerName = "Tester"
function UnitCanAttack(a, unit) local u = U(unit) if u and u.secretHostility then return SECRET end return u and u.hostile or false end
function UnitCanAssist(a, unit) local u = U(unit) return u and u.friendly or false end
function UnitIsDead(unit) local u = U(unit) return u and u.dead or false end
function UnitGUID(unit) local u = U(unit) return u and (u.guid or tostring(u)) end
function UnitIsPlayer(unit) local u = U(unit) return u and u.player or false end
function UnitIsGameObject(unit) return false end
function UnitNameplateShowsWidgetsOnly(unit) return false end
function UnitDistanceSquared(unit)
    local u = U(unit)
    if u and u.group then return u.d * u.d, true end
    return 0, false
end

local function restrictedCheck(api, unit)
    local u = U(unit)
    if M.combat and u and not u.hostile then
        M.blocked[#M.blocked + 1] = api
        error("ADDON_ACTION_BLOCKED: " .. api .. " on a non-attackable unit in combat")
    end
    return u
end

-- CheckInteractDistance: 3 = 8 yd, 4 = 28 yd (others answer false).
function CheckInteractDistance(unit, index)
    local u = restrictedCheck("CheckInteractDistance", unit)
    M.calls.interact = (M.calls.interact or 0) + 1
    local reach = ({ [3] = 8, [4] = 28 })[index]
    if not u or not reach then return false end
    return u.d <= reach
end

-- Test spellbook: a made-up class with ranged, min-range, melee and helpful spells.
M.spells = {
    { id = 101, name = "Frostbolt", min = 0, max = 30, harmful = true },
    { id = 102, name = "Frostbolt", min = 0, max = 30, harmful = true },           -- a lower rank
    { id = 103, name = "Fire Blast", min = 0, max = 20, harmful = true },
    { id = 104, name = "Auto Shot", min = 8, max = 35, harmful = true, shot = true },
    { id = 105, name = "Raptor Strike", min = 0, max = 0, harmful = true, melee = true },
    { id = 106, name = "Heal", min = 0, max = 40, helpful = true },
    { id = 107, name = "Fortitude", min = 0, max = 30, helpful = true },
    { id = 108, name = "Passive Thing", min = 0, max = 30, harmful = true, passive = true },
    { id = 109, name = "Future Spell", min = 0, max = 25, harmful = true, future = true },
}
local spellByID = {}
for _, s in ipairs(M.spells) do spellByID[s.id] = s end
function M.AddSpell(s) M.spells[#M.spells + 1] = s; spellByID[s.id] = s end
function M.SetSpells(list)
    M.spells = list
    spellByID = {}
    for _, s in ipairs(list) do spellByID[s.id] = s end
end

C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 2 end,
    GetSpellBookSkillLineInfo = function(line)
        if line == 1 then return { name = "General", itemIndexOffset = 0, numSpellBookItems = 5, isGuild = false, shouldHide = false } end
        return { name = "Class", itemIndexOffset = 5, numSpellBookItems = #M.spells - 5, isGuild = false, shouldHide = false }
    end,
    GetSpellBookItemInfo = function(index, bank)
        assert(bank == 0, "bank")
        local s = M.spells[index]
        if not s then return nil end
        return {
            actionID = s.id, spellID = s.id, name = s.name, subName = "", iconID = 1,
            itemType = s.future and Enum.SpellBookItemType.FutureSpell or Enum.SpellBookItemType.Spell,
            isPassive = s.passive or false, isOffSpec = false, skillLineIndex = index <= 5 and 1 or 2,
        }
    end,
}
-- Forms: M.forms lists the stance bar as { formID, spellID }; M.activeForm is
-- the index of the one in use, or nil. M.SetForm changes it as the client does.
M.forms = {}
function GetShapeshiftForm() return M.activeForm or 0 end
function GetShapeshiftFormID() local f = M.forms[M.activeForm or 0] return f and f.formID end
function GetShapeshiftFormInfo(index)
    local f = M.forms[index]
    if f then return 1, index == M.activeForm, true, f.spellID end
end
function M.SetForm(index)
    M.activeForm = index
    M.Fire("UPDATE_SHAPESHIFT_FORM")
end
-- A spell's usableIn lists the forms it can be cast in ("caster", "cat",
-- "bear"); without it, any.
local FORM_NAMES = { [1] = "cat", [5] = "bear" }
local function UsableNow(s)
    if not s.usableIn then return true end
    return s.usableIn[FORM_NAMES[GetShapeshiftFormID() or 0] or "caster"] or false
end

C_Spell = {
    IsSpellUsable = function(id)
        local s = spellByID[id]
        if not s then return false, false end
        return UsableNow(s), false
    end,
    GetSpellInfo = function(id)
        local s = spellByID[id]
        return s and { name = s.name, iconID = 1, originalIconID = 1, castTime = 0, minRange = s.min, maxRange = s.max, spellID = id }
    end,
    IsSpellHarmful = function(id) return spellByID[id].harmful or false end,
    IsSpellHelpful = function(id) return spellByID[id].helpful or false end,
    IsRangedAutoAttackSpell = function(id) return spellByID[id].shot or false end,
    IsAutoAttackSpell = function(id) return spellByID[id] and spellByID[id].autoAttack or false end,
    IsSpellInRange = function(id, unit)
        local s, u = spellByID[id], U(unit)
        if M.throwOnSpell then error("simulated API failure") end
        if not u then return nil end
        if s.melee then return true end -- as Raptor Strike on Forever: in range at any distance
        if s.harmful and not u.hostile then return nil end
        if s.helpful and not u.friendly then return nil end
        if M.secretRanges then return SECRET end
        if s.onlyFor and u.type ~= s.onlyFor then return nil end -- e.g. Polymorph on an undead
        local inRange = (s.min == 0 or u.d > s.min) and u.d <= s.max
        -- M.spellNilOutOfRange: the answer seen on WoW Forever, nothing instead of false.
        if not inRange and M.spellNilOutOfRange then return nil end
        return inRange
    end,
}

-- Items: only some answer, as measured on the beta (20/30/35 hostile).
local ITEM_RANGE = { [4945] = 40, [8348] = 40, [10645] = 20, [1191] = 20, [835] = 30, [7734] = 30, [18904] = 35, [1251] = 15, [2581] = 15, [1180] = 30, [954] = 30 }
local UNKNOWN_ITEMS = { [22432] = true, [21267] = true }
M.requestedItems = {}
-- Action bars: M.actions[slot] = spell ID. Melee abilities are in range up
-- to the game's melee reach: max(5, player reach + target reach + 4/3), plus
-- 8/3 when both are moving (M.playerMoving and the unit's moving).
M.actions = {}
M.rangeChecks = {}
-- [slot] = true: that button's range event says "in range" at any distance.
M.alwaysInRange = {}
-- What the client does for the buttons: ACTION_RANGE_CHECK_UPDATE for every
-- enabled slot, about the current target (call after moving it or targeting).
function M.RangeEvents()
    for slot in pairs(M.rangeChecks) do
        local s, u = spellByID[M.actions[slot]], M.target and M.units[M.target]
        if s and u then
            local reach = (s.melee or s.autoAttack) and M.MeleeReach(u) or s.max
            M.Fire("ACTION_RANGE_CHECK_UPDATE", slot, M.alwaysInRange[slot] or u.d <= reach, true)
        else
            M.Fire("ACTION_RANGE_CHECK_UPDATE", slot, false, false)
        end
    end
end
function UnitIsUnit(a, b)
    local function resolve(t) if t == "target" then return M.target end return t end
    local ra, rb = resolve(a), resolve(b)
    return ra ~= nil and ra == rb
end
M.playerReach = 1.5
function M.MeleeReach(u)
    local reach = math.max(5, M.playerReach + (u.reach or 1.5) + 4 / 3)
    if M.playerMoving and u.moving then reach = reach + 8 / 3 end
    return reach
end
function GetActionInfo(slot)
    local id = M.actions[slot]
    if id then return "spell", id, "spell" end
end
C_ActionBar = {
    HasAction = function(slot)
        assert(slot >= 1 and slot <= 300, "invalid action slot " .. tostring(slot))
        return M.actions[slot] ~= nil
    end,
    HasRangeRequirements = function(slot)
        local s = spellByID[M.actions[slot]]
        return s ~= nil and (s.melee or s.autoAttack or s.max > 0) or false
    end,
    -- With a unit, melee actions answer "in range" at any distance, as Raptor
    -- Strike's does on WoW Forever (other abilities answer right in game).
    IsActionInRange = function(slot, unit)
        local s, u = spellByID[M.actions[slot]], U(unit)
        if not s or not u then return nil end
        if not (s.melee or s.autoAttack) then return u.d <= s.max end
        return true
    end,
    EnableActionRangeCheck = function(slot, enable)
        M.rangeChecks[slot] = enable and true or nil
        M.enableCalls = (M.enableCalls or 0) + 1
    end,
}

C_Item = {
    GetItemInfoInstant = function(id) if UNKNOWN_ITEMS[id] then return nil end return id, "Misc", "Misc", "", 1, 15, 0 end,
    RequestLoadItemDataByID = function(id) M.requestedItems[id] = true end,
    IsItemInRange = function(id, unit)
        local u = restrictedCheck("IsItemInRange", unit)
        local range = ITEM_RANGE[id]
        if not u or not range then return nil end
        if range == 40 and not M.items40 then return nil end -- only some sessions have 40 yard items
        -- 1251/2581/1180/954 are friendly-only, the rest hostile-only (roughly like the real items).
        local friendlyItem = id == 1251 or id == 2581 or id == 1180 or id == 954
        if friendlyItem ~= (u.friendly and true or false) then return nil end
        if u.d > range and M.itemNilOutOfRange then return nil end
        return u.d <= range
    end,
}

-- Blizzard's name coloring (see CompactUnitFrame.lua) and the hook helper.
M.hooks = {}
function CompactUnitFrame_UpdateName(frame)
    local c = frame.blizzardNameColor or { 1, 0, 0 }
    if frame.name then frame.name:SetVertexColor(c[1], c[2], c[3]) end
end
function hooksecurefunc(name, hook)
    local original = _G[name]
    assert(type(original) == "function", "hooksecurefunc: no function " .. tostring(name))
    _G[name] = function(...) original(...); hook(...) end
    M.hooks[name] = (M.hooks[name] or 0) + 1
end

-- Nameplates
local function NewPlate(unit)
    local plate = CreateFrame("Frame")
    plate.unitToken = unit
    plate.GetUnit = function(self) return self.unitToken end
    plate.level = 5
    plate.UnitFrame = { HealthBarsContainer = CreateFrame("Frame"), name = NewRegion("FontString") }
    plate.UnitFrame.name:SetVertexColor(1, 0, 0) -- Blizzard: red for a hostile NPC
    return plate
end
function M.AddUnit(unit, info)
    M.units[unit] = info
    M.plates[unit] = M.plates[unit] or NewPlate(unit)
end
C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit == "target" then unit = M.target end
        return unit and M.units[unit] and M.plates[unit] or nil
    end,
    GetNamePlates = function()
        local list = {}
        for unit, plate in pairs(M.plates) do if M.units[unit] then list[#list + 1] = plate end end
        return list
    end,
}

-- Settings panel and color picker
SettingsPanel = CreateFrame("Frame")
SettingsPanel.shown = false
local nextCategory = 0
local function NewCategory(frame, name)
    nextCategory = nextCategory + 1
    local id = nextCategory
    return { frame = frame, name = name, GetID = function() return id end }
end
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) M.mainCategory = NewCategory(frame, name) return M.mainCategory end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name) M.subCategory = NewCategory(frame, name) return M.subCategory end,
    RegisterAddOnCategory = function(c) M.addonCategory = c end,
    OpenToCategory = function(id) M.openedCategory = id; SettingsPanel.shown = true end,
}
ColorPickerFrame = {
    SetupColorPickerAndShow = function(self, info)
        M.picker = info
        M.pickerColor = { info.r, info.g, info.b }
        info.swatchFunc() -- the real frame fires OnColorSelect while setting up
    end,
    GetColorRGB = function() return unpack(M.pickerColor) end,
}
