# Forever port notes

Checked November 5, 2026. Target: **1.60.1 / interface 16001**. The launch UI-source snapshot is **70790**, commit [`eac30af`](https://github.com/Gethe/wow-ui-source/commit/eac30af597e5aaa43a60f6675ef5fdcea100375f), dated November 4. This is a static source audit; the addon has not been tested inside the game.

## API findings

- [Blizzard's Forever recap](https://news.blizzard.com/en-gb/article/24304071/world-of-warcraft-forever-found-photos-panel-recap) confirms the November 4 launch.
- [API exported from Forever build 70170](https://github.com/Atraeau/WoW-Addons/blob/main/docs/api/README.md) records interface **16001**. [Client inspection notes updated November 3](https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md) independently record live build 70755, interface 16001, and the `_forever_` folder. No local Forever install was queried.
- [Blizzard's launch CooldownViewer TOC](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_CooldownViewer/Blizzard_CooldownViewer.toc) allows both `standard` and `camelot`. Forever retains modern APIs; the lower interface number does not mean the Classic Era API. A plain TOC suffices for this dedicated package.
- [Spell API](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua) marks timing data as potentially secret. [Spell structures](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua) mark `isActive` and `isEnabled` as `NeverSecret`. The port checks secrecy before numeric operations, respects held cooldowns, and uses state transitions when timestamps cannot be read. The old hidden cooldown-frame fallback was removed.
- [FrameScript API](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua) documents `issecretvalue`. A `pcall` around arithmetic is not a substitute for checking secrecy first.
- [SpellBook API](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua) and [spell banks](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookConstantsDocumentation.lua) provide the modern Pet bank. The port resolves pet casts to pet spellbook slots and queries their cooldowns there.
- [Unit event documentation](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) includes `UNIT_SPELLCAST_SUCCEEDED` and potentially secret cast payloads. The port keeps `RegisterUnitEvent` for player/pet and skips restricted identifiers before comparison or conversion. It has no combat-log dependency.
- [Item API](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua) returns numeric item cooldowns plus an enabled boolean; `GetItemSpell` returns a spell ID. The port preserves shared-trinket tracking, respects enabled flags, and uses exact item spell IDs to route trinket casts, including `/use` macros. It no longer filters unrelated abilities because their icons match.

Other fixes: initialize only on this addon's own `ADDON_LOADED`, and expire short cooldown watch entries after three seconds so they cannot poll forever. Existing saved-variable identifiers and customization controls remain.

## Version 1.0.6: Settings launcher

Replace the duplicate Settings form with one large **Open /dcp options** button. It closes Settings and opens the existing floating window. `/dcp` and its aliases remain standalone; all sliders, filters, pet controls, and the Unlock/Lock toggle live in that window. No embedded frame, duplicate move button, or duplicate settings state remains. The floating Unlock button shows/unlocks the icon on the first click and hides/locks it on the second. All 51 mocked Lua 5.1 checks pass, including repeated toggling and the launcher path.

## Version 1.0.5: Separate floating and Settings layouts

Restore `/dcp` and both aliases to the independent floating window. Replace the embedded dialog in Settings → AddOns with a flat, two-column page: Appearance and Timing groups, pet visibility and color, blacklist/whitelist input, and a spaced action row. The native page has no dialog border or draggable header, scrolls vertically, and scales to fit narrower canvas widths. Both layouts use one shared slider definition list and the same saved variables. Opening either layout never reparents the other.

Native changes apply immediately. Reopening the floating window refreshes its slider positions and value labels, checkboxes, filter, and pet color. Native Test/Move actions open the floating window and close Settings; native Defaults uses the same reset handler without opening a floating dialog. Preserve unfinished filter typing while other native controls refresh.

All **57 mocked Lua 5.1 checks** pass, covering both entry points, independent frames, shared values in both directions, color apply/cancel, filtering, defaults, preview/move actions, and reopening value labels. Final typography, spacing, scrolling and scaling still need an in-game visual check.

## Version 1.0.4: Internal casts, pulse identification, and Settings

The owner reported a sporadic insignia-like flash whose name/ID is still unknown. The existing cast handler can enroll engine-generated player casts; this establishes a possible cause, not the identity of that particular flash. There is no automatic developer-test animation in the addon; its Test preview is triggered only by the options button.

- Exclude explicit `[DNT]` / `(DNT)` name prefixes from spell tracking, checking again when enrolling a watch. Match prefixes only, case-insensitively. Preserve normal spells, including ones absent from a visible spellbook, and preserve independent item-use tracking.
- Add `/dcp last` for a bounded, session-only history of the ten most recently displayed cooldown pulses, with name, spell/item ID, type, and elapsed seconds. Log at display time, not queue time; skip the options Test preview. `/dcp last clear` clears history without changing watched cooldowns or preferences. No protected value is converted to diagnostic text.
- Register the complete options frame under **Settings → AddOns → Doom CooldownPulse - Forever** using Forever's [documented canvas registration](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua). A scroll frame accommodates the full 660-unit controls. `/dcp` and its aliases open this category. Test/Unlock detach the panel into the floating form and close Settings, so the preview can be seen and moved. Reopening Settings reuses the same controls. If the Settings API is unavailable at addon load, retry at login and retain the floating fallback.

All **51 mocked Lua 5.1 checks** pass. In game, verify the native Settings page, scrolling, Escape/Close, Test/Unlock, reopening Settings, and unchanged preferences. If the unknown flash remains, capture its `/dcp last` entry before `/reload`; the exact Forever spell has not yet been identified and there is no claim that DNT-prefix filtering alone resolves it.

## Version 1.0.3: Options footer spacing

The owner's in-game screenshot showed the filter edit box overlapping the upper button row after the pet checkbox was added. Increase the options panel height from 610 to 660 UI units, keeping the button rows anchored to the bottom, and give the edit box an eight-unit gap below the filter radio controls. This reserves space between the filter field and the Defaults/Unlock buttons. Cooldown behavior and saved settings are unchanged. The existing options-creation and behavior checks pass; final appearance needs checking in the client.

## Version 1.0.2: Retail improvements carried to Forever

- Added the per-character **Show pet cooldown pulses** checkbox from the Retail update. Defaults to enabled, preserves an existing saved `false`, removes pending/tracked pet cooldowns and queued/active pet animations immediately when disabled, and retains player/item work. Re-enabling tracks subsequent casts; Defaults restores enabled.
- Carried over the GCD timing fix: sample the documented `NeverSecret` `isOnGCD` flag only inside `SPELL_UPDATE_COOLDOWN`, retain that event-sampled state on each watch, exclude known GCD-only casts from real cooldown tracking, and pulse a previously tracked real cooldown as soon as only the GCD remains. Missing flags retain the existing completion fallback. Held cooldowns remain guarded by `isEnabled`.
- Adapted event queries to Forever's `GetWatchedSpellCooldown` helper so pet watches still use the **Pet spellbook bank**. The Retail file was used as a reference, not substituted for the Forever implementation. Interface 16001 and the Forever icon are retained.
- Updated the pet color swatch background to `SetColorTexture`, matching the Retail options fix.

All **31 mocked Lua 5.1 behavior checks** pass, including the original 15 checks and 16 GCD/pet-toggle regressions. These new features still need an in-game Forever check: finish or reset a long cooldown during another spell's GCD, confirm no GCD-only flashes, and toggle pet pulses during queued/active animations. Also verify the checkbox layout, `/reload` persistence, re-enabling, and Defaults. The owner previously reported that the original Forever port worked in game; that report does not validate this new version.

## Restrictions and validation

The state-transition fallback cannot honor an early-notification offset or precisely measure a restricted cooldown's original duration. It suppresses completions observed within two seconds of the cast to avoid ordinary GCD pulses. A cast whose identifier is restricted is not added to the watch list. These limits need checking against the live client's restrictions and actual abilities.

The Lua 5.1 suite exercises the actual addon file and its event/update handlers against mocked APIs. It cannot reproduce WoW's taint engine, secret scalar types, protected execution, rendering, or server timing. Secret test sentinels reject arithmetic/conversion, and a mock `issecretvalue` identifies them.

Before releasing as game-tested:

- Enable only this edition, turn on Lua errors (`/console scriptErrors 1`), and `/reload`. Open `/dcp`, press Test, move the icon with Unlock, and try Defaults.
- Use a player ability with a cooldown longer than two seconds outside combat and in combat. Confirm one pulse; repeat with early notification enabled.
- Cast GCD-only abilities and confirm no pulses. Check an ability whose cooldown starts after a buff ends or a channel completes.
- Use pet abilities manually and with autocast. Confirm the correct icon and overlay. Dismiss or replace the pet before completion and check for stale pulses.
- Use trinkets from action bars and `/use 13` or `/use 14` macros. Verify the used trinket and its partner pulse only when their own/shared cooldowns allow it. Check a long cooldown overlapping a shorter shared lockout.
- Use a consumable from a bag and an action bar. Check blacklist and whitelist entries by name and ID.
- Change talents, enter and leave instances, then `/reload` and fully restart. Confirm settings persist.
- If an error occurs, capture the full error text and `/dump GetBuildInfo()` output.
