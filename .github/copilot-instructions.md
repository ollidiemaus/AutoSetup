# AutoSetup AI Coding Instructions

## Project Overview

AutoSetup is a **World of Warcraft addon** (Lua + XML) that automatically applies per-resolution profiles for Edit Mode layouts, UI scale, and addon enable/disable sets. Players switch between devices (PC, laptop, Steam Deck) at different resolutions; AutoSetup detects resolution and applies the right profile.

**Key insight:** This addon solves "friction on low-playtime" by automating multi-device WoW setup—reducing manual Edit Mode/AddOns screen interaction each session.

## Architecture & Key Components

### Core Event Loop (`AutoSetup.lua`)

- **Entry point:** `ADDON_LOADED` event initializes `AutoSetupDB` (SavedVariables table)
- **Main flow:**
  1. `PLAYER_ENTERING_WORLD` → evaluates profile after 4s delay
  2. `CheckResolutionChange()` runs every 5 seconds (monitors resolution changes)
  3. `EvaluateProfileState()` applies scale, layout, and addon set for current resolution
  4. Combat/target events trigger re-evaluation (switches base ↔ target layout as needed)

### Profile Structure

```lua
profile = {
  name = "Display name", -- e.g., "Steam Deck 1280x800"
  editLayoutBase = "MyBaseLayout",
  editLayoutTarget = "MyCombatLayout",  -- optional; used in combat or with target
  scale = 0.85,  -- optional UI scale override
  suppressChat = true,  -- suppress "layout applied" messages
  autoReload = true,  -- auto-reload UI when addons change
  addonSet = {AddonName = true/false, ...}  -- only touched addons are modified
}
```

User resolution is the key: `AutoSetupDB["1920x1080"] = profile`

### Options Panel (`AutoSetup_Options.lua` + `.xml`)

- XML defines UI layout; Lua (`AutoSetup_OptionsPanel_OnLoad`) wires event handlers
- **Key patterns:**
  - `ParseAddonsString()` / `BuildAddonsString()`: parse user input `"Guild, !Raid, WeakAuras"`
  - `ResolveAddonNames()`: user types addon title ("WeakAuras") → resolves to folder name
  - `ShowLayoutPopup()`: dropdown list of available Edit Mode layouts (from `C_EditMode.GetLayouts()`)
  - `RefreshProfileList()`: renders scrollable profile list with edit/delete buttons
- `GetLayoutNames()` loads Blizzard_EditMode if needed; iterates `C_EditMode.GetLayouts().layouts`

### Reload Popup (`AutoSetup_ReloadPopup.xml`)

- Appears when addons are changed for a profile
- Two buttons: "ReloadUI" (calls `ExecuteImmediateAutoReload()`) or "Later"
- Message is set in `OnLoad` script after 0.1s delay to ensure child elements exist

## Critical Patterns & Developer Conventions

### WoW API Compatibility

- **Modern Retail vs Legacy:** Always check for `C_AddOns` namespace first, fall back to global functions:
  ```lua
  local numAddons = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns())
                   or GetNumAddOns()
  ```
- **Handling reload:** Multiple detection candidates (`C_UI.Reload`, `ReloadUI`, etc.); see `DetectReloadFunction()`
- Interface version: Check `.toc` file (currently `## Interface: 120000`)

### Combat Safety

- **Never modify state in lockdown:** Always check `InCombatLockdown()` before changing layouts, addon state, or scale
- Return silently if in combat; optionally log with `verbose` flag for debugging
- Exception: Layout re-evaluation still runs in combat (read-only check of active layout)

### Resolution Monitoring (Observe-Only)

- Never call `SetCVar("gxResolution")` or change actual screen resolution
- Detect via `GetPhysicalScreenSize()` → parse as `WIDTHxHEIGHT` string
- Check every 5 seconds; apply profile when resolution changes

### String Normalization for Layout Names

- **`CleanString()`:** Remove color codes (`|cXXXXXXXX`, `|r`), links, trim, lowercase
- Used to compare layout names from user input vs. system internals
- Example: user types "My Layout" → cleaned to "my layout" → matched against system "My Layout" (cleaned to "my layout")
- Store `lastAppliedLayoutClean` to avoid redundant layout switches

### Debug Logging

- In-memory rolling log (max 50 entries) stored in `debugLog` table
- `/autosetup debug` displays current resolution + full debug log in chat
- Use `Debug(msg)` for info, `Print(msg)` for user-facing messages (includes chat prefix)
- Log timestamps on all entries for troubleshooting

### Addon Set Application

- **Quirk:** AutoSetup addon itself is never disabled even if listed with `!` prefix
- Use `C_AddOns.GetAddOnEnableState()` (returns 0=disabled, 1=enabled by default, 2=enabled by user)
- Only touch addons that appear in `profile.addonSet`; leave others untouched
- If changes detected, show reload popup (not auto-reload immediately unless profile has `autoReload = true`)

### XML Reference Pattern

- XML children auto-registered by frame name prefix: `<EditBox name="$parentNameInput">` → accessible as `panel.nameInput` in Lua
- See `AutoSetup_OptionsPanel_OnLoad()`: resolves all children by building names like `baseName .. "NameInput"`
- Anchors use `relativeTo="$parent"` and `relativePoint` for responsive positioning

## Testing & Debugging

- **Debug logging:** Use `/autosetup debug` to dump resolution history and recent operations
- **Manual reload test:** `/autosetup testreload` to test reload function detection (logs all attempts)
- **Slash commands:** `/autosetup` or `/as` opens options panel
- **Key WoW events to understand:**
  - `ADDON_LOADED` – fires when addon loads; before SavedVariables are available
  - `PLAYER_ENTERING_WORLD` – fires on login/zoning; 4-second delay before profile eval
  - `EDIT_MODE_LAYOUTS_UPDATED` – fires when layouts change or EditMode loads
  - `PLAYER_TARGET_CHANGED`, `PLAYER_SOFT_ENEMY_CHANGED` – trigger layout re-eval

## Common Tasks

**Adding a new profile field:**

1. Add to profile structure in `EnsureProfile()`
2. Update `RefreshProfileList()` to display it
3. Wire UI control in `AutoSetup_OptionsPanel_OnLoad()`
4. Add save logic in saveButton's `OnClick` handler

**Debugging profile not applying:**

1. Run `/autosetup debug` → check if resolution string matches a saved profile key
2. Verify `PLAYER_ENTERING_WORLD` fired (4s delay applies profile)
3. If in combat, layout/addon changes are skipped (expected behavior)
4. Check `debugLog` for `"Switching to Edit Mode layout"` line; if missing, layout not found

**Handling new WoW patches:**

- Update `## Interface:` in `.toc` file
- Test addon API calls (especially `C_AddOns`, `C_EditMode`, `C_UI.Reload`)
- Check for conflicts with new combat-lockdown restrictions

## Key Files Reference

- [AutoSetup.lua](AutoSetup.lua) – Core event loop, profile evaluation, layout/addon/scale application
- [AutoSetup_Options.lua](FrameXML/AutoSetup_Options.lua) – Options UI controller (profile CRUD, layout picker)
- [AutoSetup_Options.xml](FrameXML/AutoSetup_Options.xml) – Options panel layout definition
- [AutoSetup_ReloadPopup.xml](FrameXML/AutoSetup_ReloadPopup.xml) – Reload confirmation dialog
- [AutoSetup.toc](AutoSetup.toc) – Addon metadata and load order
- [README.md](README.md) – User-facing feature documentation
