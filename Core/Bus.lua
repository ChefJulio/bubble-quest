local ADDON_NAME, ns = ...

-- Two dispatchers:
--   ns.Events: game events, through one hidden frame.
--   ns.Bus:    Questmark's own events ("QuestAdded", ...). Later phases subscribe here rather than
--              to game events, so the quest log is read in exactly one place.
-- A handler that errors is reported (BugSack) without stopping the other handlers.

local function dispatch(handlers, ...)
  for i = 1, #handlers do
    local ok, err = pcall(handlers[i], ...)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

-- Game events whose firing /qm events should not print (they fire constantly).
local QUIET_EVENTS = {
  QUEST_LOG_UPDATE = true,
  ADDON_LOADED = true,  -- fires for every addon, including load-on-demand ones mid-session
}

local Events = {
  frame = CreateFrame("Frame"),
  handlers = {},
}
ns.Events = Events

Events.frame:SetScript("OnEvent", function(_, event, ...)
  if not QUIET_EVENTS[event] then
    ns.Debug:Event("game", event, ...)
  end
  dispatch(Events.handlers[event], ...)
end)

---Call fn(...) with the event's payload every time the game event fires.
---@param event string
---@param fn function
function Events:On(event, fn)
  local list = self.handlers[event]
  if not list then
    list = {}
    self.handlers[event] = list
    self.frame:RegisterEvent(event)
  end
  list[#list + 1] = fn
end

local Bus = {
  handlers = {},
}
ns.Bus = Bus

---@param name string
---@param fn function
function Bus:On(name, fn)
  local list = self.handlers[name]
  if not list then
    list = {}
    self.handlers[name] = list
  end
  list[#list + 1] = fn
end

---@param name string
function Bus:Fire(name, ...)
  ns.Debug:Event("bus", name, ...)
  local list = self.handlers[name]
  if list then
    dispatch(list, ...)
  end
end
