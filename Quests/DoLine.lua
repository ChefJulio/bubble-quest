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

local function collectLine(questID, itemName)
  local sources = questID and ns.ForeverData:ItemSources(questID, itemName)
  if not sources or #sources.names == 0 then
    return "Collect " .. itemName
  end
  local from = table.concat(sources.names, ", ")
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
  if not rest then
    return text, nil
  end
  local counter = ("%d/%d"):format(objective.fulfilled or 0, objective.required or 0)

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
