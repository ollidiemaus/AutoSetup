-- Options UI controller for AutoSetup

local addonName, AutoSetup = ...
AutoSetup = AutoSetup or {}

local function GetCurrentResolution()
    local width, height = GetPhysicalScreenSize()
    if width and height then
        return math.floor(width) .. "x" .. math.floor(height)
    end
    local rawRes = GetCVar("gxWindowedResolution") or GetCVar("gxResolution") or ""
    return rawRes:match("%d+x%d+") or "Unknown"
end

-- Parse addons string: "Addon1, !Addon2, WeakAuras"
--  "Name"  => enable
--  "!Name" => disable
local function ParseAddonsString(str)
    if not str then return nil end
    local trimmed = str:gsub("^%s*(.-)%s*$", "%1")
    if trimmed == "" then return nil end

    local map = {}
    for token in string.gmatch(trimmed, "[^,; \n\r]+") do
        local disable = false
        if token:sub(1, 1) == "!" then
            disable = true
            token = token:sub(2)
        end
        if token ~= "" then
            map[token] = not disable
        end
    end
    return map
end

local function BuildAddonsString(tbl)
    if not tbl then return "" end
    local parts = {}
    for name, enabled in pairs(tbl) do
        if enabled then
            table.insert(parts, name)
        else
            table.insert(parts, "!" .. name)
        end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function ASP(msg)
    if AutoSetup and AutoSetup.Print then
        AutoSetup.Print(msg)
    else
        print("AutoSetup: " .. tostring(msg))
    end
end

local function RefreshProfileList(panel)
    if not panel or not panel.listContent then return end

    local db = AutoSetup.GetDB and AutoSetup.GetDB() or _G.AutoSetupDB or {}
    panel.rows = panel.rows or {}

    for _, row in ipairs(panel.rows) do
        row:Hide()
    end

    local index = 1
    local yOffset = 0
    for res, data in pairs(db) do
        local row = panel.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, panel.listContent, "BackdropTemplate")
            row:SetSize(360, 55)
            row:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                tile = true,
                tileSize = 16
            })
            row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            row:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.text:SetPoint("TOPLEFT", 10, -5)

            row.subtext = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.subtext:SetPoint("BOTTOMLEFT", 10, 5)
            row.subtext:SetJustifyH("LEFT")

            row.delBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            row.delBtn:SetPoint("RIGHT", -5, 0)

            row.editBtn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
            row.editBtn:SetSize(50, 20)
            row.editBtn:SetPoint("RIGHT", row.delBtn, "LEFT", -5, 0)
            row.editBtn:SetText("Edit")

            panel.rows[index] = row
        end

        local displayName = data.name or "Profile"
        local targetText = data.editLayoutTarget and (" -> " .. data.editLayoutTarget) or ""
        local hasAddons = data.addonSet and "|cff00ff00Addons|r" or "|cffff0000No Addons|r"
        local scaleText = data.scale and tostring(data.scale) or "default"

        row.text:SetText(displayName)
        row.subtext:SetText(res .. "\nBase: " .. (data.editLayoutBase or "?") .. targetText .. " | Scale: " .. scaleText .. " | " .. hasAddons)

        row.delBtn:SetScript("OnClick", function()
            AutoSetupDB[res] = nil
            AutoSetup.RefreshOptionsList()
        end)

        row.editBtn:SetScript("OnClick", function()
            if not panel.nameInput then return end
            panel.nameInput:SetText(data.name or "")
            panel.resInput:SetText(res)
            panel.baseLayoutInput:SetText(data.editLayoutBase or "")
            panel.targetLayoutInput:SetText(data.editLayoutTarget or "")
            panel.scaleSlider:SetValue(data.scale or (tonumber(GetCVar("uiScale")) or 1.0))
            panel.suppressCheck:SetChecked(data.suppressChat or false)
            panel.addonsInput:SetText(BuildAddonsString(data.addonSet))
        end)

        row:SetPoint("TOPLEFT", 0, yOffset)
        row:Show()

        yOffset = yOffset - 60
        index = index + 1
    end
end

function AutoSetup_OpenOptionsPanel()
    if Settings and Settings.OpenToCategory and AutoSetup.optionsCategory then
        Settings.OpenToCategory(AutoSetup.optionsCategory:GetID())
        return
    end

    if InterfaceOptionsFrame then
        InterfaceOptionsFrame_OpenToCategory("AutoSetup")
        InterfaceOptionsFrame_OpenToCategory("AutoSetup")
    end
end

function AutoSetup_OptionsPanel_OnLoad(panel)
    panel.name = "AutoSetup"

    panel.titleText:SetText("AutoSetup - Resolution Profiles")

    panel.nameInput:SetAutoFocus(false)
    panel.resInput:SetAutoFocus(false)
    panel.baseLayoutInput:SetAutoFocus(false)
    panel.targetLayoutInput:SetAutoFocus(false)
    panel.addonsInput:SetAutoFocus(false)

    panel.useCurrentResButton:SetScript("OnClick", function()
        panel.resInput:SetText(GetCurrentResolution())
        panel.resInput:ClearFocus()
    end)

    panel.saveButton:SetScript("OnClick", function()
        local name = panel.nameInput:GetText() or ""
        local res = panel.resInput:GetText() or ""
        local baseLayout = panel.baseLayoutInput:GetText() or ""
        local targetLayout = panel.targetLayoutInput:GetText() or ""
        local scale = tonumber(string.format("%.2f", panel.scaleSlider:GetValue()))
        local suppress = panel.suppressCheck:GetChecked() and true or false
        local addonsStr = panel.addonsInput:GetText() or ""

        if res == "" or baseLayout == "" then
            ASP("Please enter a resolution and a base Edit Mode layout name.")
            return
        end

        local profile = AutoSetup.EnsureProfile(res)
        profile.name = (name ~= "" and name) or ("Profile " .. res)
        profile.editLayoutBase = baseLayout
        profile.editLayoutTarget = (targetLayout ~= "" and targetLayout) or nil
        profile.scale = scale
        profile.suppressChat = suppress
        profile.addonSet = ParseAddonsString(addonsStr)

        ASP("Saved AutoSetup profile for " .. res .. ".")
        AutoSetup.RefreshOptionsList()
    end)

    panel.clearButton:SetScript("OnClick", function()
        panel.nameInput:SetText("")
        panel.resInput:SetText("")
        panel.baseLayoutInput:SetText("")
        panel.targetLayoutInput:SetText("")
        panel.scaleSlider:SetValue(tonumber(GetCVar("uiScale")) or 1.0)
        panel.suppressCheck:SetChecked(false)
        panel.addonsInput:SetText("")
    end)

    panel.scaleSlider:SetMinMaxValues(0.65, 1.15)
    panel.scaleSlider:SetValueStep(0.01)
    panel.scaleSlider:SetObeyStepOnDrag(true)
    panel.scaleSlider:SetValue(tonumber(GetCVar("uiScale")) or 1.0)
    panel.scaleSlider:SetScript("OnValueChanged", function(self, value)
        panel.scaleSliderText:SetText(string.format("UI Scale: %.2f", value))
    end)
    panel.scaleSliderText:SetText(string.format("UI Scale: %.2f", panel.scaleSlider:GetValue()))

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "AutoSetup")
        Settings.RegisterAddOnCategory(category)
        AutoSetup.optionsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    AutoSetup.optionsPanel = panel

    AutoSetup.RefreshOptionsList = function()
        RefreshProfileList(panel)
    end

    C_Timer.After(0.5, function()
        AutoSetup.RefreshOptionsList()
    end)
end

