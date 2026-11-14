local ADDON_NAME, ns = ...

-- The quest-log model: the one place Questmark reads the game's quest log.
--
-- QuestLog.quests[questID] = quest snapshot (see readQuest). Keyed by quest ID, never by log
-- index: indices shift when headers collapse or quests are added.
--
-- Every QUEST_LOG_UPDATE (the client sends at most one per frame) re-reads the log and diffs it
-- against the model, then fires on ns.Bus:
--   QuestAdded(quest)
--   QuestChanged(quest, oldQuest)
--   QuestRemoved(questID, how)   how = "turnin" | "abandon", resolved one frame later
--   QuestLogChanged()            once per batch, only when something changed
-- Re-reading is cheap: the log holds at most 40 quests.

local QuestLog = {
  quests = {},      -- [questID] = quest
  turnedIn = {},    -- [questID] = true between QUEST_TURNED_IN and the removal being resolved
  expanding = false,
  expandedFor = nil,  -- numQuests value an expand-scan already ran for (prevents repeat loops)
}
ns.QuestLog = QuestLog

-- Objective keys --------------------------------------------------------------------------------

-- "1/10 Kobold Vermin slain" -> "Kobold Vermin slain". Forever puts the counter first (confirmed in
-- game: monster "1/10 Kobold Vermin slain", item "3/8 Tough Wolf Meat"); a trailing ": 3/8" and a
-- "(45%)" suffix are stripped too. Step objectives (type "log", e.g. "Return the book to Brother
-- Paxton.") and skill objectives ("Raise your blacksmithing skill to 20") have no counter.
local function stripProgress(text)
  local stripped = text:gsub("%s*:?%s*%d+%s*/%s*%d+", ""):gsub("%s*%(%d+%%%)", "")
  return (stripped:match("^%s*(.-)%s*$"))
end

-- Rows are keyed by objective, not position: Forever quests can gain objectives mid-quest and take
-- them in any order. Key = type + text without progress; exact duplicates get "#2", "#3".
local function readObjectives(questID)
  local objectives, seen = {}, {}
  for i, info in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
    local text = info.text or ""
    local base = (info.type or "?") .. ":" .. stripProgress(text)
    local count = (seen[base] or 0) + 1
    seen[base] = count
    objectives[i] = {
      key = count > 1 and (base .. "#" .. count) or base,
      text = text,
      type = info.type,
      finished = info.finished,
      fulfilled = info.numFulfilled,
      required = info.numRequired,
    }
  end
  return objectives
end

-- Snapshots --------------------------------------------------------------------------------------

---@param info QuestInfo from C_QuestLog.GetInfo
---@param group string? the quest-log header it sits under
local function readQuest(info, group)
  local questID = info.questID
  local tag = C_QuestLog.GetQuestTagInfo(questID)
  return {
    questID = questID,
    title = info.title,
    level = info.level,
    difficultyLevel = info.difficultyLevel,
    group = group,
    frequency = info.frequency,
    classification = info.questClassification,
    suggestedGroup = info.suggestedGroup,
    isAutoComplete = info.isAutoComplete,
    tagID = tag and tag.tagID,
    tagName = tag and tag.tagName,
    isComplete = C_QuestLog.IsComplete(questID),
    readyForTurnIn = C_QuestLog.ReadyForTurnIn(questID) or false,
    isFailed = C_QuestLog.IsFailed(questID),
    objectives = readObjectives(questID),
  }
end

-- Re-read a quest we already know but couldn't see in the index loop (collapsed header): state
-- and objectives by ID, static fields carried over.
local function rereadKnownQuest(old)
  local quest = {}
  for key, value in pairs(old) do
    quest[key] = value
  end
  local questID = old.questID
  quest.signature = nil  -- recomputed in Commit from the fresh state below
  quest.isComplete = C_QuestLog.IsComplete(questID)
  quest.readyForTurnIn = C_QuestLog.ReadyForTurnIn(questID) or false
  quest.isFailed = C_QuestLog.IsFailed(questID)
  quest.objectives = readObjectives(questID)
  return quest
end

-- One string per quest; "did anything change" is one compare.
local function signature(quest)
  local parts = {
    quest.title or "",
    quest.isComplete and "C" or "-",
    quest.readyForTurnIn and "R" or "-",
    quest.isFailed and "F" or "-",
  }
  for _, objective in ipairs(quest.objectives) do
    parts[#parts + 1] = ("%s=%s%s"):format(objective.key, tostring(objective.fulfilled), objective.finished and "!" or "")
  end
  return table.concat(parts, "|")
end

-- Reading the log --------------------------------------------------------------------------------

---Visible entries of the quest log.
---@return table snapshot [questID] = quest
---@return number counted quests seen, hidden ones included (to compare with numQuests)
---@return boolean anyCollapsed
local function readVisibleEntries()
  local snapshot, counted, anyCollapsed, group = {}, 0, false, nil
  local numEntries = C_QuestLog.GetNumQuestLogEntries()
  for index = 1, numEntries do
    local info = C_QuestLog.GetInfo(index)
    if info then
      if info.isHeader then
        group = info.title
        anyCollapsed = anyCollapsed or info.isCollapsed
      elseif info.questID and info.questID > 0 then
        counted = counted + 1
        if not info.isHidden and not info.isInternalOnly then
          snapshot[info.questID] = readQuest(info, group)
        end
      end
    end
  end
  return snapshot, counted, anyCollapsed
end

-- Blizzard's own quest-log search does this (Mainline/QuestMapFrame.lua QuestSearcher): expand
-- collapsed headers, read, collapse them back. Only used when quests are missing otherwise.
function QuestLog:ExpandScan()
  self.expanding = true
  local collapsedTitles = {}
  local index = 1
  while index <= (C_QuestLog.GetNumQuestLogEntries()) do
    local info = C_QuestLog.GetInfo(index)
    if info and info.isHeader and info.isCollapsed then
      collapsedTitles[info.title] = true
      -- One argument, exactly as Blizzard's QuestSearcher calls it; the annotation's isAuto is
      -- undocumented and Blizzard never passes it.
      ---@diagnostic disable-next-line: missing-parameter
      ExpandQuestHeader(index)
    end
    index = index + 1
  end

  local snapshot = readVisibleEntries()

  -- Backwards, so collapsing a header doesn't shift the indices still to visit.
  for i = C_QuestLog.GetNumQuestLogEntries(), 1, -1 do
    local info = C_QuestLog.GetInfo(i)
    if info and info.isHeader and collapsedTitles[info.title] then
      ---@diagnostic disable-next-line: missing-parameter
      CollapseQuestHeader(i)
    end
  end
  self.expanding = false
  self:Commit(snapshot)
end

function QuestLog:Refresh()
  if self.expanding then
    return
  end
  local snapshot, counted, anyCollapsed = readVisibleEntries()

  -- Quests we already know that the index loop didn't show (under a collapsed header) are still
  -- in the log if the game can find them by ID.
  for questID, old in pairs(self.quests) do
    if not snapshot[questID] and C_QuestLog.GetLogIndexForQuestID(questID) then
      snapshot[questID] = rereadKnownQuest(old)
      counted = counted + 1
    end
  end

  local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
  if counted < numQuests and anyCollapsed and self.expandedFor ~= numQuests then
    self.expandedFor = numQuests
    ns.Debug:Event("questlog", "expand-scan", counted, numQuests)
    if not InCombatLockdown() then
      self:ExpandScan()  -- commits the complete snapshot itself
      return
    end
    -- In combat: commit what we can see now, complete it when combat ends.
    ns.Combat:Run("questlog-expand", function()
      self:ExpandScan()
    end)
  end
  self:Commit(snapshot)
end

-- Diff ----------------------------------------------------------------------------------------

function QuestLog:Commit(snapshot)
  local old = self.quests

  -- A quest missing from the snapshot but still on the player's log was hidden from this read
  -- (loading screen, collapsed header the ID lookup missed). Keep it rather than report a removal.
  for questID, quest in pairs(old) do
    if not snapshot[questID] and C_QuestLog.IsOnQuest(questID) then
      snapshot[questID] = quest
    end
  end

  self.quests = snapshot
  local changed = false
  for questID, quest in pairs(snapshot) do
    quest.signature = quest.signature or signature(quest)
    local previous = old[questID]
    if not previous then
      ns.Bus:Fire("QuestAdded", quest)
      changed = true
    elseif previous.signature ~= quest.signature then
      ns.Bus:Fire("QuestChanged", quest, previous)
      changed = true
    end
  end

  local removed = {}
  for questID in pairs(old) do
    if not snapshot[questID] then
      removed[#removed + 1] = questID
    end
  end

  -- QuestLogChanged closes each batch, and only fires when something changed: most
  -- QUEST_LOG_UPDATEs (loot, combat) change nothing, and listeners re-sort on it (spec tracking
  -- rule 4: re-sort only on events).
  if #removed > 0 then
    self:ResolveRemovals(removed)  -- fires QuestLogChanged after the removals
  elseif changed then
    ns.Bus:Fire("QuestLogChanged")
  end
end

-- There is no abandon event: QUEST_REMOVED fires for turn-ins and abandons alike, and
-- QUEST_TURNED_IN only for turn-ins, in an order we don't rely on. One frame later, either
-- signal has arrived.
function QuestLog:ResolveRemovals(questIDs)
  C_Timer.After(0, function()
    for _, questID in ipairs(questIDs) do
      local turnedIn = self.turnedIn[questID] or C_QuestLog.IsQuestFlaggedCompleted(questID)
      self.turnedIn[questID] = nil
      ns.Bus:Fire("QuestRemoved", questID, turnedIn and "turnin" or "abandon")
    end
    ns.Bus:Fire("QuestLogChanged")
  end)
end

---@param questID number
---@return table?
function QuestLog:Get(questID)
  return self.quests[questID]
end

-- Events -----------------------------------------------------------------------------------------

ns.Events:On("QUEST_LOG_UPDATE", function()
  QuestLog:Refresh()
end)

ns.Events:On("QUEST_TURNED_IN", function(questID)
  QuestLog.turnedIn[questID] = true
end)

-- Registered so /qm events shows them; the diff on the following QUEST_LOG_UPDATE does the work.
ns.Events:On("QUEST_ACCEPTED", function() end)
ns.Events:On("QUEST_REMOVED", function() end)
ns.Events:On("QUEST_WATCH_UPDATE", function() end)

ns.Events:On("PLAYER_LOGIN", function()
  QuestLog:Refresh()
end)
