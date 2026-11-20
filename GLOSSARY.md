# AutoSetup

AutoSetup applies a saved setup of the game's interface for each screen resolution, so moving between devices needs no manual changes.

## Language

**Profile**:
The saved setup for one resolution, applied whenever the game runs at that resolution.
_Avoid_: Preset, config

**Input mode**:
Whether the game's interface is set up for keyboard and mouse or for a controller (the game's controller interface). Clients without the controller interface are always in keyboard mode.
_Avoid_: Controller mode, interface style, gamepad mode

**Controller support**:
A Profile's setting for which Input mode the game starts in: Leave alone, On or Off. It sets the Input mode; it isn't the Input mode itself.
_Avoid_: Controller mode, native controller support

**Base layout**:
The Edit Mode layout a Profile uses out of combat and without a target. A Profile has one for each Input mode.
_Avoid_: Default layout, main layout

**Target layout**:
The Edit Mode layout a Profile uses in combat or while something is targeted. A Profile has one for each Input mode; without one, the Base layout stays.
_Avoid_: Combat layout

**Damage Meter**:
The game's built-in meter of combat performance. It is either on or off for the whole game, independent of any Edit Mode layout.
_Avoid_: DPS meter

**Damage Meter preview**:
The Damage Meter frame shown only while in Edit Mode so it can be placed. Turning the preview off doesn't turn the Damage Meter off.
_Avoid_: Showing or hiding the Damage Meter (in Edit Mode)

**Leave alone**:
A Profile's default for a setting: applying the Profile doesn't change that setting, so it keeps whatever value it had. It's different from a Profile that asks for on or off.
_Avoid_: Default, unset
