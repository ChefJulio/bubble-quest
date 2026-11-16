local ADDON_NAME, ns = ...

-- Areas from location points (docs/design/navigation-areas.md). An objective's points (spawns from
-- Questie and forever-db, learned sightings) become areas: occupied CELL_YARDS grid cells joined with
-- their 8 neighbours, each connected group one area. Then the rule: ignore areas lighter than
-- MAIN_SHARE of the biggest one (a stray spawn far from the camp), keep the rest.
--
-- Points: { map, x, y, weight? } in world yards (weight 1 by default; learned spots carry their
-- sighting count). The same spawn from two sources counts once: points within MERGE_YARDS merge,
-- keeping the larger weight. Built once per objective and cached by the caller (Navigation).

local CELL_YARDS = 50
local MERGE_YARDS = 4
local MAIN_SHARE = 0.25

local Areas = {}
ns.Areas = Areas

local floor = math.floor

local function cellKey(map, cx, cy)
  return map .. ":" .. cx .. ":" .. cy
end

-- Merge near-identical points (two sources listing one spawn), keeping the larger weight.
local function merge(points)
  local byCell, merged = {}, {}
  for _, p in ipairs(points) do
    local key = cellKey(p.map, floor(p.x / MERGE_YARDS), floor(p.y / MERGE_YARDS))
    local existing = byCell[key]
    local weight = p.weight or 1
    if existing then
      existing.weight = math.max(existing.weight, weight)
    else
      local copy = { map = p.map, x = p.x, y = p.y, weight = weight, source = p.source, kind = p.kind }
      byCell[key] = copy
      merged[#merged + 1] = copy
    end
  end
  return merged
end

---Areas of a set of points, heaviest first; each { map, points, weight, minX, minY, maxX, maxY, kept }.
---`kept` is false for areas lighter than MAIN_SHARE of the heaviest.
---@param points table[]
---@return table[]
function Areas:Build(points)
  points = merge(points)
  -- Occupied cells.
  local cells, cellList = {}, {}
  for _, p in ipairs(points) do
    local cx, cy = floor(p.x / CELL_YARDS), floor(p.y / CELL_YARDS)
    local key = cellKey(p.map, cx, cy)
    local cell = cells[key]
    if not cell then
      cell = { map = p.map, cx = cx, cy = cy, points = {} }
      cells[key] = cell
      cellList[#cellList + 1] = cell
    end
    cell.points[#cell.points + 1] = p
  end
  -- Connected groups of cells (8-neighbourhood), by flood fill.
  local areas = {}
  for _, start in ipairs(cellList) do
    if not start.area then
      local area = { map = start.map, points = {}, weight = 0 }
      areas[#areas + 1] = area
      start.area = area
      local stack = { start }
      while #stack > 0 do
        local cell = table.remove(stack)
        for _, p in ipairs(cell.points) do
          area.points[#area.points + 1] = p
          area.weight = area.weight + p.weight
          area.minX = math.min(area.minX or p.x, p.x)
          area.maxX = math.max(area.maxX or p.x, p.x)
          area.minY = math.min(area.minY or p.y, p.y)
          area.maxY = math.max(area.maxY or p.y, p.y)
        end
        for dx = -1, 1 do
          for dy = -1, 1 do
            local neighbour = cells[cellKey(cell.map, cell.cx + dx, cell.cy + dy)]
            if neighbour and not neighbour.area then
              neighbour.area = area
              stack[#stack + 1] = neighbour
            end
          end
        end
      end
    end
  end
  table.sort(areas, function(a, b) return a.weight > b.weight end)
  local heaviest = areas[1] and areas[1].weight or 0
  for _, area in ipairs(areas) do
    area.kept = area.weight >= heaviest * MAIN_SHARE
  end
  return areas
end

---The area's point nearest to a position on the same map, and its distance; nil if the area is on
---another map, or can't beat `limit` (its bounding box is already farther: skipped cheaply).
---@param area table
---@param map number
---@param x number
---@param y number
---@param limit number? only look for something closer than this
---@return table? point
---@return number? distance
function Areas:Nearest(area, map, x, y, limit)
  if area.map ~= map then
    return nil
  end
  if limit then
    local dx = math.max(area.minX - x, 0, x - area.maxX)
    local dy = math.max(area.minY - y, 0, y - area.maxY)
    if dx * dx + dy * dy >= limit * limit then
      return nil
    end
  end
  local best, bestSq
  for _, p in ipairs(area.points) do
    local dx, dy = p.x - x, p.y - y
    local d = dx * dx + dy * dy
    if not bestSq or d < bestSq then
      best, bestSq = p, d
    end
  end
  return best, bestSq and math.sqrt(bestSq)
end
