--[[
  Clean Bank. Groups the open bank with the same sections as Clean Bags:
  Quest Items, Reagents, Crafting, equipment sets, Gear, General, Junk, Empty.

  Uses the bank's own item buttons. A secret item id is left in General.
]]

local _, FTK = ...
if not FTK.CleanBagRules then
  error("CleanBags: BagSections.lua must load before CleanBank.lua")
end

local Rules = FTK.CleanBagRules
local MODULE_ID = "CleanBank"
local ITEM_GAP_X = 5
local ITEM_GAP_Y = 5
local HEADER_H = 20
local SECTION_GAP = 8
local TOP_OFFSET = 40

local SECTIONS = {
  { id = "quest", title = "Quest Items" },
  { id = "consumable", title = "Consumables" },
  { id = "junk", title = "Junk" },
  { id = "spellreagent", title = "Reagents" },
  { id = "reagent", title = "Crafting" },
  { id = "gear", title = "Gear" },
  { id = "other", title = "General" },
  { id = "empty", title = "Empty" },
}

local hooked = false
local layingOut = false
local warned = false
local headerPool = {}
local headerUsed = 0

local function BankPanel()
  local frame = _G.BankFrame
  if frame and frame.BankPanel and frame.BankPanel.EnumerateValidItems then
    return frame, frame.BankPanel
  end
  return frame, nil
end

local function ButtonBagSlot(button, panel)
  local bag, slot
  if type(button) ~= "table" then
    return nil, nil
  end
  if button.GetBankTabID then
    local ok, value = pcall(button.GetBankTabID, button)
    if ok then
      bag = Rules.PlainNumber(value)
    end
  end
  if not bag and button.bankTabID then
    bag = Rules.PlainNumber(button.bankTabID)
  end
  if not bag and panel and panel.GetSelectedTabID then
    local ok, value = pcall(panel.GetSelectedTabID, panel)
    if ok then
      bag = Rules.PlainNumber(value)
    end
  end
  if button.GetContainerSlotID then
    local ok, value = pcall(button.GetContainerSlotID, button)
    if ok then
      slot = Rules.PlainNumber(value)
    end
  end
  if not slot and button.GetID then
    local ok, value = pcall(button.GetID, button)
    if ok then
      slot = Rules.PlainNumber(value)
    end
  end
  if not bag then
    local bankBag = Enum and Enum.BagIndex and Enum.BagIndex.Bank
    bag = Rules.PlainNumber(bankBag) or -1
  end
  return bag, slot
end

local function CollectButtons(panel)
  local buttons = {}
  if panel and panel.EnumerateValidItems then
    local ok, iter, state, index = pcall(panel.EnumerateValidItems, panel)
    if ok and type(iter) == "function" then
      -- The bank iterator returns the button first and a validity flag second.
      local itemButton, isValid
      for itemButton, isValid in iter, state, index do
        if type(itemButton) == "table" and isValid ~= false then
          buttons[#buttons + 1] = itemButton
        end
      end
    end
  end
  if #buttons == 0 then
    local index = 1
    while true do
      local button = _G["BankFrameItem" .. index]
      if not button then
        break
      end
      buttons[#buttons + 1] = button
      index = index + 1
    end
  end
  return buttons
end

local function AcquireHeader(parent)
  headerUsed = headerUsed + 1
  local header = headerPool[headerUsed]
  if not header then
    header = CreateFrame("Frame", nil, parent)
    header:SetHeight(HEADER_H)
    header.line = FTK.CreateDivider(header)
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 24, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB()) -- Blizzard's white (GameFontHighlight)
    header.label = label
    header:EnableMouse(false)
    headerPool[headerUsed] = header
  end
  header:EnableMouse(false)
  header:SetParent(parent)
  header:Show()
  return header
end

local function HideUnusedHeaders()
  local index
  for index = headerUsed + 1, #headerPool do
    headerPool[index]:Hide()
  end
end

local function ButtonSize(button)
  local width = button and Rules.PlainNumber(button:GetWidth()) or nil
  local height = button and Rules.PlainNumber(button:GetHeight()) or nil
  if not width or width < 20 then
    width = 37
  end
  if not height or height < 20 then
    height = 37
  end
  return width, height
end

local function Place(button, parent, x, y)
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:Show()
end

local SCREEN_MARGIN = 10
local DIVIDER_GAP = 8
local FALLBACK_BOTTOM_AREA = 240
local MIN_HEIGHT = 300
local MIN_SIDE = 10

-- The panel is anchored by its LEFT point, so it's centered in the bank window. Laying out with the panel as tall as
-- the window puts the panel's top at the window's top, so offsets measured from the window's top hold for both.

-- Sections start below the bank's search box row (the portrait hangs down beside it), or TOP_OFFSET without one
local function TopOffset(frame)
  local searchBox = frame.BankItemSearchBox
  local frameTop = Rules.PlainNumber(frame:GetTop())
  local searchBottom = searchBox and searchBox:IsShown() and Rules.PlainNumber(searchBox:GetBottom())
  if frameTop and searchBottom then
    local offset = math.floor(frameTop - searchBottom + 0.5) + 10
    if offset > TOP_OFFSET and offset < 120 then
      return offset
    end
  end
  return TOP_OFFSET
end

-- Room kept at the bottom of the window for Blizzard's bag slot area: everything from the "bank-divider" line above
-- the Bag Slots row down to the window's bottom, plus a gap above that line
local function BottomArea(frame, panel)
  local frameBottom = Rules.PlainNumber(frame:GetBottom())
  if frameBottom then
    for _, region in ipairs({ frame:GetRegions() }) do
      if region.GetAtlas and region:GetAtlas() == "bank-divider" and region:IsShown() then
        -- The divider is drawn at 0.48 scale, and its position comes back in its own scaled units
        local dividerTop = Rules.PlainNumber(region:GetTop())
        dividerTop = dividerTop and dividerTop * region:GetEffectiveScale() / frame:GetEffectiveScale()
        if dividerTop and dividerTop > frameBottom then
          return math.ceil(dividerTop - frameBottom) + DIVIDER_GAP
        end
      end
    end
  end
  -- Retail has no bag slot area: room for the bank panel's deposit button (Deposit All Reagents / Warbound Items),
  -- or its money bar when there's no button. Measured from the panel's bottom, which the layout puts at the
  -- window's bottom.
  local panelBottom = panel and Rules.PlainNumber(panel:GetBottom())
  if panelBottom then
    for _, child in ipairs({ panel.AutoDepositFrame, panel.MoneyFrame }) do
      local top = child and child:IsShown() and Rules.PlainNumber(child:GetTop())
      if top and top > panelBottom then
        return math.ceil(top - panelBottom) + DIVIDER_GAP
      end
    end
  end
  return FALLBACK_BOTTOM_AREA
end

-- Window height needed for the sections with this many columns
local function NeededHeight(ordered, columns, buttonHeight, top, bottomArea, asOpen)
  local height, gap = top, 0
  for index = 1, #ordered do
    local sectionHeight
    sectionHeight, gap = Rules.SectionHeight(ordered[index], "bank", columns, buttonHeight, asOpen)
    height = height + sectionHeight
  end
  return height - gap + bottomArea
end

-- Blizzard's column count, or more when the sections wouldn't fit between the window's top and the bottom of the
-- screen: the window gets wider (to the right, where it grows) instead of running off the screen
local function FitColumns(frame, ordered, columns, buttonWidth, buttonHeight, top, bottomArea, asOpen)
  local windowTop, left = Rules.PlainNumber(frame:GetTop()), Rules.PlainNumber(frame:GetLeft())
  local frameScale = frame:GetEffectiveScale()
  if not windowTop or not left or not frameScale or frameScale <= 0 then
    return columns
  end
  local screenRight = UIParent:GetRight() * UIParent:GetEffectiveScale() / frameScale
  local extraRoom = screenRight - left - SCREEN_MARGIN - frame.ftkBaseWidth
  local maxColumns = columns + math.max(0, math.floor(extraRoom / (buttonWidth + ITEM_GAP_X)))
  local availableHeight = windowTop - SCREEN_MARGIN -- the screen's bottom is 0
  while columns < maxColumns and NeededHeight(ordered, columns, buttonHeight, top, bottomArea, asOpen) > availableHeight do
    columns = columns + 1
  end
  return columns
end

-- The search box and Clean Up button row, laid out like the backpack's (ContainerFrameCombinedBagsMixin:
-- SetSearchBoxPoint and UpdateSearchBox): an 18-tall search box from x 62 to 6 left of the 28x26 button, which sits
-- 9 in from the window's right edge. Without sorting, Blizzard's bank layout (BankFrameTemplates.xml) is put back.
local function LayOutSearchRow(frame, panel, likeBackpack)
  local searchBox, sortButton = frame.BankItemSearchBox, panel and panel.AutoSortButton
  if not (searchBox and sortButton) then
    return
  end
  searchBox:ClearAllPoints()
  sortButton:ClearAllPoints()
  if likeBackpack then
    sortButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -34)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -37)
    searchBox:SetPoint("RIGHT", sortButton, "LEFT", -6, 0)
    searchBox:SetHeight(18)
  else
    searchBox:SetSize(110, 20)
    searchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -56, -33)
    sortButton:SetPoint("LEFT", searchBox, "RIGHT", 8, -1)
  end
end

-- Blizzard's own size for the bank window and panel, from before the first layout
local function RestoreBaseSize(frame, panel)
  if frame and frame.ftkBaseHeight then
    frame:SetHeight(frame.ftkBaseHeight)
  end
  if panel and panel.ftkBaseHeight then
    panel:SetHeight(panel.ftkBaseHeight)
  end
  if frame and frame.ftkBaseWidth then
    frame:SetWidth(frame.ftkBaseWidth)
  end
  if panel and panel.ftkBaseWidth then
    panel:SetWidth(panel.ftkBaseWidth)
  end
end

-- Blizzard is showing one of its prompts instead of slots: buying a tab, or a locked bank
local function ShowingPrompt(panel)
  for _, prompt in ipairs(type(panel.Prompts) == "table" and panel.Prompts or {}) do
    if prompt:IsShown() then
      return true
    end
  end
  return false
end

local function Layout(frame, panel)
  if layingOut or not FTK:IsEnabled(MODULE_ID) or not frame or not panel or not panel:IsShown() then
    return
  end
  if ShowingPrompt(panel) then
    -- nothing to sort: the prompt shows at Blizzard's size, without the last tab's sections over it
    FTK.UntrackSlots()
    headerUsed = 0
    HideUnusedHeaders()
    RestoreBaseSize(frame, panel)
    if UpdateUIPanelPositions then
      pcall(UpdateUIPanelPositions, frame)
    end
    return
  end
  local buttons = CollectButtons(panel)
  if #buttons == 0 then
    return
  end
  layingOut = true
  headerUsed = 0
  LayOutSearchRow(frame, panel, true)
  if not panel.ftkBaseHeight then
    panel.ftkBaseHeight = Rules.PlainNumber(panel:GetHeight())
    frame.ftkBaseHeight = Rules.PlainNumber(frame:GetHeight())
  end
  if not panel.ftkBaseWidth then
    panel.ftkBaseWidth = Rules.PlainNumber(panel:GetWidth()) or 400
    frame.ftkBaseWidth = Rules.PlainNumber(frame:GetWidth()) or panel.ftkBaseWidth
  end

  local ordered
  if FTK:GroupBy() == "bag" then
    ordered = Rules.GroupByBag(buttons, function(button)
      return ButtonBagSlot(button, panel)
    end)
  else
    local setByItem, setBySlot = Rules.EquipmentSetMaps()
    local groups = {}
    local groupOrder = {}
    local function Group(id, title)
      local group = groups[id]
      if not group then
        group = { id = id, title = title, items = {}, empties = {} }
        groups[id] = group
        groupOrder[#groupOrder + 1] = id
      end
      return group
    end
    local index
    for index = 1, #SECTIONS do
      Group(SECTIONS[index].id, SECTIONS[index].title)
    end
    for index = 1, #buttons do
      local button = buttons[index]
      local bag, slot = ButtonBagSlot(button, panel)
      local item = Rules.ReadItem(bag, slot)
      if not item then
        Group("empty", "Empty").empties[#Group("empty", "Empty").empties + 1] = button
        FTK.TrackSlot(button, "empty", bag, slot, true)
      else
        local category, setTitle = Rules.CategoryFor(item, bag, slot, setByItem, setBySlot)
        local title = setTitle or FTK.SECTION_NAMES[category] or FTK.SECTION_NAMES.other
        local group = Group(category, title)
        group.items[#group.items + 1] = { button = button, itemID = item.itemID, quality = item.quality or 0, bag = bag, slot = slot }
        FTK.TrackSlot(button, category, bag, slot, false)
      end
    end

    ordered = Rules.OrderGroups(groups, groupOrder)
  end

  local buttonWidth, buttonHeight = ButtonSize(buttons[1])
  -- As many columns as fit with at least MIN_SIDE on each side; the grid is centered, and the dividers span it
  local baseColumns = math.floor((panel.ftkBaseWidth - (2 * MIN_SIDE) + ITEM_GAP_X) / (buttonWidth + ITEM_GAP_X))
  baseColumns = math.min(math.max(baseColumns, 8), 16)
  local top, bottomArea = TopOffset(frame), BottomArea(frame, panel)
  local sizing = FTK:CollapseSizing()
  local columns = FitColumns(frame, ordered, baseColumns, buttonWidth, buttonHeight, top, bottomArea, sizing == "full")
  if sizing == "hold" and frame.cbHeldColumns then
    columns = math.max(columns, frame.cbHeldColumns)
  end
  local extraWidth = (columns - baseColumns) * (buttonWidth + ITEM_GAP_X)
  frame:SetWidth(frame.ftkBaseWidth + extraWidth)
  panel:SetWidth(panel.ftkBaseWidth + extraWidth)
  local gridWidth = (columns * buttonWidth) + ((columns - 1) * ITEM_GAP_X)
  local side = math.floor((panel.ftkBaseWidth + extraWidth - gridWidth) / 2)
  local rightInset = panel.ftkBaseWidth + extraWidth - side - gridWidth
  local cursor, gap = top, 0

  for index = 1, #ordered do
    local group = ordered[index]
    local header = AcquireHeader(panel)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", side, -cursor)
    local count = #group.items
    if group.id == "bag" then
      count = #group.swapItems .. "/" .. #group.items -- used / total slots
    elseif count == 0 then
      count = #group.empties
    end
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -rightInset, -cursor)
    Rules.DressHeader(header, group, "bank", group.title .. " (" .. count .. ")")
    if FTK.QuickDrop and FTK.QuickDrop.Attach then
      FTK.QuickDrop:Attach(header, group.swapItems or group.items, "withdraw", group.title, function(button)
        return ButtonBagSlot(button, panel)
      end)
    end
    Rules.PlaceTitle(header)

    local collapsed = Rules.IsCollapsed("bank", group)
    local placed = {}
    local itemIndex
    for itemIndex = 1, #group.items do
      placed[#placed + 1] = group.items[itemIndex].button
    end
    for itemIndex = 1, #group.empties do
      placed[#placed + 1] = group.empties[itemIndex]
    end
    local itemsTop = cursor + Rules.HeaderHeight() + 4
    for itemIndex = 1, #placed do
      if collapsed then
        placed[itemIndex]:Hide()
      else
        local column = (itemIndex - 1) % columns
        local row = math.floor((itemIndex - 1) / columns)
        local x = side + (column * (buttonWidth + ITEM_GAP_X))
        local y = -(itemsTop + (row * (buttonHeight + ITEM_GAP_Y)))
        Place(placed[itemIndex], panel, x, y)
      end
    end
    local sectionHeight
    sectionHeight, gap = Rules.SectionHeight(group, "bank", columns, buttonHeight)
    cursor = cursor + sectionHeight
  end

  HideUnusedHeaders()
  -- Fit to the sections: the last row ends DIVIDER_GAP above the bag slot area's divider. (Not Blizzard's own
  -- height as a minimum: Forever's bank window starts sized for a full 88-slot page.)
  local height = cursor - gap + bottomArea
  if sizing == "full" then
    height = NeededHeight(ordered, columns, buttonHeight, top, bottomArea, true)
  elseif sizing == "hold" and frame.cbHeldHeight then
    height = math.max(height, frame.cbHeldHeight)
  end
  height = math.max(height, MIN_HEIGHT)
  -- Kept until the bank closes, for "hold"
  if sizing == "hold" then
    frame.cbHeldHeight, frame.cbHeldColumns = height, columns
  end
  frame:SetHeight(height)
  panel:SetHeight(height) -- as tall as the window, so its top is the window's top (it's centered)
  -- Blizzard's bank Clean Up button reorders the slots: only useful when sections show items in slot order
  if panel.AutoSortButton then
    panel.AutoSortButton:SetShown(FTK:ShowsSlotOrder())
  end
  if UpdateUIPanelPositions then
    pcall(UpdateUIPanelPositions, frame)
  end
  layingOut = false
end

local function RequestLayout()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  local frame, panel = BankPanel()
  if not panel then
    if frame and frame:IsShown() and not warned then
      warned = true
      FTK:Print("Clean Bank: the bank item panel was not found.")
    end
    return
  end
  if panel:IsShown() then
    Layout(frame, panel)
  end
end

local function ScheduleLayout()
  RequestLayout()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, RequestLayout)
    C_Timer.After(0.1, RequestLayout)
  end
end

local function RestoreBank()
  FTK.UntrackSlots()
  headerUsed = 0
  HideUnusedHeaders()
  local frame, panel = BankPanel()
  if frame then
    LayOutSearchRow(frame, panel, false)
  end
  if panel then
    for _, button in ipairs(CollectButtons(panel)) do
      button:Show() -- items of collapsed sections
    end
  end
  if panel and panel.RefreshBankPanel then
    pcall(panel.RefreshBankPanel, panel)
  end
  if panel and panel.AutoSortButton then
    panel.AutoSortButton:Show()
  end
  RestoreBaseSize(frame, panel)
  if frame and UpdateUIPanelPositions then
    pcall(UpdateUIPanelPositions, frame)
  end
end

local function InstallHook()
  if hooked or not hooksecurefunc then
    return hooked
  end
  local _, panel = BankPanel()
  if not panel then
    return false
  end
  local methods = {
    "GenerateItemSlotsForSelectedTab",
    "RefreshAllItemsForSelectedTab",
    "RefreshBankPanel",
  }
  local index
  for index = 1, #methods do
    local name = methods[index]
    if type(panel[name]) == "function" then
      hooksecurefunc(panel, name, function()
        if layingOut or not FTK:IsEnabled(MODULE_ID) then
          return
        end
        ScheduleLayout()
      end)
    end
  end
  local frame = _G.BankFrame
  if frame and frame.HookScript and not frame.ftkCleanBankShow then
    frame.ftkCleanBankShow = true
    frame:HookScript("OnShow", function()
      ScheduleLayout()
    end)
    frame:HookScript("OnHide", function(self)
      self.cbHeldHeight, self.cbHeldColumns = nil, nil -- fits the sections again next time it opens
    end)
  end
  hooked = true
  return true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  InstallHook()
  ScheduleLayout()
end)

FTK.CleanBankRefresh = ScheduleLayout

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Clean Bank",
  description = "Groups the bank into Quest Items, Reagents, Crafting, equipment sets, Gear, General, Junk, and Empty.",
  defaultEnabled = true,
  onEnable = function()
    InstallHook()
    events:RegisterEvent("BANKFRAME_OPENED")
    events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    events:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
    events:RegisterEvent("BAG_UPDATE")
    events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    ScheduleLayout()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    RestoreBank()
  end,
})
