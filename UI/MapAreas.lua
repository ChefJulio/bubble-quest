local ADDON_NAME, ns = ...

-- PROTOTYPE (review, 2026-11-16: "prototype first"): quest areas on the world map as soft shaded
-- blobs, to judge the look before building it properly. Remaining work if kept: hover links (card <->
-- area), turn-in markers, the minimap layer, settings for colours/opacity, performance caps, and
-- possibly true outlined shapes instead of blobs (docs: research summary in this session).
--
-- What it draws: for every quest on the cards, the kept areas of its unfinished objectives (or its
-- turn-in when ready), the same areas the arrows use (Quests/Navigation.lua). Each spawn point gets a
-- soft round texture (Media/Map/blob.tga), faint on its own, so overlaps build up colour where spawns
-- are dense. One colour per quest, matched by a strip on its card.
--
-- How (from what installed addons do safely on Forever): our own mouse-disabled frame on the map
-- canvas (WorldMapFrame:GetCanvas()), like Questie's patrol lines; no data provider, no Blizzard pin
-- pools, never WorldMapFrame:SetMapID. Redrawn when the map's zone or canvas size changes, or the
-- quests/areas change.

local BLOB_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Map\\blob"
local BLOB_YARDS = 30        -- radius of one spawn's soft circle
local MERGE_YARDS = 12       -- spawns closer than this share one circle (fewer textures)
-- Each circle's own opacity: overlaps build up colour, so dense spawn areas read stronger (a heat
-- map). A frame buffer per quest (to merge circles into one even shape) rendered the colours almost
-- black inside the world map's own frame buffer (seen in review), so it's not used.
local BLOB_ALPHA = 0.22
local FRAME_LEVEL = 2005     -- under Questie's map lines (2015) and icons (2016+)

-- Eight hues that stay distinct on the map's parchment and from each other.
local PALETTE = {
  { 0.10, 0.75, 0.70 },  -- teal
  { 1.00, 0.55, 0.10 },  -- orange
  { 0.90, 0.25, 0.70 },  -- magenta
  { 0.25, 0.50, 1.00 },  -- blue
  { 0.35, 0.80, 0.25 },  -- green
  { 0.90, 0.20, 0.20 },  -- red
  { 0.60, 0.35, 0.95 },  -- purple
  { 0.95, 0.80, 0.15 },  -- gold
}

local MapAreas = {
  colors = {},   -- [questID] = palette index, for the session (stays when cards re-sort)
  groups = {},   -- [n] = per-quest frame with its textures
  dirty = true,
}
ns.MapAreas = MapAreas

function MapAreas:Enabled()
  return ns.DB.profile and ns.DB.profile.map and ns.DB.profile.map.areas
end

---A quest's colour: assigned once per session, the palette colour least used by the other quests
---on the cards right now (so neighbours rarely match).
---@param questID number
---@return table { r, g, b }
function MapAreas:ColorFor(questID)
  local index = self.colors[questID]
  if not index then
    local used = {}
    for visibleID in pairs(ns.Stack.visible) do
      local i = self.colors[visibleID]
      if i then
        used[i] = (used[i] or 0) + 1
      end
    end
    index = 1
    for i = 2, #PALETTE do
      if (used[i] or 0) < (used[index] or 0) then
        index = i
      end
    end
    self.colors[questID] = index
  end
  return PALETTE[index]
end

function MapAreas:MarkDirty()
  self.dirty = true
end

-- Drawing ------------------------------------------------------------------------------------------

local vector  -- reused for every conversion

local function acquireGroup(layer, n)
  local group = MapAreas.groups[n]
  if not group then
    group = CreateFrame("Frame", nil, layer)
    group:SetAllPoints(layer)
    group:EnableMouse(false)
    group.textures = {}
    MapAreas.groups[n] = group
  end
  group.used = 0
  group:Show()
  return group
end

local function placeBlob(group, canvas, x, y, size, color)
  group.used = group.used + 1
  local texture = group.textures[group.used]
  if not texture then
    texture = group:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(BLOB_TEXTURE)
    group.textures[group.used] = texture
  end
  texture:SetVertexColor(color[1], color[2], color[3], BLOB_ALPHA)
  texture:SetSize(size, size)
  texture:ClearAllPoints()
  texture:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
  texture:Show()
end

local function finishGroup(group)
  for i = group.used + 1, #group.textures do
    group.textures[i]:Hide()
  end
end

-- Every kept area point of the quest's current targets (unfinished objectives, or the turn-in).
local function questPoints(quest)
  local points = {}
  for _, areas in pairs(ns.Navigation:Targets(quest).byObjective) do
    for _, area in ipairs(areas) do
      if area.kept then
        for _, p in ipairs(area.points) do
          points[#points + 1] = p
        end
      end
    end
  end
  return points
end

function MapAreas:Redraw()
  local map = rawget(_G, "WorldMapFrame")
  local layer = self.layer
  if not map or not layer then
    return
  end
  for _, group in ipairs(self.groups) do
    group:Hide()
  end
  local mapID = map:GetMapID()
  local canvas = map:GetCanvas()
  local width, height = canvas:GetSize()
  self.drawnFor = { mapID = mapID, width = width, height = height }
  self.dirty = false
  if not self:Enabled() or not mapID or not width or width == 0 then
    return
  end
  local worldWidth, worldHeight = C_Map.GetMapWorldSize(mapID)
  if not worldWidth or worldWidth == 0 then
    return
  end
  local size = 2 * BLOB_YARDS / worldWidth * width
  vector = vector or CreateVector2D(0, 0)

  local n = 0
  for questID in pairs(ns.Stack.visible) do
    local quest = ns.QuestLog:Get(questID)
    if quest then
      n = n + 1
      local group = acquireGroup(layer, n)
      local color = self:ColorFor(questID)
      local seen = {}
      for _, p in ipairs(questPoints(quest)) do
        local key = p.map .. ":" .. math.floor(p.x / MERGE_YARDS) .. ":" .. math.floor(p.y / MERGE_YARDS)
        if not seen[key] then
          seen[key] = true
          vector:SetXY(p.x, p.y)
          local _, pos = C_Map.GetMapPosFromWorldPos(p.map, vector, mapID)
          if pos and pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1 then
            placeBlob(group, canvas, pos.x * width, pos.y * height, size, color)
          end
        end
      end
      finishGroup(group)
    end
  end
end

-- The layer -----------------------------------------------------------------------------------------

local function createLayer()
  local map = rawget(_G, "WorldMapFrame")
  if MapAreas.layer or not map then
    return
  end
  local canvas = map:GetCanvas()
  local layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:EnableMouse(false)
  layer:SetFrameLevel(FRAME_LEVEL)
  -- Runs only while the map is shown (the layer is part of it): redraw when the zone shown, the
  -- canvas size or our data changed.
  layer:SetScript("OnUpdate", function()
    local drawn = MapAreas.drawnFor
    local width = canvas:GetWidth()
    if MapAreas.dirty or not drawn or drawn.mapID ~= map:GetMapID() or drawn.width ~= width then
      MapAreas:Redraw()
    end
  end)
  MapAreas.layer = layer
end

ns.Events:On("PLAYER_LOGIN", createLayer)
ns.Events:On("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then
    createLayer()
  end
end)

-- Our data changed: redraw next time the map is looked at (or now, if it's open).
for _, message in ipairs({ "QuestLogChanged", "LocationsChanged", "TrackingChanged", "LearnedChanged" }) do
  ns.Bus:On(message, function() MapAreas:MarkDirty() end)
end
