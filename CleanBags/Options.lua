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

Kit.Register(page)

CB.RefreshOptions = function() page:Refresh() end

SLASH_CLEANBAGS1 = "/cleanbags"
SlashCmdList["CLEANBAGS"] = function()
  Kit.Open(page)
end
