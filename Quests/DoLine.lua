local ADDON_NAME, ns = ...

-- The Do line for an objective, from its raw text (spec: verb-first action).
--
-- Forever puts the counter first: "1/10 Kobold Vermin slain", "3/8 Tough Wolf Meat" (verified in
-- game). The counter moves to the right edge of the row. Only rewrites whose meaning is certain are
-- made, on English clients only; everything else keeps the game's wording. Phase 7's hint data
-- overrides this per objective.

local DoLine = {}
ns.DoLine = DoLine

local ENGLISH = GetLocale() == "enUS" or GetLocale() == "enGB"

-- "Loot Red Burlap Bandana from Defias Thug", "Gather X from Y", "Collect X" (no source known).
-- forever-db's names are English, so this runs on English clients only.
local SOURCE_VERBS = { npc = "Loot", object = "Gather", item = "Open" }

local MAX_SHOWN_NAMES = 2
local ALL_NAMES = 99         -- ask for every source: grouping needs them all
local GROUP_SHARE = 0.6      -- a word shared by at least this share of the sources names the group
local GROUP_MIN = 3          -- ... and by at least this many

---All known sources of an item objective: forever-db's, else learned in play (Data/Learned.lua: e.g.
---Stolen Book from Kobold Worker and Kobold Vermin; Gnomeregan Archival Data from Snowdrift).
---@param questID number
---@param itemName string
---@return table? sources { kind, names = every name (nearest first), more = beyond those }
function DoLine.ItemSources(questID, itemName)
  local sources = ns.ForeverData:ItemSources(questID, itemName, ALL_NAMES)
  if sources then
    return sources
  end
  local names, kind = ns.Learned:Sources(questID, itemName)
  return names and { kind = kind, names = names, more = 0 } or nil
end

-- STOPGAP (review, 2026-11-16: "that's lazy but ok", deferred): the group reads "any Stonesplinter"
-- to avoid writing English plurals, and odd groupings ("any Young") would be fixed one by one.
-- Remaining work, agreed but skipped for now: (1) real plurals with irregulars (wolf -> wolves,
-- harpy -> harpies, -man -> -men): "from boars", "from Stonesplinters"; (2) head noun first: the last
-- word wins when it qualifies, the first only for a shared tribe name; (3) an offline audit printing
-- the grouping for every item objective in forever-db (and Questie), reviewed before shipping.
---A group name for many sources sharing a word (review: "kill boars, not every boar"): the first word
---(a tribe, "Stonesplinter Trogg, Stonesplinter Seer, ...") or the last (a kind, "Mountain Boar, Elder
---Mountain Boar, ..."), when at least GROUP_SHARE of the names (and GROUP_MIN) have it. Returns
---"any Stonesplinter" and how many names it doesn't cover, or nil.
---@param names string[]
---@return string? group
---@return number? leftovers
function DoLine.GroupName(names)
  if #names < GROUP_MIN then
    return nil
  end
  local counts = { first = {}, last = {} }
  for _, name in ipairs(names) do
    local first, last = name:match("^(%S+)%s"), name:match("%s(%S+)$")
    if first then counts.first[first] = (counts.first[first] or 0) + 1 end
    if last then counts.last[last] = (counts.last[last] or 0) + 1 end
  end
  local bestWord, bestCount = nil, 0
  for _, which in ipairs({ "first", "last" }) do
    for word, count in pairs(counts[which]) do
      if count > bestCount then
        bestWord, bestCount = word, count
      end
    end
  end
  if not bestWord or bestCount < GROUP_MIN or bestCount < #names * GROUP_SHARE then
    return nil
  end
  return "any " .. bestWord, #names - bestCount
end

---A drop chance as shown in tooltips: "45%", or "0.5%" under one percent. It's how often a kill (or
---a search) drops it at all, not how many: forever-db has no counts.
---@param chance number percent
---@return string
function DoLine.ChanceText(chance)
  return chance < 1 and ("%.1f%%"):format(chance) or ("%d%%"):format(math.floor(chance + 0.5))
end

---"any Stonesplinter +1", or the first `shown` names "A, B +7": how to name an objective's sources.
---@param names string[] every source name
---@param more number sources beyond `names`
---@param shown number how many names to list when they don't group
---@return string
function DoLine.SourcesText(names, more, shown)
  local group, leftovers = DoLine.GroupName(names)
  if group then
    local rest = leftovers + more
    return rest > 0 and ("%s +%d"):format(group, rest) or group
  end
  local list = {}
  for i = 1, math.min(#names, shown) do
    list[i] = names[i]
  end
  local rest = #names - #list + more
  local text = table.concat(list, ", ")
  return rest > 0 and ("%s +%d"):format(text, rest) or text
end

local function collectLine(questID, itemName)
  local sources = questID and DoLine.ItemSources(questID, itemName)
  if not sources or #sources.names == 0 then
    return "Collect " .. itemName
  end
  -- A source named like the item adds nothing ("Gather Milly's Harvest from Milly's Harvest": the
  -- crates you click share the item's name, seen in game).
  local names = {}
  for _, name in ipairs(sources.names) do
    if name ~= itemName then
      names[#names + 1] = name
    end
  end
  if #names == 0 then
    return ("%s %s"):format(SOURCE_VERBS[sources.kind] or "Collect", itemName)
  end
  local from = DoLine.SourcesText(names, sources.more, MAX_SHOWN_NAMES)
  if sources.kind == "item" then
    return ("Open %s for %s"):format(from, itemName)
  end
  return ("%s %s from %s"):format(SOURCE_VERBS[sources.kind] or "Collect", itemName, from)
end

---@param objective table from ns.QuestLog (text, type, fulfilled, required)
---@param questID number? enables item sources from forever-db
---@return string text
---@return string? counter "3/8", or nil when the objective has no counter
function DoLine:For(objective, questID)
  local text = objective.text or ""
  local rest = text:match("^%d+%s*/%s*%d+%s+(.+)$")  -- "1/10 Kobold Vermin slain"
    or text:match("^(.-)%s*:%s*%d+%s*/%s*%d+$")      -- "Kobold Vermin slain: 1/10"
  local counter = rest and ("%d/%d"):format(objective.fulfilled or 0, objective.required or 0) or nil

  -- A triaged forever-db step that says more clearly what to do (phase 7, Data/Hints.lua) wins.
  -- English only, like the rewrites below.
  if ENGLISH and questID then
    local better = ns.Hints:DoFor(questID, rest or text)
    if better then
      return better, counter
    end
  end
  if not rest then
    return text, nil
  end

  if ENGLISH then
    if objective.type == "monster" then
      local name = rest:match("^(.-)%s+slain$")
      if name then
        return "Kill " .. name, counter
      end
    elseif objective.type == "item" then
      return collectLine(questID, rest), counter
    end
  end
  return rest, counter
end
