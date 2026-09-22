## AutoSetup

AutoSetup is a World of Warcraft addon that automatically applies **per‑resolution profiles** for:

- **Edit Mode layouts** (base layout + optional combat/target layout)
- **UI scale**
- **AddOn enable/disable sets**

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
  - Store a friendly name, base layout, optional target/combat layout, scale, chat suppression, and addon set.

- **Base + target layout support**
  - `Base` layout is used out of combat / no target.
  - Optional `Target` layout is used when:
    - you are in combat, or
    - you have a target / soft enemy.

- **AddOn set management**
  - Per‑profile addon map: enable some addons, disable others.
  - Supports addon names with spaces and resolves titles (e.g. `Midnight Viewport`) to folder names.
  - Only touches the addons you list; everything else is left alone.

- **UI scale per profile**
  - Optional override for `uiScale` per resolution.

- **Chat noise control**
  - Optional flag to suppress “Edit Mode layout applied” messages in chat.

- **Native controller support per profile (WoW Forever only)**
  - Optional flag marking whether a profile expects WoW Forever's built-in native controller support to be on or off (e.g. on for a Steam Deck/couch profile, off for a mouse-and-keyboard profile).
  - This setting doesn't exist on any other flavor, so the checkbox is hidden entirely unless AutoSetup detects it's running on Forever.
  - The underlying setting is a protected CVar that Blizzard only allows addons to change during the initial evaluation right after login/reload, so switching it takes **two reloads**: the first login/reload where AutoSetup detects the mismatch applies the CVar and asks you to reload again; the second reload is where it actually takes functional effect. AutoSetup shows the same "reload required" popup used for AddOn changes at each step (with wording specific to which step you're on), and leaves Edit Mode untouched the whole time until the mode switch is fully confirmed.

- **Non‑intrusive behavior**
  - Never changes your actual resolution; it only **observes** it.
  - Skips layout and addon changes in combat to avoid taint.
  - Avoids redundant layout switches and stutter when you're already on the right layout.

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
3. **Base Edit Mode layout**
   - Either type the layout name or click **Pick Layout** to choose from existing Edit Mode layouts.
   - Leave blank if this profile has native controller support enabled: controller mode uses its own hidden default layout that doesn't appear in the layout picker, and a keyboard/mouse layout can't be applied while controller mode is active anyway. AutoSetup skips Edit Mode entirely for such profiles and lets the client manage it.
4. **Target layout (optional)**
   - Optional alternate layout used while in combat or when you have a target.
   - Leave blank if you only want one layout for this resolution, or if this profile has native controller support enabled (same reason as above).
5. **UI Scale**
   - Adjust the slider if you want a per‑profile UI scale override.
6. **Suppress chat**
   - Check to hide Edit Mode "layout applied" spam in chat when this profile is active.
7. **Enable native controller support** (only shown on WoW Forever)
   - Check this if the profile expects WoW Forever's native controller support to be on (leave unchecked for keyboard/mouse profiles).
   - Takes two reloads to fully apply: AutoSetup sets the CVar as soon as it can (on the next login/reload after a mismatch is detected) and asks you to reload once more for it to actually take effect. Blizzard also blocks addons from changing this setting live mid-session (e.g. right when you switch resolutions), so in that case AutoSetup shows the reload popup first to get that initial reload going. Edit Mode is left alone the whole time until the mode switch is fully confirmed.
8. **AddOns**
   - Comma/semicolon‑separated list of addons to enable/disable:
     - `WeakAuras, Details, Midnight Viewport`
     - `WeakAuras, !Details, !Midnight Viewport`
   - `Name` = enable that addon
   - `!Name` = disable that addon
   - Names can be either **folder names** or **titles** from the AddOns list; the addon resolves them internally.
9. Click **Save / Update** to store the profile for that resolution.

Saved profiles are listed in the scrollable list at the bottom:

- **Edit**: loads the profile back into the form for changes.
- **X**: deletes the profile for that resolution.

---

### Behavior overview

- On login / zone load:
  - After a short delay, AutoSetup detects the current resolution and applies:
    - Scale (if set)
    - Base or target layout (depending on combat/target state)
    - Addon set (enabling/disabling only the configured addons)

- When resolution changes (e.g. window resize, different screen):
  - A periodic check notices the new resolution string and reapplies the matching profile (if any).

- When combat/target state changes:
  - AutoSetup re‑evaluates whether to be on the **base** or **target** layout and switches only if needed.

If AutoSetup detects that addons or native controller support need to change for a profile, it shows a popup with **Reload UI** and **Later** buttons so you can apply those changes when it's convenient. If more than one thing needs a reload at the same time, the popup lists each reason on its own line rather than showing them one at a time.

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
