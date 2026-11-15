local ADDON_NAME, ns = ...

-- The tracking rules (spec, Tracking). This module decides what shows and in what order; the card
-- stack only draws the result (Tracking:View()).
--
--   1. Pinned quests always show, in pin order, wherever they are; not counted in the cap.
--   2. Other quests are chosen by zone and sorted by distance to their map marker.
--   3. Ready turn-ins within NEAR_TURNIN_YARDS go first; farther ones sort by distance like the rest.
--   4. The order changes only on events: QuestLogChanged, a zone change, or moving more than
--      MOVE_YARDS since the last sort. Never on a timer by itself, never in combat (the stack
--      defers). Hysteresis: neighbours swap only when the lower one is HYSTERESIS times closer.
--   5. At most profile.cards.cap zone cards; the rest behind "+ N more here".
--   6. Ignored quests are hidden until unhidden.
-- Categories (phase 4): a category set to "separate" gets its own group (all its quests, any zone);
-- "hide" removes its quests. Pinned quests show whatever their category.

local MOVE_YARDS = 100
local NEAR_TURNIN_YARDS = 250
local HYSTERESIS = 0.8  -- swap only when at least 20% closer
local MOVE_CHECK_SECONDS = 1

local Tracking = {
  rank = {},           -- [questID] = position in the last sorted order (this zone's quests)
  nearTurnIn = {},     -- [questID] = true: ready and within NEAR_TURNIN_YARDS at the last sort
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

-- Re-sort this zone's quests (rule 4: called only on events).
function Tracking:Resort()
  ns.Zone:Update()
  local distance, ready, rest = {}, {}, {}
  wipe(self.nearTurnIn)
  for questID, quest in pairs(ns.QuestLog.quests) do
    if placement(quest) == "show" and ns.Zone:IsInZone(quest) then
      -- Nearest target from the arrows (spawn points or marker), else the zone-map marker.
      -- A quest creature on the player's nameplates means "here": distance 0, whatever the targets say.
      local d = ns.Nearby:Has(questID) and 0 or ns.Navigation:Distance(quest) or ns.Zone:DistanceTo(questID)
      distance[questID] = d
      -- Rule 3, "turn-ins near you": ready and within NEAR_TURNIN_YARDS. (In-zone alone put a turn-in
      -- 700 yards away at the top, seen in game.) Re-sorts happen only after moving 100 yards, so
      -- crossing this line doesn't make cards jump.
      local near = quest.readyForTurnIn and d ~= nil and d <= NEAR_TURNIN_YARDS
      self.nearTurnIn[questID] = near or nil
      local list = near and ready or rest
      list[#list + 1] = quest
    end
  end
  settle(ready, distance, self.rank)
  settle(rest, distance, self.rank)

  wipe(self.rank)
  for i, quest in ipairs(ready) do
    self.rank[quest.questID] = i
  end
  for i, quest in ipairs(rest) do
    self.rank[quest.questID] = #ready + i
  end

  local x, y = ns.Zone:PlayerPosition()
  self.sortedAt = x and { mapID = ns.Zone.mapID, x = x, y = y } or nil
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
  local near = self.nearTurnIn
  table.sort(here, function(a, b)
    local na, nb = near[a.questID] == true, near[b.questID] == true
    if na ~= nb then return na end
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
