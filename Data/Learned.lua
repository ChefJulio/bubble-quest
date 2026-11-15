local ADDON_NAME, ns = ...

-- Where objectives were found, learned in play (spec, In-game learning: "where collector"). Pulled
-- forward from phase 8 for quests forever-db has no spawn data for (most Forever-new quests, e.g.
-- Rascally Rodents' Stolen Books).
--
-- When a nameplate of a creature that counts for an objective appears (Quests/Nearby.lua), the
-- player is within nameplate range of it: their position is recorded for that objective. The arrow
-- then points at the nearest recorded spot. Account-wide (QuestmarkDB.learned), so every character
-- benefits; local only, nothing leaves the machine.

local MIN_SPACING_YARDS = 25   -- don't record a spot closer than this to a known one
local MAX_POINTS = 40          -- per objective

local Learned = {}
ns.Learned = Learned

local function store()
  return ns.DB.account.learned
end

-- Sources ----------------------------------------------------------------------------------------
-- Which creatures count for an objective, learned from their nameplates' tooltips (a Kobold Worker's
-- tooltip lists "3/8 Stolen Book" under Rascally Rodents). For an item objective that is who drops
-- it; the Do line names them where forever-db has no item sources.

---Record that a creature counts for an objective.
---@param questID number
---@param objectiveName string
---@param creatureName string
function Learned:RecordSource(questID, objectiveName, creatureName)
  local all = ns.DB.account.learnedSources
  local quest = all[questID] or {}
  all[questID] = quest
  local names = quest[objectiveName] or {}
  quest[objectiveName] = names
  if not names[creatureName] then
    names[creatureName] = true
    ns.Bus:Fire("LearnedSourcesChanged", questID)
  end
end

---Creature names learned for an objective, sorted, or nil.
---@param questID number
---@param objectiveName string
---@return string[]?
function Learned:Sources(questID, objectiveName)
  local quest = ns.DB.account.learnedSources[questID]
  local names = quest and quest[objectiveName]
  if not names then
    return nil
  end
  local list = {}
  for name in pairs(names) do
    list[#list + 1] = name
  end
  table.sort(list)
  return #list > 0 and list or nil
end

-- Spots ------------------------------------------------------------------------------------------

---Known spots for an objective, as { { map, x, y } }, or nil.
---@param questID number
---@param objectiveName string objective text without its counter
---@return table?
function Learned:Points(questID, objectiveName)
  local quest = store()[questID]
  local points = quest and quest[objectiveName]
  return points and #points > 0 and points or nil
end

---Record the player's position for an objective, unless a known spot is near.
---@param questID number
---@param objectiveName string
function Learned:Record(questID, objectiveName)
  local north, west, map = ns.Navigation:PlayerPosition()
  if not north then
    return
  end
  local quest = store()[questID] or {}
  store()[questID] = quest
  local points = quest[objectiveName] or {}
  quest[objectiveName] = points
  if #points >= MAX_POINTS then
    return
  end
  for _, p in ipairs(points) do
    local dn, dw = p.x - north, p.y - west
    if p.map == map and dn * dn + dw * dw < MIN_SPACING_YARDS * MIN_SPACING_YARDS then
      return
    end
  end
  points[#points + 1] = { map = map, x = math.floor(north * 2 + 0.5) / 2, y = math.floor(west * 2 + 0.5) / 2 }
  ns.Bus:Fire("LearnedChanged", questID)
end
