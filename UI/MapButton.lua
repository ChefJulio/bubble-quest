local ADDON_NAME, ns = ...

-- A button on the world map with a menu of map toggles (docs/design/available-quests.md: "the map
-- menu"), like Questie's. Each item is a Map setting, changed through the settings code
-- (ns.Settings:SetValue), so the settings window and Blizzard's panel stay in step.
--
-- Where it sits: in the column of map buttons at the map's top-left. Addons share that column through
-- the Krowi_WorldMapButtons library (Questie embeds it); it's "All Rights Reserved", so it isn't
-- shipped here, but when another addon has loaded it ours joins its column. Otherwise ours goes where
-- that column would put it: under Blizzard's map pin button (Forever moves it to the top-left,
-- Krowi_WorldMapButtons.lua:22-24).
-- Look: the round minimap-button style Questie's uses (its QuestieWorldMapButtonTemplate.xml), with
-- Questmarker's icon.

local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Icon"
local KROWI = "Krowi_WorldMapButtons-1.4"

local MapButton = {}
ns.MapButton = MapButton

-- The menu: { setting id, label } or "-" for a divider. Settings live in UI/SettingsSchema.lua.
local ITEMS = {
  { "QUESTMARKER_MAP_AREAS", "Quest areas" },
  { "QUESTMARKER_MAP_AVAILABLE", "Quests you can pick up" },
  { "QUESTMARKER_MAP_AVAILABLE_TRIVIAL", "Low-level quests", indent = true },
  { "QUESTMARKER_MAP_AVAILABLE_DROPS", "Quests started by a drop", indent = true },
  "-",
  { "QUESTMARKER_MINIMAP_AREAS", "Quest areas on the minimap" },
  { "QUESTMARKER_MINIMAP_GUIDE", "Guide line on the minimap" },
}

local function value(id)
  local entry = ns.SettingsSchema:Find(id)
  return entry ~= nil and entry.get(ns.DB.profile) == true
end

local function openMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Questmarker")
    for _, item in ipairs(ITEMS) do
      if item == "-" then
        root:CreateDivider()
      else
        local id, label = item[1], item[2]
        local checkbox = root:CreateCheckbox((item.indent and "   " or "") .. label,
          function() return value(id) end,
          function() ns.Settings:SetValue(id, not value(id)) end)
        -- The sub-options only matter while "Quests you can pick up" is on.
        if item.indent and not value("QUESTMARKER_MAP_AVAILABLE") then
          checkbox:SetEnabled(false)
        end
      end
    end
    root:CreateDivider()
    root:CreateButton("Map settings...", function() ns.Settings:Open() end)
  end)
end

local function style(button)
  button:SetSize(32, 32)
  button:SetFrameStrata("HIGH")  -- Blizzard's map buttons' strata
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(25, 25)
  background:SetPoint("TOPLEFT", 2, -4)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 6, -6)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", function(self) openMenu(self) end)
  local function showTooltip()
    if ns.Tooltips:Take(button, "ANCHOR_RIGHT", showTooltip) then
      GameTooltip:SetText("Questmarker", 1, 1, 1)
      GameTooltip:AddLine("Click: what Questmarker shows on the maps", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end
  button:SetScript("OnEnter", showTooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function create()
  local map = rawget(_G, "WorldMapFrame")
  if MapButton.button or not map then
    return
  end
  local libStub = rawget(_G, "LibStub")
  local krowi = libStub and libStub:GetLibrary(KROWI, true)
  local button
  if krowi and type(krowi.Add) == "function" then
    -- Joins the shared column; the library calls Refresh after map changes.
    button = krowi:Add(nil, "BUTTON")
    button.Refresh = function() end
  else
    button = CreateFrame("Button", nil, map)
    button:SetPoint("TOPLEFT", map:GetCanvasContainer(), "TOPLEFT", 3, -32)
  end
  style(button)
  MapButton.button = button
end

ns.Events:On("PLAYER_LOGIN", create)
ns.Events:On("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then
    create()
  end
end)
