-- Range.lua: estimates how far away a unit is.
--
-- Addons cannot read where other units stand (UnitPosition only answers for
-- the player and group members), so the distance is bracketed with range
-- checks: spells from the player's spellbook, items with known ranges and
-- interaction distances. The result is a range such as 20-25 yards. Party and
-- raid members get an exact figure from UnitDistanceSquared.
--
-- Measured on the WoW Forever beta (forever-addon-kit, build 69893):
--   * C_Spell.IsSpellInRange, C_Item.IsItemInRange and CheckInteractDistance
--     return plain values, also in open-world combat.
--   * Melee abilities report a 0-0 range, so they give no distance to check,
--     and the ones that only change the next swing (Raptor Strike) mostly
--     answer "in range" at any distance. Spells without a maximum range are left out
--     of the checks; the melee reach comes from the action buttons instead
--     (see TargetMeleeProbe).
-- UnitInRange is documented with SecretReturns on this client, so it is not used.
local _, ns = ...
local Plain = ns.Plain
local L = ns.L

local Range = {}
ns.Range = Range

local INF = math.huge
local MAX_PROBES_PER_SLOT = 4
local CATEGORIES = { "hostile", "friendly", "other" }

-- Items with a known use range, in yards (vanilla item data, as listed by
-- LibRangeCheck-3.0). Items the client does not know are skipped.
local HOSTILE_ITEMS = {
    [5] = { 8149, 22432 },          -- Voodoo Charm, Devilsaur Barb
    [10] = { 17626, 10699 },        -- Frostwolf Muzzle, Yeh'kinya's Bramble
    [20] = { 10645, 1191 },         -- Gnomish Death Ray, Bag of Marbles
    [25] = { 13289 },               -- Egan's Blaster
    [30] = { 835, 7734 },           -- Large Rope Net, Six Demon Bag
    [35] = { 18904 },               -- Zorbin's Ultra-Shrinker
    [40] = { 4945, 8348 },          -- Faintly Glowing Skull, Helm of Fire
}
local FRIENDLY_ITEMS = {
    [5] = { 8149, 1970 },           -- Voodoo Charm, Restoring Balm
    [10] = { 17626, 21267 },        -- Frostwolf Muzzle, Toasting Goblet
    [15] = { 1251, 2581 },          -- Linen Bandage, Heavy Linen Bandage
    [20] = { 21519, 12450 },        -- Mistletoe, Juju Flurry
    [25] = { 13289 },               -- Egan's Blaster
    [30] = { 1180, 954 },           -- Scroll of Stamina, Scroll of Strength
    [35] = { 18904 },               -- Zorbin's Ultra-Shrinker
    [40] = { 18662, 11562 },        -- Heavy Leather Ball, Crystal Restore
}

-- CheckInteractDistance indexes 3 (duel) and 4 (follow), in yards. They depend
-- on the player's race because larger models reach less far (measurements
-- from LibRangeCheck-3.0).
local INTERACT = { [3] = 8, [4] = 28 }
local INTERACT_BY_RACE = {
    Tauren = { [3] = 6, [4] = 25 },
    Scourge = { [3] = 7, [4] = 27 },
}

-- Probes answer true (in range), false (out of range) or nil (cannot tell).

local function SpellProbe(spellID, unit)
    return Plain(C_Spell.IsSpellInRange(spellID, unit))
end

-- Many listed items answer nil on WoW Forever, so an item only counts as a
-- working check once it has answered. The ones that did are kept in
-- db.knownItems, so the check distances are known from login on.
local function ItemProbe(itemID, unit)
    local inRange = Plain(C_Item.IsItemInRange(itemID, unit))
    if inRange ~= nil and not ns.db.knownItems[itemID] then
        ns.db.knownItems[itemID] = true
        ns.Colors.OnChecksChanged()
    end
    return inRange
end

-- The real melee check, for the current target: the ACTION_RANGE_CHECK_UPDATE
-- event of the melee abilities on the action bars, which is what turns their
-- buttons red. Melee reach is not a fixed 5 yards: it grows with the size of
-- both models and while both are moving (max(5, reach + reach + 4/3), +8/3
-- when moving). The event only covers the target; other units keep the fixed
-- 5 yard checks of the same slot.
--
-- Not every melee ability answers right. Measured in game (2026-10-03,
-- /npd melee): Raptor Strike, which only changes the next swing (its button
-- never turns red), says "in range" at 20 yards, to the event and to
-- C_ActionBar.IsActionInRange and C_Spell.IsSpellInRange alike, yet it once
-- said "out of range" on a living enemy. Mongoose Bite, Wing Clip and
-- Disengage say "out of range" past melee and "in range" in it. So:
--   * every melee button is watched, and one counts (trusted) once it has
--     said both: one stuck on a single answer never does;
--   * the target is in melee only when every trusted button says so: they
--     all share the melee reach, so one "out of range" wins;
--   * no "in range" is believed while the 8 yard interaction check says the
--     target is farther, for a character whose only trusted button is wrong.
local MELEE_RANGE = 5
-- Past the slots of the gamepad bars, which start at 181 on WoW Forever.
local MAX_ACTION_SLOT = 1000
local INTERACT_NEAR = 3      -- CheckInteractDistance index: 8 yards

-- The melee buttons watched, in the order they are asked: abilities before
-- Attack, then by slot. As { slot, spellID, name, autoAttack }.
local meleeActions = {}
-- [slot] = { spellID, inRange (the event's last answer, or nil), sawIn, sawOut }
local meleeState = {}

local function InteractProbe(index, unit)
    local inRange = Plain(CheckInteractDistance(unit, index))
    if inRange ~= nil then
        return inRange and true or false
    end
end

local function Trusted(state)
    return state.sawIn and state.sawOut and state.inRange ~= nil
end

-- What the trusted buttons say about the target: true, false or nil (none
-- can tell), and true as the second value when the 8 yard check overruled
-- their "in range".
local function TargetMelee(unit)
    local answer
    for _, action in ipairs(meleeActions) do
        local state = meleeState[action.slot]
        if Trusted(state) then
            if not state.inRange then
                return false
            end
            answer = true
        end
    end
    if answer and InteractProbe(INTERACT_NEAR, unit) == false then
        return nil, true
    end
    return answer
end

local function TargetMeleeProbe(_, unit)
    if Plain(UnitIsUnit(unit, "target")) then
        return (TargetMelee(unit))
    end
end

-- Action slots up to lastSlot holding a melee ability with a range check, in
-- the order they are asked, as { slot, spellID, name, autoAttack }.
local function MeleeActions(lastSlot)
    local found = {}
    for slot = 1, lastSlot do
        local ok, has = pcall(C_ActionBar.HasAction, slot)
        if ok and Plain(has) then
            local actionType, id = GetActionInfo(slot)
            local spell = actionType == "spell" and id and C_Spell.GetSpellInfo(id)
            if spell then
                local autoAttack = Plain(C_Spell.IsAutoAttackSpell(id)) and true or false
                local melee = autoAttack
                    or ((Plain(spell.maxRange) or 0) <= MELEE_RANGE and Plain(C_Spell.IsSpellHarmful(id)))
                if melee and Plain(C_ActionBar.HasRangeRequirements(slot)) then
                    found[#found + 1] = { slot = slot, spellID = id, name = spell.name, autoAttack = autoAttack }
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.autoAttack ~= b.autoAttack then
            return b.autoAttack
        end
        return a.slot < b.slot
    end)
    return found
end

-- A slot is one distance with the probes that can test it, tried in order
-- until one answers. Only probes marked combatSafe are used in combat on
-- units the player cannot attack: items and interactions are restricted
-- there, the same rule LibRangeCheck-3.0 follows.
local slots, minSlots
-- Range of the ranged auto attack (Auto Shot, Shoot), with talents.
local shotRange
-- [category] = every spell with a range for it, as { spellID, name, minRange,
-- maxRange }: a slot holds a few probes only, and Colors needs them all.
local spellRanges
-- [unit GUID] = { [probe] = true } for the checks that have answered for it.
local answeredFor, answeredCount = {}, 0

local function AddProbe(list, maxRange, minRange, test, arg, combatSafe, label)
    local slot
    for _, candidate in ipairs(list) do
        if candidate.range == maxRange and candidate.minRange == minRange then
            slot = candidate
            break
        end
    end
    if not slot then
        slot = { range = maxRange, minRange = minRange }
        list[#list + 1] = slot
    end
    if #slot >= MAX_PROBES_PER_SLOT then
        return
    end
    for _, probe in ipairs(slot) do
        if probe.label == label then
            return -- another rank of the same spell
        end
    end
    slot[#slot + 1] = { test = test, arg = arg, combatSafe = combatSafe, label = label }
end

local function AddSpells()
    local bank = Enum.SpellBookSpellBank.Player
    local spellType = Enum.SpellBookItemType.Spell
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.offSpecID then
            for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                local spellID = item and item.itemType == spellType and not item.isPassive and not item.isOffSpec and item.spellID
                local spell = spellID and C_Spell.GetSpellInfo(spellID)
                local maxRange = spell and Plain(spell.maxRange)
                -- Melee abilities report 0-0: no distance to check (see the top).
                if maxRange and maxRange > 0 then
                    maxRange = math.floor(maxRange + 0.5)
                    local minRange = math.floor((Plain(spell.minRange) or 0) + 0.5)
                    local harmful = Plain(C_Spell.IsSpellHarmful(spellID))
                    local helpful = Plain(C_Spell.IsSpellHelpful(spellID))
                    if Plain(C_Spell.IsRangedAutoAttackSpell(spellID)) then
                        shotRange = { min = minRange, max = maxRange }
                    end
                    for category, usable in pairs({ hostile = harmful, friendly = helpful }) do
                        if usable then
                            local list = minRange > 0 and minSlots[category] or slots[category]
                            AddProbe(list, maxRange, minRange, SpellProbe, spellID, true, spell.name)
                            local known = spellRanges[category]
                            known[#known + 1] = { spellID = spellID, name = spell.name, minRange = minRange, maxRange = maxRange }
                        end
                    end
                end
            end
        end
    end
end

local function AddItems(category, items)
    for range, itemIDs in pairs(items) do
        for _, itemID in ipairs(itemIDs) do
            if C_Item.GetItemInfoInstant(itemID) then
                -- Range checks on an item only answer once its data is loaded.
                C_Item.RequestLoadItemDataByID(itemID)
                AddProbe(slots[category], range, 0, ItemProbe, itemID, false, L["item %d"]:format(itemID))
            end
        end
    end
end

local function AddInteractions()
    local _, race = UnitRace("player")
    local distances = INTERACT_BY_RACE[Plain(race)] or INTERACT
    for index, range in pairs(distances) do
        for _, category in ipairs(CATEGORIES) do
            AddProbe(slots[category], range, 0, InteractProbe, index, false, L["interaction %d"]:format(index))
        end
    end
end

local function AddMeleeActions()
    meleeActions = MeleeActions(MAX_ACTION_SLOT)
    -- A button keeps what it has said while it holds the same ability.
    local states, names, seen = {}, {}, {}
    for _, action in ipairs(meleeActions) do
        local state = meleeState[action.slot]
        if not state or state.spellID ~= action.spellID then
            state = { spellID = action.spellID }
            -- Only ever enabled: Blizzard's own buttons share the flag.
            pcall(C_ActionBar.EnableActionRangeCheck, action.slot, true)
        end
        states[action.slot] = state
        local name = action.name or "?"
        if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    meleeState = states
    if #meleeActions == 0 then
        return
    end
    local list = slots.hostile
    local melee
    for _, candidate in ipairs(list) do
        if candidate.range == MELEE_RANGE and candidate.minRange == 0 then
            melee = candidate
            break
        end
    end
    if not melee then
        melee = { range = MELEE_RANGE, minRange = 0 }
        list[#list + 1] = melee
    end
    -- First in its slot: it decides for the target and answers nothing for
    -- other units, which then go on to the fixed checks. Its nothing never
    -- means out of range (noMemory): a unit just stopped being the target.
    table.insert(melee, 1, {
        test = TargetMeleeProbe, combatSafe = true, noMemory = true,
        label = L["melee (%s)"]:format(table.concat(names, ", ")),
    })
end

local function ByRange(a, b)
    return a.range < b.range
end

function Range.Rebuild()
    slots, minSlots, shotRange, spellRanges = {}, {}, nil, {}
    -- The memory is keyed by the old checks.
    wipe(answeredFor)
    answeredCount = 0
    for _, category in ipairs(CATEGORIES) do
        slots[category], minSlots[category], spellRanges[category] = {}, {}, {}
    end
    AddSpells()
    AddItems("hostile", HOSTILE_ITEMS)
    AddItems("friendly", FRIENDLY_ITEMS)
    AddInteractions()
    AddMeleeActions()
    for _, category in ipairs(CATEGORIES) do
        table.sort(slots[category], ByRange)
        table.sort(minSlots[category], ByRange)
    end
end

-- Spells and interactions answer for the units they apply to; items only
-- once seen answering.
local function SlotWorks(slot)
    for _, probe in ipairs(slot) do
        if probe.test ~= ItemProbe or ns.db.knownItems[probe.arg] then
            return true
        end
    end
    return false
end

-- The distances at which the answers of the checks for this category change,
-- in order. The nameplate text can only change at these distances, so they are
-- the limits that give exact ranges.
function Range.GetMarks(category)
    local seen, marks = {}, {}
    local function Add(distance)
        if distance > 0 and not seen[distance] then
            seen[distance] = true
            marks[#marks + 1] = distance
        end
    end
    for _, slot in ipairs(slots and slots[category] or {}) do
        if SlotWorks(slot) then
            Add(slot.range)
        end
    end
    for _, slot in ipairs(minSlots and minSlots[category] or {}) do
        if SlotWorks(slot) then
            Add(slot.minRange)
            Add(slot.range)
        end
    end
    table.sort(marks)
    return marks
end

-- The longest range of the spells that check this category (past it the
-- player can cast nothing on the unit), or nil without such spells.
function Range.GetReach(category)
    local reach
    for _, list in ipairs({ slots and slots[category] or {}, minSlots and minSlots[category] or {} }) do
        for _, slot in ipairs(list) do
            for _, probe in ipairs(slot) do
                if probe.test == SpellProbe and (not reach or slot.range > reach) then
                    reach = slot.range
                end
            end
        end
    end
    return reach
end

-- Every spell with a range for this category (see spellRanges).
function Range.GetSpells(category)
    return spellRanges and spellRanges[category] or {}
end

-- Minimum and maximum range of the ranged auto attack, or nil without one.
function Range.GetShotRange()
    if shotRange then
        return shotRange.min, shotRange.max
    end
end

function Range.GetCategory(unit)
    if Plain(UnitCanAttack("player", unit)) then
        return "hostile"
    elseif Plain(UnitCanAssist("player", unit)) then
        return "friendly"
    end
    return "other"
end

-- Exact distance in yards; only answers for party and raid members.
function Range.GetExactDistance(unit)
    local distanceSquared, checked = UnitDistanceSquared(unit)
    distanceSquared, checked = Plain(distanceSquared), Plain(checked)
    if checked and distanceSquared then
        return math.sqrt(distanceSquared)
    end
end

-- Checks that have answered for a unit, by GUID. On WoW Forever a spell check
-- answers nothing, instead of false, once the unit is out of range (seen with
-- Fireball and Arcane Shot); nothing is also the answer when a check cannot
-- apply to the unit at all (Polymorph on an undead). A check that has
-- answered for this unit before does apply to it, so its nothing then means
-- out of range. LibRangeCheck-3.0 counts every nothing as out of range, which
-- the Polymorph case would get wrong. (answeredFor is declared at the top.)
local function Memory(unit)
    local guid = Plain(UnitGUID(unit))
    if not guid then
        return nil
    end
    local memory = answeredFor[guid]
    if not memory then
        if answeredCount >= 500 then
            wipe(answeredFor)
            answeredCount = 0
        end
        memory = {}
        answeredFor[guid] = memory
        answeredCount = answeredCount + 1
    end
    return memory
end

local function Test(slot, unit, restricted, memory)
    for i = 1, #slot do
        local probe = slot[i]
        if probe.combatSafe or not restricted then
            local inRange = probe.test(probe.arg, unit)
            if inRange ~= nil then
                if memory and not probe.noMemory then
                    memory[probe] = true
                end
                return inRange
            elseif memory and memory[probe] then
                return false
            end
        end
    end
end

-- Once a check has said in range, the longer ones are not needed for the
-- distance, but each is asked until it has answered once for this unit, so
-- that its nothing can be read when the unit moves away. Items that never
-- answered on this client are left out.
local function Learn(list, from, unit, restricted, memory)
    for i = from, #list do
        for _, probe in ipairs(list[i]) do
            if not memory[probe] and not probe.noMemory and (probe.combatSafe or not restricted)
                and (probe.test ~= ItemProbe or ns.db.knownItems[probe.arg]) then
                if probe.test(probe.arg, unit) ~= nil then
                    memory[probe] = true
                end
            end
        end
    end
end

local function IsRestricted(category)
    return category ~= "hostile" and InCombatLockdown()
end

-- Returns low, high in yards (high may be math.huge), or nil when no check
-- could answer for this unit.
function Range.GetRange(unit, category)
    local restricted = IsRestricted(category)
    local memory = Memory(unit)
    local low, high, answered = 0, INF, false

    -- Checks without a minimum range pass at every distance up to their
    -- range: the first one that passes caps the distance and the ones before
    -- it, which failed, set the floor.
    local list = slots[category]
    for index, slot in ipairs(list) do
        local inRange = Test(slot, unit, restricted, memory)
        if inRange then
            high, answered = slot.range, true
            if memory then
                Learn(list, index + 1, unit, restricted, memory)
            end
            break
        elseif inRange == false then
            low, answered = slot.range, true
        end
    end

    -- Checks with a minimum range (Auto Shot's 8-35, Charge's 8-25) only pass
    -- inside their band, which can narrow the bracket further.
    for _, slot in ipairs(minSlots[category]) do
        local inRange = Test(slot, unit, restricted, memory)
        if inRange then
            low, high, answered = math.max(low, slot.minRange), math.min(high, slot.range), true
        elseif inRange == false then
            if high <= slot.range then
                high, answered = math.min(high, slot.minRange), true
            elseif low >= slot.minRange then
                low, answered = math.max(low, slot.range), true
            end
        end
    end

    if not answered then
        return nil
    end
    return math.min(low, high), high
end

-- /npd check: which checks answer for the unit, and what they say.
function Range.Report(unit)
    if not Plain(UnitExists(unit)) then
        ns.Print(L["target something first."])
        return
    end
    local category = Range.GetCategory(unit)
    local restricted = IsRestricted(category)
    local memory = Memory(unit) or {}
    local categoryNames = { hostile = L["hostile unit"], friendly = L["friendly unit"], other = L["other unit"] }
    ns.Print("%s: %s, %s.", Plain(UnitName(unit)) or "?", categoryNames[category], InCombatLockdown() and L["in combat"] or L["out of combat"])
    for _, list in ipairs({ slots[category], minSlots[category] }) do
        for _, slot in ipairs(list) do
            local answers = {}
            for _, probe in ipairs(slot) do
                local answer = L["skipped in combat"]
                if probe.combatSafe or not restricted then
                    local ok, inRange = pcall(probe.test, probe.arg, unit)
                    answer = not ok and L["error"] or inRange and L["in range"] or inRange == false and L["out of range"]
                        or memory[probe] and L["no answer (out of range: it answered for this unit before)"] or L["no answer"]
                end
                answers[#answers + 1] = probe.label .. ": " .. answer
            end
            local range = slot.minRange > 0 and (slot.minRange .. "-" .. slot.range) or tostring(slot.range)
            ns.Print("  %s - %s", ns.Yards(range), table.concat(answers, ", "))
        end
    end
    ns.Print("  " .. L["the answers change at: %s"], ns.Yards(table.concat(Range.GetMarks(category), ", ")))
    local exact = Plain(UnitIsPlayer(unit)) and Range.GetExactDistance(unit)
    local low, high = Range.GetRange(unit, category)
    if exact then
        ns.Print("  " .. L["result: %s (group member); the nameplate shows %s"], ns.Yards(("%.1f"):format(exact)), (ns.FormatDistance(nil, nil, exact)))
    elseif low then
        local checks = high == INF and (low .. "+") or low == high and tostring(low) or (low .. "-" .. high)
        ns.Print("  " .. L["result: the checks say %s; the nameplate shows %s"], ns.Yards(checks), (ns.FormatDistance(low, high)))
    else
        ns.Print("  " .. L["result: no check answered for this unit."])
    end
end

-- /npd melee: a diagnostic, in English, of the melee range answers on WoW
-- Forever (it showed that Raptor Strike's cannot be used; see the melee check
-- above). A window shows, ready to copy, what each melee button on the
-- bars says about the target: the button's range event,
-- C_ActionBar.IsActionInRange and C_Spell.IsSpellInRange, also through the
-- target's nameplate token. "/npd melee log" records every range event until
-- it is run again, then opens the window.
local MAX_LOG_LINES = 300
local meleeEvents = {}       -- [slot] = the last ACTION_RANGE_CHECK_UPDATE for it
local meleeLog               -- the recorded lines, nil before any recording
local logStart               -- GetTime() when the recording began, while on

local function Show(value)
    if issecretvalue(value) then
        return "secret"
    end
    return tostring(value)
end

local function Ask(func, ...)
    if not func then
        return "missing"
    end
    local ok, value = pcall(func, ...)
    return ok and Show(value) or "error"
end

-- True while /npd melee log records and has room: the lines are only built
-- then, so the events cost nothing more the rest of the time.
local function Recording()
    return logStart ~= nil and #meleeLog < MAX_LOG_LINES
end

local function Record(text, ...)
    meleeLog[#meleeLog + 1] = ("%7.1f s  "):format(GetTime() - logStart) .. text:format(...)
end

-- The nameplate token of the target, or nil: whether the checks also answer
-- through it tells if other nameplates could get the real melee reach.
local function TargetPlateToken()
    for index = 1, 40 do
        local unit = "nameplate" .. index
        if Plain(UnitIsUnit(unit, "target")) then
            return unit
        end
    end
end

local function YesNo(value)
    return value and "yes" or "no"
end

-- The target's name, and whether it can be attacked and is dead: a button
-- may say "out of range" for a target it cannot be used on at all.
local function TargetInfo()
    return ("%s, attackable %s, dead %s"):format(Show(Plain(UnitName("target"))),
        Ask(UnitCanAttack, "player", "target"), Ask(UnitIsDead, "target"))
end

local function MeleeReportText()
    local lines = {}
    local function Add(text, ...)
        lines[#lines + 1] = select("#", ...) > 0 and text:format(...) or text
    end
    Add("Nameplate Distance - melee check, %s", date("%Y-%m-%d %H:%M:%S"))
    local trusted = {}
    for _, action in ipairs(meleeActions) do
        if Trusted(meleeState[action.slot]) then
            trusted[#trusted + 1] = ("slot %d %s"):format(action.slot, action.name or "?")
        end
    end
    if #trusted > 0 then
        local answer, overruled = TargetMelee("target")
        Add("Melee answer for the target: %s (trusted: %s).", overruled and "none, the 8 yd check says farther"
            or answer and "in range" or answer == false and "out of range" or "none", table.concat(trusted, ", "))
    else
        Add("Melee answer for the target: none yet (no button has said both in range and out of range).")
    end
    local token = TargetPlateToken()
    Add("Target: %s (%s). Within 8 yd (interaction 3): %s. Swing range: %s. Gamepad slots from: %s.",
        TargetInfo(), token or "no nameplate", Ask(CheckInteractDistance, "target", 3),
        Ask(C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange, 0),
        Ask(C_GamepadUI and C_GamepadUI.GetFirstGamepadActionStorageSlotIndex))
    Add("")
    Add("Melee buttons, in the order they are asked:")
    for _, action in ipairs(meleeActions) do
        local state, seen = meleeState[action.slot], meleeEvents[action.slot]
        local plate = token and ("; on %s: action %s, spell %s"):format(token,
            Ask(C_ActionBar.IsActionInRange, action.slot, token), Ask(C_Spell.IsSpellInRange, action.spellID, token)) or ""
        Add("  slot %d, %s%s%s: said in range %s, out of range %s%s; event %s; action %s; on target: action %s, spell %s%s",
            action.slot, action.name or "?", action.autoAttack and " (auto attack)" or "", Trusted(state) and " (trusted)" or "",
            YesNo(state.sawIn), YesNo(state.sawOut), state.outTarget and (" (first: " .. state.outTarget .. ")") or "",
            seen and ("in range %s, checks range %s, %.0f s ago, %d times"):format(Show(seen.inRange),
                Show(seen.checksRange), GetTime() - seen.time, seen.count) or "none yet",
            Ask(C_ActionBar.IsActionInRange, action.slot), Ask(C_ActionBar.IsActionInRange, action.slot, "target"),
            Ask(C_Spell.IsSpellInRange, action.spellID, "target"), plate)
    end
    if #meleeActions == 0 then
        Add("  none with a range check.")
    end
    Add("")
    if meleeLog then
        Add("Range events recorded%s:", logStart and " (still recording)" or "")
        for _, line in ipairs(meleeLog) do
            lines[#lines + 1] = "  " .. line
        end
        if #meleeLog == 0 then
            Add("  none")
        elseif #meleeLog >= MAX_LOG_LINES then
            Add("  (only the first %d kept)", MAX_LOG_LINES)
        end
    else
        Add("No range events recorded yet: /npd melee log, walk away from your target and back, then /npd melee log again.")
    end
    return table.concat(lines, "\n")
end

local reportWindow

-- A window with the text selected, to copy with Ctrl+C.
local function ShowReport(text)
    if not reportWindow then
        local window = CreateFrame("Frame", "NameplateDistanceReport", UIParent, "PortraitFrameTemplate")
        window:SetSize(680, 460)
        window:SetPoint("CENTER")
        window:SetFrameStrata("DIALOG")
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window:SetPortraitToAsset("Interface\\Icons\\Ability_MeleeDamage")
        window:SetTitle("Nameplate Distance - melee check")
        tinsert(UISpecialFrames, window:GetName())

        local hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        hint:SetPoint("TOPLEFT", 70, -36)
        hint:SetPoint("RIGHT", -20, 0)
        hint:SetJustifyH("LEFT")
        hint:SetText("Press Ctrl+A, then Ctrl+C, to copy the text.")

        local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -66)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(620)
        pcall(edit.SetMaxLetters, edit, 0)
        pcall(edit.SetMaxBytes, edit, 0)
        edit:SetScript("OnEscapePressed", function()
            window:Hide()
        end)
        scroll:SetScrollChild(edit)
        window.Edit = edit
        reportWindow = window
    end
    reportWindow.Edit:SetText(text)
    reportWindow:Show()
    reportWindow.Edit:SetFocus()
    reportWindow.Edit:HighlightText()
end

function Range.MeleeReport(option)
    if option == "log" then
        if logStart then
            logStart = nil
            ShowReport(MeleeReportText())
        else
            meleeLog, logStart = {}, GetTime()
            ns.Print("recording range events: walk away from your target and back, then /npd melee log again.")
        end
        return
    end
    ShowReport(MeleeReportText())
end

function Range.Init()
    -- The melee buttons' range, listened to before Rebuild enables it.
    -- Blizzard's buttons are updated only by this event, so it also fires when
    -- the target changes.
    local melee = CreateFrame("Frame")
    ns.RegisterEvents(melee, "ACTION_RANGE_CHECK_UPDATE", "PLAYER_TARGET_CHANGED")
    melee:SetScript("OnEvent", function(_, event, slot, inRange, checksRange)
        if event == "PLAYER_TARGET_CHANGED" then
            if Recording() then
                Record("target changed to %s", TargetInfo())
            end
            return
        end
        slot = Plain(slot)
        if not slot then
            return
        end
        local seen = meleeEvents[slot] or { count = 0 }
        meleeEvents[slot] = seen
        seen.inRange, seen.checksRange, seen.time, seen.count = inRange, checksRange, GetTime(), seen.count + 1
        if Recording() then
            Record("slot %d: in range %s, checks range %s", slot, Show(inRange), Show(checksRange))
        end
        local state = meleeState[slot]
        if state then
            checksRange, inRange = Plain(checksRange), Plain(inRange)
            if checksRange and inRange ~= nil then
                state.inRange = inRange and true or false
                if state.inRange then
                    state.sawIn = true
                elseif not state.sawOut then
                    state.sawOut = true
                    -- For /npd melee: the target of that first "out of range".
                    state.outTarget = TargetInfo()
                end
            else
                state.inRange = nil
            end
        end
    end)

    Range.Rebuild()
    -- Learning spells or changing talents changes the checks, and so does
    -- moving a melee ability on the action bars.
    local pending = false
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events, "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED",
        "ACTIONBAR_SLOT_CHANGED")
    events:SetScript("OnEvent", function()
        if pending then
            return
        end
        pending = true
        C_Timer.After(0.5, function()
            pending = false
            Range.Rebuild()
            ns.Colors.OnChecksChanged()
        end)
    end)
end
