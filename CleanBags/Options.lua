-- Options page (Options > AddOns > Clean Bags), drawn in Blizzard's settings style by SettingsKit

local _, CB = ...
local Kit = CB.SettingsKit

local function Getter(id)
  return function() return CB:IsSavedEnabled(id) end
end

local function Setter(id)
  return function(value) CB:SetEnabled(id, value) end
end

local function SortingOn()
  return CB:IsSavedEnabled("BagSections") or CB:IsSavedEnabled("CleanBank")
end

local page = Kit.NewPage("Clean Bags", {
  onDefaults = function()
    for _, id in ipairs(CB.moduleOrder) do
      CB:SetEnabled(id, CB.modules[id].defaultEnabled == true)
    end
    CleanBagsDB.itemOrder = nil
    CleanBagsDB.groupBy = nil
    CB:SetSectionOrder(nil)
  end,
})

page:Header("Bags")
page:Checkbox("Sort Bags into Sections", Getter("BagSections"), Setter("BagSections"),
  "Groups your bags into sections: Quest Items, Consumables, Quiver, Reagents, Crafting, Profession Equipment, "
  .. "one per equipment set, Gear, General, Junk and Empty. Their order is set under Section Order.\n\nWorks with Blizzard's combined backpack (bag menu: Combine Bags).")

page:Header("Bank")
page:Checkbox("Sort Bank into Sections", Getter("CleanBank"), Setter("CleanBank"),
  "Groups the open bank into the same sections as your bags, in the same order.")
page:Checkbox("Quick Swap Buttons", Getter("QuickDrop"), Setter("QuickDrop"),
  "While the bank is open, adds a button to each section title that moves the whole section between your bags "
  .. "and the bank. Your Hearthstone always stays in your bags.",
  { enabled = SortingOn })

-- Item Order and Section Order only apply to sections by item type
local function ByTypeOn()
  return SortingOn() and CB:GroupBy() == "type"
end

page:Header("Items")
page:Dropdown("Group Items By", {
  { label = "Item Type", value = "type",
    tooltip = "Sections for each kind of item: Quest Items, Consumables, Gear, Junk and so on." },
  { label = "Bag", value = "bag",
    tooltip = "A section for each bag, like Guild Wars 2: every slot in its bag, in slot order, so items stay where "
      .. "you put them and can be dragged between bags. Blizzard's Clean Up button is shown." },
}, function() return CB:GroupBy() end, function(value) CB:SetGroupBy(value) end,
  "How your bags and the bank are split into sections.", { enabled = SortingOn })
page:Dropdown("Item Order", {
  { label = "By Quality", value = "quality",
    tooltip = "Best quality first, then grouped by item. An item that's dragged elsewhere in its section goes back "
      .. "to its sorted spot." },
  { label = "By Bag Slot", value = "slot",
    tooltip = "In the order of your bag slots, so you can arrange a section by dragging items onto each other. "
      .. "Blizzard's Clean Up button is shown, to tidy them in one click." },
}, function() return CB:ItemOrder() end, function(value) CB:SetItemOrder(value) end,
  "How items are ordered inside each section, in both your bags and the bank.", { enabled = ByTypeOn })

-- Section order: one row per position, with up/down arrows (the minimal scroll bar's stepper art)
page:Header("Section Order")

local SECTION_TIPS = {
  quest = "Quest items, including items that start a quest.",
  consumable = "Food, drink, potions, elixirs, bandages, scrolls and other items that are used up.",
  quiver = "Every slot of your quiver or ammo pouch, filled or empty. Bags only.",
  spellreagent = "Reagents that spells use up.",
  reagent = "Trade goods: materials for crafting professions.",
  profession = "Fishing poles, skinning knives, mining picks, smithing hammers, enchanting rods and other "
    .. "profession tools.",
  sets = "A section for each of your equipment sets, with the gear saved in it, in order of set name.",
  gear = "Weapons and armor that aren't in an equipment set.",
  other = "Everything that doesn't belong in another section.",
  junk = "Poor quality (gray) items.",
  empty = "Empty slots.",
}
local ORDER_HINT = "Use the arrows to move this section up or down, in both your bags and the bank. "
  .. "Sections with nothing in them aren't shown."

local function Move(index, delta)
  local order = CB:SectionOrder()
  local target = index + delta
  if target < 1 or target > #order then
    return
  end
  order[index], order[target] = order[target], order[index]
  PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
  CB:SetSectionOrder(order)
  page:Refresh()
end

local function Arrow(row, atlas, onClick)
  local button = CreateFrame("Button", nil, row)
  button:SetSize(17, 11)
  button:SetNormalAtlas(atlas)
  button:SetPushedAtlas(atlas .. "-down")
  button:SetDisabledAtlas(atlas)
  button:GetDisabledTexture():SetAlpha(0.3)
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self)
    self:SetNormalAtlas(atlas .. "-over")
    row:ShowHover(self)
  end)
  button:SetScript("OnLeave", function(self)
    self:SetNormalAtlas(atlas)
    row:HideHover()
  end)
  return button
end

for index = 1, #CB.DEFAULT_ORDER do
  local row = page:SettingRow("Section Order", nil, { enabled = ByTypeOn })
  -- The section in this row changes as sections are moved, so its tooltip is looked up when shown
  function row:ShowHover(owner)
    local id = CB:SectionOrder()[index]
    self.HoverBackground:Show()
    SettingsTooltip:SetOwner(owner or self.Hover, "ANCHOR_RIGHT", -10, 0)
    GameTooltip_AddHighlightLine(SettingsTooltip, CB.SECTION_NAMES[id])
    GameTooltip_AddNormalLine(SettingsTooltip, SECTION_TIPS[id], true)
    GameTooltip_AddBlankLineToTooltip(SettingsTooltip)
    GameTooltip_AddInstructionLine(SettingsTooltip, ORDER_HINT, true)
    SettingsTooltip:Show()
  end
  local up = Arrow(row, "minimal-scrollbar-arrow-top", function() Move(index, -1) end)
  up:SetPoint("LEFT", row, "CENTER", -80, 0)
  local down = Arrow(row, "minimal-scrollbar-arrow-bottom", function() Move(index, 1) end)
  down:SetPoint("LEFT", up, "RIGHT", 6, 0)
  page:OnRefresh(function()
    local order = CB:SectionOrder()
    row.Text:SetText(CB.SECTION_NAMES[order[index]])
    local enabled = row:UpdateEnabled()
    up:SetEnabled(enabled and index > 1)
    down:SetEnabled(enabled and index < #order)
  end)
end

Kit.Register(page)

CB.RefreshOptions = function() page:Refresh() end

SLASH_CLEANBAGS1 = "/cleanbags"
SlashCmdList["CLEANBAGS"] = function()
  Kit.Open(page)
end
