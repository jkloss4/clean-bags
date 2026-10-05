--[[
  Quick Swap. While the bank is open, Clean Bags and Clean Bank headers
  get a swap button. The button moves every item in that category from
  bags to the bank, or from the bank to bags.

  Items move one at a time with C_Container.UseContainerItem. The bank
  type is only read. Nothing writes BankPanel.bankType.
]]

local _, FTK = ...

local MODULE_ID = "QuickDrop"
-- The button shows where it moves the section to: your bags, or the bank (the minimap's banker tracking icon)
local ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local DIRECTION_ICONS = {
  withdraw = ICON,
  deposit = "Interface\\Minimap\\Tracking\\Banker",
}

local session = 0
local moving = false
local queue
local stuck = 0

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

local function BankOpen()
  local frame = _G.BankFrame
  if not frame or not frame.IsShown then
    return false
  end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown == true
end

local function Flag(fn)
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn)
  if not ok or IsSecret(value) then
    return false
  end
  return value == true
end

local function ActiveBankType()
  local frame = _G.BankFrame
  if not frame or not frame.GetActiveBankType then
    return nil
  end
  local ok, value = pcall(frame.GetActiveBankType, frame)
  if not ok or IsSecret(value) then
    return nil
  end
  return PlainNumber(value)
end

local function SlotState(bag, slot)
  if not (C_Container and C_Container.GetContainerItemInfo) then
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
  local locked = info.isLocked
  if IsSecret(locked) then
    locked = true
  end
  return {
    itemID = itemID,
    count = PlainNumber(info.stackCount),
    locked = locked == true,
  }
end

local function IsAccountBank(bankType)
  return bankType ~= nil and Enum and Enum.BankType and bankType == Enum.BankType.Account
end

-- Whether the item in this bag slot may go in the open bank (soulbound items can't go in the Warband bank). True
-- when the game can't say (Forever's bank has no such rule).
local function AllowedInBank(bag, slot, bankType)
  if bankType == nil or not (C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation
      and ItemLocation.CreateFromBagAndSlot) then
    return true
  end
  local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, bankType, ItemLocation:CreateFromBagAndSlot(bag, slot))
  if not ok or IsSecret(allowed) then
    return true
  end
  return allowed ~= false
end

local function MoveSlot(bag, slot)
  local bankType = ActiveBankType()
  if C_Container and C_Container.UseContainerItem then
    if bankType ~= nil then
      local ok = pcall(C_Container.UseContainerItem, bag, slot, nil, bankType)
      if ok then
        return true
      end
    end
    return pcall(C_Container.UseContainerItem, bag, slot)
  end
  if UseContainerItem then
    return pcall(UseContainerItem, bag, slot)
  end
  return false
end

local function Later(delay, token, callback)
  local function run()
    if session ~= token then
      return
    end
    callback()
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, run)
    return
  end
  run()
end

local function StopMove()
  session = session + 1
  moving = false
  queue = nil
  stuck = 0
end

local function MoveNext()
  if not moving or not queue or not FTK:IsEnabled(MODULE_ID) or not BankOpen() then
    moving = false
    queue = nil
    return
  end
  while queue[1] do
    local entry = queue[1]
    local state = SlotState(entry.bag, entry.slot)
    if not state then
      stuck = 0
      table.remove(queue, 1)
    elseif state.locked then
      entry.tries = entry.tries + 1
      if entry.tries > 5 then
        table.remove(queue, 1)
      else
        Later(0.2, session, MoveNext)
        return
      end
    elseif entry.sent and not entry.settled then
      entry.settled = true
      Later(0.45, session, MoveNext)
      return
    elseif entry.sent then
      local sameItem = (not entry.itemID) or state.itemID == entry.itemID
      local shrunk = entry.count and state.count and state.count < entry.count
      if not sameItem then
        stuck = 0
        table.remove(queue, 1)
      elseif shrunk then
        stuck = 0
        entry.count = state.count
        entry.sent = false
        entry.settled = false
        entry.tries = 0
      else
        stuck = stuck + 1
        table.remove(queue, 1)
        if stuck >= 2 then
          moving = false
          queue = nil
          FTK:Print("Quick Swap: stopped because items were not moving.")
          return
        end
      end
    else
      entry.sent = true
      MoveSlot(entry.bag, entry.slot)
      Later(0.15, session, MoveNext)
      return
    end
  end
  moving = false
  queue = nil
end

local HEARTHSTONE_ID = 6948

local function ItemName(itemID)
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok then
      local plain = PlainString(name)
      if plain then
        return plain
      end
    end
  end
  if GetItemInfo then
    local ok, name = pcall(GetItemInfo, itemID)
    if ok then
      return PlainString(name)
    end
  end
  return nil
end

local function IsHearthstone(itemID)
  itemID = PlainNumber(itemID)
  if not itemID then
    return false
  end
  if itemID == HEARTHSTONE_ID then
    return true
  end
  return ItemName(itemID) == "Hearthstone"
end

local function StartMove(moves, direction, title)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  if Flag(InCombatLockdown) then
    FTK:Print("Quick Swap: wait until you leave combat.")
    return
  end
  if Flag(CursorHasItem) then
    FTK:Print("Quick Swap: clear your cursor first.")
    return
  end
  if not BankOpen() then
    FTK:Print("Quick Swap: the bank is not open.")
    return
  end
  StopMove()
  local token = session
  local list = {}
  local skipped = 0
  local bankType = ActiveBankType()
  local index
  for index = 1, #moves do
    local source = moves[index]
    local bag = PlainNumber(source.bag)
    local slot = PlainNumber(source.slot)
    local state = bag and slot and SlotState(bag, slot) or nil
    if state and direction ~= "withdraw" and IsHearthstone(state.itemID) then
      state = nil
    end
    if state and direction ~= "withdraw" and not AllowedInBank(bag, slot, bankType) then
      state = nil -- soulbound items can't go in the Warband bank; they'd stop the move as "not moving"
      skipped = skipped + 1
    end
    if state then
      list[#list + 1] = {
        bag = bag,
        slot = slot,
        itemID = state.itemID,
        count = state.count,
        tries = 0,
        sent = false,
        settled = false,
      }
    end
  end
  local where = direction == "withdraw" and "your bags" or "the bank"
  if direction ~= "withdraw" and IsAccountBank(bankType) then
    where = "the Warband bank"
  end
  local skippedNote = skipped > 0
    and (" " .. skipped .. (skipped == 1 and " item" or " items") .. " can't go in " .. where .. ".") or ""
  if #list == 0 then
    FTK:Print("Quick Swap: nothing in that category to move." .. skippedNote)
    return
  end
  queue = list
  moving = true
  stuck = 0
  if type(title) ~= "string" or title == "" or IsSecret(title) then
    title = "that category"
  end
  FTK:Print("Quick Swap: moving " .. #list .. " " .. title .. " to " .. where .. "." .. skippedNote)
  Later(0.05, token, MoveNext)
end

local function EnsureButton(header)
  local button = header.ftkQuickDrop
  if button then
    return button
  end
  button = CreateFrame("Button", nil, header)
  button:SetSize(16, 16)
  button:SetPoint("LEFT", header, "LEFT", 4, 0)
  button:RegisterForClicks("LeftButtonUp")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexCoord(0, 1, 0, 1)
  local applied = icon:SetTexture(ICON)
  if applied == false and icon.SetColorTexture then
    icon:SetTexCoord(0, 1, 0, 1)
    icon:SetColorTexture(0.85, 0.68, 0.28, 1)
  end
  button.icon = icon
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  if highlight.SetColorTexture then
    highlight:SetColorTexture(1, 0.9, 0.55, 0.35)
  end
  button:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.categoryTitle then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local text
    if self.direction == "withdraw" then
      text = "Move " .. self.categoryTitle .. " to your bags"
    else
      text = "Move " .. self.categoryTitle .. " to the bank"
    end
    GameTooltip:SetText(FTK.Plain(text))
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  button:SetScript("OnMouseDown", function(self)
    if self.icon then
      self.icon:SetAlpha(0.55)
    end
  end)
  button:SetScript("OnMouseUp", function(self)
    if self.icon then
      self.icon:SetAlpha(1)
    end
  end)
  button:SetScript("OnClick", function(self)
    if self.moves then
      StartMove(self.moves, self.direction, self.categoryTitle)
    end
  end)
  button:Hide()
  header.ftkQuickDrop = button
  return button
end

local function Attach(_, header, entries, direction, title, bagSlot)
  if not header then
    return
  end
  local button = EnsureButton(header)
  local moves = {}
  if type(entries) == "table" and type(bagSlot) == "function" then
    local index
    for index = 1, #entries do
      local entry = entries[index]
      local itemButton = entry
      if type(entry) == "table" and type(entry.button) == "table" then
        itemButton = entry.button
      end
      if type(itemButton) == "table" then
        local ok, bag, slot = pcall(bagSlot, itemButton)
        if ok then
          bag = PlainNumber(bag)
          slot = PlainNumber(slot)
          if bag and slot then
            moves[#moves + 1] = { bag = bag, slot = slot }
          end
        end
      end
    end
  end
  local show = FTK:IsEnabled(MODULE_ID) and BankOpen() and #moves > 0
  if not show then
    button.moves = nil
    button:Hide()
    return
  end
  if type(title) ~= "string" or title == "" or IsSecret(title) then
    title = "this category"
  end
  button.moves = moves
  button.direction = direction == "withdraw" and "withdraw" or "deposit"
  if button.icon:SetTexture(DIRECTION_ICONS[button.direction]) == false then
    button.icon:SetTexture(ICON)
  end
  button.categoryTitle = title
  local level = 20
  local parent = header.GetParent and header:GetParent() or nil
  if parent and parent.GetFrameLevel then
    local ok, value = pcall(parent.GetFrameLevel, parent)
    value = ok and PlainNumber(value) or nil
    if value then
      level = value + 20
    end
  end
  if header.SetFrameLevel then
    header:SetFrameLevel(level)
  end
  button:SetFrameLevel(level + 5)
  button:Show()
end

local function RefreshHosts()
  if type(FTK.CleanBagsRefresh) == "function" then
    FTK.CleanBagsRefresh()
  end
  if type(FTK.CleanBankRefresh) == "function" then
    FTK.CleanBankRefresh()
  end
end

local refreshGeneration = 0

local function RefreshWhenBankOpens(attempt, generation)
  if attempt == 0 then
    refreshGeneration = refreshGeneration + 1
    generation = refreshGeneration
  end
  if generation ~= refreshGeneration then
    return
  end
  RefreshHosts()
  if BankOpen() or attempt >= 10 then
    return
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0.1, function()
      RefreshWhenBankOpens(attempt + 1, generation)
    end)
  end
end

local function HookBank()
  local frame = _G.BankFrame
  if not frame or frame.ftkQuickDropHook or not frame.HookScript then
    return false
  end
  frame.ftkQuickDropHook = true
  frame:HookScript("OnShow", function()
    RefreshWhenBankOpens(0)
  end)
  frame:HookScript("OnHide", function()
    StopMove()
    RefreshHosts()
  end)
  return true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
  if not FTK:IsEnabled(MODULE_ID) then
    return
  end
  HookBank()
  if event == "BANKFRAME_CLOSED" then
    StopMove()
    RefreshHosts()
    return
  end
  RefreshWhenBankOpens(0)
end)

FTK.QuickDrop = {
  Attach = Attach,
}

FTK:RegisterModule({
  id = MODULE_ID,
  name = "Quick Swap",
  description = "While the bank is open, adds a swap button on each Clean Bags and Clean Bank category. The button moves that category between your bags and the bank.",
  defaultEnabled = true,
  onEnable = function()
    events:RegisterEvent("BANKFRAME_OPENED")
    events:RegisterEvent("BANKFRAME_CLOSED")
    HookBank()
    if BankOpen() then
      RefreshWhenBankOpens(0)
    else
      RefreshHosts()
    end
  end,
  onDisable = function()
    events:UnregisterAllEvents()
    StopMove()
    RefreshHosts()
  end,
})
