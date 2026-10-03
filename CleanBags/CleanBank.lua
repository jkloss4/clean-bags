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
local BOTTOM_PAD = 100

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
    local line = header:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    if line.SetColorTexture then
      line:SetColorTexture(0.78, 0.64, 0.28, 0.9)
    end
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 24, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(0.95, 0.82, 0.4)
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

local function Layout(frame, panel)
  if layingOut or not FTK:IsEnabled(MODULE_ID) or not frame or not panel or not panel:IsShown() then
    return
  end
  local buttons = CollectButtons(panel)
  if #buttons == 0 then
    return
  end
  layingOut = true
  headerUsed = 0
  if not panel.ftkBaseHeight then
    panel.ftkBaseHeight = Rules.PlainNumber(panel:GetHeight())
    frame.ftkBaseHeight = Rules.PlainNumber(frame:GetHeight())
  end

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
    else
      local category, setTitle = Rules.CategoryFor(item, bag, slot, setByItem, setBySlot)
      local title = setTitle or "General"
      if category == "quest" then
        title = "Quest Items"
      elseif category == "consumable" then
        title = "Consumables"
      elseif category == "junk" then
        title = "Junk"
      elseif category == "spellreagent" then
        title = "Reagents"
      elseif category == "reagent" then
        title = "Crafting"
      elseif category == "gear" then
        title = "Gear"
      end
      local group = Group(category, title)
      group.items[#group.items + 1] = { button = button, itemID = item.itemID, quality = item.quality or 0 }
    end
  end

  local ordered = Rules.OrderGroups(groups, groupOrder)

  local buttonWidth, buttonHeight = ButtonSize(buttons[1])
  local panelWidth = Rules.PlainNumber(panel:GetWidth()) or 400
  local columns = math.floor((panelWidth - 24) / (buttonWidth + ITEM_GAP_X))
  if columns < 8 then
    columns = 8
  end
  if columns > 16 then
    columns = 16
  end
  local cursor = TOP_OFFSET

  for index = 1, #ordered do
    local group = ordered[index]
    local header = AcquireHeader(panel)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -cursor)
    local count = #group.items
    if count == 0 then
      count = #group.empties
    end
    header.label:ClearAllPoints()
    header.label:SetPoint("LEFT", header, "LEFT", 24, 0)
    header.label:SetText(group.title .. " (" .. count .. ")")
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -cursor) -- same inset as the left
    if FTK.QuickDrop and FTK.QuickDrop.Attach then
      FTK.QuickDrop:Attach(header, group.items, "withdraw", group.title, function(button)
        return ButtonBagSlot(button, panel)
      end)
    end
    -- Title sits against the left edge unless the Quick Swap button is showing there
    local swap = header.ftkQuickDrop
    header.label:SetPoint("LEFT", header, "LEFT", (swap and swap:IsShown()) and 24 or 2, 0)
    cursor = cursor + HEADER_H + 4

    local placed = {}
    local itemIndex
    for itemIndex = 1, #group.items do
      placed[#placed + 1] = group.items[itemIndex].button
    end
    for itemIndex = 1, #group.empties do
      placed[#placed + 1] = group.empties[itemIndex]
    end
    for itemIndex = 1, #placed do
      local column = (itemIndex - 1) % columns
      local row = math.floor((itemIndex - 1) / columns)
      local x = 12 + (column * (buttonWidth + ITEM_GAP_X))
      local y = -(cursor + (row * (buttonHeight + ITEM_GAP_Y)))
      Place(placed[itemIndex], panel, x, y)
    end
    local rows = math.ceil(#placed / columns)
    if rows < 1 then
      rows = 1
    end
    cursor = cursor + (rows * buttonHeight) + ((rows - 1) * ITEM_GAP_Y) + SECTION_GAP
  end

  HideUnusedHeaders()
  local height = cursor + BOTTOM_PAD
  if panel.ftkBaseHeight and height < panel.ftkBaseHeight then
    height = panel.ftkBaseHeight
  end
  panel:SetHeight(height)
  -- Blizzard's bank Clean Up button only reorders the slots, which the sections hide
  if panel.AutoSortButton then
    panel.AutoSortButton:Hide()
  end
  local chrome = 0
  if frame.ftkBaseHeight and panel.ftkBaseHeight then
    chrome = frame.ftkBaseHeight - panel.ftkBaseHeight
  end
  if chrome < 0 or chrome > 180 then
    chrome = 36
  end
  frame:SetHeight(height + chrome)
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
  headerUsed = 0
  HideUnusedHeaders()
  local frame, panel = BankPanel()
  if panel and panel.RefreshBankPanel then
    pcall(panel.RefreshBankPanel, panel)
  end
  if panel and panel.AutoSortButton then
    panel.AutoSortButton:Show()
  end
  if frame and frame.ftkBaseHeight then
    frame:SetHeight(frame.ftkBaseHeight)
  end
  if panel and panel.ftkBaseHeight then
    panel:SetHeight(panel.ftkBaseHeight)
  end
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
