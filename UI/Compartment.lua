local ADDON_NAME, ns = ...

-- Entry in Blizzard's addon compartment (the minimap's addon dropdown), declared in the TOC
-- (## AddonCompartmentFunc / FuncOnEnter / FuncOnLeave). Instead of a minimap button: no clutter, no
-- libraries (decided in review). Blizzard calls these by global name
-- (Blizzard_Minimap/Mainline/AddonCompartment.lua:113-143): click with (addonName, mouse button),
-- enter and leave with (addonName, menu button).

local function toggleMinimized()
  ns.DB.char.minimized = not ns.DB.char.minimized
  ns.Stack:Request(false, true)
end

function BubbleQuest_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then
    toggleMinimized()
  else
    ns.Settings:Open()
  end
end

function BubbleQuest_OnAddonCompartmentEnter(addon, menuButton)
  if not ns.Tooltips:Take(menuButton, "ANCHOR_LEFT", function()
    BubbleQuest_OnAddonCompartmentEnter(addon, menuButton)
  end) then
    return
  end
  GameTooltip:SetText("BubbleQuest", 1, 1, 1)
  GameTooltip:AddLine("Left-click: settings", 0.8, 0.8, 0.8)
  GameTooltip:AddLine(ns.DB.char.minimized and "Right-click: show the cards" or "Right-click: minimize the cards",
    0.8, 0.8, 0.8)
  GameTooltip:Show()
end

function BubbleQuest_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end
