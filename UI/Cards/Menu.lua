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
    -- Sharing itself (QuestLogPushQuest) is protected on Forever, blocked even through Blizzard's
    -- QuestUtil.ShareQuest (ADDON_ACTION_BLOCKED in game). So this opens the quest's details, where the
    -- player clicks Blizzard's own Share button; that click works after we opened them (tested in game:
    -- the details frame's questID, written by our call, didn't taint the Share click).
    -- Greyed out when it couldn't share anyway, like the quest map's menu (QuestMapFrame.lua:2395-2400).
    local share = root:CreateButton("Share in quest log", function() QuestmarkerMenu:OpenToShare(questID) end)
    if not (IsInGroup() and C_QuestLog.IsPushableQuest(questID)) or InCombatLockdown() then
      share:SetEnabled(false)
    end
  end)
end

---Open the quest's details in the quest log (the Share button is there). Out of combat only: opening
---Blizzard's UI from an addon can taint it, which only bites in combat.
---@param questID number
function QuestmarkerMenu:OpenToShare(questID)
  if not InCombatLockdown() then
    QuestMapFrame_OpenToQuestDetails(questID)
  end
end

---Menu for a quest in the Hidden group.
function QuestmarkerMenu:OpenForHidden(owner, quest)
  local questID = quest.questID
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(quest.title or "?")
    root:CreateButton("Unhide", function() ns.Tracking:SetIgnored(questID, false) end)
  end)
end
