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

local MAX_LEARNED_NAMES = 2

-- Creatures and objects seen in play whose tooltips list this objective (Data/Learned.lua), for items
-- forever-db has no sources for (e.g. Stolen Book: Kobold Worker and Kobold Vermin; Gnomeregan
-- Archival Data: Snowdrift).
local function learnedSources(questID, itemName)
  local names, kind = ns.Learned:Sources(questID, itemName)
  if not names then
    return nil
  end
  local shown = {}
  for i = 1, math.min(#names, MAX_LEARNED_NAMES) do
    shown[i] = names[i]
  end
  return { kind = kind, names = shown, more = #names - #shown }
end

local function collectLine(questID, itemName)
  local sources = questID and (ns.ForeverData:ItemSources(questID, itemName) or learnedSources(questID, itemName))
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
  local from = table.concat(names, ", ")
  if sources.more > 0 then
    from = ("%s +%d"):format(from, sources.more)
  end
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
