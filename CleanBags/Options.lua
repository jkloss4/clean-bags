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
    CB:SetSectionOrder(nil)
  end,
})

page:Header("Bags")
page:Checkbox("Sort Bags into Sections", Getter("BagSections"), Setter("BagSections"),
  "Groups your bags into Quest Items, Consumables, Reagents, Crafting, one section per equipment set, Gear, "
  .. "General, Junk and Empty.\n\nWorks with Blizzard's combined backpack (bag menu: Combine Bags).")

page:Header("Bank")
page:Checkbox("Sort Bank into Sections", Getter("CleanBank"), Setter("CleanBank"),
  "Groups the open bank into the same sections as your bags.")
page:Checkbox("Quick Swap Buttons", Getter("QuickDrop"), Setter("QuickDrop"),
  "While the bank is open, adds a button to each section title that moves the whole section between your bags "
  .. "and the bank. Your Hearthstone always stays in your bags.",
  { enabled = SortingOn })

-- Section order: one row per position, with up/down arrows (the minimal scroll bar's stepper art)
page:Header("Section Order")

local ORDER_TIP = "Use the arrows to move this section up or down, in both your bags and the bank. Empty sections "
  .. "aren't shown. Equipment Sets places a section for each of your equipment sets."

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
  local row = page:SettingRow("Section Order", ORDER_TIP, { enabled = SortingOn })
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
