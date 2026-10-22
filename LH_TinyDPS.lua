local ADDON_NAME = ...
local Addon = {}
LH_TinyDPS = Addon

local panelR, panelG, panelB, panelA = 0.122, 0.118, 0.129, 0.8
if PANEL_BACKGROUND_COLOR then
    panelR, panelG, panelB, panelA = PANEL_BACKGROUND_COLOR:GetRGBA()
end

local defaults = {
    enabled = true, mode = "damage", session = "overall", width = 190, height = 113,
    barHeight = 16, barSpacing = 1, visibleBars = 5, textSize = 10, textOffset = 0,
    showRank = false, showAmount = false, showRate = false, showPercent = true, showSelfOnly = false,
    automaticValues = true,
    shortNumbers = true, classColors = true, dimClassColors = false,
    classText = false, growUpwards = false, locked = true, borderStyle = "thin",
    hideSolo = false, hideCombat = false, hideOutOfCombat = false,
    hidePvP = false, hidePetBattle = false, minimapButton = false,
    showTooltips = true, tooltipSpells = 5, tooltipTargets = 5,
    resetOnNewGroup = false, reportLength = 5, font = 1, outline = 2,
    backgroundAlpha = panelA, barAlpha = 0.9, borderAlpha = 1,
    backgroundR = panelR, backgroundG = panelG, backgroundB = panelB,
    barR = 0.3, barG = 0.55, barB = 0.8,
    borderR = 0.65, borderG = 0.59, borderB = 0.45,
    minimapAngle = 225,
}

local fonts = {
    { "Default", STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Morpheus", "Fonts\\MORPHEUS.TTF" },
    { "Skurri", "Fonts\\SKURRI.TTF" },
}
local outlines = { "", "OUTLINE", "THICKOUTLINE", "MONOCHROME,OUTLINE" }
local rows = {}
local frame, minimapButton, resizeHandle, notice, modeButton, standardBorder
local currentSources, currentSession, currentMax = {}, nil, 0
local selectedSessionID, scrollOffset, moving, sizing = nil, 0, nil, nil
local initialized, pendingRefresh = false, false
local groupState
local RequestRefresh

local function DB() return LH_TinyDPSDB end
local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end
local function Announce(message) print("LH_TinyDPS: " .. message) end
local function Notify()
    if Addon.RefreshSettings then Addon:RefreshSettings() end
end
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end
local function Short(value)
    if value == nil then return "0" end
    if DB().shortNumbers and AbbreviateLargeNumbers then
        return AbbreviateLargeNumbers(value)
    end
    return tostring(math.floor(value + 0.5))
end
local function Exact(value)
    local rounded = math.floor((value or 0) + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(rounded) or tostring(rounded)
end
local function TypeID()
    return DB().mode == "healing" and Enum.DamageMeterType.HealingDone or Enum.DamageMeterType.DamageDone
end
local function SessionID()
    local sessions = C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetAvailableCombatSessions() or {}
    for _, session in ipairs(sessions) do
        if session.sessionID == selectedSessionID then return selectedSessionID end
    end
    selectedSessionID = nil
end
local function GetSession()
    if not C_DamageMeter then return nil end
    if DB().session == "history" and SessionID() and C_DamageMeter.GetCombatSessionFromID then
        return C_DamageMeter.GetCombatSessionFromID(selectedSessionID, TypeID())
    end
    if C_DamageMeter.GetCombatSessionFromType then
        local kind = DB().session == "current" and Enum.DamageMeterSessionType.Current or Enum.DamageMeterSessionType.Overall
        return C_DamageMeter.GetCombatSessionFromType(kind, TypeID())
    end
end
local function SetFont(fontString)
    fontString:SetFont(fonts[DB().font][2], DB().textSize, outlines[DB().outline])
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(2, -2)
end
local function SavePosition()
    local x, y = frame:GetCenter()
    if not x or not y then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    DB().position = { x = x * scale, y = y * scale }
end
local function Place()
    frame:ClearAllPoints()
    local p = DB().position
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    elseif LH_StatsFrame then
        frame:SetPoint("TOP", LH_StatsFrame, "BOTTOM", 0, -16)
    else
        frame:SetPoint("TOPRIGHT", Minimap or UIParent, "BOTTOMRIGHT", 0, -12)
    end
end
local function StopMoving()
    if moving then
        frame:StopMovingOrSizing()
        moving = nil
        SavePosition()
        Place()
    end
end
local function StopSizing()
    if sizing then
        sizing = nil
        DB().width, DB().height = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
        SavePosition()
        Place()
        Notify()
    end
end
local function InPvP()
    local _, instanceType = IsInInstance()
    return instanceType == "pvp" or instanceType == "arena"
end
local function Visible()
    local db = DB()
    if not db.enabled then return false end
    if db.hideSolo and not IsInGroup() then return false end
    if db.hidePvP and InPvP() then return false end
    if db.hidePetBattle and C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return false end
    local combat = UnitAffectingCombat("player")
    if db.hideCombat and combat then return false end
    if db.hideOutOfCombat and not combat then return false end
    return true
end
local function UpdateVisibility()
    if not frame then return end
    frame:SetShown(Visible())
    if minimapButton then minimapButton:SetShown(DB().minimapButton) end
end
local function ClassColor(source)
    if source.classFilename then
        local c = RAID_CLASS_COLORS[source.classFilename]
        if c then
            local factor = DB().dimClassColors and 0.65 or 1
            return c.r * factor, c.g * factor, c.b * factor
        end
    end
end
local function ShortName(name)
    if IsSecret(name) then return name end
    return name:match("^([^%s%-]+)") or name
end
local function RowValue(source)
    local db = DB()
    if db.automaticValues then
        if IsInGroup() then
            local total = currentSession and currentSession.totalAmount
            if IsSecret(total) or IsSecret(source.totalAmount) then return "—" end
            return total and total > 0 and string.format("%.0f%%", source.totalAmount / total * 100) or "0%"
        end
        if IsSecret(source.amountPerSecond) then return AbbreviateLargeNumbers(source.amountPerSecond) end
        return Short(source.amountPerSecond) .. "/s"
    end
    if IsSecret(source.totalAmount) and db.showAmount then
        return AbbreviateLargeNumbers(source.totalAmount)
    end
    if IsSecret(source.amountPerSecond) and db.showRate then
        return AbbreviateLargeNumbers(source.amountPerSecond)
    end
    local pieces = {}
    local safeTotal = not IsSecret(currentSession and currentSession.totalAmount) and currentSession and currentSession.totalAmount or nil
    local safeValue = not IsSecret(source.totalAmount) and source.totalAmount or nil
    if db.showAmount then
        pieces[#pieces + 1] = (db.shortNumbers or safeValue) and Short(source.totalAmount) or "—"
    end
    if db.showRate then
        local value = source.amountPerSecond
        pieces[#pieces + 1] = (db.shortNumbers or not IsSecret(value)) and (Short(value) .. "/s") or "—/s"
    end
    if db.showPercent and safeTotal and safeTotal > 0 and safeValue then
        pieces[#pieces + 1] = string.format("%.0f%%", safeValue / safeTotal * 100)
    end
    return table.concat(pieces, "  ")
end
local function ShowTooltip(row)
    if not DB().showTooltips or not row.source then return end
    local source = row.source
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if UnitAffectingCombat("player") or IsSecret(source.sourceGUID) or IsSecret(source.totalAmount) then
        GameTooltip:AddLine(source.name, 1, 0.85, 0.35)
        GameTooltip:AddLine("Spell details are available after combat.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(source.name, 1, 0.85, 0.35)
    GameTooltip:AddDoubleLine("Total (including pets)", Exact(source.totalAmount), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(DB().mode == "healing" and "HPS" or "DPS",
        Short(source.amountPerSecond), 0.75, 0.75, 0.75, 1, 1, 1)
    if C_DamageMeter then
        local kind = DB().session == "current" and Enum.DamageMeterSessionType.Current or Enum.DamageMeterSessionType.Overall
        local details
        if DB().session == "history" and selectedSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            details = C_DamageMeter.GetCombatSessionSourceFromID(selectedSessionID, TypeID(), source.sourceGUID, source.sourceCreatureID)
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            details = C_DamageMeter.GetCombatSessionSourceFromType(kind, TypeID(), source.sourceGUID, source.sourceCreatureID)
        end
        if details and details.combatSpells then
            local sections = { { name = source.name, total = 0, spells = {} } }
            local petSections = {}
            for _, spell in ipairs(details.combatSpells) do
                local petName = spell.creatureName
                local section = sections[1]
                if petName and petName ~= "" then
                    section = petSections[petName]
                    if not section then
                        section = { name = petName, total = 0, spells = {}, pet = true }
                        petSections[petName] = section
                        sections[#sections + 1] = section
                    end
                end
                section.total = section.total + spell.totalAmount
                section.spells[#section.spells + 1] = spell
            end
            table.sort(sections, function(a, b)
                if a.pet ~= b.pet then return not a.pet end
                return a.total > b.total
            end)
            for _, section in ipairs(sections) do
                if section.total > 0 then
                    local sectionShare = source.totalAmount > 0 and section.total / source.totalAmount * 100 or 0
                    GameTooltip:AddDoubleLine(section.pet and ("Pet: " .. section.name)
                        or ("Player: " .. ShortName(source.name)),
                        string.format("%s  (%.1f%%)", Exact(section.total), sectionShare), 1, 0.82, 0, 1, 0.82, 0)
                    table.sort(section.spells, function(a, b) return a.totalAmount > b.totalAmount end)
                    for i = 1, math.min(DB().tooltipSpells, #section.spells) do
                        local spell = section.spells[i]
                        local name = spell.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.spellID) or (spell.spellID and GetSpellInfo and GetSpellInfo(spell.spellID)) or "Spell"
                        local share = source.totalAmount > 0 and spell.totalAmount / source.totalAmount * 100 or 0
                        GameTooltip:AddDoubleLine("  " .. (name or "Spell"),
                            string.format("%s  (%.1f%%)", Exact(spell.totalAmount), share), 0.8, 0.8, 0.8, 1, 1, 1)
                        if spell.combatSpellDetails then
                            for j = 1, math.min(DB().tooltipTargets, #spell.combatSpellDetails) do
                                local target = spell.combatSpellDetails[j]
                                GameTooltip:AddDoubleLine("    " .. (target.unitName or "Target"), Short(target.amount),
                                    0.65, 0.65, 0.65, 0.8, 0.8, 0.8)
                            end
                        end
                    end
                end
            end
        end
    end
    GameTooltip:Show()
end
local function CreateRow(index)
    local row = CreateFrame("Button", nil, frame)
    row.index = index
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetAllPoints()
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(0)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)
    row.rank = row.bar:CreateFontString(nil, "OVERLAY")
    row.rank:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.rank:SetWidth(20)
    row.rank:SetJustifyH("LEFT")
    row.name = row.bar:CreateFontString(nil, "OVERLAY")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row, "CENTER", 0, 0)
    row.name:SetJustifyH("LEFT")
    row.value = row.bar:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("LEFT", row, "CENTER", 0, 0)
    row.value:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.value:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        if DB().locked or sizing then return end
        moving = true
        frame:StartMoving()
    end)
    row:SetScript("OnDragStop", StopMoving)
    row:SetScript("OnHide", StopMoving)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Addon:OpenSettings()
        elseif button == "MiddleButton" then Addon:ResetData()
        elseif button == "Button4" then Addon:CycleSession(-1)
        elseif button == "Button5" then Addon:CycleSession(1) end
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        scrollOffset = Clamp(scrollOffset - delta, 0, math.max(0, #currentSources - DB().visibleBars))
        RequestRefresh()
    end)
    row:Hide()
    rows[index] = row
    return row
end
local function Layout()
    if not frame then return end
    local db = DB()
    frame:SetSize(db.width, db.height)
    frame:SetBackdropColor(db.backgroundR, db.backgroundG, db.backgroundB, db.backgroundAlpha)
    frame:SetBackdropBorderColor(db.borderR, db.borderG, db.borderB, db.borderStyle == "thin" and db.borderAlpha or 0)
    standardBorder:SetSize(db.width * 2, db.height * 2)
    standardBorder:SetShown(db.borderStyle == "standard")
    standardBorder:SetAlpha(db.borderAlpha)
    local slots = math.min(db.visibleBars, math.max(1, math.floor((db.height - 28) / (db.barHeight + db.barSpacing))))
    for i = 1, math.max(slots, #rows) do
        local row = rows[i] or (i <= slots and CreateRow(i))
        if row then
            row:SetSize(db.width - 8, db.barHeight)
            row:ClearAllPoints()
            if db.growUpwards then
                row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 5 + (i - 1) * (db.barHeight + db.barSpacing))
            else
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -24 - (i - 1) * (db.barHeight + db.barSpacing))
            end
            row.slotShown = i <= slots
            row.rank:ClearAllPoints()
            row.rank:SetPoint("LEFT", row, "LEFT", 4, db.textOffset)
            row.rank:SetShown(db.showRank)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row, "LEFT", db.showRank and 25 or 4, db.textOffset)
            row.name:SetPoint("RIGHT", row, "CENTER", 0, db.textOffset)
            row.value:ClearAllPoints()
            row.value:SetPoint("LEFT", row, "CENTER", 0, db.textOffset)
            row.value:SetPoint("RIGHT", row, "RIGHT", -4, db.textOffset)
            SetFont(row.rank)
            SetFont(row.name)
            SetFont(row.value)
            if not row.slotShown then row:Hide() end
        end
    end
    frame.title:SetFont(fonts[db.font][2], db.textSize + 1, outlines[db.outline])
    frame.title:SetShadowColor(0, 0, 0, 1)
    frame.title:SetShadowOffset(2, -2)
    resizeHandle:SetShown(not db.locked)
end
local function Refresh()
    if not initialized then return end
    pendingRefresh = false
    UpdateVisibility()
    if not frame:IsShown() then return end
    local label = DB().mode == "healing" and "Healing" or "Damage"
    local context = DB().session == "current" and "Current" or DB().session == "history" and "History" or "Overall"
    frame.title:SetText(label .. "  ·  " .. context)
    modeButton:SetText(DB().mode == "healing" and "Dmg" or "Heal")
    local available = C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable and C_DamageMeter.IsDamageMeterAvailable()
    if available == false then
        notice:SetText("Damage meter data unavailable")
        notice:Show()
        for _, row in ipairs(rows) do row:Hide() end
        return
    end
    currentSession = GetSession()
    currentSources = currentSession and currentSession.combatSources or {}
    currentMax = currentSession and currentSession.maxAmount or 0
    notice:SetShown(#currentSources == 0)
    if #currentSources == 0 then notice:SetText("No data") end
    local selfIndex
    if DB().showSelfOnly then
        for i, source in ipairs(currentSources) do
            if source.isLocalPlayer then selfIndex = i; break end
        end
    end
    for i, row in ipairs(rows) do
        local source = row.slotShown and (DB().showSelfOnly and i == 1 and selfIndex and currentSources[selfIndex]
            or (not DB().showSelfOnly and currentSources[i + scrollOffset])) or nil
        row.source = source
        row.index = DB().showSelfOnly and selfIndex or i + scrollOffset
        if source then
            row:Show()
            row.rank:SetText(tostring(row.index) .. ".")
            row.name:SetText(ShortName(source.name))
            row.value:SetText(RowValue(source))
            row.bar:SetMinMaxValues(0, currentMax)
            row.bar:SetValue(source.totalAmount)
            local cr, cg, cb = ClassColor(source)
            local r, g, b = DB().barR, DB().barG, DB().barB
            if DB().classColors and not DB().classText and cr then r, g, b = cr, cg, cb end
            row.bar:SetStatusBarColor(r, g, b, DB().barAlpha)
            if DB().classText and cr then row.name:SetTextColor(cr, cg, cb) else row.name:SetTextColor(1, 1, 1) end
        else
            row:Hide()
        end
    end
end
RequestRefresh = function()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0, Refresh)
end
local function UpdateMinimapButton()
    if not minimapButton then return end
    local angle = math.rad(DB().minimapAngle)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
    minimapButton:SetShown(DB().minimapButton)
end
local function CreateMinimapButton()
    if not Minimap then return end
    minimapButton = CreateFrame("Button", "LH_TinyDPSMinimapButton", Minimap)
    minimapButton:SetSize(30, 30)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetNormalTexture("Interface\\AddOns\\LH_Tweaks\\Icon.tga")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then Addon:Set("enabled", not DB().enabled)
        elseif button == "MiddleButton" then Addon:ResetData()
        else Addon:OpenSettings() end
    end)
    minimapButton:SetScript("OnDragStart", function(button) button:StartMoving() end)
    minimapButton:SetScript("OnDragStop", function(button)
        button:StopMovingOrSizing()
        local mx, my = Minimap:GetCenter()
        local bx, by = button:GetCenter()
        if mx and bx then
            local angle
            if math.atan2 or _G.atan2 then
                angle = math.deg((math.atan2 or _G.atan2)(by - my, bx - mx))
            else
                local dx, dy = bx - mx, by - my
                angle = math.deg(math.atan(dy / (dx == 0 and 0.0001 or dx)))
                if dx < 0 then angle = angle + 180 end
            end
            DB().minimapAngle = angle
            UpdateMinimapButton()
        end
    end)
    UpdateMinimapButton()
end
local function CreateWindow()
    frame = CreateFrame("Frame", "LH_TinyDPSFrame", UIParent, "BackdropTemplate")
    frame:SetSize(DB().width, DB().height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    standardBorder = CreateFrame("Frame", nil, frame)
    standardBorder:SetPoint("CENTER", frame, "CENTER")
    standardBorder:SetScale(0.5)
    standardBorder:SetFrameLevel(frame:GetFrameLevel() + 2)
    standardBorder:EnableMouse(false)
    NineSliceUtil.ApplyLayoutByName(standardBorder, "ButtonFrameTemplateNoPortrait")
    local titleLayer = CreateFrame("Frame", nil, frame)
    titleLayer:SetAllPoints()
    titleLayer:SetFrameLevel(frame:GetFrameLevel() + 3)
    titleLayer:EnableMouse(false)
    frame.title = titleLayer:CreateFontString(nil, "OVERLAY")
    frame.title:SetPoint("LEFT", frame, "TOPLEFT", 6, -11)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    local function HeaderButton(label, width, rightOffset, tooltip, onClick)
        local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
        button:SetSize(width, 16)
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", rightOffset, -4)
        button:SetFrameLevel(frame:GetFrameLevel() + 4)
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        button:SetBackdropColor(0.16, 0.16, 0.18, 0.9)
        button:SetBackdropBorderColor(0.45, 0.42, 0.35, 1)
        button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
        button:SetNormalFontObject("GameFontNormalSmall")
        button:SetText(label)
        button:SetScript("OnClick", onClick)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return button
    end
    local resetButton = HeaderButton("", 18, -5, "Clear all damage meter data and begin a fresh recording.",
        function() Addon:ResetData() end)
    resetButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    resetButton:SetBackdropColor(0.16, 0.16, 0.18, 0.9)
    local function CanPart(width, height, x, y)
        local part = resetButton:CreateTexture(nil, "ARTWORK")
        part:SetSize(width, height)
        part:SetPoint("CENTER", resetButton, "CENTER", x, y)
        part:SetColorTexture(1, 0.78, 0.12, 1)
    end
    CanPart(12, 2, 0, 5)
    CanPart(4, 2, 0, 7)
    CanPart(10, 9, 0, -1)
    for x = -2, 0, 2 do
        local slot = resetButton:CreateTexture(nil, "OVERLAY")
        slot:SetSize(1, 6)
        slot:SetPoint("CENTER", resetButton, "CENTER", x, -1)
        slot:SetColorTexture(0.32, 0.23, 0.04, 1)
    end
    modeButton = HeaderButton("Heal", 32, -26, "Switch between damage and healing.",
        function() Addon:Set("mode", DB().mode == "damage" and "healing" or "damage") end)
    frame.title:SetPoint("RIGHT", modeButton, "LEFT", -3, 0)
    notice = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notice:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame:SetScript("OnDragStart", function()
        if DB().locked or sizing then return end
        moving = true
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", StopMoving)
    frame:SetScript("OnHide", function() StopMoving(); StopSizing() end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        scrollOffset = Clamp(scrollOffset - delta, 0, math.max(0, #currentSources - DB().visibleBars))
        RequestRefresh()
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Addon:OpenSettings()
        elseif button == "MiddleButton" then Addon:ResetData()
        elseif button == "Button4" then Addon:CycleSession(-1)
        elseif button == "Button5" then Addon:CycleSession(1) end
    end)
    resizeHandle = CreateFrame("Button", "LH_TinyDPSResizeHandle", frame)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 10)
    resizeHandle:EnableMouse(true)
    local circle = resizeHandle:CreateTexture(nil, "ARTWORK")
    circle:SetAllPoints()
    circle:SetTexture("Interface\\Buttons\\UI-RadioButton")
    circle:SetTexCoord(0.25, 0.5, 0, 1)
    resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not DB().locked then
            StopMoving()
            local x, y = GetCursorPosition()
            local scale = frame:GetEffectiveScale()
            local parentScale = UIParent:GetEffectiveScale()
            local left, top = frame:GetLeft(), frame:GetTop()
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale / parentScale, top * scale / parentScale)
            sizing = { x = x / scale, y = y / scale, width = frame:GetWidth(), height = frame:GetHeight() }
        end
    end)
    resizeHandle:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then StopSizing() end end)
    resizeHandle:SetScript("OnHide", StopSizing)
    Place()
    Layout()
    CreateMinimapButton()
end

function Addon:Get(key)
    local db = DB()
    if db and db[key] ~= nil then return db[key] end
    return defaults[key]
end
function Addon:Set(key, value)
    if not initialized or defaults[key] == nil then return end
    local kind = type(defaults[key])
    if type(value) ~= kind then return end
    if kind == "number" then
        local ranges = { width = {130,500}, height = {60,600}, barHeight = {10,30}, barSpacing = {0,8},
            visibleBars = {1,40}, textSize = {7,18}, textOffset = {-5,5}, tooltipSpells = {0,20}, tooltipTargets = {0,20},
            reportLength = {1,20}, font = {1,#fonts}, outline = {1,#outlines} }
        local range = ranges[key]
        if range then value = Clamp(math.floor(value + 0.5), range[1], range[2])
        else value = Clamp(value, 0, 1) end
    elseif key == "mode" and value ~= "damage" and value ~= "healing" then return
    elseif key == "borderStyle" and value ~= "none" and value ~= "thin" and value ~= "standard" then return
    elseif key == "session" and value ~= "overall" and value ~= "current" and value ~= "history" then return end
    DB()[key] = value
    if key == "enabled" or key:find("^hide") then UpdateVisibility() end
    if key == "minimapButton" then UpdateMinimapButton() end
    Layout()
    RequestRefresh()
    Notify()
end
function Addon:GetFontNames() return fonts end
function Addon:GetOutlineNames() return { "None", "Thin", "Thick", "Monochrome" } end
function Addon:ResetLayout()
    DB().position = nil
    DB().width, DB().height, DB().visibleBars = defaults.width, defaults.height, defaults.visibleBars
    DB().barHeight, DB().barSpacing = defaults.barHeight, defaults.barSpacing
    Place(); Layout(); RequestRefresh(); Notify()
end
function Addon:ResetDefaults()
    for key, value in pairs(defaults) do DB()[key] = value end
    DB().position = nil
    selectedSessionID, scrollOffset = nil, 0
    Place(); UpdateMinimapButton(); UpdateVisibility(); Layout(); RequestRefresh(); Notify()
end
function Addon:ResetData()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
        selectedSessionID, scrollOffset = nil, 0
        DB().session = "overall"
        RequestRefresh()
        Notify()
    end
end
function Addon:CycleSession(direction)
    local sessions = C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetAvailableCombatSessions() or {}
    local list = { { mode = "overall" }, { mode = "current" } }
    for i = #sessions, 1, -1 do list[#list + 1] = { mode = "history", id = sessions[i].sessionID } end
    local index = 1
    for i, item in ipairs(list) do
        if item.mode == DB().session and (item.mode ~= "history" or item.id == selectedSessionID) then index = i; break end
    end
    local chosen = list[(index - 1 + direction + #list) % #list + 1]
    selectedSessionID = chosen.id
    DB().session = chosen.mode
    scrollOffset = 0
    RequestRefresh(); Notify()
end
function Addon:Report(channel, target)
    local session = GetSession()
    local sources = session and session.combatSources or {}
    if not SendChatMessage or #sources == 0 then Announce("No data to report."); return end
    channel = (channel or "SAY"):upper()
    if channel == "INSTANCE" then channel = "INSTANCE_CHAT" end
    if channel ~= "SAY" and channel ~= "PARTY" and channel ~= "RAID" and channel ~= "GUILD" and channel ~= "OFFICER" and channel ~= "INSTANCE_CHAT" and channel ~= "WHISPER" then
        Announce("Use say, party, raid, guild, officer, instance, or whisper NAME."); return
    end
    if channel == "WHISPER" and (not target or target == "") then Announce("A whisper target is required."); return end
    for i = 1, math.min(DB().reportLength, #sources) do
        local source = sources[i]
        if IsSecret(source.name) or IsSecret(source.totalAmount) then
            Announce("Reporting is unavailable while combat values are protected.")
            return
        end
    end
    local label = DB().mode == "healing" and "Healing" or "Damage"
    SendChatMessage("LH TinyDPS " .. label .. " (" .. DB().session .. ")", channel, nil, target)
    for i = 1, math.min(DB().reportLength, #sources) do
        local source = sources[i]
        SendChatMessage(i .. ". " .. (source.name or "Unknown") .. " - " .. Short(source.totalAmount), channel, nil, target)
    end
end
function Addon:OpenSettings()
    local category = LH_Tweaks and LH_Tweaks.modules and LH_Tweaks.modules[ADDON_NAME] and LH_Tweaks.modules[ADDON_NAME].category
    if category and Settings and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
end

SLASH_LH_TINYDPS1 = "/lh_tinydps"
SlashCmdList.LH_TINYDPS = function(message)
    local command, args = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" or command == "toggle" then Addon:Set("enabled", not DB().enabled)
    elseif command == "show" then Addon:Set("enabled", true)
    elseif command == "hide" then Addon:Set("enabled", false)
    elseif command == "lock" then Addon:Set("locked", true); Announce("Window locked.")
    elseif command == "unlock" then Addon:Set("locked", false); Announce("Left-drag the window to move; drag the circle to resize.")
    elseif command == "damage" or command == "healing" then Addon:Set("mode", command)
    elseif command == "overall" or command == "current" then selectedSessionID = nil; Addon:Set("session", command)
    elseif command == "next" then Addon:CycleSession(1)
    elseif command == "previous" then Addon:CycleSession(-1)
    elseif command == "reset" then Addon:ResetData()
    elseif command == "settings" then Addon:OpenSettings()
    elseif command == "visiblebars" then Addon:Set("visibleBars", tonumber(args))
    elseif command == "reportlength" then Addon:Set("reportLength", tonumber(args))
    elseif command == "report" then
        local channel, target = args:match("^(%S+)%s*(.-)$")
        Addon:Report(channel, target)
    else
        Announce("/lh_tinydps [toggle|show|hide|lock|unlock|damage|healing|overall|current|next|previous|reset|settings|visiblebars N|reportlength N|report CHANNEL [NAME]]")
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        LH_TinyDPSDB = type(LH_TinyDPSDB) == "table" and LH_TinyDPSDB or {}
        if LH_TinyDPSDB.layoutVersion ~= 2 then
            if LH_TinyDPSDB.height == 180 then LH_TinyDPSDB.height = defaults.height end
            if LH_TinyDPSDB.visibleBars == 10 then LH_TinyDPSDB.visibleBars = defaults.visibleBars end
            if LH_TinyDPSDB.backgroundR == 0.045 and LH_TinyDPSDB.backgroundG == 0.045
                and LH_TinyDPSDB.backgroundB == 0.06 and LH_TinyDPSDB.backgroundAlpha == 0.82 then
                LH_TinyDPSDB.backgroundR, LH_TinyDPSDB.backgroundG = 0, 0
                LH_TinyDPSDB.backgroundB, LH_TinyDPSDB.backgroundAlpha = 0, 1
            end
            if LH_TinyDPSDB.borderR == 0.4 and LH_TinyDPSDB.borderG == 0.4
                and LH_TinyDPSDB.borderB == 0.46 and LH_TinyDPSDB.borderAlpha == 0.8 then
                LH_TinyDPSDB.borderR, LH_TinyDPSDB.borderG = defaults.borderR, defaults.borderG
                LH_TinyDPSDB.borderB, LH_TinyDPSDB.borderAlpha = defaults.borderB, defaults.borderAlpha
            end
            LH_TinyDPSDB.layoutVersion = 2
        end
        if not LH_TinyDPSDB.appearanceVersion then
            if LH_TinyDPSDB.borderStyle == nil and type(LH_TinyDPSDB.showBorder) == "boolean" then
                LH_TinyDPSDB.borderStyle = LH_TinyDPSDB.showBorder and "thin" or "none"
            end
            if LH_TinyDPSDB.backgroundR == 0 and LH_TinyDPSDB.backgroundG == 0
                and LH_TinyDPSDB.backgroundB == 0 and LH_TinyDPSDB.backgroundAlpha == 1 then
                LH_TinyDPSDB.backgroundR, LH_TinyDPSDB.backgroundG = panelR, panelG
                LH_TinyDPSDB.backgroundB, LH_TinyDPSDB.backgroundAlpha = panelB, panelA
            end
            LH_TinyDPSDB.appearanceVersion = 1
        end
        if not LH_TinyDPSDB.displayVersion then
            local oldDefaultValues = LH_TinyDPSDB.showRank == true and LH_TinyDPSDB.showAmount == true
                and LH_TinyDPSDB.showRate == true and LH_TinyDPSDB.showPercent == false
            if oldDefaultValues then
                LH_TinyDPSDB.showRank = defaults.showRank
                LH_TinyDPSDB.showAmount = defaults.showAmount
                LH_TinyDPSDB.showRate = defaults.showRate
                LH_TinyDPSDB.showPercent = defaults.showPercent
            elseif LH_TinyDPSDB.showRank ~= nil then
                LH_TinyDPSDB.automaticValues = false
            end
            if LH_TinyDPSDB.outline == 1 then LH_TinyDPSDB.outline = defaults.outline end
            LH_TinyDPSDB.displayVersion = 1
        end
        LH_TinyDPSDB.showBorder = nil
        for key, value in pairs(defaults) do
            if type(LH_TinyDPSDB[key]) ~= type(value) then LH_TinyDPSDB[key] = value end
        end
        for key, range in pairs({ width = {130,500}, height = {60,600}, barHeight = {10,30},
            barSpacing = {0,8}, visibleBars = {1,40}, textSize = {7,18}, textOffset = {-5,5}, tooltipSpells = {0,20},
            tooltipTargets = {0,20}, reportLength = {1,20}, font = {1,#fonts}, outline = {1,#outlines} }) do
            LH_TinyDPSDB[key] = Clamp(math.floor(LH_TinyDPSDB[key] + 0.5), range[1], range[2])
        end
        for _, key in ipairs({ "backgroundAlpha", "barAlpha", "borderAlpha", "backgroundR", "backgroundG",
            "backgroundB", "barR", "barG", "barB", "borderR", "borderG", "borderB" }) do
            LH_TinyDPSDB[key] = Clamp(LH_TinyDPSDB[key], 0, 1)
        end
        if LH_TinyDPSDB.mode ~= "damage" and LH_TinyDPSDB.mode ~= "healing" then LH_TinyDPSDB.mode = "damage" end
        if LH_TinyDPSDB.borderStyle ~= "none" and LH_TinyDPSDB.borderStyle ~= "thin"
            and LH_TinyDPSDB.borderStyle ~= "standard" then LH_TinyDPSDB.borderStyle = defaults.borderStyle end
        if LH_TinyDPSDB.session ~= "overall" and LH_TinyDPSDB.session ~= "current" then LH_TinyDPSDB.session = "overall" end
        CreateWindow()
        initialized = true
        UpdateVisibility()
        Refresh()
        return
    end
    if not initialized then return end
    if event == "GROUP_ROSTER_UPDATE" then
        local now = IsInGroup()
        if groupState ~= nil and now and not groupState and DB().resetOnNewGroup then Addon:ResetData() end
        groupState = now
    elseif event == "PLAYER_ENTERING_WORLD" then
        groupState = IsInGroup()
        if not DB().position then Place() end
        if not minimapButton then CreateMinimapButton() end
    end
    UpdateVisibility()
    RequestRefresh()
end)
events:SetScript("OnUpdate", function()
    if not sizing then return end
    if not IsMouseButtonDown("LeftButton") then StopSizing(); return end
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    DB().width = Clamp(math.floor(sizing.width + x / scale - sizing.x + 0.5), 130, 500)
    DB().height = Clamp(math.floor(sizing.height + sizing.y - y / scale + 0.5), 60, 600)
    Layout()
    RequestRefresh()
end)
