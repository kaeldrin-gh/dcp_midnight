-- Behavioral tests against a small modern WoW API mock. Run with Lua 5.1:
-- lua tests/test_cooldowns.lua [path/to/Doom_CooldownPulse_Forever.lua]
local addonPath = (arg and arg[1]) or "Doom_CooldownPulse_Forever.lua"
local addon = assert(loadfile(addonPath))
local editorPath = addonPath:match("^(.*[/\\])") or ""
local editor = assert(loadfile(editorPath .. "FilterEditor.lua"))
local passed = 0

local function setup(settings, characterSettings, nativeSettings)
    local env = setmetatable({}, {__index = _G})
    env._G = env
    local state = {now = 100, frames = {}, spells = {}, items = {}, slots = {}, hooks = {}, pulses = {}, spellNames = {}, messages = {}, spellIcons = {}, itemIcons = {}, itemNames = {}, itemSpells = {}, bags = {}, knownSpells = {}, itemIDsByName = {}}
    env.DCP_Saved = settings
    env.DCP_SavedPerCharacter = characterSettings
    local methods = {}
    local mt = {__index = function(_, key) return methods[key] or function() end end}
    local function frame(name)
        local f = setmetatable({scripts = {}, events = {}, mouse = false}, mt)
        if name then env[name] = f end
        return f
    end
    function methods:SetScript(key, value) self.scripts[key] = value end
    function methods:GetScript(key) return self.scripts[key] end
    function methods:HasFocus() return rawget(self, "focused") == true end
    function methods:SetFocus() self.focused = true end
    function methods:ClearFocus()
        local focused = self:HasFocus()
        self.focused = false
        if focused and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
    end
    function methods:SetParent(parent) self.parent = parent end
    function methods:GetParent() return rawget(self, "parent") end
    function methods:SetPoint(...) self.point = {...} end
    function methods:ClearAllPoints() self.point = nil end
    function methods:SetFrameStrata(strata) self.strata = strata end
    function methods:GetFrameStrata() return rawget(self, "strata") or "MEDIUM" end
    function methods:SetMovable(value) self.movable = value end
    function methods:SetScrollChild(child) self.scrollChild = child end
    function methods:IsShown() return rawget(self, "shown") == true end
    function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function methods:SetEnabled(value) self.enabled=value end
    function methods:Show()
        if self:IsShown() then return end
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:Hide()
        local wasShown = self:IsShown()
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:RegisterUnitEvent(event, ...) self.events[event] = {...} end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:GetWidth() return 1920 end
    function methods:GetHeight() return 1080 end
    function methods:GetEffectiveScale() return 1 end
    function methods:SetAlpha(value) self.alpha = value end
    function methods:IsMouseEnabled() return self.mouse end
    function methods:EnableMouse(value) self.mouse = value end
    function methods:CreateFontString()
        local region = frame()
        if not rawget(self, "fontStrings") then self.fontStrings = {} end
        table.insert(self.fontStrings, region)
        return region
    end
    function methods:CreateTexture()
        local texture = frame()
        if self == state.frames[1] then state.icon = texture end
        return texture
    end
    function methods:SetChecked(value) self.checked = value end
    function methods:GetChecked() return rawget(self, "checked") end
    function methods:SetText(value) self.text = value end
    function methods:GetText() return rawget(self, "text") end
    function methods:SetValue(value)
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function methods:GetValue() return self.value end
    function methods:SetNormalTexture(value)
        self.normalTexture = frame()
        self.normalTexture:SetTexture(value)
    end
    function methods:GetNormalTexture() return self.normalTexture end
    function methods:SetTexture(value)
        self.texture = value
        if self == state.icon and value then table.insert(state.pulses, value) end
    end
    function methods:GetTexture() return rawget(self, "texture") end
    env.UIParent = frame()
    env.CreateFrame = function(kind, name, parent, template)
        local f = frame(name)
        f.kind, f.parent = kind, parent
        if name and template == "OptionsSliderTemplate" then
            for _, suffix in ipairs({"Text", "Low", "High"}) do frame(name .. suffix) end
        end
        table.insert(state.frames, f)
        return f
    end
    env.getglobal = function(name) return env[name] end
    env.ceil = math.ceil
    env.PlaySound = function() end
    env.print = function(message) table.insert(state.messages, message) end
    state.cursorCleared=0
    state.missingSpells={}
    state.spellDataRequests={}
    env.GetCursorInfo=function() return unpack(state.cursor or {}) end
    env.ClearCursor=function() state.cursor=nil state.cursorCleared=state.cursorCleared+1 end
    env.GameTooltip={
        SetOwner=function() end,SetText=function() end,AddLine=function() end,Show=function() end,Hide=function() end,
        SetSpellByID=function(_,id) state.tooltipSpell=id end,
        SetItemByID=function(_,id) state.tooltipItem=id end,
    }
    state.bookSlots={}
    env.GetTime = function() return state.now end
    env.STANDARD_TEXT_FONT = "font"
    env.tinsert, env.tremove, env.format = table.insert, table.remove, string.format
    env.wipe = function(t) for key in pairs(t) do t[key] = nil end end
    env.strtrim = function(s) return s:match('^%s*(.-)%s*$') end
    env.strsplit = function(_, s)
        local parts = {}
        for part in (s .. ','):gmatch('(.-),') do table.insert(parts, part) end
        return unpack(parts)
    end
    env.SlashCmdList, env.UISpecialFrames = {}, {}
    env.IsInInstance = function() return false, "none" end
    env.Enum = {SpellBookSpellBank = {Player = 0, Pet = 1}}
    env.issecretvalue = function(value) return type(value) == "table" and rawget(value, "secret") == true end
    local function numericCooldown(data)
        if data and (env.issecretvalue(data.startTime) or env.issecretvalue(data.duration)) then return data end
        if data and state.now < data.startTime + data.duration then return data end
        return {startTime = 0, duration = 0, isActive = false, isEnabled = true}
    end
    env.C_Spell = {
        RequestLoadSpellData = function(id) state.spellDataRequests[id]=(state.spellDataRequests[id] or 0)+1 end,
        GetSpellInfo = function(id)
            if state.missingSpells[id] then return nil end
            if type(id)=="string" then
                for number,name in pairs(state.spellNames) do if name==id then return {name=name,iconID=state.spellIcons[number] or number,spellID=number} end end
                return nil
            end
            return {name=state.spellNames[id] or "Spell "..id,iconID=state.spellIcons[id] or id,spellID=id}
        end,
        GetSpellCooldown = function(id)
            local data = state.spells[id]
            if type(data) == "function" then return data() end
            return numericCooldown(data)
        end,
    }
    env.C_SpellBook = {
        IsSpellKnown = function(id, bank) assert(bank == 0) return state.knownSpells[id] == true end,
        HasPetSpells = function() return state.petID and 1 or 0 end,
        GetSpellBookItemInfo = function(slot, bank)
            if bank==0 then return state.bookSlots[slot] end
            assert(slot == 1 and bank == 1)
            return {spellID = state.petID}
        end,
        GetSpellBookItemCooldown = function(slot, bank)
            assert(slot == 1 and bank == 1)
            state.petQueries = (state.petQueries or 0) + 1
            if type(state.petCooldown) == "function" then return state.petCooldown() end
            return numericCooldown(state.petCooldown)
        end,
    }
    local function itemCooldown(id)
        local d = numericCooldown(state.items[id])
        return d.startTime, d.duration, d.isEnabled
    end
    env.C_Item = {
        GetItemCooldown = itemCooldown,
        GetItemNameByID = function(id) return state.itemNames[id] or "Item " .. id end,
        GetItemIconByID = function(id) return state.itemIcons[id] or id end,
        GetItemSpell = function(id)
            if state.itemSpells[id] == false then return nil end
            return "Item spell " .. id, state.itemSpells[id] or id + 1000
        end,
        UseItemByName = function() end,
        GetItemInfoInstant = function(info)
            if type(info) == "number" then return info end
            return state.itemIDsByName[info]
        end,
    }
    env.NUM_BAG_SLOTS = 4
    env.C_Container = {
        UseContainerItem = function() end,
        GetContainerNumSlots = function(bag) return #(state.bags[bag] or {}) end,
        GetContainerItemID = function(bag, slot) return (state.bags[bag] or {})[slot] end,
    }
    env.GetInventoryItemID = function(_, slot) return state.slots[slot] end
    env.GetInventoryItemTexture = env.GetInventoryItemID
    env.GetInventoryItemCooldown = function(_, slot) return itemCooldown(state.slots[slot]) end
    env.UseInventoryItem = function() end
    env.hooksecurefunc = function(target, method, callback)
        if type(target) == "table" then state.hooks[method] = callback
        else state.hooks[target] = method end
    end
    env.GetActionInfo = function() return "item", state.actionItem end
    function state:installSettings()
        self.settingsPanel = frame()
        env.SettingsPanel = self.settingsPanel
        env.HideUIPanel = function(panel) panel:Hide() end
        self.settingsPanel:SetScript("OnHide", function()
            if self.settingsCanvas then self.settingsCanvas:Hide() end
        end)
        env.ColorPickerFrame = {
            SetupColorPickerAndShow = function(_, options) self.pickerOptions = options end,
            GetColorRGB = function() return unpack(self.pickerColor or {1,1,1}) end,
        }
        env.Settings = {
            RegisterCanvasLayoutCategory = function(panel, name)
                self.settingsRegistrations = (self.settingsRegistrations or 0) + 1
                self.settingsCanvas, self.settingsName = panel, name
                return {GetID = function() return 9001 end}
            end,
            RegisterAddOnCategory = function(category)
                assert(category:GetID() == 9001)
                self.settingsRegistered = true
            end,
            OpenToCategory = function(id)
                assert(id == 9001)
                self.settingsOpenedID = id
                self.settingsPanel:Show()
                self.settingsCanvas:Show()
            end,
        }
    end
    if nativeSettings then state:installSettings() end
    local private = {}
    setfenv(addon, env)("Doom_CooldownPulse_Forever", private)
    setfenv(editor, env)("Doom_CooldownPulse_Forever", private)
    state.private = private
    state.dcp = state.frames[1]
    function state:event(event, ...)
        assert(self.dcp.events[event], "event not registered: " .. event)
        self.dcp.scripts.OnEvent(self.dcp, event, ...)
    end
    function state:tick(seconds)
        for _ = 1, math.floor(seconds * 20 + 0.5) do
            self.now = self.now + 0.05
            local update = self.dcp.scripts.OnUpdate
            if update then update(self.dcp, 0.05) end
        end
    end
    function state:cast(id, unit)
        self:event("UNIT_SPELLCAST_SUCCEEDED", unit or "player", "cast-guid", id)
    end
    state:event("ADDON_LOADED", "SomeOtherAddon")
    assert(env.DCP_Saved == settings, "initialized on a different addon's event")
    state:event("ADDON_LOADED", "Doom_CooldownPulse_Forever")
    function state:options() env.SlashCmdList.DOOMCOOLDOWNPULSE() end
    function state:settings() env.Settings.OpenToCategory(9001) end
    function state:command(message) env.SlashCmdList.DOOMCOOLDOWNPULSE(message) end
    function state:setPetPulses(enabled)
        if not env.DCP_OptionsFrame then self:options() end
        local checkbox = env.DCP_OptionsFramePetPulsesCheckButton
        checkbox:SetChecked(enabled)
        checkbox.scripts.OnClick(checkbox)
    end
    state.env = env
    return state
end

local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

local function cooldown(duration, enabled)
    return {startTime = 100, duration = duration, isActive = true, isEnabled = enabled ~= false}
end

test("player cooldown pulses once", function()
    local s = setup()
    s.spells[1] = cooldown(5)
    s:cast(1); s:tick(4)
    assert(#s.pulses == 0)
    s:tick(3)
    assert(#s.pulses == 1 and s.pulses[1] == 1)
end)

test("numeric cooldown supports early notification", function()
    local s = setup({remainingCooldownWhenNotified = 1})
    s.spells[2] = cooldown(5)
    s:cast(2); s:tick(4.3)
    assert(#s.pulses == 1)
end)

test("GCD does not pulse and stops polling", function()
    local s = setup()
    s.spells[3] = cooldown(1.5)
    s:cast(3); s:tick(4)
    assert(#s.pulses == 0 and s.dcp.scripts.OnUpdate == nil)
end)

test("permanent short cooldown expires from watch list", function()
    local s = setup()
    s.spells[4] = function() return cooldown(1.5) end
    s:cast(4); s:tick(4)
    assert(#s.pulses == 0 and s.dcp.scripts.OnUpdate == nil)
end)

test("ignore list accepts spell ID", function()
    local s = setup(nil, {ignoredSpells = "5", invertIgnored = false})
    s.spells[5] = cooldown(5)
    s:cast(5); s:tick(7)
    assert(#s.pulses == 0)
end)

test("whitelist accepts spell name", function()
    local s = setup(nil, {ignoredSpells = "Spell 6", invertIgnored = true})
    s.spells[6], s.spells[7] = cooldown(5), cooldown(5)
    s:cast(6); s:cast(7); s:tick(7)
    assert(#s.pulses == 1 and s.pulses[1] == 6)
end)

local secret = setmetatable({secret = true}, {
    __add = function() error("secret arithmetic") end,
    __lt = function() error("secret comparison") end,
    __tostring = function() error("secret string conversion") end,
})

test("restricted cooldown uses readable state flags", function()
    local s = setup({remainingCooldownWhenNotified = 2})
    s.spells[8] = function()
        return {startTime = secret, duration = secret, isActive = s.now < 105, isEnabled = true}
    end
    s:cast(8); s:tick(4)
    assert(#s.pulses == 0, "restricted timer must not notify early")
    s:tick(3)
    assert(#s.pulses == 1)
end)

test("restricted GCD becoming numeric does not pulse", function()
    local s = setup()
    s.spells[9] = function()
        if s.now < 101.5 then
            return {startTime = secret, duration = secret, isActive = true, isEnabled = true}
        end
        return {startTime = 0, duration = 0, isActive = false, isEnabled = true}
    end
    s:cast(9); s:tick(4)
    assert(#s.pulses == 0)
end)

test("secret cast payload is ignored safely", function()
    local s = setup()
    s:cast(secret); s:cast(1, secret); s:tick(1)
    assert(#s.pulses == 0)
end)

test("pet spell uses pet bank and overlay", function()
    local s = setup()
    s.petID, s.petCooldown = 10, cooldown(5)
    s:cast(10, "pet"); s:tick(7)
    assert(s.petQueries > 0 and #s.pulses == 1 and s.pulses[1] == 10)
end)

test("trinket cast from macro routes to item tracking", function()
    local s = setup()
    s.slots[13], s.items[20] = 20, cooldown(5)
    s:cast(1020); s:tick(7)
    assert(#s.pulses == 1 and s.pulses[1] == 20)
end)

test("shared trinket does not replace longer cooldown", function()
    local s = setup()
    s.slots[13], s.slots[14] = 20, 21
    s.items[20], s.items[21] = cooldown(40), cooldown(20)
    s:cast(1020); s:tick(1)
    -- API begins reporting the shorter shared lockout for the used trinket.
    s.items[20] = cooldown(20)
    s:tick(21)
    assert(#s.pulses == 1 and s.pulses[1] == 21)
    s:tick(20)
    assert(#s.pulses == 2 and s.pulses[2] == 20)
end)

test("ordinary bag item on action bar", function()
    local s = setup()
    s.actionItem, s.items[22] = 22, cooldown(5)
    s.hooks.UseAction(1); s:tick(7)
    assert(#s.pulses == 1 and s.pulses[1] == 22)
end)

test("on-hold cooldown does not pulse before activation", function()
    local s = setup()
    s.spells[11] = function()
        if s.now < 110 then return cooldown(5, false) end
        return {startTime = 110, duration = 5, isEnabled = true, isActive = s.now < 115}
    end
    s:cast(11); s:tick(9)
    assert(#s.pulses == 0)
    s:tick(8)
    assert(#s.pulses == 1)
end)

test("talent change clears watched cooldowns", function()
    local s = setup()
    s.spells[12] = cooldown(5)
    s:cast(12); s:tick(1)
    s:event("PLAYER_SPECIALIZATION_CHANGED", "player"); s:tick(6)
    assert(#s.pulses == 0)
end)

test("readable reset pulses while only the GCD remains", function()
    local s = setup()
    s.spells[40] = cooldown(30)
    s.spells[40].isOnGCD = false
    s:cast(40); s:event("SPELL_UPDATE_COOLDOWN"); s:tick(10)
    s.spells[40] = {startTime = s.now, duration = 1.5, isActive = true, isEnabled = true, isOnGCD = true}
    s:event("SPELL_UPDATE_COOLDOWN"); s:tick(0.15)
    assert(#s.pulses == 1 and s.pulses[1] == 40, "waited for the GCD")
    s:tick(3); assert(#s.pulses == 1, "duplicate completion pulse")
end)

test("restricted reset pulses while only the GCD remains", function()
    local s = setup()
    s.spells[41] = {startTime = secret, duration = secret, isActive = true, isEnabled = true, isOnGCD = false}
    s:cast(41); s:event("SPELL_UPDATE_COOLDOWN"); s:tick(10)
    s.spells[41].isOnGCD = true
    s:event("SPELL_UPDATE_COOLDOWN"); s:tick(0.15)
    assert(#s.pulses == 1 and s.pulses[1] == 41)
end)

test("a real cooldown still active during GCD does not pulse", function()
    local s = setup()
    s.spells[42] = {startTime = secret, duration = secret, isActive = true, isEnabled = true, isOnGCD = false}
    s:cast(42); s:event("SPELL_UPDATE_COOLDOWN"); s:tick(10)
    s:event("SPELL_UPDATE_COOLDOWN"); s:tick(0.2)
    assert(#s.pulses == 0)
end)

test("GCD flags outside the update event are ignored", function()
    local s = setup()
    s.spells[43] = {startTime = secret, duration = secret, isActive = true, isEnabled = true, isOnGCD = false}
    s:cast(43); s:event("SPELL_UPDATE_COOLDOWN"); s:tick(10)
    s.spells[43].isOnGCD = true
    s:tick(0.2)
    assert(#s.pulses == 0)
end)

test("known restricted GCD-only casts never enter real cooldown tracking", function()
    local s = setup()
    s.spells[44] = {startTime = secret, duration = secret, isActive = true, isEnabled = true, isOnGCD = true}
    s:cast(44); s:event("SPELL_UPDATE_COOLDOWN"); s:tick(0.7)
    s.spells[44].isActive, s.spells[44].isOnGCD = false, nil
    s:event("SPELL_UPDATE_COOLDOWN"); s:tick(3)
    assert(#s.pulses == 0 and s.dcp.scripts.OnUpdate == nil)
end)

test("missing GCD flag retains restricted completion fallback", function()
    local s = setup()
    s.spells[45] = {startTime = secret, duration = secret, isActive = true, isEnabled = true, isOnGCD = false}
    s:cast(45); s:event("SPELL_UPDATE_COOLDOWN"); s:tick(5)
    s.spells[45].isActive, s.spells[45].isOnGCD = false, nil
    s:event("SPELL_UPDATE_COOLDOWN"); s:tick(0.15)
    assert(#s.pulses == 1)
end)

test("pet GCD events query the Forever Pet spell bank", function()
    local s = setup()
    s.petID, s.petCooldown = 46, cooldown(30)
    s.petCooldown.isOnGCD = false
    s.spells[46] = cooldown(90) -- Player API must not control this pet's state.
    s:cast(46, "pet"); s:event("SPELL_UPDATE_COOLDOWN"); s:tick(5)
    s.petCooldown = {startTime = s.now, duration = 1.5, isActive = true, isEnabled = true, isOnGCD = true}
    s:event("SPELL_UPDATE_COOLDOWN"); s:tick(0.15)
    assert(#s.pulses == 1 and s.pulses[1] == 46 and s.petQueries > 0)
end)

test("held cooldown cannot complete from a GCD flag", function()
    local s = setup()
    s.spells[47] = function() return {startTime = 100, duration = 30, isActive = false, isEnabled = false, isOnGCD = true} end
    s:cast(47); s:tick(5) -- No reliable GCD event yet; tracks the held timer.
    s:event("SPELL_UPDATE_COOLDOWN"); s:tick(0.15)
    assert(#s.pulses == 0)
end)

test("pet preference migrates existing settings and retains a saved false", function()
    local old = {ignoredSpells = "", invertIgnored = false}
    local s = setup(nil, old)
    assert(s.env.DCP_SavedPerCharacter.showPetCooldowns == true)
    s:setPetPulses(false)
    local reloaded = setup(s.env.DCP_Saved, old)
    reloaded:options()
    assert(old.showPetCooldowns == false)
    assert(not reloaded.env.DCP_OptionsFramePetPulsesCheckButton:GetChecked())
end)

test("disabling pet pulses removes watches before enrollment", function()
    local s = setup()
    s.petID, s.petCooldown = 50, cooldown(10)
    s:cast(50, "pet"); s:tick(0.2); s:setPetPulses(false); s:tick(12)
    assert(not s.petQueries and #s.pulses == 0)
end)

test("disabling pet pulses removes tracked pet cooldowns immediately", function()
    local s = setup()
    s.petID, s.petCooldown = 51, cooldown(10)
    s:cast(51, "pet"); s:tick(1)
    local queries = s.petQueries
    assert(queries > 0)
    s:setPetPulses(false); s:tick(12)
    assert(s.petQueries == queries and #s.pulses == 0)
end)

test("hiding an active pet pulse preserves player and item work", function()
    local s = setup()
    s.petID, s.petCooldown = 52, cooldown(3)
    s.spells[53], s.items[54], s.actionItem = cooldown(3.5), cooldown(4), 54
    s:cast(52, "pet"); s:cast(53); s.hooks.UseAction(1); s:tick(3.1)
    assert(s.icon:GetTexture() == 52, "pet should be currently displayed")
    s:setPetPulses(false)
    assert(s.icon:GetTexture() == nil, "active pet pulse was not cleared")
    s:tick(5)
    assert(#s.pulses == 3 and s.pulses[2] == 53 and s.pulses[3] == 54)
end)

test("hiding pet pulses removes a pet queued behind a player", function()
    local s = setup({holdTime = 2})
    s.spells[55] = cooldown(3)
    s.petID, s.petCooldown = 56, cooldown(3.2)
    s:cast(55); s:cast(56, "pet"); s:tick(3.4)
    assert(s.icon:GetTexture() == 55)
    s:setPetPulses(false); s:tick(5)
    assert(#s.pulses == 1 and s.pulses[1] == 55)
end)

test("disabled repeated pet casts do not crowd out player completion", function()
    local s = setup(nil, {ignoredSpells = "", invertIgnored = false, showPetCooldowns = false})
    s.petID, s.petCooldown, s.spells[58] = 57, cooldown(3), cooldown(5)
    s:cast(58)
    for _ = 1, 70 do s:cast(57, "pet"); s:tick(0.1) end
    assert(not s.petQueries and #s.pulses == 1 and s.pulses[1] == 58)
end)

test("rechecking pet pulses enables subsequent casts", function()
    local s = setup(nil, {ignoredSpells = "", invertIgnored = false, showPetCooldowns = false})
    s.petID, s.petCooldown = 59, cooldown(5)
    s:cast(59, "pet"); s:tick(1); s:setPetPulses(true)
    s.petCooldown = {startTime = s.now, duration = 5, isEnabled = true, isActive = true}
    s:cast(59, "pet"); s:tick(7)
    assert(#s.pulses == 1 and s.pulses[1] == 59)
end)

test("Defaults restores checkbox and pet pulse behavior", function()
    local s = setup(nil, {ignoredSpells = "", invertIgnored = false, showPetCooldowns = false})
    s:options()
    local button = s.env.DCP_OptionsFrameButton4
    button.scripts.OnClick(button)
    assert(s.env.DCP_SavedPerCharacter.showPetCooldowns == true)
    assert(s.env.DCP_OptionsFramePetPulsesCheckButton:GetChecked())
    s.petID, s.petCooldown = 60, cooldown(5)
    s:cast(60, "pet"); s:tick(7)
    assert(#s.pulses == 1 and s.pulses[1] == 60)
end)


test("explicit DNT developer spell names do not flash", function()
    for _, name in ipairs({"[DNT] Internal Check", "(DNT) Engine Check", "  [dnt] Internal Check"}) do
        local s = setup()
        s.spellNames[70], s.spells[70] = name, cooldown(5)
        s:cast(70); s:tick(7)
        assert(#s.pulses == 0, "internal spell was shown: " .. name)
        s:command("last")
        assert(#s.messages == 1 and s.messages[1]:find("No cooldown pulses", 1, true))
    end
end)

test("DNT identification after the cast is still filtered before enrollment", function()
    local s = setup()
    s.spells[71] = cooldown(5)
    s:cast(71); s:tick(0.2)
    s.spellNames[71] = "[DNT] Late Metadata"
    s:tick(7)
    assert(#s.pulses == 0)
end)

test("ordinary names containing developer-like text are preserved", function()
    for _, name in ipairs({"DNT Strike", "Strike [DNT]", "Unknown Emblem Ability"}) do
        local s = setup()
        s.spellNames[72], s.spells[72] = name, cooldown(5)
        s:cast(72); s:tick(7)
        assert(#s.pulses == 1 and s.pulses[1] == 72)
    end
end)

test("history identifies the displayed unknown spell by name and ID", function()
    local s = setup()
    s.spellNames[73], s.spells[73] = "Unknown Emblem Ability", cooldown(5)
    s:cast(73); s:tick(4); s:command("last")
    assert(#s.messages == 1 and s.messages[1]:find("No cooldown pulses", 1, true))
    s.messages = {}
    s:tick(2); s:command("  LAST  ")
    assert(#s.messages == 2)
    assert(s.messages[2]:find("Unknown Emblem Ability | spell ID 73", 1, true))
    assert(s.env.DCP_OptionsFrame == nil, "history opened options")
end)

test("history distinguishes pet and item identifiers", function()
    local s = setup()
    s.petID, s.petCooldown = 74, cooldown(3)
    s.actionItem, s.items[75] = 75, cooldown(5)
    s:cast(74, "pet"); s.hooks.UseAction(1); s:tick(8); s:command("last")
    assert(#s.messages == 3)
    assert(s.messages[2]:find("Item 75 | item ID 75", 1, true))
    assert(s.messages[3]:find("Spell 74 | pet spell ID 74", 1, true))
end)

test("history contains visible pulses rather than pending queue entries", function()
    local s = setup({holdTime = 3})
    s.spells[76], s.spells[77] = cooldown(3), cooldown(3.2)
    s:cast(76); s:cast(77); s:tick(3.4); s:command("last")
    assert(#s.messages == 2 and s.messages[2]:find("spell ID 76", 1, true))
    s.messages = {}
    s:tick(5); s:command("last")
    assert(#s.messages == 3 and s.messages[2]:find("spell ID 77", 1, true))
end)

test("history stays bounded and displays newest first", function()
    local s = setup()
    for id = 80, 91 do
        s.spells[id] = {startTime = s.now, duration = 3, isEnabled = true, isActive = true}
        s:cast(id); s:tick(5)
    end
    s:command("last")
    assert(#s.messages == 11, "history should contain ten entries plus its header")
    assert(s.messages[2]:find("spell ID 91", 1, true))
    assert(s.messages[11]:find("spell ID 82", 1, true))
end)

test("clearing history preserves ongoing cooldown tracking", function()
    local s = setup()
    s.spells[92], s.spells[93] = cooldown(3), cooldown(10)
    s:cast(92); s:cast(93); s:tick(5); s:command("last clear")
    s.messages = {}
    s:command("last")
    assert(#s.messages == 1 and s.messages[1]:find("No cooldown pulses", 1, true))
    s.messages = {}
    s:tick(7); s:command("last")
    assert(#s.messages == 2 and s.messages[2]:find("spell ID 93", 1, true))
end)

test("options Test preview does not populate cooldown history", function()
    local s = setup()
    s:options()
    local button = s.env.DCP_OptionsFrameButton2
    button.scripts.OnClick(button)
    s:tick(1.5); s:command("last")
    assert(#s.messages == 1 and s.messages[1]:find("No cooldown pulses", 1, true))
end)

test("filtered spells cannot be forced through with a whitelist", function()
    local s = setup(nil, {ignoredSpells = "94", invertIgnored = true})
    s.spellNames[94], s.spells[94] = "[DNT] Whitelisted Internal Check", cooldown(5)
    s:cast(94); s:tick(7)
    assert(#s.pulses == 0)
end)

test("suppressed pet spells do not appear in pulse history", function()
    local s = setup(nil, {ignoredSpells = "", invertIgnored = false, showPetCooldowns = false})
    s.petID, s.petCooldown = 95, cooldown(5)
    s:cast(95, "pet"); s:tick(7); s:command("last")
    assert(#s.messages == 1 and s.messages[1]:find("No cooldown pulses", 1, true))
end)

test("restricted cast IDs are not converted into diagnostic text", function()
    local s = setup()
    s:cast(secret); s:tick(7); s:command("last")
    assert(#s.messages == 1 and s.messages[1]:find("No cooldown pulses", 1, true))
end)


test("Settings launcher registers once without opening the floating window", function()
    local s = setup(nil, nil, true)
    assert(s.settingsRegistrations == 1 and s.settingsRegistered)
    assert(s.env.DCP_OptionsFrame == nil and not s.settingsPanel:IsShown())
    assert(s.env.DCP_ForeverSettingsOpenOptions:GetText() == "Open /dcp options")
    s.dcp:PLAYER_LOGIN()
    assert(s.settingsRegistrations == 1)
end)

test("dcp keeps its independent floating screen", function()
    local s = setup(nil, nil, true)
    s:options()
    local options = s.env.DCP_OptionsFrame
    assert(options:IsShown() and options:GetParent() == s.env.UIParent and options.movable)
    assert(not s.settingsOpenedID)
    assert(s.env.SLASH_DOOMCOOLDOWNPULSE2 == "/cooldownpulse" and s.env.SLASH_DOOMCOOLDOWNPULSE3 == "/doomcooldownpulse")
end)

test("Settings contains only the launcher and does not create duplicate controls", function()
    local s = setup(nil, nil, true)
    s:settings()
    assert(s.settingsPanel:IsShown() and s.env.DCP_OptionsFrame == nil)
    assert(s.env.DCP_ForeverSettingsSlider1 == nil and s.env.DCP_ForeverSettingsAction2 == nil)
    local button = s.env.DCP_ForeverSettingsOpenOptions
    assert(button:GetParent() == s.settingsCanvas)
    s.settingsPanel:Hide(); s:settings()
    assert(s.env.DCP_ForeverSettingsOpenOptions == button)
end)

test("big Settings button closes Settings and opens the floating options", function()
    local s = setup(nil, nil, true)
    s:settings()
    local button = s.env.DCP_ForeverSettingsOpenOptions
    button.scripts.OnClick(button)
    assert(not s.settingsPanel:IsShown())
    assert(s.env.DCP_OptionsFrame:IsShown() and s.env.DCP_OptionsFrame:GetParent() == s.env.UIParent)
end)

test("launcher reuses the floating window and preserves preferences", function()
    local s = setup(nil, nil, true)
    s:options()
    local options = s.env.DCP_OptionsFrame
    s:setPetPulses(false)
    s:settings(); s.env.DCP_ForeverSettingsOpenOptions.scripts.OnClick()
    assert(s.env.DCP_OptionsFrame == options and options:GetParent() == s.env.UIParent)
    assert(not s.env.DCP_OptionsFramePetPulsesCheckButton:GetChecked())
    local close = s.env.DCP_OptionsFrameButton1
    close.scripts.OnClick(close)
    assert(not options:IsShown())
end)

test("floating Unlock locks and hides the icon on its second click", function()
    local s = setup(nil, nil, true)
    s:options()
    local button = s.env.DCP_OptionsFrameButton3
    button.scripts.OnClick(button)
    assert(s.dcp:IsMouseEnabled() and s.dcp.alpha == 1 and button:GetText() == "Lock")
    button.scripts.OnClick(button)
    assert(not s.dcp:IsMouseEnabled() and s.dcp.alpha == 0 and button:GetText() == "Unlock")
    button.scripts.OnClick(button)
    assert(s.dcp:IsMouseEnabled() and s.dcp.alpha == 1)
end)

test("history and delayed Settings registration leave dcp standalone", function()
    local s = setup()
    s:installSettings(); s:event("PLAYER_LOGIN")
    s:command("last"); s:command("last clear")
    assert(s.settingsRegistrations == 1 and not s.settingsOpenedID)
    s:options()
    assert(s.env.DCP_OptionsFrame:IsShown() and not s.settingsOpenedID)
end)

test("reopening floating options refreshes slider values and labels", function()
    local s = setup(nil, nil, true)
    s:options()
    local options = s.env.DCP_OptionsFrame
    local slider = s.env.DCP_OptionsFrameSlider1
    options:Hide()
    s.env.DCP_Saved.iconSize = 95
    s:options()
    assert(slider:GetValue() == 95 and slider.fontStrings[1]:GetText() == "95.0")
end)

local function preparePotion(s, itemID, icon)
    itemID = itemID or 118
    s.itemSpells[itemID] = 439
    s.itemIcons[itemID] = icon or 500118
    s.itemNames[itemID] = "Minor Healing Potion"
    s.spellNames[439], s.spellIcons[439] = "Healing Potion", 999439
    s.spells[439], s.items[itemID] = cooldown(10), cooldown(30)
    s.bags[0] = {itemID}
    s:event("PLAYER_ENTERING_WORLD")
    return itemID
end

test("potion effect uses item texture and item cooldown instead of placeholder", function()
    local s = setup()
    preparePotion(s)
    s:cast(439); s:tick(12)
    assert(#s.pulses == 0, "used the potion effect's shorter timer")
    s:tick(20); s:command("last")
    assert(#s.pulses == 1 and s.pulses[1] == 500118, "displayed the spell placeholder")
    assert(#s.messages == 2 and s.messages[2]:find("Minor Healing Potion | item ID 118", 1, true))
end)

test("action item use and cast event produce one potion flash", function()
    local s = setup()
    preparePotion(s); s.actionItem = 118
    s.hooks.UseAction(1); s:cast(439); s:tick(32)
    assert(#s.pulses == 1 and s.pulses[1] == 500118)
end)

test("post-use hook replaces a spell watch created before inventory indexing", function()
    local s = setup()
    s.itemSpells[118], s.itemIcons[118] = 439, 500118
    s.items[118], s.spells[439], s.actionItem = cooldown(30), cooldown(10), 118
    s:cast(439); s:tick(0.7) -- Spell is already enrolled when the hook arrives.
    s.hooks.UseAction(1); s:tick(32)
    assert(#s.pulses == 1 and s.pulses[1] == 500118)
end)

test("last potion in a stack resolves after the bag update removes it", function()
    local s = setup()
    preparePotion(s)
    s.bags[0] = {}
    s:event("BAG_UPDATE_DELAYED")
    s:cast(439); s:tick(32)
    assert(#s.pulses == 1 and s.pulses[1] == 500118)
end)

test("bag use hook retains the last consumed slot identity", function()
    local s = setup()
    preparePotion(s)
    s.bags[0] = {}
    s.hooks.UseContainerItem(0, 1); s:cast(439); s:tick(32)
    assert(#s.pulses == 1 and s.pulses[1] == 500118)
end)

test("recently used potion variant wins over another carried item with same effect", function()
    local s = setup()
    preparePotion(s)
    s.itemSpells[119], s.itemIcons[119] = 439, 500119
    s.items[119], s.bags[0], s.actionItem = cooldown(30), {118,119}, 118
    s:event("BAG_UPDATE_DELAYED")
    s.hooks.UseAction(1)
    s.bags[0] = {119}; s:event("BAG_UPDATE_DELAYED")
    s:cast(439); s:tick(32)
    assert(#s.pulses == 1 and s.pulses[1] == 500118)
end)

test("carried item sharing a learned class ability does not steal the cast", function()
    local s = setup()
    preparePotion(s)
    s.knownSpells[439] = true
    s:cast(439); s:tick(12)
    assert(#s.pulses == 1 and s.pulses[1] == 999439)
end)

test("explicit use still routes an item even when its effect is a learned spell", function()
    local s = setup()
    preparePotion(s)
    s.knownSpells[439], s.actionItem = true, 118
    s.hooks.UseAction(1); s:cast(439); s:tick(32)
    assert(#s.pulses == 1 and s.pulses[1] == 500118)
end)

test("named item use routes consumables through item tracking", function()
    local s = setup()
    s.itemSpells[118], s.itemIcons[118], s.itemIDsByName["Minor Healing Potion"] = 439, 500118, 118
    s.items[118], s.spells[439] = cooldown(30), cooldown(10)
    s.hooks.UseItemByName("Minor Healing Potion"); s:cast(439); s:tick(32)
    assert(#s.pulses == 1 and s.pulses[1] == 500118)
end)

test("potion metadata arriving later refreshes the effect mapping", function()
    local s = setup()
    s.bags[0], s.itemSpells[118], s.itemIcons[118] = {118}, false, 500118
    s.items[118], s.spells[439] = cooldown(30), cooldown(10)
    s:event("PLAYER_ENTERING_WORLD")
    s.itemSpells[118] = 439
    s:event("GET_ITEM_INFO_RECEIVED", 118, true)
    s:cast(439); s:tick(32)
    assert(#s.pulses == 1 and s.pulses[1] == 500118)
end)

test("expired removed-item mappings cannot redirect unrelated later casts", function()
    local s = setup()
    preparePotion(s)
    s.bags[0] = {}; s:event("BAG_UPDATE_DELAYED"); s:tick(6)
    s.spells[439] = {startTime=s.now, duration=10, isActive=true, isEnabled=true}
    s:cast(439); s:tick(12)
    assert(#s.pulses == 1 and s.pulses[1] == 999439)
end)

test("potion blacklist applies to the real item ID", function()
    local s = setup(nil, {ignoredSpells="118", invertIgnored=false})
    preparePotion(s)
    s:cast(439); s:tick(32)
    assert(#s.pulses == 0)
end)


test("visual editor is lazy and preserves legacy text on opening", function()
    local original="Charge, 118, unknown old spell,spell:6343"
    local s=setup(nil,{ignoredSpells=original,invertIgnored=false})
    local editor=s.private.FilterEditor
    assert(editor.frame==nil)
    s:options()
    assert(editor.frame==nil and s.env.DCP_OptionsFrameEditFilters)
    s.env.DCP_OptionsFrameEditFilters.scripts.OnClick()
    assert(editor.frame:IsShown() and #editor.rows==7)
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells==original)
    assert(#editor:Entries()==4)
end)

test("spell drop uses the fourth cursor return, not the spellbook slot", function()
    local s=setup()
    local editor=s.private.FilterEditor
    s.cursor={"spell",7,0,6343}
    assert(editor:Drop())
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="spell:6343" and s.cursorCleared==1)
end)

test("bag item drop keeps its ID separate from the effect spell", function()
    local s=setup()
    s.cursor={"item",118,"item:118"}
    assert(s.private.FilterEditor:Drop())
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="item:118")
end)

test("spellbook fallback resolves a missing fourth cursor return", function()
    local s=setup()
    s.bookSlots[3]={spellID=7384,name="Overpower"}
    s.cursor={"spell",3,0}
    assert(s.private.FilterEditor:Drop())
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="spell:7384")
end)

test("unsupported and restricted cursor payloads do not change filters or cursor", function()
    local s=setup()
    local editor=s.private.FilterEditor
    for _, cursor in ipairs({{"macro",1},{"spell",4,0,secret},{secret,118},{"item",secret},{"item",0}}) do
        s.cursor=cursor
        assert(not editor:Drop())
    end
    assert(s.cursorCleared==0 and s.env.DCP_SavedPerCharacter.ignoredSpells=="")
end)

test("adding duplicates preserves spell-item distinctions and legacy coverage", function()
    local s=setup()
    local editor=s.private.FilterEditor
    assert(editor:Add("spell",118) and editor:Add("item",118) and editor:Add("spell",118))
    assert(#editor:Entries()==2)
    editor:ApplyText("118,Charge")
    s.spellNames[100]="Charge"
    editor:Add("item",118); editor:Add("spell",118); editor:Add("spell",100)
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="118,Charge")
end)

test("typed spell filters do not suppress items with the same numeric ID", function()
    local s=setup()
    s.private.FilterEditor:Add("spell",20)
    s.spells[20],s.items[20],s.actionItem=cooldown(5),cooldown(6),20
    s.itemIcons[20]=500020
    s:cast(20);s.hooks.UseAction(1);s:tick(8)
    assert(#s.pulses==1 and s.pulses[1]==500020)
end)

test("typed item filters do not suppress spells with the same numeric ID", function()
    local s=setup()
    s.private.FilterEditor:Add("item",20)
    s.spells[20],s.items[20],s.actionItem=cooldown(5),cooldown(6),20
    s:cast(20);s.hooks.UseAction(1);s:tick(8)
    assert(#s.pulses==1 and s.pulses[1]==20)
end)

test("removal preserves unresolved legacy entries and per-character mode", function()
    local s=setup(nil,{ignoredSpells="old unknown name,spell:100,item:118",invertIgnored=true})
    s.private.FilterEditor:Remove("spell:100")
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="old unknown name,item:118")
    assert(s.env.DCP_SavedPerCharacter.invertIgnored)
end)

test("adding a filter suppresses an already tracked cooldown immediately", function()
    local s=setup()
    s.spells[100]=cooldown(5)
    s:cast(100);s:tick(1)
    s.private.FilterEditor:Add("spell",100);s:tick(7)
    assert(#s.pulses==0)
end)

test("filtering an active animation clears that pulse", function()
    local s=setup()
    s.spells[100]=cooldown(5)
    s:cast(100);s:tick(5.2)
    assert(s.icon:GetTexture()==100)
    s.private.FilterEditor:Add("spell",100)
    assert(s.icon:GetTexture()==nil and s.dcp.alpha==0)
end)

test("editor and main options share blacklist and whitelist state", function()
    local s=setup()
    s:command("filters")
    local editor=s.private.FilterEditor
    editor:Add("spell",100)
    editor.whitelist.scripts.OnClick()
    s:options()
    assert(s.env.DCP_SavedPerCharacter.invertIgnored and s.env.DCP_OptionsFrameIgnoreTypeButtonWhitelist:GetChecked())
    s.env.DCP_OptionsFrameIgnoreTypeButtonBlacklist.scripts.OnClick()
    assert(not s.env.DCP_SavedPerCharacter.invertIgnored and editor.blacklist:GetChecked())
    assert(not editor.whitelist:GetChecked())
end)

test("recent flashes deduplicate and add real potion item IDs", function()
    local s=setup()
    preparePotion(s)
    s:cast(439);s:tick(32)
    s.spells[100]={startTime=s.now,duration=3,isActive=true,isEnabled=true}
    s:cast(100);s:tick(5)
    s.spells[100]={startTime=s.now,duration=3,isActive=true,isEnabled=true}
    s:cast(100);s:tick(5)
    s:command("filters")
    local editor=s.private.FilterEditor
    editor.recentTab.scripts.OnClick()
    assert(#editor:RecentEntries()==2)
    assert(editor.rows[1].entry.token=="spell:100" and editor.rows[2].entry.token=="item:118")
    assert(editor.rows[2].icon:GetTexture()==500118)
    editor.rows[2].action.scripts.OnClick()
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="item:118")
    assert(editor.rows[2].action:GetText()=="Added" and not editor.rows[2].action.enabled)
end)

test("pet recent flashes add spell IDs rather than item IDs", function()
    local s=setup()
    s.petID,s.petCooldown=10,cooldown(5)
    s:cast(10,"pet");s:tick(7)
    local editor=s.private.FilterEditor
    local entry=editor:RecentEntries()[1]
    assert(entry.token=="spell:10")
    editor:Add(entry.kind,entry.id)
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="spell:10")
end)

test("row pooling and paging keep large filter lists usable", function()
    local s=setup()
    local editor=s.private.FilterEditor
    local entries={}
    for i=1,20 do entries[i]="spell:"..i end
    editor:ApplyText(table.concat(entries,","));editor:Open()
    assert(#editor.rows==7 and editor.rows[1].entry.token=="spell:1")
    editor.next.scripts.OnClick()
    assert(editor.rows[1].entry.token=="spell:8")
    editor.next.scripts.OnClick()
    assert(editor.rows[7].entry.token=="spell:20" and not editor.next.enabled)
    editor.rows[1].action.scripts.OnClick()
    assert(#editor:Entries()==19)
    editor.previous.scripts.OnClick()
    assert(editor.offset>=0)
end)

test("advanced text round-trips names and typed IDs without changing mode", function()
    local s=setup()
    s:command("filters")
    local editor=s.private.FilterEditor
    editor.advancedButton.scripts.OnClick()
    assert(editor.raw:IsShown())
    editor.raw:SetText("Charge, SPELL:100, item:118, Charge, unknown name")
    editor.apply.scripts.OnClick()
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="Charge,spell:100,item:118,unknown name")
    assert(not s.env.DCP_SavedPerCharacter.invertIgnored)
end)

test("filter changes survive reload and Defaults refreshes an open editor", function()
    local s=setup()
    s:command("filters")
    s.private.FilterEditor:Add("spell",100)
    s.private.Filters.SetMode(true)
    local reloaded=setup(s.env.DCP_Saved,s.env.DCP_SavedPerCharacter)
    assert(reloaded.private.FilterEditor:Contains("spell",100) and reloaded.private.Filters.GetMode())
    s:options()
    local button=s.env.DCP_OptionsFrameButton4
    button.scripts.OnClick(button)
    assert(#s.private.FilterEditor:Entries()==0 and s.private.FilterEditor.blacklist:GetChecked())
end)

test("row tooltips show resolved spell and item details", function()
    local s=setup()
    s:command("filters")
    local editor=s.private.FilterEditor
    editor:Add("spell",100);editor:Add("item",118)
    editor.rows[1].scripts.OnEnter()
    assert(s.tooltipSpell==100)
    editor.rows[2].scripts.OnEnter()
    assert(s.tooltipItem==118)
end)


test("editor resolves pet abilities and rejects pet commands",function()
    local s=setup()
    s.petID=10
    s.cursor={"petaction",10}
    assert(s.private.FilterEditor:Drop())
    assert(s.env.DCP_SavedPerCharacter.ignoredSpells=="spell:10")
    s.cursor={"petaction",1}
    assert(not s.private.FilterEditor:Drop() and s.cursorCleared==1)
end)

test("editor rejects oversized IDs and preserves protected cursor values",function()
    local s=setup()
    local editor=s.private.FilterEditor
    assert(not editor:Add("spell",1e30))
    s.bookSlots[4]={spellID=100}
    s.cursor={"spell",4,0,secret}
    assert(not editor:Drop() and s.cursorCleared==0)
    editor:ApplyText("spell:99999999999999999999")
    editor:Open()
    assert(editor.rows[1].entry.detail=="Unresolved entry")
end)

test("click after a completed drop does not overwrite the success message",function()
    local s=setup()
    local editor=s.private.FilterEditor
    editor:Open()
    s.cursor={"spell",4,0,100}
    editor.drop.scripts.OnReceiveDrag()
    local message=editor.lastStatus
    editor.drop.scripts.OnClick()
    assert(editor.lastStatus==message and s.cursorCleared==1)
end)

test("missing spell data is requested once and its loaded name refreshes",function()
    local s=setup()
    local editor=s.private.FilterEditor
    s.missingSpells[999]=true
    editor:Add("spell",999);editor:Open();editor:Refresh()
    assert(s.spellDataRequests[999]==1)
    assert(editor.rows[1].entry.name=="spell 999")
    s.missingSpells[999]=false;s.spellNames[999]="Loaded spell"
    editor.frame.scripts.OnEvent(editor.frame,"SPELL_DATA_LOAD_RESULT",999,true)
    assert(editor.rows[1].entry.name=="Loaded spell")
end)

print(string.format("%d cooldown tests passed", passed))
