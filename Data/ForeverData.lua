local ADDON_NAME, ns = ...

-- The only file that touches LibForeverData (bundled in Libs/LibForeverData, see
-- THIRD-PARTY-NOTICES). Everything else asks this adapter, so a library change lands in one place.
--
-- The library is read through the global, not ns.LibForeverData: if another addon loaded an equal or
-- newer copy first, ours steps aside and only the global points at the live copy (Core.lua:37-41).
-- Supports library API 1; any other version means "no data", never an error.

local SUPPORTED_API = 1

local ForeverData = {
  cache = {},  -- [questID] = record or false (looked up, not in the data)
}
ns.ForeverData = ForeverData

---@return table?
local function library()
  local lib = rawget(_G, "LibForeverData")
  if type(lib) == "table" and lib.api == SUPPORTED_API then
    return lib
  end
  return nil
end

---@return boolean
function ForeverData:Available()
  return library() ~= nil
end

---@return string? version forever-db data version, e.g. "2026.11.1"
function ForeverData:Version()
  local lib = library()
  return lib and lib.version
end

---The forever-db record for a quest, or nil (unknown quest, or no library).
---@param questID number
---@return table?
function ForeverData:Quest(questID)
  local cached = self.cache[questID]
  if cached ~= nil then
    return cached or nil
  end
  local lib = library()
  if not lib then
    return nil
  end
  local record = lib.Quest(questID)
  self.cache[questID] = record or false
  return record
end

-- For the available-quest index when QuestieDB isn't installed (Quests/Available.lua's forever source).

---Every quest ID in forever-db.
---@return number[]
function ForeverData:QuestIds()
  local lib = library()
  return lib and lib.Ids("quest") or {}
end

---Every object ID in forever-db (town services: mailboxes).
---@return number[]
function ForeverData:ObjectIds()
  local lib = library()
  return lib and lib.Ids("object") or {}
end

---An NPC's or object's name.
---@param kind string "npc" or "object" (or "item")
---@param id number
---@return string?
function ForeverData:Name(kind, id)
  local lib = library()
  return lib and lib.Name(kind, id)
end

---Every spawn of an NPC or object, in world yards: { { map, x, y, kind } }, cached; nil when none.
---@param kind string "npc" or "object"
---@param id number
---@return table?
function ForeverData:EntityPoints(kind, id)
  local key = "spawns:" .. kind .. id
  local hit = self.cache[key]
  if hit == nil then
    local lib = library()
    local points = {}
    for _, p in ipairs(lib and lib.Spawns(kind, id) or {}) do
      points[#points + 1] = { map = p.map, x = p.x, y = p.y, kind = kind }
    end
    hit = #points > 0 and points or false
    self.cache[key] = hit
  end
  return hit or nil
end

---Who drops an item: NPC ids and object ids.
---@param itemID number
---@return number[] npcs
---@return number[] objects
function ForeverData:ItemDroppers(itemID)
  local lib = library()
  local item = lib and lib.Get("item", itemID)
  return item and item.npcDrops or {}, item and item.objectDrops or {}
end

---An item's drop chances by source: { ["npc" .. id | "object" .. id] = percent }, or nil.
---@param itemID number
---@return table?
function ForeverData:DropChances(itemID)
  local lib = library()
  local item = lib and lib.Get("item", itemID)
  if not item or not item.sources then
    return nil
  end
  local chances = {}
  for _, source in ipairs(item.sources) do
    if source.kind and source.id and source.chance then
      chances[source.kind .. source.id] = source.chance
    end
  end
  return chances
end

---Who (or what) takes the quest in: the first finisher's name.
---@param questID number
---@return string?
function ForeverData:TurnInName(questID)
  local lib = library()
  local record = self:Quest(questID)
  local finisher = record and record.finish and record.finish[1]
  if not lib or not finisher or not finisher.kind or not finisher.id then
    return nil
  end
  return lib.Name(finisher.kind, finisher.id)
end

local MAX_SOURCE_NAMES = 2

-- Yards from the player to a creature's or object's nearest spawn on this continent, or nil.
local function nearestSpawn(lib, kind, id)
  local north, west, map = ns.Navigation:PlayerPosition()
  if not north then
    return nil
  end
  local best
  for _, p in ipairs(lib.Spawns(kind, id)) do
    if p.map == map then
      local dn, dw = p.x - north, p.y - west
      local d = dn * dn + dw * dw
      if not best or d < best then
        best = d
      end
    end
  end
  return best and math.sqrt(best) or nil
end

---Where a collect objective's item comes from, matched by item name among the quest's item
---objectives. Coverage: about half of item objectives, mostly classic quests; few Forever-new ones.
---@param questID number
---@param itemName string the objective text without its counter
---@param maxNames number? names to list before counting the rest in `more` (default 2)
---@return table? sources { kind = "npc" | "object" | "item", names = { ... }, more = n,
---  chances = { [name] = percent, the best of that name's sources } }
function ForeverData:ItemSources(questID, itemName, maxNames)
  maxNames = maxNames or MAX_SOURCE_NAMES
  local lib = library()
  local record = self:Quest(questID)
  if not lib or not record then
    return nil
  end
  for _, objective in ipairs(record.objectives or {}) do
    if objective.kind == "item" and objective.target and lib.Name("item", objective.target) == itemName then
      local item = lib.Get("item", objective.target)
      local sources = item and item.sources or {}
      if not sources[1] then
        return nil
      end
      -- The main kind (npc / object / item) is that of the likeliest source.
      local best = sources[1]
      for _, source in ipairs(sources) do
        if (source.chance or 0) > (best.chance or 0) then
          best = source
        end
      end
      -- Nearest first (closest spawn to the player, this continent), then by drop chance: sorted by
      -- chance alone, a Loch Modan quest led with Badlands boars and Ashenvale bears (seen in review).
      local list, distance = {}, {}
      for _, source in ipairs(sources) do
        if source.kind == best.kind then
          list[#list + 1] = source
          distance[source] = nearestSpawn(lib, source.kind, source.id)
        end
      end
      table.sort(list, function(a, b)
        local da, db = distance[a], distance[b]
        if da ~= db then
          if da and db then return da < db end
          return da ~= nil
        end
        return (a.chance or 0) > (b.chance or 0)
      end)
      local result = { kind = best.kind, names = {}, more = 0, chances = {} }
      for _, source in ipairs(list) do
        local name = lib.Name(source.kind, source.id)
        if #result.names < maxNames then
          result.names[#result.names + 1] = name
        else
          result.more = result.more + 1
        end
        if name and source.chance and (result.chances[name] or 0) < source.chance then
          result.chances[name] = source.chance
        end
      end
      return result
    end
  end
  return nil
end

-- Spawn points (phase 5 arrows) -------------------------------------------------------------------

-- forever-db objective kind -> the record kind its target is.
local TARGET_KIND = { kill = "npc", talk = "npc", object = "object", item = "item" }

-- Copies (the library's own tables stay untouched), tagged with what they are: "npc" or "object"
-- (navigation's "here" distance depends on it).
local function addSpawns(lib, kind, id, points)
  for _, point in ipairs(lib.Spawns(kind, id)) do
    points[#points + 1] = { map = point.map, x = point.x, y = point.y, kind = kind }
  end
end

local pointCache = {}  -- [questID .. ":" .. text] = points or false

-- The quest objective an objective's text is about: the first whose target's name it contains
-- ("Kobold Vermin slain" -> Kobold Vermin). Returns the objective, its target's kind and name.
local function objectiveFor(lib, record, text)
  for _, objective in ipairs(record.objectives or {}) do
    local kind = TARGET_KIND[objective.kind]
    local name = kind and objective.target and lib.Name(kind, objective.target)
    if name and text:find(name, 1, true) then
      return objective, kind, name
    end
  end
  return nil
end

-- Guide steps (lib.Steps: action, targetKind, target, place { map, x, y } in world yards, text) as a
-- location source. A step is about the objective when it targets the objective's own target (then
-- only its place adds anything), or, for an item objective, when it's a loot / kill / gather step on a
-- creature or object and the quest has one item objective or the step names the item: that's where
-- the item comes from, often the only record of it (review: a quarter of item objectives list no
-- dropper; most of those have steps).
local SOURCE_ACTIONS = { loot = true, kill = true, ["collect-object"] = true, ["use-item"] = true }

local function addStepPoints(lib, questID, record, objective, kind, name, points, added)
  local items = 0
  for _, o in ipairs(record.objectives or {}) do
    items = items + (o.kind == "item" and 1 or 0)
  end
  local lowerName = name:lower()
  for _, step in ipairs(lib.Steps(questID)) do
    local stepKind, target = step.targetKind, step.target
    local about = stepKind == kind and target == objective.target
    if not about and kind == "item" and SOURCE_ACTIONS[step.action] and target
        and (stepKind == "npc" or stepKind == "object")
        and (items == 1 or (step.text and step.text:lower():find(lowerName, 1, true))) then
      about = true
      if not added[stepKind .. target] then
        added[stepKind .. target] = true
        addSpawns(lib, stepKind, target, points)
      end
    end
    local place = about and step.place
    if place and place.map and place.x and place.y then
      points[#points + 1] = { map = place.map, x = place.x, y = place.y,
        kind = (stepKind == "npc" or stepKind == "object") and stepKind or "explore" }
    end
  end
end

---Points (world yards: { map, x, y, kind }) of whatever an objective needs, from forever-db: the
---creature to kill or talk to, the object to use, or the creatures/objects an item comes from (its
---listed droppers, and guide steps that say where it's got), plus the places guide steps name for it.
---@param questID number
---@param text string the objective's text
---@return table? points, nil when forever-db has none
function ForeverData:ObjectivePoints(questID, text)
  local key = questID .. ":" .. text
  if pointCache[key] ~= nil then
    return pointCache[key] or nil
  end
  local lib, record = library(), self:Quest(questID)
  local points = {}
  if lib and record then
    local objective, kind, name = objectiveFor(lib, record, text)
    if objective and kind and name then
      local added = {}  -- [kind .. id]: spawns already in
      if kind == "item" then
        local item = lib.Get("item", objective.target)
        for _, source in ipairs(item and item.sources or {}) do
          if (source.kind == "npc" or source.kind == "object") and not added[source.kind .. source.id] then
            added[source.kind .. source.id] = true
            addSpawns(lib, source.kind, source.id, points)
          end
        end
      else
        addSpawns(lib, kind, objective.target, points)
      end
      addStepPoints(lib, questID, record, objective, kind, name, points, added)
    end
  end
  pointCache[key] = #points > 0 and points or false
  return pointCache[key] or nil
end

-- Guessed droppers -------------------------------------------------------------------------------

-- For an item objective nothing else places (no dropper listed, no step: review, WANTED: Jai'vhanel's
-- "Feather of Jai'vhanel", forever-db knowing her and the feather but not that she drops it): the
-- creature the item or the quest is named after. Strict, as a wrong guess sends the player away:
--   - names taken whole from set patterns, never any word: the item's "<thing> of <Name>" and
--     "<Name>'s <thing>", its leading words ("Wolf Fang" -> Wolf; at least LEADING_MIN letters), the
--     title's part after a colon ("WANTED: <Name>") and the whole title;
--   - a creature's name must equal one of them exactly (case aside), longest first;
--   - and it must spawn in the quest's zone (forever-db's zone for the quest).
-- Kept apart from real data (source "guess" in Quests/Navigation.lua): used only when no database and
-- no learned spot has anything.
local LEADING_MIN = 4
local guessCache = {}  -- [questID .. ":" .. text] = points or false

local function candidateNames(itemName, title)
  local list, seen = {}, {}
  local function add(s)
    s = s and s:match("^%s*(.-)%s*$")
    if s and s ~= "" and not seen[s:lower()] then
      seen[s:lower()] = true
      list[#list + 1] = s
    end
  end
  add(itemName:match("^.- of (.+)$"))
  add(itemName:match("^(.-)'s "))
  local words = {}
  for word in itemName:gmatch("%S+") do
    words[#words + 1] = word
  end
  for n = #words - 1, 1, -1 do
    local prefix = table.concat(words, " ", 1, n)
    if #prefix >= LEADING_MIN then
      add(prefix)
    end
  end
  if title then
    add(title:match(":%s*(.+)$"))
    add(title)
  end
  table.sort(list, function(a, b) return #a > #b end)
  return list
end

-- The zone (uiMap name) a world point lies in: the first Zone-type map up from the smallest one.
local zoneNames = {}
local function zoneNameAt(lib, map, x, y)
  local uiMap = lib.ToUiMap(map, x, y)
  if not uiMap then
    return nil
  end
  if zoneNames[uiMap] == nil then
    zoneNames[uiMap] = false
    local id = uiMap
    while id and id > 0 do
      local info = C_Map.GetMapInfo(id)
      if not info then
        break
      end
      if info.mapType == Enum.UIMapType.Zone then
        zoneNames[uiMap] = info.name
        break
      end
      id = info.parentMapID
    end
  end
  return zoneNames[uiMap] or nil
end

-- The guess itself, into `points`.
local function guess(lib, record, text, points)
  local objective, kind, name = objectiveFor(lib, record, text)
  local zone = objective and kind == "item" and name and C_Map.GetAreaInfo(record.zone)
  if not zone or not name then
    return
  end
  local wanted = {}
  for rank, candidate in ipairs(candidateNames(name, record.name)) do
    wanted[candidate:lower()] = rank
  end
  -- Every creature with one of those names (a scan: rare, and cached per objective), best rank first.
  local found = {}
  for _, id in ipairs(lib.Ids("npc")) do
    local npcName = lib.Name("npc", id)
    local rank = npcName and wanted[npcName:lower()]
    if rank then
      found[#found + 1] = { id = id, rank = rank }
    end
  end
  table.sort(found, function(a, b) return a.rank < b.rank end)
  -- The best-ranked name with spawns in the quest's zone: all its creatures' spawns there.
  local bestRank
  for _, f in ipairs(found) do
    if bestRank and f.rank > bestRank then
      break
    end
    for _, p in ipairs(lib.Spawns("npc", f.id)) do
      if zoneNameAt(lib, p.map, p.x, p.y) == zone then
        bestRank = f.rank
        points[#points + 1] = { map = p.map, x = p.x, y = p.y, kind = "npc" }
      end
    end
  end
end

---Points of the creature an unplaced item objective is likely got from, guessed by name (see above),
---or nil. Only for Quests/Navigation.lua's last resort.
---@param questID number
---@param text string the objective's text
---@return table?
function ForeverData:GuessedPoints(questID, text)
  local key = questID .. ":" .. text
  if guessCache[key] ~= nil then
    return guessCache[key] or nil
  end
  local lib, record = library(), self:Quest(questID)
  local points = {}
  if lib and record and record.zone then
    guess(lib, record, text, points)
  end
  guessCache[key] = #points > 0 and points or false
  return guessCache[key] or nil
end

---Spawn points of whoever takes the quest in.
---@param questID number
---@return table?
function ForeverData:TurnInPoints(questID)
  local key = questID .. ":turnin"
  if pointCache[key] ~= nil then
    return pointCache[key] or nil
  end
  local lib, record = library(), self:Quest(questID)
  local finisher = record and record.finish and record.finish[1]
  local points = {}
  if lib and finisher and (finisher.kind == "npc" or finisher.kind == "object") then
    addSpawns(lib, finisher.kind, finisher.id, points)
  end
  pointCache[key] = #points > 0 and points or false
  return pointCache[key] or nil
end

---The in-game map (uiMapID) a world point lies on, or nil.
function ForeverData:UiMapOf(map, x, y)
  local lib = library()
  return lib and (lib.ToUiMap(map, x, y))
end

---Tips for a quest from forever-db's guide: its "gotcha" steps and its notes (confirmed ones), as text.
---@param questID number
---@return string[]
function ForeverData:Tips(questID)
  local lib = library()
  local tips = {}
  if not lib then
    return tips
  end
  for _, step in ipairs(lib.Steps(questID)) do
    if step.action == "gotcha" and step.text and step.text ~= "" and step.confidence == nil then
      tips[#tips + 1] = step.text
    end
  end
  for _, note in ipairs(lib.Notes(questID)) do
    if note.text and note.text ~= "" and note.confidence == nil then
      tips[#tips + 1] = note.text
    end
  end
  return tips
end

---The quest's area (zone or subzone) name, from its AreaTable id.
---@param questID number
---@return string?
function ForeverData:AreaName(questID)
  local record = self:Quest(questID)
  if not record or not record.zone then
    return nil
  end
  return C_Map.GetAreaInfo(record.zone)
end
