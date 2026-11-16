local ADDON_NAME, ns = ...

-- Available quests on the world map (docs/design/available-quests.md), from Quests/Available.lua;
-- the minimap draws the same entries (UI/MinimapAreas.lua).
--
--   - Quest givers (NPCs, objects): Blizzard's "!" (QuestNormal, the atlas its own map uses for quest
--     offers, Blizzard_SharedMapDataProviders/QuestOfferDataProvider.lua:3), blue for daily/repeatable,
--     grey for trivial (only with the "Trivial quests" setting). One per spawn, close spawns merged.
--   - Quests started by a drop (decided in review: honest, not a "!" on every mob): the droppers' area
--     in a faint grey, and at each cluster's centre the item's own icon with a small "!". The tooltip
--     says what to do: "Loot Westfall Deed from Defias Thug, ... to start this quest".
--
-- Same approach as the quest areas: our own mouse-disabled frame on the map canvas, hover worked out
-- from the cursor; when an icon is under it, its tooltip wins over the areas' (MapAreas yields).

local ICON_SIZE = 20          -- pixels at 100% (setting map.iconSize), whatever the zoom
local DROP_ICON_SIZE = 18
local DROP_TINT, DROP_ALPHA = { 0.8, 0.8, 0.8 }, 0.14
local MERGE_PIXELS = 8        -- one giver's spawns closer than this on screen share one icon
local FRAME_LEVEL = 2006      -- just above the quest areas (2005), under Questie's icons (2016+)
local HOVER_SECONDS = 0.05
local ATLAS_NORMAL, ATLAS_REPEATABLE = "QuestNormal", "UI-QuestPoiRecurring-QuestBang"
local FALLBACK_TEXTURE = "Interface/GossipFrame/AvailableQuestIcon"

local MapAvailable = {
  entries = {},     -- what to draw, built from Available's givers and the settings (Entries)
  builtFor = nil,   -- Available.version .. settings, the entries were built for
  hits = {},        -- world map: { x, y, radius (canvas pixels), entry }
  icons = {},       -- world map icon textures in use, for resizing on zoom
  hovering = false,
}
ns.MapAvailable = MapAvailable

local function settings()
  return ns.DB.profile and ns.DB.profile.map
end

function MapAvailable:Enabled()
  local map = settings()
  return map ~= nil and map.available == true and ns.Available.records ~= nil
end

-- Entries -----------------------------------------------------------------------------------------
-- Per giver, the quests to show (trivial ones only with the setting), how it looks, and where:
-- spawns for NPCs and objects; for items, the droppers' clusters (Quests/Areas.lua) and their centres.

local hasAtlas = {}
local function atlasOr(atlas)
  if hasAtlas[atlas] == nil then
    hasAtlas[atlas] = C_Texture.GetAtlasInfo(atlas) ~= nil
  end
  return hasAtlas[atlas] and atlas or nil
end

---Sets a texture to a giver's "!": blue when every quest it offers repeats, grey when all are trivial.
function MapAvailable.SetGiverArt(texture, entry)
  local atlas = atlasOr(entry.repeatable and ATLAS_REPEATABLE or ATLAS_NORMAL) or atlasOr(ATLAS_NORMAL)
  if atlas then
    texture:SetAtlas(atlas)
  else
    texture:SetTexture(FALLBACK_TEXTURE)
  end
  texture:SetDesaturated(entry.trivial)
  texture:SetVertexColor(1, 1, 1, entry.trivial and 0.75 or 1)
end

local function clusterCentres(points)
  local clusters = {}
  for _, area in ipairs(ns.Areas:Build(points)) do
    if area.kept then
      local x, y = 0, 0
      for _, p in ipairs(area.points) do
        x, y = x + p.x, y + p.y
      end
      clusters[#clusters + 1] = {
        centre = { map = area.map, x = x / #area.points, y = y / #area.points }, points = area.points,
      }
    end
  end
  return clusters
end

---The entries for the current givers and settings, rebuilt only when either changed.
---@return table[]
function MapAvailable:Entries()
  local map = settings() or {}
  local key = ("%d:%s:%s"):format(ns.Available.version, tostring(map.availableTrivial), tostring(map.availableDrops))
  if key == self.builtFor then
    return self.entries
  end
  self.builtFor = key
  wipe(self.entries)
  for _, giver in ipairs(ns.Available.givers) do
    local quests, allTrivial, allRepeatable = {}, true, true
    for _, q in ipairs(giver.quests) do
      if map.availableTrivial or not q.trivial then
        quests[#quests + 1] = q
        allTrivial = allTrivial and q.trivial
        allRepeatable = allRepeatable and ns.Available.Repeatable(q.record)
      end
    end
    if #quests > 0 and (giver.kind ~= "item" or map.availableDrops) then
      local entry = { giver = giver, quests = quests, trivial = allTrivial, repeatable = allRepeatable }
      if giver.kind == "item" then
        entry.clusters = clusterCentres(giver.points)
        entry.icon = C_Item.GetItemIconByID(giver.id)
      end
      self.entries[#self.entries + 1] = entry
    end
  end
  return self.entries
end

-- Tooltip -----------------------------------------------------------------------------------------

local dropperNames = {}  -- [itemID] = "Defias Thug, Defias Bandit +3", for the session

local function droppersText(itemID)
  local text = dropperNames[itemID]
  if not text then
    local names, seen = {}, {}
    for _, npcID in ipairs(ns.QuestieData.Get("ItemDB", "npcDrops", itemID) or {}) do
      local name = ns.QuestieData.Get("NpcDB", "name", npcID)
      if name and not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
    for _, objectID in ipairs(ns.QuestieData.Get("ItemDB", "objectDrops", itemID) or {}) do
      local name = ns.QuestieData.Get("ObjectDB", "name", objectID)
      if name and not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
    local shown = {}
    for i = 1, math.min(3, #names) do
      shown[i] = names[i]
    end
    text = table.concat(shown, ", ") .. (#names > 3 and (" +%d"):format(#names - 3) or "")
    dropperNames[itemID] = text
  end
  return text
end

local function questLine(tooltip, q)
  local r = q.record
  local level = (r.level and r.level > 0) and r.level or UnitLevel("player")
  local color = GetQuestDifficultyColor(level)
  local tag = q.trivial and "(Trivial)" or ns.Available.Repeatable(r) and "(Repeatable)" or ""
  tooltip:AddDoubleLine(("[%d] %s"):format(level, r.name or "?"), tag, color.r, color.g, color.b, 0.6, 0.6, 0.6)
end

---Fills `tooltip` (owned and anchored by the caller) for the entries under the cursor.
function MapAvailable.FillTooltip(tooltip, entries)
  tooltip:ClearLines()
  for i, entry in ipairs(entries) do
    if i > 1 then
      tooltip:AddLine(" ")
    end
    local giver = entry.giver
    if giver.kind == "item" then
      for _, q in ipairs(entry.quests) do
        questLine(tooltip, q)
      end
      tooltip:AddLine(("Loot %s from %s to start this quest."):format(giver.name or "it", droppersText(giver.id)),
        0.8, 0.8, 0.8, true)
    else
      tooltip:AddLine(giver.name or "?", 1, 1, 1)
      for _, q in ipairs(entry.quests) do
        questLine(tooltip, q)
      end
    end
  end
  tooltip:Show()
end

-- World map ---------------------------------------------------------------------------------------

local layer, iconPool, blobPool
local vector

local function iconSize(base, canvas)
  return base * ns.MapAreas.iconScale() * UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
end

local function mapPos(p, mapID, width, height)
  vector = vector or CreateVector2D(0, 0)
  vector:SetXY(p.x, p.y)
  local _, pos = C_Map.GetMapPosFromWorldPos(p.map, vector, mapID)
  if pos and pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1 then
    return pos.x * width, pos.y * height
  end
  return nil
end

local function sizeIcon(icon, size)
  icon:SetSize(size, size)
  icon.bang:SetSize(size * 0.6, size * 0.6)
end

local function placeIcon(canvas, x, y, base, setArt)
  local icon = iconPool:Acquire()
  setArt(icon)
  icon.base = base
  local size = iconSize(base, canvas)
  sizeIcon(icon, size)
  icon:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
  MapAvailable.icons[#MapAvailable.icons + 1] = icon
  return size
end

function MapAvailable:Redraw()
  local map = rawget(_G, "WorldMapFrame")
  if not map or not layer then
    return
  end
  iconPool:ReleaseAll()
  blobPool:ReleaseAll()
  wipe(self.hits)
  wipe(self.icons)
  local canvas = map:GetCanvas()
  local mapID = map:GetMapID()
  local width, height = canvas:GetSize()
  self.drawnFor = { mapID = mapID, width = width, built = self.builtFor, scale = canvas:GetEffectiveScale() }
  if not self:Enabled() or not mapID or not width or width == 0 then
    return
  end
  local entries = self:Entries()
  self.drawnFor.built = self.builtFor
  local worldWidth = C_Map.GetMapWorldSize(mapID)
  local blobSize = worldWidth and worldWidth > 0 and 2 * ns.MapAreas.blobYards() / worldWidth * width or 0
  for _, entry in ipairs(entries) do
    if entry.giver.kind == "item" then
      for _, cluster in ipairs(entry.clusters) do
        local cx, cy = mapPos(cluster.centre, mapID, width, height)
        if cx then
          for _, p in ipairs(cluster.points) do
            local x, y = mapPos(p, mapID, width, height)
            if x and blobSize > 0 then
              local blob = blobPool:Acquire()
              blob:SetSize(blobSize, blobSize)
              blob:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
              self.hits[#self.hits + 1] = { x = x, y = y, radius = blobSize / 2 * 0.7, entry = entry }
            end
          end
          local size = placeIcon(canvas, cx, cy, DROP_ICON_SIZE, function(icon)
            icon:SetTexture(entry.icon or FALLBACK_TEXTURE)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetDesaturated(entry.trivial)
            icon:SetVertexColor(1, 1, 1, 1)
            icon.bang:Show()
          end)
          self.hits[#self.hits + 1] = { x = cx, y = cy, radius = size / 2, entry = entry, base = DROP_ICON_SIZE }
        end
      end
    else
      local placed = {}
      for _, p in ipairs(entry.giver.points) do
        local x, y = mapPos(p, mapID, width, height)
        if x then
          local near = false
          for _, q in ipairs(placed) do
            if (q[1] - x) ^ 2 + (q[2] - y) ^ 2 < MERGE_PIXELS * MERGE_PIXELS then
              near = true
              break
            end
          end
          if not near then
            placed[#placed + 1] = { x, y }
            local size = placeIcon(canvas, x, y, ICON_SIZE, function(icon)
              MapAvailable.SetGiverArt(icon, entry)
              icon:SetTexCoord(0, 1, 0, 1)
              icon.bang:Hide()
            end)
            self.hits[#self.hits + 1] = { x = x, y = y, radius = size / 2, entry = entry, base = ICON_SIZE }
          end
        end
      end
    end
  end
end

-- Zooming scales the canvas: keep the icons' size on screen (cheaper than a redraw every frame).
local function resizeIcons(canvas)
  for _, icon in ipairs(MapAvailable.icons) do
    sizeIcon(icon, iconSize(icon.base, canvas))
  end
  for _, hit in ipairs(MapAvailable.hits) do
    if hit.base then
      hit.radius = iconSize(hit.base, canvas) / 2
    end
  end
end

---Entries under a point, icons first (an icon over its own area counts once).
---@return table[]? entries
function MapAvailable.Under(hits, x, y)
  local found, seen = {}, {}
  for _, hit in ipairs(hits) do
    local dx, dy = hit.x - x, hit.y - y
    if dx * dx + dy * dy <= hit.radius * hit.radius and not seen[hit.entry] then
      seen[hit.entry] = true
      found[#found + 1] = hit.entry
    end
  end
  return #found > 0 and found or nil
end

local hoverElapsed = 0
local function updateHover(map, delta)
  hoverElapsed = hoverElapsed + delta
  if hoverElapsed < HOVER_SECONDS then
    return
  end
  hoverElapsed = 0
  local found
  if map:IsMouseOver() and #MapAvailable.hits > 0 then
    local nx, ny = map:GetNormalizedCursorPosition()
    if nx and ny and not issecretvalue(nx) and not issecretvalue(ny) then
      local width, height = map:GetCanvas():GetSize()
      found = MapAvailable.Under(MapAvailable.hits, nx * width, ny * height)
    end
  end
  if found then
    local tooltip = ns.Tooltips:Take(layer, "ANCHOR_CURSOR")  -- nil while Ctrl hides ours
    if tooltip then
      MapAvailable.FillTooltip(tooltip, found)
    end
    MapAvailable.hovering = tooltip ~= nil
  elseif MapAvailable.hovering then
    if GameTooltip:GetOwner() == layer then
      GameTooltip:Hide()
    end
    MapAvailable.hovering = false
  end
end

local function createLayer()
  local map = rawget(_G, "WorldMapFrame")
  if layer or not map then
    return
  end
  local canvas = map:GetCanvas()
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:EnableMouse(false)
  layer:SetFrameLevel(FRAME_LEVEL)
  ---@class QuestmarkerMapIcon: Texture
  ---@field bang Texture the small "!" on an item's icon
  ---@field base number size at 100%
  iconPool = ns.CreatePool(function()
    local icon = layer:CreateTexture(nil, "OVERLAY") --[[@as QuestmarkerMapIcon]]
    icon.bang = layer:CreateTexture(nil, "OVERLAY", nil, 1)  -- the small "!" on an item's icon
    local atlas = atlasOr(ATLAS_NORMAL)
    if atlas then
      icon.bang:SetAtlas(atlas)
    else
      icon.bang:SetTexture(FALLBACK_TEXTURE)
    end
    icon.bang:SetPoint("CENTER", icon, "TOPRIGHT", -2, -2)
    icon.bang:Hide()
    return icon
  end, function(icon)
    icon.bang:Hide()
  end)
  blobPool = ns.CreatePool(function()
    local blob = layer:CreateTexture(nil, "ARTWORK")
    blob:SetTexture(ns.MapAreas.BLOB_TEXTURE)
    blob:SetVertexColor(DROP_TINT[1], DROP_TINT[2], DROP_TINT[3], DROP_ALPHA)
    return blob
  end)
  layer:SetScript("OnUpdate", function(_, delta)
    local drawn = MapAvailable.drawnFor
    MapAvailable:Entries()
    if not drawn or drawn.mapID ~= map:GetMapID() or drawn.width ~= canvas:GetWidth()
        or drawn.built ~= MapAvailable.builtFor then
      MapAvailable:Redraw()
    elseif drawn.scale ~= canvas:GetEffectiveScale() then
      drawn.scale = canvas:GetEffectiveScale()
      resizeIcons(canvas)
    end
    updateHover(map, delta)
  end)
  layer:SetScript("OnHide", function()
    if MapAvailable.hovering and GameTooltip:GetOwner() == layer then
      GameTooltip:Hide()
    end
    MapAvailable.hovering = false
  end)
end

ns.Events:On("PLAYER_LOGIN", createLayer)
ns.Events:On("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then
    createLayer()
  end
end)

-- Settings that change what's drawn (the entries key covers trivial/drops; this covers on/off, size).
function MapAvailable:MarkDirty()
  self.drawnFor = nil
  self.builtFor = nil
end
