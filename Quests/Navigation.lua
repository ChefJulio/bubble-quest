local ADDON_NAME, ns = ...

-- Arrows (spec, Navigation arrows; docs/design/phase-5.md). For every visible card: the nearest
-- target, its distance, the arrow's angle, and whether the player is inside the objective's area.
--
-- Targets, best first:
--   1. forever-db spawn points of what each unfinished objective needs (or of the turn-in NPC when
--      the quest is ready). The nearest spawn point is the nearest edge of the area (spec).
--   2. the client's quest marker (GetQuestsOnMap), converted to world yards. One point: never
--      claims "in the area".
-- Positions are world yards on the instance map (0 Eastern Kingdoms, 1 Kalimdor, ...), so distances
-- work across zones. Hysteresis: the target switches only when the new one is SWITCH_RATIO closer.
--
-- [Assumes] axes: UnitPosition's first two values, GetWorldPosFromMapPos's x/y and forever-db's x/y
-- are all (north, west). /qm where prints them side by side to verify.

local TICK_SECONDS = 0.1   -- 10 updates a second (agreed in review)
local IN_AREA_YARDS = 40   -- tune in testing
local SWITCH_RATIO = 0.8   -- switch target only when at least 20% closer

local Navigation = {
  targets = {},  -- [questID] = { points = { { map, x, y, objective } }, spawnBased = bool }
  current = {},  -- [questID] = { map, x, y } the point the arrow pointed at last
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

-- "item:Kobold Vermin slain#2" -> "Kobold Vermin slain"
local function objectiveName(objective)
  return (objective.key:gsub("^[^:]*:", ""):gsub("#%d+$", ""))
end

local function buildTargets(quest)
  local points, spawnBased = {}, false
  local function add(list, objectiveIndex)
    for _, p in ipairs(list) do
      points[#points + 1] = { map = p.map, x = p.x, y = p.y, objective = objectiveIndex }
    end
    spawnBased = true
  end
  if quest.readyForTurnIn then
    local turnIn = ns.ForeverData:TurnInPoints(quest.questID)
    if turnIn then add(turnIn, nil) end
  else
    for i, objective in ipairs(quest.objectives) do
      if not objective.finished then
        local found = ns.ForeverData:ObjectivePoints(quest.questID, objectiveName(objective))
        if found then add(found, i) end
      end
    end
  end
  if #points == 0 then
    local marker = markerPoint(quest.questID)
    if marker then
      points[1] = marker
    end
  end
  return { points = points, spawnBased = spawnBased }
end

local function targetsFor(quest)
  local targets = Navigation.targets[quest.questID]
  if not targets then
    targets = buildTargets(quest)
    Navigation.targets[quest.questID] = targets
  end
  return targets
end

local function yards(n1, w1, n2, w2)
  local dn, dw = n2 - n1, w2 - w1
  return math.sqrt(dn * dn + dw * dw)
end

local function zoneNameOf(point, questID)
  if point.marker then
    return ns.Zone.questZone[questID]
  end
  if point.uiMap == nil then
    point.uiMap = ns.ForeverData:UiMapOf(point.map, point.x, point.y) or false
  end
  return point.uiMap and ns.Zone:MapName(point.uiMap) or nil
end

---Distance to the nearest target, no hysteresis (for sorting). Nil when unknown or on another map.
---@param quest table
---@return number?
function Navigation:Distance(quest)
  local north, west, instanceMap = self:PlayerPosition()
  if not north then
    return nil
  end
  local best
  for _, p in ipairs(targetsFor(quest).points) do
    if p.map == instanceMap then
      local d = yards(north, west, p.x, p.y)
      if not best or d < best then best = d end
    end
  end
  return best
end

---Everything a card's arrow needs, or nil (no position, no target).
---@param quest table
---@return table? nav { distance, angle?, inArea, objective?, zone? }
function Navigation:Compute(quest)
  local north, west, instanceMap = self:PlayerPosition()
  if not north then
    return nil
  end
  local targets = targetsFor(quest)
  local best, bestDistance, current, currentDistance
  local last = self.current[quest.questID]
  for _, p in ipairs(targets.points) do
    if p.map == instanceMap then
      local d = yards(north, west, p.x, p.y)
      if not best or d < bestDistance then
        best, bestDistance = p, d
      end
      if last and p.x == last.x and p.y == last.y then
        current, currentDistance = p, d
      end
    end
  end
  if not best then
    -- Target on another continent: name only, no arrow.
    local p = targets.points[1]
    return p and { zone = zoneNameOf(p, quest.questID) } or nil
  end
  if current and bestDistance > currentDistance * SWITCH_RATIO then
    best, bestDistance = current, currentDistance
  end
  self.current[quest.questID] = { x = best.x, y = best.y }

  local nav = { distance = bestDistance, objective = best.objective }
  nav.inArea = targets.spawnBased and bestDistance <= IN_AREA_YARDS
  local facing = GetPlayerFacing()
  if facing then
    -- Bearing counter-clockwise from north (towards west), minus where the player faces.
    nav.angle = math.atan2(best.y - west, best.x - north) - facing
  end
  local zone = zoneNameOf(best, quest.questID)
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
    end
  end
end)

-- Targets depend on progress, readiness and the markers; rebuild lazily after any of them change.
local function forget(questID)
  Navigation.targets[questID] = nil
end
ns.Bus:On("QuestChanged", function(quest) forget(quest.questID) end)
ns.Bus:On("QuestRemoved", function(questID)
  forget(questID)
  Navigation.current[questID] = nil
end)
local function forgetAll()
  wipe(Navigation.targets)
end
ns.Bus:On("QuestLogChanged", forgetAll)
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "QUEST_POI_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  ns.Events:On(event, forgetAll)
end
