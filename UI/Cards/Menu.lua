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
    -- No "Share quest": sharing (QuestLogPushQuest) is protected on Forever, blocked even through
    -- Blizzard's QuestUtil.ShareQuest (ADDON_ACTION_BLOCKED in game). Opening the quest details for
    -- Blizzard's Share button doesn't help either: the button reads the details frame's questID,
    -- which our call would have written, so its click would be blocked too. Share from the quest log.
  end)
end

---Menu for a quest in the Hidden group.
function QuestmarkerMenu:OpenForHidden(owner, quest)
  local questID = quest.questID
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(quest.title or "?")
    root:CreateButton("Unhide", function() ns.Tracking:SetIgnored(questID, false) end)
  end)
end
