# Doom CooldownPulse

![Doom CooldownPulse Forever icon](Media/Icon.png)

This repository keeps the editions on separate branches: [`main`](https://github.com/kaeldrin-gh/dcp_midnight/tree/main) is **Retail/Midnight**; [`forever`](https://github.com/kaeldrin-gh/dcp_midnight/tree/forever) is **WoW Forever**. Download source archives from the branch for your client. The Forever branch is maintained independently and is not intended to merge into Retail.

Flashes an ability's icon when its cooldown finishes. This edition targets **World of Warcraft: Forever 1.60.1**, interface **16001**. The port was checked against Blizzard's launch UI/API source for build **70790** (November 4, 2026).

Thanks to Discoteq for maintaining Doom CooldownPulse in the past. Kaeldrin's Midnight adaptation is the basis of this Forever edition.

## Install

1. Extract the release ZIP into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Check that the resulting path is `Doom_CooldownPulse_Forever/Doom_CooldownPulse_Forever.toc`, without an extra nested directory.
3. Enable **Doom CooldownPulse** in the AddOns menu and reload the UI.
4. Type `/dcp` and press **Test** to check the animation.

Disable other Doom CooldownPulse editions in this client: they share slash commands, frame names, and saved-variable identifiers.

## Options

Use `/dcp`, `/cooldownpulse`, or `/doomcooldownpulse` for the floating options window. **Settings → AddOns → Doom CooldownPulse** contains one large **Open /dcp options** button that closes Settings and opens that same window. All controls stay in the floating window. Customize icon size and position (**Unlock**), fade times, opacity, hold time, animation scaling, early notification, spell names, ignored spells, and the pet icon overlay. Use **Edit filters...** for drag/drop and recent flashes; **Advanced text** retains comma-separated entry. Whitelist mode shows only listed abilities. **Test** previews the animation; **Defaults** restores settings.

**Show pet cooldown pulses** is enabled by default. Uncheck it in `/dcp` to hide pet abilities for this character. The change takes effect immediately, including queued and active pet flashes; player and item flashes continue. Checking it again tracks subsequent pet casts. **Defaults** restores it to enabled.

`DCP_Saved` and `DCP_SavedPerCharacter` retain their names and structure. WoW stores them under the addon's folder name, so older settings are not automatically imported. To migrate manually, exit WoW, back up the old SavedVariables files, and copy their contents to the corresponding `Doom_CooldownPulse_Forever.lua` SavedVariables files in the Forever account and character folders. Do not edit the addon source file to transfer settings.

## Visual filters

Open `/dcp` and press **Edit filters...**, or use **`/dcp filters`** directly.

- Drag a spell from the spellbook or action bars, or an item from your bags, onto the drop area. IDs are stored automatically; entries show their icons and names.
- Use **Remove** to delete an entry. Hover a row for the spell/item tooltip. Scroll or use Previous/Next for longer lists.
- Choose **Blacklist** to hide listed abilities/items, or **Whitelist** to show only listed entries. This choice and the entries are saved per character and shared with the main options window.
- Switch to **Recent flashes** to add an icon that actually appeared, including potion effects and pet spells. Repeated flashes are deduplicated. History covers the current session's ten most recent displayed flashes and clears on `/reload`.
- **Advanced text** retains manual comma-separated names and IDs; press **Apply** or Enter to save. `spell:100` and `item:118` target a specific type. Existing names and plain numeric IDs are preserved; legacy numeric IDs continue matching either type.

Drag/drop and remove changes apply immediately, including to an already tracked or queued pulse. Duplicate entries are avoided. Pet abilities can be dragged; pet commands such as Attack and macros are not filter entries. Unsupported or protected cursor data does not change the list. The editor is created only when opened, reuses seven visible rows, and adds no external libraries or image assets.

The install ZIP now includes **`FilterEditor.lua`**, which the TOC loads after the main Lua file. Install all files from the ZIP.

## Compatibility

Forever uses modern namespaced APIs, including `C_Spell`, `C_Item`, `C_Container`, and `C_SpellBook`. This dedicated Forever package does not target Retail or Classic Era.

Readable numeric cooldowns support **Show Before Available Time**. When timing values are restricted, the addon uses the documented readable `isActive` state and pulses after the cooldown becomes inactive. Early notification is unavailable for those cooldowns. If only the global cooldown remains after an ability finishes or resets, the addon now pulses without waiting for that GCD to end; the GCD flag is sampled only during the documented cooldown update event. Restricted cast identifiers are skipped safely. The addon does not access the combat log or attempt to reveal secret values.

This build passed mocked Lua 5.1 behavior tests. It still needs validation inside the live Forever client, especially pet autocasts, combat restrictions, and individual items. See [the port notes and in-game checklist](docs/FOREVER_PORT.md).

Consumable use effects are resolved to the carried item so potions use their item icon, name, and cooldown rather than the effect spell's placeholder texture. This also prevents an extra spell-effect flash alongside the item flash. Bag and named-item use paths are supported, including the last item in a stack. In `/dcp last`, a resolved consumable is labeled as an **item ID**.

## Identifying an unexpected flash

Spells whose names begin with `[DNT]` or `(DNT)` are excluded from spell tracking. The addon does not identify internal spells by their icon or assume that every spell absent from the visible spellbook is invalid.

If an unexpected icon still flashes, type **`/dcp last`** afterward. Chat shows the ten most recent displayed cooldown icons, newest first, including their names, spell/item IDs, and how many seconds ago they appeared. Pet spell IDs and item IDs are labeled separately. Copy the unexpected entry when reporting it, or add its ID to the blacklist in `/dcp` once identified.

History clears on `/reload` or logout. `/dcp last clear` clears it manually. It records only icons actually displayed, excludes the Test preview, and does not print protected cast identifiers. No diagnostic output is printed automatically during combat.

## Development checks

Run `lua tests/test_cooldowns.lua` from the repository root with Lua 5.1, or install `lupa` and run `python tests/run.py`. Tests cover spells, items, early notification, GCD filtering, ignore/whitelists, restricted values, pets, trinket macros, shared lockouts, held cooldowns, and talent changes.

The previous Midnight edition's CurseForge page is [Doom CooldownPulse Midnight](https://www.curseforge.com/wow/addons/doom-cooldownpulse-midnight). This port has not been published there.
