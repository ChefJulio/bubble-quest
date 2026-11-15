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

---Where a collect objective's item comes from, matched by item name among the quest's item
---objectives. Coverage: about half of item objectives, mostly classic quests; few Forever-new ones.
---@param questID number
---@param itemName string the objective text without its counter
---@return table? sources { kind = "npc" | "object" | "item", names = { ... }, more = n }
function ForeverData:ItemSources(questID, itemName)
  local lib = library()
  local record = self:Quest(questID)
  if not lib or not record then
    return nil
  end
  for _, objective in ipairs(record.objectives or {}) do
    if objective.kind == "item" and objective.target and lib.Name("item", objective.target) == itemName then
      local item = lib.Get("item", objective.target)
      local sources = item and item.sources or {}
      table.sort(sources, function(a, b) return (a.chance or 0) > (b.chance or 0) end)
      local first = sources[1]
      if not first then
        return nil
      end
      local result = { kind = first.kind, names = {}, more = 0 }
      for _, source in ipairs(sources) do
        if source.kind == first.kind then
          if #result.names < MAX_SOURCE_NAMES then
            result.names[#result.names + 1] = lib.Name(source.kind, source.id)
          else
            result.more = result.more + 1
          end
        end
      end
      return result
    end
  end
  return nil
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
