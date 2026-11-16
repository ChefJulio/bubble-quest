local ADDON_NAME, ns = ...

-- Quests you can pick up (docs/design/available-quests.md), from QuestieDB (Data/QuestieData.lua).
--
--   1. The index, built once per login in the background (a few hundred quests a frame): every quest
--      in QuestieDB this character could ever take (race, class, faction), with what the checks need
--      and who starts it (NPCs, objects, items).
--   2. The checks, QuestieDB.IsDoable's ported (Questie/Database/QuestieDB.lua:695-960): not done,
--      not in the log, level, prerequisites, chains, exclusives, breadcrumbs, skill, reputation,
--      spell. Rerun on events (log changes, turn-ins, level, skills, reputation), never per frame.
--   3. The givers: per starting NPC or object, its spawns and the quests it offers; per starting item
--      (dropped by mobs: "Furlbrow's Deed"), the droppers' spawns, kept apart so the map can show them
--      honestly (decided in review).
--
-- Questie's blacklist (not in QuestieDB) comes in through Data/QuestieHidden.lua, extracted at build
-- time (tools/extract_questie_hidden.py; review: Darkmoon, Lunar Festival, Season of Discovery books
-- and removed quests showed without it).
-- What givers actually offer when you talk to them corrects this as you play (Quests/Offers.lua).
-- Stopgaps (recorded in the design doc): holiday quests are always hidden (no event awareness yet).
-- Without QuestieDB nothing shows (LibForeverData fallback: later).

local BUILD_PER_FRAME = 200
local KEYS = {
  "name", "startedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "preQuestGroup",
  "preQuestSingle", "exclusiveTo", "requiredSkill", "requiredMinRep", "requiredMaxRep", "nextQuestInChain",
  "questFlags", "specialFlags", "parentQuest", "breadcrumbForQuestId", "breadcrumbs", "requiredSpell",
  "requiredMaxLevel", "availableUntilCompleted", "availableStartingWith", "disabledByQuest", "zoneOrSort",
}
-- Holiday and world-event quest categories (zoneOrSort, QuestieDB corrections/enum/quests.lua): hidden,
-- as their events aren't running most of the time. Stopgap: Questie shows them while the event is on
-- (QuestieEvent's dates); event awareness is recorded in docs/design/available-quests.md.
local EVENT_SORTS = {
  [-404] = true, [-402] = true, [-378] = true, [-376] = true, [-375] = true, [-374] = true, [-370] = true,
  [-369] = true, [-366] = true, [-364] = true, [-41] = true, [-22] = true, [-21] = true, [-368] = true,
  [-365] = true, [-241] = true,
}
local FLAG_DAILY, FLAG_WEEKLY = 4096, 32768  -- questFlags (QuestieDB corrections/enum/quests.lua)
local SPECIAL_REPEATABLE = 1                   -- specialFlags

local Available = {
  records = nil,     -- [questID] = record, once built
  building = false,
  completed = {},    -- [questID] = true
  givers = {},       -- list of { kind = "npc"|"object"|"item", id, name, points, quests = { record } }
  version = 0,       -- bumped when givers change (the maps redraw)
}
ns.Available = Available

-- Bit tests by arithmetic: Forever's race masks use bits 32-33, past bit.band's 32 (Questie's rule).
local function hasBit(mask, flag)
  return not mask or mask == 0 or (mask % (2 * flag)) >= flag
end

local function flagSet(value, flag)
  return value ~= nil and value ~= 0 and (value % (2 * flag)) >= flag
end

-- The index ---------------------------------------------------------------------------------------

local function list(t)
  return type(t) == "table" and t or nil
end

local function playerMasks()
  local lib = ns.QuestieData.Library()
  -- apiguard: allow our own character ("player") is never identity-restricted; secret values are skipped
  local raceID = select(3, UnitRace("player"))
  -- apiguard: allow our own character ("player") is never identity-restricted; secret values are skipped
  local classID = select(3, UnitClass("player"))
  if issecretvalue(raceID) or issecretvalue(classID) then
    return nil, nil  -- unreadable: no race/class filter rather than a wrong one
  end
  local raceMasks = lib and lib.Enum and lib.Enum.raceMaskById
  return raceMasks and raceMasks[raceID], classID and 2 ^ (classID - 1)
end

local function build()
  local lib = ns.QuestieData.Library()
  local quest = lib and lib.Quest
  if not quest or not ns.QuestieData:Installed() then
    Available.building = false
    return
  end
  local raceFlag, classFlag = playerMasks()
  local records, n = {}, 0
  for _, questID in ipairs(quest.GetAllIds()) do
    local ok, v = pcall(quest.GetAll, questID, KEYS)
    if ok and type(v) == "table" then
      local startedBy = list(v[2])
      local npcs, objects, items = startedBy and list(startedBy[1]), startedBy and list(startedBy[2]),
        startedBy and list(startedBy[3])
      -- Starters are sparse ({[3] = {1972}}): each index on its own, never ipairs over startedBy.
      -- Questie's own list hides what isn't takeable or shouldn't be on the map (Data/QuestieHidden.lua).
      if (npcs or objects or items) and not ns.QuestieHidden[questID] and not EVENT_SORTS[v[24] or 0]
          and (not raceFlag or hasBit(v[5], raceFlag))
          and (not classFlag or hasBit(v[6], classFlag)) then
        records[questID] = {
          questID = questID, name = v[1], requiredLevel = v[3], level = v[4], preGroup = list(v[7]),
          preSingle = list(v[8]), exclusiveTo = list(v[9]), skill = list(v[10]), minRep = list(v[11]),
          maxRep = list(v[12]), nextInChain = v[13], questFlags = v[14], specialFlags = v[15], parent = v[16],
          breadcrumbFor = v[17], breadcrumbs = list(v[18]), spell = v[19], maxLevel = v[20],
          untilCompleted = v[21], startingWith = v[22], disabledBy = v[23],
          npcs = npcs, objects = objects, items = items,
        }
      end
    end
    n = n + 1
    if n % BUILD_PER_FRAME == 0 then
      coroutine.yield()
    end
  end
  Available.records = records
  Available.building = false
  Available:Refresh()
end

function Available:Build()
  if self.building or self.records then
    return
  end
  self.building = true
  local co = coroutine.create(build)
  local ticker
  ticker = C_Timer.NewTicker(0, function()
    local ok, err = coroutine.resume(co)
    if not ok then
      ticker:Cancel()
      self.building = false
      geterrorhandler()(err)
    elseif coroutine.status(co) == "dead" then
      ticker:Cancel()
    end
  end)
end

-- The checks --------------------------------------------------------------------------------------

local function done(questID)
  return Available.completed[questID] == true
end

local function active(questID)
  return ns.QuestLog.quests[questID] ~= nil
end

local function doneOrActive(questID)
  return questID and (done(questID) or active(questID))
end

local function anyDone(ids)
  for _, id in ipairs(ids) do
    if done(id) then
      return true
    end
  end
  return false
end

local function anyDoneOrActive(ids)
  for _, id in ipairs(ids or {}) do
    if doneOrActive(id) then
      return true
    end
  end
  return false
end

-- Skill rank by skill line ID, from the character's skill list (C_SkillInfo, SkillInfoDocumentation.lua;
-- Questie's source on Forever). Not in the type checker's stubs: reached guarded.
local skillRanks
local function skillRank(skillID)
  if not skillRanks then
    skillRanks = {}
    local skillInfo = rawget(_G, "C_SkillInfo")
    local count = skillInfo and skillInfo.GetNumSkillLines and skillInfo.GetNumSkillLines() or 0
    for i = 1, count do
      local line = skillInfo.GetSkillLineInfo(i)
      if line and not line.isHeader and line.skillID then
        skillRanks[line.skillID] = line.rank
      end
    end
  end
  return skillRanks[skillID]
end

local function standing(factionID)
  local data = C_Reputation.GetFactionDataByID(factionID)
  return data and data.currentStanding
end

-- Every check but level (which also decides trivial: drawn grey).
local function doable(r)
  local id = r.questID
  if done(id) or active(id) then
    return false
  end
  if r.preSingle and #r.preSingle > 0 and not anyDone(r.preSingle) then
    return false
  end
  if (not r.preSingle or #r.preSingle == 0) and r.preGroup then
    for _, pre in ipairs(r.preGroup) do
      -- Negative: done, no exclusiveTo alternative considered (QuestieDB's convention).
      if not done(math.abs(pre)) then
        local record = pre > 0 and Available.records[pre]
        if not (record and record.exclusiveTo and anyDone(record.exclusiveTo)) then
          return false
        end
      end
    end
  end
  if r.parent and r.parent ~= 0 and not active(r.parent) then
    return false
  end
  if r.nextInChain and r.nextInChain ~= 0 and doneOrActive(r.nextInChain) then
    return false
  end
  if anyDoneOrActive(r.exclusiveTo) then
    return false
  end
  if r.breadcrumbFor and r.breadcrumbFor ~= 0 and doneOrActive(r.breadcrumbFor) then
    return false
  end
  if anyDoneOrActive(r.breadcrumbs) and r.breadcrumbFor == nil then
    return false  -- the quest a breadcrumb leads to: one of its breadcrumbs is already running
  end
  if r.disabledBy and r.disabledBy ~= 0 and active(r.disabledBy) then
    return false
  end
  if r.untilCompleted and r.untilCompleted ~= 0 and done(r.untilCompleted) then
    return false
  end
  if r.startingWith and r.startingWith ~= 0 and not doneOrActive(r.startingWith) then
    return false
  end
  if r.skill and r.skill[1] then
    local rank = skillRank(r.skill[1])
    if not rank or rank < (r.skill[2] or 0) then
      return false
    end
  end
  if r.minRep and r.minRep[1] then
    local value = standing(r.minRep[1])
    if not value or value < (r.minRep[2] or 0) then
      return false
    end
  end
  if r.maxRep and r.maxRep[1] then
    local value = standing(r.maxRep[1])
    if value and value >= (r.maxRep[2] or 0) then
      return false
    end
  end
  if r.spell and r.spell ~= 0 then
    local known = C_SpellBook.IsSpellKnown(math.abs(r.spell))
    if (r.spell > 0) ~= known then
      return false
    end
  end
  return true
end

---Level window (Questie's default): the required level met, under the max level. Returns whether it
---shows and whether it's trivial (grey: you're more than the trivial range above it).
local function levelCheck(r, playerLevel, trivialRange)
  local level = (r.level == -1 or not r.level) and playerLevel or r.level
  local required = (r.requiredLevel and r.requiredLevel > 0) and r.requiredLevel or level
  if required > playerLevel or (r.maxLevel and r.maxLevel > 0 and playerLevel > r.maxLevel) then
    return false, false
  end
  return true, playerLevel - level > trivialRange
end

-- The givers --------------------------------------------------------------------------------------

-- What doesn't change about a giver (name, spawns), for the session: every QuestieDB read decodes.
local giverInfo = {}  -- [kind .. id] = { name, points } or false (nowhere known)

local function infoFor(kind, id)
  local key = kind .. id
  local info = giverInfo[key]
  if info == nil then
    local points
    if kind == "item" then
      -- The droppers' spawns: mobs that drop it, objects it's found in.
      points = {}
      for _, npcID in ipairs(ns.QuestieData.Get("ItemDB", "npcDrops", id) or {}) do
        for _, p in ipairs(ns.QuestieData:EntityPoints("npc", npcID) or {}) do
          points[#points + 1] = p
        end
      end
      for _, objectID in ipairs(ns.QuestieData.Get("ItemDB", "objectDrops", id) or {}) do
        for _, p in ipairs(ns.QuestieData:EntityPoints("object", objectID) or {}) do
          points[#points + 1] = p
        end
      end
    else
      points = ns.QuestieData:EntityPoints(kind, id)
    end
    if points and #points > 0 then
      local dbName = kind == "npc" and "NpcDB" or kind == "object" and "ObjectDB" or "ItemDB"
      info = { name = ns.QuestieData.Get(dbName, "name", id), points = points }
    else
      info = false
    end
    giverInfo[key] = info
  end
  return info or nil
end

local function addGiver(byKey, kind, id, record, trivial)
  local key = kind .. id
  local giver = byKey[key]
  if not giver then
    local info = infoFor(kind, id)
    if not info then
      return
    end
    giver = { kind = kind, id = id, name = info.name, points = info.points, quests = {} }
    byKey[key] = giver
  end
  giver.quests[#giver.quests + 1] = { record = record, trivial = trivial }
end

-- A starting NPC hostile to you can't give you the quest. Cached: an NPC's faction doesn't change.
local faction
local friendlyCache = {}
local function friendly(npcID)
  local cachedAnswer = friendlyCache[npcID]
  if cachedAnswer == nil then
    faction = faction or (UnitFactionGroup("player") == "Horde" and "H" or "A")
    local f = ns.QuestieData.Get("NpcDB", "friendlyToFaction", npcID)
    cachedAnswer = f == nil or f == "AH" or f == faction
    friendlyCache[npcID] = cachedAnswer
  end
  return cachedAnswer
end

---Recompute what's available and who offers it. Cheap after the index; on events only.
function Available:Refresh()
  if not self.records then
    return
  end
  skillRanks = nil
  local playerLevel = UnitLevel("player")
  local trivialRange = C_QuestLog.GetTrivialRange()
  local byKey = {}
  for _, r in pairs(self.records) do
    local shown, trivial = levelCheck(r, playerLevel, trivialRange)
    if shown and doable(r) then
      -- A giver that left it out when you talked to it doesn't get its "!" (Quests/Offers.lua).
      for _, npcID in ipairs(r.npcs or {}) do
        if friendly(npcID) and not ns.Offers:NotOffered("npc", npcID, r.questID) then
          addGiver(byKey, "npc", npcID, r, trivial)
        end
      end
      for _, objectID in ipairs(r.objects or {}) do
        if not ns.Offers:NotOffered("object", objectID, r.questID) then
          addGiver(byKey, "object", objectID, r, trivial)
        end
      end
      for _, itemID in ipairs(r.items or {}) do
        if C_Item.GetItemCount(itemID) == 0 then  -- in your bags: use it, nothing to find
          addGiver(byKey, "item", itemID, r, trivial)
        end
      end
    end
  end
  wipe(self.givers)
  for _, giver in pairs(byKey) do
    if giver then
      self.givers[#self.givers + 1] = giver
    end
  end
  self.version = self.version + 1
  ns.Bus:Fire("AvailableChanged")
end

---Daily or weekly (blue "!"), from QuestieDB's flags.
---@return boolean
function Available.Repeatable(record)
  return flagSet(record.questFlags, FLAG_DAILY) or flagSet(record.questFlags, FLAG_WEEKLY)
    or flagSet(record.specialFlags, SPECIAL_REPEATABLE)
end

-- Events ------------------------------------------------------------------------------------------

local function loadCompleted()
  wipe(Available.completed)
  for _, questID in ipairs(C_QuestLog.GetAllCompletedQuestIDs()) do
    Available.completed[questID] = true
  end
end

ns.Events:On("PLAYER_LOGIN", function()
  loadCompleted()
  Available:Build()
end)

ns.Events:On("QUEST_TURNED_IN", function(questID)
  Available.completed[questID] = true
end)

-- The log changed (accepted, turned in, abandoned), or what decides the checks did.
local pending = false
local function refreshSoon()
  if pending then
    return
  end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    Available:Refresh()
  end)
end
ns.Bus:On("QuestLogChanged", refreshSoon)
ns.Bus:On("LocationsChanged", function()  -- QuestieDB data changed (Questie's corrections): re-read
  wipe(giverInfo)
  refreshSoon()
end)
for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "LEARNED_SPELL_IN_SKILL_LINE",
  "BAG_UPDATE_DELAYED" }) do
  ns.Events:On(event, refreshSoon)
end
