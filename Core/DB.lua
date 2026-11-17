local ADDON_NAME, ns = ...

-- SavedVariables.
--   QuestmarkerDB      account-wide: profiles (settings shared across characters), debug flags
--   QuestmarkerCharDB  per character: which profile, pins, ignore list, collapse state, notices
-- Defaults are deep-filled on load (missing keys only), so new settings reach existing users.
-- When a later version changes the shape, bump SCHEMA and add MIGRATIONS[SCHEMA]: it receives the
-- saved table at schema SCHEMA - 1 and upgrades it in place.

local SCHEMA = 1

local ACCOUNT_DEFAULTS = {
  profiles = {},
  learned = {},  -- [questID] = { [objective name] = { { map, x, y } } }, see Data/Learned.lua
  learnedSources = {},  -- [questID] = { [objective name] = { [creature name] = true } }
  debug = {
    events = false,
  },
}

local PROFILE_DEFAULTS = {
  blizzardTracker = {
    hide = true,
  },
  cards = {
    locked = true,
    cap = 5,  -- most zone cards shown before "+ N more here" (pinned cards don't count)
    opacity = 25,  -- background panel opacity, percent
    clickOpensMap = true,  -- left-clicking a card highlights the quest and opens the map at it
    nearestAnywhere = false,  -- free card slots take the nearest quests outside this zone
    sortMode = "smart",  -- key in Tracking.SORT_MODES
    arrowStyle = "classic",  -- key in Card.ARROW_STYLES
    arrowColorByDistance = true,  -- green close -> red far; off = gold
    progressBar = true,           -- thin progress bar under each card
    hints = true,                 -- "Tip:" lines for quests with a known tricky step
    show = { name = true, level = true, arrow = true, distance = true },  -- card elements shown
    keepDone = true,  -- ready quests keep their finished objectives (greyed) above the turn-in line
    width = 250,      -- card width (resize grip while unlocked)
    maxHeight = 0,    -- most the cards' scroll area may grow; 0 = down to the screen's bottom
    -- position = { point, relativePoint, x, y } once the player has moved the stack
  },
  automation = {
    accept = false,        -- accept regular quests (and pick them from NPC gossip) automatically
    acceptDaily = false,   -- the same for daily quests
    acceptWeekly = false,  -- the same for weekly (and scheduler-reset) quests
    turnIn = false,        -- turn in completed quests (only with 0 or 1 reward to choose)
    key = "SHIFT",         -- override key: "SHIFT" | "CTRL" | "ALT"
    requireKey = false,    -- false: holding the key pauses automation; true: only automate while held
  },
  questieData = true,  -- use Questie's location data for arrows when it's installed
  map = {
    areas = true,         -- quest areas on the world map, one colour per quest on the cards
    minimapAreas = true,  -- the same areas on the minimap
    guide = true,         -- a faint dotted line on the minimap to the guided quest's target
    opacity = 40,         -- each area circle's opacity, percent
    size = 30,            -- each area circle's radius, yards
    iconSize = 100,       -- the "?" and "!" icons on the maps, percent
    available = true,     -- quests you can pick up, on the world map and minimap
    availableTrivial = false,  -- also grey (trivial) ones
    availableDrops = true,     -- also quests started by a dropped item (their droppers' area)
    services = {},        -- [service key | "trainer:<profession>"] = true: shown on the world map (UI/MapServices.lua)
  },
  categories = {},  -- [category] = "show" | "separate" | "hide"; unset = Categories.DEFAULT_MODES
  font = {
    face = "default",  -- a LibSharedMedia font name, or "default" (the game's)
    scale = 100,       -- text size, percent
  },
}

local CHAR_DEFAULTS = {
  profile = "Default",
  pins = {},        -- [questID] = pin order number (lower = pinned earlier)
  pinCounter = 0,   -- last pin order number handed out
  ignored = {},     -- [questID] = true: hidden until unhidden
  collapsed = {},   -- [questID] = true: card shows only its title line
  minimized = false,  -- whole tracker collapsed to its header row
  elsewhere = {
    expanded = false,
  },
  overflow = {
    expanded = false,  -- "+ N more here" opened
  },
  turnins = {
    expanded = true,   -- the "Ready to turn in" section is open
  },
  hidden = {
    expanded = false,
  },
  groups = {},  -- [category] = true: that category's separate group is expanded
  notices = {},    -- [noticeKey] = true, one-time messages already shown
  removedWatches = {},  -- [questID] = true: Blizzard quest watches we removed to hide its tracker
  notOffered = {},  -- ["npc"|"object" .. id] = { [questID] = expiry time }: a giver left it out (Quests/Offers.lua)
}

local MIGRATIONS = {
  account = {},
  char = {},
}

local DB = {
  account = nil,  ---@type table?
  char = nil,     ---@type table?
  profile = nil,  ---@type table?
}
ns.DB = DB

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

---@param saved table? the SavedVariables global as loaded (nil on first run)
---@param steps table<number, function>
---@param defaults table
---@return table
local function prepare(saved, steps, defaults)
  if saved == nil then
    saved = { schema = SCHEMA }
  end
  for version = (saved.schema or 1) + 1, SCHEMA do
    steps[version](saved)
  end
  saved.schema = SCHEMA
  fill(saved, defaults)
  return saved
end

-- Called once, on our ADDON_LOADED (SavedVariables are available from then on).
function DB:Load()
  QuestmarkerDB = prepare(QuestmarkerDB, MIGRATIONS.account, ACCOUNT_DEFAULTS)
  QuestmarkerCharDB = prepare(QuestmarkerCharDB, MIGRATIONS.char, CHAR_DEFAULTS)
  self.account = QuestmarkerDB
  self.char = QuestmarkerCharDB
  self:UseProfile(self.char.profile)
end

---Switch this character to a profile, creating it from defaults if new.
---@param name string
function DB:UseProfile(name)
  local profiles = self.account.profiles
  profiles[name] = profiles[name] or {}
  fill(profiles[name], PROFILE_DEFAULTS)
  self.char.profile = name
  self.profile = profiles[name]
  ns.Bus:Fire("ProfileChanged", name)
end
