local ADDON_NAME, ns = ...

-- BubbleMap: a square minimap and everything around it, standalone, part of the Bubble suite. With
-- the suite's quest addon loaded it also carries that addon's tracker under the map, in one column.
-- Design: docs/design/questmarker-map.md; suite rules: docs/design/bubble-suite.md (no Bubble addon
-- requires another: siblings are optional and found through their public API).

local QUEST_API_NEEDED = 1  -- the quest addon's API version these features are written against

-- The quest addon's public API, if it's loaded and new enough. Loaded before us when present
-- (## OptionalDeps).
local quest = rawget(_G, "BubbleQuestAPI")
if quest and quest.API < QUEST_API_NEEDED then
  quest = nil
end
ns.Quest = quest  ---@type table?

-- The open sea's colour in the terrain tiles (sampled from coastal tiles' sea edges: about 5, 6, 7 of
-- 255), for the fill where there's no tile, so the coast's tile grid doesn't show.
ns.SEA = { 0.02, 0.024, 0.028, 1 }

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

-- Work that must wait for the end of combat (with the quest addon, its tracker carries secure quest
-- item buttons and hangs under our frame, so our frame doesn't move in combat). Keyed: the latest
-- request per key wins.
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

-- Saved settings, account-wide (the suite's shared profiles replace this with LibBubble).
local DEFAULTS = {
  notices = {},       -- [key] = true: "Don't ask again"
  position = nil,     -- { left, top } once dragged; nil: hang from Edit Mode's minimap box
  locked = true,      -- the bar can't drag the map
  worldTerrain = false, -- the real terrain on zone maps of the world map (WorldMap.lua)
  mapStyle = "terrain", -- what our map draws: "terrain" (the ground tiles) or "art" (the world map's art)
  groupNames = true,  -- party and raid members' names beside their dots (Group.lua)
  revealMap = true,  -- map art: every zone's land pieces, explored or not (Data/Overlays.lua)
  windowStyle = "terrain", -- the same for the map window (MapWindow.lua), switched in its footer
  attachTracker = true, -- with the quest addon: its tracker hangs under the map (one column)
  width = 220,        -- the map's width when the tracker isn't attached under it
  heightPercent = 100,  -- the map's height, percent of its width
  lastGather = nil,   -- the tracking spell the gather button turns on (its name)
  gatherMode = "never", -- Blizzard's minimap for its blips: "never" (our map only), "auto" (a
                       -- tracking spell on), "always"
  gatherModeV2 = nil,  -- set once the default moved from "auto" to "never" (user's call, 2026-11-17)
  show = {            -- what's around the map (Around.lua); Blizzard's own versions are always hidden
    bar = true,       -- the bar along the map's top (zone, buttons, clock)
    zone = true,
    clock = true,
    calendar = true,
    tracking = true,
    gather = true,    -- the gather button (a tracking spell on/off; Zoom.lua)
    style = true,     -- the map style button (terrain or the world map's art; Art.lua)
    mail = true,
    coords = false,   -- the quest addon's header shows them already
    zoom = false,     -- the mouse wheel zooms
    launchers = true, -- addons' minimap buttons collected into one list (Launchers.lua)
  },
}

local function fill(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then
        target[key] = {}
      end
      fill(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON_NAME then
    return
  end
  BubbleMapDB = BubbleMapDB or {}
  fill(BubbleMapDB, DEFAULTS)
  -- The default moved from "auto" to "never" (our map only, Ctrl peeks); saved before that, once.
  if not BubbleMapDB.gatherModeV2 then
    BubbleMapDB.gatherModeV2 = true
    if BubbleMapDB.gatherMode == "auto" then
      BubbleMapDB.gatherMode = "never"
    end
  end
  ns.DB = BubbleMapDB
end)
