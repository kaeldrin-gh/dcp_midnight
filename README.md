# Doom CooldownPulse - Forever

Flashes an ability's icon when its cooldown finishes. This edition targets **World of Warcraft: Forever 1.60.1**, interface **16001**. The port was checked against Blizzard's launch UI/API source for build **70790** (November 4, 2026).

Thanks to Discoteq for maintaining Doom CooldownPulse in the past. Kaeldrin's Midnight adaptation is the basis of this Forever edition.

## Install

1. Extract the release ZIP into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Check that the resulting path is `Doom_CooldownPulse_Forever/Doom_CooldownPulse_Forever.toc`, without an extra nested directory.
3. Enable **Doom CooldownPulse - Forever** in the AddOns menu and reload the UI.
4. Type `/dcp` and press **Test** to check the animation.

Disable other Doom CooldownPulse editions in this client: they share slash commands, frame names, and saved-variable identifiers.

## Options

Open `/dcp`, `/cooldownpulse`, or `/doomcooldownpulse`. Customize icon size and position (**Unlock**), fade times, opacity, hold time, animation scaling, early notification, spell names, ignored spells, and the pet icon overlay. Ignore lists accept comma-separated names or IDs; whitelist mode shows only listed abilities. **Test** previews the animation; **Defaults** restores settings.

`DCP_Saved` and `DCP_SavedPerCharacter` retain their names and structure. WoW stores them under the addon's folder name, so older settings are not automatically imported. To migrate manually, exit WoW, back up the old SavedVariables files, and copy their contents to the corresponding `Doom_CooldownPulse_Forever.lua` SavedVariables files in the Forever account and character folders. Do not edit the addon source file to transfer settings.

## Compatibility

Forever uses modern namespaced APIs, including `C_Spell`, `C_Item`, `C_Container`, and `C_SpellBook`. This dedicated Forever package does not target Retail or Classic Era.

Readable numeric cooldowns support **Show Before Available Time**. When timing values are restricted, the addon uses the documented readable `isActive` state and pulses after the cooldown becomes inactive. Early notification is unavailable for those cooldowns. Restricted cast identifiers are skipped safely. The addon does not access the combat log or attempt to reveal secret values.

This build passed mocked Lua 5.1 behavior tests. It still needs validation inside the live Forever client, especially pet autocasts, combat restrictions, and individual items. See [the port notes and in-game checklist](docs/FOREVER_PORT.md).

## Development checks

Run `lua tests/test_cooldowns.lua` from the repository root with Lua 5.1, or install `lupa` and run `python tests/run.py`. Tests cover spells, items, early notification, GCD filtering, ignore/whitelists, restricted values, pets, trinket macros, shared lockouts, held cooldowns, and talent changes.

The previous Midnight edition's CurseForge page is [Doom CooldownPulse Midnight](https://www.curseforge.com/wow/addons/doom-cooldownpulse-midnight). This port has not been published there.
