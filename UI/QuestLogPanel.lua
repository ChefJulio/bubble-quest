local ADDON_NAME, ns = ...

-- A quest log list for other frames: BubbleMap's map window's drawer (BubbleQuestAPI.CreateQuestLogPanel),
-- like the list beside Blizzard's world map, and the core of the quest log window planned later (phase
-- 11), so built to be reused, not for one owner.
--
-- What it shows: every quest in the log, under its zone (as the tracker's sections: Zone:NameFor, the
-- player's zone first, then by name), each "[level] Title" in its difficulty colour with its objectives,
-- a pin checkbox (the tracker's pins), a search box (title, objectives or zone), and "12/40" (the log's
-- cap, C_QuestLog.GetMaxNumQuestsCanAccept). Zones collapse with their header (char.logCollapsed; open by
-- default); while searching every zone with a match is open.
--
-- Clicking a quest makes it the guide's quest (QuestView.ChooseGuide: the minimap's line and the world
-- map's) and calls the owner's onQuestClick with where it leads: the guide's point, its next objective or
-- its turn-in (review: "centre and guide").
--
-- Plain frames only (no secure ones), so it works in combat. Rebuilt a frame after what it shows changes,
-- only while shown; a hidden panel catches up when shown again.
--
-- Not yet (the full quest log, phase 11): description, rewards, abandon / share / link.

local PAD = 6
local INDENT = 12             -- quests under their header; objectives one more
local HEADER_HEIGHT = 20
local SEARCH_HEIGHT = 20
local CHECK_SIZE = 20
local ROW_GAP = 4             -- between quests
local SCROLL_STEP = 40
local MIN_WIDTH = 240
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local DONE = { 0.5, 0.5, 0.5 }
local OPEN = { 0.85, 0.85, 0.85 }
local READY = { 0.3, 0.85, 0.3 }
local FAILED = { 0.9, 0.25, 0.25 }

local DESCRIPTION_LINES = 4  -- the description's lines before "more"
local REWARD_SIZE = 24
local ACTION_HEIGHT = 20

local QuestLogPanel = {
  MIN_WIDTH = MIN_WIDTH,
  expanded = nil,   -- the quest whose entry is open (one at a time, in every panel)
  fullText = {},    -- [questID] = true: its whole description shown ("more")
}
ns.QuestLogPanel = QuestLogPanel

-- Abandoning, confirmed in our own dialog (not Blizzard's ABANDON_QUEST: ours runs our code only). The
-- game abandons the selected quest, as Blizzard's own (GameDialogDefs.lua:837).
-- Blizzard's own strings (GlobalStrings; not in the annotations lint reads), English if missing.
StaticPopupDialogs["BUBBLEQUEST_ABANDON"] = {
  text = rawget(_G, "ABANDON_QUEST_CONFIRM") or "Abandon \"%s\"?",
  button1 = rawget(_G, "YES") or "Yes",
  button2 = rawget(_G, "NO") or "No",
  OnAccept = function(_, questID)
    C_QuestLog.SetSelectedQuest(questID)
    C_QuestLog.SetAbandonQuest()
    C_QuestLog.AbandonQuest()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local panels = {}

-- Data ---------------------------------------------------------------------------------------------

local function titleText(quest)
  local color = GetQuestDifficultyColor(quest.level or 0)
  return ("|cff%02x%02x%02x[%d]|r %s"):format(color.r * 255, color.g * 255, color.b * 255, quest.level or 0,
    quest.title or "?")
end

local function objectiveText(objective)
  if objective.required and objective.required > 0 and objective.fulfilled then
    return ("- %d/%d %s"):format(objective.fulfilled, objective.required, ns.QuestLog.ObjectiveName(objective))
  end
  return "- " .. ns.QuestLog.StripProgress(objective.text or "")
end

-- The quest's section: the player's zone for quests the tracker counts as here (some have no marker,
-- only an area or a log header naming it), else the tracker's zone heading.
local function zoneOf(quest)
  if ns.Zone.name and ns.Zone:IsInZone(quest) then
    return ns.Zone.name
  end
  return ns.Zone:NameFor(quest)
end

local function matches(quest, zone, needle)
  if not needle then
    return true
  end
  local function has(text)
    return text ~= nil and text:lower():find(needle, 1, true) ~= nil
  end
  if has(quest.title) or has(zone) then
    return true
  end
  for _, objective in ipairs(quest.objectives or {}) do
    if has(objective.text) then
      return true
    end
  end
  return false
end

-- { { zone, quests = { quest... } }... }: the player's zone first, then by name; quests by level, title.
local function groups(needle)
  local byZone, list = {}, {}
  for _, quest in pairs(ns.QuestLog.quests) do
    local zone = zoneOf(quest)
    if matches(quest, zone, needle) then
      local group = byZone[zone]
      if not group then
        group = { zone = zone, quests = {} }
        byZone[zone] = group
        list[#list + 1] = group
      end
      group.quests[#group.quests + 1] = quest
    end
  end
  local here = ns.Zone.name
  table.sort(list, function(a, b)
    if (a.zone == here) ~= (b.zone == here) then
      return a.zone == here
    end
    return a.zone < b.zone
  end)
  for _, group in ipairs(list) do
    table.sort(group.quests, function(a, b)
      if (a.level or 0) ~= (b.level or 0) then
        return (a.level or 0) < (b.level or 0)
      end
      return (a.title or "") < (b.title or "")
    end)
  end
  return list
end

local function logCount()
  local count = 0
  for _ in pairs(ns.QuestLog.quests) do
    count = count + 1
  end
  return count, C_QuestLog.GetMaxNumQuestsCanAccept()
end

-- A panel -----------------------------------------------------------------------------------------

local Panel = {}
Panel.__index = Panel

local function onWheel(scroll, delta)
  local range = scroll:GetVerticalScrollRange()
  local offset = math.max(0, math.min(range, scroll:GetVerticalScroll() - delta * SCROLL_STEP))
  scroll:SetVerticalScroll(offset)
end

---A quest log list filling `parent`.
---@param parent Frame
---@param options table? { onQuestClick = function(questID, target) } (target: { map, north, west } or nil)
---@return table
function QuestLogPanel.New(parent, options)
  local panel = setmetatable({ options = options or {},
    used = { headers = 0, quests = 0, lines = 0, links = 0, rewards = 0, actions = 0 },
    pools = { headers = {}, quests = {}, lines = {}, links = {}, rewards = {}, actions = {} }, dirty = true }, Panel)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetAllPoints(parent)
  panel.frame = frame

  local count = frame:CreateFontString(nil, "OVERLAY", "BubbleQuestSmallFont")
  count:SetPoint("TOPRIGHT", -PAD, -PAD - 4)
  panel.count = count

  local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
  search:SetHeight(SEARCH_HEIGHT)
  search:SetPoint("TOPLEFT", PAD + 4, -PAD)
  search:SetPoint("RIGHT", count, "LEFT", -PAD, 0)
  search.Instructions:SetText("Search quest log")
  -- After the template's own handler (its clear button, its instructions).
  search:HookScript("OnTextChanged", function() panel:MarkDirty() end)
  panel.search = search

  local scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", PAD, -PAD - SEARCH_HEIGHT - PAD)
  scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", onWheel)
  panel.scroll = scroll

  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(1, 1)
  scroll:SetScrollChild(body)
  panel.body = body

  panel.thumb = frame:CreateTexture(nil, "OVERLAY")
  panel.thumb:SetWidth(2)
  panel.thumb:SetColorTexture(1, 1, 1, 0.3)
  scroll:SetScript("OnVerticalScroll", function() panel:placeThumb() end)

  panel.empty = body:CreateFontString(nil, "OVERLAY", "BubbleQuestSmallFont")
  panel.empty:SetPoint("TOPLEFT", 0, -PAD)
  panel.empty:SetTextColor(DONE[1], DONE[2], DONE[3])

  frame:SetScript("OnShow", function() panel:MarkDirty() end)
  frame:SetScript("OnSizeChanged", function() panel:MarkDirty() end)
  panels[#panels + 1] = panel
  panel:MarkDirty()  -- created shown: no OnShow comes
  return panel
end

function Panel:MarkDirty()
  self.dirty = true
  if self.pending or not self.frame:IsVisible() then
    return
  end
  self.pending = true
  C_Timer.After(0, function()
    self.pending = false
    if self.dirty and self.frame:IsVisible() then
      self:Refresh()
    end
  end)
end

function Panel:placeThumb()
  local scroll, thumb = self.scroll, self.thumb
  local range = scroll:GetVerticalScrollRange()
  local height = scroll:GetHeight()
  if range <= 0 or height <= 0 then
    thumb:Hide()
    return
  end
  local share = height / (height + range)
  local size = math.max(16, height * share)
  thumb:SetHeight(size)
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", PAD - 2, -(height - size) * scroll:GetVerticalScroll() / range)
  thumb:Show()
end

function Panel:acquire(kind, make)
  local used, pool = self.used, self.pools[kind]
  used[kind] = used[kind] + 1
  local item = pool[used[kind]]
  if not item then
    item = make()
    pool[used[kind]] = item
  end
  item:Show()
  return item
end

function Panel:makeHeader()
  local header = CreateFrame("Button", nil, self.body)
  header:SetHeight(HEADER_HEIGHT)
  local band = header:CreateTexture(nil, "BACKGROUND")
  band:SetAllPoints()
  band:SetColorTexture(0, 0, 0, 0.35)
  local highlight = header:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.06)
  header.toggle = header:CreateTexture(nil, "ARTWORK")
  header.toggle:SetSize(14, 14)
  header.toggle:SetPoint("RIGHT", -4, 0)
  header.text = header:CreateFontString(nil, "ARTWORK", "BubbleQuestHeaderFont")
  header.text:SetPoint("LEFT", 6, 0)
  header.text:SetPoint("RIGHT", header.toggle, "LEFT", -4, 0)
  header.text:SetJustifyH("LEFT")
  header.text:SetWordWrap(false)
  header:SetScript("OnClick", function(self)
    local collapsed = ns.DB.char.logCollapsed
    collapsed[self.zone] = not collapsed[self.zone] or nil
    QuestLogPanel.RefreshAll()
  end)
  return header
end

function Panel:makeQuest()
  local row = CreateFrame("Button", nil, self.body)
  row:RegisterForClicks("LeftButtonUp")
  row.selected = row:CreateTexture(nil, "BACKGROUND")
  row.selected:SetAllPoints()
  row.selected:SetColorTexture(1, 0.82, 0, 0.12)
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.06)
  row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.check:SetSize(CHECK_SIZE, CHECK_SIZE)
  row.check:SetPoint("TOPRIGHT", 0, 1)
  row.check:SetScript("OnClick", function(check)
    ns.Tracking:SetPinned(row.questID, check:GetChecked())
  end)
  row.check:SetScript("OnEnter", function(check)
    if ns.Tooltips:Take(check, "ANCHOR_RIGHT") then
      GameTooltip:SetText(check:GetChecked() and "Pinned in the tracker" or "Pin in the tracker", 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.title = row:CreateFontString(nil, "ARTWORK", "BubbleQuestLineFont")
  row.title:SetPoint("TOPLEFT", INDENT, 0)
  row.title:SetPoint("RIGHT", row.check, "LEFT", -2, 0)
  row.title:SetJustifyH("LEFT")
  -- A click opens the quest's entry under it (and closes the one open), centres and guides; on the open
  -- one it closes it.
  row:SetScript("OnClick", function(self)
    if QuestLogPanel.expanded == self.questID then
      QuestLogPanel.expanded = nil
      QuestLogPanel.RefreshAll()
    else
      QuestLogPanel.expanded = self.questID
      QuestLogPanel.Choose(self.questID, self.panel)
    end
  end)
  -- Hovered, the quest previews as a hovered card does: its guide line, its areas lit (MapAreas'
  -- card hover, which the world map and quest views read). The map doesn't move.
  local function hover() ns.MapAreas:SetCardHover(row.questID) end
  local function leave()
    if ns.MapAreas.cardHover == row.questID then
      ns.MapAreas:SetCardHover(nil)
    end
  end
  row:SetScript("OnEnter", hover)
  row:SetScript("OnLeave", leave)
  row.check:HookScript("OnEnter", hover)
  row.check:HookScript("OnLeave", leave)
  row:SetScript("OnHide", leave)
  return row
end

function Panel:makeLine()
  local line = self.body:CreateFontString(nil, "ARTWORK", "BubbleQuestSmallFont")
  line:SetJustifyH("LEFT")
  return line
end

-- "more" / "less" under a description.
function Panel:makeLink()
  local link = CreateFrame("Button", nil, self.body)
  link.text = link:CreateFontString(nil, "ARTWORK", "BubbleQuestSmallFont")
  link.text:SetPoint("LEFT")
  link.text:SetTextColor(0.4, 0.7, 1)
  link:SetScript("OnClick", function(self)
    QuestLogPanel.fullText[self.questID] = not QuestLogPanel.fullText[self.questID] or nil
    QuestLogPanel.RefreshAll()
  end)
  return link
end

-- GameTooltip:SetQuestLogItem(type, index, questID): Forever's takes the quest (GameTooltip.lua:845,
-- AM_QuestDialog.lua:281); the annotations lint reads still list the older two-argument form.
local setQuestLogItem = GameTooltip.SetQuestLogItem --[[@as fun(tooltip, kind: string, index: number, questID: number)]]

-- A reward item: its icon and count; its tooltip on hover, Shift-click links it.
function Panel:makeReward()
  local button = CreateFrame("Button", nil, self.body)
  button:SetSize(REWARD_SIZE, REWARD_SIZE)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  button.count:SetPoint("BOTTOMRIGHT", -1, 1)
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetScript("OnEnter", function(reward)
    if ns.Tooltips:Take(reward, "ANCHOR_RIGHT") then
      setQuestLogItem(GameTooltip, reward.kind, reward.index, reward.questID)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Shift-click: the item's link into chat (not HandleModifiedItemClick: it reaches restricted calls).
  button:SetScript("OnClick", function(reward)
    local link = IsModifiedClick("CHATLINK") and GetQuestLogItemLink(reward.kind, reward.index, reward.questID)
    if link then
      ChatFrameUtil.InsertLink(link)
    end
  end)
  return button
end

function Panel:makeAction()
  local button = CreateFrame("Button", nil, self.body, "UIPanelButtonTemplate")
  button:SetHeight(ACTION_HEIGHT)
  button:SetScript("OnClick", function(self) self.action(self.questID, self) end)
  return button
end

-- Link: a menu of where to (review: "link opens a menu that the player chooses the channel, and it
-- prints there by itself"). The groups and guild you're in, your numbered channels (GetChannelList:
-- id, name, disabled, ...), and "Into chat box..." (the chat box being typed in, else a new one: as
-- ChatFrameUtil.LinkItem does) to add your own words. Sending is a click, which say and channels need;
-- in chat lockdown (restricted content) the game refuses it, so those wait greyed out.
-- Party categories (Blizzard globals, not in the annotations lint reads): home group, instance group.
local HOME = rawget(_G, "LE_PARTY_CATEGORY_HOME") or 1
local INSTANCE = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE") or 2
local GROUP_CHATS = {
  { "Say", "SAY", function() return true end },
  { "Party", "PARTY", function() return IsInGroup(HOME) end },
  { "Raid", "RAID", function() return IsInRaid(HOME) end },
  { "Instance", "INSTANCE_CHAT", function() return IsInGroup(INSTANCE) end },
  { "Guild", "GUILD", function() return IsInGuild() end },
}

local function sendLink(link, chatType, target)
  if C_ChatInfo.InChatMessagingLockdown() then
    return
  end
  -- apiguard: allow a quest link and constant chat types from a click, never secret; not sent in lockdown
  C_ChatInfo.SendChatMessage(link, chatType, nil, target)
end

---@param owner table the Link button
---@param questID number
function QuestLogPanel.OpenLinkMenu(owner, questID)
  local link = GetQuestLink(questID)
  if not link then
    return
  end
  local locked = C_ChatInfo.InChatMessagingLockdown()
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(locked and "Link (chat is locked here)" or "Link to")
    for _, chat in ipairs(GROUP_CHATS) do
      if chat[3]() then
        local item = root:CreateButton(chat[1], function() sendLink(link, chat[2]) end)
        item:SetEnabled(not locked)
      end
    end
    local channels = { GetChannelList() }
    if #channels > 0 then
      root:CreateDivider()
      for i = 1, #channels, 3 do
        local id, name, disabled = channels[i], channels[i + 1], channels[i + 2]
        local item = root:CreateButton(("%d. %s"):format(id, name), function() sendLink(link, "CHANNEL", id) end)
        item:SetEnabled(not (locked or disabled))
      end
    end
    root:CreateDivider()
    root:CreateButton("Into chat box...", function()
      if ChatFrameUtil.GetActiveWindow() then
        ChatFrameUtil.InsertLink(link)
      else
        ChatFrameUtil.OpenChat(link)
      end
    end)
  end)
end

local ACTIONS = {
  {
    label = "Share",
    enabled = function(questID) return IsInGroup() and C_QuestLog.IsPushableQuest(questID) end,
    action = function(questID) ns.Party:Push(questID) end,  -- queued in combat (Quests/Party.lua)
  },
  {
    label = "Link",
    action = function(questID, button) QuestLogPanel.OpenLinkMenu(button, questID) end,
  },
  {
    label = "Abandon",
    action = function(questID)
      local quest = ns.QuestLog:Get(questID)
      StaticPopup_Show("BUBBLEQUEST_ABANDON", quest and quest.title or "?", nil, questID)
    end,
  },
}

-- The open quest's entry, under its objectives: the game's summary and description (the description
-- cut at DESCRIPTION_LINES with "more"), its rewards, and Share / Link / Abandon. Returns the new y.
function Panel:placeEntry(quest, y, width)
  local questID = quest.questID
  local left = 2 * INDENT
  local inner = width - left - PAD
  local function text(value, color, maxLines)
    local fs = self:acquire("lines", function() return self:makeLine() end)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", left, -y)
    fs:SetWidth(inner)
    fs:SetMaxLines(maxLines or 0)
    fs:SetText(value)
    fs:SetTextColor(color[1], color[2], color[3])
    y = y + fs:GetStringHeight() + 3
    return fs
  end
  y = y + 3
  -- By its log index: no selection needed (as GameTooltip.lua:709 reads it).
  local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
  local description, summary
  if logIndex then
    description, summary = GetQuestLogQuestText(logIndex)
  end
  if summary and summary ~= "" then
    text(summary, OPEN)
  end
  if description and description ~= "" then
    local full = QuestLogPanel.fullText[questID]
    local fs = text(description, DONE, not full and DESCRIPTION_LINES or nil)
    if full or fs:IsTruncated() then
      local link = self:acquire("links", function() return self:makeLink() end)
      link.questID = questID
      link.text:SetText(full and "less" or "more")
      link:SetSize(link.text:GetStringWidth() + 4, link.text:GetStringHeight() + 2)
      link:ClearAllPoints()
      link:SetPoint("TOPLEFT", left, -y)
      y = y + link:GetHeight() + 3
    end
  end
  -- Rewards: experience and money on one line, then the items (all of them, then the choices).
  local parts = {}
  local xp = GetQuestLogRewardXP(questID)
  if xp and xp > 0 then
    parts[#parts + 1] = BreakUpLargeNumbers(xp) .. " XP"
  end
  local money = GetQuestLogRewardMoney(questID)
  if money and money > 0 then
    parts[#parts + 1] = GetMoneyString(money)
  end
  if #parts > 0 then
    text("Rewards: " .. table.concat(parts, "   "), OPEN)
  end
  local function items(kind, count, info, label)
    if count == 0 then
      return
    end
    if label then
      text(label, DONE)
    end
    local x = left
    for index = 1, count do
      local _, texture, number = info(index, questID)
      if x + REWARD_SIZE > left + inner then
        x, y = left, y + REWARD_SIZE + 3
      end
      local button = self:acquire("rewards", function() return self:makeReward() end)
      button.kind, button.index, button.questID = kind, index, questID
      button.icon:SetTexture(texture)
      button.count:SetText(number and number > 1 and number or "")
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", x, -y)
      x = x + REWARD_SIZE + 3
    end
    y = y + REWARD_SIZE + 4
  end
  items("reward", GetNumQuestLogRewards(questID) or 0, GetQuestLogRewardInfo, nil)
  items("choice", GetNumQuestLogChoices(questID) or 0, GetQuestLogChoiceInfo, "Choose one:")
  -- The actions, side by side.
  local gap = 4
  local buttonWidth = (inner - gap * (#ACTIONS - 1)) / #ACTIONS
  for i, def in ipairs(ACTIONS) do
    local button = self:acquire("actions", function() return self:makeAction() end)
    button.questID, button.action = questID, def.action
    button:SetText(def.label)
    button:SetWidth(buttonWidth)
    button:SetEnabled(not def.enabled or def.enabled(questID) == true)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", left + (i - 1) * (buttonWidth + gap), -y)
  end
  return y + ACTION_HEIGHT + 4
end

function Panel:hideUnused()
  for kind, pool in pairs(self.pools) do
    for i = self.used[kind] + 1, #pool do
      pool[i]:Hide()
    end
    self.used[kind] = 0
  end
end

---Rebuild the list now (it also rebuilds itself when what it shows changes).
function Panel:Refresh()
  self.dirty = false
  local count, max = logCount()
  self.count:SetText(("%d/%d"):format(count, max or 0))
  if max and count >= max then
    self.count:SetTextColor(FAILED[1], FAILED[2], FAILED[3])
  else
    self.count:SetTextColor(OPEN[1], OPEN[2], OPEN[3])
  end
  local text = self.search:GetText()
  local needle = text and text ~= "" and text:lower() or nil
  local width = self.scroll:GetWidth()
  if width <= 0 then
    return
  end
  self.body:SetWidth(width)
  local collapsed = ns.DB.char.logCollapsed
  local pins = ns.DB.char.pins
  local chosen = ns.QuestView.Chosen()
  local y = 0
  local list = groups(needle)
  for index, group in ipairs(list) do
    if index > 1 then
      y = y + ROW_GAP
    end
    local header = self:acquire("headers", function() return self:makeHeader() end)
    header.zone = group.zone
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 0, -y)
    header:SetPoint("RIGHT", self.body, "RIGHT")
    header.text:SetText(("%s |cff999999(%d)|r"):format(group.zone, #group.quests))
    local open = needle ~= nil or not collapsed[group.zone]
    header.toggle:SetTexture(open and MINUS or PLUS)
    y = y + HEADER_HEIGHT + ROW_GAP
    if open then
      for _, quest in ipairs(group.quests) do
        y = self:placeQuest(quest, y, width, pins, chosen) + ROW_GAP
      end
    end
  end
  self.empty:SetShown(#list == 0)
  self.empty:SetText(needle and "No quests match." or "No quests in your log.")
  if #list == 0 then
    y = HEADER_HEIGHT
  end
  self:hideUnused()
  self.body:SetHeight(math.max(1, y))
  -- A shorter list (a zone closed) can leave the scroll past its end.
  local range = self.scroll:GetVerticalScrollRange()
  if self.scroll:GetVerticalScroll() > range then
    self.scroll:SetVerticalScroll(range)
  end
  self:placeThumb()
end

-- One quest: its row (title, pin) and its objective lines under it. Returns the new y.
function Panel:placeQuest(quest, y, width, pins, chosen)
  local row = self:acquire("quests", function() return self:makeQuest() end)
  row.panel, row.questID = self, quest.questID
  row.title:SetText(titleText(quest))
  row.check:SetChecked(pins[quest.questID] ~= nil)
  row.selected:SetShown(chosen == quest.questID)
  local top = y
  row.title:SetWidth(width - INDENT - CHECK_SIZE - 2)
  y = y + math.max(row.title:GetStringHeight(), CHECK_SIZE - 4) + 1
  local function line(text, color)
    local fs = self:acquire("lines", function() return self:makeLine() end)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 2 * INDENT, -y)
    fs:SetWidth(width - 2 * INDENT - CHECK_SIZE)
    fs:SetMaxLines(0)  -- pooled: may have been a cut description
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3])
    y = y + fs:GetStringHeight() + 1
  end
  if quest.isFailed then
    line("- Failed", FAILED)
  elseif quest.readyForTurnIn or quest.isComplete then
    line("- Ready to turn in", READY)
  else
    for _, objective in ipairs(quest.objectives or {}) do
      line(objectiveText(objective), objective.finished and DONE or OPEN)
    end
  end
  -- The row covers its objectives too: click anywhere on the quest.
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", 0, -top)
  row:SetPoint("RIGHT", self.body, "RIGHT")
  row:SetHeight(y - top)
  -- Its entry, when open: under the row, not part of it (its own buttons take the clicks).
  if QuestLogPanel.expanded == quest.questID then
    y = self:placeEntry(quest, y, width)
  end
  return y
end

function Panel:Show()
  self.frame:Show()
end

function Panel:Hide()
  self.frame:Hide()
end

-- Every panel ------------------------------------------------------------------------------------

function QuestLogPanel.RefreshAll()
  for _, panel in ipairs(panels) do
    panel:MarkDirty()
  end
end

---A click on a quest: it becomes the guide's quest, and the panel's owner hears where it leads.
---@param questID number
---@param panel table?
function QuestLogPanel.Choose(questID, panel)
  ns.QuestView.ChooseGuide(questID)
  QuestLogPanel.RefreshAll()
  local onClick = panel and panel.options.onQuestClick
  if onClick then
    local quest = ns.QuestLog:Get(questID)
    local point = quest and ns.Navigation:GuidePoint(quest)
    onClick(questID, point and { map = point.map, north = point.x, west = point.y } or nil)
  end
end

for _, event in ipairs({ "QuestLogChanged", "TrackingChanged", "TrackingResortWanted", "FontsChanged",
    "ProfileChanged" }) do
  ns.Bus:On(event, QuestLogPanel.RefreshAll)
end
