local ADDON_NAME, ns = ...

-- Every continent on one plane, for the map window (MapWindow.lua): pan from one to the next across the
-- sea. Each continent is its own world with its own yards (UnitPosition's north and west on its instance
-- map), so there's no shared coordinate in the game; the world map (the UI map above the continents)
-- does place them side by side, so we take its layout: each continent's rectangle on it
-- (C_Map.GetMapRectOnMap), at one common scale, yards kept true within each continent.
--
-- The plane: X east, Y south, in yards. A continent's point (north, west) sits at
-- X = ax - west, Y = ay - north, where (ax, ay) puts the continent's centre where the world map has it.
-- A continent the world map doesn't show (none found, or Forever's new ones) goes to the right of the
-- others.
--
-- Continents: the instance maps we have terrain for (Data/Tiles.lua); their extent from their tiles.

local TILE_YARDS = 1600 / 3
local GRID = 64
local GAP = 4000  -- yards between a continent placed by hand and the others

local World = {}
ns.World = World

local continents  -- { { map, ui, ax, ay, x0, y0, x1, y1 (bounds on the plane) }, ... }, once laid out

-- A continent's extent in its own yards, from its tiles: north0 > north1, west0 > west1.
local function extent(tiles)
  local c0, c1, r0, r1 = GRID, -1, GRID, -1
  for key in pairs(tiles) do
    local c, r = math.floor(key / GRID), key % GRID
    c0, c1 = math.min(c0, c), math.max(c1, c)
    r0, r1 = math.min(r0, r), math.max(r1, r)
  end
  return (32 - r0) * TILE_YARDS, (32 - c0) * TILE_YARDS, (31 - r1) * TILE_YARDS, (31 - c1) * TILE_YARDS
end

-- The continent's UI map, from tiles' centres until one is on a continent map (some are open sea).
local function continentUi(map, tiles)
  local tried = 0
  for key in pairs(tiles) do
    local c, r = math.floor(key / GRID), key % GRID
    local ui = ns.MapPoints.Continent(map, (31.5 - r) * TILE_YARDS, (31.5 - c) * TILE_YARDS)
    if ui then
      return ui
    end
    tried = tried + 1
    if tried >= 40 then
      return nil
    end
  end
end

local function worldUi(ui)
  local info = C_Map.GetMapInfo(ui)
  while info and info.parentMapID and info.parentMapID ~= 0 do
    info = C_Map.GetMapInfo(info.parentMapID)
    if info and (info.mapType == Enum.UIMapType.World or info.mapType == Enum.UIMapType.Cosmic) then
      return info.mapID
    end
  end
end

local function layout()
  continents = {}
  local placed, unplaced = {}, {}
  local scales = {}
  for map, tiles in pairs(ns.Tiles.maps) do
    local n0, w0, n1, w1 = extent(tiles)
    local entry = { map = map, north0 = n0, west0 = w0, north1 = n1, west1 = w1 }
    entry.ui = continentUi(map, tiles)
    local world = entry.ui and worldUi(entry.ui)
    local minX, maxX, minY, maxY
    if world then
      minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(entry.ui, world)
    end
    -- The continent map's own corners in yards: its rectangle on the world map is that map's.
    local topLeft, bottomRight
    if entry.ui then
      topLeft = select(2, C_Map.GetWorldPosFromMapPos(entry.ui, CreateVector2D(0, 0)))
      bottomRight = select(2, C_Map.GetWorldPosFromMapPos(entry.ui, CreateVector2D(1, 1)))
    end
    if minX and maxX > minX and maxY > minY and topLeft and bottomRight then
      entry.rect = { cx = (minX + maxX) / 2, cy = (minY + maxY) / 2 }
      entry.centreNorth, entry.centreWest = (topLeft.x + bottomRight.x) / 2, (topLeft.y + bottomRight.y) / 2
      scales[#scales + 1] = (topLeft.y - bottomRight.y) / (maxX - minX)
      scales[#scales + 1] = (topLeft.x - bottomRight.x) / (maxY - minY)
      placed[#placed + 1] = entry
    else
      unplaced[#unplaced + 1] = entry
    end
  end
  -- One scale for the plane: the continents' own (yards per world-map width), averaged.
  local k = 0
  for _, s in ipairs(scales) do
    k = k + s / #scales
  end
  local function bounds(e)
    e.x0, e.x1 = e.ax - e.west0, e.ax - e.west1
    e.y0, e.y1 = e.ay - e.north0, e.ay - e.north1
  end
  for _, e in ipairs(placed) do
    e.ax, e.ay = k * e.rect.cx + e.centreWest, k * e.rect.cy + e.centreNorth
    bounds(e)
  end
  -- The world map isn't to scale, so continents at their true size can overlap: from the left, one that
  -- overlaps an earlier one moves right of it.
  table.sort(placed, function(a, b) return a.x0 < b.x0 end)
  for i, e in ipairs(placed) do
    for j = 1, i - 1 do
      local o = placed[j]
      if e.x0 < o.x1 + GAP and e.x1 > o.x0 and e.y0 < o.y1 and e.y1 > o.y0 then
        e.ax = e.ax + (o.x1 + GAP - e.x0)
        bounds(e)
      end
    end
  end
  local right = 0
  for _, e in ipairs(placed) do
    right = math.max(right, e.x1)
    continents[#continents + 1] = e
  end
  -- The rest to the right, one after another (west edge GAP past the last), centred on the world map's
  -- middle row.
  table.sort(unplaced, function(a, b) return a.map < b.map end)
  local middle = k * 0.5
  for _, e in ipairs(unplaced) do
    e.ax = right + GAP + e.west0
    e.ay = middle + (e.north0 + e.north1) / 2
    bounds(e)
    right = e.x1
    continents[#continents + 1] = e
  end
end

---The continents on the plane: { map, ui, ax, ay, x0, y0, x1, y1 }, laid out the first time.
---@return table[]
function World.Continents()
  if not continents then
    layout()
  end
  return continents
end

---The continent entry of instance map `map`, or nil.
---@param map number
---@return table?
function World.Entry(map)
  for _, e in ipairs(World.Continents()) do
    if e.map == map then
      return e
    end
  end
end

---A point on instance map `map` on the plane (X east, Y south), or nil off our continents.
---@param map number
---@param north number
---@param west number
---@return number?
---@return number?
function World.ToPlane(map, north, west)
  local e = World.Entry(map)
  if not e then
    return nil
  end
  return e.ax - west, e.ay - north
end

---The continent under plane point (x, y) and the point in its yards: entry, north, west; nil over open
---sea between continents.
---@param x number
---@param y number
---@return table?
---@return number?
---@return number?
function World.FromPlane(x, y)
  for _, e in ipairs(World.Continents()) do
    if x >= e.x0 and x <= e.x1 and y >= e.y0 and y <= e.y1 then
      return e, e.ay - y, e.ax - x
    end
  end
end

---The whole plane's bounds: x0, y0, x1, y1.
---@return number, number, number, number
function World.Bounds()
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, e in ipairs(World.Continents()) do
    x0, y0 = math.min(x0, e.x0), math.min(y0, e.y0)
    x1, y1 = math.max(x1, e.x1), math.max(y1, e.y1)
  end
  return x0, y0, x1, y1
end
