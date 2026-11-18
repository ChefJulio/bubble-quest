local ADDON_NAME, ns = ...

-- The world map's painted art drawn at any scale and turn, with the explored-area overlays, so
-- unexplored parts look as they do on the world map. Views: the minimap's "Map art" style (Terrain.lua
-- calls Draw instead of placing its tiles) and the map window (MapWindow.lua: its Map art style, and
-- whole continents when zoomed far out, where terrain tiles would be thousands of textures).
--
-- Three layers, bottom up: the continent's art (it paints the sea and fills anything no zone covers),
-- the zones around, and one zone on top (the minimap: the zone you're in; its art outside its border is
-- the faded neighbourhood the world map shows). Laid out as Blizzard's world map lays them out: a zone's
-- art is a grid of tiles (C_Map.GetMapArtLayers / GetMapArtLayerTextures,
-- Blizzard_MapCanvasDetailLayer.lua), its explored overlays pieces at pixel offsets on the same grid
-- (C_MapExplorationInfo.GetExploredMapTextures, MapExplorationDataProvider.lua; the mouse-over-only
-- ones left out). A map's art spans its rectangle in the world (C_Map.GetWorldPosFromMapPos at its
-- corners), so each piece gets a world centre and size once, and every frame only positions change.
--
-- The pieces are shared by every view; each view has its own textures. Rebuilt when exploration
-- changes (MAP_EXPLORATION_UPDATED: the piece tables are replaced, views return their textures).

local Art = {}
Art.__index = Art
ns.Art = Art

local maps = {}        -- [uiMap] = { north0, west0, north1, west1, base, overlays } (false: no art there)
local zonesOf = {}     -- [continent UI map] = { uiMap, ... }: its zones

ns.On("MAP_EXPLORATION_UPDATED", function()
  wipe(maps)
end)

---Forget the built pieces (the reveal setting changed).
function Art.Rebuild()
  wipe(maps)
end

-- A map's overlays: every one in Data/Overlays.lua with the reveal setting on (the game's data, explored
-- or not, as Leatrix Maps reveals), else the explored ones the game gives (and the mouse-over-only ones
-- left out). Both as { textureWidth, textureHeight, offsetX, offsetY, fileDataIDs, wide, top }.
local function overlaysOf(uiMap)
  local list = {}
  local all = ns.DB.revealMap and ns.Overlays.maps[uiMap]
  if all then
    for _, o in ipairs(all) do
      list[#list + 1] = { textureWidth = o.w, textureHeight = o.h, offsetX = o.x, offsetY = o.y,
        fileDataIDs = o.files, wide = o.cols, top = false }
    end
    return list
  end
  for _, o in ipairs(C_MapExplorationInfo.GetExploredMapTextures(uiMap) or {}) do
    if not o.isShownByMouseOver then
      list[#list + 1] = { textureWidth = o.textureWidth, textureHeight = o.textureHeight, offsetX = o.offsetX,
        offsetY = o.offsetY, fileDataIDs = o.fileDataIDs, top = o.isDrawOnTopLayer }
    end
  end
  return list
end

-- A map's art, as pieces in world yards: { file, north, west (centre), height, width (yards),
-- right, bottom (texcoords), sub (draw sublevel) }, in two lists: base (the painted map) and overlays
-- (the explored land pieces).
local function build(uiMap)
  local layers = C_Map.GetMapArtLayers(uiMap)
  local layer = layers and layers[1]
  local _, topLeft = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(0, 0))
  local _, bottomRight = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(1, 1))
  if not (layer and topLeft and bottomRight and layer.layerWidth > 0 and layer.layerHeight > 0) then
    return false
  end
  local n0, w0 = topLeft.x, topLeft.y
  local yardsDown, yardsRight = (n0 - bottomRight.x) / layer.layerHeight, (w0 - bottomRight.y) / layer.layerWidth
  local base, overlays = {}, {}
  local pieces = base
  -- One piece: `w` x `h` layer pixels at (`x`, `y`) from the art's top left, shown from a file
  -- `fileW` x `fileH` pixels.
  local function add(file, x, y, w, h, fileW, fileH, sub)
    pieces[#pieces + 1] = {
      file = file, sub = sub, right = w / fileW, bottom = h / fileH,
      north = n0 - (y + h / 2) * yardsDown, west = w0 - (x + w / 2) * yardsRight,
      height = h * yardsDown, width = w * yardsRight,
    }
  end

  -- The base art: tiles of tileWidth x tileHeight, row by row; the last row and column cut at the art's
  -- edge (Blizzard lets its canvas clip them).
  local tw, th = layer.tileWidth, layer.tileHeight
  local cols, rows = math.ceil(layer.layerWidth / tw), math.ceil(layer.layerHeight / th)
  local textures = C_Map.GetMapArtLayerTextures(uiMap, 1) or {}
  for row = 1, rows do
    for col = 1, cols do
      local file = textures[(row - 1) * cols + col]
      if file then
        local x, y = (col - 1) * tw, (row - 1) * th
        add(file, x, y, math.min(tw, layer.layerWidth - x), math.min(th, layer.layerHeight - y), tw, th, 0)
      end
    end
  end

  -- Explored overlays: each a grid of files on the same tile size; a last row or column is only part of
  -- a smaller power-of-two file (as MapExplorationDataProvider.lua works it out).
  local function fileSize(pixels)
    local size = 16
    while size < pixels do
      size = size * 2
    end
    return size
  end
  pieces = overlays
  for _, overlay in ipairs(overlaysOf(uiMap)) do
    do
      local wide = overlay.wide or math.ceil(overlay.textureWidth / tw)
      local tall = math.ceil(overlay.textureHeight / th)
      for j = 1, tall do
        local h, fileH = th, th
        if j == tall then
          h = overlay.textureHeight % th
          h = h == 0 and th or h
          fileH = fileSize(h)
        end
        for k = 1, wide do
          local w, fileW = tw, tw
          if k == wide then
            w = overlay.textureWidth % tw
            w = w == 0 and tw or w
            fileW = fileSize(w)
          end
          local file = overlay.fileDataIDs[(j - 1) * wide + k]
          if file and file ~= 0 then
            add(file, overlay.offsetX + tw * (k - 1), overlay.offsetY + th * (j - 1), w, h, fileW, fileH,
              overlay.top and 2 or 1)
          end
        end
      end
    end
  end
  return { north0 = n0, west0 = w0, north1 = bottomRight.x, west1 = bottomRight.y, base = base,
    overlays = overlays }
end

local function artOf(uiMap)
  local art = maps[uiMap]
  if art == nil then
    art = build(uiMap)
    maps[uiMap] = art
  end
  return art or nil
end

---The zones on a continent's UI map (any depth: some sit under a region map), once.
---@param continent number
---@return number[]
function Art.Zones(continent)
  local list = zonesOf[continent]
  if not list then
    list = {}
    for _, child in ipairs(C_Map.GetMapChildrenInfo(continent, Enum.UIMapType.Zone, true) or {}) do
      list[#list + 1] = child.mapID
    end
    zonesOf[continent] = list
  end
  return list
end

---A view drawing into `parent` (which shows, hides and clips it).
---@param parent Frame
---@return table
function Art.New(parent)
  local view = setmetatable({ parent = parent, frames = {}, icons = {}, free = {}, drawn = 0 }, Art)
  for rank = 1, 3 do
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:SetFrameLevel(parent:GetFrameLevel() + rank)
    view.frames[rank], view.icons[rank], view.free[rank] = frame, {}, {}
  end
  return view
end

-- Texture of a piece in a rank's frame, set up once.
function Art:Texture(rank, piece)
  local t = self.icons[rank][piece]
  if not t then
    t = table.remove(self.free[rank]) or self.frames[rank]:CreateTexture(nil, "BACKGROUND")
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
    t:SetDrawLayer("BACKGROUND", piece.sub)
    t:SetTexture(piece.file, nil, nil, "TRILINEAR")
    t:SetTexCoord(0, piece.right, 0, piece.bottom)
    self.icons[rank][piece] = t
  end
  return t
end

---Hide everything (the terrain style, or nothing to draw).
function Art:Hide()
  for rank = 1, 3 do
    local icons, free = self.icons[rank], self.free[rank]
    for piece, t in pairs(icons) do
      t:Hide()
      free[#free + 1] = t
      icons[piece] = nil
    end
  end
  self.drawn = 0
end

---Draw around world (north, west) on instance map `map`, the point at the parent's centre, `s` pixels
---a yard, turned by `turn` radians (0: north up). `top`: the UI map drawn over the others (nil: none);
---`continentOnly`: the continent's art alone (far out: the zones' detail wouldn't show); `landOnly`: the
---zones around as their land pieces (overlays) only, not their painted base, whose faded borders overlap
---their neighbours' (the map window: review, "this looks bad"; the continent's art is the base there).
---@param north number
---@param west number
---@param map number
---@param s number
---@param turn number
---@param top number?
---@param continentOnly boolean?
---@param landOnly boolean?
function Art:Draw(north, west, map, s, turn, top, continentOnly, landOnly)
  local continent = ns.MapPoints.Continent(map, north, west)
  local w, h = self.parent:GetWidth(), self.parent:GetHeight()
  local reach = math.sqrt(w * w + h * h) / 2  -- pixels from the centre to a corner, whatever the turn
  local reachYards = reach / s

  -- What each rank shows: maps whose rectangle reaches the view.
  local function inView(art)
    return art and north - reachYards <= art.north0 and north + reachYards >= art.north1
      and west - reachYards <= art.west0 and west + reachYards >= art.west1
  end
  local ranks = { {}, {}, {} }
  if continent then
    local art = artOf(continent)
    if art and inView(art) then
      ranks[1][1] = { art.base, art.overlays }
    end
    if not continentOnly then
      for _, zone in ipairs(Art.Zones(continent)) do
        if zone ~= top then
          local zoneArt = artOf(zone)
          if zoneArt and inView(zoneArt) then
            if not landOnly then
              ranks[2][#ranks[2] + 1] = zoneArt.base
            end
            ranks[2][#ranks[2] + 1] = zoneArt.overlays
          end
        end
      end
    end
  end
  if top and top ~= continent and not continentOnly then
    local art = artOf(top)
    if art and inView(art) then
      ranks[3][1] = { art.base, art.overlays }
    end
  end

  local cos, sin = math.cos(turn), math.sin(turn)
  local overlap = turn ~= 0 and 1 or 0  -- turned pieces get a pixel of overlap: no hairline between them
  local drawn = 0
  for rank = 1, 3 do
    local wanted = {}
    local frame, icons, free = self.frames[rank], self.icons[rank], self.free[rank]
    -- Rank 1 and 3 hold one map's { base, overlays }; rank 2 a list of piece lists.
    local lists = ranks[rank]
    if rank ~= 2 then
      lists = lists[1] or {}
    end
    for _, pieces in ipairs(lists) do
      for _, piece in ipairs(pieces) do
        local x, y = (west - piece.west) * s, (piece.north - north) * s
        local pw, ph = piece.width * s, piece.height * s
        -- Culled: nowhere near the view (the piece's centre farther than the corner plus its own size).
        if math.abs(x) - pw <= reach and math.abs(y) - ph <= reach then
          local t = self:Texture(rank, piece)
          wanted[piece] = true
          t:SetSize(pw + overlap, ph + overlap)
          t:SetRotation(-turn)
          t:ClearAllPoints()
          t:SetPoint("CENTER", frame, "CENTER", x * cos + y * sin, -x * sin + y * cos)
          t:Show()
          drawn = drawn + 1
        end
      end
    end
    for piece, t in pairs(icons) do
      if not wanted[piece] then
        t:Hide()
        free[#free + 1] = t
        icons[piece] = nil
      end
    end
  end
  self.drawn = drawn
end
