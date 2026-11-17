local ADDON_NAME, ns = ...

-- Where objectives were found, learned in play (spec, In-game learning: "where collector"). Pulled
-- forward from phase 8 for quests forever-db has no spawn data for (most Forever-new quests, e.g.
-- Rascally Rodents' Stolen Books).
--
-- When a nameplate of a creature that counts for an objective appears (Quests/Nearby.lua), the
-- player is within nameplate range of it: their position is recorded for that objective. The arrow
-- then points at the nearest recorded spot. Account-wide (BubbleQuestDB.learned), so every character
-- benefits; local only, nothing leaves the machine.

local MIN_SPACING_YARDS = 25   -- don't record a spot closer than this to a known one
local MAX_POINTS = 40          -- per objective
local MAX_SIGHTINGS = 3        -- a spot's weight (sightings) stops growing here

local Learned = {}
ns.Learned = Learned

local function store()
  return ns.DB.account.learned
end

-- Sources ----------------------------------------------------------------------------------------
-- Which creatures or objects count for an objective, learned from their tooltips: a Kobold Worker's
-- nameplate tooltip lists "3/8 Stolen Book" under Rascally Rodents (Quests/Nearby.lua); a Snowdrift's
-- mouseover tooltip lists "1/7 Gnomeregan Archival Data" under Data Hoarders (Quests/Mouseover.lua).
-- For an item objective that is who drops it or what it's gathered from; the Do line names them
-- where forever-db has no item sources. Stored as [name] = "npc" | "object" (true, from before
-- objects were learned, means "npc").

---Record that a creature or object counts for an objective.
---@param questID number
---@param objectiveName string
---@param sourceName string
---@param kind string? "npc" (default) or "object"
function Learned:RecordSource(questID, objectiveName, sourceName, kind)
  local all = ns.DB.account.learnedSources
  local quest = all[questID] or {}
  all[questID] = quest
  local names = quest[objectiveName] or {}
  quest[objectiveName] = names
  kind = kind or "npc"
  local known = names[sourceName]
  if known ~= kind and not (known == true and kind == "npc") then
    names[sourceName] = kind
    ns.Bus:Fire("LearnedSourcesChanged", questID)
  end
end

---Source names learned for an objective, sorted, and their kind ("object" when every one is an
---object, else "npc"); or nil.
---@param questID number
---@param objectiveName string
---@return string[]?
---@return string? kind
function Learned:Sources(questID, objectiveName)
  local quest = ns.DB.account.learnedSources[questID]
  local names = quest and quest[objectiveName]
  if not names then
    return nil
  end
  local list, allObjects = {}, true
  for name, kind in pairs(names) do
    list[#list + 1] = name
    allObjects = allObjects and kind == "object"
  end
  table.sort(list)
  if #list == 0 then
    return nil
  end
  return list, allObjects and "object" or "npc"
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
---@param kind string? "npc" (a nameplate) or "object" (a mouseover); navigation's "here" uses it
function Learned:Record(questID, objectiveName, kind)
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
      -- Seen here again: the spot counts for more, up to MAX_SIGHTINGS (navigation weighs areas by
      -- it, so one stray sighting stays weak: docs/design/navigation-areas.md).
      if (p.n or 1) < MAX_SIGHTINGS then
        p.n = (p.n or 1) + 1
        ns.Bus:Fire("LearnedChanged", questID)
      end
      return
    end
  end
  points[#points + 1] = {
    map = map, x = math.floor(north * 2 + 0.5) / 2, y = math.floor(west * 2 + 0.5) / 2, kind = kind,
  }
  ns.Bus:Fire("LearnedChanged", questID)
end
