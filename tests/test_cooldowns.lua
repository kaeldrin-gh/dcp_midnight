-- Behavioral tests against a small modern WoW API mock. Run with Lua 5.1:
-- lua tests/test_cooldowns.lua [path/to/Doom_CooldownPulse_Forever.lua]
local addonPath = (arg and arg[1]) or "Doom_CooldownPulse_Forever.lua"
local addon = assert(loadfile(addonPath))
local passed = 0

local function setup(settings, characterSettings)
    local env = setmetatable({}, {__index = _G})
    env._G = env
    local state = {now = 100, frames = {}, spells = {}, items = {}, slots = {}, hooks = {}, pulses = {}}
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
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:RegisterUnitEvent(event, ...) self.events[event] = {...} end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:GetWidth() return 1920 end
    function methods:GetHeight() return 1080 end
    function methods:GetEffectiveScale() return 1 end
    function methods:IsMouseEnabled() return self.mouse end
    function methods:EnableMouse(value) self.mouse = value end
    function methods:CreateFontString() return frame() end
    function methods:CreateTexture() return frame() end
    function methods:SetTexture(value)
        self.texture = value
        if value then table.insert(state.pulses, value) end
    end
    function methods:GetTexture() return rawget(self, "texture") end
    env.UIParent = frame()
    env.CreateFrame = function(_, name)
        local f = frame(name)
        table.insert(state.frames, f)
        return f
    end
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
        if data and state.now < data.startTime + data.duration then return data end
        return {startTime = 0, duration = 0, isActive = false, isEnabled = true}
    end
    env.C_Spell = {
        GetSpellInfo = function(id) return {name = "Spell " .. id, iconID = id} end,
        GetSpellCooldown = function(id)
            local data = state.spells[id]
            if type(data) == "function" then return data() end
            return numericCooldown(data)
        end,
    }
    env.C_SpellBook = {
        HasPetSpells = function() return state.petID and 1 or 0 end,
        GetSpellBookItemInfo = function(slot, bank)
            assert(slot == 1 and bank == 1)
            return {spellID = state.petID}
        end,
        GetSpellBookItemCooldown = function(slot, bank)
            assert(slot == 1 and bank == 1)
            state.petQueries = (state.petQueries or 0) + 1
            return numericCooldown(state.petCooldown)
        end,
    }
    local function itemCooldown(id)
        local d = numericCooldown(state.items[id])
        return d.startTime, d.duration, d.isEnabled
    end
    env.C_Item = {
        GetItemCooldown = itemCooldown,
        GetItemNameByID = function(id) return "Item " .. id end,
        GetItemIconByID = function(id) return id end,
        GetItemSpell = function(id) return "Item spell " .. id, id + 1000 end,
    }
    env.GetInventoryItemID = function(_, slot) return state.slots[slot] end
    env.GetInventoryItemTexture = env.GetInventoryItemID
    env.GetInventoryItemCooldown = function(_, slot) return itemCooldown(state.slots[slot]) end
    env.UseInventoryItem = function() end
    env.hooksecurefunc = function(name, callback) state.hooks[name] = callback end
    env.GetActionInfo = function() return "item", state.actionItem end
    setfenv(addon, env)("Doom_CooldownPulse_Forever")
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

print(string.format("%d cooldown tests passed", passed))
