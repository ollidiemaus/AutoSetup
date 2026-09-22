# AutoSetup — Copilot Instructions

## Project overview

A World of Warcraft addon (Lua + XML, no external libraries). It detects the
current screen resolution and applies a matching per-resolution profile: an
Edit Mode layout, an optional UI scale, and an addon enable/disable set. Aimed
at players who switch devices (PC, laptop, Steam Deck) at different
resolutions.

## Files & load order

Per `AutoSetup.toc` (in this order):

- `AutoSetup.lua` — core: resolution detection, profile storage, layout/scale/
  addon application, event loop, reload, slash commands. Exposes shared
  helpers on the `AutoSetup` table (also assigned to `_G.AutoSetup`, since XML
  `<OnClick>`/`<OnLoad>` scripts only see globals, not Lua file-locals).
- `FrameXML/AutoSetup_Options.lua` + `.xml` — Settings panel: profile CRUD,
  addon-name parsing/resolution, Edit Mode layout picker.
- `FrameXML/AutoSetup_ReloadPopup.xml` — "reload required" dialog; its button
  calls `AutoSetup.ExecuteReload()`.

`SavedVariables: AutoSetupDB` is the only persisted table, keyed by resolution
string (e.g. `AutoSetupDB["1920x1080"]`).

## Core flow

1. `ADDON_LOADED` (own addon) → init `AutoSetupDB`, purge legacy `autoReload`
   fields from old saved profiles, prime the chat-suppression cache, start a
   20s fallback ticker.
2. `PLAYER_ENTERING_WORLD` → after a 4s delay, run the first
   `EvaluateProfileState(true)` (guarded by `initDone`; `EDIT_MODE_LAYOUTS_UPDATED`
   can also trigger this first run — whichever fires first wins, not both).
3. `DISPLAY_SIZE_CHANGED` / `UI_SCALE_CHANGED` → primary resolution-change
   detection; 0.1s defer then `CheckResolutionChange()`.
4. The 20s ticker also calls `CheckResolutionChange()` — a fallback only, for
   cases the two events above don't catch.
5. `PLAYER_TARGET_CHANGED`, `PLAYER_SOFT_ENEMY_CHANGED`,
   `PLAYER_REGEN_DISABLED/ENABLED` → re-evaluate (base ↔ target layout switch),
   once `initDone`.
6. `EvaluateProfileState()` → looks up the profile for the current resolution,
   applies scale, layout (base or target depending on combat/target state),
   and the addon set; updates the `currentSuppressChat` cache.

## Profile schema

```lua
profile = {
  name = "Display name",               -- e.g. "Steam Deck 1280x800"
  editLayoutBase = "MyBaseLayout",
  editLayoutTarget = "MyCombatLayout",  -- optional; used in combat or with a target
  scale = 0.85,                         -- optional UI scale override
  suppressChat = true,                  -- suppress "layout applied" chat messages
  addonSet = { AddonName = true/false }, -- only listed addons are touched
}
```

## Conventions

- **Combat lockdown**: never mutate layout, scale, or addon state while
  `InCombatLockdown()` is true. Every mutating function already guards this
  itself (`ApplyEditLayoutInternal`, `ApplyScale`, `ApplyAddonSet`,
  `AutoSetup.ExecuteReload`) — don't add a second guard at the call site.
- **Resolution string**: always `WIDTHxHEIGHT` from `GetPhysicalScreenSize()`
  (falls back to parsing the `gxWindowedResolution`/`gxResolution` CVars). Use
  `AutoSetup.GetCurrentResolution()` from other files rather than
  reimplementing it.
- **WoW API fallback idiom**: check the `C_AddOns`/`C_EditMode`/`C_UI`
  namespace first, fall back to the legacy global. Reuse `GetAddOnCount()` /
  `GetAddOnNameAndTitle()` (exposed on `AutoSetup`) instead of reimplementing
  addon-list iteration again.
- **Reload**: always go through `AutoSetup.ExecuteReload()` — it checks combat
  lockdown, then tries `ReloadUI()`/`C_UI.Reload()`. Never call those directly.
- **Layout name comparison**: run both sides through `CleanString()` (strips
  color codes, trims, lowercases) before comparing; `lastAppliedLayoutClean`
  avoids redundant re-application.
- **Chat suppression**: read the cached `currentSuppressChat` (kept up to date
  inside `EvaluateProfileState`) — don't look up the profile per chat line.
- **Self-protection quirk**: `ApplyAddonSet` forces `desired = true` for
  AutoSetup's own addon name, so it can never disable itself even if listed
  with `!`.
- `Debug(msg)` logs to the rolling in-memory buffer only; `Print(msg)` does
  that *and* prints to chat with the addon's color prefix.

## Common tasks

**Add a new profile field**: default it in `EnsureProfile()` → wire a control
in `AutoSetup_OptionsPanel_OnLoad()` → read/write it in the save button's
`OnClick` → display it in `RefreshProfileList()`.

**New WoW patch**: bump `## Interface:` in `AutoSetup.toc`; re-check that
`C_AddOns`/`C_EditMode`/`C_UI` calls still resolve; watch for new
combat-lockdown restrictions.

## Debugging

- `/autosetup` or `/as` — opens the options panel.
- `/autosetup debug` — prints current resolution + the rolling debug log.
- `/autosetup testreload` — runs the real `AutoSetup.ExecuteReload()` path
  (will actually reload the UI unless you're in combat).
