local ADDON_NAME, ns = ...

-- What quest givers actually offer (docs/design/available-quests.md, "a quest the NPC didn't offer"),
-- correcting Quests/Available.lua as you play. Opening an NPC's (or object's) dialog lists every quest
-- it offers you right now; one we drew a "!" for that isn't listed isn't available to you, whatever
-- the data says (a prerequisite it lacks, a chain, an event). That giver's "!" for it goes.
--
-- Questie does this for dailies and weeklies only (AvailableQuests.lua:390-524); here for every quest
-- (decided in review: never claim a quest that isn't there), so a hidden one comes back as soon as it
-- could have changed: you level up, you turn in any quest, or the daily reset passes. Kept per
-- character (SavedVariables), per giver and quest: one wrong starter in the data doesn't hide the
-- quest at its real giver.
--
-- Read like Questie on Forever: gossip (C_GossipInfo.GetAvailableQuests/GetActiveQuests), greetings
-- (GetAvailableQuestInfo's 5th value is the quest ID, GetActiveQuestID), a single quest shown straight
-- away (QUEST_DETAIL, GetQuestID). No conclusion from a dialog whose giver is secret or not a creature
-- or object (a player sharing, an item), from a greeting with a quest it can't identify, or from a
-- quest window opened from a list already checked (the same giver as the last check).

local Offers = {}
ns.Offers = Offers

local lastGuid  -- the giver last checked: a quest opened from its list isn't a new list

-- The giver in a dialog: "npc" or "object" and its ID, from its GUID. Nil when unreadable or neither.
local function dialogGiver(unit)
  -- apiguard: allow a secret GUID (restricted identity) is checked and skipped right after
  local guid = UnitGUID(unit)
  if guid == nil or issecretvalue(guid) then
    return nil
  end
  local kind, _, _, _, _, idText = strsplit("-", guid)
  local id = tonumber(idText)
  if not id then
    return nil
  end
  if kind == "Creature" or kind == "Vehicle" then
    return guid, "npc", id
  elseif kind == "GameObject" then
    return guid, "object", id
  end
  return nil
end

local function store()
  local char = ns.DB.char
  char.notOffered = char.notOffered or {}
  return char.notOffered
end

---Did this giver, when you last talked to it, leave this quest out?
---@param kind string "npc" or "object"
---@param id number
---@param questID number
---@return boolean
function Offers:NotOffered(kind, id, questID)
  local giver = store()[kind .. id]
  local expires = giver and giver[questID]
  return expires ~= nil and expires > time()
end

-- Compare a giver's list with what we expected from it. `offered`: [questID] = true, the full list.
local function check(guid, kind, id, offered)
  lastGuid = guid
  local key = kind .. id
  local giver = store()[key] or {}
  local changed = false
  -- Offered now: never hidden (an offer disproves an old "not offered").
  for questID in pairs(offered) do
    if giver[questID] then
      giver[questID] = nil
      changed = true
    end
  end
  -- Expected but not listed: hidden until the daily reset (or sooner, see the events below).
  local expires = time() + C_DateAndTime.GetSecondsUntilDailyReset()
  for _, g in ipairs(ns.Available.givers) do
    if g.kind == kind and g.id == id then
      for _, q in ipairs(g.quests) do
        local questID = q.record.questID
        if not offered[questID] and not ns.QuestLog.quests[questID] and not giver[questID] then
          giver[questID] = expires
          changed = true
        end
      end
    end
  end
  store()[key] = next(giver) and giver or nil
  if changed then
    ns.Available:Refresh()
  end
end

local function onGossip()
  local guid, kind, id = dialogGiver("npc")
  if not guid or guid == lastGuid then
    return
  end
  local offered = {}
  for _, info in ipairs(C_GossipInfo.GetAvailableQuests()) do
    offered[info.questID] = true
  end
  -- Quests you already have can be listed before the log catches up (Questie's note): count them too.
  for _, info in ipairs(C_GossipInfo.GetActiveQuests()) do
    offered[info.questID] = true
  end
  check(guid, kind, id, offered)
end

local function onGreeting()
  local guid, kind, id = dialogGiver("npc")
  if not guid or guid == lastGuid then
    return
  end
  local offered = {}
  for i = 1, GetNumActiveQuests() do
    local questID = GetActiveQuestID(i)
    if not questID or questID <= 0 then
      return  -- one it can't identify: the list isn't complete enough to prove anything
    end
    offered[questID] = true
  end
  for i = 1, GetNumAvailableQuests() do
    local questID = select(5, GetAvailableQuestInfo(i))
    if not questID or questID <= 0 then
      return
    end
    offered[questID] = true
  end
  check(guid, kind, id, offered)
end

-- A quest window straight away, no list: this giver offers just this one (unless it was opened from a
-- list we already checked).
local function onDetail()
  local guid, kind, id = dialogGiver("questnpc")
  if not guid or guid == lastGuid then
    return
  end
  local questID = GetQuestID()
  if not questID or questID <= 0 then
    return
  end
  check(guid, kind, id, { [questID] = true })
end

ns.Events:On("GOSSIP_SHOW", onGossip)
ns.Events:On("QUEST_GREETING", onGreeting)
ns.Events:On("QUEST_DETAIL", onDetail)

-- What could make a hidden quest available: a level, a turn-in (prerequisites). Forget them all then.
local function forget()
  if ns.DB.char and ns.DB.char.notOffered and next(ns.DB.char.notOffered) then
    wipe(ns.DB.char.notOffered)
    lastGuid = nil
  end
end
ns.Events:On("PLAYER_LEVEL_UP", forget)
ns.Events:On("QUEST_TURNED_IN", forget)
