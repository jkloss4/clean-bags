--[[
  Splits the combined backpack into labeled groups:
  Quest Items, Reagents, Crafting, one section per saved equipment set,
  Gear, General, Junk (poor quality), then Empty.

  Only runs while the combined backpack is the bag UI.
  Item buttons stay Blizzard's buttons, so click, drag, and tooltips
  keep working. A secret item id is left in General.
]]

local _, FTK = ...

local MODULE_ID = "BagSections"
local ITEM_GAP_X = 5
local ITEM_GAP_Y = 5
local HEADER_H = 20
local SECTION_GAP = 8
local TOP_OFFSET = 68
local BOTTOM_PAD = 28

local hooked = false
local layingOut = false
local headerPool = {}
local headerUsed = 0

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

local function IsSecret(value)
  if value == nil or not issecretvalue then
    return false
  end
  local ok, secret = pcall(issecretvalue, value)
  return ok and secret == true
end

local function PlainNumber(value)
  if type(value) ~= "number" or IsSecret(value) then
    return nil
  end
  local ok, valid = pcall(function()
    return value == value
  end)
  if not ok or valid ~= true then
    return nil
  end
  return value
end

local function PlainString(value)
  if type(value) ~= "string" or value == "" or IsSecret(value) then
    return nil
  end
  return value
end

local function UsingCombinedBags()
  if ContainerFrameSettingsManager and ContainerFrameSettingsManager.IsUsingCombinedBags then
    local ok, value = pcall(ContainerFrameSettingsManager.IsUsingCombinedBags, ContainerFrameSettingsManager)
    if ok and not IsSecret(value) then
      return value == true
    end
  end
  if GetCVarBool then
    local ok, value = pcall(GetCVarBool, "combinedBags")
    if ok and not IsSecret(value) then
      return value == true
    end
  end
  return false
end

local function CombinedFrame()
  local frame = _G.ContainerFrameCombinedBags
  if frame and frame.IsCombinedBagContainer and frame:IsCombinedBagContainer() then
    return frame
  end
  return nil
end

local function ItemClass(itemID)
  if not itemID or not (C_Item and C_Item.GetItemInfoInstant) then
    return nil
  end
  local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
  if not ok then
    return nil
  end
  return PlainNumber(classID)
end

local function ItemTypeName(itemID)
  if not itemID or not (C_Item and C_Item.GetItemInfoInstant) then
    return nil
  end
  local ok, _, itemType = pcall(C_Item.GetItemInfoInstant, itemID)
  if not ok then
    return nil
  end
  return PlainString(itemType)
end

local function MaterialKind(itemID)
  local classID = ItemClass(itemID)
  local itemClass = Enum and Enum.ItemClass
  local reagentClass = (itemClass and itemClass.Reagent) or 5
  local tradeClass = (itemClass and itemClass.Tradegoods) or 7
  if classID == reagentClass then
    return "spellreagent"
  end
  if classID == tradeClass then
    return "reagent"
  end
  local itemType = ItemTypeName(itemID)
  if itemType == "Reagent" then
    return "spellreagent"
  end
  if itemType == "Trade Goods" then
    return "reagent"
  end
  return nil
end

local function IsConsumable(itemID)
  local classID = ItemClass(itemID)
  local consumableClass = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
  if classID == consumableClass then
    return true
  end
  return ItemTypeName(itemID) == "Consumable"
end

local function EquipLoc(itemID)
  if not itemID or not (C_Item and C_Item.GetItemInfoInstant) then
    return nil
  end
  local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, itemID)
  if not ok then
    return nil
  end
  return PlainString(equipLoc)
end

local function IsGear(itemID)
  local classID = ItemClass(itemID)
  local itemClass = Enum and Enum.ItemClass
  local weapon = (itemClass and itemClass.Weapon) or 2
  local armor = (itemClass and itemClass.Armor) or 4
  if classID ~= weapon and classID ~= armor then
    return false
  end
  local loc = EquipLoc(itemID)
  if loc == "INVTYPE_BAG" or loc == "INVTYPE_QUIVER" or loc == "INVTYPE_AMMO" then
    return false
  end
  return true
end

-- Quivers and ammo pouches: the bag family is 1 (arrows) or 2 (bullets), or the equipped bag's slot is a quiver.
-- The backpack (bag 0) never is.
local function IsQuiverBag(bag)
  if not bag or bag <= 0 then
    return false
  end
  if C_Container and C_Container.GetContainerNumFreeSlots and bit and bit.band then
    local ok, _, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
    family = ok and PlainNumber(family) or nil
    if family and bit.band(family, 3) ~= 0 then
      return true
    end
  end
  if C_Container and C_Container.ContainerIDToInventoryID and GetInventoryItemID then
    local ok, invSlot = pcall(C_Container.ContainerIDToInventoryID, bag)
    invSlot = ok and PlainNumber(invSlot) or nil
    if invSlot then
      local idOk, itemID = pcall(GetInventoryItemID, "player", invSlot)
      itemID = idOk and PlainNumber(itemID) or nil
      if itemID and EquipLoc(itemID) == "INVTYPE_QUIVER" then
        return true
      end
    end
  end
  return false
end

local function IsQuestClass(classID)
  local itemClass = Enum and Enum.ItemClass
  if itemClass and itemClass.Questitem and classID == itemClass.Questitem then
    return true
  end
  return classID == 12
end

local function LocationBagSlot(location)
  location = PlainNumber(location)
  if not location or location <= 1 then
    return nil, nil
  end
  if EquipmentManager_UnpackLocation then
    local ok, player, bank, bags, fourth, fifth, sixth = pcall(EquipmentManager_UnpackLocation, location)
    if ok and bags == true and not IsSecret(bags) then
      local slot, bag
      if type(fourth) == "boolean" then
        slot = PlainNumber(fifth)
        bag = PlainNumber(sixth)
      else
        slot = PlainNumber(fourth)
        bag = PlainNumber(fifth)
      end
      if bag and slot then
        return bag, slot
      end
    end
  end
  if not (bit and bit.band and bit.rshift and bit.lshift) then
    return nil, nil
  end
  local bagsFlag = _G.ITEM_INVENTORY_LOCATION_BAGS or 0x400000
  local bankFlag = _G.ITEM_INVENTORY_LOCATION_BANK or 0x200000
  local playerFlag = _G.ITEM_INVENTORY_LOCATION_PLAYER or 0x100000
  local shift = _G.ITEM_INVENTORY_BAG_BIT_OFFSET or 8
  if bit.band(location, bagsFlag) == 0 or bit.band(location, bankFlag) ~= 0 then
    return nil, nil
  end
  local packed = location - bagsFlag
  if bit.band(location, playerFlag) ~= 0 then
    packed = packed - playerFlag
  end
  local bag = bit.rshift(packed, shift)
  local slot = packed - bit.lshift(bag, shift)
  bag = PlainNumber(bag)
  slot = PlainNumber(slot)
  if bag and slot then
    return bag, slot
  end
  return nil, nil
end

local function RememberItemID(map, itemID, setName)
  itemID = PlainNumber(itemID)
  if itemID and itemID > 0 and not map[itemID] then
    map[itemID] = setName
  end
end

local function EquipmentSetMaps()
  local byItem = {}
  local bySlot = {}
  local api = C_EquipmentSet
  if not (api and api.GetEquipmentSetInfo) then
    return byItem, bySlot
  end
  local setIDs = {}
  if api.GetEquipmentSetIDs then
    local ok, ids = pcall(api.GetEquipmentSetIDs)
    if ok and type(ids) == "table" then
      local index
      for index = 1, #ids do
        local setID = PlainNumber(ids[index])
        if setID then
          setIDs[#setIDs + 1] = setID
        end
      end
    end
  end
  if #setIDs == 0 and api.GetNumEquipmentSets then
    local ok, count = pcall(api.GetNumEquipmentSets)
    count = ok and PlainNumber(count) or nil
    local index
    if count and count > 0 then
      for index = 0, count do
        setIDs[#setIDs + 1] = index
      end
    end
  end
  local sets = {}
  local index
  for index = 1, #setIDs do
    local infoOk, name, _, setID = pcall(api.GetEquipmentSetInfo, setIDs[index])
    name = infoOk and PlainString(name) or nil
    setID = infoOk and PlainNumber(setID) or PlainNumber(setIDs[index])
    if name and setID then
      local seen = false
      local existing
      for existing = 1, #sets do
        if sets[existing].id == setID then
          seen = true
        end
      end
      if not seen then
        sets[#sets + 1] = { name = name, id = setID }
      end
    end
  end
  table.sort(sets, function(a, b)
    return a.name < b.name
  end)
  for index = 1, #sets do
    local set = sets[index]
    if api.GetItemIDs then
      local idsOk, ids = pcall(api.GetItemIDs, set.id)
      if idsOk and type(ids) == "table" then
        local slot
        for slot = 0, 19 do
          RememberItemID(byItem, ids[slot], set.name)
        end
        for _, itemID in pairs(ids) do
          RememberItemID(byItem, itemID, set.name)
        end
      end
    end
    if api.GetItemLocations then
      local locOk, locations = pcall(api.GetItemLocations, set.id)
      if locOk and type(locations) == "table" then
        local slot
        for slot = 0, 19 do
          local bag, bagSlot = LocationBagSlot(locations[slot])
          if bag and bagSlot then
            local key = (bag * 100) + bagSlot
            if not bySlot[key] then
              bySlot[key] = set.name
            end
          end
        end
      end
    end
  end
  return byItem, bySlot
end

local function ContainerSetName(bag, slot)
  if not (C_Container and C_Container.GetContainerItemEquipmentSetInfo) then
    return nil
  end
  local ok, inSet, setList = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
  if not ok then
    return nil
  end
  if IsSecret(inSet) or (inSet ~= true and type(setList) ~= "table" and type(setList) ~= "string") then
    return nil
  end
  if type(setList) == "string" then
    local name = PlainString(setList)
    if not name then
      return nil
    end
    local first = name:match("^[^,]+")
    if first then
      first = first:gsub("^%s+", ""):gsub("%s+$", "")
    end
    return PlainString(first)
  end
  if type(setList) == "table" then
    local index
    for index = 1, #setList do
      local name = PlainString(setList[index])
      if name then
        return name
      end
    end
  end
  return nil
end

local function ButtonBagSlot(button)
  local bag, slot
  if button.GetBagID then
    local ok, value = pcall(button.GetBagID, button)
    if ok then
      bag = PlainNumber(value)
    end
  end
  if button.GetID then
    local ok, value = pcall(button.GetID, button)
    if ok then
      slot = PlainNumber(value)
    end
  end
  return bag, slot
end

local function ReadItem(bag, slot)
  if not bag or not slot or not (C_Container and C_Container.GetContainerItemInfo) then
    return nil
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or type(info) ~= "table" then
    return nil
  end
  local itemID = PlainNumber(info.itemID)
  if not itemID then
    return nil
  end
  local quality = PlainNumber(info.quality)
  local quest = false
  if C_Container.GetContainerItemQuestInfo then
    local questOk, questInfo = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if questOk and type(questInfo) == "table" then
      local questID = PlainNumber(questInfo.questID)
      local isQuest = questInfo.isQuestItem
      if not IsSecret(isQuest) and isQuest == true then
        quest = true
      elseif questID and questID > 0 then
        quest = true
      end
    end
  end
  return {
    itemID = itemID,
    quality = quality,
    quest = quest,
  }
end

local function CategoryFor(item, bag, slot, setByItem, setBySlot)
  if item.quest or IsQuestClass(ItemClass(item.itemID)) then
    return "quest"
  end
  if IsConsumable(item.itemID) then
    return "consumable"
  end
  local poor = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor
  if item.quality ~= nil and (item.quality == 0 or (poor ~= nil and item.quality == poor)) then
    return "junk"
  end
  local material = MaterialKind(item.itemID)
  if material then
    return material
  end
  local setName = ContainerSetName(bag, slot)
  if not setName and bag and slot then
    setName = setBySlot[(bag * 100) + slot]
  end
  if not setName then
    setName = setByItem[item.itemID]
  end
  if setName then
    return "set:" .. setName, "Equipment Set: " .. setName
  end
  if IsGear(item.itemID) then
    return "gear"
  end
  return "other"
end

local function CollectButtons(frame)
  local buttons = {}
  if frame.EnumerateValidItems then
    local ok, iter, state, index = pcall(frame.EnumerateValidItems, frame)
    if ok and iter then
      for _, button in iter, state, index do
        if button then
          buttons[#buttons + 1] = button
        end
      end
      if #buttons > 0 then
        return buttons
      end
    end
  end
  if type(frame.Items) == "table" then
    local index
    for index = 1, #frame.Items do
      buttons[#buttons + 1] = frame.Items[index]
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
  local width = button and PlainNumber(button:GetWidth()) or nil
  local height = button and PlainNumber(button:GetHeight()) or nil
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

local function Layout(frame)
  if layingOut or not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
    return
  end
  if not frame or not frame:IsShown() then
    return
  end
  local buttons = CollectButtons(frame)
  if #buttons == 0 then
    return
  end

  layingOut = true
  headerUsed = 0

  local setByItem, setBySlot = EquipmentSetMaps()
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

  local quiverBags = {}
  for index = 1, #buttons do
    local button = buttons[index]
    local bag, slot = ButtonBagSlot(button)
    local item = ReadItem(bag, slot)
    if bag and quiverBags[bag] == nil then
      quiverBags[bag] = IsQuiverBag(bag)
    end
    if bag and quiverBags[bag] then
      -- A quiver's slots, filled or empty, stay together in their own section
      local group = Group("quiver", "Quiver")
      if item then
        group.items[#group.items + 1] = { button = button, itemID = item.itemID, quality = item.quality or 0 }
      else
        group.empties[#group.empties + 1] = button
      end
    elseif not item then
      Group("empty", "Empty").empties[#Group("empty", "Empty").empties + 1] = button
    else
      local category, setTitle = CategoryFor(item, bag, slot, setByItem, setBySlot)
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

  local function SortEntries(list)
    table.sort(list, function(a, b)
      if a.quality ~= b.quality then
        return a.quality > b.quality
      end
      return a.itemID < b.itemID
    end)
  end

  local ordered = {}
  local prefix = { "quest", "consumable", "quiver", "spellreagent", "reagent" }
  for index = 1, #prefix do
    local group = groups[prefix[index]]
    if group and (#group.items > 0 or #group.empties > 0) then
      SortEntries(group.items)
      ordered[#ordered + 1] = group
    end
  end
  local setIDs = {}
  for index = 1, #groupOrder do
    local id = groupOrder[index]
    if id:find("^set:") and groups[id] and #groups[id].items > 0 then
      setIDs[#setIDs + 1] = id
    end
  end
  table.sort(setIDs, function(a, b)
    return groups[a].title < groups[b].title
  end)
  for index = 1, #setIDs do
    SortEntries(groups[setIDs[index]].items)
    ordered[#ordered + 1] = groups[setIDs[index]]
  end
  local gear = groups.gear
  if gear and #gear.items > 0 then
    SortEntries(gear.items)
    ordered[#ordered + 1] = gear
  end
  local general = groups.other
  if general and #general.items > 0 then
    SortEntries(general.items)
    ordered[#ordered + 1] = general
  end
  local junk = groups.junk
  if junk and #junk.items > 0 then
    SortEntries(junk.items)
    ordered[#ordered + 1] = junk
  end
  local empty = groups.empty
  if empty and #empty.empties > 0 then
    ordered[#ordered + 1] = empty
  end

  local columns = 10
  if frame.GetColumns then
    local ok, count = pcall(frame.GetColumns, frame)
    count = ok and PlainNumber(count) or nil
    if count and count >= 4 and count <= 20 then
      columns = count
    end
  end
  local buttonWidth, buttonHeight = ButtonSize(buttons[1])
  local gridWidth = (columns * buttonWidth) + ((columns - 1) * ITEM_GAP_X)
  local cursor = TOP_OFFSET

  for index = 1, #ordered do
    local group = ordered[index]
    local header = AcquireHeader(frame)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -cursor)
    local count = #group.items
    if group.id == "quiver" then
      count = count .. "/" .. (#group.items + #group.empties) -- used / total slots
    elseif count == 0 then
      count = #group.empties
    end
    header.label:ClearAllPoints()
    header.label:SetPoint("LEFT", header, "LEFT", 24, 0)
    header.label:SetText(group.title .. " (" .. count .. ")")
    header:SetWidth(gridWidth)
    if FTK.QuickDrop and FTK.QuickDrop.Attach then
      FTK.QuickDrop:Attach(header, group.items, "deposit", group.title, ButtonBagSlot)
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
      local x = 9 + (column * (buttonWidth + ITEM_GAP_X))
      local y = -(cursor + (row * (buttonHeight + ITEM_GAP_Y)))
      Place(placed[itemIndex], frame, x, y)
    end
    local rows = math.ceil(#placed / columns)
    if rows < 1 then
      rows = 1
    end
    cursor = cursor + (rows * buttonHeight) + ((rows - 1) * ITEM_GAP_Y) + SECTION_GAP
  end

  HideUnusedHeaders()
  local height = cursor + BOTTOM_PAD
  if height < 160 then
    height = 160
  end
  frame:SetHeight(height)
  layingOut = false
end

local function RequestLayout()
  if not FTK:IsEnabled(MODULE_ID) or not UsingCombinedBags() then
    return
  end
  local frame = CombinedFrame()
  if frame and frame:IsShown() then
    Layout(frame)
  end
end

local function ScheduleLayout()
  RequestLayout()
  if not (C_Timer and C_Timer.After) then
    return
  end
  C_Timer.After(0, RequestLayout)
  C_Timer.After(0.1, RequestLayout)
end

local function HookBagOpen()
  local frame = _G.ContainerFrameCombinedBags
  if not frame or frame.ftkBagManagerShow or not frame.HookScript then
    return
  end
  frame.ftkBagManagerShow = true
  frame:HookScript("OnShow", function()
    ScheduleLayout()
  end)
end

local function RestoreBlizzardLayout()
  local frame = CombinedFrame()
  if not frame then
    HideUnusedHeaders()
    headerUsed = 0
    HideUnusedHeaders()
    return
  end
  headerUsed = 0
  HideUnusedHeaders()
  if frame.UpdateFrameSize then
    pcall(frame.UpdateFrameSize, frame)
  end
  if frame.UpdateItemLayout then
    pcall(frame.UpdateItemLayout, frame)
  end
end

local function InstallHook()
  if hooked or not hooksecurefunc or not ContainerFrameMixin or not ContainerFrameMixin.UpdateItemLayout then
    return hooked
  end
  hooksecurefunc(ContainerFrameMixin, "UpdateItemLayout", function(self)
    if layingOut or not FTK:IsEnabled(MODULE_ID) then
      return
    end
    if self and self.IsCombinedBagContainer and self:IsCombinedBagContainer() and UsingCombinedBags() then
      Layout(self)
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          if self:IsShown() then
            Layout(self)
          end
        end)
      end
    end
  end)
  HookBagOpen()
  if OpenAllBags then
    hooksecurefunc("OpenAllBags", ScheduleLayout)
  end
  if ToggleBackpack then
    hooksecurefunc("ToggleBackpack", ScheduleLayout)
  end
  hooked = true
  return true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  InstallHook()
  HookBagOpen()
  if event == "USE_COMBINED_BAGS_CHANGED" and not UsingCombinedBags() then
    RestoreBlizzardLayout()
    return
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, RequestLayout)
  else
    RequestLayout()
  end
end)

FTK.CleanBagRules = {
  CategoryFor = CategoryFor,
  EquipmentSetMaps = EquipmentSetMaps,
  ReadItem = ReadItem,
  PlainNumber = PlainNumber,
}

FTK.CleanBagsRefresh = ScheduleLayout

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Clean Bags",
  description = "Groups the combined backpack into Quest Items, Reagents, Crafting, equipment sets, Gear, General, Junk, and Empty.",
  defaultEnabled = true,
  onEnable = function()
    InstallHook()
    events:RegisterEvent("BAG_UPDATE")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    events:RegisterEvent("USE_COMBINED_BAGS_CHANGED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    RequestLayout()
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    RestoreBlizzardLayout()
  end,
})
