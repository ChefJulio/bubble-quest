local ADDON_NAME, ns = ...

-- The tracking rules (spec, Tracking). This module decides what shows and in what order; the card
-- stack only draws the result (Tracking:View()).
--
--   1. Pinned quests always show, in pin order, wherever they are; not counted in the cap.
--   2. Other quests are chosen by zone and sorted by distance to their map marker.
--   3. Quests whose area you're in go first. Ready quests get their own section, "Ready to turn in"
--      (review: you're either at a hub handing in or out doing objectives; mixing the two put a
--      turn-in above the quest being done). It goes above this zone's cards when you're at a hub
--      (Tracking.turninsFirst: the nearest turn-in clearly closer than the nearest objective), below
--      them otherwise.
--   4. The order changes only on events: QuestLogChanged, a zone change, moving more than
--      MOVE_YARDS since the last sort, or a zone quest the last sort didn't rank (HasUnranked).
--      Never on a timer by itself, never in combat (the stack defers). Hysteresis: neighbours swap
--      only when the lower one is HYSTERESIS times closer; the turn-in section flips the same way.
--   5. At most profile.cards.cap zone cards; the rest behind "+ N more here". With "Always show
--      nearest quests" (cards.nearestAnywhere), free slots take the nearest quests outside the zone
--      (same continent, by distance, ranked after every zone quest); the rest stay in Elsewhere.
--      With a height set (resize grip), the stack fills that height instead of counting (UI/Cards/
--      Stack.lua); View then hands over every candidate in order.
--   6. Ignored quests are hidden until unhidden.
-- Categories (phase 4): a category set to "separate" gets its own group (all its quests, any zone);
-- "hide" removes its quests. Pinned quests show whatever their category.

local MOVE_YARDS = 100
local HYSTERESIS = 0.8  -- swap only when at least 20% closer
local MOVE_CHECK_SECONDS = 1

local Tracking = {
  rank = {},           -- [questID] = position in the last sorted order (this zone's quests)
  tier = {},           -- [questID] = 1 in the area, 2 the rest, 3 nearest outside, "turnin" (last sort)
  turninsFirst = false,  -- rule 3: the turn-in section goes above this zone's cards (at a hub)
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

-- ("Turn-ins first" went when ready quests got their own section; a saved "turnins" reads as Smart.)
Tracking.SORT_MODES = {
  { key = "smart", label = "Smart" },
  { key = "distance", label = "Distance" },
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
  -- A mode that no longer exists ("turnins"): Smart, saved, so the settings dropdown shows it too.
  ns.DB.profile.cards.sortMode = Tracking.SORT_MODES[1].key
  return Tracking.SORT_MODES[1]
end

-- An active zone quest's tier (1 top, 2) in a mode; `here`: you're in its area. Smart puts a quest
-- with a running timer (it's urgent: review) or whose area you're in on top.
local function tierFor(mode, quest, here)
  if mode.key == "smart" and (here or ns.Card.TimerEnd(quest.questID)) then
    return 1
  end
  return 2  -- distance and the fixed modes: one list
end

-- Rule 3's hub test, with hysteresis: flip only when the other side is clearly closer.
local function turninsFirst(was, nearestTurnin, nearestActive)
  if not nearestTurnin then
    return false
  end
  if not nearestActive then
    return true
  end
  if was then
    return not (nearestActive < nearestTurnin * HYSTERESIS)
  end
  return nearestTurnin < nearestActive * HYSTERESIS
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
  --      you're doing outranks one you'd walk to; or a running timer (urgent);
  --   2. everything else active in the zone;
  --   3. with nearestAnywhere, active quests outside the zone that have a distance (same continent):
  --      only used to fill free card slots (rule 5), after every zone quest;
  --   4. ready to turn in (rule 3's own section): in the zone, or with nearestAnywhere anywhere on the
  --      continent; always by distance.
  -- Each tier sorted by distance with hysteresis. Re-sorts happen only on events (100 yd moves), so
  -- crossing a tier line doesn't make cards jump. Those are the Smart mode's tiers; other modes
  -- (SORT_MODES) put zone quests in tiers 1-2 their own way, or in a fixed order.
  local distance, tiers = {}, { {}, {}, {}, {} }
  local nearestAnywhere = ns.DB.profile.cards.nearestAnywhere
  local mode = sortMode()
  local nearestTurnin, nearestActive
  wipe(self.tier)
  for questID, quest in pairs(ns.QuestLog.quests) do
    local shown = placement(quest) == "show"
    local inZone = shown and ns.Zone:IsInZone(quest)
    local d, tier
    if inZone then
      local here = not quest.readyForTurnIn and ns.Navigation:InArea(quest)
      -- Nearest target from the arrows (spawn points or marker), else the zone-map marker.
      d = here and 0 or ns.Navigation:Distance(quest) or ns.Zone:DistanceTo(questID)
      tier = quest.readyForTurnIn and 4 or tierFor(mode, quest, here)
    elseif shown and nearestAnywhere then
      d = ns.Navigation:Distance(quest)
      tier = d and (quest.readyForTurnIn and 4 or 3)
    end
    if tier then
      distance[questID] = d
      self.tier[questID] = tier == 4 and "turnin" or tier
      table.insert(tiers[tier], quest)
      if d and tier == 4 then
        nearestTurnin = math.min(nearestTurnin or d, d)
      elseif d and tier < 3 then
        nearestActive = math.min(nearestActive or d, d)
      end
    end
  end
  self.turninsFirst = turninsFirst(self.turninsFirst, nearestTurnin, nearestActive)

  -- Settle against the previous order (hysteresis needs it), then replace it. Fixed-order modes
  -- sort the zone's active tiers by their key instead; tiers 3 and 4 are always by distance.
  for i, list in ipairs(tiers) do
    if mode.fixed and i < 3 then
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
---@return table view { pinned, turnins, turninsFirst, here, near, groups, elsewhere, hidden }: lists of
---quests (here: this zone's active quests in order, near: nearestAnywhere's candidates; split by
---Fill); groups is a list of { category, label, quests } in Categories.ORDER
function Tracking:View()
  ns.Zone:Update()
  local char = ns.DB.char
  local view = {
    pinned = {}, turnins = {}, turninsFirst = self.turninsFirst, groups = {}, elsewhere = {}, hidden = {},
  }
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
    elseif quest.readyForTurnIn and (self.tier[quest.questID] == "turnin" or ns.Zone:IsInZone(quest)) then
      table.insert(view.turnins, quest)
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
  local function byRank(a, b)
    local ra, rb = rank[a.questID], rank[b.questID]
    if ra and rb then return ra < rb end
    if ra or rb then return ra ~= nil end
    return (a.order or 0) < (b.order or 0)
  end
  table.sort(here, byRank)
  table.sort(view.turnins, byRank)
  table.sort(view.hidden, function(a, b) return (a.title or "") < (b.title or "") end)

  view.here = here
  -- Rule 5, nearestAnywhere: candidates for free slots, the nearest ranked quests from Elsewhere (only
  -- tier 3 quests are ranked there, and only while the setting is on).
  view.near = {}
  if ns.DB.profile.cards.nearestAnywhere then
    local rest = {}
    for _, quest in ipairs(view.elsewhere) do
      table.insert(rank[quest.questID] and view.near or rest, quest)
    end
    table.sort(view.near, function(a, b) return rank[a.questID] < rank[b.questID] end)
    view.elsewhere = rest
  end
  return view
end

---Rule 5: the zone's cards, in order, while they fit; the rest behind "+ N more here"; then free room
---goes to the nearest outside quests (nearestAnywhere), the rest of which stay in Elsewhere. `place`
---places one card if it fits (by count, or by height with one set: the stack decides) and says so.
---Once one doesn't fit, nothing after it is placed, so the order stays the order.
---@param view table from View
---@param place fun(quest: table, index: number): boolean
---@return table[] overflow quests behind "+ N more here"
function Tracking:Fill(view, place)
  local overflow, placed = {}, 0
  for _, quest in ipairs(view.here) do
    if #overflow == 0 and place(quest, placed + 1) then
      placed = placed + 1
    else
      overflow[#overflow + 1] = quest
    end
  end
  local full = #overflow > 0
  for _, quest in ipairs(view.near) do
    full = full or not place(quest, placed + 1)
    if full then
      table.insert(view.elsewhere, quest)
    else
      placed = placed + 1
    end
  end
  return overflow
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

---Is the last sort's order clearly wrong where you stand now? A card clearly closer (HYSTERESIS) than
---the one above it in its tier, a quest whose area you entered or left (Smart's tier 1), or the
---turn-in section on the wrong side (rule 3). Review: a quest 218 yd away stayed above one at 167 yd
---(and the guide line followed it) because the player hadn't walked MOVE_YARDS since the last sort.
---The same hysteresis as the sort, so this never asks for a re-sort that wouldn't change anything.
---@return boolean
function Tracking:OrderStale()
  local mode = sortMode()
  local lists, distance = {}, {}
  local nearestTurnin, nearestActive
  for questID, tier in pairs(self.tier) do
    local quest = ns.QuestLog:Get(questID)
    if quest then
      local here = tier ~= "turnin" and tier ~= 3 and ns.Navigation:InArea(quest)
      if mode.key == "smart" and tier ~= "turnin" and tier ~= 3
          and (tier == 1) ~= (here or ns.Card.TimerEnd(questID) ~= nil) then
        return true  -- entered or left its area
      end
      -- Exactly Resort's distances (its marker fallback in the zone), or it would ask forever.
      local d = here and 0 or ns.Navigation:Distance(quest)
        or (ns.Zone:IsInZone(quest) and ns.Zone:DistanceTo(questID) or nil)
      distance[questID] = d
      if d and tier == "turnin" then
        nearestTurnin = math.min(nearestTurnin or d, d)
      elseif d and tier ~= 3 then
        nearestActive = math.min(nearestActive or d, d)
      end
      if not (mode.fixed and (tier == 1 or tier == 2)) then
        lists[tier] = lists[tier] or {}
        table.insert(lists[tier], quest)
      end
    end
  end
  if turninsFirst(self.turninsFirst, nearestTurnin, nearestActive) ~= self.turninsFirst then
    return true
  end
  local rank = self.rank
  for _, list in pairs(lists) do
    table.sort(list, function(a, b) return (rank[a.questID] or 0) < (rank[b.questID] or 0) end)
    for i = 1, #list - 1 do
      if clearlyCloser(list[i + 1], list[i], distance) then
        return true
      end
    end
  end
  return false
end

-- Rule 4's movement triggers. Only look: they ask for a re-sort like any other event; the re-sort
-- itself is deferred out of combat by the stack. Moving MOVE_YARDS since the last sort, or the order
-- now clearly wrong (OrderStale).
local function checkMovement()
  local from = Tracking.sortedAt
  if not from or from.mapID ~= ns.Zone.mapID then
    return
  end
  local x, y = ns.Zone:PlayerPosition()
  if x and (ns.Zone:Yards(from.x, from.y, x, y) > MOVE_YARDS or Tracking:OrderStale()) then
    Tracking.sortedAt = nil  -- ask once; the next Resort records a new position
    ns.Bus:Fire("TrackingResortWanted")
  end
end

ns.Events:On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(MOVE_CHECK_SECONDS, checkMovement)
end)
