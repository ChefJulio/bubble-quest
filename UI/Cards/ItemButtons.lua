local ADDON_NAME, ns = ...

-- Quest item buttons (spec, Card extras: "a clickable button on the objective row for any usable
-- quest item ... Secure buttons can't be created or changed in combat; build them out of combat and
-- queue changes"). Pulled forward from phase 9 (asked for in review: the Kobold Tracking Kit).
--
-- Using an item is protected, so the button is a SecureActionButtonTemplate with type "item"
-- (Blizzard_FrameXML/SecureTemplates.lua:418, SECURE_ACTIONS.item): the click itself is the game's
-- secure code, which works in combat. Blizzard's own tracker button calls UseQuestLogSpecialItem
-- from trusted code, which an addon can't.
--
-- Combat: a secure button can't be created, moved, shown, hidden or changed in combat, and the
-- frames it's anchored to inherit that. So buttons are only set up out of combat, and while any is
-- shown the stack defers every layout (even the player's clicks) to the end of combat
-- (UI/Cards/Stack.lua). The item's icon sits left of its card, outside the panel, like Blizzard's.

local SIZE = 26
local GAP = 10  -- between the button and the panel's left edge (panel padding included)

local ItemButtons = {
  free = {},
  active = {},   -- [questID] = button
}
ns.ItemButtons = ItemButtons

---The quest's usable item, or nil. Same call Blizzard's tracker uses
---(Blizzard_ObjectiveTrackerShared.lua:53).
---@param quest table
---@return table? { link, itemID, icon, charges, index }
function ItemButtons:Info(quest)
  local index = C_QuestLog.GetLogIndexForQuestID(quest.questID)
  if not index then
    return nil
  end
  local link, icon, charges, showWhenComplete = GetQuestLogSpecialItemInfo(index)
  if not link or (quest.readyForTurnIn and not showWhenComplete) then
    return nil
  end
  local itemID = tonumber(link:match("item:(%d+)"))
  if not itemID then
    return nil
  end
  return { link = link, itemID = itemID, icon = icon, charges = charges, index = index }
end

local function updateCooldown(button)
  if button.logIndex then
    local start, duration, enable = GetQuestLogSpecialItemCooldown(button.logIndex)
    CooldownFrame_Set(button.cooldown, start or 0, duration or 0, enable)
  end
end

local function create(parent)
  -- Every Show/Hide/SetPoint/SetAttribute on it happens out of combat: Attach and ReleaseAll refuse
  -- in combat, and Stack defers layouts while buttons are shown.
  -- apiguard: allow combat-guarded as described above
  local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
  button:SetSize(SIZE, SIZE)
  button:RegisterForClicks("AnyUp", "AnyDown")  -- works with either ActionButtonUseKeyDown setting
  button:SetAttribute("type", "item")

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  button.border = button:CreateTexture(nil, "BACKGROUND")
  button.border:SetPoint("TOPLEFT", -1, 1)
  button.border:SetPoint("BOTTOMRIGHT", 1, -1)
  button.border:SetColorTexture(0, 0, 0, 0.8)
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  button.cooldown:SetAllPoints()
  button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  button.count:SetPoint("BOTTOMRIGHT", -1, 1)

  button:SetScript("OnEnter", function(self)
    if self.link then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetHyperlink(self.link)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return button
end

---Show the quest's item button next to its card. Out of combat only; returns false if refused.
---@param card table
---@param quest table
---@param parent table the stack's container
---@return boolean
function ItemButtons:Attach(card, quest, parent)
  if InCombatLockdown() then
    return false
  end
  local info = self:Info(quest)
  if not info then
    return true
  end
  local button = table.remove(self.free) or create(parent)
  button:SetAttribute("item", "item:" .. info.itemID)
  button.link, button.logIndex = info.link, info.index
  button.icon:SetTexture(info.icon)
  button.count:SetText((info.charges or 0) > 1 and info.charges or "")
  button:ClearAllPoints()
  button:SetPoint("TOPRIGHT", card.frame, "TOPLEFT", -GAP, 0)
  button:Show()
  updateCooldown(button)
  self.active[quest.questID] = button
  return true
end

---Hide every button. Out of combat only; returns false if refused (they stay until combat ends).
---@return boolean
function ItemButtons:ReleaseAll()
  if InCombatLockdown() then
    return false
  end
  for questID, button in pairs(self.active) do
    button:Hide()
    button:ClearAllPoints()
    button:SetAttribute("item", nil)
    button.link, button.logIndex = nil, nil
    self.free[#self.free + 1] = button
    self.active[questID] = nil
  end
  return true
end

---Is any button on screen (the stack then defers layouts in combat)?
---@return boolean
function ItemButtons:AnyShown()
  return next(self.active) ~= nil
end

ns.Events:On("BAG_UPDATE_COOLDOWN", function()
  for _, button in pairs(ItemButtons.active) do
    updateCooldown(button)
  end
end)
