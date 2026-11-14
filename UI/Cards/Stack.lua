local ADDON_NAME, ns = ...

-- The card stack: this zone's quests as cards, then a collapsible "Elsewhere (N)" group with the
-- rest under zone headings.
--
-- When things change (spec: nothing jumps around):
--   - Progress updates in place, any time, combat included (Card:UpdateInPlace).
--   - Cards appear, disappear or move only on QuestLogChanged or a zone change, and never in
--     combat: those layouts wait for the end of combat (ns.Combat). Not a taint issue (plain
--     frames), a calm-UI rule.
--   - The player's own clicks (collapse, Elsewhere) apply immediately.
--
-- Order: turn-in cards first (spec, Card behavior), then quest-log order, so it is stable.
-- STOPGAP until phase 3: no height limit; the visible-card cap comes with the tracking rules.

local DEFAULT_POSITION = { "TOPRIGHT", "TOPRIGHT", -60, -230 }
local HEADING_HEIGHT = 16

local Stack = {
  container = nil,
  visible = {},  -- [questID] = card currently on screen
}
ns.Stack = Stack

local cardPool, headingPool

local function byReadyThenLogOrder(a, b)
  if a.readyForTurnIn ~= b.readyForTurnIn then
    return a.readyForTurnIn
  end
  return (a.order or 0) < (b.order or 0)
end

local function placeCard(quest, y)
  local card = cardPool:Acquire()
  card.frame:SetPoint("TOPLEFT", Stack.container, "TOPLEFT", 0, -y)
  Stack.visible[quest.questID] = card
  card.ready = quest.readyForTurnIn
  return card:SetQuest(quest, ns.DB.char.collapsed[quest.questID] == true)
end

local function placeHeading(text, y)
  local heading = headingPool:Acquire()
  heading:SetPoint("TOPLEFT", Stack.container, "TOPLEFT", 0, -y)
  heading:SetText(text)
  return HEADING_HEIGHT
end

function Stack:Layout()
  if not self.container then
    return
  end
  ns.Zone:Update()
  cardPool:ReleaseAll()
  headingPool:ReleaseAll()
  wipe(self.visible)

  local here, away = {}, {}
  for _, quest in pairs(ns.QuestLog.quests) do
    local list = ns.Zone:IsInZone(quest) and here or away
    list[#list + 1] = quest
  end
  table.sort(here, byReadyThenLogOrder)

  local y = 0
  for _, quest in ipairs(here) do
    y = y + placeCard(quest, y)
  end

  local elsewhere = self.elsewhereButton
  if #away == 0 then
    elsewhere:Hide()
  else
    local expanded = ns.DB.char.elsewhere.expanded
    elsewhere:ClearAllPoints()
    elsewhere:SetPoint("TOPLEFT", self.container, "TOPLEFT", 0, -y)
    elsewhere.label:SetText(("%s Elsewhere (%d)"):format(expanded and "-" or "+", #away))
    elsewhere:Show()
    y = y + HEADING_HEIGHT + 4

    if expanded then
      local byZone, zones = {}, {}
      for _, quest in ipairs(away) do
        local zone = ns.Zone:NameFor(quest)
        if not byZone[zone] then
          byZone[zone] = {}
          zones[#zones + 1] = zone
        end
        table.insert(byZone[zone], quest)
      end
      table.sort(zones)
      for _, zone in ipairs(zones) do
        y = y + placeHeading(zone, y)
        table.sort(byZone[zone], byReadyThenLogOrder)
        for _, quest in ipairs(byZone[zone]) do
          y = y + placeCard(quest, y)
        end
      end
    end
  end

  self.container:SetHeight(math.max(y, 1))
end

---Re-layout now, or after combat unless the player asked for it.
---@param playerAction boolean? true for the player's own clicks
function Stack:RequestLayout(playerAction)
  if playerAction or not InCombatLockdown() then
    self:Layout()
  else
    ns.Combat:Run("cards-layout", function() self:Layout() end)
  end
end

-- Position and lock ------------------------------------------------------------------------------

function Stack:ApplyPosition()
  local p = ns.DB.profile.cards.position or DEFAULT_POSITION
  self.container:ClearAllPoints()
  self.container:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function Stack:ApplyLock()
  local unlocked = not ns.DB.profile.cards.locked
  self.container:EnableMouse(unlocked)
  self.dragBackground:SetShown(unlocked)
  self.dragLabel:SetShown(unlocked)
end

local function savePosition(container)
  container:StopMovingOrSizing()
  local point, _, relativePoint, x, y = container:GetPoint(1)
  ns.DB.profile.cards.position = { point, relativePoint, x, y }
end

-- Construction -------------------------------------------------------------------------------------

function Stack:Create()
  local container = CreateFrame("Frame", "QuestmarkStack", UIParent)
  container:SetSize(ns.Card.WIDTH, 1)
  container:SetMovable(true)
  container:SetClampedToScreen(true)
  container:RegisterForDrag("LeftButton")
  container:SetScript("OnDragStart", container.StartMoving)
  container:SetScript("OnDragStop", savePosition)
  self.container = container

  -- Shown only while unlocked, so it's clear what can be dragged.
  self.dragBackground = container:CreateTexture(nil, "BACKGROUND")
  self.dragBackground:SetAllPoints()
  self.dragBackground:SetColorTexture(0.2, 0.6, 1, 0.25)
  self.dragLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  self.dragLabel:SetPoint("BOTTOM", container, "TOP", 0, 2)
  self.dragLabel:SetText("Questmark: drag to move, lock in settings")

  cardPool = ns.CreatePool(function()
    return ns.Card.Create(container, function(questID)
      local collapsed = ns.DB.char.collapsed
      collapsed[questID] = not collapsed[questID] or nil
      Stack:RequestLayout(true)
    end)
  end, function(card)
    card.questID = nil
  end)

  headingPool = ns.CreatePool(function()
    local heading = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    heading:SetTextColor(0.7, 0.7, 0.7)
    return heading
  end)

  local elsewhere = CreateFrame("Button", nil, container)
  elsewhere:SetSize(ns.Card.WIDTH, HEADING_HEIGHT)
  elsewhere.label = elsewhere:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
  elsewhere.label:SetPoint("LEFT")
  elsewhere:SetScript("OnClick", function()
    local state = ns.DB.char.elsewhere
    state.expanded = not state.expanded
    Stack:RequestLayout(true)
  end)
  self.elsewhereButton = elsewhere

  self:ApplyPosition()
  self:ApplyLock()
end

-- Events -------------------------------------------------------------------------------------------

ns.Events:On("PLAYER_LOGIN", function()
  Stack:Create()
end)

-- Membership can change with the zone, the map markers, or the log itself.
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "QUEST_POI_UPDATE" }) do
  ns.Events:On(event, function()
    Stack:RequestLayout()
  end)
end

ns.Bus:On("QuestLogChanged", function()
  Stack:RequestLayout()
end)

ns.Bus:On("QuestChanged", function(quest)
  local card = Stack.visible[quest.questID]
  if not card then
    return
  end
  local collapsed = ns.DB.char.collapsed[quest.questID] == true
  if card.ready == quest.readyForTurnIn and card.rowCount == ns.Card.RowCount(quest, collapsed) then
    card:UpdateInPlace(quest)
  else
    Stack:RequestLayout()  -- turned ready, or an objective appeared: layout (after combat)
  end
end)

ns.Bus:On("ProfileChanged", function()
  if Stack.container then
    Stack:ApplyPosition()
    Stack:ApplyLock()
    Stack:RequestLayout(true)
  end
end)
