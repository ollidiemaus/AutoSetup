### Repo overview

- This is a World of Warcraft AddOn named `AutoSetup` (see `AutoSetup.toc`).
- Primary runtime files: `AutoSetup.lua` (core logic) and `FrameXML/AutoSetup_Options.lua` + `FrameXML/AutoSetup_Options.xml` (options UI).
- Persistent state lives in the saved-variables table `AutoSetupDB` (declared in `AutoSetup.toc` via `## SavedVariables`).

### Big picture / intent

- Purpose: apply resolution-specific Edit Mode layouts, UI scale, and AddOn enable/disable profiles automatically when resolution or player state changes.
- Data model: profiles keyed by resolution strings (e.g. `1920x1080`). Each profile shape discovered in code: `name`, `editLayoutBase`, `editLayoutTarget`, `scale`, `suppressChat`, `addonSet` (map of addon folder names -> boolean).
- Key flows:
  - On load / PLAYER_ENTERING_WORLD: call `EvaluateProfileState()` which reads `AutoSetupDB[resolution]` and runs `ApplyScale`, `ApplyEditLayout`, `ApplyAddonSet`.
  - Resolution polling: `C_Timer.NewTicker(5.0, CheckResolutionChange)` monitors resolution changes and reapplies.
  - UI interactions: the XML file wires `AutoSetup_OptionsPanel_OnLoad` which manipulates `AutoSetupDB` via `AutoSetup.EnsureProfile` and `AutoSetup.GetDB`.

### Important files / symbols

- `AutoSetup.lua` — core runtime behaviour, helpers and event handlers. Key functions: `AutoSetup.EnsureProfile`, `AutoSetup.GetProfileForResolution`, `ApplyEditLayout`, `ApplyAddonSet`, `ApplyScale`, `EvaluateProfileState`.
- `FrameXML/AutoSetup_Options.lua` & `.xml` — settings UI, parsing helpers (`ParseAddonsString`, `ResolveAddonNames`, `BuildAddonsString`) and examples of how users enter addon lists.
- `AutoSetup.toc` — lists the files loaded by WoW; keep it in sync when moving files.

### Project-specific conventions & patterns

- Resolution keys are literal strings returned by `GetPhysicalScreenSize()` or `GetCVar("gxResolution")` (code uses `GetCurrentResolution()`); treat them as exact keys.
- Addon enable/disable mapping: user-entered list is parsed into a map where `"Name"` => enable and `"!Name"` => disable; resolution profiles store resolved folder names in `addonSet`.
- Do not disable `AutoSetup` itself — the runtime enforces this when applying `addonSet`.
- Use provided helper APIs rather than manipulating `AutoSetupDB` directly when possible: prefer `AutoSetup.EnsureProfile(res)` and `AutoSetup.GetDB()`.

### Integration points & external dependencies

- Uses Blizzard API modules: `C_AddOns`, `C_EditMode`, `EditModeManagerFrame`, `C_Timer` and standard UI APIs (`CreateFrame`, `Settings`, `InterfaceOptions_*`).
- When calling AddOn APIs, code uses fallbacks for older global functions (`GetAddOnInfo`, `EnableAddOn`) — preserve that compatibility.

### Debugging & developer workflows

- Quick runtime checks inside the game client:
  - Open options via `/autosetup` or `/as` (calls `AutoSetup_OpenOptionsPanel`).
  - View debug log: `/autosetup debug` prints `debugLog` entries (see `SLASH_AUTOSETUP` handler in `AutoSetup.lua`).
  - To test AddOn state changes, update an `AutoSetupDB` profile then either trigger `EvaluateProfileState()` from code or reload the UI (`/reload`).
- There is no build step — to test changes, copy the addon folder to your WoW `Interface/AddOns` directory and reload the client or `/reload` in-game.

### Editing guidance for contributors (AI agents)

- When changing behavior that touches saved data, keep `AutoSetupDB` shape backwards compatible.
- Prefer using existing helpers (e.g. `ParseAddonsString`, `ResolveAddonNames`) when modifying UI code in `FrameXML/AutoSetup_Options.lua`.
- If you add new saved fields, document them and provide sensible defaults in `defaultDB` inside `AutoSetup.lua`.
- Event registrations live in `AutoSetup.lua` — adding new events should be done alongside careful combat-lockdown checks (the code already guards many operations with `InCombatLockdown()`).

### Examples to reference in PRs or patches

- To change how a profile is initialized, update `EnsureProfile` in `AutoSetup.lua` (it currently sets `name`, `editLayoutBase`, `editLayoutTarget`, `scale`, `suppressChat`, `addonSet`).
- To change layout selection logic, edit `EvaluateProfileState()` and `ApplyEditLayoutInternal()` (they handle active layout discovery and retrying).
- To change addon parsing UI behavior, modify `ParseAddonsString` / `ResolveAddonNames` in `FrameXML/AutoSetup_Options.lua`.

If any of the above areas are unclear or you want me to include more examples (e.g., common edits, PR templates, or test steps), tell me which part to expand and I will iterate.
