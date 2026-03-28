local fadeInTime, fadeOutTime, maxAlpha, animScale, iconSize, holdTime, showSpellName, ignoredSpells, invertIgnored, remainingCooldownWhenNotified
local spellCooldowns, itemCooldowns, animating, spellWatching, itemWatching = { }, { }, { }, { }, { }
local GetTime = GetTime
local unpack = unpack or table.unpack
local OnUpdate
local MINIMUM_FLASH_COOLDOWN = 2.0
local IsEquippedTrinketReady

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
    invertIgnored = false
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

local function IsAnimatingCooldownByName(name)
    for i, details in pairs(animating) do
        if details[3] == name then
            return true
        end
    end

    return false
end

local function QueueAnimation(texture, isPet, name)
    if texture and not IsAnimatingCooldownByName(name) then
        tinsert(animating, {texture, isPet, name})
    end

    if (not DCP:IsMouseEnabled()) then
        DCP:SetScript("OnUpdate", OnUpdate)
    end
end

local secretCooldownBucket = CreateFrame("Frame", nil, UIParent)
secretCooldownBucket:SetSize(1, 1)
secretCooldownBucket:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
secretCooldownBucket:Show()

local secretCooldownFrames = {}

local function StartSecretCooldownTracker(id, cooldownType, cooldown, startedAt)
    if not cooldown or not cooldown.texture then
        return false
    end

    if cooldown.rawStart == nil or cooldown.rawDuration == nil then
        return false
    end

    local key = tostring(cooldownType) .. ":" .. tostring(id)
    local frame = secretCooldownFrames[key]
    if not frame then
        frame = CreateFrame("Cooldown", nil, secretCooldownBucket, "CooldownFrameTemplate")
        frame:SetAllPoints(secretCooldownBucket)
        frame:SetDrawSwipe(false)
        frame:SetDrawEdge(false)
        frame:SetDrawBling(false)
        frame:SetHideCountdownNumbers(true)
        frame.noCooldownCount = true
        frame:SetScript("OnCooldownDone", function(self)
            local elapsedSinceTrigger = nil
            if self._startedAt then
                elapsedSinceTrigger = GetTime() - self._startedAt
            end

            -- Preserve original behavior: ignore very short cooldowns.
            if (elapsedSinceTrigger == nil or elapsedSinceTrigger > MINIMUM_FLASH_COOLDOWN) then
                local trinketSlot = self._trinketSlot
                local shouldFlash = true
                if (trinketSlot == 13 or trinketSlot == 14) then
                    shouldFlash = IsEquippedTrinketReady and IsEquippedTrinketReady(self._itemID, trinketSlot)
                end

                if shouldFlash then
                    QueueAnimation(self._texture, self._isPet, self._name)
                elseif (self._itemID and trinketSlot) then
                    -- Re-check a bit later if the secret cooldown completed but the
                    -- trinket is still not truly ready (shared-lockout edge cases).
                    itemWatching[self._watchKey] = {GetTime(), "item", self._texture, trinketSlot, self._itemID}
                end
            end
        end)
        secretCooldownFrames[key] = frame
    end

    frame._name = cooldown.name
    frame._texture = cooldown.texture
    frame._isPet = cooldown.isPet
    frame._startedAt = startedAt
    frame._watchKey = id
    frame._itemID = cooldown.itemID or id
    frame._trinketSlot = cooldown.trinketSlot

    local configured = false

    -- Midnight security update: secret cooldown values must be configured via
    -- duration objects, not SetCooldown(start, duration).
    if frame.SetCooldownFromDurationObject and cooldown.durationObject then
        configured = pcall(function()
            frame:SetCooldownFromDurationObject(cooldown.durationObject)
        end)
    end

    -- Fallback for non-secret numeric cooldowns (older behavior).
    if not configured and cooldown.rawStart ~= nil and cooldown.rawDuration ~= nil then
        configured = pcall(function()
            frame:SetCooldown(cooldown.rawStart, cooldown.rawDuration)
        end)
    end

    return configured
end

local function SafeNumber(value)
    if value == nil then
        return nil
    end

    local ok, num = pcall(function()
        return value + 0
    end)

    if ok and type(num) == "number" then
        return num
    end

    return nil
end

local function NormalizeCooldown(rawStartOrTable, rawDuration, rawEnabled, defaultEnabled)
    local start, duration, enabled
    local rawStart, rawDurationValue
    local isActive
    local durationObject

    if type(rawStartOrTable) == "table" then
        rawStart = rawStartOrTable.startTime or rawStartOrTable.start or rawStartOrTable[1]
        rawDurationValue = rawStartOrTable.duration or rawStartOrTable[2]
        isActive = rawStartOrTable.isActive

        -- Try to preserve any duration object returned by the API for secure
        -- cooldown frame setup in Midnight.
        if type(rawDurationValue) == "table" then
            durationObject = rawDurationValue
        else
            durationObject = rawStartOrTable.durationObject or rawStartOrTable.cooldownDuration
        end

        start = SafeNumber(rawStart)
        duration = SafeNumber(rawDurationValue)
        -- IMPORTANT: Do NOT read/test `isEnabled` here in Midnight.
        -- It can be a protected "secret boolean" and throws when used in boolean ops.
        enabled = defaultEnabled
    else
        rawStart = rawStartOrTable
        rawDurationValue = rawDuration
        start = SafeNumber(rawStart)
        duration = SafeNumber(rawDurationValue)
        if rawEnabled == nil then
            enabled = defaultEnabled
        elseif rawEnabled == 0 then
            enabled = false
        elseif rawEnabled == 1 then
            enabled = true
        else
            -- Avoid boolean-testing unknown values; fall back to default.
            enabled = defaultEnabled
        end
    end

    local isSecret = false
    if rawStart ~= nil and start == nil then
        isSecret = true
    end
    if rawDurationValue ~= nil and duration == nil then
        isSecret = true
    end

    return start, duration, enabled, rawStart, rawDurationValue, isSecret, isActive, durationObject
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

local function BuildCooldownData(rawStartOrTable, rawDuration)
    local start, duration, enabled, normalizedRawStart, normalizedRawDuration, isSecret, isActive, durationObject = NormalizeCooldown(rawStartOrTable, rawDuration, nil, true)
    return {
        start = start,
        duration = duration,
        enabled = enabled,
        rawStart = normalizedRawStart,
        rawDuration = normalizedRawDuration,
        isSecret = isSecret,
        isActive = isActive,
        durationObject = durationObject,
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
        local slotRawStartOrTable, slotRawDuration = GetInventoryItemCooldown("player", trinketSlot)
        slotCooldownData = BuildCooldownData(slotRawStartOrTable, slotRawDuration)
    end

    local itemCooldownData
    if C_Item and C_Item.GetItemCooldown then
        local itemRawStartOrTable, itemRawDuration = C_Item.GetItemCooldown(itemID)
        itemCooldownData = BuildCooldownData(itemRawStartOrTable, itemRawDuration)
    end

    local function stillCoolingDown(data)
        if not data then
            return false
        end

        if data.remaining and data.remaining > remainingCooldownWhenNotified then
            return true
        end

        -- Midnight-safe: unknown numeric duration but still active means not ready.
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

    -- Do not override an already tracked cooldown unless explicitly requested.
    -- This prevents shared-trinket helper watches from replacing a trinket's
    -- real longer cooldown entry with a fresh 20s shared lockout snapshot.
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

    itemWatching[itemKey] = {GetTime(), "item", texture, inventorySlot, itemID, nil}
end

local function WatchItemAndSharedTrinket(itemID, knownSlot)
    local slot = knownSlot or FindEquippedTrinketSlotByItemID(itemID)

    -- The directly used item should always refresh its own watch snapshot.
    QueueWatchedItem(itemID, slot, true)

    -- Midnight trinkets can share a 20s lockout; also watch the other trinket
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
local runtimer = 0
OnUpdate = function(_,update)
    elapsed = elapsed + update
    if (elapsed > 0.05) then
        for id, v in pairs(spellWatching) do
            if (GetTime() >= v[1] + 0.5) then
                local watchedID = id
                local watchedEntry = v
                local getCooldownDetails = memoize(function()
                    if not (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellCooldown) then
                        return {}
                    end
                    if not watchedEntry[3] then
                        return {}
                    end
                    local info = C_Spell.GetSpellInfo(watchedEntry[3])
                    local cooldown = C_Spell.GetSpellCooldown(watchedEntry[3])
                    local start, duration, enabled, rawStart, rawDuration, isSecret, isActive, durationObject = NormalizeCooldown(cooldown, nil, nil, true)
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
                        durationObject = durationObject,
                        spellID = watchedEntry[3],
                        isPet = watchedEntry[4]
                    }
                end)

                local cooldown = getCooldownDetails()
                local ignoredByName = (ignoredSpells[cooldown.name] ~= nil)
                local ignoredByTrackingID = (ignoredSpells[tostring(watchedID)] ~= nil)
                local ignoredBySpellID = (cooldown.spellID ~= nil and ignoredSpells[tostring(cooldown.spellID)] ~= nil)
                if ((ignoredByName or ignoredByTrackingID or ignoredBySpellID) ~= invertIgnored) then
                    spellWatching[watchedID] = nil
                else
                    local duration = SafeNumber(cooldown.duration)
                    local hasLongNumericCooldown = (duration and duration > MINIMUM_FLASH_COOLDOWN)
                    local hasUnknownDurationActiveCooldown = (cooldown.isActive and duration == nil)

                    if (cooldown.texture and (hasLongNumericCooldown or hasUnknownDurationActiveCooldown)) then
                        spellCooldowns[watchedID] = {
                            getCooldownDetails = getCooldownDetails,
                            wasActive = (cooldown.isActive == true),
                            startedAt = watchedEntry[1]
                        }
                        spellWatching[watchedID] = nil
                    elseif ((cooldown.isActive or cooldown.isSecret) and StartSecretCooldownTracker(watchedID, watchedEntry[2], cooldown, watchedEntry[1])) then
                        spellWatching[watchedID] = nil
                    end

                    -- Keep watching short spell cooldowns (likely GCD/start recovery)
                    local isShortSpellCooldown = (duration and duration > 0 and duration <= 2.0)
                    if (not isShortSpellCooldown) then
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
                        local slotRawStartOrTable, slotRawDuration = GetInventoryItemCooldown("player", equippedTrinketSlot)
                        slotCooldownData = BuildCooldownData(slotRawStartOrTable, slotRawDuration)
                    end

                    local itemCooldownData
                    if C_Item and C_Item.GetItemCooldown then
                        local itemRawStartOrTable, itemRawDuration = C_Item.GetItemCooldown(itemID)
                        itemCooldownData = BuildCooldownData(itemRawStartOrTable, itemRawDuration)
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
                        durationObject = cooldownData.durationObject,
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
                    elseif ((cooldown.isActive or cooldown.isSecret) and StartSecretCooldownTracker(watchedID, watchedEntry[2], cooldown, watchedEntry[1])) then
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
            if (start and duration) then
                local remaining = duration-(GetTime()-start)
                if (remaining <= remainingCooldownWhenNotified) then
                    QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name)
                    spellCooldowns[i] = nil
                end
            elseif (entry and entry.wasActive ~= nil and cooldown.isActive ~= nil) then
                -- Midnight-safe path: cooldown was active and became inactive.
                if (entry.wasActive and not cooldown.isActive) then
                    local elapsedSinceStart = nil
                    if entry.startedAt then
                        elapsedSinceStart = GetTime() - entry.startedAt
                    end

                    if (elapsedSinceStart == nil or elapsedSinceStart > MINIMUM_FLASH_COOLDOWN) then
                        QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name)
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

            if (start and duration) then
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
                        QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name)
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
                            QueueAnimation(cooldown.texture, cooldown.isPet, cooldown.name)
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
    InitializeSavedVariables()
    RefreshLocals()
    self:SetPoint("CENTER",UIParent,"BOTTOMLEFT",DCP_Saved.x,DCP_Saved.y)
    self:UnregisterEvent("ADDON_LOADED")
end
DCP:RegisterEvent("ADDON_LOADED")

function DCP:SPELL_UPDATE_COOLDOWN()
    for _,entry in pairs(spellCooldowns) do
        local getCooldownDetails = entry.getCooldownDetails or entry
        if getCooldownDetails and getCooldownDetails.resetCache then
            getCooldownDetails.resetCache()
        end
    end
end
DCP:RegisterEvent("SPELL_UPDATE_COOLDOWN")

-- FIX: UNIT_SPELLCAST_SUCCEEDED is a unit event in Midnight and must use
--      RegisterUnitEvent, or it will never fire.
--      Also handles pet spells here directly (removing need for COMBAT_LOG).
--      The 2nd arg is castGUID (not lineID) in Midnight; name doesn't matter.
function DCP:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if ((unit == "player" or unit == "pet") and spellID) then
        local isPet = (unit == "pet")
        local spellKey = GetSpellTrackingKey(spellID)
        -- Store spell in watching; v[4] = isPet flag so the pet overlay is applied.
        spellWatching[spellKey] = {GetTime(), "spell", spellID, isPet}

        if (not self:IsMouseEnabled()) then
            self:SetScript("OnUpdate", OnUpdate)
        end
    end
end
-- FIX: Use RegisterUnitEvent so the event actually fires in Midnight.
--      "pet" replaces the old COMBAT_LOG_EVENT_UNFILTERED pet detection.
DCP:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")

-- FIX: COMBAT_LOG_EVENT_UNFILTERED handler removed.
--      It relied on GetPetActionInfo / GetPetActionCooldown which are gone in
--      Midnight. Pet spells are now caught by UNIT_SPELLCAST_SUCCEEDED above.

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
-- FIX: WOW_PROJECT_MAINLINE constant may not match Midnight's project ID.
--      Just always register; it's harmless on other versions too.
DCP:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

hooksecurefunc("UseAction", function(slot)
    local actionType, itemID = GetActionInfo(slot)
    if (actionType == "item" and itemID) then
        -- Midnight-safe: track by itemID/slot and include paired trinket lockout.
        WatchItemAndSharedTrinket(itemID)
    end
end)

-- FIX: UseInventoryItem was removed in Midnight. Guard the hook so it doesn't
--      throw a Lua error at load time when the global doesn't exist.
if UseInventoryItem then
    hooksecurefunc("UseInventoryItem", function(slot)
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            WatchItemAndSharedTrinket(itemID, slot)
        end
    end)
end

-- FIX: Guard UseContainerItem in case it was renamed/moved in Midnight.
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

SlashCmdList["DOOMCOOLDOWNPULSE"] = function() if (not DCP_OptionsFrame) then DCP:CreateOptionsFrame() end DCP_OptionsFrame:Show() end
SLASH_DOOMCOOLDOWNPULSE1 = "/dcp"
SLASH_DOOMCOOLDOWNPULSE2 = "/cooldownpulse"
SLASH_DOOMCOOLDOWNPULSE3 = "/doomcooldownpulse"

function DCP:CreateOptionsFrame()
    local sliders = {
        { text = "Icon Size", value = "iconSize", min = 30, max = 125, step = 5 },
        { text = "Fade In Time", value = "fadeInTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Fade Out Time", value = "fadeOutTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Max Opacity", value = "maxAlpha", min = 0, max = 1, step = 0.1 },
        { text = "Max Opacity Hold Time", value = "holdTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Animation Scaling", value = "animScale", min = 0, max = 2, step = 0.1 },
        { text = "Show Before Available Time", value = "remainingCooldownWhenNotified", min = 0, max = 3, step = 0.1 },
    }

    local buttons = {
        { text = "Close", func = function(self) self:GetParent():Hide() end },
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
    optionsframe:SetHeight(610)
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
    headertext:SetText("Doom_CooldownPulse")

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
            DCP_Saved[v.value] = value
            RefreshLocals()
            valuetext:SetText(format("%.1f", value))
            if (DCP:IsMouseEnabled()) then
                DCP:SetWidth(DCP_Saved.iconSize)
                DCP:SetHeight(DCP_Saved.iconSize)
            end
        end)
    end

    local pettext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    pettext:SetPoint("TOPLEFT","DCP_OptionsFrameSlider"..#sliders,"BOTTOMLEFT",-15,-30)
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
    petcolorselectbg:SetTexture(1,1,1)
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
    ignorebox:SetPoint("TOPLEFT",ignoretypebuttonblacklist,"BOTTOMLEFT",4,2)
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
end
