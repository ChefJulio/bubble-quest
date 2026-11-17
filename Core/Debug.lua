local ADDON_NAME, ns = ...

-- Forever disables /dump and /run, so these prints are our window into the addon in game.

local Debug = {
  history = {},  -- recent printed lines, color codes stripped, for /qm copy
}
ns.Debug = Debug

local PREFIX = "|cff66ccffBubbleQuest|r:"
local HISTORY_SIZE = 300

local function stripColors(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Debug:Print(...)
  print(PREFIX, ...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring((select(i, ...)))
  end
  local history = self.history
  history[#history + 1] = date("%H:%M:%S ") .. stripColors(table.concat(parts, " "))
  if #history > HISTORY_SIZE then
    table.remove(history, 1)
  end
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
  local parts, seenQuest = { ("|cff999999%s|r %s"):format(source, name) }, nil
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    -- QuestChanged passes the new and the old copy of the same quest: print it once.
    local questID = type(value) == "table" and value.questID or nil
    if not (questID and questID == seenQuest) then
      parts[#parts + 1] = describe(value)
      seenQuest = questID or seenQuest
    end
  end
  self:Print(table.concat(parts, " "))
end
