-- Lint guards globals: a leaked global (wow-addon-standards T4) or a misspelled API name fails it.
-- Unused values and line length are left to review.
std = "lua51"
max_line_length = false
ignore = { "21" }
-- .lua/, .luarocks/ and .install/ are the toolchains the CI actions install into the workspace.
exclude_files = { ".git/", ".release/", ".lua/", ".luarocks/", ".install/" }

-- Globals the addon defines; the two AutoSetup_ functions are called from the options XML.
globals = {
    "AutoSetupDB",
    "SLASH_AUTOSETUP1", "SLASH_AUTOSETUP2",
    "SlashCmdList",
    "AutoSetup_OpenOptionsPanel",
    "AutoSetup_OptionsPanel_OnLoad",
}

-- WoW API the addon reads. Keep this list explicit: an unexpected global is usually a typo.
read_globals = {
    -- Lua extensions in the WoW client
    "date",
    -- Namespaces
    "C_AddOns", "C_EditMode", "C_InputInterfaceStyle", "C_Timer", "C_UI", "Settings", "EventRegistry",
    -- Frames and UI (AutoSetupReloadPopup* are named in FrameXML/AutoSetup_ReloadPopup.xml)
    "CreateFrame", "UIParent", "EditModeManagerFrame", "InterfaceOptionsFrame",
    "InterfaceOptionsFrame_OpenToCategory", "InterfaceOptions_AddCategory",
    "AutoSetupReloadPopup", "AutoSetupReloadPopupMessage",
    -- Addons
    "DisableAddOn", "EnableAddOn", "GetAddOnInfo", "GetNumAddOns", "LoadAddOn",
    -- Client
    "CallErrorHandler", "CopyTable", "GetBuildInfo", "GetCVar", "SetCVar", "GetPhysicalScreenSize",
    "InCombatLockdown", "ReloadUI", "UnitAffectingCombat", "UnitExists",
}
