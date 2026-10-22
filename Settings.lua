local addonName = ...
local Addon = LH_TinyDPS
local variables = {}

function Addon:RefreshSettings()
    if self.notifying or not Settings or not Settings.NotifyUpdate then return end
    self.notifying = true
    for _, name in ipairs(variables) do Settings.NotifyUpdate(name) end
    self.notifying = false
end

local function Header(layout, title)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
end
local function Button(layout, label, text, callback, tooltip)
    layout:AddInitializer(CreateSettingsButtonInitializer(label, text, callback, tooltip, true))
end
local function Checkbox(category, key, label, help)
    local name = "LH_TinyDPS_" .. key
    variables[#variables + 1] = name
    local setting = Settings.RegisterProxySetting(category, name, "boolean", label, false,
        function() return Addon:Get(key) end,
        function(value) Addon:Set(key, value) end)
    Settings.CreateCheckbox(category, setting, help)
end
local function ChoiceCheckbox(category, key, label, getter, setter, help)
    local name = "LH_TinyDPS_" .. key
    variables[#variables + 1] = name
    local setting = Settings.RegisterProxySetting(category, name, "boolean", label, false, getter, setter)
    Settings.CreateCheckbox(category, setting, help)
end
local function Slider(category, key, label, low, high, step, help, format)
    local name = "LH_TinyDPS_" .. key
    variables[#variables + 1] = name
    local setting = Settings.RegisterProxySetting(category, name, "number", label, low,
        function() return Addon:Get(key) end,
        function(value) Addon:Set(key, value) end)
    local options = Settings.CreateSliderOptions(low, high, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
        format or function(value) return string.format("%.0f", value) end)
    Settings.CreateSlider(category, setting, options, help)
end
local function Build(category, layout)
    Header(layout, "Display")
    Checkbox(category, "enabled", "Show LH TinyDPS", "Use a separate compact window powered by the game's damage meter data. The Blizzard window is not modified.")
    Checkbox(category, "locked", "Lock window", "Unlock to left-drag the window or resize it using the small circle below its right edge.")
    Button(layout, "Window position", "Unlock", function() Addon:Set("locked", false) end,
        "Left-drag the window to move it; drag the circle to resize.")
    Button(layout, "Window position", "Lock", function() Addon:Set("locked", true) end,
        "Keep the current position and size.")
    local borderName = "LH_TinyDPS_borderStyle"
    variables[#variables + 1] = borderName
    local borderSetting = Settings.RegisterProxySetting(category, borderName, "string", "Window border", "thin",
        function() return Addon:Get("borderStyle") end,
        function(value) Addon:Set("borderStyle", value) end)
    local function BorderOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add("none", "No border", "Hide the window border.")
        container:Add("thin", "Thin (LH ExpBar)", "Use the muted gold border from LH ExpBar.")
        container:Add("standard", "Standard (Options)", "Use the game's standard Options dialog border.")
        return container:GetData()
    end
    Settings.CreateDropdown(category, borderSetting, BorderOptions,
        "Choose no border, the thin LH ExpBar border, or the standard Options dialog border.")
    Checkbox(category, "growUpwards", "Grow bars upwards", "Place the first result at the bottom of the window.")
    Slider(category, "width", "Window width", 130, 500, 5, "Width in UI units.")
    Slider(category, "height", "Window height", 60, 600, 1, "Height in UI units.")
    Slider(category, "barHeight", "Bar height", 10, 30, 1, "Height of each player row.")
    Slider(category, "barSpacing", "Bar spacing", 0, 8, 1, "Space between rows.")
    Slider(category, "visibleBars", "Maximum visible bars", 1, 40, 1, "The window can show fewer rows if it is too short. Mouse wheel scrolls the list.")
    Button(layout, "Position and size", "Reset layout", function() Addon:ResetLayout() end,
        "Restore the five-bar default size and anchor the window below LH Stats when available.")

    Header(layout, "View and numbers")
    Checkbox(category, "showRank", "Show rank", "Show the position to the left of the name.")
    Checkbox(category, "showSelfOnly", "Show only yourself", "Use the sole visible row for your own result, regardless of rank.")
    Checkbox(category, "automaticValues", "Automatic solo/group value", "Show DPS or HPS while solo and the share of group damage or healing in percent while grouped. Turn this off to use the custom choices below.")
    Checkbox(category, "showAmount", "Custom: total amount", "Show total damage or healing when automatic values are off.")
    Checkbox(category, "showRate", "Custom: amount per second", "Show DPS or HPS when automatic values are off.")
    Checkbox(category, "showPercent", "Custom: percent", "Show the share of total damage or healing when automatic values are off and values are readable.")
    Checkbox(category, "shortNumbers", "Short numbers", "Abbreviate large amounts.")
    ChoiceCheckbox(category, "healingMode", "Show healing instead of damage",
        function() return Addon:Get("mode") == "healing" end,
        function(value) Addon:Set("mode", value and "healing" or "damage") end,
        "Switch between damage and healing done.")
    ChoiceCheckbox(category, "currentSession", "Show current fight instead of overall",
        function() return Addon:Get("session") == "current" end,
        function(value) Addon:Set("session", value and "current" or "overall") end,
        "Use the current fight; turn off for the overall session. History buttons select earlier fights.")
    Button(layout, "Combat session", "Previous", function() Addon:CycleSession(-1) end,
        "Cycle through the client's available combat history.")
    Button(layout, "Combat session", "Next", function() Addon:CycleSession(1) end,
        "Cycle through the client's available combat history.")

    Header(layout, "Text and color")
    Slider(category, "textSize", "Text size", 7, 18, 1, "Font size in points.")
    Slider(category, "textOffset", "Text nudge", -5, 5, 1, "Shift row text up or down within each bar.")
    Slider(category, "font", "Font", 1, #Addon:GetFontNames(), 1,
        "Default, Arial Narrow, Morpheus, or Skurri.",
        function(value) return Addon:GetFontNames()[math.floor(value + 0.5)][1] end)
    Slider(category, "outline", "Text outline", 1, #Addon:GetOutlineNames(), 1,
        "None, thin, thick, or monochrome outline.",
        function(value) return Addon:GetOutlineNames()[math.floor(value + 0.5)] end)
    Checkbox(category, "classColors", "Class-colored bars", "Use source class colors where available.")
    Checkbox(category, "dimClassColors", "Dim class colors", "Reduce the brightness of class-colored bars.")
    Checkbox(category, "classText", "Class-colored names instead of bars", "Use class colors for names and the chosen bar color for bars. Rank and values keep the configured text color.")
    for _, group in ipairs({
        { title = "Bar text color", prefix = "text" },
        { title = "Bar text shadow", prefix = "shadow" },
        { title = "Window background", prefix = "background" },
        { title = "Bar color", prefix = "bar" },
        { title = "Thin border color", prefix = "border" },
    }) do
        Header(layout, group.title)
        for _, color in ipairs({ { "R", "Red" }, { "G", "Green" }, { "B", "Blue" } }) do
            Slider(category, group.prefix .. color[1], color[2], 0, 1, 0.05,
                "Color channel from 0 to 100 percent.", function(value) return string.format("%.0f%%", value * 100) end)
        end
        Slider(category, group.prefix .. "Alpha", group.prefix == "shadow" and "Shadow strength" or "Opacity", 0, 1, 0.05,
            "Opacity from 0 to 100 percent.", function(value) return string.format("%.0f%%", value * 100) end)
        if group.prefix == "shadow" then
            Slider(category, "shadowOffsetX", "Horizontal shadow offset", -4, 4, 1,
                "Move the bar text shadow left or right in UI units.")
            Slider(category, "shadowOffsetY", "Vertical shadow offset", -4, 4, 1,
                "Move the bar text shadow down or up in UI units.")
        end
    end

    Header(layout, "Visibility")
    Checkbox(category, "hideSolo", "Hide while solo", "Show only while in a group.")
    Checkbox(category, "hideCombat", "Hide in combat", "Hide while the player is in combat.")
    Checkbox(category, "hideOutOfCombat", "Hide outside combat", "Show only while the player is in combat.")
    Checkbox(category, "hidePvP", "Hide in battlegrounds and arenas", "Hide in PvP instances.")
    Checkbox(category, "hidePetBattle", "Hide in pet battles", "Hide during pet battles.")
    Checkbox(category, "minimapButton", "Show minimap button", "Left-click to toggle; right-click for settings; middle-click to reset data. Drag to move around the minimap.")

    Header(layout, "Details and reporting")
    Checkbox(category, "showTooltips", "Show row tooltips", "Show the full name and separate player and pet damage or healing, with ability amounts and percentages.")
    Slider(category, "tooltipSpells", "Tooltip spells", 0, 20, 1, "Maximum abilities shown for the player and for each pet.")
    Slider(category, "tooltipTargets", "Targets per spell", 0, 20, 1, "Maximum targets listed under each spell.")
    Checkbox(category, "resetOnNewGroup", "Reset on new group", "Clear all game combat sessions when joining a new group.")
    Slider(category, "reportLength", "Report length", 1, 20, 1, "Maximum sources included in a chat report.")
    Button(layout, "Report", "Say", function() Addon:Report("SAY") end, "Send the current view to nearby chat.")
    Button(layout, "Report", "Party", function() Addon:Report("PARTY") end, "Send the current view to party chat.")
    Button(layout, "Report", "Raid", function() Addon:Report("RAID") end, "Send the current view to raid chat.")
    Button(layout, "Report", "Instance", function() Addon:Report("INSTANCE") end, "Send the current view to instance chat.")
    Button(layout, "Report", "Guild", function() Addon:Report("GUILD") end, "Send the current view to guild chat.")
    Button(layout, "Report", "Officer", function() Addon:Report("OFFICER") end, "Send the current view to officer chat.")
    Button(layout, "Combat data", "Reset all", function() Addon:ResetData() end,
        "Clear all sessions collected by the game's damage meter, including data visible in Blizzard's own window.")

    Header(layout, "Defaults")
    Button(layout, "All LH TinyDPS settings", "Restore defaults", function() Addon:ResetDefaults() end,
        "Restore the LH TinyDPS window, appearance, visibility and reporting defaults.")
    EventRegistry:RegisterCallback("Settings.CategoryDefaulted", function(_, selected)
        if selected == category then Addon:ResetDefaults() end
    end, Addon)
    EventRegistry:RegisterCallback("Settings.Defaulted", function() Addon:ResetDefaults() end, Addon)
end

LH_Tweaks:RegisterModule(addonName, "LH TinyDPS", Build)
