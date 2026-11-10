-- Options UI controller for AutoSetup

local addonName, AutoSetup = ...
AutoSetup = AutoSetup or {}

local GetCurrentResolution = AutoSetup.GetCurrentResolution

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

local function BuildAddonsString(...)
    local parts = {}
    for _, tbl in ipairs({ ... }) do
        for name, enabled in pairs(tbl) do
            if enabled then
                table.insert(parts, name)
            else
                table.insert(parts, "!" .. name)
            end
        end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local ASP = AutoSetup.Print

-- Find the installed addon matching a user-entered name or title (case-insensitive).
-- Returns its folder name, or nil.
local function ResolveAddonName(userName)
    local lowerUser = string.lower(userName)
    for i = 1, AutoSetup.GetAddOnCount() do
        local name, title = AutoSetup.GetAddOnNameAndTitle(i)
        if name then
            local lowerTitle = title and string.lower(title) or nil
            if lowerUser == string.lower(name) or (lowerTitle and lowerUser == lowerTitle) then
                return name
            end
        end
    end
    return nil
end

-- Split the parsed entries into addons and addon features. "Provider:feature" entries (or
-- "Provider=feature") whose provider is a known feature provider (e.g. "QoL:viewport") become
-- features, keyed by the provider's folder name and the lowercased feature; everything else stays an
-- addon, so titles that contain a colon or "=" keep working.
local function SplitFeatures(userMap)
    if not userMap then return nil, nil end

    local addons, features = {}, {}
    for userName, enabled in pairs(userMap) do
        local provider, feature = AutoSetup.SplitFeatureKey((userName:gsub("=", ":")))
        local folder = provider and ResolveAddonName(provider:gsub("^%s*(.-)%s*$", "%1"))
        if folder and AutoSetup.FeatureProviders[folder] then
            features[folder .. ":" .. feature:gsub("^%s*(.-)%s*$", "%1"):lower()] = enabled
        else
            addons[userName] = enabled
        end
    end
    return next(addons) and addons or nil, next(features) and features or nil
end

-- Resolve user-entered addon names (which may be titles) to real folder names
local function ResolveAddonNames(userMap)
    if not userMap then return nil end

    local resolved = {}
    for userName, enabled in pairs(userMap) do
        local name = ResolveAddonName(userName)
        if name then
            resolved[name] = enabled
        else
            -- If we didn't find a matching addon, keep the raw key as a fallback,
            -- but let the user know so a typo isn't a silent no-op.
            resolved[userName] = enabled
            ASP("No installed addon matches '" ..
                userName .. "' — check the spelling; this entry will not affect any addon until corrected.")
        end
    end

    return next(resolved) and resolved or nil
end

-- Warn about features the provider (when loaded) doesn't know, so a typo isn't a silent no-op.
local function ValidateFeatures(features)
    if not features then return end
    for key in pairs(features) do
        local provider, feature = AutoSetup.SplitFeatureKey(key)
        local api = AutoSetup.GetFeatureProvider(provider)
        if api then
            -- A failed call was reported by CallFeatureProvider; the save goes on.
            local ok, enabled = AutoSetup.CallFeatureProvider(api.IsFeatureEnabled, feature)
            if ok and enabled == nil then
                ASP("'" .. provider .. "' has no feature '" .. feature .. "' — this entry will have no effect.")
            end
        end
    end
end

-- Blizzard's own layout dropdown hides the presets of the other interface (keyboard and mouse or
-- controller) too.
local function IsOtherInterfacePreset(layoutInfo)
    if layoutInfo.layoutType ~= Enum.EditModeLayoutType.Preset or layoutInfo.interfaceStyle == nil then
        return false
    end
    local style = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle
        and C_InputInterfaceStyle.GetCurrentStyle()
    return style ~= nil and style ~= layoutInfo.interfaceStyle
end

-- The names of the layouts a profile can use: the same list ApplyEditLayoutInternal searches, so
-- presets are included (C_EditMode.GetLayouts has only the saved ones).
local function GetLayoutNames()
    local names = {}
    local manager = EditModeManagerFrame
    if manager and manager:IsInitialized() then
        for _, layoutInfo in ipairs(manager:GetLayouts()) do
            if layoutInfo.layoutName and not IsOtherInterfacePreset(layoutInfo) then
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

-- The panel holds the form's state until save: true = On, false = Off, nil = Leave alone.
local function SetDamageMeterState(panel, state)
    panel.damageMeterState = state
    local stateText = state == nil and "Leave alone" or state and "On" or "Off"
    panel.damageMeterButton:SetText("Damage Meter: " .. stateText)
end

-- nil leaves the UI scale alone; the slider only matters with the box ticked.
local function SetScaleOverride(panel, scale)
    panel.scaleCheck:SetChecked(scale ~= nil)
    panel.scaleSlider:SetEnabled(scale ~= nil)
    panel.scaleSlider:SetValue(scale or tonumber(GetCVar("uiScale")) or 1.0)
end

local function RefreshProfileList(panel)
    if not panel or not panel.listContent then return end

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

    for res, data in AutoSetup.IterateProfiles() do
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
        local hasAddons = (data.addonSet or data.featureSet) and "|cff00ff00Addons|r" or "|cffff0000No Addons|r"
        local scaleText = data.scale and tostring(data.scale) or "unchanged"
        local controllerText = (AutoSetup.hasControllerInterface and data.nativeControllerSupport)
            and " | |cff00ff00Controller|r" or ""
        local damageMeterText = ""
        if data.damageMeter ~= nil then
            damageMeterText = data.damageMeter and " | |cff00ff00Meter On|r" or " | |cffff0000Meter Off|r"
        end

        row.text:SetText(displayName)
        row.subtext:SetText(res ..
            "\nBase: " ..
            (data.editLayoutBase or "?") ..
            targetText .. " | Scale: " .. scaleText .. " | " .. hasAddons .. controllerText .. damageMeterText)

        row.delBtn:SetScript("OnClick", function()
            AutoSetup.DeleteProfile(res)
            AutoSetup.RefreshOptionsList()
            -- Another resolution's profile plays no part in what applies now. Evaluating anyway
            -- would re-apply the current profile, and deleting shouldn't change anything.
            if res == GetCurrentResolution() then AutoSetup.ApplyCurrentProfile() end
        end)

        row.editBtn:SetScript("OnClick", function()
            if not panel.nameInput then return end
            panel.nameInput:SetText(data.name or "")
            panel.resInput:SetText(res)
            panel.baseLayoutInput:SetText(data.editLayoutBase or "")
            panel.targetLayoutInput:SetText(data.editLayoutTarget or "")
            SetScaleOverride(panel, data.scale)
            if panel.controllerCheck then panel.controllerCheck:SetChecked(data.nativeControllerSupport or false) end
            SetDamageMeterState(panel, data.damageMeter)
            panel.addonsInput:SetText(BuildAddonsString(data.addonSet or {}, data.featureSet or {}))
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

    -- The scroll range follows the child's height; without this, rows past it can't be reached.
    panel.listContent:SetHeight(math.max(-yOffset, 40))
end

function AutoSetup_OpenOptionsPanel()
    if AutoSetup.optionsCategory then
        Settings.OpenToCategory(AutoSetup.optionsCategory:GetID())
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
    panel.baseLayoutLabel     = _G[baseName .. "BaseLayoutLabel"]
    panel.targetLayoutInput   = _G[baseName .. "TargetLayoutInput"]
    panel.scaleCheck          = _G[baseName .. "ScaleCheck"]
    panel.scaleSlider         = _G[baseName .. "ScaleSlider"]
    panel.scaleSliderText     = _G[baseName .. "ScaleSliderText"] -- the slider template's $parentText
    panel.controllerCheck     = _G[baseName .. "ControllerCheck"]
    panel.damageMeterButton   = _G[baseName .. "DamageMeterButton"]
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

    -- Native controller support needs the game's controller interface; hide the option entirely
    -- on clients without it rather than showing a checkbox for a setting they don't have.
    if panel.controllerCheck then
        if AutoSetup.hasControllerInterface then
            if panel.controllerCheck.Text then
                panel.controllerCheck.Text:SetText("Enable native controller support")
            end
        else
            panel.controllerCheck:Hide()
        end
    end

    if panel.baseLayoutLabel then
        panel.baseLayoutLabel:SetText(AutoSetup.hasControllerInterface
            and "Base Edit Mode Layout Name (blank = controller default)"
            or "Base Edit Mode Layout Name")
    end

    -- A button that steps through the states, not a dropdown: opening a dropdown menu in the
    -- controller interface and closing the settings has frozen the game on WoW Forever.
    SetDamageMeterState(panel, nil)
    panel.damageMeterButton:SetScript("OnClick", function()
        local state = panel.damageMeterState
        if state == nil then
            SetDamageMeterState(panel, true)
        elseif state then
            SetDamageMeterState(panel, false)
        else
            SetDamageMeterState(panel, nil)
        end
    end)

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
            -- Profiles are looked up by the exact "WIDTHxHEIGHT" key GetCurrentResolution builds.
            local res = (panel.resInput:GetText() or ""):gsub("%s+", ""):lower()
            local baseLayout = panel.baseLayoutInput:GetText() or ""
            local targetLayout = panel.targetLayoutInput:GetText() or ""
            local scale = panel.scaleCheck:GetChecked()
                and tonumber(string.format("%.2f", panel.scaleSlider:GetValue())) or nil
            -- Without the controller interface the checkbox is hidden but Edit still sets it from the
            -- stored value; store false so a stale true neither survives the save nor allows a blank base.
            local controllerSupport = AutoSetup.hasControllerInterface and panel.controllerCheck
                and panel.controllerCheck:GetChecked() and true or false
            local addonsStr = panel.addonsInput:GetText() or ""

            if res == "" then
                ASP("Please enter a resolution.")
                return
            end
            if not res:match("^%d+x%d+$") then
                ASP("Please enter the resolution as WIDTHxHEIGHT, e.g. 1920x1080.")
                return
            end
            panel.resInput:SetText(res)
            if baseLayout == "" and not controllerSupport then
                ASP(AutoSetup.hasControllerInterface
                    and "Please enter a base Edit Mode layout name, or enable native controller support."
                    or "Please enter a base Edit Mode layout name.")
                return
            end

            local profile = AutoSetup.EnsureProfile(res)
            profile.name = (name ~= "" and name) or ("Profile " .. res)
            profile.editLayoutBase = (baseLayout ~= "" and baseLayout) or nil
            profile.editLayoutTarget = (targetLayout ~= "" and targetLayout) or nil
            profile.scale = scale
            profile.nativeControllerSupport = controllerSupport
            profile.damageMeter = panel.damageMeterState
            local addons, features = SplitFeatures(ParseAddonsString(addonsStr))
            profile.addonSet = ResolveAddonNames(addons)
            profile.featureSet = features
            ValidateFeatures(features)

            ASP("Saved AutoSetup profile for " .. res .. ".")
            AutoSetup.RefreshOptionsList()
            AutoSetup.ApplyCurrentProfile()
        end)
    end

    if panel.clearButton then
        panel.clearButton:SetScript("OnClick", function()
            panel.nameInput:SetText("")
            panel.resInput:SetText("")
            panel.baseLayoutInput:SetText("")
            panel.targetLayoutInput:SetText("")
            SetScaleOverride(panel, nil)
            if panel.controllerCheck then panel.controllerCheck:SetChecked(false) end
            SetDamageMeterState(panel, nil)
            panel.addonsInput:SetText("")
        end)
    end

    if panel.scaleSlider and panel.scaleSliderText then
        panel.scaleSlider:SetMinMaxValues(0.65, 1.15)
        panel.scaleSlider:SetValueStep(0.01)
        panel.scaleSlider:SetObeyStepOnDrag(true)
        panel.scaleSlider:SetScript("OnValueChanged", function(self, value)
            panel.scaleSliderText:SetText(string.format("UI Scale: %.2f", value))
        end)
        if panel.scaleCheck.Text then panel.scaleCheck.Text:SetText("Set UI scale") end
        panel.scaleCheck:HookScript("OnClick", function(self)
            panel.scaleSlider:SetEnabled(self:GetChecked())
        end)
        SetScaleOverride(panel, nil)
        panel.scaleSliderText:SetText(string.format("UI Scale: %.2f", panel.scaleSlider:GetValue()))
    end

    local category = Settings.RegisterCanvasLayoutCategory(panel, "AutoSetup")
    Settings.RegisterAddOnCategory(category)
    AutoSetup.optionsCategory = category

    AutoSetup.optionsPanel = panel

    AutoSetup.RefreshOptionsList = function()
        RefreshProfileList(panel)
    end

    -- Built when shown, so it's current every time and costs nothing until the panel is opened.
    -- Save and delete refresh it while it's open.
    panel:HookScript("OnShow", AutoSetup.RefreshOptionsList)
    -- The popup hangs off UIParent, so it wouldn't close with the settings by itself.
    panel:HookScript("OnHide", HideLayoutPopup)
end
