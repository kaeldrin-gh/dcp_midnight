local _, addon = ...
local api = addon.Filters
local Editor = {view="filters", offset=0, rows={}, advanced=false}
addon.FilterEditor = Editor
local QUESTION_MARK = 134400
local requestedItems, requestedSpells = {}, {}

local function public(value, expected)
    return not api.IsSecret(value) and type(value) == expected
end

local function validID(value)
    return public(value, "number") and value > 0 and value <= 2147483647 and value == math.floor(value)
end

local function parse(text)
    local entries, seen = {}, {}
    for token in (text .. ","):gmatch("(.-),") do
        token = strtrim(token)
        local kind, id = token:match("^(%a+):(%d+)$")
        if kind and (kind:lower() == "spell" or kind:lower() == "item") and validID(tonumber(id)) then
            token = kind:lower() .. ":" .. tonumber(id)
        end
        if token ~= "" and not seen[token] then
            entries[#entries+1], seen[token] = token, true
        end
    end
    return entries
end

function Editor:Entries() return parse(api.GetText()) end

function Editor:Describe(token, fallback)
    local kind, id = token:match("^(spell):(%d+)$")
    if not kind then kind, id = token:match("^(item):(%d+)$") end
    id = tonumber(id)
    local name, icon
    if kind and not validID(id) then
        return {token=token, name=token, icon=QUESTION_MARK, detail="Unresolved entry"}
    end
    if kind == "spell" then
        local info = C_Spell.GetSpellInfo(id)
        if info and not api.IsSecret(info) then name, icon = info.name, info.iconID end
        if not name and C_Spell.RequestLoadSpellData and not requestedSpells[id] then
            requestedSpells[id] = true
            C_Spell.RequestLoadSpellData(id)
        end
    elseif kind == "item" then
        name, icon = C_Item.GetItemNameByID(id), C_Item.GetItemIconByID(id)
        if not name and C_Item.RequestLoadItemDataByID and not requestedItems[id] then
            requestedItems[id] = true
            C_Item.RequestLoadItemDataByID(id)
        end
    elseif not tonumber(token) then
        local info = C_Spell.GetSpellInfo(token)
        if info and not api.IsSecret(info) then name, icon = info.name, info.iconID end
        name = name or token
    end
    if not public(name, "string") then name = fallback and fallback.name or (kind and (kind .. " " .. id) or ("ID " .. token)) end
    if not public(name, "string") then name = "Unknown" end
    if not validID(icon) then icon = fallback and fallback.texture or QUESTION_MARK end
    if not validID(icon) and not public(icon, "string") then icon = QUESTION_MARK end
    return {token=token, kind=kind, id=id, name=name, icon=icon,
        detail=kind and (kind .. " ID " .. id) or (tonumber(token) and "Legacy ID (spell or item)" or "Legacy name")}
end

function Editor:Contains(kind, id)
    local token = kind .. ":" .. id
    local name = self:Describe(token).name
    for _, entry in ipairs(self:Entries()) do
        if entry == token or entry == tostring(id) or entry == name then return true end
    end
    return false
end

function Editor:Status(message)
    self.lastStatus = message
    if self.status then self.status:SetText(message) end
end

function Editor:Add(kind, id)
    if not public(kind, "string") or (kind ~= "spell" and kind ~= "item") or not validID(id) then
        self:Status("Drop a spell or item. Macros and other cursor types are not supported.")
        return false
    end
    if self:Contains(kind, id) then self:Status("Already in this filter list.") return true end
    local entries = self:Entries()
    entries[#entries+1] = kind .. ":" .. id
    api.SetText(table.concat(entries, ","))
    self:Status("Added " .. self:Describe(kind .. ":" .. id).name .. ".")
    return true
end

function Editor:Remove(token)
    local entries = {}
    for _, entry in ipairs(self:Entries()) do if entry ~= token then entries[#entries+1] = entry end end
    api.SetText(table.concat(entries, ","))
    self:Status("Removed entry.")
end

function Editor:ApplyText(text)
    if not public(text, "string") then return false end
    api.SetText(table.concat(parse(text), ","))
    self:Status("Filter text applied.")
    return true
end

function Editor:Drop()
    local kind, first, bank, spellID = GetCursorInfo()
    if api.IsSecret(kind) then self:Status("This cursor value is unavailable.") return false end
    local result = false
    if kind == "item" then
        result = self:Add("item", first)
    elseif kind == "spell" then
        if api.IsSecret(spellID) then self:Status("This cursor value is unavailable.") return false end
        -- Forever's modern cursor returns the spell ID fourth, not the slot second.
        if not validID(spellID) and validID(first) and public(bank, "number") and (bank == 0 or bank == 1) then
            local info = C_SpellBook.GetSpellBookItemInfo(first, bank)
            if info and not api.IsSecret(info) then spellID = info.spellID end
        end
        result = self:Add("spell", spellID)
    elseif kind == "petaction" then
        if validID(first) then
            for slot=1,C_SpellBook.HasPetSpells() or 0 do
                local info=C_SpellBook.GetSpellBookItemInfo(slot,Enum.SpellBookSpellBank.Pet)
                if info and not api.IsSecret(info) then
                    local spell, action=info.spellID,info.actionID
                    if (not api.IsSecret(spell) and spell==first) or (not api.IsSecret(action) and action==first) then
                        result=self:Add("spell",spell)
                        break
                    end
                end
            end
        end
        if not result then self:Status("Drag a pet ability from the pet spellbook, not a command such as Attack.") end
    else
        self:Status("Drop a spell or item. Macros and other cursor types are not supported.")
    end
    if result then ClearCursor() end
    return result
end

function Editor:RecentEntries()
    local result, seen = {}, {}
    local recent = api.GetRecent()
    for i = #recent, 1, -1 do
        local entry = recent[i]
        local kind = entry.kind == "item" and "item" or "spell"
        local token = kind .. ":" .. entry.id
        if not seen[token] then
            result[#result+1], seen[token] = self:Describe(token, entry), true
        end
    end
    return result
end

function Editor:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local entries = {}
    if self.view == "recent" then entries = self:RecentEntries()
    else entries = self:Entries() end
    self.offset = math.max(0, math.min(self.offset, math.max(0, #entries-7)))
    self.blacklist:SetChecked(not api.GetMode())
    self.whitelist:SetChecked(api.GetMode())
    self.filtersTab:SetText((self.view == "filters" and "> " or "") .. "Filters (" .. #self:Entries() .. ")")
    self.recentTab:SetText((self.view == "recent" and "> " or "") .. "Recent flashes")
    for i, row in ipairs(self.rows) do
        local entry = entries[self.offset+i]
        if type(entry)=="string" then entry=self:Describe(entry) end
        row.entry = entry
        if entry then
            row.icon:SetTexture(entry.icon)
            row.name:SetText(entry.name)
            row.detail:SetText(entry.detail)
            local included = self.view == "recent" and self:Contains(entry.kind, entry.id)
            row.action:SetText(self.view == "filters" and "Remove" or (included and "Added" or "Add"))
            row.action:SetEnabled(not included)
            row:Show()
        else row:Hide() end
    end
    self.empty:SetText(#entries == 0 and (self.view == "recent" and "No flashes recorded yet. Use an ability, then return here." or "No filters yet. Drop a spell or item above to add it.") or "")
    self.page:SetText(#entries == 0 and "0 entries" or (self.offset+1) .. "–" .. math.min(self.offset+7, #entries) .. " of " .. #entries)
    self.previous:SetEnabled(self.offset > 0)
    self.next:SetEnabled(self.offset+7 < #entries)
    if not self.raw:HasFocus() then self.raw:SetText(api.GetText()) end
end

function Editor:Create()
    local frame = CreateFrame("Frame", "DCP_FilterEditor", UIParent, "BackdropTemplate")
    self.frame = frame
    frame:Hide()
    frame:SetSize(600, 580)
    frame:SetPoint("CENTER", UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
    frame:SetBackdropColor(0.035, 0.055, 0.075, 0.98)
    tinsert(UISpecialFrames, "DCP_FilterEditor")
    local function text(value, x, y, font)
        local label = frame:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        label:SetJustifyH("LEFT")
        label:SetText(value)
        return label
    end
    local function button(name, title, x, y, width, callback, parent)
        parent = parent or frame
        local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
        b:SetSize(width, 26)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        b:SetText(title)
        b:SetScript("OnClick", callback)
        return b
    end
    text("Cooldown filters", 20, -18, "GameFontNormalLarge")
    text("Drag spells/items, or add a recent flash. Changes save immediately.", 20, -44, "GameFontHighlightSmall")
    local drop = CreateFrame("Button", "DCP_FilterEditorDrop", frame, "BackdropTemplate")
    self.drop = drop
    drop:EnableMouse(true)
    drop:SetSize(560, 56)
    drop:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -68)
    drop:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12})
    drop:SetBackdropColor(0.06,0.17,0.23,1)
    local dropText = drop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropText:SetPoint("CENTER", drop, "CENTER")
    dropText:SetText("Drop a spell or item here")
    drop:SetScript("OnReceiveDrag", function() self:Drop() end)
    drop:SetScript("OnClick", function()
        local kind=GetCursorInfo()
        if not api.IsSecret(kind) and kind then self:Drop() end
    end)
    local function mode(name, title, x, value)
        local radio = CreateFrame("CheckButton", name, frame, "UIRadioButtonTemplate")
        radio:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -138)
        local label = radio:CreateFontString(nil,"ARTWORK","GameFontHighlight")
        label:SetPoint("LEFT",radio,"RIGHT",4,0)
        label:SetText(title)
        radio:SetScript("OnClick",function() api.SetMode(value) self:Refresh() end)
        return radio
    end
    self.blacklist = mode("DCP_FilterEditorBlacklist", "Blacklist — hide these", 20, false)
    self.whitelist = mode("DCP_FilterEditorWhitelist", "Whitelist — show only these", 300, true)
    self.filtersTab = button("DCP_FilterEditorFilters", "Filters",20,-174,176,function() self.view="filters" self.offset=0 self:Refresh() end)
    self.recentTab = button("DCP_FilterEditorRecent", "Recent flashes",212,-174,176,function() self.view="recent" self.offset=0 self:Refresh() end)
    self.advancedButton = button("DCP_FilterEditorAdvancedToggle","Advanced text",404,-174,176,function()
        self.advanced = not self.advanced
        frame:SetHeight(self.advanced and 650 or 580)
        self.rawLabel:SetShown(self.advanced) self.raw:SetShown(self.advanced) self.apply:SetShown(self.advanced)
        self.advancedButton:SetText(self.advanced and "Hide advanced" or "Advanced text")
        self.status:ClearAllPoints()
        self.status:SetPoint("TOPLEFT",frame,"TOPLEFT",20,self.advanced and -588 or -522)
    end)
    local list = CreateFrame("Frame",nil,frame)
    list:SetPoint("TOPLEFT",frame,"TOPLEFT",20,-208)
    list:SetSize(560,266)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel",function(_,delta) self.offset=self.offset-delta self:Refresh() end)
    for i=1,7 do
        local row = CreateFrame("Button","DCP_FilterEditorRow"..i,list)
        self.rows[i] = row
        row:SetSize(560,36) row:SetPoint("TOPLEFT",list,"TOPLEFT",0,-(i-1)*38)
        row.icon=row:CreateTexture(nil,"ARTWORK") row.icon:SetSize(28,28) row.icon:SetPoint("TOPLEFT",row,"TOPLEFT",0,-4)
        row.name=row:CreateFontString(nil,"ARTWORK","GameFontHighlight") row.name:SetPoint("TOPLEFT",row,"TOPLEFT",38,-3) row.name:SetWidth(430) row.name:SetJustifyH("LEFT")
        row.detail=row:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall") row.detail:SetPoint("TOPLEFT",row,"TOPLEFT",38,-21) row.detail:SetTextColor(0.65,0.7,0.75)
        row.action=button("DCP_FilterEditorRow"..i.."Action","Remove",486,-5,74,function()
            if not row.entry then return end
            if self.view == "filters" then self:Remove(row.entry.token) else self:Add(row.entry.kind,row.entry.id) end
            self:Refresh()
        end,row)
        row:SetScript("OnEnter",function()
            if not row.entry then return end
            GameTooltip:SetOwner(row,"ANCHOR_RIGHT")
            if row.entry.kind == "spell" then GameTooltip:SetSpellByID(row.entry.id)
            elseif row.entry.kind == "item" then GameTooltip:SetItemByID(row.entry.id)
            else GameTooltip:SetText(row.entry.name) GameTooltip:AddLine(row.entry.detail) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    self.empty=text("",26,-232,"GameFontHighlightSmall")
    self.previous=button("DCP_FilterEditorPrevious","Previous",20,-482,90,function() self.offset=self.offset-7 self:Refresh() end)
    self.next=button("DCP_FilterEditorNext","Next",490,-482,90,function() self.offset=self.offset+7 self:Refresh() end)
    self.page=text("",244,-490,"GameFontHighlightSmall")
    self.rawLabel=text("Comma-separated names, IDs, spell:ID or item:ID",20,-522,"GameFontHighlightSmall")
    self.raw=CreateFrame("EditBox","DCP_FilterEditorRaw",frame,"InputBoxTemplate")
    self.raw:SetSize(452,32) self.raw:SetPoint("TOPLEFT",frame,"TOPLEFT",24,-542) self.raw:SetAutoFocus(false)
    local function apply() local value=self.raw:GetText() self.raw:ClearFocus() self:ApplyText(value) self:Refresh() end
    self.raw:SetScript("OnEnterPressed",apply)
    self.apply=button("DCP_FilterEditorApply","Apply",490,-542,90,apply)
    self.rawLabel:Hide() self.raw:Hide() self.apply:Hide()
    self.status=text("",20,-522,"GameFontHighlightSmall") self.status:SetWidth(560)
    local close=button("DCP_FilterEditorClose","Close",470,0,110,function() frame:Hide() end)
    close:ClearAllPoints() close:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-20,14)
    frame:SetScript("OnShow",function() self:Refresh() end)
    frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    frame:SetScript("OnEvent",function() if frame:IsShown() then self:Refresh() end end)
end

function Editor:Open()
    if not self.frame then self:Create() end
    self.frame:Show()
    self:Refresh()
end
