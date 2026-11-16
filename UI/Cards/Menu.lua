local ADDON_NAME, ns = ...

-- Right-click menus, on Blizzard's current menu system (MenuUtil.CreateContextMenu, as used by the
-- AddOns list), not the old UIDropDownMenu code that is known to spread taint.

local QuestmarkerMenu = {}  -- not "Menu": that is Blizzard's global menu system
ns.Menu = QuestmarkerMenu

---Menu for a card.
---@param owner table the frame that was clicked
---@param quest table
function QuestmarkerMenu:OpenForCard(owner, quest)
  local questID = quest.questID
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(quest.title or "?")
    if ns.Tracking:IsPinned(questID) then
      root:CreateButton("Unpin", function() ns.Tracking:SetPinned(questID, false) end)
    else
      root:CreateButton("Pin (always show)", function() ns.Tracking:SetPinned(questID, true) end)
    end
    root:CreateButton("Hide", function() ns.Tracking:SetIgnored(questID, true) end)
    local collapsed = ns.DB.char.collapsed[questID]
    root:CreateButton(collapsed and "Expand" or "Collapse", function() ns.Tracking:ToggleCollapsed(questID) end)
    -- Greyed out when it can't share: solo, or a quest the game won't share (like the quest map's
    -- menu, QuestMapFrame.lua:2395-2400). In combat it queues (see Share).
    local inCombat = InCombatLockdown()
    local share = root:CreateButton(inCombat and "Share quest (after combat)" or "Share quest", function()
      QuestmarkerMenu:Share(questID)
    end)
    if not (IsInGroup() and C_QuestLog.IsPushableQuest(questID)) then
      share:SetEnabled(false)
    end
  end)
end

-- The log-index form Forever's own quest map uses (QuestMapFrame.lua:1450-1452); the WoW API
-- annotations still describe the old no-argument version.
-- Called only out of combat: pushNow runs from Share's out-of-combat branch or the combat queue.
---@type fun(questLogIndex: number)
local questLogPushQuest = QuestLogPushQuest  -- apiguard: allow combat-restricted; out of combat only


local function pushNow(questID)
  local index = C_QuestLog.GetLogIndexForQuestID(questID)
  if index and IsInGroup() then
    questLogPushQuest(index)
    PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
  end
end

---Offer the quest to the party. QuestLogPushQuest is restricted in combat (Patch 12.0.0 API notes;
---blocked in game, and in Pretty Wide Quest Log on Forever, issue #38); out of combat addon calls work
---[Inferred from those reports]. Out of combat it shares from the click; in combat it's queued and sent
---when combat ends (asked for in review; Pretty Wide Quest Log does the same), said so in chat.
---@param questID number
function QuestmarkerMenu:Share(questID)
  if not InCombatLockdown() then
    pushNow(questID)
    return
  end
  local title = C_QuestLog.GetTitleForQuestID(questID) or "quest"
  ns.Debug:Print(("Sharing %s when combat ends."):format(title))
  ns.Combat:Run("share:" .. questID, function() pushNow(questID) end)
end

---Menu for a quest in the Hidden group.
function QuestmarkerMenu:OpenForHidden(owner, quest)
  local questID = quest.questID
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(quest.title or "?")
    root:CreateButton("Unhide", function() ns.Tracking:SetIgnored(questID, false) end)
  end)
end
