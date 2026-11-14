local ADDON_NAME, ns = ...

-- Forever disables /dump and /run, so these prints are our window into the addon in game.

local Debug = {}
ns.Debug = Debug

local PREFIX = "|cff66ccffQuestmark|r:"

function Debug:Print(...)
  print(PREFIX, ...)
end

---Short readable form of an event argument: quests print as "#id title".
local function describe(value)
  if type(value) == "table" then
    if value.questID then
      return ("#%d %s"):format(value.questID, tostring(value.title))
    end
    return "{...}"
  end
  return tostring(value)
end

function Debug:EventsEnabled()
  return ns.DB.account ~= nil and ns.DB.account.debug.events
end

function Debug:SetEventsEnabled(enabled)
  ns.DB.account.debug.events = enabled
end

---Print an event if /qm events is on.
---@param source string "game" or "bus"
---@param name string
function Debug:Event(source, name, ...)
  if not self:EventsEnabled() then
    return
  end
  local parts = { ("|cff999999%s|r %s"):format(source, name) }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = describe((select(i, ...)))
  end
  self:Print(table.concat(parts, " "))
end
