local ADDON_NAME, ns = ...

-- Every setting, defined once. Both Blizzard's Options > AddOns panel (UI/Settings.lua) and
-- Questmarker's own window (UI/SettingsWindow.lua) are built from this list, so they can't drift apart.
--
-- Entry fields:
--   kind     "checkbox" | "slider" | "dropdown" | "section"
--   id       unique variable name (also Blizzard's setting variable)
--   label, tooltip, default
--   get(profile) / set(profile, value)   read and change the active profile
--   slider:   min, max, step, format(value) -> text
--   dropdown: options() -> { { value, label }, ... }; preview(value) -> font file to draw that
--             option's label in (Questmarker's window only)
--   column   1 or 2 in Questmarker's window
--   grid     dropdowns sharing a grid name and the same options form one table in Questmarker's window
-- Questmarker's window only (Blizzard's panel shows every entry on its own line, full label):
--   row         entries sharing a row name sit on one line; the first one's rowLabel leads the line,
--               checkboxes show their `short` label, dropdowns are `width` wide
--   enabledWhen(profile) -> false greys the control out (e.g. automation options while it's all off)
--   kind "status": a label, a live status (status() -> text, color) and a button made by
--               button(parent) (shown only while actionEnabled() -> true); windowOnly, as it isn't a
--               setting
-- Both UIs:
--   onlyIf() -> false leaves the entry out (checked when the UI is built, e.g. Questie not installed)
--   windowOnly  not in Blizzard's panel
--
-- List order is the order in Blizzard's panel, and per column in Questmarker's window.

local Schema = {}
ns.SettingsSchema = Schema

local function percent(value)
  return ("%d%%"):format(value)
end

local function questieInstalled()
  return ns.Questie:Installed()
end

-- Any automation on: its override-key options only matter then.
local function automating(p)
  local a = p.automation
  return a.accept or a.acceptDaily or a.acceptWeekly or a.turnIn
end

---The list of entries (built on demand: categories come from ns.Categories).
---@return table[]
function Schema:Entries()
  if self.entries then
    return self.entries
  end
  local entries = {
    { kind = "section", label = "Tracker", column = 1 },
    {
      kind = "checkbox", id = "QUESTMARKER_HIDE_BLIZZARD_TRACKER", column = 1, default = true,
      label = "Hide Blizzard quest tracker",
      tooltip = "Hide the game's objective tracker so Questmarker's cards replace it. Done by untracking "
        .. "quests in the game's own tracker (Questmarker doesn't use it); they come back when you untick "
        .. "this. Tracked achievements, scenarios and quest popups still show the game's tracker.",
      get = function(p) return p.blizzardTracker.hide end,
      set = function(p, v) p.blizzardTracker.hide = v; ns.BlizzardTracker:Apply() end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_LOCK_CARDS", column = 1, default = true,
      label = "Lock card position",
      tooltip = "Untick to drag Questmarker's cards by their header; tick again to lock them there.",
      get = function(p) return p.cards.locked end,
      set = function(p, v) p.cards.locked = v; ns.Stack:ApplyLock() end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_CLICK_OPENS_MAP", column = 1, default = true,
      label = "Click a card to show its quest on the map",
      tooltip = "Left-clicking a card makes it your tracked quest (map highlight and in-world beacon) and "
        .. "opens the map at it. Out of combat only.",
      get = function(p) return p.cards.clickOpensMap end,
      set = function(p, v) p.cards.clickOpensMap = v end,
    },
    {
      kind = "slider", id = "QUESTMARKER_CARD_CAP", column = 1, default = 5, min = 1, max = 15, step = 1,
      label = "Cards for this zone",
      tooltip = "How many of this zone's quests get a card before the rest go behind \"N more here\". "
        .. "Pinned quests always show and don't count. Greyed out once you've set the tracker's height "
        .. "with its resize grip: the cards then fill that height (right-click the grip to go back).",
      enabledWhen = function(p) return (p.cards.maxHeight or 0) == 0 end,
      format = tostring,
      get = function(p) return p.cards.cap end,
      set = function(p, v) p.cards.cap = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "dropdown", id = "QUESTMARKER_SORT_MODE", column = 1, default = "smart",
      label = "Sort quests by",
      tooltip = "Smart: quests whose area you're in (or with a timer running) first, then by distance. "
        .. "Distance: nearest first. Level and Quest log: a fixed order that doesn't change as you move. "
        .. "Ready quests always have their own section, on top when you're nearer a turn-in than an "
        .. "objective.",
      options = function()
        local list = {}
        for _, mode in ipairs(ns.Tracking.SORT_MODES) do
          list[#list + 1] = { mode.key, mode.label }
        end
        return list
      end,
      get = function(p) return p.cards.sortMode end,
      set = function(p, v) p.cards.sortMode = v; ns.Tracking:ResetOrder() end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_NEAREST_ANYWHERE", column = 1, default = false,
      label = "Always show nearest quests",
      tooltip = "When this zone has fewer quests than the card limit, fill the free cards with your "
        .. "nearest quests elsewhere on this continent, so the tracker is never empty.",
      get = function(p) return p.cards.nearestAnywhere end,
      set = function(p, v) p.cards.nearestAnywhere = v; ns.Bus:Fire("TrackingResortWanted") end,
    },

    -- What a card shows (review: a card layout editor). The four "Show" toggles share one row in
    -- Questmarker's window; Blizzard's panel lists them with their full labels.
    { kind = "section", label = "Cards", column = 1 },
    {
      kind = "checkbox", id = "QUESTMARKER_SHOW_NAME", column = 1, default = true,
      row = "show", rowLabel = "Show:", short = "Name",
      label = "Show quest names on cards",
      get = function(p) return p.cards.show.name end,
      set = function(p, v) p.cards.show.name = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_SHOW_LEVEL", column = 1, default = true,
      row = "show", short = "Level",
      label = "Show quest levels on cards",
      get = function(p) return p.cards.show.level end,
      set = function(p, v) p.cards.show.level = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_SHOW_ARROW", column = 1, default = true,
      row = "show", short = "Arrow",
      label = "Show arrows on cards",
      tooltip = "The direction arrow, and the green marker when you're in the area.",
      get = function(p) return p.cards.show.arrow end,
      set = function(p, v) p.cards.show.arrow = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_SHOW_DISTANCE", column = 1, default = true,
      row = "show", short = "Distance",
      label = "Show distances on cards",
      tooltip = "The yards, zone name or \"here\" next to the arrow.",
      get = function(p) return p.cards.show.distance end,
      set = function(p, v) p.cards.show.distance = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_KEEP_DONE", column = 1, default = true,
      label = "Keep finished objectives on ready quests",
      tooltip = "When a quest is ready to turn in, its card keeps showing the objectives you finished "
        .. "(greyed, with their counts) above the turn-in line, so you can still tell which quest it is. "
        .. "Off: only the turn-in line.",
      get = function(p) return p.cards.keepDone end,
      set = function(p, v) p.cards.keepDone = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_PROGRESS_BAR", column = 1, default = true,
      label = "Progress bar under each quest",
      tooltip = "A thin bar under each card showing how far along the quest is; green when ready to "
        .. "turn in. Split into segments when progress is a count.",
      get = function(p) return p.cards.progressBar end,
      set = function(p, v) p.cards.progressBar = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_HINTS", column = 1, default = true,
      label = "Show hints for tricky steps",
      tooltip = "A \"Tip:\" line under quests that have a step players often get stuck on (timers, hidden "
        .. "spawns, items to use or keep). Only some quests have one.",
      get = function(p) return p.cards.hints end,
      set = function(p, v) p.cards.hints = v; ns.Stack:Request(false, true) end,
    },

    { kind = "section", label = "Look", column = 1 },
    {
      kind = "dropdown", id = "QUESTMARKER_FONT", column = 1, default = "default",
      label = "Font",
      tooltip = "The tracker's font. Lists every font your addons share through SharedMedia (MSBT, "
        .. "Details, ...), or WoW's own fonts if none do.",
      options = function() return ns.Fonts:Options() end,
      preview = function(value) return ns.Fonts:Path(value) end,  -- each name drawn in its own font
      get = function(p) return p.font.face end,
      set = function(p, v) p.font.face = v; ns.Fonts:Apply() end,
    },
    {
      kind = "slider", id = "QUESTMARKER_FONT_SCALE", column = 1, default = 100, min = 80, max = 140, step = 5,
      label = "Text size",
      tooltip = "Size of the tracker's text.",
      format = percent,
      get = function(p) return p.font.scale end,
      set = function(p, v) p.font.scale = v; ns.Fonts:Apply() end,
    },
    {
      kind = "slider", id = "QUESTMARKER_BACKGROUND_OPACITY", column = 1, default = 25, min = 0, max = 100, step = 5,
      label = "Background opacity",
      tooltip = "How dark the panel behind the cards is. 0% shows no panel.",
      format = percent,
      get = function(p) return p.cards.opacity end,
      set = function(p, v) p.cards.opacity = v; ns.Stack:ApplyBackground() end,
    },

    -- Only with Questie installed: its tracker's state, and Questie's own switch to turn it off.
    -- Questie's tracker state (with Questie), and QuestieDB's data (with QuestieDB, Questie or not).
    { kind = "section", label = "Questie", column = 1, windowOnly = true, onlyIf = function()
      return questieInstalled() or ns.QuestieData:Installed()
    end },
    {
      kind = "status", id = "QUESTMARKER_QUESTIE_TRACKER", column = 1, windowOnly = true, onlyIf = questieInstalled,
      label = "Questie's tracker",
      tooltip = "Questmarker replaces Questie's quest tracker (Questie keeps its map, tooltips and the rest). "
        .. "Turn off runs Questie's own switch, which reloads your UI. Not in combat.",
      status = function()
        local enabled = ns.Questie:TrackerEnabled()
        if enabled == true then
          return "On", ORANGE_FONT_COLOR
        elseif enabled == false then
          return "Off", GREEN_FONT_COLOR
        end
        return "Unknown", GRAY_FONT_COLOR
      end,
      -- A secure "/reload" button (Compat/Questie.lua): addons can't reload the UI themselves.
      button = function(parent) return ns.Questie:CreateTurnOffButton(parent, "Turn off") end,
      actionEnabled = function() return ns.Questie:TrackerEnabled() ~= false end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_QUESTIE_DATA", column = 1, default = true,
      onlyIf = function() return ns.QuestieData:Installed() end,
      label = "Use QuestieDB's location data",
      tooltip = "Arrows and map areas also use QuestieDB's spawn locations for mobs, objects and turn-ins "
        .. "(the database Questie reads; Questie itself isn't needed), so quests the bundled data doesn't "
        .. "cover get them too.",
      get = function(p) return p.questieData end,
      set = function(p, v) p.questieData = v; ns.QuestieData:Reset() end,
    },

    { kind = "section", label = "Quest categories", column = 2 },
  }

  local modes = function()
    return { { "show", "Show with zone cards" }, { "separate", "Separate group" }, { "hide", "Hide" } }
  end
  for _, name in ipairs(ns.Categories.ORDER) do
    entries[#entries + 1] = {
      -- grid: Questmarker's window shows these as one table (a row each, a radio per option); Blizzard's
      -- panel, which has no such control, keeps dropdowns.
      kind = "dropdown", grid = "categories", id = "QUESTMARKER_CATEGORY_" .. name:upper(), column = 2,
      default = ns.Categories.DEFAULT_MODES[name],
      label = ns.Categories.LABELS[name],
      tooltip = "Show: as normal cards with this zone's quests. Separate: in their own collapsed group. "
        .. "Hide: not shown (pinned quests always show).",
      options = modes,
      get = function() return ns.Categories:Mode(name) end,
      set = function(p, v) p.categories[name] = v; ns.Stack:Request(true, true) end,
    }
  end

  local rest = {
    { kind = "section", label = "Automation", column = 2 },
    {
      kind = "checkbox", id = "QUESTMARKER_AUTO_ACCEPT", column = 2, default = false,
      row = "accept", rowLabel = "Accept:", short = "Regular",
      label = "Accept regular quests automatically",
      tooltip = "Accepts quests when an NPC offers them, and picks them from the NPC's dialogue. "
        .. "Stands aside while Leatrix Plus's quest automation is on.",
      get = function(p) return p.automation.accept end,
      set = function(p, v) p.automation.accept = v end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_AUTO_ACCEPT_DAILY", column = 2, default = false,
      row = "accept", short = "Daily",
      label = "Accept daily quests automatically",
      get = function(p) return p.automation.acceptDaily end,
      set = function(p, v) p.automation.acceptDaily = v end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_AUTO_ACCEPT_WEEKLY", column = 2, default = false,
      row = "accept", short = "Weekly",
      label = "Accept weekly quests automatically",
      get = function(p) return p.automation.acceptWeekly end,
      set = function(p, v) p.automation.acceptWeekly = v end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_AUTO_TURN_IN", column = 2, default = false,
      label = "Turn in completed quests automatically",
      tooltip = "Turns in completed quests when you talk to the NPC. Never picks between rewards (you "
        .. "choose when there's more than one), never pays gold or currency, never hands over crafting "
        .. "reagents. Stands aside while Leatrix Plus's quest automation is on.",
      get = function(p) return p.automation.turnIn end,
      set = function(p, v) p.automation.turnIn = v end,
    },
    {
      kind = "dropdown", id = "QUESTMARKER_AUTO_KEY", column = 2, default = "SHIFT", enabledWhen = automating,
      label = "Override key",
      tooltip = "Hold this while talking to an NPC to do it yourself (or, with the option below, to "
        .. "automate only then).",
      options = function() return { { "SHIFT", "Shift" }, { "CTRL", "Ctrl" }, { "ALT", "Alt" } } end,
      get = function(p) return p.automation.key end,
      set = function(p, v) p.automation.key = v end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_AUTO_REQUIRE_KEY", column = 2, default = false,
      enabledWhen = automating,
      label = "Only automate while holding it",
      get = function(p) return p.automation.requireKey end,
      set = function(p, v) p.automation.requireKey = v end,
    },

    { kind = "section", label = "Map", column = 2 },
    {
      kind = "checkbox", id = "QUESTMARKER_MAP_AREAS", column = 2, default = true,
      label = "Show quest areas on the world map",
      tooltip = "Shades where each card's objectives are on the world map, one colour per quest, matched by "
        .. "a strip on its card; ready quests get a \"?\" at their turn-in. With Questie, untick its "
        .. "Icons > Objectives to hide its dots and keep just the areas.",
      get = function(p) return p.map.areas end,
      set = function(p, v) p.map.areas = v; ns.MapAreas:MarkDirty(); ns.Stack:Request(false, true) end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_MINIMAP_AREAS", column = 2, default = true,
      label = "Show quest areas on the minimap",
      tooltip = "The same coloured areas around you on the minimap.",
      get = function(p) return p.map.minimapAreas end,
      set = function(p, v) p.map.minimapAreas = v end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_MINIMAP_GUIDE", column = 2, default = true,
      label = "Guide line on the minimap",
      tooltip = "A faint dotted line from you toward the nearest area of one quest: the card you're hovering, "
        .. "else your first pinned quest, else the top card.",
      get = function(p) return p.map.guide end,
      set = function(p, v) p.map.guide = v end,
    },
    {
      kind = "slider", id = "QUESTMARKER_MAP_OPACITY", column = 2, default = 40, min = 10, max = 80, step = 5,
      label = "Area opacity",
      tooltip = "How strong each area circle is; where spawns overlap, colour builds up.",
      format = percent,
      get = function(p) return p.map.opacity end,
      set = function(p, v) p.map.opacity = v; ns.MapAreas:MarkDirty() end,
    },
    {
      kind = "slider", id = "QUESTMARKER_MAP_SIZE", column = 2, default = 30, min = 15, max = 60, step = 5,
      label = "Area circle size",
      tooltip = "The radius of the soft circle around each spawn point, in yards.",
      format = function(v) return ("%d yd"):format(v) end,
      get = function(p) return p.map.size end,
      set = function(p, v) p.map.size = v; ns.MapAreas:MarkDirty() end,
    },
    {
      kind = "slider", id = "QUESTMARKER_MAP_ICON_SIZE", column = 2, default = 100, min = 50, max = 200, step = 10,
      label = "Icon size",
      tooltip = "Size of the \"?\" at ready quests' turn-ins, on the world map and the minimap.",
      format = percent,
      get = function(p) return p.map.iconSize end,
      set = function(p, v) p.map.iconSize = v; ns.MapAreas:MarkDirty() end,
    },

    { kind = "section", label = "Arrows", column = 2 },
    {
      kind = "dropdown", id = "QUESTMARKER_ARROW_STYLE", column = 2, default = "classic",
      label = "Arrow style",
      tooltip = "The arrow on each card. /qm arrows shows them all side by side.",
      options = function()
        local list = {}
        for _, style in ipairs(ns.Card.ARROW_STYLES) do
          list[#list + 1] = { style.key, style.label }
        end
        return list
      end,
      get = function(p) return p.cards.arrowStyle end,
      set = function(p, v) p.cards.arrowStyle = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "checkbox", id = "QUESTMARKER_ARROW_COLOR", column = 2, default = true,
      label = "Color arrows by distance",
      tooltip = "Green when close, through yellow and orange, to red when far (or in another zone). "
        .. "Off: gold. Applies to Questmarker's own arrow styles.",
      get = function(p) return p.cards.arrowColorByDistance end,
      set = function(p, v) p.cards.arrowColorByDistance = v end,
    },
  }
  for _, entry in ipairs(rest) do
    entries[#entries + 1] = entry
  end

  self.entries = entries
  return entries
end

---Change a setting: apply it, then tell both settings UIs (SettingChanged).
---@param entry table
function Schema:Set(entry, value)
  if entry.get(ns.DB.profile) == value then
    return
  end
  entry.set(ns.DB.profile, value)
  ns.Bus:Fire("SettingChanged", entry.id)
end

---@param id string
function Schema:Find(id)
  for _, entry in ipairs(self:Entries()) do
    if entry.id == id then
      return entry
    end
  end
  return nil
end
