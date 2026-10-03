--[[
  Drag guard. While an item from a sorted bag or bank slot is on the cursor, the slots of other sections are dimmed
  and stop taking the drop: dropping onto them would swap the two items' slots, and each would then show up in a
  different spot of its own section. Slots of the same section and empty slots still take it.
]]

local _, FTK = ...

local DIMMED_ALPHA = 0.35

local tracked = setmetatable({}, { __mode = "k" }) -- item button -> { section, bag, slot, empty }
local dimmed = setmetatable({}, { __mode = "k" })

-- Called by the bag and bank layouts for every slot they place
function FTK.TrackSlot(button, section, bag, slot, empty)
  local entry = tracked[button]
  if not entry then
    entry = {}
    tracked[button] = entry
  end
  entry.section, entry.bag, entry.slot, entry.empty = section, bag, slot, empty
end

local function Restore(button)
  dimmed[button] = nil
  button:EnableMouse(true)
  button:SetAlpha(1)
end

-- Forget the slots of a layout that was turned off (all of them when no parent is given)
function FTK.UntrackSlots(parent)
  for button in pairs(tracked) do
    if not parent or button:GetParent() == parent then
      if dimmed[button] then
        Restore(button)
      end
      tracked[button] = nil
    end
  end
end

local function IsLocked(bag, slot)
  if not (bag and slot and C_Container and C_Container.GetContainerItemInfo) then
    return false
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or type(info) ~= "table" then
    return false
  end
  local locked = info.isLocked
  if issecretvalue and issecretvalue(locked) then
    return false
  end
  return locked == true
end

-- The section of the sorted slot the cursor's item was picked up from (that slot is locked while it's carried)
local function CarriedSection()
  if not (CursorHasItem and CursorHasItem()) then
    return nil
  end
  for button, entry in pairs(tracked) do
    if not entry.empty and button:IsVisible() and IsLocked(entry.bag, entry.slot) then
      return entry.section
    end
  end
  return nil
end

local function Update()
  local carried = CarriedSection()
  for button, entry in pairs(tracked) do
    local block = carried ~= nil and not entry.empty and entry.section ~= carried and button:IsVisible()
    if block then
      dimmed[button] = true
      button:EnableMouse(false)
      button:SetAlpha(DIMMED_ALPHA)
    elseif dimmed[button] then
      Restore(button)
    end
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CURSOR_CHANGED")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:SetScript("OnEvent", Update)
