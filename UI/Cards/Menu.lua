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
    -- Shown greyed out when it can't be shared (solo, or a quest the game won't share), like the
    -- quest map's menu does (QuestMapFrame.lua:2395-2400), so the option is never a mystery.
    local share = root:CreateButton("Share quest", function() QuestmarkerMenu:Share(questID) end)
    if not (IsInGroup() and C_QuestLog.IsPushableQuest(questID)) then
      share:SetEnabled(false)
    end
  end)
end

---Offer the quest to the party, through the helper Blizzard's own tracker menu calls
---(Blizzard_QuestObjectiveTracker.lua:115, QuestUtils.lua:356). The quest map plays this sound too.
---@param questID number
function QuestmarkerMenu:Share(questID)
  QuestUtil.ShareQuest(questID)
  PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
end

---Menu for a quest in the Hidden group.
function QuestmarkerMenu:OpenForHidden(owner, quest)
  local questID = quest.questID
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(quest.title or "?")
    root:CreateButton("Unhide", function() ns.Tracking:SetIgnored(questID, false) end)
  end)
end
