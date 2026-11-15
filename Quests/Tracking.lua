local ADDON_NAME, ns = ...

-- The tracking rules (spec, Tracking). This module decides what shows and in what order; the card
-- stack only draws the result (Tracking:View()).
--
--   1. Pinned quests always show, in pin order, wherever they are; not counted in the cap.
--   2. Other quests are chosen by zone and sorted by distance to their map marker.
--   3. Quests whose area you're in go first, then ready turn-ins within NEAR_TURNIN_YARDS; farther
--      turn-ins sort by distance like the rest.
--   4. The order changes only on events: QuestLogChanged, a zone change, moving more than
--      MOVE_YARDS since the last sort, or a zone quest the last sort didn't rank (HasUnranked).
--      Never on a timer by itself, never in combat (the stack defers). Hysteresis: neighbours swap
--      only when the lower one is HYSTERESIS times closer.
--   5. At most profile.cards.cap zone cards; the rest behind "+ N more here". With "Always show
--      nearest quests" (cards.nearestAnywhere), free slots take the nearest quests outside the zone
--      (same continent, by distance, ranked after every zone quest); the rest stay in Elsewhere.
--   6. Ignored quests are hidden until unhidden.
-- Categories (phase 4): a category set to "separate" gets its own group (all its quests, any zone);
-- "hide" removes its quests. Pinned quests show whatever their category.

local MOVE_YARDS = 100
local NEAR_TURNIN_YARDS = 250
local HYSTERESIS = 0.8  -- swap only when at least 20% closer
local MOVE_CHECK_SECONDS = 1

local Tracking = {
  rank = {},           -- [questID] = position in the last sorted order (this zone's quests)
  tier = {},           -- [questID] = 1 in the area, 2 ready turn-in nearby, 3 the rest (last sort)
  sortedAt = nil,      -- { mapID, x, y } where the last sort happened
}
ns.Tracking = Tracking

-- Sorting ----------------------------------------------------------------------------------------

-- b is clearly closer than a. Quests without a distance count as farthest.
local function clearlyCloser(b, a, distance)
  local db, da = distance[b.questID], distance[a.questID]
  if not db then
    return false
  end
  return da == nil or db < da * HYSTERESIS
end

-- Start from the previous order (new quests by distance, after the known ones), then let a quest
-- move up past a neighbour only when it is clearly closer. "Clearly closer" implies "closer", so
-- every swap fixes one out-of-order pair and the loop ends.
local function settle(list, distance, rank)
  table.sort(list, function(a, b)
    local ra, rb = rank[a.questID], rank[b.questID]
    if ra and rb then return ra < rb end
    if ra or rb then return ra ~= nil end
    local da, db = distance[a.questID], distance[b.questID]
    if da and db then return da < db end
    if da or db then return da ~= nil end
    return (a.order or 0) < (b.order or 0)
  end)
  local swapped = true
  while swapped do
    swapped = false
    for i = 1, #list - 1 do
      if clearlyCloser(list[i + 1], list[i], distance) then
        list[i], list[i + 1] = list[i + 1], list[i]
        swapped = true
      end
    end
  end
end

-- Where a quest goes, before zone: "pinned", "ignored", "hide", "separate" or "show"; and its category.
---@return string where
---@return string category
local function placement(quest)
  local char = ns.DB.char
  local category = ns.Categories:For(quest)
  if char.ignored[quest.questID] then
    return "ignored", category
  end
  if char.pins[quest.questID] then
    return "pinned", category
  end
  return ns.Categories:Mode(category), category
end

-- Sort modes (setting "Sort quests by"). Smart is the spec's order. `fixed` modes sort by a key that
-- doesn't depend on position, so moving never changes them (the movement re-sort still runs, and
-- finds the same order).
local function byLevel(a, b)
  if (a.level or 0) ~= (b.level or 0) then
    return (a.level or 0) < (b.level or 0)
  end
  return (a.order or 0) < (b.order or 0)
end
local function byLogOrder(a, b)
  return (a.order or 0) < (b.order or 0)
end

Tracking.SORT_MODES = {
  { key = "smart", label = "Smart" },
  { key = "distance", label = "Distance" },
  { key = "turnins", label = "Turn-ins first" },
  { key = "level", label = "Level", fixed = byLevel },
  { key = "log", label = "Quest log order", fixed = byLogOrder },
}

local function sortMode()
  local key = ns.DB.profile.cards.sortMode
  for _, mode in ipairs(Tracking.SORT_MODES) do
    if mode.key == key then
      return mode
    end
  end
  return Tracking.SORT_MODES[1]
end

-- A zone quest's tier (1 top .. 3) in a mode; `here`: you're in its area, `d`: its distance or nil.
local function tierFor(mode, quest, here, d)
  if mode.key == "smart" then
    if here then
      return 1
    elseif quest.readyForTurnIn and d ~= nil and d <= NEAR_TURNIN_YARDS then
      return 2
    end
    return 3
  elseif mode.key == "turnins" then
    if quest.readyForTurnIn then
      return 1
    end
    return here and 2 or 3
  end
  return 3  -- distance and the fixed modes: one list
end

---Forget the current order and sort again from scratch (sort mode changed: hysteresis would
---otherwise keep much of the old mode's order).
function Tracking:ResetOrder()
  wipe(self.rank)
  ns.Bus:Fire("TrackingResortWanted")
end

-- Re-sort this zone's quests (rule 4: called only on events).
function Tracking:Resort()
  ns.Zone:Update()
  -- Tiers, top first (decided in review):
  --   1. in the area right now (nameplate, or within the in-area radius of a spawn): the quest
  --      you're doing outranks one you'd walk to;
  --   2. rule 3, "turn-ins near you": ready and within NEAR_TURNIN_YARDS (in-zone alone put a turn-in
  --      700 yards away on top; a 213 yd turn-in above the quest being done was also wrong);
  --   3. everything else.
  --   4. with nearestAnywhere, quests outside the zone that have a distance (same continent): only
  --      used to fill free card slots (rule 5), after every zone quest.
  -- Each tier sorted by distance with hysteresis. Re-sorts happen only on events (100 yd moves), so
  -- crossing a tier line doesn't make cards jump. Those are the Smart mode's tiers; other modes
  -- (SORT_MODES) put zone quests in tiers 1-3 their own way, or in a fixed order.
  local distance, tiers = {}, { {}, {}, {}, {} }
  local nearestAnywhere = ns.DB.profile.cards.nearestAnywhere
  local mode = sortMode()
  wipe(self.tier)
  for questID, quest in pairs(ns.QuestLog.quests) do
    local shown = placement(quest) == "show"
    local inZone = shown and ns.Zone:IsInZone(quest)
    if shown and not inZone and nearestAnywhere then
      local d = ns.Navigation:Distance(quest)
      if d then
        distance[questID] = d
        self.tier[questID] = 4
        table.insert(tiers[4], quest)
      end
    end
    if inZone then
      local here = ns.Navigation:InArea(quest)
      -- Nearest target from the arrows (spawn points or marker), else the zone-map marker.
      local d = here and 0 or ns.Navigation:Distance(quest) or ns.Zone:DistanceTo(questID)
      distance[questID] = d
      local tier = tierFor(mode, quest, here, d)
      self.tier[questID] = tier
      table.insert(tiers[tier], quest)
    end
  end

  -- Settle against the previous order (hysteresis needs it), then replace it. Fixed-order modes
  -- sort zone tiers by their key instead; tier 4 (nearest outside quests) is always by distance.
  for i, list in ipairs(tiers) do
    if mode.fixed and i < 4 then
      table.sort(list, mode.fixed)
    else
      settle(list, distance, self.rank)
    end
  end
  wipe(self.rank)
  local position = 0
  for _, list in ipairs(tiers) do
    for _, quest in ipairs(list) do
      position = position + 1
      self.rank[quest.questID] = position
    end
  end

  local x, y = ns.Zone:PlayerPosition()
  self.sortedAt = x and { mapID = ns.Zone.mapID, x = x, y = y } or nil
end

---Is a quest in this zone missing from the last sort? Then the order is stale: a re-sort event like
---any other in rule 4. Happens when a quest joins the zone between sorts: a just-accepted quest whose
---map marker arrives after the QuestLogChanged sort (QUEST_POI_UPDATE), a subzone change, an unpin or
---unhide. Without this it sat at the bottom until the next 100 yd move (seen in review).
---Zone quests only: with nearestAnywhere, outside quests without a distance are never ranked.
---@return boolean
function Tracking:HasUnranked()
  for questID, quest in pairs(ns.QuestLog.quests) do
    if not self.rank[questID] and placement(quest) == "show" and ns.Zone:IsInZone(quest) then
      return true
    end
  end
  return false
end

-- The view ---------------------------------------------------------------------------------------

---What the stack should draw. Uses the order from the last Resort; quests it hasn't ranked yet
---(just pinned off, just unhidden) go after the ranked ones until the next re-sort.
---@return table view { pinned, zone, overflow, groups, elsewhere, hidden }: lists of quests;
---groups is a list of { category, label, quests } in Categories.ORDER
function Tracking:View()
  ns.Zone:Update()
  local char = ns.DB.char
  local view = { pinned = {}, zone = {}, overflow = {}, groups = {}, elsewhere = {}, hidden = {} }
  local here, byCategory = {}, {}
  for _, quest in pairs(ns.QuestLog.quests) do
    local where, category = placement(quest)
    if where == "ignored" then
      table.insert(view.hidden, quest)
    elseif where == "pinned" then
      table.insert(view.pinned, quest)
    elseif where == "separate" then
      byCategory[category] = byCategory[category] or {}
      table.insert(byCategory[category], quest)
    elseif where == "hide" then
      -- category hidden in settings: not shown
    elseif ns.Zone:IsInZone(quest) then
      here[#here + 1] = quest
    else
      table.insert(view.elsewhere, quest)
    end
  end

  for _, category in ipairs(ns.Categories.ORDER) do
    local quests = byCategory[category]
    if quests then
      table.sort(quests, function(a, b) return (a.order or 0) < (b.order or 0) end)
      table.insert(view.groups, { category = category, label = ns.Categories.LABELS[category], quests = quests })
    end
  end

  table.sort(view.pinned, function(a, b) return char.pins[a.questID] < char.pins[b.questID] end)
  local rank = self.rank
  -- The rank already orders by tier; quests not ranked yet (just unpinned or unhidden) go after the
  -- ranked ones until the next re-sort.
  table.sort(here, function(a, b)
    local ra, rb = rank[a.questID], rank[b.questID]
    if ra and rb then return ra < rb end
    if ra or rb then return ra ~= nil end
    return (a.order or 0) < (b.order or 0)
  end)
  table.sort(view.hidden, function(a, b) return (a.title or "") < (b.title or "") end)

  local cap = ns.DB.profile.cards.cap
  for i, quest in ipairs(here) do
    table.insert(i <= cap and view.zone or view.overflow, quest)
  end

  -- Rule 5, nearestAnywhere: free slots take the nearest ranked quests from Elsewhere (only tier 4
  -- quests are ranked there, and only while the setting is on).
  local free = cap - #view.zone
  if free > 0 and ns.DB.profile.cards.nearestAnywhere then
    local near, rest = {}, {}
    for _, quest in ipairs(view.elsewhere) do
      table.insert(rank[quest.questID] and near or rest, quest)
    end
    table.sort(near, function(a, b) return rank[a.questID] < rank[b.questID] end)
    for i, quest in ipairs(near) do
      table.insert(i <= free and view.zone or rest, quest)
    end
    view.elsewhere = rest
  end
  return view
end

-- Player actions -----------------------------------------------------------------------------------

function Tracking:IsPinned(questID)
  return ns.DB.char.pins[questID] ~= nil
end

function Tracking:SetPinned(questID, pinned)
  local char = ns.DB.char
  if pinned then
    char.pinCounter = char.pinCounter + 1
    char.pins[questID] = char.pinCounter
  else
    char.pins[questID] = nil
  end
  ns.Bus:Fire("TrackingChanged")
end

function Tracking:SetIgnored(questID, ignored)
  ns.DB.char.ignored[questID] = ignored or nil
  ns.Bus:Fire("TrackingChanged")
end

function Tracking:ToggleCollapsed(questID)
  local collapsed = ns.DB.char.collapsed
  collapsed[questID] = not collapsed[questID] or nil
  ns.Bus:Fire("TrackingChanged")
end

-- Events -------------------------------------------------------------------------------------------

-- A quest that leaves the log takes its pin, hidden flag and collapse state with it.
ns.Bus:On("QuestRemoved", function(questID)
  local char = ns.DB.char
  char.pins[questID] = nil
  char.ignored[questID] = nil
  char.collapsed[questID] = nil
  Tracking.rank[questID] = nil
end)

-- Rule 4's movement trigger. Only looks: it asks for a re-sort when the player has moved far
-- enough, like any other event; the re-sort itself is deferred out of combat by the stack.
local function checkMovement()
  local from = Tracking.sortedAt
  if not from or from.mapID ~= ns.Zone.mapID then
    return
  end
  local x, y = ns.Zone:PlayerPosition()
  if x and ns.Zone:Yards(from.x, from.y, x, y) > MOVE_YARDS then
    Tracking.sortedAt = nil  -- ask once; the next Resort records a new position
    ns.Bus:Fire("TrackingResortWanted")
  end
end

ns.Events:On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(MOVE_CHECK_SECONDS, checkMovement)
end)
