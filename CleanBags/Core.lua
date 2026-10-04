-- Clean Bags core: saved settings and turning features on and off.
--
-- The feature files (BagSections, CleanBank, QuickDrop) come from ForeverForge and keep its small module API,
-- which this file provides on the addon namespace: RegisterModule, IsEnabled, SetEnabled, Print and Plain.

local addonName, CB = ...

CB.modules = {}
CB.moduleOrder = {}

function CB.Plain(s)
  return (tostring(s or ""):gsub("|", "||"))
end

function CB:Print(msg)
  local chat = _G.DEFAULT_CHAT_FRAME
  if chat and chat.AddMessage then
    chat:AddMessage("|cffffd200Clean Bags|r: " .. self.Plain(msg))
  end
end

-- Sections, in their default display order. "sets" stands for every equipment set's section (sorted by name).
CB.DEFAULT_ORDER = {
  "quest", "consumable", "quiver", "spellreagent", "reagent", "profession", "sets", "gear", "other", "junk", "empty",
}
CB.SECTION_NAMES = {
  quest = "Quest Items",
  consumable = "Consumables",
  quiver = "Quiver",
  spellreagent = "Reagents",
  reagent = "Crafting",
  profession = "Profession Equipment",
  sets = "Equipment Sets",
  gear = "Gear",
  other = "General",
  junk = "Junk",
  empty = "Empty",
}

-- The saved order, cleaned up: unknown or repeated entries dropped, and sections it's missing (new in an update)
-- added after the section they follow by default
function CB:SectionOrder()
  local order, seen = {}, {}
  local saved = CleanBagsDB and CleanBagsDB.order
  for _, id in ipairs(type(saved) == "table" and saved or {}) do
    if self.SECTION_NAMES[id] and not seen[id] then
      seen[id] = true
      order[#order + 1] = id
    end
  end
  for index, id in ipairs(self.DEFAULT_ORDER) do
    if not seen[id] then
      seen[id] = true
      local at = 1
      local previous = self.DEFAULT_ORDER[index - 1]
      for position, existing in ipairs(order) do
        if existing == previous then
          at = position + 1
        end
      end
      table.insert(order, at, id)
    end
  end
  return order
end

function CB:SetSectionOrder(order)
  CleanBagsDB.order = order
  if self.CleanBagsRefresh then
    self.CleanBagsRefresh()
  end
  if self.CleanBankRefresh then
    self.CleanBankRefresh()
  end
end

-- Order of the items inside a section: "quality" (best first) or "slot" (bag slot order, so dragging rearranges)
function CB:ItemOrder()
  return CleanBagsDB and CleanBagsDB.itemOrder == "slot" and "slot" or "quality"
end

function CB:SetItemOrder(value)
  CleanBagsDB.itemOrder = value == "slot" and "slot" or nil
  self:SetSectionOrder(CleanBagsDB.order) -- relays out the bags and bank
end

-- Section divider: Blizzard's settings page divider (Options_HorizontalDivider, under each page's title) at its own
-- height, stretched across the section
function CB.CreateDivider(header)
  local line = header:CreateTexture(nil, "BORDER")
  line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 1)
  line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 1)
  if C_Texture.GetAtlasInfo("Options_HorizontalDivider") then
    line:SetAtlas("Options_HorizontalDivider", true) -- native height; the anchors set the width
  else
    line:SetHeight(1)
    line:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.4)
  end
  return line
end

-- How the sections are made: "type" (by kind of item, the default) or "bag" (one section per bag, Guild Wars 2 style)
function CB:GroupBy()
  return CleanBagsDB and CleanBagsDB.groupBy == "bag" and "bag" or "type"
end

function CB:SetGroupBy(value)
  CleanBagsDB.groupBy = value == "bag" and "bag" or nil
  self:SetSectionOrder(CleanBagsDB.order) -- relays out the bags and bank
end

-- Collapsible Sections: section titles that hide or show their section's items, with either grouping. Collapsed
-- sections are kept apart for the bags and the bank (where = "bags" or "bank"), by section key: the section's id
-- ("junk", "set:<name>"...), or "bag:<bag id>" when grouped by bag.
function CB:CollapsibleSections()
  return CleanBagsDB and CleanBagsDB.collapsible == true
end

function CB:SetCollapsibleSections(value)
  CleanBagsDB.collapsible = value == true or nil
  self:SetSectionOrder(CleanBagsDB.order) -- relays out the bags and bank
end

-- How the window sizes when sections are collapsed: "shrink" (fits the open sections), "hold" (keeps the size it had
-- while it stays open, then fits next time) or "full" (always sized for every section open). Plain fitting without
-- Collapsible Sections.
function CB:CollapseSizing()
  if not self:CollapsibleSections() then
    return "shrink"
  end
  local value = CleanBagsDB.collapseSizing
  return (value == "shrink" or value == "full") and value or "hold"
end

function CB:SetCollapseSizing(value)
  CleanBagsDB.collapseSizing = (value == "shrink" or value == "full") and value or nil
  self:SetSectionOrder(CleanBagsDB.order) -- relays out the bags and bank
end

function CB:IsSectionCollapsed(where, key)
  local saved = self:CollapsibleSections() and CleanBagsDB.collapsed and CleanBagsDB.collapsed[where]
  return key ~= nil and type(saved) == "table" and saved[key] == true
end

function CB:ToggleSectionCollapsed(where, key)
  if key == nil then
    return
  end
  CleanBagsDB.collapsed = CleanBagsDB.collapsed or {}
  local saved = CleanBagsDB.collapsed[where] or {}
  CleanBagsDB.collapsed[where] = saved
  saved[key] = not saved[key] or nil
  local refresh = where == "bank" and self.CleanBankRefresh or self.CleanBagsRefresh
  if refresh then
    refresh()
  end
end

-- Whether the items show in bag slot order, where Blizzard's Clean Up button (which reorders the slots) is useful
function CB:ShowsSlotOrder()
  return self:GroupBy() == "bag" or self:ItemOrder() == "slot"
end

function CB:RegisterModule(def)
  self.modules[def.id] = def
  self.moduleOrder[#self.moduleOrder + 1] = def.id
end

-- Saved choice, or the module's default before the first change
function CB:IsSavedEnabled(id)
  local saved = CleanBagsDB and CleanBagsDB.modules[id]
  if saved ~= nil then
    return saved
  end
  local module = self.modules[id]
  return module ~= nil and module.defaultEnabled == true
end

function CB:IsEnabled(id)
  local module = self.modules[id]
  return module ~= nil and module._active == true
end

local function Run(module, fn)
  if type(fn) ~= "function" then
    return true
  end
  local ok, err = pcall(fn, module)
  if not ok then
    CB:Print(module.name .. ": " .. tostring(err))
  end
  return ok
end

function CB:SetEnabled(id, enabled)
  local module = self.modules[id]
  if not module then
    return
  end
  enabled = enabled == true
  CleanBagsDB.modules[id] = enabled
  if enabled == (module._active == true) then
    return
  end
  if enabled then
    -- Active before onEnable, so the module's own IsEnabled checks pass while it starts
    module._active = true
    if not Run(module, module.onEnable) then
      module._active = false
    end
  else
    module._active = false
    Run(module, module.onDisable)
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then
      return
    end
    self:UnregisterEvent("ADDON_LOADED")
    CleanBagsDB = CleanBagsDB or {}
    CleanBagsDB.modules = CleanBagsDB.modules or {}
    if CB.RefreshOptions then
      CB.RefreshOptions()
    end
    return
  end
  self:UnregisterEvent("PLAYER_LOGIN")
  for _, id in ipairs(CB.moduleOrder) do
    if CB:IsSavedEnabled(id) then
      CB:SetEnabled(id, true)
    end
  end
end)
