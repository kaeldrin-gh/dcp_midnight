# Doom CooldownPulse - Forever

![Doom CooldownPulse Forever icon](Media/Icon.png)

This repository keeps the editions on separate branches: [`main`](https://github.com/kaeldrin-gh/dcp_midnight/tree/main) is **Retail/Midnight**; [`forever`](https://github.com/kaeldrin-gh/dcp_midnight/tree/forever) is **WoW Forever**. Download source archives from the branch for your client. The Forever branch is maintained independently and is not intended to merge into Retail.

Flashes an ability's icon when its cooldown finishes. This edition targets **World of Warcraft: Forever 1.60.1**, interface **16001**. The port was checked against Blizzard's launch UI/API source for build **70790** (November 4, 2026).

Thanks to Discoteq for maintaining Doom CooldownPulse in the past. Kaeldrin's Midnight adaptation is the basis of this Forever edition.

## Install

1. Extract the release ZIP into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Check that the resulting path is `Doom_CooldownPulse_Forever/Doom_CooldownPulse_Forever.toc`, without an extra nested directory.
3. Enable **Doom CooldownPulse - Forever** in the AddOns menu and reload the UI.
4. Type `/dcp` and press **Test** to check the animation.

Disable other Doom CooldownPulse editions in this client: they share slash commands, frame names, and saved-variable identifiers.

## Options

Use `/dcp`, `/cooldownpulse`, or `/doomcooldownpulse` for the original floating options window. **Settings → AddOns → Doom CooldownPulse - Forever** has a separate flat, two-column page with grouped appearance/timing controls, pet options, a color picker, spell filters, and Test/Move/Defaults buttons. Both views share the same saved settings. The Settings page scrolls and fits narrower panels; it never embeds or reparents the floating window. Customize icon size and position (**Unlock**), fade times, opacity, hold time, animation scaling, early notification, spell names, ignored spells, and the pet icon overlay. Ignore lists accept comma-separated names or IDs; whitelist mode shows only listed abilities. **Test** previews the animation; **Defaults** restores settings.

**Show pet cooldown pulses** is enabled by default. Uncheck it in `/dcp` to hide pet abilities for this character. The change takes effect immediately, including queued and active pet flashes; player and item flashes continue. Checking it again tracks subsequent pet casts. **Defaults** restores it to enabled.

`DCP_Saved` and `DCP_SavedPerCharacter` retain their names and structure. WoW stores them under the addon's folder name, so older settings are not automatically imported. To migrate manually, exit WoW, back up the old SavedVariables files, and copy their contents to the corresponding `Doom_CooldownPulse_Forever.lua` SavedVariables files in the Forever account and character folders. Do not edit the addon source file to transfer settings.

## Compatibility

Forever uses modern namespaced APIs, including `C_Spell`, `C_Item`, `C_Container`, and `C_SpellBook`. This dedicated Forever package does not target Retail or Classic Era.

Readable numeric cooldowns support **Show Before Available Time**. When timing values are restricted, the addon uses the documented readable `isActive` state and pulses after the cooldown becomes inactive. Early notification is unavailable for those cooldowns. If only the global cooldown remains after an ability finishes or resets, the addon now pulses without waiting for that GCD to end; the GCD flag is sampled only during the documented cooldown update event. Restricted cast identifiers are skipped safely. The addon does not access the combat log or attempt to reveal secret values.

This build passed mocked Lua 5.1 behavior tests. It still needs validation inside the live Forever client, especially pet autocasts, combat restrictions, and individual items. See [the port notes and in-game checklist](docs/FOREVER_PORT.md).

## Identifying an unexpected flash

Spells whose names begin with `[DNT]` or `(DNT)` are excluded from spell tracking. The addon does not identify internal spells by their icon or assume that every spell absent from the visible spellbook is invalid.

If an unexpected icon still flashes, type **`/dcp last`** afterward. Chat shows the ten most recent displayed cooldown icons, newest first, including their names, spell/item IDs, and how many seconds ago they appeared. Pet spell IDs and item IDs are labeled separately. Copy the unexpected entry when reporting it, or add its ID to the blacklist in `/dcp` once identified.

History clears on `/reload` or logout. `/dcp last clear` clears it manually. It records only icons actually displayed, excludes the Test preview, and does not print protected cast identifiers. No diagnostic output is printed automatically during combat.

## Development checks

Run `lua tests/test_cooldowns.lua` from the repository root with Lua 5.1, or install `lupa` and run `python tests/run.py`. Tests cover spells, items, early notification, GCD filtering, ignore/whitelists, restricted values, pets, trinket macros, shared lockouts, held cooldowns, and talent changes.

The previous Midnight edition's CurseForge page is [Doom CooldownPulse Midnight](https://www.curseforge.com/wow/addons/doom-cooldownpulse-midnight). This port has not been published there.
