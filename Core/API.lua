local ADDON_NAME, ns = ...

-- QuestmarkerAPI: the one public, read-only table other addons (Questmarker_Map) use instead of the
-- private namespace. Versioned: API goes up when a member changes meaning or goes away; adding one
-- keeps it. Design: docs/design/questmarker-map.md ("Interface between the two addons").
--
-- Members are added by the build steps that need them (SetMinimapView with the padded minimap,
-- FrameLevels with the world map terrain layer); nothing here reaches into internals on the
-- caller's behalf beyond what's listed.

local API_VERSION = 1

-- Public callback names and the internal Bus events behind them. Handlers get no arguments unless
-- listed: a public payload is a contract, so only what a caller needs.
local CALLBACKS = {
  ProfileChanged = { "ProfileChanged" },       -- another profile: re-read everything
  TrackerResized = { "TrackerWidthChanged" },  -- (width): the tracker's outer width, pixels
  ThemeChanged = { "FontsChanged", "BackgroundChanged" },
  AreasChanged = { "AreasChanged" },           -- what the map areas draw changed
  -- The tracker's header dragged the attached frame (it must be movable) and let go: save its place.
  TrackerAttachMoved = { "TrackerAttachMoved" },
}

local api = {}

api.API = API_VERSION

---Call fn whenever `event` happens (see CALLBACKS). Errors in fn are reported without stopping
---Questmarker's own handlers.
---@param event string
---@param fn function
function api.RegisterCallback(event, fn)
  local internal = CALLBACKS[event]
  if not internal then
    error(("QuestmarkerAPI.RegisterCallback: unknown event %q"):format(tostring(event)), 2)
  end
  if type(fn) ~= "function" then
    error("QuestmarkerAPI.RegisterCallback: fn must be a function", 2)
  end
  for _, name in ipairs(internal) do
    if name == "TrackerWidthChanged" then
      ns.Bus:On(name, function(width) fn(width) end)
    else
      ns.Bus:On(name, function() fn() end)
    end
  end
end

---The tracker's root frame, or nil before PLAYER_LOGIN (it's created then).
---@return Frame?
function api.GetTracker()
  return ns.Stack.container
end

---Attach the tracker's top edge under `frame` (left edges aligned), or nil to put it back where it
---was. While attached, dragging the tracker's header moves `frame` if it's movable (then
---TrackerAttachMoved fires), and nothing otherwise; the resize grip still changes width and height.
---Applied after combat if called in combat (the tracker carries secure quest item buttons).
---@param frame Frame?
function api.SetTrackerAttach(frame)
  ns.Combat:Run("trackerAttach", function()
    ns.Stack:Attach(frame)
  end)
end

---How the tracker looks, for matching it. A fresh table each call; changes come with ThemeChanged.
---@return table
function api.Theme()
  return {
    fonts = {  -- font object names (global Font objects), sized and faced by Questmarker's settings
      header = "QuestmarkerHeaderFont",
      line = "QuestmarkerLineFont",
      small = "QuestmarkerSmallFont",
      smallHighlight = "QuestmarkerSmallHighlightFont",
    },
    background = { 0, 0, 0, ns.DB.profile.cards.opacity / 100 },  -- the panel
    headerBand = { 0, 0, 0, 0.35 },                                -- over the panel, behind the header
    divider = { 1, 1, 1, 0.2 },
    pad = ns.Stack.PAD,
    headerHeight = ns.Stack.HEADER_HEIGHT,
  }
end

-- Read-only: writes error, and the real table can't be reached through getmetatable.
QuestmarkerAPI = setmetatable({}, {
  __index = api,
  __newindex = function()
    error("QuestmarkerAPI is read-only", 2)
  end,
  __metatable = false,
})
