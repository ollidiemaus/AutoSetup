# In-game test checklist

AutoSetup has no automated tests. Before a release, run this checklist on Retail and on WoW Forever.
Items marked **Retail only** or **Forever only** run on that flavor alone. Every check looks only at what the player sees or
what the game reports: the active layout, chat lines, errors, the saved variables file, the debug log
and the profiler. `docs/` is in `.pkgmeta`'s ignore list, so this file isn't in the release.

## Tools

- **`/as`** (or `/autosetup`): opens the options panel (profile list and form).
- **`/autosetup debug`**: prints the current resolution and the debug log (the last 50 lines, in
  memory only, cleared by a reload).
- **`/autosetup testreload`**: runs the real reload path (`AutoSetup.ExecuteReload`).
- **Errors**: BugSack (with BugGrabber), or without it `/console scriptErrors 1` so Lua errors show
  in the game's error frame. Turn one of them on before every run.
- **Saved variables file**: `WTF/Account/<ACCOUNT>/SavedVariables/AutoSetup.lua` inside the game
  folder (`_retail_` for Retail, `_classic_beta_` for Forever). The client reads it at login and
  overwrites it at logout or reload, so edit it only with the game closed, and look at it after
  logging out. Back it up before items 1 to 3 and put it back afterwards.
- **Event registration**: the event frame is local, so read it from the debug log. Every full
  evaluation (login, reload, resolution change, profile save or delete) whose result differs from
  the last one logs one of:
  - `Target layout applies: target and combat-start events registered.`
  - `No target layout applies: target and combat-start events unregistered.`

  The first evaluation after login always logs one. The events are `PLAYER_TARGET_CHANGED`,
  `PLAYER_SOFT_ENEMY_CHANGED` and `PLAYER_REGEN_DISABLED`; `PLAYER_REGEN_ENABLED` stays registered.
- **Profiler** (CPU time, ms per frame, averaged over recent frames):

  ```
  /dump C_AddOnProfiler.GetAddOnMetric("AutoSetup", Enum.AddOnProfilerMetric.RecentAverageTime)
  ```

  Read it after about 10 seconds of the activity being measured.
- **Layouts**: you need at least two saved Edit Mode layouts (e.g. `Base` and `Target`), made in
  Edit Mode, so a switch is visible: make them clearly different (move the player frame).

## Setup files

### Upgrade test file (item 2)

The unversioned shape before saved-data version 2: profiles at the top level, with the old
`autoReload` flag and `suppressChat`. Replace the resolutions with your own (`/autosetup debug`
prints it) so one profile applies, and the layout names with yours:

```lua
AutoSetupDB = {
    ["1920x1080"] = {
        ["name"] = "Desk",
        ["editLayoutBase"] = "Base",
        ["editLayoutTarget"] = "Target",
        ["scale"] = 0.8,
        ["nativeControllerSupport"] = false,
        ["suppressChat"] = true,
        ["autoReload"] = true,
        ["addonSet"] = {
            ["QoL"] = true,
        },
        ["featureSet"] = {
            ["ForeverQoL:viewport"] = true,
        },
    },
    ["2560x1440"] = {
        ["name"] = "Collision",
        ["editLayoutBase"] = "Base",
        ["featureSet"] = {
            ["ForeverQoL:viewport"] = false,
            ["QoL:viewport"] = true,
        },
    },
}
```

### Broken feature provider (item 11)

Needs Quality of Life (folder `QoL`, API global `QoLAPI`) loaded and a profile with a `QoL:viewport`
entry in its AddOns box. These lines break QoL's API for the session only; `/reload` restores it.

```
/run QoLAPI.SetFeatureEnabled = function() error("AutoSetup test: SetFeatureEnabled") end
/run QoLAPI.IsFeatureEnabled = function() error("AutoSetup test: IsFeatureEnabled") end
```

## Checklist

### 1. Fresh install

Setup: game closed, move `AutoSetup.lua` out of `SavedVariables`.

1. Log in. No errors.
2. Log out. The file reads `AutoSetupDB = { ["version"] = 2, ["profiles"] = {} }` (formatting aside).

### 2. Upgrade from unversioned saved data

Setup: game closed, put the [upgrade test file](#upgrade-test-file-item-2) in place.

1. Log in. No errors. `/autosetup debug` shows `Saved data migrated from version 1 to 2.` `/as`
   lists both profiles, and **Edit** on each fills the form with every setting (name, layouts,
   scale, AddOns box with `QoL:viewport` or `!QoL:viewport`).
2. Log out. In the file: `version` is 2, both profiles are under `profiles`, neither has
   `suppressChat` or `autoReload`, the first has `QoL:viewport = true` and no `ForeverQoL:` key, and
   `Collision` has only `QoL:viewport = true` (the `QoL:` value won).
3. Log in and out again. The file is the same as after step 2 and the debug log has no migration line.

### 3. Saved data from a newer AutoSetup

Setup: game closed, take the file from item 2 and change `["version"] = 2` to `["version"] = 3`.
Keep a copy.

1. Log in. No errors, no migration line in the debug log, the profiles are listed in `/as`.
2. Log out without saving or deleting a profile. The file matches the copy (key order aside).

### 4. Base and target layout switching

Setup: a profile for the current resolution with base `Base` and target `Target`. Stand near mobs.

1. Target a mob: the `Target` layout applies.
2. Clear the target (Escape): the `Base` layout applies.
3. Get into combat without a target (let a mob hit you, then clear the target): `Target` applies.
4. Leave combat: `Base` applies.
5. None of these switches prints "layout applied" (or any other line) in chat. No errors.

### 5. Picking a layout by hand

1. Open Edit Mode and pick another layout from its dropdown.
2. Blizzard's "layout applied" line shows in chat, as it does without AutoSetup.

### 6. Edit Mode open

Setup: the profile from item 4.

1. Open Edit Mode, then target a mob or clear the target. The layout doesn't change while it is open.
2. Close Edit Mode (keep or discard the changes). The layout for the current target state applies.

### 7. Target change in combat

Setup: the profile from item 4.

1. Target a mob and pull it, so combat starts with the `Target` layout.
2. In combat, clear the target and target it again a few times: no switch, no "action blocked"
   error or `ADDON_ACTION_BLOCKED` in BugSack.
3. Leave combat: the layout for the current target state applies, without errors.
4. Switches AutoSetup couldn't make before combat are caught up after it: open `/as` before a pull
   and keep it open, then in combat change the profile's target layout to another saved layout
   and save. No switch while in combat;
   once combat ends, the new target layout (or the base layout, without a target) applies.

### 8. Target events only while a target layout applies

1. With a profile that has no target layout (or no profile for this resolution), `/reload`, then
   `/autosetup debug`: it shows `No target layout applies: ... unregistered.` Turn on action
   targeting (or use soft targeting), walk through a group of mobs for about 10 seconds and read the
   profiler: close to zero.
2. In `/as`, give the profile a target layout and save. `/autosetup debug` shows
   `Target layout applies: ... registered.` Targeting a mob switches layouts, without a reload. Read
   the profiler again while soft-targeting through mobs, for comparison.
3. Remove the target layout and save. The debug log shows `... unregistered.` again and targeting
   no longer switches layouts.

### 9. Forever only: controller support on

Setup: a profile with native controller support on and a target layout, applied (accept the reload
prompts until the controller interface is on).

1. `/autosetup debug` after the last reload shows `No target layout applies: ... unregistered.`
2. Targeting mobs and entering combat don't change the Edit Mode layout.

### 10. Window resizing

Setup: windowed mode (Options > Graphics > Display Mode).

1. Drag the window edge for a few seconds, then `/autosetup debug`. Each burst of resizing shows one
   `Resolution check after size/scale change.` line, not one per event.
2. Make profiles for two window sizes (each with a different base layout), resize from one to the
   other (or move the window to a monitor with another resolution): once the size settles, the
   debug log shows `Resolution changed from ... to ...` and that size's profile applies.

### 11. Broken feature provider

Setup: QoL loaded, a profile for this resolution with base layout, scale and a QoL feature in the
AddOns box set to the opposite of QoL's current setting, so AutoSetup has to switch it
(`QoL:viewport` turns it on, `!QoL:viewport` off), plus another AddOns entry.

1. Run the `SetFeatureEnabled` line from [Broken feature provider](#broken-feature-provider-item-11),
   then save the profile in `/as` (which applies it). The error shows once in BugSack or the error
   frame. The layout and scale are applied and the save message, list refresh and AddOns entry are
   unaffected.
2. `/reload`, run the `IsFeatureEnabled` line, then save the profile with `QoL:viewport` again. The
   error shows (from the save's check and from the apply). `Saved AutoSetup profile for <res>.`
   prints, the list shows the saved profile and the rest of the profile is applied.
3. `/reload` to restore QoL.

### 12. Retail only: chat in restricted states

1. In a dungeon or raid encounter (or in the open world with the secret-value test CVars from the
   Warcraft Wiki's "Secret values" page turned on), with a target layout profile, let party, raid
   and system lines arrive while targeting switches layouts.
2. Every line reaches chat. AutoSetup raises no errors.

### 13. Options panel

1. Log in and open `/as` straight away: the profile list shows every profile.
2. There is no "Suppress chat" checkbox.
3. The native controller support checkbox shows on Forever and is hidden on Retail.
4. Save a new profile and delete one: the list updates each time while the panel is open. Close and
   reopen the panel: the list is still correct.

### 14. Reload popup

1. Save a profile for this resolution whose AddOns box changes an addon's state (e.g. `!SomeAddon`
   for an enabled addon). The popup lists the reason; with a controller change pending too (Forever),
   it lists both.
2. Click **Reload UI**: the UI reloads. Outside combat, `/autosetup testreload` reloads too; in
   combat it prints `Cannot reload UI in combat. Reload skipped.`
