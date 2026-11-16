local ADDON_NAME, ns = ...

-- QuestieDB's data (the database Questie reads, shipped as its own addon) as a navigation source
-- (docs/design/navigation-areas.md), read at runtime from the player's install, never bundled.
-- Through QuestieDB's public library, written for other addons: "Another addon can read entity
-- fields ... Questie is the first consumer, but nothing here assumes it" (QuestieDB/src/api.lua:3-6),
-- versioned by contract (RequireContract). Questie itself isn't needed (review, 2026-11-16:
-- Questmarker is replacing Questie; docs/design/available-quests.md): QuestieDB applies its own
-- corrections at load, so its data is usable as soon as it's loaded, and it publishes the area ->
-- uiMap table Questie's ZoneDB reads. With Questie also running, its extra corrections land when it's
-- ready (RegisterOnReady), and the cache is dropped then.
--
-- Shapes (QuestieDB/Types/General.t.lua): QuestDB.objectives(id) = { [1] creatures {npcId, text?},
-- [2] objects {objectId, text?}, [3] items {itemId, text?}, [4] reputation, [5] kill credit
-- {npcIds, rootNpcId, text?}, [6] spells }; triggerEnd(id) = { text, spawnList } (exploration);
-- finishedBy(id) = { npcIds?, objectIds? }; spawn lists are { [areaId] = { {x, y, phase?}, ... } }
-- with x/y in 0-100 percent of that zone's map, {-1, -1} meaning "inside an instance" (skipped).
-- Area IDs become uiMapIDs through QuestieDB's published ZoneDB table
-- (LibQuestieDB.Support.Get("ZoneDB").private.areaIdToUiMapId, the table Questie's
-- ZoneDB:GetUiMapIdByAreaId reads; a miss skips the spawn), then world yards through
-- C_Map.GetWorldPosFromMapPos, as the map marker is.
--
-- Used when QuestieDB is loaded with a compatible contract and the setting "Use QuestieDB's location
-- data" is on.

local CONTRACT = 4

local QuestieData = {
  cache = {},  -- [questID .. ":" .. key] = points or false
}
ns.QuestieData = QuestieData

local function library()
  local lib = rawget(_G, "LibQuestieDB")
  return type(lib) == "table" and lib or nil
end

-- QuestieDB publishes its zone tables as Lua source ("[[return { ... }]]",
-- QuestieDB/support/Forever/Zones/areaIdToUiMapId.lua), which Questie's ZoneDB compiles at startup
-- (Questie/Database/Zones/zoneDB.lua:73-90). A table is taken as is.
local function decodeTable(value)
  if type(value) == "table" then
    return value
  end
  if type(value) ~= "string" then
    return nil
  end
  local chunk = loadstring(value)
  local ok, result = false, nil
  if chunk then
    ok, result = pcall(chunk)
  end
  return ok and type(result) == "table" and result or nil
end

-- QuestieDB's area -> uiMap table, built once as Questie's ZoneDB does: the table, then its
-- overrides on top (0 = not displayed). False: not available. (Review: read as a table only, the
-- source string was missed and no quest giver had a position.)
local areaToUiMap
local function uiMapOf(areaId)
  if areaToUiMap == nil then
    local lib = library()
    local ok, zone = false, nil
    if lib and type(lib.Support) == "table" and type(lib.Support.Get) == "function" then
      ok, zone = pcall(lib.Support.Get, "ZoneDB")
    end
    local private = ok and type(zone) == "table" and type(zone.private) == "table" and zone.private or {}
    local base = decodeTable(private.areaIdToUiMapId)
    if base then
      for id, uiMap in pairs(decodeTable(private.areaIdToUiMapIdOverride) or {}) do
        base[id] = uiMap
      end
    end
    areaToUiMap = base or false
  end
  local uiMap = areaToUiMap and areaToUiMap[areaId]
  return type(uiMap) == "number" and uiMap > 0 and uiMap or nil
end

---Installed with a compatible contract (whatever the setting says).
---@return boolean
function QuestieData:Installed()
  local lib = library()
  return lib ~= nil and type(lib.RequireContract) == "function" and lib.RequireContract(CONTRACT) == true
end

---Usable right now: installed, compatible, and the setting on.
---@return boolean
function QuestieData:Available()
  return ns.DB.profile ~= nil and ns.DB.profile.questieData == true and self:Installed()
end

-- A QuestieDB getter, guarded. dbName: "QuestDB", "NpcDB", "ItemDB" or "ObjectDB" (the library's
-- entities: LibQuestieDB.Quest, ...).
local function get(dbName, field, id)
  local lib = library()
  local t = lib and lib[dbName:sub(1, -3)]
  local fn = type(t) == "table" and t[field]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, id)
  return ok and value or nil
end

-- kind: "npc", "object" or "explore" (navigation's "here" distance depends on it).
local function addSpawnList(spawnList, points, kind)
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
            points[#points + 1] = { map = instanceMap, x = world.x, y = world.y, kind = kind }
          end
        end
      end
    end
  end
end

local function addEntitySpawns(dbName, id, points)
  addSpawnList(get(dbName, "spawns", id), points, dbName == "ObjectDB" and "object" or "npc")
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
      addSpawnList(trigger[2], points, "explore")
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

---How many areas QuestieDB's zone table maps (for /qm available); 0 when it couldn't be read.
---@return number
function QuestieData:ZoneCount()
  uiMapOf(0)  -- builds the table on first use
  local n = 0
  for _ in pairs(areaToUiMap or {}) do
    n = n + 1
  end
  return n
end

-- Shared with the available-quest index (Quests/Available.lua).
QuestieData.Library = library
QuestieData.Get = get

---Every spawn of an NPC ("npc") or object ("object") in world yards, cached; nil when none known.
---@param kind string
---@param id number
---@return table? points { { map, x, y, kind } }
function QuestieData:EntityPoints(kind, id)
  return cached(kind .. "#" .. id, function(points)
    addEntitySpawns(kind == "object" and "ObjectDB" or "NpcDB", id, points)
  end)
end

function QuestieData:Reset()
  wipe(self.cache)
  ns.Bus:Fire("LocationsChanged")
end

-- With Questie also running: it adds its own corrections when ready, so cached answers are stale.
ns.Events:On("PLAYER_LOGIN", function()
  local q = rawget(_G, "Questie")
  local api = type(q) == "table" and q.API
  if type(api) == "table" and type(api.RegisterOnReady) == "function" then
    pcall(api.RegisterOnReady, function() QuestieData:Reset() end)
  end
end)
