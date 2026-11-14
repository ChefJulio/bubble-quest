local ADDON_NAME, ns = ...

-- The card stack: a header row, then what ns.Tracking:View() says to show:
--   pinned cards, this zone's cards (capped), "+ N more here", "Elsewhere (N)", "Hidden (N)".
-- Tracking decides order and membership; this file only draws.
--
-- When things change (spec: nothing jumps around):
--   - Progress updates in place, any time, combat included (Card:UpdateInPlace).
--   - Re-sorts happen on QuestLogChanged, zone changes and Tracking's movement trigger, and never in
--     combat: they wait for the end of combat (ns.Combat). A calm-UI rule; the frames are plain.
--   - The player's own clicks (collapse, pin, hide, groups, header buttons) apply at once, even in
--     combat; a re-sort still waiting stays queued until combat ends.

local DEFAULT_POSITION = { "TOPRIGHT", "TOPRIGHT", -60, -230 }
local HEADER_HEIGHT = 20
local LINE_HEIGHT = 16
local BUTTON_SIZE_X, BUTTON_SIZE_Y = 18, 19  -- Blizzard's tracker header buttons

local Stack = {
  container = nil,  ---@type Frame?
  visible = {},     -- [questID] = card currently on screen
  resortPending = false,
}
ns.Stack = Stack

local cardPool, headingPool, linePool

-- Drawing ----------------------------------------------------------------------------------------

local function placeCard(quest, y, options)
  local card = cardPool:Acquire()
  card.frame:SetPoint("TOPLEFT", Stack.body, "TOPLEFT", 0, -y)
  Stack.visible[quest.questID] = card
  card.ready = quest.readyForTurnIn
  return card:SetQuest(quest, ns.DB.char.collapsed[quest.questID] == true, options)
end

local function placeHeading(text, y)
  local heading = headingPool:Acquire()
  heading:SetPoint("TOPLEFT", Stack.body, "TOPLEFT", 0, -y)
  heading:SetText(text)
  return LINE_HEIGHT
end

---A clickable text line: group toggles and hidden quests.
---@param onClick fun(line: table, button: string)
local function placeLine(text, y, onClick, indent)
  local line = linePool:Acquire()
  line:SetPoint("TOPLEFT", Stack.body, "TOPLEFT", indent or 0, -y)
  line.label:SetText(text)
  line.onClick = onClick
  return LINE_HEIGHT + 2
end

local function toggleGroup(state)
  return function()
    state.expanded = not state.expanded
    Stack:Request(false, true)
  end
end

local function updateHeader()
  local header = Stack.header
  local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
  local max = C_QuestLog.GetMaxNumQuestsCanAccept()
  local r, g, b = 0.8, 0.8, 0.8
  if numQuests >= max then
    r, g, b = 1, 0.2, 0.2
  elseif numQuests >= max - 5 then
    r, g, b = 1, 0.6, 0.1
  end
  header.count:SetText(("%d/%d"):format(numQuests, max))
  header.count:SetTextColor(r, g, b)

  local minimized = ns.DB.char.minimized
  header.minimize:SetNormalAtlas(minimized and "ui-questtrackerbutton-expand-all" or "ui-questtrackerbutton-collapse-all")
  header.minimize:SetPushedAtlas(minimized and "ui-questtrackerbutton-expand-all-pressed"
    or "ui-questtrackerbutton-collapse-all-pressed")
  header.lock:SetAlpha(ns.DB.profile.cards.locked and 1 or 0.4)
end

function Stack:Layout()
  if not self.container then
    return
  end
  cardPool:ReleaseAll()
  headingPool:ReleaseAll()
  linePool:ReleaseAll()
  wipe(self.visible)
  updateHeader()

  local char = ns.DB.char
  if char.minimized then
    self.body:Hide()
    self.container:SetHeight(HEADER_HEIGHT)
    return
  end
  self.body:Show()

  local view = ns.Tracking:View()
  local y = 0

  for _, quest in ipairs(view.pinned) do
    local elsewhere = not ns.Zone:IsInZone(quest) and ns.Zone:NameFor(quest) or nil
    y = y + placeCard(quest, y, { pinned = true, zone = elsewhere })
  end
  for _, quest in ipairs(view.zone) do
    y = y + placeCard(quest, y)
  end

  if #view.overflow > 0 then
    if char.overflow.expanded then
      for _, quest in ipairs(view.overflow) do
        y = y + placeCard(quest, y)
      end
      y = y + placeLine("- Show fewer", y, toggleGroup(char.overflow))
    else
      y = y + placeLine(("+ %d more here"):format(#view.overflow), y, toggleGroup(char.overflow))
    end
  end

  if #view.elsewhere > 0 then
    local expanded = char.elsewhere.expanded
    y = y + placeLine(("%s Elsewhere (%d)"):format(expanded and "-" or "+", #view.elsewhere), y,
      toggleGroup(char.elsewhere))
    if expanded then
      local byZone, zones = {}, {}
      for _, quest in ipairs(view.elsewhere) do
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
        table.sort(byZone[zone], function(a, b) return (a.order or 0) < (b.order or 0) end)
        for _, quest in ipairs(byZone[zone]) do
          y = y + placeCard(quest, y)
        end
      end
    end
  end

  if #view.hidden > 0 then
    local expanded = char.hidden.expanded
    y = y + placeLine(("%s Hidden (%d)"):format(expanded and "-" or "+", #view.hidden), y, toggleGroup(char.hidden))
    if expanded then
      for _, quest in ipairs(view.hidden) do
        y = y + placeLine(quest.title or "?", y, function(line)
          ns.Menu:OpenForHidden(line, quest)
        end, 14)
      end
    end
  end

  self.body:SetHeight(math.max(y, 1))
  self.container:SetHeight(HEADER_HEIGHT + 4 + y)
end

-- Re-sort (rule 4) and layout, applying the combat rule. Player actions lay out at once; anything
-- else waits for the end of combat, and a pending re-sort never runs in combat.
function Stack:Flush()
  if self.resortPending then
    self.resortPending = false
    ns.Tracking:Resort()
  end
  self:Layout()
end

---@param resort boolean the order may change (an event from rule 4)
---@param playerAction boolean? the player's own click: lay out now
function Stack:Request(resort, playerAction)
  if resort then
    self.resortPending = true
  end
  if not InCombatLockdown() then
    self:Flush()
    return
  end
  if playerAction then
    self:Layout()
  end
  ns.Combat:Run("cards", function() self:Flush() end)
end

-- Position and lock ------------------------------------------------------------------------------

-- Until the player drags the stack, it sits exactly where Blizzard's (hidden) tracker is: the
-- game's layout system places that frame below the minimap and its widgets (timers, buffs), and
-- anchoring to it follows any change to that layout. Anchoring ours to theirs changes nothing of
-- theirs; ObjectiveTrackerFrame is not protected on Forever (/qm tracker).
function Stack:ApplyPosition()
  local container, saved = self.container, ns.DB.profile.cards.position
  if not container then
    return
  end
  container:ClearAllPoints()
  if saved then
    container:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
  elseif ObjectiveTrackerFrame then
    container:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "TOPRIGHT")
  else
    local p = DEFAULT_POSITION
    container:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  end
end

function Stack:ApplyLock()
  if self.header then
    updateHeader()
  end
end

-- StartMoving re-anchors the frame to UIParent, so the point read back is screen-relative.
local function savePosition()
  local container = Stack.container
  if not container then
    return
  end
  container:StopMovingOrSizing()
  local point, _, relativePoint, x, y = container:GetPoint(1)
  ns.DB.profile.cards.position = { point, relativePoint, x, y }
end

-- Construction -------------------------------------------------------------------------------------

local function headerButton(parent, tooltip, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(BUTTON_SIZE_X, BUTTON_SIZE_Y)
  button:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(tooltip(), 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return button
end

local function createHeader(container)
  local header = CreateFrame("Frame", nil, container)
  header:SetPoint("TOPLEFT")
  header:SetSize(ns.Card.WIDTH, HEADER_HEIGHT)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function()
    if not ns.DB.profile.cards.locked then
      container:StartMoving()
    end
  end)
  header:SetScript("OnDragStop", savePosition)

  header.title = header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
  header.title:SetPoint("LEFT", 0, 0)
  header.title:SetText("Questmark")

  header.minimize = headerButton(header, function()
    return ns.DB.char.minimized and "Show Questmark's cards" or "Minimize to this header"
  end, function()
    ns.DB.char.minimized = not ns.DB.char.minimized
    Stack:Request(false, true)
  end)
  header.minimize:SetPoint("RIGHT", 0, 0)

  header.settings = headerButton(header, function() return "Questmark settings" end, function()
    ns.Settings:Open()
  end)
  header.settings:SetNormalAtlas("ui-questtrackerbutton-filter")
  header.settings:SetPushedAtlas("ui-questtrackerbutton-filter-pressed")
  header.settings:SetPoint("RIGHT", header.minimize, "LEFT", -2, 0)

  header.lock = headerButton(header, function()
    return ns.DB.profile.cards.locked and "Locked. Click to unlock, then drag this header to move the cards."
      or "Unlocked: drag this header to move the cards. Click to lock."
  end, function()
    local cards = ns.DB.profile.cards
    cards.locked = not cards.locked
    updateHeader()
  end)
  header.lock:SetNormalAtlas("groupfinder-icon-lock")
  header.lock:SetPoint("RIGHT", header.settings, "LEFT", -2, 0)

  header.count = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  header.count:SetPoint("RIGHT", header.lock, "LEFT", -6, 0)

  return header
end

function Stack:Create()
  local container = CreateFrame("Frame", "QuestmarkStack", UIParent)
  container:SetSize(ns.Card.WIDTH, HEADER_HEIGHT)
  container:SetMovable(true)
  container:SetClampedToScreen(true)
  self.container = container

  self.header = createHeader(container)

  local body = CreateFrame("Frame", nil, container)
  body:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -4)
  body:SetSize(ns.Card.WIDTH, 1)
  self.body = body

  cardPool = ns.CreatePool(function()
    return ns.Card.Create(body, function(questID)
      ns.Tracking:ToggleCollapsed(questID)
    end, function(card, questID)
      local quest = ns.QuestLog:Get(questID)
      if quest then
        ns.Menu:OpenForCard(card.frame, quest)
      end
    end)
  end, function(card)
    card.questID = nil
  end)

  headingPool = ns.CreatePool(function()
    local heading = body:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    heading:SetTextColor(0.7, 0.7, 0.7)
    return heading
  end)

  linePool = ns.CreatePool(function()
    local line = CreateFrame("Button", nil, body)
    line:SetSize(ns.Card.WIDTH, LINE_HEIGHT)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    line.label = line:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
    line.label:SetPoint("LEFT")
    line:SetScript("OnClick", function(self, button)
      if self.onClick then
        self.onClick(self, button)
      end
    end)
    return line
  end, function(line)
    line.onClick = nil
  end)

  self:ApplyPosition()
end

-- Events -------------------------------------------------------------------------------------------

ns.Events:On("PLAYER_LOGIN", function()
  Stack:Create()
end)

-- Rule 4: these may change the order.
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
  ns.Events:On(event, function() Stack:Request(true) end)
end
ns.Bus:On("QuestLogChanged", function() Stack:Request(true) end)
ns.Bus:On("TrackingResortWanted", function() Stack:Request(true) end)

-- These can change membership (subzone fallback, map markers) but are not re-sort events.
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "QUEST_POI_UPDATE" }) do
  ns.Events:On(event, function() Stack:Request(false) end)
end

-- Pin, hide, collapse: the player's own actions.
ns.Bus:On("TrackingChanged", function() Stack:Request(false, true) end)

ns.Bus:On("QuestChanged", function(quest)
  local card = Stack.visible[quest.questID]
  if not card then
    return
  end
  local collapsed = ns.DB.char.collapsed[quest.questID] == true
  if card.ready == quest.readyForTurnIn and card.rowCount == ns.Card.RowCount(quest, collapsed) then
    card:UpdateInPlace(quest)
  end
  -- Otherwise (turned ready, an objective appeared) the QuestLogChanged that closes this batch
  -- lays it out, after combat.
end)

ns.Bus:On("ProfileChanged", function()
  if Stack.container then
    Stack:ApplyPosition()
    Stack:Request(false, true)
  end
end)
