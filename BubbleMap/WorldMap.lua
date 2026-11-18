local ADDON_NAME, ns = ...

-- Terrain on Blizzard's world map (build step 7): a toggle that shows the real terrain, the minimap's
-- own tiles (Data/Tiles.lua), instead of the painted art on zone maps. Design:
-- docs/design/terrain-map.md ("World map toggle").
--
-- Touching nothing of Blizzard's: our own frame on the map's canvas (WorldMapFrame:GetCanvas()), mouse
-- off, an opaque fill and the tiles. Its frame level is read, not claimed: one above the explored-area
-- pins (PIN_FRAME_LEVEL_MAP_EXPLORATION), so it covers the art and its explored overlays and sits under
-- every other pin, BubbleQuest's quest areas (2004) included. The canvas zooms and pans it with the
-- map. Redrawn on post-hooks only: map changed, shown, canvas resized.
--
-- Where: zone maps on a continent we have tiles for. Continent and world maps keep Blizzard's art (a
-- continent at tile detail is thousands of textures; the art reads better there). Cities show their
-- ground only: their buildings need the WMO tables (later; terrain-map.md).
-- Placing a tile: the zone's world rectangle from its map corners (C_Map.GetWorldPosFromMapPos: x north,
-- y west, as BubbleQuest's Navigation reads it), each tile's world edges into that rectangle's 0-1, times
-- the canvas size.
-- Gamepad UI: off. Blizzard's gamepad code scans every frame on the world map, and addon frames there
-- taint it (docs/research/forever-api-and-questiedb.md: TomTom stays off it the same way).

local TILE_YARDS = 1600 / 3
local GRID = 64
local FILL = { 0.05, 0.06, 0.07, 1 }

local WorldMap = {
  failed = 0,
}
ns.WorldMap = WorldMap

local layer, fill, button
local pool, used = {}, 0

local function gamepad()
  local style = rawget(_G, "C_InputInterfaceStyle")
  return style ~= nil and style.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad
end

local function tile()
  used = used + 1
  local t = pool[used]
  if not t then
    t = layer:CreateTexture(nil, "ARTWORK")
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
    pool[used] = t
  end
  t:Show()
  return t
end

local function clear()
  for i = 1, #pool do
    pool[i]:Hide()
    pool[i].fileID = nil
  end
  used = 0
end

-- The zone's world rectangle: { n0, w0 } at its map's top left, { n1, w1 } at its bottom right, and
-- the instance map (UnitPosition's, the key of Data/Tiles.lua).
local function worldRect(mapID)
  local map0, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
  local map1, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
  if not (a and b) or map0 ~= map1 then
    return nil
  end
  return { n0 = a.x, w0 = a.y, n1 = b.x, w1 = b.y, map = map0 }
end

local function draw()
  clear()
  local map = WorldMapFrame:GetMapID()
  local info = map and C_Map.GetMapInfo(map)
  if not (ns.DB.worldTerrain and not gamepad() and info and info.mapType == Enum.UIMapType.Zone) then
    layer:Hide()
    return
  end
  local rect = worldRect(map)
  local tiles = rect and ns.Tiles.maps[rect.map]
  if not rect or not tiles then
    layer:Hide()
    return
  end
  -- Above the explored-area pins, under every other pin (see the header). Read each time: pins and
  -- levels can be added as the map loads providers.
  local levels = WorldMapFrame:GetPinFrameLevelsManager()
  layer:SetFrameLevel(levels:GetFrameLevelStart("PIN_FRAME_LEVEL_MAP_EXPLORATION") + 1)
  layer:Show()

  local w, h = layer:GetWidth(), layer:GetHeight()
  local function u(west) return (west - rect.w0) / (rect.w1 - rect.w0) * w end
  local function v(north) return (north - rect.n0) / (rect.n1 - rect.n0) * h end
  local c0 = math.floor(32 - math.max(rect.w0, rect.w1) / TILE_YARDS)
  local c1 = math.floor(32 - math.min(rect.w0, rect.w1) / TILE_YARDS)
  local r0 = math.floor(32 - math.max(rect.n0, rect.n1) / TILE_YARDS)
  local r1 = math.floor(32 - math.min(rect.n0, rect.n1) / TILE_YARDS)
  for c = math.max(0, c0), math.min(GRID - 1, c1) do
    for r = math.max(0, r0), math.min(GRID - 1, r1) do
      local fileID = tiles[c * GRID + r]
      if fileID then
        local t = tile()
        if not t:SetTexture(fileID) then
          WorldMap.failed = WorldMap.failed + 1
        end
        -- Tile (c, r) spans west (32 - c) T down to (31 - c) T, north (32 - r) T down to (31 - r) T.
        local left, right = u((32 - c) * TILE_YARDS), u((31 - c) * TILE_YARDS)
        local top, bottom = v((32 - r) * TILE_YARDS), v((31 - r) * TILE_YARDS)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", layer, "TOPLEFT", left, -top)
        t:SetSize(right - left, bottom - top)
      end
    end
  end
end

local function updateButton()
  if not button then
    return
  end
  button:SetShown(not gamepad())
  button.icon:SetDesaturated(not ns.DB.worldTerrain)
  button.icon:SetAlpha(ns.DB.worldTerrain and 1 or 0.7)
end

---Terrain on the world map on or off (the map's button, and the setting).
---@param on boolean
function WorldMap:SetEnabled(on)
  ns.DB.worldTerrain = on
  updateButton()
  if layer and WorldMapFrame:IsShown() then
    draw()
  end
end

local KROWI = "Krowi_WorldMapButtons-1.4"  -- the shared map button column (Questie embeds it)

local function createButton()
  -- In the column of map buttons at the map's top left, under BubbleQuest's (review: at the top right it
  -- sat under Blizzard's filter button, whose name differs on Forever). Through the shared column when
  -- another addon has loaded its library, as BubbleQuest's button does (UI/MapButton.lua; the library
  -- is "All Rights Reserved", so not shipped here); otherwise where it would put us: the slot under
  -- BubbleQuest's button, or BubbleQuest's slot without it. Not AddOverlayFrame: that runs our frame in
  -- Blizzard's secure refresh loop.
  local libStub = rawget(_G, "LibStub")
  local krowi = libStub and libStub:GetLibrary(KROWI, true)
  if krowi and type(krowi.Add) == "function" then
    button = krowi:Add(nil, "BUTTON")
    button.Refresh = function() end
  else
    button = CreateFrame("Button", nil, WorldMapFrame)
    local slot = ns.Quest and 2 or 1  -- BubbleQuest's button takes the first
    button:SetPoint("TOPLEFT", WorldMapFrame:GetCanvasContainer(), "TOPLEFT", 3, -32 * slot)
  end
  -- The round map-button look of BubbleQuest's (and Questie's) button, with a terrain tile as its icon.
  button:SetSize(32, 32)
  button:SetFrameStrata("HIGH")  -- Blizzard's map buttons' strata
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(25, 25)
  background:SetPoint("TOPLEFT", 2, -4)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetSize(20, 20)
  button.icon:SetPoint("TOPLEFT", 6, -6)
  button.icon:SetTexture(ns.Tiles.maps[0] and ns.Tiles.maps[0][32 * GRID + 49] or 134400)  -- Elwynn
  local mask = button:CreateMaskTexture()
  mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
    "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(button.icon)
  button.icon:AddMaskTexture(mask)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
      ns.MapWindow:Toggle()  -- BubbleMap's own map: whole continents, pan and deep zoom
    else
      WorldMap:SetEnabled(not ns.DB.worldTerrain)
    end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Terrain: " .. (ns.DB.worldTerrain and "on" or "off"), 1, 1, 1)
    GameTooltip:AddLine("Left-click: the real terrain on zone maps instead of the painted art.", 0.8, 0.8,
      0.8, true)
    GameTooltip:AddLine("Right-click: BubbleMap's own map (drag to pan across zones, deep zoom).", 0.8, 0.8,
      0.8, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  updateButton()
end

local function setUp()
  local canvas = WorldMapFrame:GetCanvas()
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:EnableMouse(false)
  fill = layer:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(FILL[1], FILL[2], FILL[3], FILL[4])
  layer:Hide()
  createButton()
  hooksecurefunc(WorldMapFrame, "OnMapChanged", draw)
  hooksecurefunc(WorldMapFrame, "OnCanvasSizeChanged", draw)
  WorldMapFrame:HookScript("OnShow", draw)
end

---One line for /bmap.
---@return string
function WorldMap:Describe()
  return ("world map terrain %s (%d tiles drawn, %d failed)"):format(ns.DB.worldTerrain and "on" or "off",
    used, self.failed)
end

-- The world map loads on demand.
ns.On("PLAYER_LOGIN", function()
  EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", setUp)
end)
