-- AutoSetup
-- Per‑resolution profiles that:
--   * apply a chosen Edit Mode layout (and optional combat/target layout)
--   * optionally set a UI scale
--   * enable/disable a set of addons
--   * optionally turn the game's Damage Meter on or off

local addonName, AutoSetup = ...
AutoSetup = AutoSetup or {}
_G.AutoSetup = AutoSetup -- expose to XML <OnClick>/<OnLoad> scripts, which only see globals

local debugLog = {}                -- rolling in‑memory log for /autosetup debug
local lastResolution = nil         -- last resolution string we evaluated
local initDone = false             -- the one verbose evaluation per login/reload has run (see RunInitialEvaluation)
local applyAfterCombat = false     -- the last full evaluation ran in combat; run it again once combat ends
local lastAppliedControllerSupport = nil -- the controller support state the last evaluation saw the profile want; a mismatch is reported once per state
local controllerSupportChangedThisSession = false -- our SetCVar took this session; Edit Mode won't offer the new mode's layouts until the next reload
local controllerSupportSetAtLogin = false -- our SetCVar took at PLAYER_LOGIN; the initial evaluation asks for the follow-up reload
local controllerSupportBlocked = false -- the game refused our SetCVar at PLAYER_LOGIN
local controllerAutoReloadAllowed = false -- set at ADDON_LOADED; false right after an automatic reload (TakeControllerReloadMark)

-- Native controller support (WoW Forever): confirmed by diffing config-cache.wtf before/after
-- toggling the setting in Forever's Options menu -- the only line that changed was
-- InputDeviceInterfaceStyle going from unset (default 0) to "1".
local CONTROLLER_SUPPORT_CVAR = "InputDeviceInterfaceStyle"

-- CVars are written through the C API, not the game's Lua SetCVar wrapper around it: a Blizzard Lua
-- function called from addon code runs tainted.
local GetCVarValue = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVarValue = (C_CVar and C_CVar.SetCVar) or SetCVar

-- Native controller support needs the game's controller interface: on Forever, not on Retail.
-- Checked by capability, not flavor, so a client that adds it later gets the option too. The
-- C_InputInterfaceStyle namespace alone isn't enough:
-- Retail 12.1.7 ships it without the interface. Like Blizzard's InputUtil.IsGamepadUISupported(),
-- also require the CVar to exist.
AutoSetup.hasControllerInterface = C_InputInterfaceStyle ~= nil and GetCVar(CONTROLLER_SUPPORT_CVAR) ~= nil

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

AutoSetup.GetCurrentResolution = GetCurrentResolution

-------------------------------------------------------------------------------
-- SavedVariables helpers
-------------------------------------------------------------------------------

-- AutoSetupDB = { version = DB_VERSION, profiles = { ["WIDTHxHEIGHT"] = profile } }. The unversioned
-- shape before it, with the profiles at the top level, is version 1.
local DB_VERSION = 2

-- The table the profile database functions read and write: AutoSetupDB.profiles once LoadDB has run.
-- When the saved data can't be used (a failed migration), it stays a table that lives for this session
-- only, so the client writes the saved data back as it was.
local profiles = {}

-- Migrations[n](data) returns the version n data as version n + 1. Each runs once per saved file:
-- MigrateDB stores the new version number with the result.
local Migrations = {
    -- 1 -> 2: profiles move under their own key, the old auto-reload flag and suppressChat go, and
    -- features of renamed providers take the new name. When both names are saved, the new one's value stays.
    [1] = function(data)
        local renamedProviders = { ForeverQoL = "QoL" } -- Forever QoL became Quality of Life
        local migrated = {}
        for resolution, profile in pairs(data) do
            if type(profile) == "table" then
                profile.autoReload = nil
                profile.suppressChat = nil
                local featureSet = profile.featureSet
                if type(featureSet) == "table" then
                    local newKeys = {}
                    for key in pairs(featureSet) do
                        local provider, feature = AutoSetup.SplitFeatureKey(key)
                        local renamed = provider and renamedProviders[provider]
                        if renamed then newKeys[key] = renamed .. ":" .. feature end
                    end
                    for key, newKey in pairs(newKeys) do
                        if featureSet[newKey] == nil then featureSet[newKey] = featureSet[key] end
                        featureSet[key] = nil
                    end
                end
                migrated[resolution] = profile
            end
        end
        return { profiles = migrated }
    end,
}

-- Migrate a copy of the saved data from version to DB_VERSION, one version at a time, so a step that
-- fails leaves the saved data as it was.
local function MigrateDB(db, version)
    local data = CopyTable(db)
    while version < DB_VERSION do
        local migrate = Migrations[version] or error("no migration from saved data version " .. tostring(version))
        data = migrate(data)
        version = version + 1
        data.version = version
    end
    return data
end

-- Run once, at ADDON_LOADED. Data from a newer AutoSetup, or data that fails to migrate, is left as it
-- is: no migration runs on it and nothing resets it. A newer file's profiles still apply, from a copy,
-- so nothing this version does can write its shape into the file.
local function LoadDB()
    if AutoSetupDB == nil then
        AutoSetupDB = { version = DB_VERSION, profiles = {} }
    elseif type(AutoSetupDB) == "table" then
        local version = AutoSetupDB.version
        if version == nil then version = 1 end
        if type(version) == "number" and version < DB_VERSION then
            local ok, migrated = xpcall(MigrateDB, CallErrorHandler, AutoSetupDB, version)
            if ok then
                AutoSetupDB = migrated
                Debug("Saved data migrated from version " .. version .. " to " .. DB_VERSION .. ".")
            end
        end
    end

    local db = AutoSetupDB
    if type(db) == "table" and db.version == DB_VERSION and type(db.profiles) == "table" then
        profiles = db.profiles
    elseif type(db) == "table" and type(db.version) == "number" and db.version > DB_VERSION
        and type(db.profiles) == "table" then
        profiles = CopyTable(db.profiles)
        Print("These saved profiles are from a newer AutoSetup. They apply, but profile changes "
            .. "made this session won't be saved.")
    else
        Print("Couldn't read the saved profiles. They are kept as they were, "
            .. "and profile changes made this session won't be saved.")
    end
end

-- AutoSetupDB.reloadedForController marks that the last session ended with the automatic reload
-- after a controller support change (RunInitialEvaluation), so a change that doesn't survive the
-- reload can't reload forever: the session after one never reloads by itself. Optional, absent
-- means false, so no DB_VERSION bump. Only saved data of this version carries it; without it
-- (a newer file, unreadable data) there is no automatic reload at all.
local function TakeControllerReloadMark()
    if type(AutoSetupDB) ~= "table" or AutoSetupDB.version ~= DB_VERSION then return true end
    local marked = AutoSetupDB.reloadedForController == true
    AutoSetupDB.reloadedForController = nil
    return marked
end

local function SetControllerReloadMark()
    AutoSetupDB.reloadedForController = true
end

local function GetProfileForResolution(resolution)
    return profiles[resolution]
end

-- Ensure and return a profile table for a given resolution key.
local function EnsureProfile(resolution)
    profiles[resolution] = profiles[resolution] or {
        name = resolution,
        editLayoutBase = nil,
        editLayoutTarget = nil,
        scale = nil,
        nativeControllerSupport = false,
        addonSet = nil, -- [addonName] = true/false
        featureSet = nil, -- ["Addon:feature"] = true/false
        damageMeter = nil, -- true = On, false = Off, nil = Leave alone
    }
    return profiles[resolution]
end

local function DeleteProfile(resolution)
    profiles[resolution] = nil
end

-- Iterate all profiles: for resolution, profile in IterateProfiles() do ... end
local function IterateProfiles()
    return next, profiles, nil
end

AutoSetup.GetProfileForResolution = GetProfileForResolution
AutoSetup.EnsureProfile = EnsureProfile
AutoSetup.DeleteProfile = DeleteProfile
AutoSetup.IterateProfiles = IterateProfiles

-------------------------------------------------------------------------------
-- AddOn iteration helpers (shared with the options panel)
-------------------------------------------------------------------------------

local function GetAddOnCount()
    return (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or GetNumAddOns()
end

local function GetAddOnNameAndTitle(index)
    if C_AddOns and C_AddOns.GetAddOnInfo then
        return C_AddOns.GetAddOnInfo(index)
    end
    return GetAddOnInfo(index)
end

-- Without a character the state covers all characters, like EnableAddOn and DisableAddOn below.
-- "Some" (enabled on other characters only, say) matches neither wish, so it gets changed.
local function IsInDesiredState(name, index, desired)
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        local state = C_AddOns.GetAddOnEnableState(name or index)
        return state == (desired and Enum.AddOnEnableState.All or Enum.AddOnEnableState.None)
    end
    local _, _, _, enabled = GetAddOnInfo(name or index)
    return (not not enabled) == desired
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

AutoSetup.GetAddOnCount = GetAddOnCount
AutoSetup.GetAddOnNameAndTitle = GetAddOnNameAndTitle

-------------------------------------------------------------------------------
-- Edit Mode layout switching
-------------------------------------------------------------------------------

-- Bumped by every ApplyEditLayout call, so a pending retry gives way to a newer request instead of
-- switching to a layout that's no longer wanted.
local layoutRequest = 0

-- Raw layout name -> CleanString result, so target changes don't rebuild the same strings. Wiped by
-- every full evaluation (CacheProfileLayouts), which keeps it to the layouts of this session.
local cleanedLayoutNames = {}

local function CleanLayoutListName(name)
    if not name then return "" end
    local clean = cleanedLayoutNames[name]
    if not clean then
        clean = CleanString(name)
        cleanedLayoutNames[name] = clean
    end
    return clean
end

local function ApplyEditLayoutInternal(targetNameClean, attemptsLeft, verbose, request)
    if request ~= layoutRequest then return end

    if InCombatLockdown() then
        -- Never touch layouts in combat; just bail quietly.
        if verbose then Print("Cannot change Edit Mode layout in combat.") end
        return
    end

    if not EditModeManagerFrame then
        C_AddOns.LoadAddOn("Blizzard_EditMode")
    end
    local manager = EditModeManagerFrame

    -- Don't switch layouts under the player while Edit Mode is open, it would throw away their
    -- unsaved changes. The EditMode.Exit callback applies the profile's layout afterwards.
    if manager and manager:IsEditModeActive() then return end

    local ready = manager and manager:IsInitialized()
    local foundIndex, foundName
    if ready then
        local activeInfo = manager:GetActiveLayoutInfo()
        if activeInfo and CleanLayoutListName(activeInfo.layoutName) == targetNameClean then
            return
        end

        for i, layoutInfo in ipairs(manager:GetLayouts()) do
            if CleanLayoutListName(layoutInfo.layoutName) == targetNameClean then
                foundIndex = i
                foundName = layoutInfo.layoutName
                break
            end
        end
    end

    if foundIndex then
        -- The manager's list (presets, then saved layouts) uses the API's layout index. Not
        -- manager:SelectLayout, which calls the same API but also prints "layout applied" in chat.
        C_EditMode.SetActiveLayout(foundIndex)
        if verbose then
            Debug("Switched to Edit Mode layout '" .. foundName .. "' (index " .. foundIndex .. ")")
            Print("Switched to layout '" .. foundName .. "'.")
        end
    elseif attemptsLeft > 0 and not ready then
        -- Only the layouts arriving late is worth a retry; a name missing from a loaded list stays missing.
        C_Timer.After(1.0, function()
            ApplyEditLayoutInternal(targetNameClean, attemptsLeft - 1, verbose, request)
        end)
    elseif verbose then
        Print("Could not find Edit Mode layout for '" .. targetNameClean .. "'.")
    end
end

-- Takes a name already cleaned with CleanString; nil leaves Edit Mode alone.
local function ApplyEditLayout(layoutNameClean, verbose)
    if not layoutNameClean then return end
    layoutRequest = layoutRequest + 1
    ApplyEditLayoutInternal(layoutNameClean, 3, verbose, layoutRequest)
end

-------------------------------------------------------------------------------
-- AddOn set switching
-- Profile.addonSet format:
--   [addonFolderName] = true  -- ensure addon is enabled
--   [addonFolderName] = false -- ensure addon is disabled
-- Only addons that appear in addonSet are touched; all others are left alone.
-- The AutoSetup addon itself is never disabled even if specified.
-------------------------------------------------------------------------------

-- Reload UI, respecting combat lockdown. This is the one code path used by
-- both the reload popup's button and the /autosetup testreload debug command.
function AutoSetup.ExecuteReload()
    if InCombatLockdown() then
        Debug("Cannot reload UI in combat. Reload skipped.")
        Print("Cannot reload UI in combat. Reload skipped.")
        return
    end

    Debug("Executing UI reload...")
    if C_UI and C_UI.Reload then
        C_UI.Reload()
    elseif ReloadUI then
        ReloadUI()
    else
        Debug("ERROR: No reload function available!")
        Print("ERROR: No reload function available for reload")
    end
end

-- Multiple independent things can require a reload at once (addon set, controller support).
-- Track each by a stable key so they combine into one popup listing every reason instead of
-- overwriting each other. Reset naturally on the next reload since this is a fresh session.
local pendingReloadReasons = {} -- key -> reason text

local function RefreshReloadPopupText()
    local lines = {}
    for _, text in pairs(pendingReloadReasons) do
        table.insert(lines, "- " .. text)
    end
    table.sort(lines)

    if AutoSetupReloadPopup then
        AutoSetupReloadPopupMessage:SetText("A UI reload is required:\n" .. table.concat(lines, "\n"))
    else
        Debug("AutoSetupReloadPopup XML frame not available, using fallback")
        Print("A UI reload is required: " .. table.concat(lines, "; "))
    end
end

-- Request a reload for a specific, stable `key` (e.g. "addonset", "controller"), with a short
-- human-readable `reason` explaining exactly why. Calling this again with the same key just
-- updates that one line rather than adding a duplicate.
local function ShowReloadPopup(key, reason)
    pendingReloadReasons[key] = reason
    RefreshReloadPopupText()
    if AutoSetupReloadPopup then
        AutoSetupReloadPopup:Show()
    end
end

local function ApplyAddonSet(profile, verbose)
    if not profile or not profile.addonSet then return end
    if InCombatLockdown() then
        if verbose then Print("Cannot change AddOn state in combat.") end
        return
    end

    local addonSet = profile.addonSet
    local numAddOns = GetAddOnCount()
    local changed = false

    for i = 1, numAddOns do
        local name = GetAddOnNameAndTitle(i)
        if name then
            local desired = addonSet[name]
            if desired ~= nil then
                if name == addonName then
                    desired = true
                end

                if not IsInDesiredState(name, i, desired) then
                    if desired then
                        EnableAddon(name, i)
                        if verbose then Debug("Enabling addon: " .. name) end
                    else
                        DisableAddon(name, i)
                        if verbose then Debug("Disabling addon: " .. name) end
                    end
                    changed = true
                end
            end
        end
    end

    if changed then
        -- Unsaved changes are lost when the game's AddOn list closes without saving (ResetAddOns).
        if C_AddOns and C_AddOns.SaveAddOns then C_AddOns.SaveAddOns() end
        Debug("AddOn changes detected: Showing reload popup")
        -- Show popup instead of auto-reload
        ShowReloadPopup("addonset", "AddOn configuration changed for '" .. (profile.name or "this profile") .. "'.")

        if verbose then
            Print("AddOn configuration changed for this resolution. Please click 'Reload UI' to apply changes.")
        end
    elseif verbose then
        Debug("No AddOn changes detected - configuration already matches profile")
    end
end

-------------------------------------------------------------------------------
-- Addon feature switching
-- Profile.featureSet format:
--   ["QoL:viewport"] = true  -- ensure the feature is on
--   ["QoL:viewport"] = false -- ensure the feature is off
-- Unlike addonSet this needs no reload: the provider addon applies the change live. Only features
-- that appear in featureSet are touched. If the provider isn't loaded (not installed, disabled, or
-- just enabled by this same profile and waiting for a reload) the entry is skipped.
-------------------------------------------------------------------------------

-- Addons that let AutoSetup switch their features: addon folder name -> name of the global API
-- table. The API provides IsFeatureEnabled(feature) (nil for an unknown feature) and
-- SetFeatureEnabled(feature, enabled) (false when the feature couldn't be set).
AutoSetup.FeatureProviders = {
    QoL = "QoLAPI",
}

-- The API table of a provider (folder name), or nil when it isn't loaded. A global that isn't a
-- table offering both functions (an outdated addon, another addon using the same name) counts as
-- not loaded.
function AutoSetup.GetFeatureProvider(provider)
    local globalName = provider and AutoSetup.FeatureProviders[provider]
    local api = globalName and _G[globalName]
    if type(api) == "table" and type(api.IsFeatureEnabled) == "function"
        and type(api.SetFeatureEnabled) == "function" then
        return api
    end
    return nil
end

-- Every call into a provider goes through here, so a broken provider only costs its own entries.
-- A failure goes to the error handler (BugSack, script errors) with the provider's own stack and
-- returns false; success returns true and the function's result.
function AutoSetup.CallFeatureProvider(func, ...)
    return xpcall(func, CallErrorHandler, ...)
end

-- "QoL:viewport" -> "QoL", "viewport". nil when the key has no feature part.
function AutoSetup.SplitFeatureKey(key)
    local provider, feature = tostring(key):match("^(.-):([^:]+)$")
    if provider and provider ~= "" then
        return provider, feature
    end
    return nil
end

local function ApplyFeatureSet(profile, verbose)
    if not profile or not profile.featureSet then return end

    for key, desired in pairs(profile.featureSet) do
        local provider, feature = AutoSetup.SplitFeatureKey(key)
        local api = AutoSetup.GetFeatureProvider(provider)
        if not api then
            if verbose then Debug("Feature provider not loaded, skipping: " .. tostring(key)) end
        else
            -- A failed call was reported by CallFeatureProvider; the entry is skipped.
            local ok, enabled = AutoSetup.CallFeatureProvider(api.IsFeatureEnabled, feature)
            if ok and enabled == nil then
                if verbose then Print("Unknown feature '" .. feature .. "' for " .. provider .. " in this profile.") end
            elseif ok and enabled ~= desired then
                local called, applied = AutoSetup.CallFeatureProvider(api.SetFeatureEnabled, feature, desired)
                if called and applied == false then
                    Debug("Feature " .. key .. " could not be set.")
                elseif called then
                    Debug("Feature " .. key .. " set to " .. tostring(desired))
                end
            end
        end
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
        SetCVarValue("useUiScale", "1")
        SetCVarValue("uiScale", tostring(profile.scale))
    elseif verbose then
        Debug("UI Scale already matches profile (" .. tostring(currentScale) .. ")")
    end
end

-- The game's real on/off for the Damage Meter; its frame listens for the CVar, so no reload is needed.
-- Edit Mode's ShowDamageMeter setting only controls the preview and is never read or written here.
local DAMAGE_METER_CVAR = "damageMeterEnabled"

-- nil (Leave alone) changes nothing, and nothing restores an earlier value. Only a client without
-- C_DamageMeter is skipped: IsDamageMeterAvailable() can change by character and the game's frame
-- checks it anyway. A change skipped in combat is caught up by EvaluateProfileState's applyAfterCombat.
local function ApplyDamageMeter(profile, verbose)
    if not profile or profile.damageMeter == nil or not C_DamageMeter then return end

    local desired = profile.damageMeter and "1" or "0"
    local current = GetCVarValue(DAMAGE_METER_CVAR)
    if not current or current == desired then return end

    if InCombatLockdown() then
        if verbose then Print("Cannot change the Damage Meter in combat.") end
        return
    end

    SetCVarValue(DAMAGE_METER_CVAR, desired)
    Debug("Damage Meter turned " .. (profile.damageMeter and "on" or "off") .. ".")
end

-- True when Edit Mode should be left alone because the input mode (keyboard/mouse vs. controller)
-- isn't settled: either we changed controller support this session (Edit Mode won't offer the
-- new mode's layouts until the next reload), or it doesn't match the profile, whose layouts belong
-- to the other mode.
local function IsInputModeUnsettled(profile)
    if not AutoSetup.hasControllerInterface then return false end
    local desired = profile.nativeControllerSupport or false
    return controllerSupportChangedThisSession or desired ~= (GetCVar(CONTROLLER_SUPPORT_CVAR) == "1")
end

-- InputDeviceInterfaceStyle is a protected CVar, and this is the only place that sets it. The game
-- answers an addon's SetCVar on it with ADDON_ACTION_BLOCKED, at PLAYER_LOGIN too (taint.log,
-- 2026-11-10: the addon's own call, nothing tainted before it; seen with the controller interface on
-- and a profile that wants it off). The call is made anyway, on purpose: the value still changes
-- and the switch works after a reload, which is worth the logged error. Likely why: the game's own
-- checkbox reloads the UI when toggled, with no reload in its Lua, so the client does that inside
-- the CVar change and refuses only that part to an addon (not confirmed).
-- Later in a session nothing tries: seen blocked there with the value left as it was. Read it back
-- to tell the two apart.
local function ApplyControllerSupportAtLogin()
    if not AutoSetup.hasControllerInterface or InCombatLockdown() then return end
    local res = GetCurrentResolution()
    local profile = GetProfileForResolution(res)
    local current = GetCVar(CONTROLLER_SUPPORT_CVAR)
    Debug("PLAYER_LOGIN: " .. res .. ", " .. CONTROLLER_SUPPORT_CVAR .. " = " .. tostring(current) ..
        ", profile: " .. tostring(profile and profile.name))
    if not profile then return end

    local desired = profile.nativeControllerSupport or false
    if desired == (current == "1") then return end

    Debug("Setting " .. CONTROLLER_SUPPORT_CVAR .. " to " .. (desired and "1" or "0"))
    SetCVarValue(CONTROLLER_SUPPORT_CVAR, desired and "1" or "0")
    if (GetCVar(CONTROLLER_SUPPORT_CVAR) == "1") == desired then
        controllerSupportChangedThisSession = true
        controllerSupportSetAtLogin = true
    else
        Debug("Setting " .. CONTROLLER_SUPPORT_CVAR .. " was blocked.")
        controllerSupportBlocked = true
    end
end

-- Reports the result; only ApplyControllerSupportAtLogin changes it. Setting the CVar alone doesn't
-- make it take functional effect -- confirmed in-game that a reload is still needed afterwards.
local function ReportControllerSupport(profile)
    if not profile or not AutoSetup.hasControllerInterface then return end

    local desired = profile.nativeControllerSupport or false
    local current = (GetCVar(CONTROLLER_SUPPORT_CVAR) == "1")
    local state = desired and "ON" or "OFF"
    local name = profile.name or "this profile"
    local setAtLogin = controllerSupportSetAtLogin
    controllerSupportSetAtLogin = false

    if desired == current then
        lastAppliedControllerSupport = desired
        if setAtLogin then
            ShowReloadPopup("controller", "Native controller support was just set to " .. state ..
                " for '" .. name .. "'. Reload once more to finish applying it.")
        end
        return
    end

    local isNewMismatch = (lastAppliedControllerSupport ~= desired)
    lastAppliedControllerSupport = desired

    if isNewMismatch then
        if controllerSupportBlocked then
            ShowReloadPopup("controller", "The game blocked setting controller support " .. state ..
                " for '" .. name .. "'. Reload to try again, or change it in Options > Controller.")
        else
            ShowReloadPopup("controller", "Controller support should be " .. state .. " for '" .. name ..
                "'. Reload to apply it, or change it in Options > Controller.")
        end
    end
end

-- The current profile and its layout names, cleaned, as of the last full evaluation
-- (CacheProfileLayouts), so target and combat events neither look up the profile nor clean names.
local layoutProfile = nil          -- profile for the current resolution, nil without one
local baseLayoutClean = nil        -- its base layout; nil when Edit Mode is left alone
local targetLayoutClean = nil      -- its target layout; nil without one or when Edit Mode is left alone

-- Cleaned name, or nil for no layout (empty or blank).
local function CleanLayoutName(name)
    local clean = CleanString(name)
    if clean ~= "" then return clean end
end

-- nil layouts leave Edit Mode alone: native controller support uses its own hidden default layout
-- that isn't selectable from GetLayouts() and can't coexist with a keyboard/mouse layout, so the
-- client manages it. Only relevant on clients with the controller interface -- elsewhere a stale
-- nativeControllerSupport value is ignored.
local function CacheProfileLayouts(profile)
    wipe(cleanedLayoutNames)
    layoutProfile = profile
    if not profile or (AutoSetup.hasControllerInterface and profile.nativeControllerSupport) then
        baseLayoutClean, targetLayoutClean = nil, nil
    else
        baseLayoutClean = CleanLayoutName(profile.editLayoutBase)
        targetLayoutClean = CleanLayoutName(profile.editLayoutTarget)
    end
end

-- The layout the profile wants right now: the target layout in combat or with a (soft) target,
-- the base layout otherwise.
local function GetDesiredLayout()
    if targetLayoutClean and (UnitAffectingCombat("player") or UnitExists("target") or UnitExists("softenemy")) then
        return targetLayoutClean
    end
    return baseLayoutClean
end

-- Switch to the layout the current profile wants right now. This is all that target and combat
-- changes do, so it stays cheap and leaves scale, addons, features and the Damage Meter alone.
local function UpdateLayout(verbose)
    -- Edit Mode won't offer the right layouts until the input mode is settled.
    if not layoutProfile or IsInputModeUnsettled(layoutProfile) then return end
    ApplyEditLayout(GetDesiredLayout(), verbose)
end

local eventFrame = CreateFrame("Frame")

-- Only needed to switch to the target layout, along with combat start. Combat end
-- (PLAYER_REGEN_ENABLED) isn't among them: it stays registered for the catch-up after an evaluation
-- that ran in combat, and to leave the target layout (or switch to it, if combat start couldn't)
-- once combat ends. It fires once per combat.
local TARGET_CHANGE_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED" }
local targetEventsRegistered = nil -- nil until the first evaluation, so that one always logs the state

-- Layouts can't change in combat and combat end looks at the target anyway, so these two are also
-- dropped for the length of a fight.
local function SetTargetChangeEvents(registered)
    for _, event in ipairs(TARGET_CHANGE_EVENTS) do
        if registered then eventFrame:RegisterEvent(event) else eventFrame:UnregisterEvent(event) end
    end
end

-- Listen to the target events only while a target layout applies, so without one AutoSetup does
-- next to nothing during play. Recomputed on every full evaluation, after CacheProfileLayouts and
-- ReportControllerSupport (an unsettled input mode leaves Edit Mode alone).
local function UpdateTargetEventRegistration()
    local wanted = targetLayoutClean ~= nil and not IsInputModeUnsettled(layoutProfile)
    if wanted == targetEventsRegistered then return end
    targetEventsRegistered = wanted
    SetTargetChangeEvents(wanted)
    if wanted then
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    else
        eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
    Debug(wanted and "Target layout applies: target and combat-start events registered."
        or "No target layout applies: target and combat-start events unregistered.")
end

-- Apply the whole profile for the current resolution: once per login/reload (verbose, see
-- RunInitialEvaluation), on a resolution change, after a profile is saved or deleted, and after
-- combat when it last ran in combat.
local function EvaluateProfileState(verbose)
    local res = GetCurrentResolution()
    lastResolution = res
    -- The Apply* functions skip what can't change in combat; catch up when it ends.
    applyAfterCombat = InCombatLockdown()

    local profile = GetProfileForResolution(res)
    CacheProfileLayouts(profile)
    if not profile then
        UpdateTargetEventRegistration()
        if verbose then Print("No AutoSetup profile for resolution " .. res .. ".") end
        return
    end

    if verbose then
        Print("Applying AutoSetup profile '" .. (profile.name or res) .. "' (" .. res .. ").")
    end

    ApplyScale(profile, verbose)
    ReportControllerSupport(profile)
    UpdateTargetEventRegistration()
    UpdateLayout(verbose)
    ApplyAddonSet(profile, verbose)
    ApplyFeatureSet(profile, verbose)
    ApplyDamageMeter(profile, verbose)
end

-- The one verbose evaluation per login/reload, on whichever comes first: Edit Mode's layouts
-- arriving or the fallback timer after PLAYER_ENTERING_WORLD. Login and reload start a fresh Lua
-- state, so the flag is never reset; loading screens (which fire PLAYER_ENTERING_WORLD too) don't
-- run it again. It is set before evaluating because switching layouts fires
-- EDIT_MODE_LAYOUTS_UPDATED synchronously, which would otherwise run the evaluation a second time.
-- That event only exists to trigger this evaluation, so stop listening to it.
local function RunInitialEvaluation()
    if initDone then return end
    initDone = true
    eventFrame:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    -- Controller support changed at login takes effect with a reload, like the game's own checkbox
    -- does it. Reload now, before applying a profile the reload would apply again. In combat, or
    -- right after such a reload, the evaluation shows the reload popup for it.
    if controllerSupportSetAtLogin and controllerAutoReloadAllowed and not InCombatLockdown() then
        SetControllerReloadMark()
        AutoSetup.ExecuteReload()
        return
    end
    EvaluateProfileState(true)
end

-- Used by the options panel after saving or deleting a profile. Before the initial evaluation there
-- is nothing to do, it picks the change up itself.
function AutoSetup.ApplyCurrentProfile()
    if initDone then EvaluateProfileState(false) end
end

-- Target/combat changes and leaving Edit Mode only need the layout of the current profile. Before
-- the initial evaluation there is no cached profile, so this does nothing.
local function UpdateCurrentLayout()
    UpdateLayout(false)
end

-- The player switched the controller interface in the game's options, which works without a reload.
-- That can settle the input mode (or unsettle it), and only a full evaluation would notice otherwise.
local function OnInputModeChanged()
    if not initDone then return end
    UpdateTargetEventRegistration()
    UpdateCurrentLayout()
end

-------------------------------------------------------------------------------
-- Resolution monitoring (observe‑only)
-- We never change the user's resolution; we only respond to changes.
-------------------------------------------------------------------------------

local function CheckResolutionChange()
    -- Size and scale events fire during login too; the initial evaluation covers those.
    if not initDone then return end
    local res = GetCurrentResolution()
    if res ~= lastResolution then
        Debug("Resolution changed from " .. tostring(lastResolution) .. " to " .. tostring(res))
        EvaluateProfileState(false)
    end
end

-- A window drag or a scale change fires a burst of size/scale events. The first one
-- schedules this check and later ones skip until it has run, so a burst costs one check.
local resolutionCheckPending = false

local function RunPendingResolutionCheck()
    resolutionCheckPending = false
    Debug("Resolution check after size/scale change.")
    CheckResolutionChange()
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

-- The target events are registered by UpdateTargetEventRegistration.
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
if AutoSetup.hasControllerInterface and C_EventUtils.IsEventValid("INPUT_DEVICE_INTERFACE_TRANSITION") then
    eventFrame:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        LoadDB()
        controllerAutoReloadAllowed = not TakeControllerReloadMark()
        Debug("AutoSetup loaded.")

        -- Safety net: DISPLAY_SIZE_CHANGED/UI_SCALE_CHANGED catch most changes, but some
        -- monitor changes (external displays, alt-tab) don't fire them reliably. Every
        -- 20 s is rare enough not to matter; a check that finds no change is one comparison.
        C_Timer.NewTicker(20.0, CheckResolutionChange)
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        -- Small defer: the new size/scale may lag the event by a frame.
        if not resolutionCheckPending then
            resolutionCheckPending = true
            C_Timer.After(0.1, RunPendingResolutionCheck)
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        ApplyControllerSupportAtLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Debug("PLAYER_ENTERING_WORLD. Current resolution: " .. GetCurrentResolution())
        -- Fallback in case EDIT_MODE_LAYOUTS_UPDATED doesn't come.
        if not initDone then
            C_Timer.After(4.0, RunInitialEvaluation)
        end
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        RunInitialEvaluation()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if targetEventsRegistered then SetTargetChangeEvents(true) end
        if applyAfterCombat then
            EvaluateProfileState(false)
        else
            UpdateCurrentLayout()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateCurrentLayout()
        SetTargetChangeEvents(false)
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_SOFT_ENEMY_CHANGED" then
        UpdateCurrentLayout()
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        -- Fires synchronously, possibly from inside our own SetCVar; look once it has finished.
        C_Timer.After(0, OnInputModeChanged)
    end
end)

-- Layout switches wait while Edit Mode is open (see ApplyEditLayoutInternal); catch up once it has
-- closed, outside Blizzard's exit code.
EventRegistry:RegisterCallback("EditMode.Exit", function()
    C_Timer.After(0, UpdateCurrentLayout)
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
        AutoSetup.ExecuteReload()
        return
    end

    if AutoSetup_OpenOptionsPanel then
        AutoSetup_OpenOptionsPanel()
    else
        Print("Options panel not available.")
    end
end
