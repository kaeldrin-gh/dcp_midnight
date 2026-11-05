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
