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
    -- Split ONLY on commas/semicolons/newlines; allow spaces inside addon names
    for rawToken in string.gmatch(trimmed, "[^,;\n\r]+") do
        local token = rawToken:gsub("^%s*(.-)%s*$", "%1") -- trim spaces around
        if token ~= "" then
            local disable = false
            if token:sub(1, 1) == "!" then
                disable = true
                token = token:sub(2)
                token = token:gsub("^%s*(.-)%s*$", "%1") -- trim again after '!'
            end
            if token ~= "" then
                map[token] = not disable
            end
        end
    end
    return next(map) and map or nil
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

-- Resolve user-entered addon names (which may be titles) to real folder names
local function ResolveAddonNames(userMap)
    if not userMap then return nil end

    local resolved = {}
    local numAddOns = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or
        (GetNumAddOns and GetNumAddOns()) or 0

    for userName, enabled in pairs(userMap) do
        local lowerUser = string.lower(userName)
        local found = false

        for i = 1, numAddOns do
            local name, title
            if C_AddOns and C_AddOns.GetAddOnInfo then
                name, title = C_AddOns.GetAddOnInfo(i)
            else
                name, title = GetAddOnInfo(i)
            end
            if name then
                local lowerName = string.lower(name)
                local lowerTitle = title and string.lower(title) or nil
                if lowerUser == lowerName or (lowerTitle and lowerUser == lowerTitle) then
                    resolved[name] = enabled
                    found = true
                    break
                end
            end
        end

        -- If we didn't find a matching addon, keep the raw key as a fallback
        if not found then
            resolved[userName] = enabled
        end
    end

    return next(resolved) and resolved or nil
end

local function ASP(msg)
    if AutoSetup and AutoSetup.Print then
        AutoSetup.Print(msg)
    else
        print("AutoSetup: " .. tostring(msg))
    end
end

-- Retrieve available Edit Mode layouts (names)
local function GetLayoutNames()
    if not C_EditMode or not C_EditMode.GetLayouts then
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_EditMode")
        else
            pcall(LoadAddOn, "Blizzard_EditMode")
        end
    end

    local names = {}
    local layouts = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
    if layouts and layouts.layouts then
        for _, layoutInfo in pairs(layouts.layouts) do
            if layoutInfo.layoutName then
                table.insert(names, layoutInfo.layoutName)
            end
        end
    end
    table.sort(names)
    return names
end

-- Shared popup for picking layouts
local layoutPopup
local layoutPopupButtons = {}

local function HideLayoutPopup()
    if layoutPopup then
        layoutPopup:Hide()
    end
end

local function ShowLayoutPopup(anchorButton, targetEditBox)
    if not targetEditBox then return end

    -- Toggle behavior: clicking the same button again hides the popup
    if layoutPopup and layoutPopup:IsShown() and layoutPopup.anchorButton == anchorButton then
        HideLayoutPopup()
        return
    end

    if not layoutPopup then
        layoutPopup = CreateFrame("Frame", "AutoSetupLayoutPopup", UIParent, "BackdropTemplate")
        layoutPopup:SetSize(220, 220)
        layoutPopup:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        layoutPopup:SetFrameStrata("TOOLTIP")

        -- Close button in the top-right
        local close = CreateFrame("Button", nil, layoutPopup, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -3, -3)
        close:SetScript("OnClick", HideLayoutPopup)

        local scroll = CreateFrame("ScrollFrame", nil, layoutPopup, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -10)
        scroll:SetPoint("BOTTOMRIGHT", -30, 10)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(180, 400)
        scroll:SetScrollChild(content)
        layoutPopup.scroll = scroll
        layoutPopup.content = content
    end

    layoutPopup:ClearAllPoints()
    layoutPopup:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", 0, -2)
    layoutPopup.anchorButton = anchorButton

    -- Hide existing item buttons
    for _, btn in ipairs(layoutPopupButtons) do
        btn:Hide()
    end

    local layouts = GetLayoutNames()
    if #layouts == 0 then
        ASP("No Edit Mode layouts found. Open Edit Mode once and save a layout.")
    end

    local y = 0
    for i, name in ipairs(layouts) do
        local btn = layoutPopupButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, layoutPopup.content, "GameMenuButtonTemplate")
            btn:SetSize(180, 20)
            layoutPopupButtons[i] = btn
        end
        btn:SetPoint("TOPLEFT", 0, -y)
        btn:SetText(name)
        btn:SetScript("OnClick", function()
            targetEditBox:SetText(name)
            HideLayoutPopup()
        end)
        btn:Show()
        y = y + 22
    end

    layoutPopup.content:SetHeight(math.max(y, 20))
    layoutPopup:Show()
end

local function RefreshProfileList(panel)
    if not panel or not panel.listContent then return end

    local db = AutoSetup.GetDB and AutoSetup.GetDB() or _G.AutoSetupDB or {}
    panel.rows = panel.rows or {}

    for _, row in ipairs(panel.rows) do
        row:Hide()
    end

    if panel.placeholderRow then
        panel.placeholderRow:Hide()
    end

    local index = 1
    local yOffset = 0
    local hasAny = false

    for res, data in pairs(db) do
        hasAny = true
        local row = panel.rows[index]
        if not row or not row.subtext then
            row = CreateFrame("Frame", nil, panel.listContent, "BackdropTemplate")
            row:SetSize(620, 55)
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
        local autoReloadText = ""

        row.text:SetText(displayName)
        row.subtext:SetText(res ..
            "\nBase: " ..
            (data.editLayoutBase or "?") ..
            targetText .. " | Scale: " .. scaleText .. " | " .. hasAddons)

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

    -- Show a friendly placeholder when there are no profiles yet (use separate frame so we never reuse it as a profile row)
    if not hasAny then
        local row = panel.placeholderRow
        if not row then
            row = CreateFrame("Frame", nil, panel.listContent, "BackdropTemplate")
            row:SetSize(620, 40)
            row:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                tile = true,
                tileSize = 16
            })
            row:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
            row:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("CENTER")

            panel.placeholderRow = row
        end
        row.text:SetText("No profiles saved yet. Fill the form above and click 'Save / Update'.")
        row:SetPoint("TOPLEFT", 0, 0)
        row:Show()
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
    panel.name                = "AutoSetup"

    -- Resolve XML-created children by name and attach them to the panel for convenience
    local baseName            = panel:GetName() or "AutoSetupOptionsPanel"
    panel.titleText           = _G[baseName .. "TitleText"]
    panel.nameInput           = _G[baseName .. "NameInput"]
    panel.resInput            = _G[baseName .. "ResInput"]
    panel.baseLayoutInput     = _G[baseName .. "BaseLayoutInput"]
    panel.targetLayoutInput   = _G[baseName .. "TargetLayoutInput"]
    panel.scaleSlider         = _G[baseName .. "ScaleSlider"]
    panel.scaleSliderText     = _G[baseName .. "ScaleSliderText"]
    panel.suppressCheck       = _G[baseName .. "SuppressCheck"]
    panel.addonsInput         = _G[baseName .. "AddonsInput"]
    panel.saveButton          = _G[baseName .. "SaveButton"]
    panel.clearButton         = _G[baseName .. "ClearButton"]
    panel.useCurrentResButton = _G[baseName .. "UseCurrentResButton"]
    panel.baseLayoutButton    = _G[baseName .. "BaseLayoutButton"]
    panel.targetLayoutButton  = _G[baseName .. "TargetLayoutButton"]
    panel.scrollFrame         = _G[baseName .. "ScrollFrame"]
    panel.listContent         = _G[baseName .. "ScrollFrameListContent"]

    if panel.titleText then
        panel.titleText:SetText("AutoSetup - Resolution Profiles")
    end

    if panel.nameInput then panel.nameInput:SetAutoFocus(false) end
    if panel.resInput then panel.resInput:SetAutoFocus(false) end
    if panel.baseLayoutInput then panel.baseLayoutInput:SetAutoFocus(false) end
    if panel.targetLayoutInput then panel.targetLayoutInput:SetAutoFocus(false) end
    if panel.addonsInput then panel.addonsInput:SetAutoFocus(false) end

    if panel.suppressCheck and panel.suppressCheck.Text then
        panel.suppressCheck.Text:SetText("Suppress 'layout applied' chat messages")
    end


    if panel.useCurrentResButton then
        panel.useCurrentResButton:SetScript("OnClick", function()
            panel.resInput:SetText(GetCurrentResolution())
            panel.resInput:ClearFocus()
        end)
    end

    if panel.baseLayoutButton then
        panel.baseLayoutButton:SetScript("OnClick", function()
            ShowLayoutPopup(panel.baseLayoutButton, panel.baseLayoutInput)
        end)
    end

    if panel.targetLayoutButton then
        panel.targetLayoutButton:SetScript("OnClick", function()
            ShowLayoutPopup(panel.targetLayoutButton, panel.targetLayoutInput)
        end)
    end

    if panel.saveButton then
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
            profile.addonSet = ResolveAddonNames(ParseAddonsString(addonsStr))

            ASP("Saved AutoSetup profile for " .. res .. ".")
            AutoSetup.RefreshOptionsList()
        end)
    end

    if panel.clearButton then
        panel.clearButton:SetScript("OnClick", function()
            panel.nameInput:SetText("")
            panel.resInput:SetText("")
            panel.baseLayoutInput:SetText("")
            panel.targetLayoutInput:SetText("")
            panel.scaleSlider:SetValue(tonumber(GetCVar("uiScale")) or 1.0)
            panel.suppressCheck:SetChecked(false)
            panel.addonsInput:SetText("")
        end)
    end

    if panel.scaleSlider and panel.scaleSliderText then
        panel.scaleSlider:SetMinMaxValues(0.65, 1.15)
        panel.scaleSlider:SetValueStep(0.01)
        panel.scaleSlider:SetObeyStepOnDrag(true)
        panel.scaleSlider:SetValue(tonumber(GetCVar("uiScale")) or 1.0)
        panel.scaleSlider:SetScript("OnValueChanged", function(self, value)
            panel.scaleSliderText:SetText(string.format("UI Scale: %.2f", value))
        end)
        panel.scaleSliderText:SetText(string.format("UI Scale: %.2f", panel.scaleSlider:GetValue()))
    end

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
