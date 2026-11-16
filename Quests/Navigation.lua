local ADDON_NAME, ns = ...

-- Arrows (spec, Navigation arrows). For every visible card: the target, its distance, the arrow's
-- angle, and whether the player is inside the objective's area. Areas, not points
-- (docs/design/navigation-areas.md, replacing phase 5's nearest point):
--
--   1. Each unfinished objective's locations, from every source: Questie (Data/QuestieData.lua, when
--      installed), forever-db, and spots learned in play (weighted by sightings). The turn-in's when
--      the quest is ready.
--   2. Grouped into areas (Quests/Areas.lua); areas tiny next to the objective's biggest are ignored
--      (a stray spawn far from the camp).
--   3. The arrow points at the nearest edge (nearest point) of the nearest kept area, any objective.
--      Hysteresis: switch areas only when another is SWITCH_RATIO closer.
--   4. "Here": within HERE_YARDS of a kept, spawn-based area, by what it is (an area takes the kind
--      most of its points have), or an objective mob's nameplate up.
--   5. Nothing known: the client's quest marker (GetQuestsOnMap) as one point; never claims "here".
-- Positions are world yards on the instance map (0 Eastern Kingdoms, 1 Kalimdor, ...), so distances
-- work across zones. Axes (north, west) verified in game with /qm where.

local TICK_SECONDS = 0.1   -- 10 updates a second (agreed in review)
-- "Here" distance by what the area is (decided in review): a turn-in you must be at (not 5: location
-- data is often a few yards off the NPC, who may wander); an object you must be near; a place; mobs,
-- which roam (their nameplates confirm it too).
local HERE_YARDS = { turnin = 10, object = 20, explore = 30, npc = 40 }
local SWITCH_RATIO = 0.8   -- switch area only when another is at least 20% closer
local MAX_LEARNED_WEIGHT = 3

local Navigation = {
  targets = {},  -- [questID] = { areas = { kept areas }, byObjective = { [index] = all areas }, spawnBased }
  current = {},  -- [questID] = { id, x, y } the area and point the arrow pointed at last
}
ns.Navigation = Navigation

---The player's world position, or nil (instances, loading).
---@return number? north
---@return number? west
---@return number? instanceMap
function Navigation:PlayerPosition()
  local north, west, _, instanceMap = UnitPosition("player")
  if not north then
    return nil
  end
  return north, west, instanceMap
end

local function markerPoint(questID)
  local marker, continent = ns.Zone.markers[questID], ns.Zone.continentID
  if not marker or not continent then
    return nil
  end
  local instanceMap, world = C_Map.GetWorldPosFromMapPos(continent, CreateVector2D(marker.x, marker.y))
  if not world then
    return nil
  end
  return { map = instanceMap, x = world.x, y = world.y, marker = true }
end

local objectiveName = ns.QuestLog.ObjectiveName

-- Every source's points for one objective (or the turn-in: objective nil), tagged with their source.
local function collect(questID, name)
  local points = {}
  local function add(list, source, weightOf)
    for _, p in ipairs(list or {}) do
      points[#points + 1] = {
        map = p.map, x = p.x, y = p.y, source = source, kind = p.kind or "npc", weight = weightOf and weightOf(p) or 1,
      }
    end
  end
  if name then
    add(ns.QuestieData:ObjectivePoints(questID, name), "questie")
    add(ns.ForeverData:ObjectivePoints(questID, name), "forever-db")
    add(ns.Learned:Points(questID, name), "learned", function(p)
      return math.min(p.n or 1, MAX_LEARNED_WEIGHT)
    end)
  else
    add(ns.QuestieData:TurnInPoints(questID), "questie")
    add(ns.ForeverData:TurnInPoints(questID), "forever-db")
  end
  return points
end

-- What an area is: the kind most of its points have ("npc", "object", "explore").
local function mainKind(area)
  local counts, best = {}, "npc"
  for _, p in ipairs(area.points) do
    counts[p.kind] = (counts[p.kind] or 0) + 1
    if counts[p.kind] > (counts[best] or 0) then
      best = p.kind
    end
  end
  return best
end

-- An area's identity across rebuilds, for hysteresis: objective and corner.
local function areaID(area)
  return ("%s:%d:%d:%d"):format(tostring(area.objective), area.map, math.floor(area.minX), math.floor(area.minY))
end

local function buildTargets(quest)
  local targets = { areas = {}, byObjective = {}, spawnBased = false }
  local function addAreas(points, objectiveIndex)
    if #points == 0 then
      return
    end
    local areas = ns.Areas:Build(points)
    targets.byObjective[objectiveIndex or "turnin"] = areas
    for _, area in ipairs(areas) do
      area.objective = objectiveIndex
      area.id = areaID(area)
      area.kind = objectiveIndex and mainKind(area) or "turnin"
      if area.kept then
        targets.areas[#targets.areas + 1] = area
        targets.spawnBased = true
      end
    end
  end
  if quest.readyForTurnIn then
    addAreas(collect(quest.questID, nil), nil)
  else
    for i, objective in ipairs(quest.objectives) do
      if not objective.finished then
        addAreas(collect(quest.questID, objectiveName(objective)), i)
      end
    end
  end
  if #targets.areas == 0 then
    local marker = markerPoint(quest.questID)
    if marker then
      local area = { map = marker.map, points = { marker }, weight = 1, kept = true, marker = true,
        minX = marker.x, maxX = marker.x, minY = marker.y, maxY = marker.y }
      area.id = "marker"
      targets.areas[1] = area
    end
  end
  return targets
end

local function targetsFor(quest)
  local targets = Navigation.targets[quest.questID]
  if not targets then
    targets = buildTargets(quest)
    Navigation.targets[quest.questID] = targets
  end
  return targets
end

---The quest's areas, built on first use (for /qm areas).
---@param quest table
---@return table targets
function Navigation:Targets(quest)
  return targetsFor(quest)
end

-- The nearest kept area on this map, its nearest point and distance (no hysteresis).
local function nearestArea(targets, north, west, instanceMap)
  local best, bestPoint, bestDistance
  for _, area in ipairs(targets.areas) do
    local point, d = ns.Areas:Nearest(area, instanceMap, north, west, bestDistance)
    if point and (not bestDistance or d < bestDistance) then
      best, bestPoint, bestDistance = area, point, d
    end
  end
  return best, bestPoint, bestDistance
end

-- The zone a target point is in, for the "other zone" label. The client decides whether it lies on
-- the player's own zone map. LibForeverData's ToUiMap picks the smallest map rectangle holding the
-- point, which is wrong where rectangles overlap at zone borders (Defias Thugs in Northshire came
-- out as Burning Steppes, verified in game); it is only used to name zones the player isn't in.
-- Cached on the point; targets are rebuilt on every zone change.
local function zoneNameOf(point, questID)
  if point.marker then
    return ns.Zone.questZone[questID]
  end
  if point.zone == nil then
    local zoneMap, world = ns.Zone.mapID, CreateVector2D(point.x, point.y)
    local _, position
    if zoneMap then
      _, position = C_Map.GetMapPosFromWorldPos(point.map, world, zoneMap)
    end
    if position and position.x >= 0 and position.x <= 1 and position.y >= 0 and position.y <= 1 then
      point.zone = ns.Zone.name or false
    else
      local uiMap = ns.ForeverData:UiMapOf(point.map, point.x, point.y)
      point.zone = uiMap and ns.Zone:MapName(uiMap) or false
    end
  end
  return point.zone or nil
end

---Distance to the nearest kept area, no hysteresis (for sorting). Nil when unknown or on another map.
---@param quest table
---@return number?
function Navigation:Distance(quest)
  local north, west, instanceMap = self:PlayerPosition()
  if not north then
    return nil
  end
  local _, _, distance = nearestArea(targetsFor(quest), north, west, instanceMap)
  return distance
end

-- A creature for one of the quest's unfinished objectives has its nameplate up (Quests/Nearby.lua):
-- the player is in the area whatever the target data says. Returns that objective's index.
local function nearbyObjective(quest)
  if quest.readyForTurnIn or not ns.Nearby:Has(quest.questID) then
    return nil
  end
  for i, objective in ipairs(quest.objectives) do
    if not objective.finished and ns.Nearby:Has(quest.questID, objectiveName(objective)) then
      return i
    end
  end
  return nil
end

local function hereYards(area)
  return HERE_YARDS[area.kind] or HERE_YARDS.npc
end

---Is the player in one of the quest's objective areas right now: a creature for it on the nameplates,
---or within its "here" distance (HERE_YARDS, by kind) of a kept area's point (not a marker: one point
---can't tell). Defined after nearbyObjective, a local it needs.
---@param quest table
---@return boolean
function Navigation:InArea(quest)
  if nearbyObjective(quest) then
    return true
  end
  local north, west, instanceMap = self:PlayerPosition()
  if not north then
    return false
  end
  for _, area in ipairs(targetsFor(quest).areas) do
    if not area.marker and ns.Areas:Nearest(area, instanceMap, north, west, hereYards(area)) then
      return true
    end
  end
  return false
end

local COMPASS = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }  -- counter-clockwise from north

---Where one objective is, on its own (review: "the areas are in different places"): each objective
---row's arrow and the tooltip's per-objective distances. Nil when unknown.
---@param quest table
---@param index number objective index
---@return table? { distance, compass, angle?, inArea } or { zone } on another map
function Navigation:ObjectiveNav(quest, index)
  local areas = targetsFor(quest).byObjective[index]
  local north, west, instanceMap = self:PlayerPosition()
  if not areas or not north then
    return nil
  end
  local best, bestPoint, bestDistance
  for _, area in ipairs(areas) do
    if area.kept then
      local point, d = ns.Areas:Nearest(area, instanceMap, north, west, bestDistance)
      if point and (not bestDistance or d < bestDistance) then
        best, bestPoint, bestDistance = area, point, d
      end
    end
  end
  if not best then
    for _, area in ipairs(areas) do
      if area.kept then
        return { zone = zoneNameOf(area.points[1], quest.questID) }
      end
    end
    return nil
  end
  -- Bearing counter-clockwise from north, as the arrow's; the eighth of the compass it falls in; and
  -- the angle for an arrow (bearing minus facing), as the card's.
  local bearing = math.atan2(bestPoint.y - west, bestPoint.x - north)
  local facing = GetPlayerFacing()
  return {
    distance = bestDistance,
    compass = COMPASS[math.floor((math.deg(bearing) % 360 + 22.5) / 45) % 8 + 1],
    angle = facing and bearing - facing or nil,
    inArea = bestDistance <= hereYards(best),
  }
end

---Everything a card's arrow needs, or nil (no position, no target).
---@param quest table
---@return table? nav { distance, angle?, inArea, objective?, zone? }
function Navigation:Compute(quest)
  local nav = self:ComputeTarget(quest)
  local nearby = nearbyObjective(quest)
  if nearby then
    nav = nav or {}
    nav.inArea, nav.objective = true, nearby
  end
  return nav
end

function Navigation:ComputeTarget(quest)
  local north, west, instanceMap = self:PlayerPosition()
  if not north then
    return nil
  end
  local targets = targetsFor(quest)
  local area, point, distance = nearestArea(targets, north, west, instanceMap)
  if not area then
    -- Target on another continent: name only, no arrow.
    local first = targets.areas[1]
    local p = first and first.points[1]
    return p and { zone = zoneNameOf(p, quest.questID) } or nil
  end
  -- Hysteresis: stay with the last area unless this one is clearly closer.
  local last = self.current[quest.questID]
  if last and last.id ~= area.id then
    for _, other in ipairs(targets.areas) do
      if other.id == last.id then
        local otherPoint, otherDistance = ns.Areas:Nearest(other, instanceMap, north, west)
        if otherPoint and distance > otherDistance * SWITCH_RATIO then
          area, point, distance = other, otherPoint, otherDistance
        end
        break
      end
    end
  end
  self.current[quest.questID] = { id = area.id, x = point.x, y = point.y }

  local nav = { distance = distance, objective = area.objective }
  nav.inArea = not area.marker and distance <= hereYards(area)
  local facing = GetPlayerFacing()
  if facing then
    -- Bearing counter-clockwise from north (towards west), minus where the player faces.
    nav.angle = math.atan2(point.y - west, point.x - north) - facing
  end
  local zone = zoneNameOf(point, quest.questID)
  if zone and zone ~= ns.Zone.name then
    nav.zone = zone
  end
  return nav
end

-- Clicking a card (decided in review): highlight the quest and open the map at it. Out of combat
-- only: calling Blizzard UI code from an addon can taint it, which only bites in combat.
function Navigation:ShowOnMap(questID)
  if InCombatLockdown() then
    return
  end
  C_SuperTrack.SetSuperTrackedQuestID(questID)
  QuestMapFrame_OpenToQuestDetails(questID)
end

-- Driver --------------------------------------------------------------------------------------------

local elapsed = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, delta)
  elapsed = elapsed + delta
  if elapsed < TICK_SECONDS then
    return
  end
  elapsed = 0
  for questID, card in pairs(ns.Stack.visible) do
    local quest = ns.QuestLog:Get(questID)
    if quest then
      card:SetNavigation(Navigation:Compute(quest))
      card:UpdateObjectiveNavigation(quest)
      card:UpdateTimer()
    end
  end
end)

-- Targets depend on progress, readiness and the markers; rebuild lazily after any of them change.
local function forget(questID)
  Navigation.targets[questID] = nil
end
ns.Bus:On("QuestChanged", function(quest) forget(quest.questID) end)
ns.Bus:On("LearnedChanged", forget)
ns.Bus:On("QuestRemoved", function(questID)
  forget(questID)
  Navigation.current[questID] = nil
end)
local function forgetAll()
  wipe(Navigation.targets)
end
ns.Bus:On("QuestLogChanged", forgetAll)
ns.Bus:On("LocationsChanged", forgetAll)  -- Questie became ready, or its setting changed
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "QUEST_POI_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  ns.Events:On(event, forgetAll)
end
