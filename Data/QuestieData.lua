local ADDON_NAME, ns = ...

-- Questie's location data as a navigation source (docs/design/navigation-areas.md), read at runtime
-- from the player's own Questie install, never bundled. Through QuestieDB's public library, written
-- for other addons: "Another addon can read entity fields ... Questie is the first consumer, but
-- nothing here assumes it" (QuestieDB/src/api.lua:3-6), versioned by contract (RequireContract).
--
-- Shapes (QuestieDB/Types/General.t.lua): QuestDB.objectives(id) = { [1] creatures {npcId, text?},
-- [2] objects {objectId, text?}, [3] items {itemId, text?}, [4] reputation, [5] kill credit
-- {npcIds, rootNpcId, text?}, [6] spells }; triggerEnd(id) = { text, spawnList } (exploration);
-- finishedBy(id) = { npcIds?, objectIds? }; spawn lists are { [areaId] = { {x, y, phase?}, ... } }
-- with x/y in 0-100 percent of that zone's map, {-1, -1} meaning "inside an instance" (skipped).
-- Area IDs become uiMapIDs through Questie's ZoneDB:GetUiMapIdByAreaId (internal: guarded, a miss
-- skips the spawn), then world yards through C_Map.GetWorldPosFromMapPos, as the map marker is.
--
-- Used only when Questie is ready (Questie.API.isReady; RegisterOnReady fires LocationsChanged) and
-- the setting "Use Questie's location data" is on.

local CONTRACT = 4

local QuestieData = {
  cache = {},  -- [questID .. ":" .. key] = points or false
}
ns.QuestieData = QuestieData

local function questie()
  local q = rawget(_G, "Questie")
  return type(q) == "table" and q or nil
end

local function db(name)
  local t = rawget(_G, name)
  return type(t) == "table" and t or nil
end

local zoneDB
local function uiMapOf(areaId)
  if zoneDB == nil then
    local loader = rawget(_G, "QuestieLoader")
    local ok, module = false, nil
    if type(loader) == "table" and type(loader.ImportModule) == "function" then
      ok, module = pcall(loader.ImportModule, loader, "ZoneDB")
    end
    zoneDB = ok and type(module) == "table" and type(module.GetUiMapIdByAreaId) == "function" and module or false
  end
  if not zoneDB then
    return nil
  end
  local ok, uiMap = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
  return ok and type(uiMap) == "number" and uiMap or nil
end

---Usable right now: installed, compatible, ready, and the setting on.
---@return boolean
function QuestieData:Available()
  local lib, q = db("LibQuestieDB"), questie()
  if not lib or not q or not (ns.DB.profile and ns.DB.profile.questieData) then
    return false
  end
  if type(lib.RequireContract) ~= "function" or not lib.RequireContract(CONTRACT) then
    return false
  end
  return type(q.API) == "table" and q.API.isReady == true
end

-- A QuestieDB getter, guarded.
local function get(dbName, field, id)
  local t = db(dbName)
  local fn = t and t[field]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, id)
  return ok and value or nil
end

local function addSpawnList(spawnList, points)
  if type(spawnList) ~= "table" then
    return
  end
  for areaId, coords in pairs(spawnList) do
    local uiMap = uiMapOf(areaId)
    if uiMap and type(coords) == "table" then
      for _, c in ipairs(coords) do
        local x, y = c[1], c[2]
        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
          local instanceMap, world = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(x / 100, y / 100))
          if world then
            points[#points + 1] = { map = instanceMap, x = world.x, y = world.y }
          end
        end
      end
    end
  end
end

local function addEntitySpawns(dbName, id, points)
  addSpawnList(get(dbName, "spawns", id), points)
end

-- Does Questie's name for a target match our objective's name? Either contains the other, as the
-- arrows' rule ("Kobold Vermin slain" contains "Kobold Vermin").
local function matches(objectiveName, targetName)
  if type(targetName) ~= "string" or targetName == "" then
    return false
  end
  local a, b = objectiveName:lower(), targetName:lower()
  return a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

local function cached(key, build)
  local hit = QuestieData.cache[key]
  if hit ~= nil then
    return hit or nil
  end
  local points = {}
  build(points)
  QuestieData.cache[key] = #points > 0 and points or false
  return QuestieData.cache[key] or nil
end

---Spawn points of what an objective needs, from Questie, or nil.
---@param questID number
---@param objectiveName string objective text without its counter
---@return table? points { { map, x, y } }
function QuestieData:ObjectivePoints(questID, objectiveName)
  if not self:Available() then
    return nil
  end
  return cached(questID .. ":" .. objectiveName, function(points)
    local objectives = get("QuestDB", "objectives", questID)
    if type(objectives) == "table" then
      for _, o in ipairs(objectives[1] or {}) do  -- creatures
        if matches(objectiveName, o[2] or get("NpcDB", "name", o[1])) then
          addEntitySpawns("NpcDB", o[1], points)
        end
      end
      for _, o in ipairs(objectives[5] or {}) do  -- kill credit: any of several creatures
        if matches(objectiveName, o[3] or get("NpcDB", "name", o[2])) then
          for _, npcId in ipairs(o[1] or {}) do
            addEntitySpawns("NpcDB", npcId, points)
          end
        end
      end
      for _, o in ipairs(objectives[2] or {}) do  -- objects
        if matches(objectiveName, o[2] or get("ObjectDB", "name", o[1])) then
          addEntitySpawns("ObjectDB", o[1], points)
        end
      end
      for _, o in ipairs(objectives[3] or {}) do  -- items: where they drop
        if matches(objectiveName, o[2] or get("ItemDB", "name", o[1])) then
          for _, npcId in ipairs(get("ItemDB", "npcDrops", o[1]) or {}) do
            addEntitySpawns("NpcDB", npcId, points)
          end
          for _, objectId in ipairs(get("ItemDB", "objectDrops", o[1]) or {}) do
            addEntitySpawns("ObjectDB", objectId, points)
          end
        end
      end
    end
    -- Exploration ("Scout through ..."): the trigger's area.
    local trigger = get("QuestDB", "triggerEnd", questID)
    if type(trigger) == "table" and matches(objectiveName, trigger[1]) then
      addSpawnList(trigger[2], points)
    end
  end)
end

---Spawn points of whoever takes the quest in, from Questie, or nil.
---@param questID number
---@return table?
function QuestieData:TurnInPoints(questID)
  if not self:Available() then
    return nil
  end
  return cached(questID .. ":turnin", function(points)
    local finishers = get("QuestDB", "finishedBy", questID)
    if type(finishers) == "table" then
      for _, npcId in ipairs(finishers[1] or {}) do
        addEntitySpawns("NpcDB", npcId, points)
      end
      for _, objectId in ipairs(finishers[2] or {}) do
        addEntitySpawns("ObjectDB", objectId, points)
      end
    end
  end)
end

function QuestieData:Reset()
  wipe(self.cache)
  ns.Bus:Fire("LocationsChanged")
end

-- Questie becomes ready after its own startup; then our cached "nothing" answers are stale.
ns.Events:On("PLAYER_LOGIN", function()
  local q = questie()
  local api = q and q.API
  if type(api) == "table" and type(api.RegisterOnReady) == "function" then
    pcall(api.RegisterOnReady, function() QuestieData:Reset() end)
  end
end)
