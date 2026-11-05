# Retail compatibility candidate — 2026-11-05

Based on `kaeldrin-gh/dcp_midnight` commit `9369fa1`.
This is a test build, not a confirmed in-game fix for the user reports.

## Pet pulse toggle follow-up

Latest candidate: `2026.11.05-pet-toggle-test`. The owner has confirmed that the GCD timing fix works in-game. They also tested a Hunter with the earlier build: player abilities do pulse, but frequent pet flashes make them hard to see.

Open `/dcp` and uncheck **Show pet cooldown pulses** to hide pet ability flashes. This preference is saved per character and defaults to enabled for existing and new users. Turning it off immediately removes pending/tracked pet cooldowns and queued pet flashes, including an active pet flash, while retaining player and item pulses. Turning it back on tracks subsequent pet casts. Defaults restores pet pulses to enabled.

The new option is built on top of the GCD timing fix. Five additional mocked checks cover preference migration/persistence, immediate queue cleanup without removing player/item work, suppression during repeated pet casts, re-enabling, and the Defaults button. All 24 mocked Lua 5.1 checks pass. The checkbox layout and behavior still need an in-game check.

## GCD timing follow-up

The owner initially reported that the compatibility candidate works on a non-Hunter character, with delayed pulses when an ability's cooldown resets while another ability's global cooldown is active. They subsequently confirmed that the GCD follow-up fixes the timing in-game.

The follow-up candidate `2026.11.05-gcd-test` samples the readable `isOnGCD` flag only during `SPELL_UPDATE_COOLDOWN`, as required by Blizzard's API documentation. A tracked cooldown can now pulse when the spell transitions to having only the GCD left, even if `isActive` is still true. Known GCD-only casts are excluded from real cooldown tracking. Missing GCD flags retain the previous completion fallback. Animation queueing still applies if another icon is already playing.

Six additional mocked regressions pass: readable and secret reset timing during a GCD, preserving a still-active real cooldown, ignoring unreliable GCD flags outside events, avoiding GCD-only enrollment, and preserving the missing-flag fallback. The previous candidate fails the new reset-during-GCD regression. That revision passed 19 checks; the latest pet-toggle revision passes 24. The owner has confirmed the timing change in-game.

For a focused retest, use a tracked long cooldown, trigger its reset while another spell's GCD is running, and check whether the pulse starts before that GCD ends. Repeat without a reset as the cooldown naturally expires during other casts. Ensure ordinary GCD-only spells do not start flashing.

## Findings and changes

- The manifest listed only 12.0.1 and 12.0.5. Added 12.1.0 and 12.1.5 interface identifiers so those clients can recognize the addon without the out-of-date override.
- Cooldown normalization attempted arithmetic inside `pcall` to identify secret numbers. It also compared and used raw cooldown fields in boolean expressions before checking secrecy. Check `issecretvalue` first and keep secret times opaque.
- Retain the existing polling of `SpellCooldownInfo.isActive` for secret cooldowns. Blizzard documents `isActive` and `isEnabled` as `NeverSecret`. Numeric cooldowns retain their early notification behavior; secret cooldowns notify only after an observable active-to-inactive transition.
- Remove the hidden cooldown-frame fallback. It guessed a duration object inside `GetSpellCooldown` results, which do not contain one, and could then attempt to pass secret numbers to `SetCooldown`. No cooldown widget is needed for the existing readable-state polling path.
- Guard secret spellcast/action identifiers before comparison or conversion to tracking keys.
- Use `SetColorTexture` for the solid pet-color background in the options panel.

Secret values existed before 12.0.5. These are independently identified compatibility problems, not proof of which later patch caused the reported failure. The 12.1.5 restriction on calling cooldown setters on protected frames does not itself establish a cause here: the removed fallback created its own frames.

## Verification

The original 13 checks pass under Lua 5.1 using mocked WoW APIs: initialization, rejecting secret arithmetic, numeric and secret cooldown completion, transitioning into restricted values, suppressing GCD-length pulses, filtering, pet flags, paired trinket lockouts, guarded identifiers, early notification for readable times, simultaneous player/pet completion, and displaying a player pulse during repeated casts of two pet abilities. Together with the six GCD checks above, 19 checks pass. The original revision fails the secret-arithmetic regression under the same stubs.

The stubs cannot reproduce secret boolean behavior, forbidden aspects, taint, actual event delivery, or client loading. No retail client was available to the agent. Charged abilities and cooldown completion during a subsequent GCD need particular attention in-game. Charged-ability handling remains unchanged; GCD handling is updated as described above.

### Original BM Hunter pet-only pulse report

The reported behavior (player pulses stop as soon as a pet is summoned, while two pet abilities repeat) was not specifically addressed by the initial compatibility patch. Added two concurrent player/pet checks; both pass with the candidate's existing runtime code. That checks simulated queue behavior, not actual BM Hunter event/API behavior, and does not establish the reported bug's cause or resolution. The isolated pet test alone was insufficient evidence.

The owner's later Hunter test found that player pulses do occur, but repeated pet flashes obscure them. The new pet toggle addresses that crowding. It does not establish a separate root cause for the older report that player pulses stopped entirely. Existing code queries C_Spell.GetSpellCooldown for both player and pet casts; the mocks cannot establish whether that query correctly represents each pet ability in the client. Blizzard's live PetActionBar source still uses GetPetActionInfo and GetPetActionCooldown, contrary to an older comment in this repository claiming those APIs were removed.

Run local checks with `pip install lupa` followed by `python tests/run.py`.

## In-game check

1. Exit WoW and back up the existing addon folder. Extract the ZIP into `_retail_/Interface/AddOns/`. The folder should be `Doom_CooldownPulse_Midnight`, with its `.toc` directly inside it. Keep existing saved variables.
2. Enable only this addon initially. Run `/console scriptErrors 1`, then `/reload`. Record `/dump GetBuildInfo()` output and any first Lua error.
3. Open `/dcp`; try Test, Unlock/Lock, and the pet-color picker. Confirm the addon appears enabled without an out-of-date warning on 12.1.5.
4. Use a normal ability with a cooldown longer than two seconds. Confirm one pulse on completion outside combat, then while fighting a training dummy. Continue using GCD abilities as it finishes, and test a cooldown reset/reduction.
5. Test a charged ability, a pet ability if available, blacklisting by name/ID, and early notification. Secret cooldowns cannot use the configured early-notification offset in this implementation.
6. Use each on-use trinket, including two equipped together. The paired lockout should not trigger a premature pulse for the trinket with the longer own cooldown. Then re-enable other addons and repeat.

Report the build, class/spec, exact spell/item, combat context, and first full Lua error if anything fails.

## API references

- Blizzard spell structures: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua
- Blizzard cooldown widget API: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua
- Blizzard secret-value predicates: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua
- Blizzard 12.1.5 update notes: https://worldofwarcraft.blizzard.com/en-us/news/24304162/12-1-5-content-update-notes
