local ADDON_NAME, ns = ...

-- BubbleQuestAPI (BubbleQuestAPI before the rename): the one public, read-only table other addons
-- (BubbleMap) use instead of the
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
---BubbleQuest's own handlers.
---@param event string
---@param fn function
function api.RegisterCallback(event, fn)
  local internal = CALLBACKS[event]
  if not internal then
    error(("BubbleQuestAPI.RegisterCallback: unknown event %q"):format(tostring(event)), 2)
  end
  if type(fn) ~= "function" then
    error("BubbleQuestAPI.RegisterCallback: fn must be a function", 2)
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

---Draw the minimap's quest areas, guide line and quest givers over `frame` instead of the minimap
---alone (nil: back to the minimap). For a map frame centred on the minimap but wider or taller (the
---padding around it shows terrain at the minimap's scale): the areas then cover all of it. Turn-ins
---the game marks itself get our "?" only outside Blizzard's square, where the game draws none.
---@param frame Frame?
function api.SetMinimapView(frame)
  ns.MinimapAreas:SetView(frame)
end

---Where the minimap view centres, for a minimap dragged away from the player: fn() -> north, west
---(world yards, UnitPosition's, on the player's instance map), or nil for the player. Called every
---frame the minimap draws; nil fn: always the player. The player stays the player for the guide line's
---start and "you're here".
---@param fn function?
function api.SetMinimapCentre(fn)
  ns.MinimapAreas:SetCentre(fn)
end

---The minimap view reaches `factor` times further than Blizzard's minimap (an overview zoom past its
---farthest level, Blizzard's minimap faded out): the quest areas scale to match, and turn-ins get our
---"?" everywhere, as the game's own are hidden. 1: Blizzard's own view.
---`gameHidden`: Blizzard's minimap is hidden (BubbleMap drawing its own map), so the game draws none of
---its own "?" and "!" and ours draw everywhere, and none of its tracking icons, so the town services
---switched on in the map button's menu draw too. Defaults to factor ~= 1.
---@param factor number
---@param gameHidden boolean?
function api.SetMinimapZoom(factor, gameHidden)
  ns.MinimapAreas:SetZoom(factor, gameHidden)
end

---A quest view in `frame`: BubbleQuest's quest areas, turn-in "?", quest givers' "!" and (option
---`guide`) the guide line, drawn around any world point at any scale (UI/QuestView.lua, the minimap's
---renderer too, so they match). The view fills `frame`; the owner clips it (no mask). Returns a handle:
---  :Draw(north, west, instanceMap, pixelsPerYard, turn)  north/west: world yards (UnitPosition's), the
---      point at the frame's centre; turn: radians (0: north up). Call when what the frame shows changes.
---  :Hide(), :Show()
---  :IsHovering()  the view's own tooltip is up (the cursor on one of its marks): the owner's other
---      tooltips can yield to it. While GameTooltip is up, the view's goes to the cursor's right.
---  :GetFrame()  the view's own frame (a child of `frame`, mouse off): for its frame level over terrain
---What shows follows the Map settings: areas with "Show quest areas on the world map", quest givers with
---"Show quests you can pick up". Options (all optional): guide (bool), hover (bool, default true: tooltips from the cursor while the
---mouse focus is `frame` or the game world), minCircle / minIcon (smallest sizes on screen, pixels;
---default 4 / 8, so marks stay visible zoomed far out), services (true, or { exclude = { [key] = true } }:
---the town services switched on in the map button's menu, minus the excluded; keys "flight", "inn",
---"bank", "auction", "repair", "mailbox", "weapon", "stable", "battle", "trainer:<profession>",
---"class:<class>"), ctrlHides (default true: the view is see-through while Ctrl is held, as the minimap's;
---false keeps it showing), highlight (default true: a quest hovered in the tracker or a quest log panel
---lights up, the others dim, as on the world map). The game's own minimap markers are never assumed here: every "?" and "!" is ours.
---@param frame Frame
---@param options table?
---@return table
function api.CreateQuestView(frame, options)
  options = options or {}
  local services = options.services
  local view = ns.QuestView.New(frame, {
    guide = options.guide == true,
    services = services and function() return true end or nil,
    servicesExclude = type(services) == "table" and services.exclude or nil,
    ctrlHides = options.ctrlHides,
    highlight = options.highlight ~= false,
    focus = options.hover ~= false and function(focus) return focus == frame end or function() return false end,
    minCircle = options.minCircle or 4,
    minIcon = options.minIcon or 8,
  })
  return {
    Draw = function(_, north, west, instanceMap, ppy, turn) view:Draw(north, west, instanceMap, ppy, turn) end,
    Hide = function() view:Hide() end,
    Show = function() view:Show() end,
    IsHovering = function() return view:IsHovering() end,
    GetFrame = function() return view.layer end,
  }
end

---A quest log list in `frame` (UI/QuestLogPanel.lua): every quest in the log under its zone (as the
---tracker's sections), with its objectives, a pin checkbox, a search box and the log's count ("12/40").
---It fills `frame`, scrolls with the mouse wheel over it, and keeps itself up to date while shown; at
---least 240 px wide (BubbleQuestAPI.QUEST_LOG_MIN_WIDTH). Options: onQuestClick(questID, target), a quest
---clicked: it's now the guide line's quest (minimap and quest views), and target is where it leads,
---{ map = instance map, north, west } in world yards (UnitPosition's), or nil when nothing is known.
---Returns a handle: :GetFrame(), :Show(), :Hide(), :Refresh() (rebuild now; never needed for updates).
---@param frame Frame
---@param options table?
---@return table
function api.CreateQuestLogPanel(frame, options)
  options = options or {}
  local panel = ns.QuestLogPanel.New(frame, { onQuestClick = options.onQuestClick })
  return {
    GetFrame = function() return panel.frame end,
    Show = function() panel:Show() end,
    Hide = function() panel:Hide() end,
    Refresh = function() panel:Refresh() end,
  }
end
api.QUEST_LOG_MIN_WIDTH = 240

---Append BubbleQuest's map menu (the world map button's: quest areas, quests you can pick up, the
---minimap's areas and guide, the Town services submenu, Map settings...) to `description`: a MenuUtil
---menu description, the root or a submenu (BubbleMap's window's filter menu).
---@param description table
function api.AddMapMenu(description)
  ns.MapButton.FillMenu(description)
end

---How the tracker looks, for matching it. A fresh table each call; changes come with ThemeChanged.
---@return table
function api.Theme()
  return {
    fonts = {  -- font object names (global Font objects), sized and faced by BubbleQuest's settings
      header = "BubbleQuestHeaderFont",
      line = "BubbleQuestLineFont",
      small = "BubbleQuestSmallFont",
      smallHighlight = "BubbleQuestSmallHighlightFont",
    },
    background = { 0, 0, 0, ns.DB.profile.cards.opacity / 100 },  -- the panel
    headerBand = { 0, 0, 0, 0.35 },                                -- over the panel, behind the header
    divider = { 1, 1, 1, 0.2 },
    pad = ns.Stack.PAD,
    headerHeight = ns.Stack.HEADER_HEIGHT,
  }
end

-- Read-only: writes error, and the real table can't be reached through getmetatable.
BubbleQuestAPI = setmetatable({}, {
  __index = api,
  __newindex = function()
    error("BubbleQuestAPI is read-only", 2)
  end,
  __metatable = false,
})
