-- Options.lua: the settings pages under Options > AddOns > Nameplate Distance.
local _, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local POINT_NAMES = {
    TOPLEFT = L["Top left"], TOP = L["Top"], TOPRIGHT = L["Top right"],
    LEFT = L["Left"], CENTER = L["Center"], RIGHT = L["Right"],
    BOTTOMLEFT = L["Bottom left"], BOTTOM = L["Bottom"], BOTTOMRIGHT = L["Bottom right"],
}
local COLOR_ROW_HEIGHT = 28

local refreshers = {}   -- functions that copy the settings into the widgets
local category

-- Replaced once the pages exist.
function Options.UpdatePreview() end

function Options.Refresh()
    for _, refresh in ipairs(refreshers) do
        refresh()
    end
    Options.UpdatePreview()
end

local function Set(key, value)
    ns.db[key] = value
    ns.SettingsChanged()
end

-- Buttons grow to fit their text, which is longer in some languages.
local function FitButton(button, minWidth)
    button:SetWidth(math.max(minWidth, math.ceil(button:GetFontString():GetStringWidth()) + 24))
end

local function SetTooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then
            GameTooltip:AddLine(text, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Widgets ---------------------------------------------------------------------

local function CreatePage(title, intro)
    local page = CreateFrame("Frame")
    page:Hide()
    local heading = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -16)
    heading:SetText(title)
    local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    text:SetWidth(620)
    text:SetJustifyH("LEFT")
    text:SetText(intro)
    page.intro = text
    -- Called by the settings panel whenever it shows the page.
    function page:OnRefresh()
        Options.Refresh()
    end
    return page
end

local function CreateHeader(page, text, x, y, width)
    local label = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetSize(width, 1)
    line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
end

local function CreateCheckbox(page, x, y, label, tooltip, get, set)
    local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", x, y)
    box.Text:SetFontObject("GameFontHighlight")
    box.Text:SetText(label)
    -- Clicking the label toggles the box too.
    box:SetHitRectInsets(0, -(box.Text:GetStringWidth() + 4), 0, 0)
    box:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    if tooltip then
        SetTooltip(box, label, tooltip)
    end
    refreshers[#refreshers + 1] = function()
        box:SetChecked(get())
    end
end

-- A checkbox bound to a boolean setting.
local function CreateOption(page, x, y, key, label, tooltip)
    CreateCheckbox(page, x, y, label, tooltip,
        function() return ns.db[key] end,
        function(value) Set(key, value) end)
end

local function CreateSlider(page, x, y, width, key, label, format)
    local low, high, step = unpack(ns.LIMITS[key])
    local slider = CreateFrame("Slider", nil, page, "UISliderTemplateWithLabels")
    slider:SetPoint("TOPLEFT", x, y)
    slider:SetSize(width, 17)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText(format(low))
    slider.High:SetText(format(high))
    local function ShowValue(value)
        slider.Text:SetText(("%s: |cffffffff%s|r"):format(label, format(value)))
    end
    slider:SetScript("OnValueChanged", function(_, value, userInput)
        value = ns.Snap(value, low, high, step)
        ShowValue(value)
        if userInput and value ~= ns.db[key] then
            Set(key, value)
        end
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        local value = ns.Snap(ns.db[key] + delta * step, low, high, step)
        if value ~= ns.db[key] then
            self:SetValue(value)
            Set(key, value)
        end
    end)
    refreshers[#refreshers + 1] = function()
        slider:SetValue(ns.db[key])
        ShowValue(ns.db[key])
    end
end

-- A label followed by radio buttons on one line.
local function CreateChoice(page, x, y, key, label, choices)
    local title = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(label)
    local buttons = {}
    local function Refresh()
        for _, button in ipairs(buttons) do
            button:SetChecked(ns.db[key] == button.value)
        end
    end
    for i, choice in ipairs(choices) do
        local button = CreateFrame("CheckButton", nil, page, "UIRadioButtonTemplate")
        if i == 1 then
            button:SetPoint("LEFT", title, "RIGHT", 10, 0)
        else
            button:SetPoint("LEFT", buttons[i - 1].text, "RIGHT", 14, 0)
        end
        button.text:SetFontObject("GameFontHighlightSmall")
        button.text:SetText(choice.text)
        button:SetHitRectInsets(0, -(button.text:GetStringWidth() + 5), 0, 0)
        button.value = choice.value
        button:SetScript("OnClick", function(self)
            Set(key, self.value)
            Refresh()
        end)
        if choice.tooltip then
            SetTooltip(button, choice.text, choice.tooltip)
        end
        buttons[i] = button
    end
    refreshers[#refreshers + 1] = Refresh
end

-- A 3x3 grid: which point of the health bar the text is attached to.
local function CreatePositionPicker(page, x, y)
    local picker = CreateFrame("Frame", nil, page)
    picker:SetPoint("TOPLEFT", x, y)
    picker:SetSize(66, 66)
    local buttons = {}
    local function Refresh()
        for _, button in ipairs(buttons) do
            if button.point == ns.db.anchor then
                button.dot:SetColorTexture(1, 0.82, 0, 1)
            else
                button.dot:SetColorTexture(0.45, 0.45, 0.45, 1)
            end
        end
    end
    for i, point in ipairs(POINTS) do
        local button = CreateFrame("Button", nil, picker)
        button:SetSize(20, 20)
        button:SetPoint("TOPLEFT", ((i - 1) % 3) * 23, -math.floor((i - 1) / 3) * 23)
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.5)
        button.dot = button:CreateTexture(nil, "ARTWORK")
        button.dot:SetSize(10, 10)
        button.dot:SetPoint("CENTER")
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.2)
        button.point = point
        button:SetScript("OnClick", function(self)
            Set("anchor", self.point)
            Refresh()
        end)
        SetTooltip(button, POINT_NAMES[point], L["Attach the distance to this point of the health bar."])
        buttons[i] = button
    end
    refreshers[#refreshers + 1] = Refresh
end

-- A mock nameplate showing the text as it will look. Returns the bar the text
-- is anchored to, the text itself and the unit's name.
local function CreatePreview(page, x, y)
    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", x, y)
    box:SetSize(230, 90)
    box:SetClipsChildren(true)
    local background = box:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.45)

    local bar = CreateFrame("Frame", nil, box)
    bar:SetSize(110, 11)
    bar:SetPoint("CENTER", 0, -6)
    local empty = bar:CreateTexture(nil, "BACKGROUND")
    empty:SetAllPoints()
    empty:SetColorTexture(0.12, 0.12, 0.12, 1)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetWidth(80)
    fill:SetColorTexture(0.8, 0.13, 0.1, 1)

    local name = box:CreateFontString(nil, "ARTWORK", "SystemFont_NamePlate")
    name:SetPoint("BOTTOM", bar, "TOP", 0, 3)
    name:SetText(L["Enemy"])

    return bar, box:CreateFontString(nil, "OVERLAY"), name
end

-- The section of rows the Colors page edits (see Colors.lua): the enemies'
-- rows, of a druid form for a druid, or those of friendly and neutral units.
local editFriendly = false
local editForm          -- the druid form edited; it follows the form in use

local function EditedSection()
    return editFriendly and ns.Colors.FRIENDLY or (editForm or ns.Colors.GetSet())
end

local function Edited()
    return ns.Colors.GetEntry(ns.Colors.GetKey(EditedSection()))
end

local function PickColor(color)
    if not ColorPickerFrame then
        C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame")
    end
    local entry = Edited()
    local r, g, b = color.r, color.g, color.b
    local wasAuto = entry.auto
    local function Apply(newR, newG, newB)
        local before = ns.ColorToHex(color)
        color.r, color.g, color.b = newR, newG, newB
        -- The picker also calls this when it opens, with the same color.
        if ns.ColorToHex(color) ~= before then
            entry.auto = false
        end
        ns.SettingsChanged()
        Options.Refresh()
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r,
        g = g,
        b = b,
        hasOpacity = false,
        swatchFunc = function()
            Apply(ColorPickerFrame:GetColorRGB())
        end,
        cancelFunc = function()
            Apply(r, g, b)
            entry.auto = wasAuto
            Options.Refresh()
        end,
    })
end

-- A color square; getColor returns the settings table ({ r, g, b }) it edits.
local function CreateSwatch(parent, getColor)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(22, 22)
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.75, 0.75, 0.75, 1)
    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local highlight = swatch:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.25)
    swatch:SetScript("OnClick", function()
        local color = getColor()
        if color then
            PickColor(color)
        end
    end)
    SetTooltip(swatch, L["Change color"])
    function swatch.Refresh()
        local color = getColor()
        if color then
            fill:SetColorTexture(color.r, color.g, color.b, 1)
        end
    end
    return swatch
end

-- Columns shared by the color rows and the "More than" row.
local SWATCH_X, REMOVE_X = 124, 160

local function CreateColorRow(page, index, top)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(400, 24)
    row:SetPoint("TOPLEFT", top, "TOPLEFT", 0, -(index - 1) * COLOR_ROW_HEIGHT)

    -- Where the row's range starts: 0, or the distance of the row above.
    local from = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    from:SetPoint("LEFT")
    from:SetWidth(40)
    from:SetJustifyH("RIGHT")

    local distance = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    distance:SetSize(36, 20)
    distance:SetPoint("LEFT", 52, 0)
    distance:SetAutoFocus(false)
    distance:SetNumeric(true)
    distance:SetMaxLetters(3)
    distance:SetJustifyH("CENTER")
    distance:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    distance:SetScript("OnEscapePressed", function(self)
        self.cancelled = true
        self:ClearFocus()
    end)
    distance:HookScript("OnEditFocusLost", function(self)
        local entry = Edited()
        local color, value = entry.colors[index], tonumber(self:GetText())
        if color and value and value >= 1 and value ~= color.distance and not self.cancelled then
            color.distance = value
            entry.auto = false
            ns.SortColors(entry.colors)
            ns.SettingsChanged()
        end
        self.cancelled = nil
        Options.Refresh()
    end)

    local yards = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    yards:SetPoint("LEFT", distance, "RIGHT", 6, 0)
    yards:SetText(L["yd"])

    local swatch = CreateSwatch(row, function() return Edited().colors[index] end)
    swatch:SetPoint("LEFT", SWATCH_X, 0)

    local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    remove:SetSize(80, 22)
    remove:SetPoint("LEFT", REMOVE_X, 0)
    remove:SetText(L["Remove"])
    FitButton(remove, 80)
    remove:SetScript("OnClick", function()
        local entry = Edited()
        table.remove(entry.colors, index)
        entry.auto = false
        ns.SettingsChanged()
        Options.Refresh()
    end)

    -- A limit the range checks cannot tell apart makes the nameplate join
    -- this row with its neighbour.
    local warning = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    warning:SetPoint("LEFT", remove, "RIGHT", 10, 0)
    warning:SetTextColor(1, 0.5, 0.2)
    warning:SetText(L["not a check distance"])

    function row.Refresh(isMark)
        local colors = Edited().colors
        local color, above = colors[index], colors[index - 1]
        row:SetShown(color ~= nil)
        if color then
            from:SetText((above and above.distance or 0) .. " -")
            if not distance:HasFocus() then
                distance:SetText(tostring(color.distance))
            end
            swatch.Refresh()
            warning:SetShown(not isMark[color.distance])
        end
    end
    return row
end

-- Pages -----------------------------------------------------------------------

StaticPopupDialogs.NAMEPLATEDISTANCE_RESET = {
    text = L["Reset all Nameplate Distance settings to their defaults?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ns.ResetSettings()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function CreateMainPage()
    local page = CreatePage("Nameplate Distance",
        L["Shows how far away each unit is on its nameplate. The game only tells addons whether a unit is in range of your spells, some items and interactions, so the distance is usually a range such as 20-25 yards. Party and raid members get an exact number."])

    CreateHeader(page, L["Position"], 16, -92, 300)
    local previewBar, previewText, previewName = CreatePreview(page, 16, -114)
    CreatePositionPicker(page, 256, -126)
    CreateOption(page, 12, -210, "inside", L["Inside the health bar"],
        L["Put the text inside the health bar, aligned to the chosen point, instead of next to it."])
    CreateSlider(page, 20, -260, 280, "offsetX", L["Horizontal offset"], tostring)
    CreateSlider(page, 20, -310, 280, "offsetY", L["Vertical offset"], tostring)

    CreateHeader(page, L["Text"], 340, -92, 300)
    CreateOption(page, 336, -110, "showText", L["Show the distance text"],
        L["Untick to show no numbers, for example to show the distance only through the color of the unit's name."])
    CreateSlider(page, 344, -152, 280, "fontSize", L["Font size"], tostring)
    CreateChoice(page, 340, -188, "outline", L["Outline:"], {
        { value = "", text = L["None"] },
        { value = "OUTLINE", text = L["Thin"] },
        { value = "THICKOUTLINE", text = L["Thick"] },
    })
    CreateChoice(page, 340, -212, "format", L["Show:"], {
        { value = "bands", text = L["Color ranges"],
          tooltip = L["The ranges on the Colors page. They are set up from the distances your range checks can tell apart, so they are exact; a limit you move between two of those distances makes the neighbouring ranges show joined."] },
        { value = "range", text = "20-25", tooltip = L["The whole range your range checks give."] },
        { value = "max", text = "25", tooltip = L["Only the upper end: the unit is at most this far away."] },
        { value = "mid", text = "~23", tooltip = L["The middle of the range, as an estimate."] },
    })
    CreateOption(page, 336, -232, "showUnit", L["Add \"%s\" after the number"]:format(L["yd"]))

    CreateHeader(page, L["Updates"], 340, -268, 300)
    CreateSlider(page, 344, -306, 280, "interval", L["Update every"], function(value)
        return L["%.2f s"]:format(value)
    end)

    CreateHeader(page, L["Show and color"], 16, -352, 624)
    CreateOption(page, 12, -374, "showEnemies", L["Enemies"], L["Units you can attack."])
    CreateOption(page, 336, -374, "showFriendly", L["Friendly and neutral units"], L["Players and NPCs you cannot attack."])
    CreateOption(page, 12, -400, "onlyTarget", L["Only my current target"])
    CreateOption(page, 336, -400, "hideBeyond", L["Hide \"more than\" distances (such as 41+)"],
        L["Hide the text when the unit is farther than your longest range check or, with \"%s\", farther than the last color row."]:format(L["Color ranges"]))
    CreateOption(page, 12, -426, "colorText", L["Color the distance text"], L["Untick for white numbers."])
    CreateOption(page, 336, -426, "colorName", L["Color the unit's name"],
        L["The name on Blizzard's nameplates takes the distance color, instead of Blizzard's own colors (class, reaction, tapped, mouseover). Friendly nameplates inside dungeons and raids are closed to addons, so their names keep their color."])

    -- The game's own name for the action bars, in the client's language.
    CreateHeader(page, ACTIONBARS_LABEL or "Action Bars", 16, -464, 624)
    CreateOption(page, 12, -486, "mouseoverIcon", L["Mouseover range icon"],
        L["Action buttons with a key bound show a small mouse icon in their lower left corner while the mouse is over a unit: in the key's color when the unit is within that ability's range, red when it is not, as the key turns red for your target."])

    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetSize(160, 22)
    reset:SetPoint("TOPLEFT", 16, -530)
    reset:SetText(L["Reset all settings"])
    FitButton(reset, 160)
    reset:SetScript("OnClick", function()
        StaticPopup_Show("NAMEPLATEDISTANCE_RESET")
    end)

    -- The settings panel's Defaults button.
    function page:OnDefault()
        ns.ResetSettings()
    end

    return page, previewBar, previewText, previewName
end

-- A label followed by radio buttons, on a line below anchor; get returns the
-- chosen value and set changes it. Returns the line, for what comes below.
local function CreateSelector(page, anchor, label, choices, get, set)
    local line = CreateFrame("Frame", nil, page)
    line:SetSize(620, 20)
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    local title = line:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("LEFT")
    title:SetText(label)
    local buttons = {}
    for i, choice in ipairs(choices) do
        local button = CreateFrame("CheckButton", nil, line, "UIRadioButtonTemplate")
        if i == 1 then
            button:SetPoint("LEFT", title, "RIGHT", 10, 0)
        else
            button:SetPoint("LEFT", buttons[i - 1].text, "RIGHT", 14, 0)
        end
        button.text:SetFontObject("GameFontHighlightSmall")
        button.text:SetText(choice.text)
        button:SetHitRectInsets(0, -(button.text:GetStringWidth() + 5), 0, 0)
        button.value = choice.value
        button:SetScript("OnClick", function(self)
            set(self.value)
            Options.Refresh()
        end)
        buttons[i] = button
    end
    refreshers[#refreshers + 1] = function()
        for _, button in ipairs(buttons) do
            button:SetChecked(get() == button.value)
        end
    end
    return line
end

local INTRO = L["Each character has its own rows, set up from its class and from the distances at which its range checks change answer, which include its talents; the nameplates show exactly these ranges. Enemies and friendly units have rows of their own."]
local ENEMIES_INTRO = L["Hunters: green in melee range, red in the dead zone and past the shooting range, green in the middle of it, grey past Hunter's Mark. Warriors, rogues, and druids in cat or bear form, each form with its own rows: green in melee range; with a charge, red up to its minimum range and light green within its range; then yellow to orange up to their longest ability, red past it. Other classes: green up close to red past their longest spell."]
local FRIENDLY_INTRO = L["Friendly and neutral units: green up close to red past your longest helpful spell, or past your farthest check if you have none."]

local function CreateColorsPage()
    local page = CreatePage(L["Colors by distance"], INTRO)
    local forms = ns.Colors.GetForms()

    -- The druid form edited follows the form in use, until another is picked.
    local seenSet
    refreshers[#refreshers + 1] = function()
        local set = ns.Colors.GetSet()
        if set ~= seenSet then
            seenSet, editForm = set, set
        end
    end

    local kindLine = CreateSelector(page, page.intro, L["Colors for:"], {
        { value = false, text = L["Enemies"] },
        { value = true, text = L["Friendly and neutral units"] },
    }, function() return editFriendly end, function(value) editFriendly = value end)

    local formLine
    if forms then
        local choices = {}
        for i, form in ipairs(forms) do
            choices[i] = { value = form.set, text = form.name }
        end
        formLine = CreateSelector(page, kindLine, L["Form:"], choices,
            function() return editForm end, function(value) editForm = value end)
    end

    local marksNote = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    marksNote:SetWidth(620)
    marksNote:SetJustifyH("LEFT")

    local status = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", marksNote, "BOTTOMLEFT", 0, -6)
    status:SetWidth(620)
    status:SetJustifyH("LEFT")

    -- The rows start below the texts, however long they are in each language.
    local top = CreateFrame("Frame", nil, page)
    top:SetSize(1, 1)
    top:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -10)

    local rows = {}
    for i = 1, ns.MAX_COLORS do
        rows[i] = CreateColorRow(page, i, top)
    end

    -- Everything past the last row, including ranges that end beyond it.
    local farRow = CreateFrame("Frame", nil, page)
    farRow:SetSize(400, 24)
    local farLabel = farRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    farLabel:SetPoint("LEFT", 8, 0)
    local farSwatch = CreateSwatch(farRow, function() return Edited().farColor end)
    farSwatch:SetPoint("LEFT", SWATCH_X, 0)

    local function Category()
        return editFriendly and "friendly" or "hostile"
    end

    local add = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    add:SetSize(120, 22)
    add:SetText(L["Add color"])
    FitButton(add, 120)
    add:SetScript("OnClick", function()
        local entry = Edited()
        local colors = entry.colors
        local lastDistance = colors[#colors] and colors[#colors].distance or 0
        -- The next check distance, so the new row gives exact ranges too.
        local distance = lastDistance + 5
        for _, mark in ipairs(ns.Range.GetMarks(Category())) do
            if mark > lastDistance then
                distance = mark
                break
            end
        end
        colors[#colors + 1] = { distance = math.min(distance, 999), r = 1, g = 1, b = 1 }
        entry.auto = false
        ns.SettingsChanged()
        Options.Refresh()
    end)

    local adjust = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    adjust:SetSize(150, 22)
    adjust:SetPoint("LEFT", add, "RIGHT", 10, 0)
    adjust:SetText(L["Reset these colors"])
    FitButton(adjust, 150)
    adjust:SetScript("OnClick", function()
        ns.Colors.Adjust(EditedSection())
    end)
    SetTooltip(adjust, L["Reset these colors"],
        L["Sets the rows up again from your class and your current range checks, which include your talents, replacing the ones you edited. From then on they follow new spells and talents by themselves."])

    local adjustAll = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    adjustAll:SetSize(150, 22)
    adjustAll:SetPoint("LEFT", adjust, "RIGHT", 10, 0)
    adjustAll:SetText(L["Reset all colors"])
    FitButton(adjustAll, 150)
    adjustAll:SetScript("OnClick", ns.Colors.AdjustAll)
    SetTooltip(adjustAll, L["Reset all colors"],
        L["Sets every row of this character up again from its class and its current range checks: enemies, friendly units and, for a druid, every form."])

    local examples = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    examples:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -20)
    examples:SetWidth(620)
    examples:SetJustifyH("LEFT")

    -- The settings panel's Defaults button.
    function page:OnDefault()
        ns.Colors.AdjustAll()
    end

    refreshers[#refreshers + 1] = function()
        local section = EditedSection()
        local entry = ns.Colors.GetRows(section)
        page.intro:SetText(INTRO .. " " .. (editFriendly and FRIENDLY_INTRO or ENEMIES_INTRO))
        -- The forms only apply to the enemies' rows.
        local showForms = formLine and not editFriendly
        if formLine then
            formLine:SetShown(showForms)
        end
        marksNote:ClearAllPoints()
        marksNote:SetPoint("TOPLEFT", showForms and formLine or kindLine, "BOTTOMLEFT", 0, -10)

        local colors, marks, isMark = entry.colors, ns.Range.GetMarks(Category()), {}
        for _, mark in ipairs(marks) do
            isMark[mark] = true
        end
        if #marks > 0 then
            local note = editFriendly and L["Your range checks on friendly units change answer at: %s."]
                or L["Your range checks on enemies change answer at: %s."]
            marksNote:SetText(note:format("|cffffffff" .. ns.Yards(table.concat(marks, ", ")) .. "|r"))
        else
            marksNote:SetText(L["No range checks found yet."])
        end
        local name, className = ns.Colors.GetOwner(section)
        if entry.auto then
            status:SetText(L["Rows for %s (%s), set up automatically: they follow new spells and talents until you edit one."]:format(name, className))
        else
            status:SetText(L["Rows for %s (%s), edited by you. \"%s\" sets them up again."]:format(name, className, L["Reset these colors"]))
        end
        for _, row in ipairs(rows) do
            row.Refresh(isMark)
        end
        local last = colors[#colors]
        farLabel:SetText(last and L["More than %s"]:format(ns.Yards(last.distance)) or L["Any distance"])
        farRow:ClearAllPoints()
        farRow:SetPoint("TOPLEFT", top, "TOPLEFT", 0, -#colors * COLOR_ROW_HEIGHT)
        farSwatch.Refresh()
        add:SetEnabled(#colors < ns.MAX_COLORS)
        add:ClearAllPoints()
        add:SetPoint("TOPLEFT", top, "TOPLEFT", 0, -(#colors + 1) * COLOR_ROW_HEIGHT - 10)
    end

    -- Each row's range written in its color, then the one past the last row.
    local function UpdateExamples()
        local entry = Edited()
        local colors, parts = entry.colors, {}
        for i, color in ipairs(colors) do
            local above = colors[i - 1]
            parts[#parts + 1] = ("|cff%s%d-%d|r"):format(ns.ColorToHex(color), above and above.distance or 0, color.distance)
        end
        local last = colors[#colors]
        parts[#parts + 1] = ("|cff%s%d+|r"):format(ns.ColorToHex(entry.farColor), last and last.distance or 0)
        examples:SetText(L["Examples:"] .. "  " .. table.concat(parts, "   "))
    end

    return page, UpdateExamples
end

-- Setup -----------------------------------------------------------------------

function Options.Init()
    local main, previewBar, previewText, previewName = CreateMainPage()
    local colors, updateExamples = CreateColorsPage()

    function Options.UpdatePreview()
        local db = ns.db
        ns.StyleText(previewText)
        ns.AnchorText(previewText, previewBar)
        local label, value = ns.FormatDistance(20, 25)
        local r, g, b = ns.GetDistanceColor(value)
        previewText:SetText(label)
        if db.colorText then
            previewText:SetTextColor(r, g, b)
        else
            previewText:SetTextColor(1, 1, 1)
        end
        previewText:SetShown(db.showText)
        if db.colorName then
            previewName:SetVertexColor(r, g, b)
        else
            previewName:SetVertexColor(1, 1, 1)
        end
        updateExamples()
    end

    category = Settings.RegisterCanvasLayoutCategory(main, "Nameplate Distance")
    Settings.RegisterCanvasLayoutSubcategory(category, colors, L["Colors"])
    Settings.RegisterAddOnCategory(category)
    Options.Refresh()
end

function Options.Open()
    -- Settings.OpenToCategory goes through a restricted call on this client, and
    -- the panel opens from an event, so success is checked a moment later.
    local ok = category and pcall(Settings.OpenToCategory, category:GetID())
    C_Timer.After(0.3, function()
        if not ok or not SettingsPanel:IsShown() then
            ns.Print(L["open the game menu, then Options > AddOns > Nameplate Distance."])
        end
    end)
end
