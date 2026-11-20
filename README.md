## AutoSetup

AutoSetup is a World of Warcraft addon that automatically applies **per‑resolution profiles** for:

- **Edit Mode layouts** (base layout + optional combat/target layout, for keyboard and for controller)
- **UI scale**
- **AddOn enable/disable sets**
- **The game's Damage Meter** (on, off or left alone)

When you play on different devices (e.g. PC monitor, laptop, Steam Deck, TV) that run WoW at different resolutions, AutoSetup detects the current resolution and applies the right profile without you touching Edit Mode or the AddOns screen.

Works on Retail and WoW Forever.

---

### Why this addon exists

With a **newborn child**, playtime is short and precious.  
Switching between PC, laptop, and Steam Deck meant that every session started with:

- Manually picking the correct **Edit Mode layout** for that device
- Toggling a different set of **addons** on or off
- Adjusting **UI scale** so things were readable on small screens

AutoSetup removes that friction: once profiles are configured, you log in and just play. The addon quietly applies the correct layout, scale, and addon set based on the resolution WoW is currently running at.

---

### Features

- **Per‑resolution profiles**
  - Each profile is keyed by resolution (e.g. `1920x1080`, `1280x800`).
  - Store a friendly name, base layout, optional target/combat layout, scale, and addon set.

- **Base + target layout support**
  - `Base` layout is used out of combat / no target.
  - Optional `Target` layout is used when:
    - you are in combat, or
    - you have a target / soft enemy.
  - On WoW Forever each profile has a Base and Target layout for keyboard and for controller.
    AutoSetup uses the ones of the input mode the game is in, and switches right away when you
    toggle the controller interface in the game's options (no reload; in combat it waits until
    combat ends). A blank Base layout leaves Edit Mode alone in that input mode.

- **AddOn set management**
  - Per‑profile addon map: enable some addons, disable others.
  - Supports addon names with spaces and resolves titles (e.g. `Midnight Viewport`) to folder names.
  - Only touches the addons you list; everything else is left alone.

- **UI scale per profile**
  - Optional override for `uiScale` per resolution.

- **Damage Meter per profile**
  - Each profile can turn the game's Damage Meter on or off, or leave it alone, which is what a new profile does. No reload needed.
  - It is the same switch as the game's advanced options, not Edit Mode's Damage Meter checkbox, which only controls the preview shown while placing it.
  - Leave alone changes nothing, and nothing restores an earlier value: a profile that needs the Damage Meter on after a profile that turned it off should say On.

- **Controller support per profile (WoW Forever only)**
  - Leave alone (the default for a new profile), On or Off: which input mode the game starts in for this resolution. Leave alone never changes it, so you can switch between keyboard and controller freely on one screen.
  - It only sets the input mode; it never picks the profile, which always goes by resolution.
  - This setting doesn't exist on any other flavor, so the button is hidden unless the game has the controller interface.
  - With On or Off, AutoSetup switches it at login/reload and then **reloads the UI once by itself**, which is when the switch takes effect (the game's own checkbox reloads too). The game logs an "action blocked" error for AutoSetup when this happens; the switch works regardless.
  - The game doesn't let addons change it later in a session (e.g. right when you switch resolutions), and AutoSetup never reloads by itself in combat or twice in a row. In those cases it shows the "reload required" popup instead, and applies the layouts of the input mode the game is actually in.

- **Non‑intrusive behavior**
  - Never changes your actual resolution; it only **observes** it.
  - Skips layout and addon changes in combat to avoid taint.
  - Avoids redundant layout switches and stutter when you're already on the right layout.
  - Switches layouts quietly: AutoSetup's own switches print no "layout applied" line in chat. A layout you pick in Edit Mode yourself, or the one a specialization change brings, still shows Blizzard's message.

---

### Installation

1. Copy the `AutoSetup` folder into:
   - `World of Warcraft/_retail_/Interface/AddOns/AutoSetup/`
2. Restart WoW or run `/reload`.
3. Enable **AutoSetup** on the AddOns screen.

---

### Configuration

You can configure AutoSetup via:

- **Settings → AddOns → AutoSetup**, or
- The slash command: `/autosetup` (alias: `/as`)

In the options panel:

1. **Resolution**
   - Click **Use Current** to fill in the current resolution (e.g. `1920x1080`).
2. **Profile name**
   - Any descriptive name (e.g. `PC 1440p`, `Steam Deck`, `Laptop`).
3. **Base layout** (keyboard and controller on WoW Forever)
   - Either type the layout name or click **Pick Layout** to choose from your saved Edit Mode layouts of that input mode. The game only selects a layout in its own input mode, so the controller picker lists controller layouts and the keyboard picker keyboard layouts.
   - A blank controller Base layout leaves Edit Mode alone in controller mode.
4. **Target layout (optional)**
   - Optional alternate layout used while in combat or when you have a target, one per input mode.
   - Leave blank if you only want one layout for that input mode.
5. **UI Scale**
   - Tick **Set UI scale** and adjust the slider for a per‑profile UI scale. Unticked leaves the scale alone.
6. **Damage Meter**
   - Click the button to step through `Damage Meter: Leave alone`, `On` and `Off`.
   - On and Off apply whenever the profile is applied. In combat the change waits until combat ends.
7. **Controller support** (only shown on WoW Forever)
   - Click the button to step through `Controller support: Leave alone`, `On` and `Off`.
   - Leave alone shows both the keyboard and the controller layouts; On shows only the controller ones, Off only the keyboard ones.
   - With On or Off, AutoSetup switches the input mode at the next login/reload and reloads the UI once by itself to finish. Mid-session (e.g. right after you save the profile or switch resolutions) it shows the reload popup first.
8. **AddOns**
   - Comma/semicolon‑separated list of addons to enable/disable:
     - `WeakAuras, Details, Midnight Viewport`
     - `WeakAuras, !Details, !Midnight Viewport`
   - `Name` = enable that addon
   - `!Name` = disable that addon
   - Names can be either **folder names** or **titles** from the AddOns list; the addon resolves them internally.
   - **Addon features** (no reload needed): `Addon:feature` switches a single feature of a supported addon instead of the whole addon, e.g. `QoL:viewport` turns the Viewport of Quality of Life on and `!QoL:viewport` turns it off (`QoL=viewport` works too). It is applied live whenever the profile is evaluated. If the addon isn't loaded, the entry is skipped.
9. Click **Save / Update** to store the profile for that resolution.

Saved profiles are listed in the scrollable list at the bottom:

- **Edit**: loads the profile back into the form for changes.
- **X**: deletes the profile for that resolution.

---

### Behavior overview

- On login / `/reload` (once, not again after loading screens):
  - As soon as Edit Mode's layouts are loaded, AutoSetup detects the current resolution and applies:
    - Scale (if set)
    - Base or target layout of the current input mode (depending on combat/target state)
    - Addon set (enabling/disabling only the configured addons) and addon features
    - Damage Meter (if the profile says On or Off)

- When resolution changes (e.g. window resize, different screen), or you save a profile or delete the current resolution's:
  - AutoSetup reapplies the matching profile (if any).

- When combat/target state changes:
  - AutoSetup re‑evaluates whether to be on the **base** or **target** layout and switches only if needed. Scale, addons, features and the Damage Meter are left alone.
  - While Edit Mode is open it doesn't switch layouts; it catches up when you close Edit Mode.

- When you switch between keyboard and controller (WoW Forever):
  - AutoSetup switches to that input mode's base or target layout. Nothing else changes and no reload is needed.

If AutoSetup detects that addons need to change for a profile, or that controller support needs a reload it won't do by itself, it shows a popup with **Reload UI** and **Later** buttons so you can apply those changes when it's convenient. If more than one thing needs a reload at the same time, the popup lists each reason on its own line rather than showing them one at a time.

---

### Debugging

Use:

- `/autosetup debug`

This will:

- Print the current resolution.
- Dump the recent internal debug log (layout switches, resolution changes, etc.) to chat for troubleshooting.

---

### Notes

- AutoSetup never changes your screen resolution.
- It avoids making changes while you are in combat.
- AutoSetup itself is never disabled by its own addon set configuration, even if you accidentally list it with a `!`.
