local ADDON_NAME, ns = ...

-- Questmarker_Map: the square minimap made for Questmarker's tracker. Design:
-- docs/design/questmarker-map.md. Talks to Questmarker only through QuestmarkerAPI, never its
-- private namespace.

local API_NEEDED = 1  -- the QuestmarkerAPI version this addon is written against

-- Required by the TOC, so Questmarker has loaded; an older one without the members we use is the case
-- left to catch.
local api = rawget(_G, "QuestmarkerAPI")
ns.API = api
ns.enabled = api ~= nil and api.API >= API_NEEDED

if not ns.enabled then
  print(("|cffffd100Questmarker Map|r is off: it needs a newer Questmarker (API %d, found %s)."):format(
    API_NEEDED, api and tostring(api.API) or "none"))
end

-- Events: one frame, handlers per event (errors reported without stopping the others).
local handlers = {}
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event]) do
    local ok, err = pcall(fn, ...)
    if not ok then
      geterrorhandler()(err)
    end
  end
end)

---@param event string
---@param fn function
function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end

-- Work that must wait for the end of combat (the tracker carries secure quest item buttons and hangs
-- under our frame, so our frame doesn't move in combat). Keyed: the latest request per key wins.
local pending, pendingOrder = {}, {}

---@param key string
---@param fn function
function ns.AfterCombat(key, fn)
  if not InCombatLockdown() then
    fn()
    return
  end
  if not pending[key] then
    pendingOrder[#pendingOrder + 1] = key
  end
  pending[key] = fn
end

ns.On("PLAYER_REGEN_ENABLED", function()
  local order, queue = pendingOrder, pending
  pendingOrder, pending = {}, {}
  for _, key in ipairs(order) do
    local ok, err = pcall(queue[key])
    if not ok then
      geterrorhandler()(err)
    end
  end
end)

-- Saved settings (account-wide). Map settings move into Questmarker's settings window with step 3.
local DEFAULTS = {
  notices = {},  -- [key] = true: "Don't ask again"
}

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON_NAME then
    return
  end
  Questmarker_MapDB = Questmarker_MapDB or {}
  for key, value in pairs(DEFAULTS) do
    if Questmarker_MapDB[key] == nil then
      Questmarker_MapDB[key] = type(value) == "table" and {} or value
    end
  end
  ns.DB = Questmarker_MapDB
end)
