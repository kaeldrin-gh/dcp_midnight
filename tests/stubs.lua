local now = 100
local secretOperations = 0
local secretValues = setmetatable({}, {__mode = "k"})
local function secretOperation()
    secretOperations = secretOperations + 1
    error("attempt to operate on a secret value")
end
local function Secret()
    local value = setmetatable({}, {
        __add = secretOperation, __sub = secretOperation,
        __lt = secretOperation, __le = secretOperation,
        __concat = secretOperation, __tostring = secretOperation,
    })
    secretValues[value] = true
    return value
end
function issecretvalue(value) return secretValues[value] == true end
local realType = type
function type(value)
    if issecretvalue(value) then return "number" end
    return realType(value)
end
local Methods = {}
local frames = {}
function CreateFrame(kind, name, parent, template)
    assert(kind ~= "Cooldown", "secret cooldown frame fallback must not be used")
    local frame = setmetatable({scripts = {}, parent = parent}, {__index = Methods})
    table.insert(frames, frame)
    if name then _G[name] = frame end
    if template == "OptionsSliderTemplate" then
        for _, suffix in ipairs({"Text", "Low", "High"}) do
            _G[name .. suffix] = CreateFrame("FontString")
        end
    end
    return frame
end
setmetatable(Methods, {__index = function(_, method)
    if method:match("^Set") or method:match("^Register") or
       method:match("^Unregister") or method == "Show" or method == "Hide" then
        return function() end
    end
end})
function Methods:SetScript(name, callback) self.scripts[name] = callback end
function Methods:CreateTexture() return CreateFrame("Texture") end
function Methods:CreateFontString() return CreateFrame("FontString") end
function Methods:GetWidth() return 1920 end
function Methods:GetHeight() return 1080 end
function Methods:GetEffectiveScale() return 1 end
function Methods:IsMouseEnabled() return false end
function Methods:EnableMouse() end
function Methods:ClearAllPoints() end
function Methods:SetTexture(value)
    assert(value == nil or type(value) == "string" or type(value) == "number")
    self.texture = value
end
function Methods:GetTexture() return self.texture end
function Methods:SetNormalTexture() self.normalTexture = CreateFrame("Texture") end
function Methods:GetNormalTexture() return self.normalTexture end
function Methods:SetText(value) self.text = value end
function Methods:GetText() return self.text end
function Methods:SetChecked(value) self.checked = value == true end
function Methods:GetChecked() return self.checked end
function Methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function Methods:GetValue() return self.value end
function Methods:GetParent() return self.parent end
UIParent = CreateFrame("Frame")
STANDARD_TEXT_FONT = "stub"
SlashCmdList = {}
UISpecialFrames = {}
getglobal = function(name) return _G[name] end
format, ceil = string.format, math.ceil
function PlaySound() end
function GetTime() return now end
function wipe(t) for k in pairs(t) do t[k] = nil end end
tinsert, tremove = table.insert, table.remove
function strtrim(s) return s:match("^%s*(.-)%s*$") end
function strsplit(_, s) return s end
local hooks = {}
function hooksecurefunc(owner, method, callback)
    if type(owner) == "string" then hooks[owner] = method
    else hooks[method] = callback end
end
local spells, items, slots = {}, {}, {}
C_Spell = {
    GetSpellInfo = function(id)
        assert(not issecretvalue(id))
        return {name = "Spell " .. id, iconID = id}
    end,
    GetSpellCooldown = function(id) return spells[id] end,
}
C_Item = {
    GetItemCooldown = function(id) return unpack(items[id] or {0, 0, true}) end,
    GetItemNameByID = function(id) return "Item " .. id end,
    GetItemIconByID = function(id) return id end,
}
function GetInventoryItemID(_, slot) return slots[slot] and slots[slot].id end
function GetInventoryItemTexture(_, slot) return GetInventoryItemID(nil, slot) end
function GetInventoryItemCooldown(_, slot)
    return unpack(slots[slot].cooldown or {0, 0, true})
end
local actionType, actionID
function GetActionInfo() return actionType, actionID end
