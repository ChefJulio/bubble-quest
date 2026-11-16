local ADDON_NAME, ns = ...

-- Quest areas on the world map (review: prototyped, then kept). For every quest on the cards (and the
-- one the quest log points at), the kept areas of its unfinished objectives, the same areas the arrows
-- use (Quests/Navigation.lua); a ready quest's turn-in gets a "?" marker. Each spawn point gets a soft
-- round texture (Media/Map/blob.tga), faint on its own, so overlaps build up colour where spawns are
-- dense. One colour per quest, matched by a strip on its card. Hover, card, quest log: highlights.
-- Opacity and circle size are settings (map.opacity, map.size). The minimap: UI/MinimapAreas.lua.
-- Remaining: performance caps for huge spawn lists (watch in busy zones).
--
-- How (from what installed addons do safely on Forever): our own mouse-disabled frame on the map
-- canvas (WorldMapFrame:GetCanvas()), like Questie's patrol lines; no data provider, no Blizzard pin
-- pools, never WorldMapFrame:SetMapID. Redrawn when the map's zone or canvas size changes, or the
-- quests/areas change.

local BLOB_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Map\\blob"
local TURNIN_TEXTURE = "Interface/GossipFrame/ActiveQuestIcon"  -- Blizzard's "?" (QuestUtils.lua:185)
local TURNIN_SIZE = 20       -- pixels, whatever the zoom
local MERGE_YARDS = 12       -- spawns closer than this share one circle (fewer textures)

-- A circle's radius in yards (setting map.size; 30 by default).
local function blobYards()
  return ns.DB.profile.map.size or 30
end

-- Each circle's own opacity (setting map.opacity; 40% by default, 22 was too faint in review):
-- overlaps build up colour, so dense spawn areas read stronger (a heat map). A frame buffer per quest
-- (to merge circles into one even shape) rendered the colours almost black inside the world map's own
-- frame buffer (seen in review), so it's not used.
local function blobAlpha()
  return (ns.DB.profile.map.opacity or 40) / 100
end
-- While something is highlighted (see Highlights), the other circles dim to this.
-- A share of their normal opacity (a fixed 0.12 was too dim in review), so it follows the setting.
local DIMMED_SHARE = 0.6
local HOVER_SECONDS = 0.05  -- how often the hover is checked while the map is open
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
  hits = {},     -- every drawn circle: { x, y (canvas pixels), questID, objective (index or nil) }
  radius = 0,    -- a circle's radius in canvas pixels, for the hover
  dirty = true,
  version = 0,
  -- Shared with the minimap.
  BLOB_TEXTURE = BLOB_TEXTURE,
  TURNIN_TEXTURE = TURNIN_TEXTURE,
  MERGE_YARDS = MERGE_YARDS,
  blobYards = blobYards,
  blobAlpha = blobAlpha,
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

-- What's drawn changed. `version` lets the minimap (UI/MinimapAreas.lua) notice too.
function MapAreas:MarkDirty()
  self.dirty = true
  self.version = (self.version or 0) + 1
end

-- Drawing ------------------------------------------------------------------------------------------

local vector  -- reused for every conversion

local function readable(value)
  return value ~= nil and not issecretvalue(value)
end

-- The quest the quest log points at, read from Blizzard's frames (plain reads, no hooks): one hovered
-- in its list (an entry carries .questID, QuestMapFrame.lua:8; the cursor may be on a child of it),
-- else the one its details show. Drawn even when it isn't on the cards, and glows (review).
local function questField(frame)
  local ok, id = pcall(function() return frame.questID end)  -- a forbidden frame can't be indexed
  return ok and type(id) == "number" and id or nil
end

local function logHoverQuest()
  local list = rawget(_G, "QuestScrollFrame")
  if not list or not list:IsVisible() or not list:IsMouseOver() then
    return nil
  end
  local foci = GetMouseFoci()
  local frame = foci and foci[1]
  for _ = 1, 4 do  -- the entry, or a line inside it
    if not frame then
      return nil
    end
    local id = questField(frame)
    if id then
      return id
    end
    frame = frame:GetParent()
  end
  return nil
end

local function detailsQuest()
  local questMap = rawget(_G, "QuestMapFrame")
  local details = questMap and questMap.DetailsFrame
  if details and details:IsVisible() and type(details.questID) == "number" then
    return details.questID
  end
  return nil
end

local function logQuest()
  return logHoverQuest() or detailsQuest()
end

local function acquireGroup(layer, n)
  local group = MapAreas.groups[n]
  if not group then
    group = CreateFrame("Frame", nil, layer)
    group:SetAllPoints(layer)
    group:EnableMouse(false)
    group.textures = {}
    group.markers = {}
    MapAreas.groups[n] = group
  end
  group.used, group.markersUsed = 0, 0
  group:Show()
  return group
end

-- A ready quest's turn-in: Blizzard's "?" over the quest's coloured circle, a fixed size on screen.
local function placeMarker(group, canvas, x, y)
  group.markersUsed = group.markersUsed + 1
  local marker = group.markers[group.markersUsed]
  if not marker then
    marker = group:CreateTexture(nil, "OVERLAY")
    marker:SetTexture(TURNIN_TEXTURE)
    group.markers[group.markersUsed] = marker
  end
  local scale = canvas:GetEffectiveScale() / UIParent:GetEffectiveScale()
  marker:SetSize(TURNIN_SIZE / scale, TURNIN_SIZE / scale)  -- the canvas zooms; the "?" doesn't
  marker:ClearAllPoints()
  marker:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
  marker:Show()
end

local function placeBlob(group, canvas, x, y, size, color)
  group.used = group.used + 1
  local texture = group.textures[group.used]
  if not texture then
    texture = group:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(BLOB_TEXTURE)
    group.textures[group.used] = texture
  end
  texture:SetVertexColor(color[1], color[2], color[3], blobAlpha())
  texture:SetSize(size, size)
  texture:ClearAllPoints()
  texture:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
  texture:Show()
  return texture
end

local function finishGroup(group)
  for i = group.used + 1, #group.textures do
    group.textures[i]:Hide()
  end
  for i = group.markersUsed + 1, #group.markers do
    group.markers[i]:Hide()
  end
end

---Every kept area point of the quest's current targets (unfinished objectives, or the turn-in), with
---its objective index (nil: the turn-in). Also used by the minimap (UI/MinimapAreas.lua). Spawns
---closer than MERGE_YARDS (same objective) share one entry: one circle, fewer textures.
---@param quest table
---@return table[] { { point = { map, x, y }, objective } }
function MapAreas:QuestPoints(quest)
  local points, seen = {}, {}
  for key, areas in pairs(ns.Navigation:Targets(quest).byObjective) do
    local objective = type(key) == "number" and key or nil
    for _, area in ipairs(areas) do
      if area.kept then
        for _, p in ipairs(area.points) do
          local cell = (objective or "t") .. ":" .. p.map .. ":" .. math.floor(p.x / MERGE_YARDS) .. ":"
            .. math.floor(p.y / MERGE_YARDS)
          if not seen[cell] then
            seen[cell] = true
            points[#points + 1] = { point = p, objective = objective }
          end
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
  local details = logQuest()
  self.drawnFor = { mapID = mapID, width = width, height = height, details = details }
  self.dirty = false
  if not self:Enabled() or not mapID or not width or width == 0 then
    return
  end
  local worldWidth, worldHeight = C_Map.GetMapWorldSize(mapID)
  if not worldWidth or worldWidth == 0 then
    return
  end
  local size = 2 * blobYards() / worldWidth * width
  vector = vector or CreateVector2D(0, 0)
  wipe(self.hits)
  self.highlightReset()  -- new circles start untinted by any hover
  self.blobSize = size
  self.radius = size / 2 * 0.7  -- the circle's visible core (its edge fades out)

  -- The cards' quests, plus the quest open in the quest log's details when it isn't on them.
  local quests = {}
  for questID in pairs(ns.Stack.visible) do
    quests[questID] = true
  end
  if details then
    quests[details] = true
  end

  local n = 0
  for questID in pairs(quests) do
    local quest = ns.QuestLog:Get(questID)
    if quest then
      n = n + 1
      local group = acquireGroup(layer, n)
      local color = self:ColorFor(questID)
      for _, entry in ipairs(self:QuestPoints(quest)) do
        local p = entry.point
        vector:SetXY(p.x, p.y)
        local _, pos = C_Map.GetMapPosFromWorldPos(p.map, vector, mapID)
        if pos and pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1 then
          local x, y = pos.x * width, pos.y * height
          local texture = placeBlob(group, canvas, x, y, size, color)
          if not entry.objective then
            placeMarker(group, canvas, x, y)
          end
          self.hits[#self.hits + 1] = {
            x = x, y = y, questID = questID, objective = entry.objective, texture = texture, color = color,
          }
        end
      end
      finishGroup(group)
    end
  end
end

-- Hover -----------------------------------------------------------------------------------------------
-- The areas take no mouse (they'd block the map and its pins), so the hover is worked out from the
-- cursor, as Questie does for its patrol lines: every quest and objective whose circles are under the
-- cursor, in a tooltip like Questie's (review). It stays out of the way when another tooltip is up
-- (a Questie icon, a map pin).

---Quests and objectives under the cursor: { [questID] = { [objective index or "turnin"] = true } }, or
---nil. `hits` are circles { x, y, questID, objective } in the same pixels as x, y. Also the minimap's.
---@param hits table[]
---@param radius number a circle's hoverable radius, pixels
---@param x number
---@param y number
---@return table?
function MapAreas.Under(hits, radius, x, y)
  local found, any = {}, false
  local r2 = radius * radius
  for _, hit in ipairs(hits) do
    local dx, dy = hit.x - x, hit.y - y
    if dx * dx + dy * dy <= r2 then
      found[hit.questID] = found[hit.questID] or {}
      found[hit.questID][hit.objective or "turnin"] = true
      any = true
    end
  end
  return any and found or nil
end

-- Quests under the cursor in card order (top card first; quests without a card after, by ID), so the
-- tooltip lists them as the tracker does and lines don't swap places between refreshes.
local function inCardOrder(found)
  local rank = {}
  for index, questID in ipairs(ns.Stack.order) do
    rank[questID] = index
  end
  local questIDs = {}
  for questID in pairs(found) do
    questIDs[#questIDs + 1] = questID
  end
  table.sort(questIDs, function(a, b)
    local ra, rb = rank[a] or math.huge, rank[b] or math.huge
    if ra ~= rb then
      return ra < rb
    end
    return a < b
  end)
  return questIDs
end

-- One tooltip for everything under the cursor, laid out like Questie's (review): per quest, "[7] Title"
-- in its map colour with a status on the right, then the objectives there, indented, with counts.
-- Also the minimap's.
function MapAreas.ShowTooltip(owner, found)
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  GameTooltip:ClearLines()
  local first = true
  for _, questID in ipairs(inCardOrder(found)) do
    local objectives = found[questID]
    local quest = ns.QuestLog:Get(questID)
    if quest then
      if not first then
        GameTooltip:AddLine(" ")
      end
      first = false
      local color = MapAreas:ColorFor(questID)
      local status = quest.readyForTurnIn and "(Ready to turn in)" or ""
      GameTooltip:AddDoubleLine(("[%d] %s"):format(quest.level or 0, quest.title or "?"), status,
        color[1], color[2], color[3], 1, 0.82, 0)
      if objectives.turnin then
        local turnIn = ns.ForeverData:TurnInName(questID)
        GameTooltip:AddLine("  " .. (turnIn and ("Turn in to " .. turnIn) or "Turn in"), 0.2, 1, 0.2)
      end
      for index, objective in ipairs(quest.objectives) do
        if objectives[index] then
          local text, counter = ns.DoLine:For(objective, questID)
          GameTooltip:AddDoubleLine("  " .. text, counter or "", 1, 1, 1, 1, 1, 1)
        end
      end
    end
  end
  GameTooltip:Show()
end

-- Highlights (review): what's lit up, most direct first: the circles under the cursor (those
-- objectives), else a hovered card (its whole quest), else the quest open in the quest log's details
-- (its whole quest). Lit circles glow, pulsing between GLOW_LOW and GLOW_HIGH every GLOW_SECONDS; the
-- rest dim. `target` is { [questID] = { [objective index | "turnin" | "*" (all)] = true } }.

local GLOW_LOW, GLOW_HIGH, GLOW_SECONDS = 0.45, 0.9, 1.4
local GLOW_GROW = 1.3  -- lit circles grow by this, so the highlighted area reads bolder (review)

local highlightKey
local lit = {}  -- the circles currently glowing
local function highlight(target)
  local key = ""
  if target then
    local parts = {}
    for questID, objectives in pairs(target) do
      for objective in pairs(objectives) do
        parts[#parts + 1] = questID .. ":" .. tostring(objective)
      end
    end
    table.sort(parts)
    key = table.concat(parts, ",")
  end
  if key == highlightKey then
    return
  end
  highlightKey = key
  wipe(lit)
  local size = MapAreas.blobSize or 0
  for _, hit in ipairs(MapAreas.hits) do
    local alpha, scale = blobAlpha(), 1
    if target then
      local objectives = target[hit.questID]
      if objectives and (objectives["*"] or objectives[hit.objective or "turnin"]) then
        lit[#lit + 1] = hit
        alpha, scale = GLOW_HIGH, GLOW_GROW
      else
        alpha = alpha * DIMMED_SHARE
      end
    end
    local c = hit.color
    hit.texture:SetVertexColor(c[1], c[2], c[3], alpha)
    hit.texture:SetSize(size * scale, size * scale)
  end
end

-- The glow: lit circles pulse (every frame while something is lit).
local function glow()
  if #lit == 0 then
    return
  end
  local wave = (math.sin(GetTime() * 2 * math.pi / GLOW_SECONDS) + 1) / 2
  local alpha = GLOW_LOW + (GLOW_HIGH - GLOW_LOW) * wave
  for _, hit in ipairs(lit) do
    local c = hit.color
    hit.texture:SetVertexColor(c[1], c[2], c[3], alpha)
  end
end

-- A redraw makes new circles at the normal alpha: forget the last highlight.
MapAreas.highlightReset = function()
  highlightKey = nil
  wipe(lit)
end

---A card is hovered (its quest lights up on the map), or nil when the cursor leaves it. `objective`:
---the objective row under the cursor (an index, or "turnin"): only that objective lights up.
---@param questID number?
---@param objective number|string|nil
function MapAreas:SetCardHover(questID, objective)
  self.cardHover, self.cardHoverObjective = questID, objective
end

local hoverElapsed, hovering = 0, false
local function updateHover(layer, map, delta)
  glow()
  hoverElapsed = hoverElapsed + delta
  if hoverElapsed < HOVER_SECONDS then
    return
  end
  hoverElapsed = 0
  local found
  if map:IsMouseOver() and #MapAreas.hits > 0 then
    local nx, ny = map:GetNormalizedCursorPosition()
    if readable(nx) and readable(ny) then
      local width, height = map:GetCanvas():GetSize()
      found = MapAreas.Under(MapAreas.hits, MapAreas.radius, nx * width, ny * height)
    end
  end
  local tooltipBusy = GameTooltip:IsShown() and GameTooltip:GetOwner() ~= layer
  if found and not tooltipBusy then
    MapAreas.ShowTooltip(layer, found)
    hovering = true
  elseif hovering and not found then
    if GameTooltip:GetOwner() == layer then
      GameTooltip:Hide()
    end
    hovering = false
  end
  -- What to light up: cursor, else hovered card, else the quest log's open quest.
  local target = found and not tooltipBusy and found or nil
  if not target and MapAreas.cardHover then
    target = { [MapAreas.cardHover] = { [MapAreas.cardHoverObjective or "*"] = true } }
  elseif not target then
    local questID = logQuest()
    target = questID and { [questID] = { ["*"] = true } } or nil
  end
  highlight(target)
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
  layer:SetScript("OnUpdate", function(_, delta)
    local drawn = MapAreas.drawnFor
    local width = canvas:GetWidth()
    if MapAreas.dirty or not drawn or drawn.mapID ~= map:GetMapID() or drawn.width ~= width
        or drawn.details ~= logQuest() then
      MapAreas:Redraw()
    end
    updateHover(layer, map, delta)
  end)
  layer:SetScript("OnHide", function()
    if hovering and GameTooltip:GetOwner() == layer then
      GameTooltip:Hide()
    end
    highlight(nil)
    hovering = false
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
for _, message in ipairs({
  "QuestLogChanged", "QuestChanged", "LocationsChanged", "TrackingChanged", "LearnedChanged",
}) do
  ns.Bus:On(message, function() MapAreas:MarkDirty() end)
end
