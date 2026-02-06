-- AutoSetup
-- Per‑resolution profiles that:
--   * apply a chosen Edit Mode layout (and optional combat/target layout)
--   * optionally set a UI scale
--   * enable/disable a set of addons

local addonName, AutoSetup = ...
AutoSetup = AutoSetup or {}

local defaultDB = {}
local debugLog = {}                -- rolling in‑memory log for /autosetup debug
local lastResolution = nil         -- last resolution string we evaluated
local initDone = false             -- guards one‑time initialization on login
local lastAppliedLayoutClean = nil -- last layout name we actually selected (CleanString)
local pendingAutoReload = false    -- queue auto-reload until PLAYER_ENTERING_WORLD
local lastReloadTime = 0           -- cooldown timer for auto-reload

-------------------------------------------------------------------------------
-- Utility helpers
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

-- Comprehensive reload function detection and execution
local detectedReloadFunction = nil
local function DetectReloadFunction()
    if detectedReloadFunction then return detectedReloadFunction end

    Debug("Detecting available reload functions...")

    -- Test multiple reload function candidates (correct WoW API functions)
    local reloadCandidates = {
        { name = "C_UI.Reload",     func = C_UI and C_UI.Reload }, -- Modern WoW API (correct)
        { name = "global ReloadUI", func = _G.ReloadUI },          -- Legacy function
        { name = "direct ReloadUI", func = ReloadUI },             -- Direct reference
        { name = "Reload",          func = _G.Reload },            -- Alternative name
    }

    for _, candidate in ipairs(reloadCandidates) do
        if candidate.func and type(candidate.func) == "function" then
            Debug("Found candidate: " .. candidate.name)
            -- Just check if it's a function, don't execute it during detection
            if type(candidate.func) == "function" then
                Debug("SUCCESS: " .. candidate.name .. " is available")
                detectedReloadFunction = candidate.func
                Debug("Using " .. candidate.name .. " for auto-reload")
                return detectedReloadFunction
            end
        else
            Debug("SKIPPED: " .. candidate.name .. " - not available")
        end
    end

    Debug("No working reload function found!")
    return nil
end

-- Strip color codes, links, textures and braces and lowercase the result.
-- Used for both input strings and system messages.
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

-- Strip WoW color codes, trim whitespace and lowercase.
-- This is the canonical way we compare layout names.
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
-- SavedVariables helpers
-------------------------------------------------------------------------------

local function GetDB()
    AutoSetupDB = AutoSetupDB or defaultDB
    return AutoSetupDB
end

local function GetProfileForResolution(resolution)
    local db = GetDB()
    return db[resolution]
end

-- Ensure and return a profile table for a given resolution key.
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
        -- Never touch layouts in combat; just bail quietly.
        if verbose then Print("Cannot change Edit Mode layout in combat.") end
        return
    end

    if not EditModeManagerFrame then
        C_AddOns.LoadAddOn("Blizzard_EditMode")
    end

    -- If Edit Mode reports that we're already on the requested layout, do nothing.
    if C_EditMode and C_EditMode.GetActiveLayoutInfo then
        local activeInfo = C_EditMode.GetActiveLayoutInfo()
        if activeInfo then
            local activeNameClean = CleanString(activeInfo.layoutName)
            if activeNameClean == targetNameClean then
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
        lastAppliedLayoutClean = targetNameClean
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
-- Profile.addonSet format:
--   [addonFolderName] = true  -- ensure addon is enabled
--   [addonFolderName] = false -- ensure addon is disabled
-- Only addons that appear in addonSet are touched; all others are left alone.
-- The AutoSetup addon itself is never disabled even if specified.
-------------------------------------------------------------------------------

-- Execute immediate auto-reload (not queued)
local function ExecuteImmediateAutoReload(verbose)
    if InCombatLockdown() then
        if verbose then
            Debug("Cannot reload UI in combat. Immediate auto-reload skipped.")
            Print("Cannot reload UI in combat. Immediate auto-reload skipped.")
        end
        return
    end

    -- Cooldown to prevent duplicate reloads within 5 seconds
    local currentTime = GetTime()
    if currentTime - lastReloadTime < 5.0 then
        if verbose then Debug("Auto-reload skipped: cooldown active") end
        return
    end

    if verbose then
        Debug("Executing immediate auto-reload...")
        Print("Executing immediate auto-reload...")
    end

    lastReloadTime = GetTime()
    Debug("Executing ReloadUI()...")

    -- Detect the best available reload function
    local reloadFunction = DetectReloadFunction()

    if not reloadFunction then
        Debug("ERROR: No reload function available!")
        if verbose then Print("ERROR: No reload function available for immediate auto-reload") end
        return
    end

    -- Try different timing approaches for the immediate reload
    Debug("Testing different timing approaches for immediate reload...")
    Print("Testing different timing approaches for immediate reload...")

    -- Approach 1: Immediate execution
    Debug("Approach 1: Immediate execution")
    Print("Approach 1: Immediate execution")
    local success, err = pcall(reloadFunction)
    if success then
        Debug("SUCCESS: Immediate execution worked!")
        Print("SUCCESS: Immediate execution worked!")
        if verbose then Print("UI reload completed successfully (immediate)") end
        return
    else
        Debug("Failed: " .. tostring(err))
        Print("Failed: " .. tostring(err))
    end

    -- Approach 2: Small delay (0.5 seconds)
    Debug("Approach 2: 0.5 second delay")
    Print("Approach 2: 0.5 second delay")
    C_Timer.After(0.5, function()
        if InCombatLockdown() then
            Debug("Cannot reload UI in combat (delayed check)")
            Print("Cannot reload UI in combat (delayed check)")
            return
        end
        Debug("Executing with 0.5 second delay...")
        Print("Executing with 0.5 second delay...")
        local success2, err2 = pcall(reloadFunction)
        if success2 then
            Debug("SUCCESS: 0.5 second delay worked!")
            Print("SUCCESS: 0.5 second delay worked!")
            if verbose then Print("UI reload completed successfully (0.5s delay)") end
        else
            Debug("Failed with 0.5s delay: " .. tostring(err2))
            Print("Failed with 0.5s delay: " .. tostring(err2))
        end
    end)

    -- Approach 3: Longer delay (2 seconds)
    Debug("Approach 3: 2 second delay")
    Print("Approach 3: 2 second delay")
    C_Timer.After(2.0, function()
        if InCombatLockdown() then
            Debug("Cannot reload UI in combat (delayed check)")
            Print("Cannot reload UI in combat (delayed check)")
            return
        end
        Debug("Executing with 2 second delay...")
        Print("Executing with 2 second delay...")
        local success3, err3 = pcall(reloadFunction)
        if success3 then
            Debug("SUCCESS: 2 second delay worked!")
            Print("SUCCESS: 2 second delay worked!")
            if verbose then Print("UI reload completed successfully (2s delay)") end
        else
            Debug("Failed with 2s delay: " .. tostring(err3))
            Print("Failed with 2s delay: " .. tostring(err3))
        end
    end)
end

-- Safe auto-reload function with enhanced logging and cooldown
local function SafeAutoReload(profile, verbose)
    if not profile or not profile.autoReload then
        if verbose then Debug("Auto-reload disabled for this profile") end
        return
    end

    if InCombatLockdown() then
        if verbose then
            Debug("Cannot reload UI in combat. Auto-reload skipped.")
            Print("Cannot reload UI in combat. Auto-reload skipped.")
        end
        return
    end

    -- Cooldown to prevent duplicate reloads within 5 seconds
    local currentTime = GetTime()
    if currentTime - lastReloadTime < 5.0 then
        if verbose then Debug("Auto-reload skipped: cooldown active") end
        return
    end

    if verbose then
        Debug("Executing auto-reload immediately...")
        Print("Executing auto-reload immediately...")
    end

    -- Execute the reload immediately (not queued)
    ExecuteImmediateAutoReload(verbose)
end

-- Comprehensive reload function detection and execution
local detectedReloadFunction = nil
local function DetectReloadFunction()
    if detectedReloadFunction then return detectedReloadFunction end

    Debug("Detecting available reload functions...")

    -- Test multiple reload function candidates (correct WoW API functions)
    local reloadCandidates = {
        { name = "C_UI.Reload",     func = C_UI and C_UI.Reload }, -- Modern WoW API (correct)
        { name = "global ReloadUI", func = _G.ReloadUI },          -- Legacy function
        { name = "direct ReloadUI", func = ReloadUI },             -- Direct reference
        { name = "Reload",          func = _G.Reload },            -- Alternative name
    }

    for _, candidate in ipairs(reloadCandidates) do
        if candidate.func and type(candidate.func) == "function" then
            Debug("Found candidate: " .. candidate.name)
            -- Just check if it's a function, don't execute it during detection
            if type(candidate.func) == "function" then
                Debug("SUCCESS: " .. candidate.name .. " is available")
                detectedReloadFunction = candidate.func
                Debug("Using " .. candidate.name .. " for auto-reload")
                return detectedReloadFunction
            end
        else
            Debug("SKIPPED: " .. candidate.name .. " - not available")
        end
    end

    Debug("No working reload function found!")
    return nil
end

-- Execute queued auto-reload after PLAYER_ENTERING_WORLD
local function ExecuteQueuedAutoReload(verbose)
    if not pendingAutoReload then return end

    pendingAutoReload = false

    if InCombatLockdown() then
        if verbose then
            Debug("Cannot reload UI in combat. Queued auto-reload skipped.")
            Print("Cannot reload UI in combat. Queued auto-reload skipped.")
        end
        return
    end

    -- Cooldown to prevent duplicate reloads within 5 seconds
    local currentTime = GetTime()
    if currentTime - lastReloadTime < 5.0 then
        if verbose then Debug("Auto-reload skipped: cooldown active") end
        return
    end

    if verbose then
        Debug("Executing queued auto-reload...")
        Print("Executing queued auto-reload...")
    end

    -- Execute the reload with different timing approaches
    if InCombatLockdown() then
        if verbose then
            Debug("Cannot reload UI in combat. Queued auto-reload skipped.")
            Print("Cannot reload UI in combat. Queued auto-reload skipped.")
        end
        return
    end

    lastReloadTime = GetTime()
    Debug("Executing ReloadUI()...")

    -- Detect the best available reload function
    local reloadFunction = DetectReloadFunction()

    if not reloadFunction then
        Debug("ERROR: No reload function available!")
        if verbose then Print("ERROR: No reload function available for auto-reload") end
        return
    end

    -- Try different timing approaches for the reload
    Debug("Testing different timing approaches for reload...")
    Print("Testing different timing approaches for reload...")

    -- Approach 1: Immediate execution
    Debug("Approach 1: Immediate execution")
    Print("Approach 1: Immediate execution")
    local success, err = pcall(reloadFunction)
    if success then
        Debug("SUCCESS: Immediate execution worked!")
        Print("SUCCESS: Immediate execution worked!")
        if verbose then Print("UI reload completed successfully (immediate)") end
        return
    else
        Debug("Failed: " .. tostring(err))
        Print("Failed: " .. tostring(err))
    end

    -- Approach 2: Small delay (0.5 seconds)
    Debug("Approach 2: 0.5 second delay")
    Print("Approach 2: 0.5 second delay")
    C_Timer.After(0.5, function()
        if InCombatLockdown() then
            Debug("Cannot reload UI in combat (delayed check)")
            Print("Cannot reload UI in combat (delayed check)")
            return
        end
        Debug("Executing with 0.5 second delay...")
        Print("Executing with 0.5 second delay...")
        local success2, err2 = pcall(reloadFunction)
        if success2 then
            Debug("SUCCESS: 0.5 second delay worked!")
            Print("SUCCESS: 0.5 second delay worked!")
            if verbose then Print("UI reload completed successfully (0.5s delay)") end
        else
            Debug("Failed with 0.5s delay: " .. tostring(err2))
            Print("Failed with 0.5s delay: " .. tostring(err2))
        end
    end)

    -- Approach 3: Longer delay (2 seconds)
    Debug("Approach 3: 2 second delay")
    Print("Approach 3: 2 second delay")
    C_Timer.After(2.0, function()
        if InCombatLockdown() then
            Debug("Cannot reload UI in combat (delayed check)")
            Print("Cannot reload UI in combat (delayed check)")
            return
        end
        Debug("Executing with 2 second delay...")
        Print("Executing with 2 second delay...")
        local success3, err3 = pcall(reloadFunction)
        if success3 then
            Debug("SUCCESS: 2 second delay worked!")
            Print("SUCCESS: 2 second delay worked!")
            if verbose then Print("UI reload completed successfully (2s delay)") end
        else
            Debug("Failed with 2s delay: " .. tostring(err3))
            Print("Failed with 2s delay: " .. tostring(err3))
        end
    end)
end

-- Execute reload function with proper detection
local function ExecuteReload()
    if InCombatLockdown() then
        Debug("Cannot reload UI in combat. Reload skipped.")
        Print("Cannot reload UI in combat. Reload skipped.")
        return
    end

    -- Detect the best available reload function
    local reloadFunction = DetectReloadFunction()

    if not reloadFunction then
        Debug("ERROR: No reload function available!")
        Print("ERROR: No reload function available for reload")
        return
    end

    Debug("Executing ReloadUI()...")
    Print("Reloading UI...")

    -- Execute the reload
    local success, err = pcall(reloadFunction)
    if success then
        Debug("SUCCESS: UI reload completed!")
        Print("UI reload completed successfully!")
    else
        Debug("FAILED: " .. tostring(err))
        Print("FAILED: " .. tostring(err))
    end
end

-- Show reload required popup
local function ShowReloadPopup(profile)
    -- The XML frame should already be loaded and available
    if AutoSetupReloadPopup then
        -- Update message with profile info if available
        if profile and profile.name then
            AutoSetupReloadPopupMessage:SetText("AddOn configuration has changed for '" ..
                profile.name .. "'.\nA UI reload is required to apply changes.")
        else
            AutoSetupReloadPopupMessage:SetText(
                "AddOn configuration has changed.\nA UI reload is required to apply changes.")
        end

        -- Show the popup
        AutoSetupReloadPopup:Show()
    else
        -- Fallback to old method if XML frame not available
        Debug("AutoSetupReloadPopup XML frame not available, using fallback")
        Print("AutoSetupReloadPopup XML frame not available")
    end
end

-- Manual test function for reload functionality
local function TestReloadFunction()
    Debug("=== MANUAL RELOAD TEST ===")
    Debug("Testing reload function manually...")

    -- Detect available reload function
    local reloadFunction = DetectReloadFunction()

    if not reloadFunction then
        Debug("ERROR: No reload function available!")
        Print("ERROR: No reload function available for manual test")
        return
    end

    Debug("Using function: " .. (detectedReloadFunction == C_UI.Reload and "C_UI.Reload()" or "ReloadUI()"))

    -- Test immediate execution
    Debug("Testing immediate execution...")
    local success, err = pcall(reloadFunction)
    if success then
        Debug("SUCCESS: Manual reload worked immediately!")
        Print("SUCCESS: Manual reload worked immediately!")
    else
        Debug("FAILED: " .. tostring(err))
        Print("FAILED: " .. tostring(err))
    end
end

local function ApplyAddonSet(profile, verbose)
    if not profile or not profile.addonSet then return end
    if InCombatLockdown() then
        if verbose then Print("Cannot change AddOn state in combat.") end
        return
    end

    local addonSet = profile.addonSet
    local numAddOns = (C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or GetNumAddOns()
    local changed = false

    local function GetEnabledState(name, index)
        if C_AddOns and C_AddOns.GetAddOnEnableState then
            -- Retail-style API: first argument is the addon name or index
            return C_AddOns.GetAddOnEnableState(name or index) > 0
        else
            local _, _, _, enabled = GetAddOnInfo(name or index)
            return not not enabled
        end
    end

    local function EnableAddon(name, index)
        if C_AddOns and C_AddOns.EnableAddOn then
            C_AddOns.EnableAddOn(name or index)
        else
            EnableAddOn(name or index)
        end
    end

    local function DisableAddon(name, index)
        if C_AddOns and C_AddOns.DisableAddOn then
            C_AddOns.DisableAddOn(name or index)
        else
            DisableAddOn(name or index)
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
        Debug("AddOn changes detected: Showing reload popup")
        -- Show popup instead of auto-reload
        ShowReloadPopup(profile)

        if verbose then
            Print("AddOn configuration changed for this resolution. Please click 'Reload UI' to apply changes.")
        end
    elseif verbose then
        Debug("No AddOn changes detected - configuration already matches profile")
        Print("AddOn configuration already matches profile.")
    end
end

-------------------------------------------------------------------------------
-- UI scale + profile evaluation
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

    -- Avoid redundant layout switches and chat spam if we already applied this layout
    if layoutToUse and layoutToUse ~= "" then
        local layoutClean = CleanString(layoutToUse)
        if layoutClean ~= "" and layoutClean ~= lastAppliedLayoutClean then
            ApplyEditLayout(layoutToUse, verbose)
        end
    end

    ApplyAddonSet(profile, verbose)
end

-------------------------------------------------------------------------------
-- Resolution monitoring (observe‑only)
-- We never change the user's resolution; we only respond to changes.
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

        -- Execute any queued auto-reload after PLAYER_ENTERING_WORLD
        ExecuteQueuedAutoReload(true)

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
    elseif msg == "testreload" then
        TestReloadFunction()
        return
    end

    if AutoSetup_OpenOptionsPanel then
        AutoSetup_OpenOptionsPanel()
    else
        Print("Options panel not available.")
    end
end
