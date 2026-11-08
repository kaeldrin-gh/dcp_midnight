local passed = 0
local function reset()
    now = 100
    wipe(spells); wipe(items); wipe(slots); wipe(spellNames)
    wipe(spellWatching); wipe(spellCooldowns)
    wipe(itemWatching); wipe(itemCooldowns); wipe(animating)
    DCP_Saved, DCP_SavedPerCharacter = nil, nil
    InitializeSavedVariables()
    RefreshLocals()
    elapsed, runtimer = 0, 0
    DCPT:SetTexture(nil)
    actionType, actionID = nil, nil
    secretOperations = 0
end
local function tick(time)
    now = time
    OnUpdate(DCP, 0.06)
end
local function test(name, callback)
    reset()
    callback()
    assert(secretOperations == 0, "performed arithmetic on a secret")
    passed = passed + 1
    print("PASS " .. name)
end

test("addon loads and saved variables initialize", function()
    DCP:ADDON_LOADED("Doom_CooldownPulse_Midnight")
    assert(DCP_Saved.iconSize == 75)
    assert(SlashCmdList.DOOMCOOLDOWNPULSE)
end)

test("secret values are rejected before arithmetic", function()
    local value = Secret()
    assert(SafeNumber(value) == nil)
    local s, d, enabled, rawS, rawD, isSecret, active = NormalizeCooldown({
        startTime = value, duration = value, isEnabled = true, isActive = true,
    }, nil, nil, true)
    assert(s == nil and d == nil and enabled and isSecret and active)
    assert(rawequal(rawS, value) and rawequal(rawD, value))
end)

test("numeric cooldown pulses once", function()
    spells[101] = {startTime = 100, duration = 10, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 101)
    tick(100.6)
    assert(#animating == 0)
    spells[101] = {startTime = 0, duration = 0, isActive = false}
    tick(110)
    assert(#animating == 1 and animating[1][1] == 101)
    tick(110.1)
    assert(#animating == 1 and next(spellCooldowns) == nil)
end)

test("secret cooldown pulses on readable active-to-inactive transition", function()
    local value = Secret()
    spells[102] = {startTime = value, duration = value, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 102)
    tick(100.6); tick(105)
    assert(#animating == 0)
    spells[102].isActive = false
    tick(110)
    assert(#animating == 1 and animating[1][1] == 102)
end)

test("numeric cooldown becoming secret remains tracked", function()
    spells[103] = {startTime = 100, duration = 10, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 103)
    tick(100.6)
    spells[103] = {startTime = Secret(), duration = Secret(), isActive = true}
    tick(105)
    assert(#animating == 0 and next(spellCooldowns))
    spells[103].isActive = false
    tick(110)
    assert(#animating == 1)
end)

test("GCD-length secret cooldown does not pulse", function()
    spells[104] = {startTime = Secret(), duration = Secret(), isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 104)
    tick(100.6)
    spells[104].isActive = false
    tick(101.6)
    assert(#animating == 0 and next(spellCooldowns) == nil)
end)

test("blacklist still suppresses a pulse", function()
    DCP_SavedPerCharacter.ignoredSpells = "105"
    RefreshLocals()
    spells[105] = {startTime = Secret(), duration = Secret(), isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 105)
    tick(100.6)
    assert(next(spellWatching) == nil and next(spellCooldowns) == nil)
end)

test("pet cooldown retains the pet overlay flag", function()
    spells[106] = {startTime = 100, duration = 10, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, 106)
    tick(100.6)
    spells[106] = {startTime = 0, duration = 0, isActive = false}
    tick(110)
    assert(#animating == 1 and animating[1][2] == true)
end)

test("shared trinket lockout does not replace longer own cooldown", function()
    slots[13] = {id = 201, cooldown = {100, 20, true}}
    slots[14] = {id = 202, cooldown = {100, 20, true}}
    items[201] = {100, 40, true}
    items[202] = {100, 20, true}
    WatchItemAndSharedTrinket(201, 13)
    tick(100.6)
    slots[13].cooldown, slots[14].cooldown = {0, 0, true}, {0, 0, true}
    items[202] = {0, 0, true}
    tick(120)
    assert(#animating == 1 and animating[1][1] == 202)
    assert(itemCooldowns["item:201"])
    wipe(animating)
    items[201] = {0, 0, true}
    tick(140)
    assert(#animating == 1 and animating[1][1] == 201)
end)

test("secret event and action identifiers are skipped safely", function()
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, Secret())
    DCP:UNIT_SPELLCAST_SUCCEEDED(Secret(), nil, 101)
    actionType, actionID = "item", Secret()
    hooks.UseAction(1)
    hooks.UseAction(Secret())
    assert(next(spellWatching) == nil and next(itemWatching) == nil)
end)

test("early notification setting remains supported for readable times", function()
    DCP_Saved.remainingCooldownWhenNotified = 2
    RefreshLocals()
    spells[107] = {startTime = 100, duration = 10, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 107)
    tick(100.6); tick(108)
    assert(#animating == 1)
end)

test("player and two pet cooldowns finishing together all queue", function()
    spells[301] = {startTime = Secret(), duration = Secret(), isActive = true}
    spells[302] = {startTime = 100, duration = 10, isActive = true}
    spells[303] = {startTime = 100, duration = 10, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 301)
    DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, 302)
    DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, 303)
    tick(100.6)
    spells[301].isActive = false
    spells[302] = {startTime = 0, duration = 0, isActive = false}
    spells[303] = {startTime = 0, duration = 0, isActive = false}
    tick(110)
    local queued = {}
    for _, pulse in ipairs(animating) do queued[pulse[1]] = true end
    assert(#animating == 3 and queued[301] and queued[302] and queued[303])
end)

test("repeated pet autocasts do not prevent displaying a player pulse", function()
    spells[311] = {startTime = Secret(), duration = Secret(), isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 311)
    local pets = {
        {id = 312, nextCast = 100, duration = 4, interval = 5},
        {id = 313, nextCast = 100, duration = 6, interval = 7},
    }
    local displayed, casts = {}, 0
    for step = 0, 300 do
        local time = 100 + step * 0.1
        now = time
        for _, pet in ipairs(pets) do
            if time >= pet.nextCast then
                pet.readyAt = time + pet.duration
                pet.nextCast = time + pet.interval
                spells[pet.id] = {startTime = time, duration = pet.duration, isActive = true}
                DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, pet.id)
                casts = casts + 1
            elseif time >= pet.readyAt then
                spells[pet.id] = {startTime = 0, duration = 0, isActive = false}
            end
        end
        if time >= 110 then spells[311].isActive = false end
        tick(time)
        local texture = DCPT:GetTexture()
        if texture then displayed[texture] = true end
    end
    assert(casts >= 10, "did not exercise repeated autocasts")
    assert(displayed[311], "player pulse was starved by pet pulses")
    assert(displayed[312] and displayed[313], "pet abilities did not both pulse")
    assert(next(spellCooldowns) == nil or spellCooldowns["spell:311"] == nil)
end)

test("readable cooldown reset pulses before a remaining GCD ends", function()
    spells[401] = {startTime = 100, duration = 30, isActive = true, isOnGCD = false}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 401)
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(100.6)
    now = 110
    spells[401] = {startTime = 110, duration = 1.5, isActive = true, isOnGCD = true}
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(110.1)
    assert(#animating == 1 and animating[1][1] == 401, "waited for the GCD")
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(110.2)
    assert(#animating == 1 and next(spellCooldowns) == nil, "duplicate pulse")
end)

test("secret cooldown reset pulses while the GCD remains active", function()
    spells[402] = {startTime = Secret(), duration = Secret(), isActive = true, isOnGCD = false}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 402)
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(100.6)
    now = 110
    spells[402].isOnGCD = true
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(110.1)
    assert(#animating == 1 and animating[1][1] == 402, "waited for the GCD")
end)

test("another ability's GCD does not finish a real cooldown", function()
    spells[403] = {startTime = Secret(), duration = Secret(), isActive = true, isOnGCD = false}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 403)
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(100.6)
    now = 110
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(110.1)
    assert(#animating == 0 and spellCooldowns["spell:403"])
end)

test("GCD flags read outside the update event cannot trigger a pulse", function()
    spells[404] = {startTime = Secret(), duration = Secret(), isActive = true, isOnGCD = false}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 404)
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(100.6)
    spells[404].isOnGCD = true
    tick(110)
    assert(#animating == 0 and spellCooldowns["spell:404"])
end)

test("GCD-only casts are not enrolled as real cooldowns", function()
    spells[405] = {startTime = Secret(), duration = Secret(), isActive = true, isOnGCD = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 405)
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(100.6)
    now = 103
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(103.1)
    assert(next(spellCooldowns) == nil and #animating == 0)
end)

test("missing GCD flag retains active-to-inactive fallback", function()
    spells[406] = {startTime = Secret(), duration = Secret(), isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 406)
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(100.6)
    spells[406].isActive = false
    now = 110
    DCP:SPELL_UPDATE_COOLDOWN()
    tick(110.1)
    assert(#animating == 1)
end)

test("pet pulse preference upgrades existing settings and retains false", function()
    DCP_SavedPerCharacter.showPetCooldowns = nil
    InitializeSavedVariables()
    assert(DCP_SavedPerCharacter.showPetCooldowns == true)
    DCP_SavedPerCharacter.showPetCooldowns = false
    InitializeSavedVariables()
    RefreshLocals()
    DCP:CreateOptionsFrame()
    assert(DCP_OptionsFramePetPulsesCheckButton:GetChecked() == false)
end)

test("unchecking pet pulses clears pet work and keeps player and item pulses", function()
    spells[501] = {startTime = Secret(), duration = Secret(), isActive = true}
    spells[502] = {startTime = 100, duration = 10, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, 501)
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 502)
    tick(100.6)
    DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, 503)
    QueueAnimation(501, true, "Pet ability")
    QueueAnimation(502, false, "Player ability")
    QueueAnimation(504, true, "Second pet ability")
    QueueAnimation(201, nil, "Item ability")
    tick(100.7)
    assert(DCPT:GetTexture() == 501)
    DCP:CreateOptionsFrame()
    local checkbox = DCP_OptionsFramePetPulsesCheckButton
    checkbox:SetChecked(false)
    checkbox.scripts.OnClick(checkbox)
    assert(DCP_SavedPerCharacter.showPetCooldowns == false)
    assert(spellCooldowns["spell:501"] == nil and spellWatching["spell:503"] == nil)
    assert(spellCooldowns["spell:502"], "player cooldown was removed")
    assert(#animating == 2 and animating[1][1] == 502 and animating[2][1] == 201)
    assert(runtimer == 0 and DCPT:GetTexture() == nil)
    tick(100.8)
    assert(DCPT:GetTexture() == 502, "player pulse did not resume")
end)

test("disabled pet pulses cannot crowd out a player's completion", function()
    DCP_SavedPerCharacter.showPetCooldowns = false
    RefreshLocals()
    spells[511] = {startTime = 100, duration = 10, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 511)
    tick(100.6)
    for i = 1, 20 do
        DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, 512)
        QueueAnimation(512, true, "Pet ability")
    end
    spells[511] = {startTime = 0, duration = 0, isActive = false}
    tick(110)
    assert(#animating == 1 and animating[1][1] == 511)
    assert(next(spellWatching) == nil and next(spellCooldowns) == nil)
end)

test("checking pet pulses enables subsequent pet casts", function()
    DCP_SavedPerCharacter.showPetCooldowns = false
    RefreshLocals()
    DCP:CreateOptionsFrame()
    local checkbox = DCP_OptionsFramePetPulsesCheckButton
    checkbox:SetChecked(true)
    checkbox.scripts.OnClick(checkbox)
    spells[521] = {startTime = 100, duration = 10, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, 521)
    tick(100.6)
    spells[521] = {startTime = 0, duration = 0, isActive = false}
    tick(110)
    assert(#animating == 1 and animating[1][2] == true)
end)

test("Defaults restores both the checkbox and pet pulse behavior", function()
    DCP_SavedPerCharacter.showPetCooldowns = false
    RefreshLocals()
    DCP:CreateOptionsFrame()
    local button = DCP_OptionsFrameButton4
    button.scripts.OnClick(button)
    assert(DCP_SavedPerCharacter.showPetCooldowns == true)
    assert(DCP_OptionsFramePetPulsesCheckButton:GetChecked() == true)
    QueueAnimation(531, true, "Pet ability")
    assert(#animating == 1)
end)

test("participation checks are excluded by ID even with localized names", function()
    for _, id in ipairs({1292640, 1292641, 1292671}) do
        spellNames[id] = "Localized internal participation check"
        spells[id] = {startTime = 100, duration = 30, isActive = true}
        DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, id)
        DCP:UNIT_SPELLCAST_SUCCEEDED("pet", nil, id)
    end
    tick(100.6)
    assert(next(spellWatching) == nil and next(spellCooldowns) == nil)
    assert(#animating == 0)
end)

test("DNT spells are excluded from tracking and the animation queue", function()
    spellNames[601] = "[DNT] Is Active Participant"
    spells[601] = {startTime = 100, duration = 30, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 601)
    tick(100.6)
    assert(next(spellWatching) == nil and next(spellCooldowns) == nil)
    QueueAnimation(601, false, spellNames[601])
    assert(#animating == 0)
end)

test("late spell data cannot enroll an internal spell", function()
    spellNames[602] = false
    spells[602] = {startTime = 100, duration = 30, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 602)
    spellNames[602] = "[DNT] Internal check loaded later"
    tick(100.6)
    assert(next(spellWatching) == nil and next(spellCooldowns) == nil)
    assert(#animating == 0)
end)

test("internal exclusion cannot be overridden by a whitelist", function()
    DCP_SavedPerCharacter.ignoredSpells = "603"
    DCP_SavedPerCharacter.invertIgnored = true
    RefreshLocals()
    spellNames[603] = "[DNT] Internal check"
    spells[603] = {startTime = 100, duration = 30, isActive = true}
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 603)
    tick(100.6)
    assert(next(spellWatching) == nil and next(spellCooldowns) == nil)
    -- A regular ability containing those letters is still allowed.
    spellNames[603] = "DNT Burst"
    DCP:UNIT_SPELLCAST_SUCCEEDED("player", nil, 603)
    tick(101.2)
    spells[603] = {startTime = 0, duration = 0, isActive = false}
    tick(130)
    assert(#animating == 1 and animating[1][1] == 603)
end)

print(passed .. " compatibility checks passed (mocked Lua 5.1; in-game verification required)")
