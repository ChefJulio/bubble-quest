local ADDON_NAME, ns = ...

-- Available quests on the world map (docs/design/available-quests.md), from Quests/Available.lua;
-- the minimap draws the same entries (UI/MinimapAreas.lua).
--
--   - Quest givers (NPCs, objects): Blizzard's "!" (QuestNormal, the atlas its own map uses for quest
--     offers, Blizzard_SharedMapDataProviders/QuestOfferDataProvider.lua:3), blue for daily/repeatable,
--     grey for trivial (only with the "Trivial quests" setting). One per spawn, close spawns merged.
--   - Quests started by a drop (decided in review: honest, not a "!" on every mob; then, from the first
--     look: one uniform, quieter icon, no standing areas): a smaller bronze "!" at the centre of each
--     droppers' cluster, close ones merged into one. Hovering it shows the droppers' area and says what
--     to do: "Loot Westfall Deed from Defias Thug, ... to start this quest".
--
-- Same approach as the quest areas: our own mouse-disabled frame on the map canvas, hover worked out
-- from the cursor; when an icon is under it, its tooltip wins over the areas' (MapAreas yields).

local ICON_SIZE = 16          -- pixels at 100% (setting map.iconSize), whatever the zoom (20 was big)
local DROP_ICON_SIZE = 12
local DROP_TINT = { 1, 0.7, 0.35 }  -- bronze, over the desaturated "!"
local DROP_ICON_ALPHA = 0.85
local DROP_AREA_ALPHA = 0.18  -- the droppers' area, shown while its icon is hovered
local MERGE_PIXELS = 8        -- a giver's spawns closer than this on screen share one icon
local DROP_MERGE_PIXELS = 14  -- drop icons closer than this share one (their tooltip lists them all)
local FRAME_LEVEL = 2007      -- above the areas (2005) and town services (2006), under turn-ins (2008)
                              -- and Questie's icons (2016+)
local HOVER_SECONDS = 0.05
local ATLAS_NORMAL, ATLAS_REPEATABLE = "QuestNormal", "UI-QuestPoiRecurring-QuestBang"
local FALLBACK_TEXTURE = "Interface/GossipFrame/AvailableQuestIcon"

local MapAvailable = {
  entries = {},     -- what to draw, built from Available's givers and the settings (Entries)
  builtFor = nil,   -- Available.version .. settings, the entries were built for
  hits = {},        -- world map: { x, y, radius (canvas pixels), base (icon size), entries }
  icons = {},       -- world map icon textures in use, for resizing on zoom
  fanItems = {},    -- the icons for fanning out (UI/MapFan.lua)
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

-- Art ---------------------------------------------------------------------------------------------

local hasAtlas = {}
local function atlasOr(atlas)
  if hasAtlas[atlas] == nil then
    hasAtlas[atlas] = C_Texture.GetAtlasInfo(atlas) ~= nil
  end
  return hasAtlas[atlas] and atlas or nil
end

local function setBang(texture, atlas)
  atlas = atlasOr(atlas) or atlasOr(ATLAS_NORMAL)
  if atlas then
    texture:SetAtlas(atlas)
  else
    texture:SetTexture(FALLBACK_TEXTURE)
  end
end

---Sets a texture to an entry's "!": a giver's is yellow (blue when every quest repeats, grey when all
---are trivial); a drop's is the uniform bronze one.
function MapAvailable.SetArt(texture, entry)
  if entry.giver.kind == "item" then
    setBang(texture, ATLAS_NORMAL)
    texture:SetDesaturated(true)
    texture:SetVertexColor(DROP_TINT[1], DROP_TINT[2], DROP_TINT[3], DROP_ICON_ALPHA)
  else
    setBang(texture, entry.repeatable and ATLAS_REPEATABLE or ATLAS_NORMAL)
    texture:SetDesaturated(entry.trivial)
    texture:SetVertexColor(1, 1, 1, entry.trivial and 0.75 or 1)
  end
end

-- Entries -----------------------------------------------------------------------------------------
-- Per giver, the quests to show (trivial ones only with the setting), how it looks, and where:
-- spawns for NPCs and objects; for items, the droppers' clusters (Quests/Areas.lua) and their centres.

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
      end
      self.entries[#self.entries + 1] = entry
    end
  end
  return self.entries
end

-- Tooltip -----------------------------------------------------------------------------------------

local dropperNames = {}  -- [itemID] = "Defias Pathstalker (4%), Defias Thug (3%) +3", for the session

-- Who drops it, most likely first, with the drop chance where forever-db knows it (QuestieDB has the
-- droppers, not the chances). One entry per name: several NPC ids can share one (keep the best chance).
local function droppersText(itemID)
  local text = dropperNames[itemID]
  if not text then
    local chances = ns.ForeverData:DropChances(itemID) or {}
    local byName, names = {}, {}
    local function add(name, chance)
      if not name then
        return
      end
      local entry = byName[name]
      if not entry then
        entry = { name = name }
        byName[name] = entry
        names[#names + 1] = entry
      end
      if chance and (not entry.chance or chance > entry.chance) then
        entry.chance = chance
      end
    end
    local src = ns.Available.source  -- QuestieDB, or forever-db without it
    local npcs, objects = src.droppers(itemID)
    for _, npcID in ipairs(npcs) do
      add(src.name("npc", npcID), chances["npc" .. npcID])
    end
    for _, objectID in ipairs(objects) do
      add(src.name("object", objectID), chances["object" .. objectID])
    end
    table.sort(names, function(a, b)
      if (a.chance ~= nil) ~= (b.chance ~= nil) then
        return a.chance ~= nil
      end
      if a.chance and b.chance and a.chance ~= b.chance then
        return a.chance > b.chance
      end
      return a.name < b.name
    end)
    local shown = {}
    for i = 1, math.min(3, #names) do
      local n = names[i]
      shown[i] = n.chance and ("%s (%s)"):format(n.name, ns.DoLine.ChanceText(n.chance)) or n.name
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

---Entries under a point, each once (hits carry a list: merged icons).
---@return table[]? entries
function MapAvailable.Under(hits, x, y)
  local found, seen = {}, {}
  for _, hit in ipairs(hits) do
    local dx, dy = hit.x - x, hit.y - y
    if dx * dx + dy * dy <= hit.radius * hit.radius then
      for _, entry in ipairs(hit.entries) do
        if not seen[entry] then
          seen[entry] = true
          found[#found + 1] = entry
        end
      end
    end
  end
  return #found > 0 and found or nil
end

-- World map ---------------------------------------------------------------------------------------

local layer, iconPool, blobPool
local vector
local dropAreas = {}  -- [entry] = { blob textures }, hidden until its icon is hovered
local shownAreas = {} -- entries whose area is showing

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

local function placeIcon(canvas, x, y, entry, base)
  local icon = iconPool:Acquire()
  MapAvailable.SetArt(icon, entry)
  icon.base = base
  local size = iconSize(base, canvas)
  icon:SetSize(size, size)
  icon:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
  MapAvailable.icons[#MapAvailable.icons + 1] = icon
  local hit = { x = x, y = y, radius = size / 2, base = base, entries = { entry } }
  MapAvailable.hits[#MapAvailable.hits + 1] = hit
  MapAvailable.fanItems[#MapAvailable.fanItems + 1] = {
    texture = icon, x = x, y = y, base = base,
    fill = function(tooltip) MapAvailable.FillTooltip(tooltip, hit.entries) end,  -- merged drops too
  }
  return hit
end

-- A drop icon near one already placed joins it (one icon, both in its tooltip).
local function nearDropHit(hits, x, y)
  for _, hit in ipairs(hits) do
    if hit.drop and (hit.x - x) ^ 2 + (hit.y - y) ^ 2 < DROP_MERGE_PIXELS * DROP_MERGE_PIXELS then
      return hit
    end
  end
  return nil
end

function MapAvailable:Redraw()
  local map = rawget(_G, "WorldMapFrame")
  if not map or not layer then
    return
  end
  ns.MapFan:Collapse()  -- an open ring holds textures that are about to go
  iconPool:ReleaseAll()
  blobPool:ReleaseAll()
  wipe(self.hits)
  wipe(self.icons)
  wipe(self.fanItems)
  wipe(dropAreas)
  wipe(shownAreas)
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
          local hit = nearDropHit(self.hits, cx, cy)
          if hit then
            hit.entries[#hit.entries + 1] = entry
          else
            placeIcon(canvas, cx, cy, entry, DROP_ICON_SIZE).drop = true
          end
          -- Its area, hidden until hovered.
          local blobs = dropAreas[entry] or {}
          dropAreas[entry] = blobs
          for _, p in ipairs(cluster.points) do
            local x, y = mapPos(p, mapID, width, height)
            if x and blobSize > 0 then
              local blob = blobPool:Acquire()
              blob:SetSize(blobSize, blobSize)
              blob:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
              blob:Hide()
              blobs[#blobs + 1] = blob
            end
          end
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
            placeIcon(canvas, x, y, entry, ICON_SIZE)
          end
        end
      end
    end
  end
end

-- Zooming scales the canvas: keep the icons' size on screen (cheaper than a redraw every frame).
local function resizeIcons(canvas)
  ns.MapFan:Collapse()
  for _, icon in ipairs(MapAvailable.icons) do
    local size = iconSize(icon.base, canvas)
    icon:SetSize(size, size)
  end
  for _, hit in ipairs(MapAvailable.hits) do
    hit.radius = iconSize(hit.base, canvas) / 2
  end
end

-- The areas of the hovered drop icons, and only those.
local function showDropAreas(entries)
  local want = {}
  for _, entry in ipairs(entries or {}) do
    if dropAreas[entry] then
      want[entry] = true
    end
  end
  for entry in pairs(shownAreas) do
    if not want[entry] then
      for _, blob in ipairs(dropAreas[entry] or {}) do
        blob:Hide()
      end
      shownAreas[entry] = nil
    end
  end
  for entry in pairs(want) do
    if not shownAreas[entry] then
      for _, blob in ipairs(dropAreas[entry]) do
        blob:Show()
      end
      shownAreas[entry] = true
    end
  end
end

local hoverElapsed = 0
local function updateHover(map, delta)
  hoverElapsed = hoverElapsed + delta
  if hoverElapsed < HOVER_SECONDS then
    return
  end
  hoverElapsed = 0
  local found
  -- An open ring of fanned-out icons owns the tooltip (UI/MapFan.lua).
  if map:IsMouseOver() and #MapAvailable.hits > 0 and not ns.MapFan.fanned then
    local nx, ny = map:GetNormalizedCursorPosition()
    if nx and ny and not issecretvalue(nx) and not issecretvalue(ny) then
      local width, height = map:GetCanvas():GetSize()
      found = MapAvailable.Under(MapAvailable.hits, nx * width, ny * height)
    end
  end
  showDropAreas(found)
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
  ns.MapFan:Register("available", MapAvailable.fanItems)
  iconPool = ns.CreatePool(function()
    return layer:CreateTexture(nil, "OVERLAY")
  end)
  blobPool = ns.CreatePool(function()
    local blob = layer:CreateTexture(nil, "ARTWORK")
    blob:SetTexture(ns.MapAreas.BLOB_TEXTURE)
    blob:SetVertexColor(1, 1, 1, DROP_AREA_ALPHA)
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
    showDropAreas(nil)
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
ns.Bus:On("ProfileChanged", function() MapAvailable:MarkDirty() end)
