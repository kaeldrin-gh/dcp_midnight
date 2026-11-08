local addonName = ...
local fadeInTime, fadeOutTime, maxAlpha, animScale, iconSize, holdTime, showSpellName, ignoredSpells, invertIgnored, remainingCooldownWhenNotified
local spellCooldowns, itemCooldowns, animating, spellWatching, itemWatching = { }, { }, { }, { }, { }
local GetTime = GetTime
local unpack = unpack or table.unpack
local OnUpdate
local MINIMUM_FLASH_COOLDOWN = 2.0
local IsEquippedTrinketReady
local showPetCooldowns
local runtimer = 0
local recentPulses = {}
local MAX_RECENT_PULSES = 10
local settingsCategory

local optionSliders = {
        { text = "Icon Size", value = "iconSize", min = 30, max = 125, step = 5 },
        { text = "Fade In Time", value = "fadeInTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Fade Out Time", value = "fadeOutTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Max Opacity", value = "maxAlpha", min = 0, max = 1, step = 0.1 },
        { text = "Max Opacity Hold Time", value = "holdTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Animation Scaling", value = "animScale", min = 0, max = 2, step = 0.1 },
        { text = "Show Before Available Time", value = "remainingCooldownWhenNotified", min = 0, max = 3, step = 0.1 },
    }

local defaultSettings = {
    fadeInTime = 0.3,
    fadeOutTime = 0.7,
    maxAlpha = 0.7,
    animScale = 1.5,
    iconSize = 75,
    holdTime = 0,
    petOverlay = {1,1,1},
    showSpellName = nil,
    x = UIParent:GetWidth()*UIParent:GetEffectiveScale()/2,
    y = UIParent:GetHeight()*UIParent:GetEffectiveScale()/2,
    remainingCooldownWhenNotified = 0
}

local defaultSettingsPerCharacter = {
    ignoredSpells = "",
    invertIgnored = false,
    showPetCooldowns = true
}

local DCP = CreateFrame("frame")
DCP:SetScript("OnEvent", function(self, event, ...)
    local handler = self[event]
    if handler then
        handler(self, ...)
    end
end)
DCP:SetMovable(true)
DCP:RegisterForDrag("LeftButton")
DCP:SetScript("OnDragStart", function(self) self:StartMoving() end)
DCP:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    DCP_Saved.x = self:GetLeft()+self:GetWidth()/2
    DCP_Saved.y = self:GetBottom()+self:GetHeight()/2
    self:ClearAllPoints()
    self:SetPoint("CENTER",UIParent,"BOTTOMLEFT",DCP_Saved.x,DCP_Saved.y)
end)
DCP.TextFrame = DCP:CreateFontString(nil, "ARTWORK")
DCP.TextFrame:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
DCP.TextFrame:SetShadowOffset(2,-2)
DCP.TextFrame:SetPoint("CENTER",DCP,"CENTER")
DCP.TextFrame:SetWidth(185)
DCP.TextFrame:SetJustifyH("CENTER")
DCP.TextFrame:SetTextColor(1,1,1)

local DCPT = DCP:CreateTexture(nil,"BACKGROUND")
DCPT:SetAllPoints(DCP)

-----------------------
-- Utility Functions --
-----------------------
local function tcount(tab)
    local n = 0
    for _ in pairs(tab) do
        n = n + 1
    end
    return n
end

local function memoize(f)
    local cache = nil

    local memoized = {}

    local function get()
        if (cache == nil) then
            cache = f()
        end

        return cache
    end

    memoized.resetCache = function()
        cache = nil
    end

    setmetatable(memoized, {__call = get})

    return memoized
end

local function RefreshLocals()
    fadeInTime = DCP_Saved.fadeInTime
    fadeOutTime = DCP_Saved.fadeOutTime
    maxAlpha = DCP_Saved.maxAlpha
    animScale = DCP_Saved.animScale
    iconSize = DCP_Saved.iconSize
    holdTime = DCP_Saved.holdTime
    showSpellName = DCP_Saved.showSpellName
    invertIgnored = DCP_SavedPerCharacter.invertIgnored
    remainingCooldownWhenNotified = DCP_Saved.remainingCooldownWhenNotified
    showPetCooldowns = DCP_SavedPerCharacter.showPetCooldowns

    if not showPetCooldowns then
        -- Apply immediately, including casts already tracked and pulses queued
        -- before the checkbox was changed. Keep player/item work in place.
        for id, watch in pairs(spellWatching) do
            if watch[4] then spellWatching[id] = nil end
        end
        for id, entry in pairs(spellCooldowns) do
            if entry.watch and entry.watch[4] then spellCooldowns[id] = nil end
        end
        local removedCurrent = animating[1] and animating[1][2]
        for i = #animating, 1, -1 do
            if animating[i][2] then tremove(animating, i) end
        end
        if removedCurrent then
            runtimer = 0
            if not DCP:IsMouseEnabled() then
                DCP.TextFrame:SetText(nil)
                DCPT:SetTexture(nil)
                DCPT:SetVertexColor(1,1,1)
                DCP:SetAlpha(0)
            end
        end
    end


    ignoredSpells = { }
    for _,v in ipairs({strsplit(",",DCP_SavedPerCharacter.ignoredSpells)}) do
        ignoredSpells[strtrim(v)] = true
    end
end

local function MergeTable(destination, source)
    for i, v in pairs(source) do
        if (destination[i] == nil) then
            destination[i] = v
        end
    end
end

local function InitializeSavedVariables()
    if (DCP_Saved == nil) then
        DCP_Saved = {}
    end

    if (DCP_SavedPerCharacter == nil) then
        DCP_SavedPerCharacter = {}
    end

    MergeTable(DCP_Saved, defaultSettings)
    MergeTable(DCP_SavedPerCharacter, defaultSettingsPerCharacter)

    if type(DCP_Saved.petOverlay) ~= "table" then
        DCP_Saved.petOverlay = {1,1,1}
    else
        local r = tonumber(DCP_Saved.petOverlay[1]) or 1
        local g = tonumber(DCP_Saved.petOverlay[2]) or 1
        local b = tonumber(DCP_Saved.petOverlay[3]) or 1
        DCP_Saved.petOverlay = {r, g, b}
    end
end

-- Forever uses the modern API even though its interface number is 16001.
-- Never do arithmetic, comparisons, or table-key conversions on secret values.
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

-- Explicit developer markers are not player-facing abilities. Do not guess
-- from an icon or reject all spells missing from the visible spellbook.
local function IsInternalSpell(info)
    if IsSecret(info) or type(info) ~= "table" then return false end
    local name = info.name
    if IsSecret(name) or type(name) ~= "string" then return false end
    name = strtrim(name):upper()
    return name:match("^%[DNT%]") ~= nil or name:match("^%(DNT%)") ~= nil
end

-- Record only actual displayed pulses, rather than casts or queued animations.
-- Session-only, bounded history; protected values are never converted to text.
local function RecordPulse(details)
    local spellID, itemID = details[4], details[5]
    if IsSecret(spellID) or type(spellID) ~= "number" then spellID = nil end
    if IsSecret(itemID) or type(itemID) ~= "number" then itemID = nil end
    if not spellID and not itemID then return end -- Skip the options Test preview.
    local name = details[3]
    if IsSecret(name) or type(name) ~= "string" then name = "Unknown" end
    tinsert(recentPulses, {
        name = name,
        id = itemID or spellID,
        kind = itemID and "item" or (details[2] and "pet spell" or "spell"),
        shownAt = GetTime()
    })
    if #recentPulses > MAX_RECENT_PULSES then tremove(recentPulses, 1) end
end

local function ShowRecentPulses()
    if #recentPulses == 0 then
        print("DCP: No cooldown pulses recorded this session.")
        return
    end
    print("DCP: Recent flashes, newest first (history clears on /reload):")
    for i = #recentPulses, 1, -1 do
        local entry = recentPulses[i]
        print(format("DCP: %s | %s ID %d | %.0fs ago", entry.name, entry.kind, entry.id, GetTime() - entry.shownAt))
    end
end

local function IsAnimatingCooldownByName(name)
    for i, details in pairs(animating) do
        if details[3] == name then
            return true
        end
    end

    return false
end

local function QueueAnimation(texture, isPet, name, spellID, itemID)
    if isPet and not showPetCooldowns then return end
    if texture and not IsAnimatingCooldownByName(name) then
        tinsert(animating, {texture, isPet, name, spellID, itemID})
    end

    if (not DCP:IsMouseEnabled()) then
        DCP:SetScript("OnUpdate", OnUpdate)
    end
end

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

local function SafeBoolean(value, fallback)
    if IsSecret(value) then
        return fallback
    end
    if type(value) == "boolean" then
        return value
    elseif value == 0 then
        return false
    elseif value == 1 then
        return true
    end
    return fallback
end

local function NormalizeCooldown(rawStartOrTable, rawDuration, rawEnabled, defaultEnabled)
    if IsSecret(rawStartOrTable) then
        return nil, nil, defaultEnabled, nil, nil, true, nil
    end

    local rawStart, durationValue, active
    if type(rawStartOrTable) == "table" then
        rawStart = rawStartOrTable.startTime
        durationValue = rawStartOrTable.duration
        rawEnabled = rawStartOrTable.isEnabled
        -- These flags are NeverSecret in Forever's SpellCooldownInfo.
        active = SafeBoolean(rawStartOrTable.isActive, nil)
    else
        rawStart = rawStartOrTable
        durationValue = rawDuration
    end

    local start = SafeNumber(rawStart)
    local duration = SafeNumber(durationValue)
    local enabled = SafeBoolean(rawEnabled, defaultEnabled)
    if active == nil and start and duration then
        active = enabled and start > 0 and duration > 0
    end
    local secret = IsSecret(rawStart) or IsSecret(durationValue) or false
    return start, duration, enabled, rawStart, durationValue, secret, active
end

-- Pet spells must be queried in the Pet spell bank, rather than as player spells.
local function GetWatchedSpellCooldown(spellID, isPet)
    if isPet then
        local bank = Enum.SpellBookSpellBank.Pet
        for slot = 1, C_SpellBook.HasPetSpells() or 0 do
            local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
            if info and info.spellID == spellID then
                return C_SpellBook.GetSpellBookItemCooldown(slot, bank)
            end
        end
        return nil
    end
    return C_Spell.GetSpellCooldown(spellID)
end

local function GetCooldownRemaining(start, duration)
    local s = SafeNumber(start)
    local d = SafeNumber(duration)
    if not s or not d then
        return nil
    end

    return d - (GetTime() - s)
end

local function GetCooldownReadyAt(start, duration)
    local s = SafeNumber(start)
    local d = SafeNumber(duration)
    if not s or not d then
        return nil
    end

    return s + d
end

local function BuildCooldownData(rawStartOrTable, rawDuration, rawEnabled)
    local start, duration, enabled, normalizedRawStart, normalizedRawDuration, isSecret, isActive = NormalizeCooldown(rawStartOrTable, rawDuration, rawEnabled, true)
    return {
        start = start,
        duration = duration,
        enabled = enabled,
        rawStart = normalizedRawStart,
        rawDuration = normalizedRawDuration,
        isSecret = isSecret,
        isActive = isActive,
        remaining = GetCooldownRemaining(start, duration),
        readyAt = GetCooldownReadyAt(start, duration)
    }
end

local function SelectBestCooldownData(primary, secondary)
    if not primary then
        return secondary
    end
    if not secondary then
        return primary
    end

    -- If either cooldown is active but has non-numeric duration, prefer active one.
    if (primary.isActive and primary.remaining == nil) and not (secondary.isActive and secondary.remaining == nil) then
        return primary
    end
    if (secondary.isActive and secondary.remaining == nil) and not (primary.isActive and primary.remaining == nil) then
        return secondary
    end

    -- Prefer the cooldown with the longer remaining time. This handles trinkets
    -- where slot cooldown shows shared lockout (20s) while item cooldown holds
    -- the real trinket-specific cooldown.
    local primaryRemaining = primary.remaining or -math.huge
    local secondaryRemaining = secondary.remaining or -math.huge
    if secondaryRemaining > primaryRemaining then
        return secondary
    end

    return primary
end

IsEquippedTrinketReady = function(itemID, trinketSlot)
    if not itemID or (trinketSlot ~= 13 and trinketSlot ~= 14) then
        return true
    end

    local slotCooldownData
    if GetInventoryItemCooldown then
        local slotRawStartOrTable, slotRawDuration, slotEnabled = GetInventoryItemCooldown("player", trinketSlot)
        slotCooldownData = BuildCooldownData(slotRawStartOrTable, slotRawDuration, slotEnabled)
    end

    local itemCooldownData
    if C_Item and C_Item.GetItemCooldown then
        local itemRawStartOrTable, itemRawDuration, itemEnabled = C_Item.GetItemCooldown(itemID)
        itemCooldownData = BuildCooldownData(itemRawStartOrTable, itemRawDuration, itemEnabled)
    end

    local function stillCoolingDown(data)
        if not data then
            return false
        end

        if data.remaining and data.remaining > remainingCooldownWhenNotified then
            return true
        end

        -- Secret-safe: unknown numeric duration but still active means not ready.
        if data.isActive and data.remaining == nil then
            return true
        end

        return false
    end

    -- Conservative trinket-only rule: if either source still shows cooldown,
    -- do NOT flash yet.
    if stillCoolingDown(slotCooldownData) or stillCoolingDown(itemCooldownData) then
        return false
    end

    return true
end

local function FindEquippedTrinketSlotByItemID(itemID)
    if not itemID then
        return nil
    end

    if (GetInventoryItemID("player", 13) == itemID) then
        return 13
    end
    if (GetInventoryItemID("player", 14) == itemID) then
        return 14
    end

    return nil
end

local function GetItemTrackingKey(itemID)
    return "item:" .. tostring(itemID)
end

local function GetSpellTrackingKey(spellID)
    return "spell:" .. tostring(spellID)
end

local function GetItemNameByID(itemID)
    if not itemID then
        return nil
    end

    if C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if name then
            return name
        end
    end

    if C_Item and C_Item.GetItemInfo then
        local info = C_Item.GetItemInfo(itemID)
        if type(info) == "table" then
            return info.name or info.itemName
        end
        return info
    end

    return nil
end

local function QueueWatchedItem(itemID, inventorySlot, forceRefresh)
    if not itemID then
        return
    end

    local itemKey = GetItemTrackingKey(itemID)
    
    -- PRESERVATION FIX: Remember the existing ready time if we are forcing a refresh
    local existingReadyAt = nil
    if itemCooldowns[itemKey] then
        existingReadyAt = itemCooldowns[itemKey].readyAt
    elseif itemWatching[itemKey] then
        existingReadyAt = itemWatching[itemKey][6]
    end

    -- Do not override an already tracked cooldown unless explicitly requested.
    if (not forceRefresh) and (itemWatching[itemKey] ~= nil or itemCooldowns[itemKey] ~= nil) then
        return
    end

    local texture = nil
    if inventorySlot and GetInventoryItemTexture then
        texture = GetInventoryItemTexture("player", inventorySlot)
    end
    if not texture and C_Item and C_Item.GetItemIconByID then
        texture = C_Item.GetItemIconByID(itemID)
    end

    -- Pass the preserved existingReadyAt to prevent downgrading a 40s CD to a 20s shared CD
    itemWatching[itemKey] = {GetTime(), "item", texture, inventorySlot, itemID, existingReadyAt}
end

local function WatchItemAndSharedTrinket(itemID, knownSlot)
    local slot = knownSlot or FindEquippedTrinketSlotByItemID(itemID)

    -- The directly used item should always refresh its own watch snapshot.
    QueueWatchedItem(itemID, slot, true)

    -- Trinkets can share a lockout; also watch the other trinket
    -- so that, when the shared lockout ends, we pulse the correct icon.
    if (slot == 13 or slot == 14) then
        local otherSlot = (slot == 13) and 14 or 13
        local otherItemID = GetInventoryItemID("player", otherSlot)
        if otherItemID and otherItemID ~= itemID then
            -- For the paired trinket, preserve existing long-cooldown tracking.
            QueueWatchedItem(otherItemID, otherSlot, false)
        end
    end

    if (not DCP:IsMouseEnabled()) then
        DCP:SetScript("OnUpdate", OnUpdate)
    end
end

--------------------------
-- Cooldown / Animation --
--------------------------
local elapsed = 0
OnUpdate = function(_,update)
    elapsed = elapsed + update
    if (elapsed > 0.05) then
        for id, v in pairs(spellWatching) do
            if (GetTime() >= v[1] + 0.5) then
                local watchedID = id
                local watchedEntry = v
                local getCooldownDetails = function()
                    if not (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellCooldown) then
                        return {}
                    end
                    if not watchedEntry[3] then
                        return {}
                    end
                    local info = C_Spell.GetSpellInfo(watchedEntry[3])
                    local cooldown = GetWatchedSpellCooldown(watchedEntry[3], watchedEntry[4])
                    local start, duration, enabled, rawStart, rawDuration, isSecret, isActive = NormalizeCooldown(cooldown, nil, nil, true)
                    return {
                        name = info and info.name,
                        texture = info and info.iconID,
                        start = start,
                        duration = duration,
                        enabled = enabled,
                        rawStart = rawStart,
                        rawDuration = rawDuration,
                        isSecret = isSecret,
                        isActive = isActive,
                        -- Sampled only during SPELL_UPDATE_COOLDOWN.
                        isOnGCD = watchedEntry.isOnGCD,
                        isInternal = IsInternalSpell(info),
                        spellID = watchedEntry[3],
                        isPet = watchedEntry[4]
                    }
                end

                local cooldown = getCooldownDetails()
                local ignoredByName = (ignoredSpells[cooldown.name] ~= nil)
                local ignoredByTrackingID = (ignoredSpells[tostring(watchedID)] ~= nil)
                local ignoredBySpellID = (cooldown.spellID ~= nil and ignoredSpells[tostring(cooldown.spellID)] ~= nil)
                if (cooldown.isInternal or ((ignoredByName or ignoredByTrackingID or ignoredBySpellID) ~= invertIgnored)) then
                    spellWatching[watchedID] = nil
                else
                    local duration = SafeNumber(cooldown.duration)
                    local hasLongNumericCooldown = (duration and duration > MINIMUM_FLASH_COOLDOWN)
                    local hasUnknownDurationActiveCooldown = (cooldown.isActive and duration == nil)

                    if (cooldown.isOnGCD ~= true and cooldown.texture and (hasLongNumericCooldown or hasUnknownDurationActiveCooldown)) then
                        spellCooldowns[watchedID] = {
                            getCooldownDetails = getCooldownDetails,
                            wasActive = (cooldown.isActive == true),
                            startedAt = watchedEntry[1],
                            restrictedTiming = (duration == nil),
                            watch = watchedEntry,
                            hasLongNumericCooldown = hasLongNumericCooldown
                        }
                        spellWatching[watchedID] = nil
                    end

                    -- Keep watching short spell cooldowns (likely GCD/start recovery)
                    local isShortSpellCooldown = (duration and duration > 0 and duration <= 2.0)
                    if (not isShortSpellCooldown or GetTime() - watchedEntry[1] > 3) then
                        spellWatching[watchedID] = nil
                    end
                end
            end
        end

        for id, v in pairs(itemWatching) do
            if (GetTime() >= v[1] + 0.5) then
                local watchedID = id
                local watchedEntry = v
                local getCooldownDetails = function()
                    local itemID = watchedEntry[5] or watchedID
                    if not itemID then
                        return {}
                    end
                    local equippedTrinketSlot = watchedEntry[4] or FindEquippedTrinketSlotByItemID(itemID)

                    local slotCooldownData
                    if equippedTrinketSlot and GetInventoryItemCooldown then
                        local slotRawStartOrTable, slotRawDuration, slotEnabled = GetInventoryItemCooldown("player", equippedTrinketSlot)
                        slotCooldownData = BuildCooldownData(slotRawStartOrTable, slotRawDuration, slotEnabled)
                    end

                    local itemCooldownData
                    if C_Item and C_Item.GetItemCooldown then
                        local itemRawStartOrTable, itemRawDuration, itemEnabled = C_Item.GetItemCooldown(itemID)
                        itemCooldownData = BuildCooldownData(itemRawStartOrTable, itemRawDuration, itemEnabled)
                    end

                    local cooldownData = SelectBestCooldownData(slotCooldownData, itemCooldownData)
                    if not cooldownData then
                        cooldownData = BuildCooldownData(nil, nil)
                    end

                    local texture = watchedEntry[3]
                    if equippedTrinketSlot and GetInventoryItemTexture then
                        texture = GetInventoryItemTexture("player", equippedTrinketSlot) or texture
                    end
                    if not texture and C_Item and C_Item.GetItemIconByID then
                        texture = C_Item.GetItemIconByID(itemID)
                    end

                    return {
                        name = GetItemNameByID(itemID),
                        texture = texture,
                        start = cooldownData.start,
                        duration = cooldownData.duration,
                        enabled = cooldownData.enabled,
                        rawStart = cooldownData.rawStart,
                        rawDuration = cooldownData.rawDuration,
                        isSecret = cooldownData.isSecret,
                        isActive = cooldownData.isActive,
                        itemID = itemID,
                        trinketSlot = equippedTrinketSlot
                    }
                end

                local cooldown = getCooldownDetails()
                local ignoredByName = (ignoredSpells[cooldown.name] ~= nil)
                local ignoredByTrackingID = (ignoredSpells[tostring(watchedID)] ~= nil)
                local ignoredByItemID = (cooldown.itemID ~= nil and ignoredSpells[tostring(cooldown.itemID)] ~= nil)
                if ((ignoredByName or ignoredByTrackingID or ignoredByItemID) ~= invertIgnored) then
                    itemWatching[watchedID] = nil
                else
                    local duration = SafeNumber(cooldown.duration)
                    local hasLongNumericCooldown = (duration and duration > MINIMUM_FLASH_COOLDOWN)
                    local hasUnknownDurationActiveCooldown = (cooldown.isActive and duration == nil)

                    if (cooldown.texture and (hasLongNumericCooldown or hasUnknownDurationActiveCooldown)) then
                        local entryReadyAt = watchedEntry[6]
                        local currentReadyAt = GetCooldownReadyAt(cooldown.start, cooldown.duration)
                        if currentReadyAt and (not entryReadyAt or currentReadyAt > entryReadyAt) then
                            entryReadyAt = currentReadyAt
                        end

                        itemCooldowns[watchedID] = {
                            getCooldownDetails = getCooldownDetails,
                            wasActive = (cooldown.isActive == true),
                            startedAt = watchedEntry[1],
                            readyAt = entryReadyAt
                        }
                        itemWatching[watchedID] = nil
                    else
                        itemWatching[watchedID] = nil
                    end
                end
            end
        end

        for i,entry in pairs(spellCooldowns) do
            local getCooldownDetails = entry.getCooldownDetails or entry
            local cooldown = getCooldownDetails()
            local start = SafeNumber(cooldown.start)
            local duration = SafeNumber(cooldown.duration)
            if cooldown.enabled and cooldown.isOnGCD == true then
                -- Only the GCD remains: the tracked ability has finished or reset.
                -- A real cooldown should pulse without waiting for that GCD.
                local elapsedSinceStart = GetTime() - entry.startedAt
                if entry.hasLongNumericCooldown or elapsedSinceStart > MINIMUM_FLASH_COOLDOWN then
                    QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name, cooldown.spellID, cooldown.itemID)
                end
                spellCooldowns[i] = nil
            elseif (cooldown.enabled and start and duration) then
                local remaining = duration-(GetTime()-start)
                if (remaining <= remainingCooldownWhenNotified) then
                    if not entry.restrictedTiming or GetTime() - entry.startedAt > MINIMUM_FLASH_COOLDOWN then
                        QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name, cooldown.spellID, cooldown.itemID)
                    end
                    spellCooldowns[i] = nil
                end
            elseif (entry and entry.wasActive ~= nil and cooldown.isActive ~= nil) then
                -- Secret-safe path: cooldown was active and became inactive.
                if (entry.wasActive and not cooldown.isActive) then
                    local elapsedSinceStart = nil
                    if entry.startedAt then
                        elapsedSinceStart = GetTime() - entry.startedAt
                    end

                    if (elapsedSinceStart == nil or elapsedSinceStart > MINIMUM_FLASH_COOLDOWN) then
                        QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name, cooldown.spellID, cooldown.itemID)
                        spellCooldowns[i] = nil
                    else
                        spellCooldowns[i] = nil
                    end
                else
                    entry.wasActive = (cooldown.isActive == true)
                end
            else
                spellCooldowns[i] = nil
            end
        end

        for i,entry in pairs(itemCooldowns) do
            local getCooldownDetails = entry.getCooldownDetails or entry
            local cooldown = getCooldownDetails()
            local start = SafeNumber(cooldown.start)
            local duration = SafeNumber(cooldown.duration)
            local trinketSlot = cooldown.trinketSlot
            local stickyReadyRemaining = nil
            if (trinketSlot == 13 or trinketSlot == 14) and entry.readyAt then
                stickyReadyRemaining = entry.readyAt - GetTime()
            end

            if (trinketSlot == 13 or trinketSlot == 14) then
                local currentReadyAt = GetCooldownReadyAt(start, duration)
                if currentReadyAt and (not entry.readyAt or currentReadyAt > entry.readyAt) then
                    -- Accept only longer/equal extension updates for trinkets.
                    -- This blocks shared 20s lockout snapshots from replacing a
                    -- previously known longer own-trinket cooldown.
                    entry.readyAt = currentReadyAt
                end
            end

            if (cooldown.enabled and start and duration) then
                local remaining
                if (trinketSlot == 13 or trinketSlot == 14) and entry.readyAt then
                    remaining = entry.readyAt - GetTime()
                else
                    remaining = duration-(GetTime()-start)
                end
                if (remaining <= remainingCooldownWhenNotified) then
                    local shouldFlash = true
                    if (trinketSlot == 13 or trinketSlot == 14) then
                        if stickyReadyRemaining and stickyReadyRemaining > remainingCooldownWhenNotified then
                            shouldFlash = false
                        else
                            shouldFlash = IsEquippedTrinketReady(cooldown.itemID or i, trinketSlot)
                        end
                    end

                    if shouldFlash then
                        QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name, cooldown.spellID, cooldown.itemID)
                        itemCooldowns[i] = nil
                    else
                        itemCooldowns[i] = nil
                        itemWatching[i] = {GetTime(), "item", cooldown.texture, trinketSlot, cooldown.itemID, entry.readyAt}
                    end
                end
            elseif (entry and entry.wasActive ~= nil and cooldown.isActive ~= nil) then
                if (entry.wasActive and not cooldown.isActive) then
                    local elapsedSinceStart = nil
                    if entry.startedAt then
                        elapsedSinceStart = GetTime() - entry.startedAt
                    end

                    if (elapsedSinceStart == nil or elapsedSinceStart > MINIMUM_FLASH_COOLDOWN) then
                        local shouldFlash = true
                        if (trinketSlot == 13 or trinketSlot == 14) then
                            if stickyReadyRemaining and stickyReadyRemaining > remainingCooldownWhenNotified then
                                shouldFlash = false
                            else
                                shouldFlash = IsEquippedTrinketReady(cooldown.itemID or i, trinketSlot)
                            end
                        end

                        if shouldFlash then
                            QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name, cooldown.spellID, cooldown.itemID)
                            itemCooldowns[i] = nil
                        else
                            itemCooldowns[i] = nil
                            itemWatching[i] = {GetTime(), "item", cooldown.texture, trinketSlot, cooldown.itemID, entry.readyAt}
                        end
                    else
                        itemCooldowns[i] = nil
                    end
                else
                    entry.wasActive = (cooldown.isActive == true)
                end
            else
                itemCooldowns[i] = nil
            end
        end

        elapsed = 0
        if (#animating == 0 and tcount(spellWatching) == 0 and tcount(itemWatching) == 0 and tcount(spellCooldowns) == 0 and tcount(itemCooldowns) == 0) then
            DCP:SetScript("OnUpdate", nil)
            return
        end
    end

    if (#animating > 0) then
        runtimer = runtimer + update
        if (runtimer > (fadeInTime + holdTime + fadeOutTime)) then
            tremove(animating,1)
            runtimer = 0
            DCP.TextFrame:SetText(nil)
            DCPT:SetTexture(nil)
            DCPT:SetVertexColor(1,1,1)
        else
            if (type(animating[1]) ~= "table") then
                tremove(animating,1)
                runtimer = 0
                DCPT:SetTexture(nil)
                DCP.TextFrame:SetText(nil)
                return
            end

            if (not DCPT:GetTexture()) then
                if (animating[1][3] ~= nil and showSpellName) then
                    DCP.TextFrame:SetText(animating[1][3])
                end
                local texture = animating[1][1]
                if texture then
                    DCPT:SetTexture(texture)
                    RecordPulse(animating[1])
                else
                    DCPT:SetTexture(nil)
                end
                if animating[1][2] then
                    local overlay = DCP_Saved.petOverlay
                    if type(overlay) == "table" then
                        DCPT:SetVertexColor(tonumber(overlay[1]) or 1, tonumber(overlay[2]) or 1, tonumber(overlay[3]) or 1)
                    else
                        DCPT:SetVertexColor(1,1,1)
                    end
                end
            end
            local alpha = maxAlpha
            if (runtimer < fadeInTime) then
                alpha = maxAlpha * (runtimer / fadeInTime)
            elseif (runtimer >= fadeInTime + holdTime) then
                alpha = maxAlpha - ( maxAlpha * ((runtimer - holdTime - fadeInTime) / fadeOutTime))
            end
            DCP:SetAlpha(alpha)
            local scale = iconSize+(iconSize*((animScale-1)*(runtimer/(fadeInTime+holdTime+fadeOutTime))))
            DCP:SetWidth(scale)
            DCP:SetHeight(scale)
        end
    end
end

--------------------
-- Event Handlers --
--------------------
function DCP:ADDON_LOADED(addon)
    if addon ~= addonName then return end
    InitializeSavedVariables()
    RefreshLocals()
    self:SetPoint("CENTER",UIParent,"BOTTOMLEFT",DCP_Saved.x,DCP_Saved.y)
    self:UnregisterEvent("ADDON_LOADED")
    if not self:RegisterSettingsCategory() then self:RegisterEvent("PLAYER_LOGIN") end
end
DCP:RegisterEvent("ADDON_LOADED")

function DCP:SPELL_UPDATE_COOLDOWN()
    -- SpellCooldownInfo.isOnGCD is NeverSecret, but only reliable in this event.
    -- Query the Pet bank for pet watches, just as the Forever polling path does.
    local function refreshGlobalCooldown(watch)
        if not watch then return end
        local cooldown = GetWatchedSpellCooldown(watch[3], watch[4])
        watch.isOnGCD = cooldown and SafeBoolean(cooldown.isOnGCD, nil)
    end
    for _, watch in pairs(spellWatching) do
        refreshGlobalCooldown(watch)
    end
    for _,entry in pairs(spellCooldowns) do
        refreshGlobalCooldown(entry.watch)
        local getCooldownDetails = entry.getCooldownDetails or entry
        -- Add a type check so Lua doesn't crash trying to index a raw function
        if type(getCooldownDetails) == "table" and getCooldownDetails.resetCache then
            getCooldownDetails.resetCache()
        end
    end
end
DCP:RegisterEvent("SPELL_UPDATE_COOLDOWN")

-- Listen only for the player and pet; Forever has no readable combat log.
function DCP:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if IsSecret(unit) or IsSecret(spellID) then return end
    if unit == "pet" and not showPetCooldowns then return end
    if ((unit == "player" or unit == "pet") and spellID) then
        
        -- Item spell casts also arrive here. Route them through item tracking so
        -- /use macros work and the same cooldown doesn't pulse twice.
        if unit == "player" then
            for slot = 13, 14 do
                local itemID = GetInventoryItemID("player", slot)
                if itemID then
                    local _, itemSpellID = C_Item.GetItemSpell(itemID)
                    if itemSpellID == spellID then
                        WatchItemAndSharedTrinket(itemID, slot)
                        return
                    end
                end
            end
        end

        if IsInternalSpell(C_Spell.GetSpellInfo(spellID)) then return end

        local isPet = (unit == "pet")
        local spellKey = GetSpellTrackingKey(spellID)
        -- Store spell in watching; v[4] = isPet flag so the pet overlay is applied.
        spellWatching[spellKey] = {GetTime(), "spell", spellID, isPet}

        if (not self:IsMouseEnabled()) then
            self:SetScript("OnUpdate", OnUpdate)
        end
    end
end
DCP:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")

function DCP:PLAYER_ENTERING_WORLD()
    local inInstance,instanceType = IsInInstance()
    if (inInstance and instanceType == "arena") then
        self:SetScript("OnUpdate", nil)
        wipe(spellCooldowns)
        wipe(itemCooldowns)
        wipe(spellWatching)
        wipe(itemWatching)
    end
end
DCP:RegisterEvent("PLAYER_ENTERING_WORLD")

function DCP:PLAYER_SPECIALIZATION_CHANGED(unit)
    if (unit == "player") then
        wipe(spellCooldowns)
        wipe(itemCooldowns)
        wipe(spellWatching)
        wipe(itemWatching)
    end
end
-- Forever shares WOW_PROJECT_MAINLINE with Retail; API availability matters.
DCP:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

hooksecurefunc("UseAction", function(slot)
    if IsSecret(slot) then return end
    local actionType, itemID = GetActionInfo(slot)
    if IsSecret(actionType) or IsSecret(itemID) then return end
    if (actionType == "item" and itemID) then
        -- Secret-safe: track by itemID/slot and include paired trinket lockout.
        WatchItemAndSharedTrinket(itemID)
    end
end)

-- Some modern clients omit this legacy global.
if UseInventoryItem then
    hooksecurefunc("UseInventoryItem", function(slot)
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            WatchItemAndSharedTrinket(itemID, slot)
        end
    end)
end

-- Bag item use is namespaced on the modern client.
if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        local itemID = C_Container.GetContainerItemID(bag, slot)
        if itemID then
            WatchItemAndSharedTrinket(itemID)
        end
    end)
end

-------------------
-- Options Frame --
-------------------

SlashCmdList["DOOMCOOLDOWNPULSE"] = function(message)
    local command = strtrim(message or ""):lower()
    if command == "last" then
        ShowRecentPulses()
        return
    elseif command == "last clear" then
        wipe(recentPulses)
        print("DCP: Recent pulse history cleared.")
        return
    end
    DCP:OpenFloatingOptions()
end
SLASH_DOOMCOOLDOWNPULSE1 = "/dcp"
SLASH_DOOMCOOLDOWNPULSE2 = "/cooldownpulse"
SLASH_DOOMCOOLDOWNPULSE3 = "/doomcooldownpulse"

function DCP:CreateOptionsFrame()
    local sliders = optionSliders
    local syncingOptions = false

    local buttons = {
        { text = "Close", func = function() DCP:CloseOptionsFrame() end },
        { text = "Test", func = function(self)
            DCP_OptionsFrameButton3:SetText("Unlock")
            DCP:EnableMouse(false)
            RefreshLocals()
            tinsert(animating,{"Interface\\Icons\\Spell_Nature_Earthbind",nil,"Spell Name"})
            DCP:SetScript("OnUpdate", OnUpdate)
            end },
        { text = "Unlock", func = function(self)
            if (self:GetText() == "Unlock") then
                RefreshLocals()
                DCP:SetWidth(iconSize)
                DCP:SetHeight(iconSize)
                self:SetText("Lock")
                DCP:SetScript("OnUpdate", nil)
                DCP:SetAlpha(1)
                DCPT:SetTexture("Interface\\Icons\\Spell_Nature_Earthbind")
                DCP:EnableMouse(true)
            else
                DCP:SetAlpha(0)
                self:SetText("Unlock")
                DCP:EnableMouse(false)
            end end },
        { text = "Defaults", func = function(self)
            for i,v in pairs(defaultSettings) do
                DCP_Saved[i] = v
            end
            for i,v in pairs(defaultSettingsPerCharacter) do
                DCP_SavedPerCharacter[i] = v
            end
            for i,v in pairs(sliders) do
                getglobal("DCP_OptionsFrameSlider"..i):SetValue(DCP_Saved[v.value])
            end
            DCP_OptionsFramePetColorBox:GetNormalTexture():SetVertexColor(unpack(DCP_Saved.petOverlay))
            DCP_OptionsFrameIgnoreTypeButtonWhitelist:SetChecked(false)
            DCP_OptionsFrameIgnoreTypeButtonBlacklist:SetChecked(true)
            DCP_OptionsFrameIgnoreBox:SetText("")
            DCP_OptionsFramePetPulsesCheckButton:SetChecked(DCP_SavedPerCharacter.showPetCooldowns)
            RefreshLocals()
            DCP:ClearAllPoints()
            DCP:SetPoint("CENTER",UIParent,"BOTTOMLEFT",DCP_Saved.x,DCP_Saved.y)
            end },
    }

    local optionsframe = CreateFrame("frame","DCP_OptionsFrame",UIParent,BackdropTemplateMixin and "BackdropTemplate")
    optionsframe:SetBackdrop({
      bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
      tile=1, tileSize=32, edgeSize=32,
      insets={left=11, right=12, top=12, bottom=11}
    })
    optionsframe:SetWidth(230)
    optionsframe:SetHeight(660)
    optionsframe:SetPoint("CENTER",UIParent)
    optionsframe:EnableMouse(true)
    optionsframe:SetMovable(true)
    optionsframe:RegisterForDrag("LeftButton")
    optionsframe:SetScript("OnDragStart", function(self) self:StartMoving() end)
    optionsframe:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    optionsframe:SetFrameStrata("FULLSCREEN_DIALOG")
    optionsframe:SetScript("OnHide", function() RefreshLocals() end)
    tinsert(UISpecialFrames, "DCP_OptionsFrame")

    local header = optionsframe:CreateTexture(nil,"ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header.blp")
    header:SetWidth(350)
    header:SetHeight(68)
    header:SetPoint("TOP",optionsframe,"TOP",0,12)

    local headertext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormal")
    headertext:SetPoint("TOP",header,"TOP",0,-14)
    headertext:SetText("Doom CooldownPulse")

    for i,v in pairs(sliders) do
        local slider = CreateFrame("slider", "DCP_OptionsFrameSlider"..i, optionsframe, "OptionsSliderTemplate")
        if (i == 1) then
            slider:SetPoint("TOP",optionsframe,"TOP",0,-50)
        else
            slider:SetPoint("TOP",getglobal("DCP_OptionsFrameSlider"..(i-1)),"BOTTOM",0,-35)
        end
        local valuetext = slider:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
        valuetext:SetPoint("TOP",slider,"BOTTOM",0,-1)
        valuetext:SetText(format("%.1f",DCP_Saved[v.value]))
        getglobal("DCP_OptionsFrameSlider"..i.."Text"):SetText(v.text)
        getglobal("DCP_OptionsFrameSlider"..i.."Low"):SetText(v.min)
        getglobal("DCP_OptionsFrameSlider"..i.."High"):SetText(v.max)
        slider:SetMinMaxValues(v.min,v.max)
        slider:SetValueStep(v.step)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(DCP_Saved[v.value])
        slider:SetScript("OnValueChanged",function()
            local value = slider:GetValue()
            valuetext:SetText(format("%.1f", value))
            if syncingOptions then return end
            DCP_Saved[v.value] = value
            RefreshLocals()
            if (DCP:IsMouseEnabled()) then
                DCP:SetWidth(DCP_Saved.iconSize)
                DCP:SetHeight(DCP_Saved.iconSize)
            end
        end)
    end

    local petpulsecbt = CreateFrame("CheckButton", "DCP_OptionsFramePetPulsesCheckButton", optionsframe, "UICheckButtonTemplate")
    petpulsecbt:SetPoint("TOPLEFT", "DCP_OptionsFrameSlider"..#sliders, "BOTTOMLEFT", -20, -14)
    petpulsecbt:SetChecked(DCP_SavedPerCharacter.showPetCooldowns)
    petpulsecbt:SetScript("OnClick", function(self)
        DCP_SavedPerCharacter.showPetCooldowns = self:GetChecked() == true
        RefreshLocals()
    end)
    local petpulsetext = optionsframe:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    petpulsetext:SetPoint("LEFT", petpulsecbt, "RIGHT", 0, 0)
    petpulsetext:SetText("Show pet cooldown pulses")

    local pettext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    pettext:SetPoint("TOPLEFT", petpulsecbt, "BOTTOMLEFT", 5, -6)
    pettext:SetText("Pet color overlay:")

    local petcolorselect = CreateFrame('Button',"DCP_OptionsFramePetColorBox",optionsframe)
    petcolorselect:SetPoint("LEFT",pettext,"RIGHT",10,0)
    petcolorselect:SetWidth(20)
    petcolorselect:SetHeight(20)
    petcolorselect:SetNormalTexture('Interface/ChatFrame/ChatFrameColorSwatch')
    petcolorselect:GetNormalTexture():SetVertexColor(unpack(DCP_Saved.petOverlay))
    petcolorselect:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self, "ANCHOR_CURSOR") GameTooltip:SetText("Note: Use white if you don't want any overlay for pet cooldowns") end)
    petcolorselect:SetScript("OnLeave",function(self) GameTooltip:Hide() end)
    petcolorselect:SetScript('OnClick', function(self)
        local r, g, b = unpack(DCP_Saved.petOverlay)
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function(self) DCP_Saved.petOverlay={ColorPickerFrame:GetColorRGB()} petcolorselect:GetNormalTexture():SetVertexColor(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function(self) DCP_Saved.petOverlay={r,g,b} petcolorselect:GetNormalTexture():SetVertexColor(unpack(DCP_Saved.petOverlay)) end,
            hasOpacity = false,
            r = r,
            g = g,
            b = b
        })
        ColorPickerFrame:SetPoint("TOPLEFT",optionsframe,"TOPRIGHT")
    end)

    local petcolorselectbg = petcolorselect:CreateTexture(nil, 'BACKGROUND')
    petcolorselectbg:SetWidth(17)
    petcolorselectbg:SetHeight(17)
    petcolorselectbg:SetColorTexture(1,1,1)
    petcolorselectbg:SetPoint('CENTER')

    local spellnametext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    spellnametext:SetPoint("TOPLEFT",pettext,"BOTTOMLEFT",0,-18)
    spellnametext:SetText("Show spell name:")

    local spellnamecbt = CreateFrame("CheckButton","DCP_OptionsFrameSpellNameCheckButton",optionsframe,"UICheckButtonTemplate")
    spellnamecbt:SetPoint("LEFT",spellnametext,"RIGHT",6,0)
    spellnamecbt:SetChecked(DCP_Saved.showSpellName)
    spellnamecbt:SetScript("OnClick", function(self)
        local newState = self:GetChecked()
        self:SetChecked(newState)
        DCP_Saved.showSpellName = newState
        RefreshLocals()
    end)

    local ignoretext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    ignoretext:SetPoint("TOPLEFT",spellnametext,"BOTTOMLEFT",0,-18)
    ignoretext:SetText("Filter spells:")

    local ignoretypebuttonblacklist = CreateFrame("Checkbutton","DCP_OptionsFrameIgnoreTypeButtonBlacklist",optionsframe,"UIRadioButtonTemplate")
    ignoretypebuttonblacklist:SetPoint("TOPLEFT",ignoretext,"BOTTOMLEFT",0,-4)
    ignoretypebuttonblacklist:SetChecked(not DCP_SavedPerCharacter.invertIgnored)
    ignoretypebuttonblacklist:SetScript("OnClick", function()
        DCP_OptionsFrameIgnoreTypeButtonWhitelist:SetChecked(false)
        DCP_SavedPerCharacter.invertIgnored = false
        RefreshLocals()
    end)

    local ignoretypetextblacklist = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    ignoretypetextblacklist:SetPoint("LEFT",ignoretypebuttonblacklist,"RIGHT",4,0)
    ignoretypetextblacklist:SetText("Blacklist")

    local ignoretypebuttonwhitelist = CreateFrame("Checkbutton","DCP_OptionsFrameIgnoreTypeButtonWhitelist",optionsframe,"UIRadioButtonTemplate")
    ignoretypebuttonwhitelist:SetPoint("LEFT",ignoretypetextblacklist,"RIGHT",10,0)
    ignoretypebuttonwhitelist:SetChecked(DCP_SavedPerCharacter.invertIgnored)
    ignoretypebuttonwhitelist:SetScript("OnClick", function()
        DCP_OptionsFrameIgnoreTypeButtonBlacklist:SetChecked(false)
        DCP_SavedPerCharacter.invertIgnored = true
        RefreshLocals()
    end)

    local ignoretypetextwhitelist = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    ignoretypetextwhitelist:SetPoint("LEFT",ignoretypebuttonwhitelist,"RIGHT",4,0)
    ignoretypetextwhitelist:SetText("Whitelist")

    local ignorebox = CreateFrame("EditBox","DCP_OptionsFrameIgnoreBox",optionsframe,"InputBoxTemplate")
    ignorebox:SetAutoFocus(false)
    ignorebox:SetPoint("TOPLEFT",ignoretypebuttonblacklist,"BOTTOMLEFT",4,-8)
    ignorebox:SetWidth(170)
    ignorebox:SetHeight(32)
    ignorebox:SetText(DCP_SavedPerCharacter.ignoredSpells)
    ignorebox:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self, "ANCHOR_CURSOR") GameTooltip:SetText("Note: Separate multiple spells with commas") end)
    ignorebox:SetScript("OnLeave",function(self) GameTooltip:Hide() end)
    ignorebox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    ignorebox:SetScript("OnEditFocusLost",function(self)
        DCP_SavedPerCharacter.ignoredSpells = ignorebox:GetText()
        RefreshLocals()
    end)

    for i,v in pairs(buttons) do
        local button = CreateFrame("Button", "DCP_OptionsFrameButton"..i, optionsframe, "UIPanelButtonTemplate")
        button:SetHeight(24)
        button:SetWidth(75)
        button:SetPoint("BOTTOM", optionsframe, "BOTTOM", ((i%2==0 and -1) or 1)*45, 10 + ceil(i/2)*15 + (ceil(i/2)-1)*15)
        button:SetText(v.text)
        button:SetScript("OnClick", function(self) PlaySound(852) v.func(self) end)
    end
    optionsframe:SetScript("OnShow", function()
        syncingOptions = true
        for i, definition in ipairs(sliders) do
            getglobal("DCP_OptionsFrameSlider"..i):SetValue(DCP_Saved[definition.value])
        end
        DCP_OptionsFramePetPulsesCheckButton:SetChecked(DCP_SavedPerCharacter.showPetCooldowns)
        DCP_OptionsFrameSpellNameCheckButton:SetChecked(DCP_Saved.showSpellName == true)
        DCP_OptionsFrameIgnoreTypeButtonBlacklist:SetChecked(not DCP_SavedPerCharacter.invertIgnored)
        DCP_OptionsFrameIgnoreTypeButtonWhitelist:SetChecked(DCP_SavedPerCharacter.invertIgnored)
        DCP_OptionsFrameIgnoreBox:SetText(DCP_SavedPerCharacter.ignoredSpells)
        DCP_OptionsFramePetColorBox:GetNormalTexture():SetVertexColor(unpack(DCP_Saved.petOverlay))
        syncingOptions = false
    end)
end


-- Settings provides a launcher; all controls remain in the /dcp window.
function DCP:OpenFloatingOptions()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if not DCP_OptionsFrame then self:CreateOptionsFrame() end
    DCP_OptionsFrame:Show()
end

function DCP:CloseOptionsFrame()
    DCP_OptionsFrame:Hide()
end

function DCP:RegisterSettingsCategory()
    if settingsCategory then return true end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return false end
    local panel = CreateFrame("Frame", "DCP_ForeverSettingsPanel", UIParent)
    panel:Hide()
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -28)
    title:SetText("Doom CooldownPulse")
    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    description:SetPoint("TOP", title, "BOTTOM", 0, -20)
    description:SetWidth(460)
    description:SetText("Use the floating options window to customize cooldown pulses.")
    local button = CreateFrame("Button", "DCP_ForeverSettingsOpenOptions", panel, "UIPanelButtonTemplate")
    button:SetSize(360, 56)
    button:SetPoint("TOP", description, "BOTTOM", 0, -28)
    button:SetNormalFontObject("GameFontNormalLarge")
    button:SetText("Open /dcp options")
    button:SetScript("OnClick", function() DCP:OpenFloatingOptions() end)
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "Doom CooldownPulse")
    Settings.RegisterAddOnCategory(settingsCategory)
    return true
end

function DCP:PLAYER_LOGIN()
    self:RegisterSettingsCategory()
    self:UnregisterEvent("PLAYER_LOGIN")
end
