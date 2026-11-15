local ADDON_NAME, ns = ...

-- Quest creatures near the player, from their nameplates (spec, Background objectives: "addons can't
-- see mob positions, but they can see when a matching mob's nameplate appears"). Nameplates exist
-- only for units within nameplate range, so "a nameplate for this objective is up" means "you're in
-- the area". Works for quests forever-db has no spawn data for.
--
-- Per nameplate: C_QuestLog.UnitIsRelatedToActiveQuest (cheap filter), then the unit's tooltip data:
-- a QuestTitle line (type 17) carries the quest's id, and the QuestObjective lines (type 8) after it
-- carry leftText ("3/8 Stolen Book") and completed [Read: /qm unit in game, Kobold Worker and Kobold
-- Vermin]. Tooltip quest data is secret in combat on Forever: secret values are skipped (the last
-- known state stays) and every nameplate is re-read when combat ends.
--
-- Each sighting also teaches Data/Learned.lua a spot for that objective, and the creature's name as
-- one of its sources (who drops the item).

local LINE_UNIT_NAME = Enum.TooltipDataLineType.UnitName              -- 2
local LINE_QUEST_TITLE = Enum.TooltipDataLineType.QuestTitle          -- 17
local LINE_QUEST_OBJECTIVE = Enum.TooltipDataLineType.QuestObjective  -- 8

local Nearby = {
  units = {},   -- [nameplate unit token] = { [questID] = { [objective name] = true } } or false
  quests = {},  -- [questID] = { [objective name] = number of nameplates }
}
ns.Nearby = Nearby

local function readable(value)
  return value ~= nil and not issecretvalue(value)
end

-- What a unit counts for: { [questID] = { [objective name] = true } }, or false when nothing (or
-- when it can't be read right now, e.g. in combat); and its name (the UnitName line), if readable.
local function scan(unit)
  local related = C_QuestLog.UnitIsRelatedToActiveQuest(unit)
  if not readable(related) or not related then
    return false
  end
  local data = C_TooltipInfo.GetUnit(unit)
  if not data or not data.lines then
    return false
  end
  local result, questID, creatureName = {}, nil, nil
  for _, typedLine in ipairs(data.lines) do
    -- `id` (QuestTitle) and `completed` (QuestObjective) are real fields (seen with /qm unit in game)
    -- that the WoW API annotations don't declare; read the line as a plain table.
    local line = typedLine --[[@as table]]
    local lineType = line.type
    if not readable(lineType) then
      return false
    end
    if lineType == LINE_UNIT_NAME then
      creatureName = readable(line.leftText) and line.leftText or nil
    elseif lineType == LINE_QUEST_TITLE then
      questID = readable(line.id) and line.id or nil
    elseif lineType == LINE_QUEST_OBJECTIVE and questID then
      if readable(line.leftText) and readable(line.completed) and not line.completed then
        result[questID] = result[questID] or {}
        result[questID][ns.QuestLog.StripProgress(line.leftText)] = true
      end
    end
  end
  if not next(result) then
    return false
  end
  return result, creatureName
end

-- Fires NearbyQuestEntered(questID) when a quest gains its first nearby creature: entering an
-- objective's area is a re-sort event (tracking rule 4). Leaving isn't, so creatures walking in and
-- out of nameplate range don't shuffle the cards.
local function rebuild()
  local before = Nearby.quests
  local quests = {}
  for _, found in pairs(Nearby.units) do
    if found then
      for questID, objectives in pairs(found) do
        quests[questID] = quests[questID] or {}
        for name in pairs(objectives) do
          quests[questID][name] = (quests[questID][name] or 0) + 1
        end
      end
    end
  end
  Nearby.quests = quests
  for questID in pairs(quests) do
    if not before[questID] then
      ns.Bus:Fire("NearbyQuestEntered", questID)
    end
  end
end

local function learn(found, creatureName)
  for questID, objectives in pairs(found) do
    for name in pairs(objectives) do
      ns.Learned:Record(questID, name)
      if creatureName then
        ns.Learned:RecordSource(questID, name, creatureName)
      end
    end
  end
end

local function update(unit)
  local found, creatureName = scan(unit)
  if found == false and InCombatLockdown() and Nearby.units[unit] then
    return  -- can't read it now; keep what we knew
  end
  Nearby.units[unit] = found
  if found then
    learn(found, creatureName)
  end
  rebuild()
end

---Is a creature for this quest's objective (or any unfinished objective) within nameplate range?
---@param questID number
---@param objectiveName string? nil: any objective
---@return boolean
function Nearby:Has(questID, objectiveName)
  local objectives = self.quests[questID]
  if not objectives then
    return false
  end
  return objectiveName == nil or objectives[objectiveName] ~= nil
end

ns.Events:On("NAME_PLATE_UNIT_ADDED", update)

ns.Events:On("NAME_PLATE_UNIT_REMOVED", function(unit)
  Nearby.units[unit] = nil
  rebuild()
end)

-- Re-read every nameplate when what they mean may have changed: combat ended (secrets readable
-- again), or quest progress changed (a finished objective no longer counts).
local function rescan()
  for unit in pairs(Nearby.units) do
    update(unit)
  end
end
ns.Events:On("PLAYER_REGEN_ENABLED", rescan)
ns.Bus:On("QuestLogChanged", rescan)
