local ADDON_NAME, ns = ...

-- Every setting, defined once. Both Blizzard's Options > AddOns panel (UI/Settings.lua) and
-- Questmark's own window (UI/SettingsWindow.lua) are built from this list, so they can't drift apart.
--
-- Entry fields:
--   kind     "checkbox" | "slider" | "dropdown" | "section"
--   id       unique variable name (also Blizzard's setting variable)
--   label, tooltip, default
--   get(profile) / set(profile, value)   read and change the active profile
--   slider:   min, max, step, format(value) -> text
--   dropdown: options() -> { { value, label }, ... }
--   column   1 or 2 in Questmark's window

local Schema = {}
ns.SettingsSchema = Schema

local function percent(value)
  return ("%d%%"):format(value)
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
      kind = "checkbox", id = "QUESTMARK_HIDE_BLIZZARD_TRACKER", column = 1, default = true,
      label = "Hide Blizzard quest tracker",
      tooltip = "Hide the game's objective tracker so Questmark's cards replace it. Quest auto-complete "
        .. "popups and the scenario tracker are part of it and hide too.",
      get = function(p) return p.blizzardTracker.hide end,
      set = function(p, v) p.blizzardTracker.hide = v; ns.BlizzardTracker:Apply() end,
    },
    {
      kind = "checkbox", id = "QUESTMARK_LOCK_CARDS", column = 1, default = true,
      label = "Lock card position",
      tooltip = "Untick to drag Questmark's cards by their header; tick again to lock them there.",
      get = function(p) return p.cards.locked end,
      set = function(p, v) p.cards.locked = v; ns.Stack:ApplyLock() end,
    },
    {
      kind = "checkbox", id = "QUESTMARK_CLICK_OPENS_MAP", column = 1, default = true,
      label = "Click a card to show its quest on the map",
      tooltip = "Left-clicking a card makes it your tracked quest (map highlight and in-world beacon) and "
        .. "opens the map at it. Out of combat only.",
      get = function(p) return p.cards.clickOpensMap end,
      set = function(p, v) p.cards.clickOpensMap = v end,
    },
    {
      kind = "slider", id = "QUESTMARK_CARD_CAP", column = 1, default = 5, min = 1, max = 15, step = 1,
      label = "Cards shown for this zone",
      tooltip = "How many of this zone's quests get a card before the rest go behind \"+ N more here\". "
        .. "Pinned quests always show and don't count.",
      format = tostring,
      get = function(p) return p.cards.cap end,
      set = function(p, v) p.cards.cap = v; ns.Stack:Request(false, true) end,
    },

    { kind = "section", label = "Look", column = 1 },
    {
      kind = "checkbox", id = "QUESTMARK_PROGRESS_BAR", column = 1, default = true,
      label = "Progress bar under each quest",
      tooltip = "A thin bar under each card showing how far along the quest is; green when ready to "
        .. "turn in. Split into segments when progress is a count.",
      get = function(p) return p.cards.progressBar end,
      set = function(p, v) p.cards.progressBar = v; ns.Stack:Request(false, true) end,
    },
    {
      kind = "slider", id = "QUESTMARK_BACKGROUND_OPACITY", column = 1, default = 25, min = 0, max = 100, step = 5,
      label = "Background opacity",
      tooltip = "How dark the panel behind the cards is. 0% shows no panel.",
      format = percent,
      get = function(p) return p.cards.opacity end,
      set = function(p, v) p.cards.opacity = v; ns.Stack:ApplyBackground() end,
    },

    { kind = "section", label = "Arrows", column = 1 },
    {
      kind = "dropdown", id = "QUESTMARK_ARROW_STYLE", column = 1, default = "classic",
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
      kind = "checkbox", id = "QUESTMARK_ARROW_COLOR", column = 1, default = true,
      label = "Color arrows by distance",
      tooltip = "Green when close, through yellow and orange, to red when far (or in another zone). "
        .. "Off: gold. Applies to Questmark's own arrow styles.",
      get = function(p) return p.cards.arrowColorByDistance end,
      set = function(p, v) p.cards.arrowColorByDistance = v end,
    },

    { kind = "section", label = "Quest categories", column = 2 },
  }

  local modes = function()
    return { { "show", "Show with zone cards" }, { "separate", "Separate group" }, { "hide", "Hide" } }
  end
  for _, name in ipairs(ns.Categories.ORDER) do
    entries[#entries + 1] = {
      kind = "dropdown", id = "QUESTMARK_CATEGORY_" .. name:upper(), column = 2,
      default = ns.Categories.DEFAULT_MODES[name],
      label = ns.Categories.LABELS[name],
      tooltip = "Show: as normal cards with this zone's quests. Separate: in their own collapsed group. "
        .. "Hide: not shown (pinned quests always show).",
      options = modes,
      get = function() return ns.Categories:Mode(name) end,
      set = function(p, v) p.categories[name] = v; ns.Stack:Request(true, true) end,
    }
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
