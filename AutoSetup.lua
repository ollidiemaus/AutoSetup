-- AutoSetup - resolution-based Edit Mode layout + AddOn profiles

local addonName, AutoSetup = ...
AutoSetup = AutoSetup or {}

local defaultDB = {}
local debugLog = {}
local lastResolution = nil
local initDone = false

-------------------------------------------------------------------------------
-- Utility
-------------------------------------------------------------------------------

local function Debug(msg)
    local timestamp = date("%H:%M:%S")
    local logEntry = "[" .. timestamp .. "] " .. msg
    table.insert(debugLog, logEntry)
    if #debugLog > 50 then table.remove(debugLog, 1) end
end

local function Print(msg)
    Debug(msg)
    print("|cFF00CCFFAutoSetup:|r " .. tostring(msg))
end

-- expose for other files (e.g. options panel)
AutoSetup.Debug = Debug
AutoSetup.Print = Print

local function StripEscapes(str)
    if not str or type(str) ~= "string" then return "" end
    local s = str
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "|H.-|h(.-)|h", "%1")
    s = string.gsub(s, "|T.-|t", "")
    s = string.gsub(s, "{.-}", "")
    s = string.lower(s)
    return s
end

local function CleanString(str)
    if not str or type(str) ~= "string" then return "" end
    local s = string.gsub(str, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.lower(s)
    s = string.gsub(s, "^%s*(.-)%s*$", "%1")
    return s
end

local function GetCurrentResolution()
    local width, height = GetPhysicalScreenSize()
    if width and height then
        return math.floor(width) .. "x" .. math.floor(height)
    end
    local rawRes = GetCVar("gxWindowedResolution") or GetCVar("gxResolution") or ""
    return rawRes:match("%d+x%d+") or "Unknown"
end

-------------------------------------------------------------------------------
-- Database helpers
-------------------------------------------------------------------------------

local function GetDB()
    AutoSetupDB = AutoSetupDB or defaultDB
    return AutoSetupDB
end

local function GetProfileForResolution(resolution)
    local db = GetDB()
    return db[resolution]
end

local function EnsureProfile(resolution)
    local db = GetDB()
    db[resolution] = db[resolution] or {
        name = resolution,
        editLayoutBase = nil,
        editLayoutTarget = nil,
        scale = nil,
        suppressChat = false,
        addonSet = nil, -- [addonName] = true/false
    }
    return db[resolution]
end

AutoSetup.GetDB = GetDB
AutoSetup.GetProfileForResolution = GetProfileForResolution
AutoSetup.EnsureProfile = EnsureProfile

-------------------------------------------------------------------------------
-- Edit Mode layout switching
-------------------------------------------------------------------------------

local function ApplyEditLayoutInternal(targetNameClean, attemptsLeft, verbose)
    if InCombatLockdown() then
        if verbose then Print("Cannot change Edit Mode layout in combat.") end
        return
    end

    if not EditModeManagerFrame then
        C_AddOns.LoadAddOn("Blizzard_EditMode")
    end

    if C_EditMode and C_EditMode.GetActiveLayoutInfo then
        local activeInfo = C_EditMode.GetActiveLayoutInfo()
        if activeInfo then
            local activeNameClean = CleanString(activeInfo.layoutName)
            if activeNameClean == targetNameClean then
                if verbose then Print("Edit Mode layout already active.") end
                return
            end
        end
    end

    local internalLayouts = EditModeManagerFrame and EditModeManagerFrame:GetLayouts()
    local foundIndex, foundName

    if internalLayouts then
        for i, layoutInfo in ipairs(internalLayouts) do
            if CleanString(layoutInfo.layoutName) == targetNameClean then
                foundIndex = i
                foundName = layoutInfo.layoutName
                break
            end
        end
    end

    if foundIndex then
        if verbose then
            Debug("Switching to Edit Mode layout '" .. foundName .. "' (index " .. foundIndex .. ")")
            Print("Switched to layout '" .. foundName .. "'.")
        end
        EditModeManagerFrame:SelectLayout(foundIndex)
    else
        if attemptsLeft and attemptsLeft > 0 then
            C_Timer.After(1.0, function()
                ApplyEditLayoutInternal(targetNameClean, attemptsLeft - 1, verbose)
            end)
        elseif verbose then
            Print("Could not find Edit Mode layout for '" .. targetNameClean .. "'.")
        end
    end
end

local function ApplyEditLayout(layoutName, verbose)
    if not layoutName or layoutName == "" then return end
    local targetNameClean = CleanString(layoutName)
    ApplyEditLayoutInternal(targetNameClean, 3, verbose)
end

-------------------------------------------------------------------------------
-- AddOn set switching
-------------------------------------------------------------------------------
-- addonSet format: [addonFolderName] = true (enable) or false (disable).
-- Only addons present in addonSet are touched. AutoSetup itself is never disabled.

local function ApplyAddonSet(profile, verbose)
    if not profile or not profile.addonSet then return end
    if InCombatLockdown() then
        if verbose then Print("Cannot change AddOn state in combat.") end
        return
    end

    local addonSet = profile.addonSet
    local numAddOns = (C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or GetNumAddOns()
    local player = UnitName("player")
    local changed = false

    local function GetEnabledState(name, index)
        if C_AddOns and C_AddOns.GetAddOnEnableState then
            return C_AddOns.GetAddOnEnableState(player, name or index) > 0
        else
            local _, _, _, enabled = GetAddOnInfo(name or index)
            return not not enabled
        end
    end

    local function EnableAddon(name, index)
        if C_AddOns and C_AddOns.EnableAddOn then
            C_AddOns.EnableAddOn(name or index, player)
        else
            EnableAddOn(name or index, player)
        end
    end

    local function DisableAddon(name, index)
        if C_AddOns and C_AddOns.DisableAddOn then
            C_AddOns.DisableAddOn(name or index, player)
        else
            DisableAddOn(name or index, player)
        end
    end

    for i = 1, numAddOns do
        local name = (C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(i)) or select(1, GetAddOnInfo(i))
        if name then
            local desired = addonSet[name]
            if desired ~= nil then
                if name == addonName then
                    desired = true
                end

                local currentlyEnabled = GetEnabledState(name, i)
                if desired and not currentlyEnabled then
                    EnableAddon(name, i)
                    changed = true
                    if verbose then Debug("Enabling addon: " .. name) end
                elseif not desired and currentlyEnabled then
                    DisableAddon(name, i)
                    changed = true
                    if verbose then Debug("Disabling addon: " .. name) end
                end
            end
        end
    end

    if changed then
        if verbose then
            Print("AddOn configuration changed for this resolution. Reloading UI...")
        end
        C_Timer.After(0.5, ReloadUI)
    elseif verbose then
        Print("AddOn configuration already matches profile.")
    end
end

-------------------------------------------------------------------------------
-- Scale + profile evaluation
-------------------------------------------------------------------------------

local function ApplyScale(profile, verbose)
    if not profile or not profile.scale then return end
    if InCombatLockdown() then
        if verbose then Print("Cannot change UI scale in combat.") end
        return
    end

    local currentScale = tonumber(GetCVar("uiScale"))
    local targetScale = tonumber(profile.scale)

    if not currentScale or not targetScale then return end

    if math.abs(currentScale - targetScale) > 0.001 then
        if verbose then Debug("Setting UI Scale to " .. tostring(profile.scale)) end
        SetCVar("useUiScale", "1")
        SetCVar("uiScale", tostring(profile.scale))
    elseif verbose then
        Debug("UI Scale already matches profile (" .. tostring(currentScale) .. ")")
    end
end

local function EvaluateProfileState(verbose)
    local res = GetCurrentResolution()
    lastResolution = res

    local profile = GetProfileForResolution(res)
    if not profile then
        if verbose then Print("No AutoSetup profile for resolution " .. res .. ".") end
        return
    end

    if verbose then
        Print("Applying AutoSetup profile '" .. (profile.name or res) .. "' (" .. res .. ").")
    end

    local inCombat = UnitAffectingCombat("player")
    local hasTarget = UnitExists("target")
    local hasSoftTarget = UnitExists("softenemy")

    local layoutToUse = profile.editLayoutBase
    if (inCombat or hasTarget or hasSoftTarget) and profile.editLayoutTarget and profile.editLayoutTarget ~= "" then
        layoutToUse = profile.editLayoutTarget
    end

    ApplyScale(profile, verbose)
    ApplyEditLayout(layoutToUse, verbose)
    ApplyAddonSet(profile, verbose)
end

-------------------------------------------------------------------------------
-- Resolution monitoring (observe-only)
-------------------------------------------------------------------------------

local function CheckResolutionChange()
    local res = GetCurrentResolution()
    if res ~= lastResolution then
        Debug("Resolution changed from " .. tostring(lastResolution) .. " to " .. tostring(res))
        EvaluateProfileState(false)
    end
end

-------------------------------------------------------------------------------
-- Chat suppression for Edit Mode messages
-------------------------------------------------------------------------------

local originalAddMessage = ChatFrame1 and ChatFrame1.AddMessage

if originalAddMessage then
    ChatFrame1.AddMessage = function(self, text, ...)
        if AutoSetupDB and text then
            local res = GetCurrentResolution()
            local profile = AutoSetupDB[res]
            if profile and profile.suppressChat then
                local cleanText = StripEscapes(text)
                local formatStr = ERR_EDIT_MODE_LAYOUT_APPLIED

                if formatStr then
                    local cleanFormat = StripEscapes(formatStr)
                    local prefix = strsplit("%", cleanFormat)
                    if prefix and prefix ~= "" and string.find(cleanText, prefix, 1, true) then
                        return
                    end
                end

                if string.find(cleanText, "edit mode layout", 1, true) then
                    return
                end
            end
        end
        return originalAddMessage(self, text, ...)
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        AutoSetupDB = AutoSetupDB or defaultDB
        Debug("AutoSetup loaded.")

        C_Timer.NewTicker(5.0, CheckResolutionChange)

    elseif event == "PLAYER_ENTERING_WORLD" then
        initDone = false
        local res = GetCurrentResolution()
        Debug("PLAYER_ENTERING_WORLD. Current resolution: " .. res)

        C_Timer.After(4.0, function()
            if not initDone then
                EvaluateProfileState(true)
                initDone = true
            end
        end)

    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if not initDone then
            initDone = true
            EvaluateProfileState(true)
        end

    elseif event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_SOFT_ENEMY_CHANGED"
        or event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        if initDone then
            EvaluateProfileState(false)
        end
    end
end)

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------

SLASH_AUTOSETUP1 = "/autosetup"
SLASH_AUTOSETUP2 = "/as"

SlashCmdList["AUTOSETUP"] = function(msg)
    msg = msg and msg:lower() or ""
    if msg == "debug" then
        Print("Current resolution: " .. GetCurrentResolution())
        for _, line in ipairs(debugLog) do
            print("|cff888888" .. line .. "|r")
        end
        return
    end

    if AutoSetup_OpenOptionsPanel then
        AutoSetup_OpenOptionsPanel()
    else
        Print("Options panel not available.")
    end
end

