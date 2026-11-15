local ADDON_NAME, ns = ...

-- Hides Blizzard's objective tracker (spec: hide it, never modify it) by leaving it nothing to show.
--
-- The tracker hides itself when no module has content (Blizzard_ObjectiveTrackerContainer.lua:117-126,
-- `self:Hide()` from its own update), and its quest module lists only watched quests
-- (Blizzard_QuestObjectiveTracker.lua:185-191). Questmarker doesn't use Blizzard's watch list, so it
-- removes every quest watch (remembered per character, put back when the setting is turned off), and
-- removes new ones as Blizzard auto-adds them on QUEST_ACCEPTED (autoQuestWatch). The CVar is left
-- alone: it's the player's, and it would outlive the addon.
--
-- Why not Hide() it (the old way, and Questie's): Blizzard Show()s it whenever a module has content,
-- and hiding it again from an OnShow hook runs Blizzard's OnHide (ManagedFrameMixin.OnHide ->
-- RemoveManagedFrame) inside our code. That tainted the managed-frame layout and Edit Mode, and their
-- next updates hit secret aura reads: "GetAuraDataByIndex(): Auras cannot be accessed when secret
-- while tainted by 'Questmarker'" (BugSack, Forever 1.60.1). Here we never call the tracker's
-- methods; it shows and hides only through Blizzard's own code.
--
-- Side effects: other modules (tracked achievements, scenarios, quest auto-complete popups) still
-- show Blizzard's tracker when they have content. The popups showing is wanted; the rest is
-- Blizzard's UI for things Questmarker doesn't track.

local Tracker = {}
ns.BlizzardTracker = Tracker

function Tracker:ShouldHide()
  return ns.DB.profile ~= nil and ns.DB.profile.blizzardTracker.hide
end

-- Remove every quest watch, remembering which (to restore them later).
local function removeWatches()
  local removed = ns.DB.char.removedWatches
  local watched = {}
  for i = 1, C_QuestLog.GetNumQuestWatches() do
    local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
    if questID then
      watched[#watched + 1] = questID
    end
  end
  for _, questID in ipairs(watched) do
    removed[questID] = true
    C_QuestLog.RemoveQuestWatch(questID)
  end
end

-- Put back the watches we removed, for quests still in the log.
local function restoreWatches()
  local removed = ns.DB.char.removedWatches
  for questID in pairs(removed) do
    if C_QuestLog.GetLogIndexForQuestID(questID) then
      C_QuestLog.AddQuestWatch(questID)
    end
  end
  wipe(removed)
end

function Tracker:Apply()
  if not ns.DB.char then
    return
  end
  if self:ShouldHide() then
    removeWatches()
  else
    restoreWatches()
  end
end

---@return table state for /qm tracker
function Tracker:State()
  local frame = ObjectiveTrackerFrame
  local removed = 0
  for _ in pairs(ns.DB.char.removedWatches) do
    removed = removed + 1
  end
  return {
    exists = frame ~= nil,
    shown = frame ~= nil and frame:IsShown(),
    watches = C_QuestLog.GetNumQuestWatches(),
    removedWatches = removed,
    setting = self:ShouldHide() and "hide" or "show",
  }
end

ns.Events:On("PLAYER_ENTERING_WORLD", function()
  Tracker:Apply()
end)

-- A watch was added (Blizzard's auto-watch on accept, the quest log's Track button): remove it again.
ns.Events:On("QUEST_WATCH_LIST_CHANGED", function(_, added)
  if added and Tracker:ShouldHide() then
    removeWatches()
  end
end)

ns.Bus:On("QuestRemoved", function(questID)
  ns.DB.char.removedWatches[questID] = nil
end)

ns.Bus:On("ProfileChanged", function()
  Tracker:Apply()
end)
