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

-- Profession tools that are plain items (not the Profession item class or a fishing pole):
-- skinning knives, mining picks, smithing hammers, enchanting rods, engineering and alchemy tools
local PROFESSION_TOOLS = {
  [7005] = true, [12709] = true, [19901] = true, -- Skinning Knife, Finkle's Skinner, Zulian Slicer
  [2901] = true, [778] = true, [756] = true, [1959] = true, [20723] = true, -- Mining Pick and other picks
  [5956] = true, -- Blacksmith Hammer
  [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- Runed enchanting rods
  [22461] = true, [22462] = true, [22463] = true, [44452] = true,
  [6219] = true, [10498] = true, -- Arclight Spanner, Gyromatic Micro-Adjustor
  [9149] = true, -- Philosopher's Stone
  [4471] = true, -- Flint and Tinder
  [20815] = true, -- Jeweler's Kit
  [40772] = true, [40892] = true, [40893] = true, -- Gnomish Army Knife, Hammer Pick, Bladed Pickaxe
}

local function IsProfessionTool(itemID)
  if PROFESSION_TOOLS[itemID] then
    return true
  end
  local classID = ItemClass(itemID)
  local itemClass = Enum and Enum.ItemClass
  if itemClass and itemClass.Profession and classID == itemClass.Profession then
    return true -- profession tools and accessories
  end
  if classID == ((itemClass and itemClass.Weapon) or 2) then
    local ok, _, _, _, _, _, _, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
    local fishingPole = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
    if ok and PlainNumber(subclassID) == fishingPole then
      return true
    end
  end
  local loc = EquipLoc(itemID)
  return loc == "INVTYPE_PROFESSION_TOOL" or loc == "INVTYPE_PROFESSION_GEAR"
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
  if IsProfessionTool(item.itemID) then
    return "profession"
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

-- Within a section: by quality (then item), or in bag slot order so items can be rearranged by dragging them
local function SortEntries(list)
  if FTK:ItemOrder() == "slot" then
    table.sort(list, function(a, b)
      if a.bag ~= b.bag then
        return (a.bag or 0) < (b.bag or 0)
      end
      return (a.slot or 0) < (b.slot or 0)
    end)
    return
  end
  table.sort(list, function(a, b)
    if a.quality ~= b.quality then
      return a.quality > b.quality
    end
    return a.itemID < b.itemID
  end)
end

-- The non-empty groups in the order chosen in the options; "sets" places every equipment set's group, by name
local function OrderGroups(groups, groupOrder)
  local ordered = {}
  for _, id in ipairs(FTK:SectionOrder()) do
    if id == "sets" then
      local setIDs = {}
      for index = 1, #groupOrder do
        local setID = groupOrder[index]
        if setID:find("^set:") and #groups[setID].items > 0 then
          setIDs[#setIDs + 1] = setID
        end
      end
      table.sort(setIDs, function(a, b)
        return groups[a].title < groups[b].title
      end)
      for index = 1, #setIDs do
        SortEntries(groups[setIDs[index]].items)
        ordered[#ordered + 1] = groups[setIDs[index]]
      end
    else
      local group = groups[id]
      if group and (#group.items > 0 or #group.empties > 0) then
        SortEntries(group.items)
        ordered[#ordered + 1] = group
      end
    end
  end
  return ordered
end

local SCREEN_MARGIN = 10
local GRID_SIDE = 9 -- space between the window's edges and the item grid

-- Height of the sections laid out with this many columns
local function SectionsHeight(ordered, columns, buttonHeight)
  local height = TOP_OFFSET
  for index = 1, #ordered do
    local group = ordered[index]
    local rows = math.max(1, math.ceil((#group.items + #group.empties) / columns))
    height = height + HEADER_H + 4 + (rows * buttonHeight) + ((rows - 1) * ITEM_GAP_Y) + SECTION_GAP
  end
  return math.max(height + BOTTOM_PAD, 160)
end

-- Blizzard's column count, or more when the sections wouldn't fit between the window's bottom (where Blizzard
-- anchors it) and the top of the screen: the window gets wider instead of running off the screen. It never gets
-- wider than the room to the left of its right edge.
local function FitColumns(frame, ordered, columns, buttonWidth, buttonHeight)
  local bottom, right = PlainNumber(frame:GetBottom()), PlainNumber(frame:GetRight())
  local frameScale, uiScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
  if not bottom or not right or not frameScale or frameScale <= 0 then
    return columns
  end
  local screenTop = UIParent:GetTop() * uiScale / frameScale
  local availableHeight = screenTop - bottom - SCREEN_MARGIN
  local maxColumns = math.floor((right - SCREEN_MARGIN - (2 * GRID_SIDE) + ITEM_GAP_X) / (buttonWidth + ITEM_GAP_X))
  while columns < maxColumns and SectionsHeight(ordered, columns, buttonHeight) > availableHeight do
    columns = columns + 1
  end
  return columns
end

-- Item Type grouping: sections by kind of item (quest, consumable, gear...), in the chosen section order
local function GroupByType(buttons)
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
    local section
    if bag and quiverBags[bag] == nil then
      quiverBags[bag] = IsQuiverBag(bag)
    end
    if bag and quiverBags[bag] then
      -- A quiver's slots, filled or empty, stay together in their own section
      local group = Group("quiver", "Quiver")
      section = "quiver"
      if item then
        group.items[#group.items + 1] = { button = button, itemID = item.itemID, quality = item.quality or 0, bag = bag, slot = slot }
      else
        group.empties[#group.empties + 1] = button
      end
    elseif not item then
      Group("empty", "Empty").empties[#Group("empty", "Empty").empties + 1] = button
      section = "empty"
    else
      local category, setTitle = CategoryFor(item, bag, slot, setByItem, setBySlot)
      local title = setTitle or FTK.SECTION_NAMES[category] or FTK.SECTION_NAMES.other
      local group = Group(category, title)
      group.items[#group.items + 1] = { button = button, itemID = item.itemID, quality = item.quality or 0, bag = bag, slot = slot }
      section = category
    end
    FTK.TrackSlot(button, section, bag, slot, item == nil)
  end

  return OrderGroups(groups, groupOrder)
end

-- The name shown for a bag's section: the bag item's name, else Backpack / Bank / Bag n
local function BagTitle(bag)
  if C_Container and C_Container.GetBagName then
    local ok, name = pcall(C_Container.GetBagName, bag)
    name = ok and PlainString(name) or nil
    if name then
      return name
    end
  end
  if bag == 0 then
    return BACKPACK_TOOLTIP or "Backpack"
  end
  if bag == ((Enum and Enum.BagIndex and Enum.BagIndex.Bank) or -1) then
    return BANK or "Bank"
  end
  return "Bag " .. bag
end

-- Bag grouping (Guild Wars 2 style): one section per bag, in bag order, with every slot, filled or empty, in slot
-- order. Items can be dragged between any slots, so the drag guard sees every slot as one section ("bags").
-- .swapItems holds just the filled slots, for the Quick Swap button.
local function GroupByBag(buttons, bagSlot)
  local groups, bags = {}, {}
  for index = 1, #buttons do
    local button = buttons[index]
    local bag, slot = bagSlot(button)
    if bag and slot then
      local group = groups[bag]
      if not group then
        group = { id = "bag", title = BagTitle(bag), items = {}, empties = {}, swapItems = {} }
        groups[bag] = group
        bags[#bags + 1] = bag
      end
      local item = ReadItem(bag, slot)
      local entry = { button = button, itemID = item and item.itemID, quality = item and item.quality or 0, bag = bag, slot = slot }
      group.items[#group.items + 1] = entry
      if item then
        group.swapItems[#group.swapItems + 1] = entry
      end
      FTK.TrackSlot(button, "bags", bag, slot, item == nil)
    end
  end
  table.sort(bags)
  local ordered = {}
  for index = 1, #bags do
    local group = groups[bags[index]]
    table.sort(group.items, function(a, b)
      return a.slot < b.slot
    end)
    ordered[#ordered + 1] = group
  end
  return ordered
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

  local ordered
  if FTK:GroupBy() == "bag" then
    ordered = GroupByBag(buttons, ButtonBagSlot)
  else
    ordered = GroupByType(buttons)
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
  columns = FitColumns(frame, ordered, columns, buttonWidth, buttonHeight)
  -- The items plus GRID_SIDE on each side. (Blizzard's CalculateWidth pads 15 in all, 8 left and 7 right; with
  -- the sections starting 9 in, that left a full row touching the right border.)
  frame:SetWidth((columns * buttonWidth) + ((columns - 1) * ITEM_GAP_X) + (2 * GRID_SIDE))
  local cursor = TOP_OFFSET

  for index = 1, #ordered do
    local group = ordered[index]
    local header = AcquireHeader(frame)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", GRID_SIDE, -cursor)
    local count = #group.items
    if group.id == "quiver" or group.id == "bag" then
      count = (group.swapItems and #group.swapItems or count) .. "/" .. (#group.items + #group.empties) -- used / total slots
    elseif count == 0 then
      count = #group.empties
    end
    header.label:ClearAllPoints()
    header.label:SetPoint("LEFT", header, "LEFT", 24, 0)
    header.label:SetText(group.title .. " (" .. count .. ")")
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -cursor) -- right inset to match the left visually
    if FTK.QuickDrop and FTK.QuickDrop.Attach then
      FTK.QuickDrop:Attach(header, group.swapItems or group.items, "deposit", group.title, ButtonBagSlot)
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
      local x = GRID_SIDE + (column * (buttonWidth + ITEM_GAP_X))
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
  -- Blizzard's Clean Up Bags button reorders the bag slots: only useful when sections show items in slot order
  local sortButton = _G.BagItemAutoSortButton
  if sortButton and sortButton:GetParent() == frame then
    sortButton:SetShown(FTK:ShowsSlotOrder())
  end
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
  FTK.UntrackSlots()
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
  if frame.UpdateSearchBox then
    pcall(frame.UpdateSearchBox, frame) -- shows the Clean Up Bags button again
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
  -- Also hook the combined bag frame itself: it copied the mixin's methods when it was created, so the hook above
  -- doesn't reach it. Re-sorting right after Blizzard updates the items, sizes the frame or lays out the grid keeps
  -- the sections in the same frame, instead of Blizzard's grid flickering in for a frame first.
  local combined = _G.ContainerFrameCombinedBags
  if combined then
    for _, method in ipairs({ "UpdateItems", "UpdateItemLayout", "UpdateFrameSize", "UpdateSearchBox" }) do
      if type(combined[method]) == "function" then
        hooksecurefunc(combined, method, function(self)
          if not layingOut and FTK:IsEnabled(MODULE_ID) and UsingCombinedBags() then
            Layout(self)
          end
        end)
      end
    end
  end
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
  OrderGroups = OrderGroups,
  GroupByBag = GroupByBag,
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
