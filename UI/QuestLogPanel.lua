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

local QuestLogPanel = {
  MIN_WIDTH = MIN_WIDTH,
}
ns.QuestLogPanel = QuestLogPanel

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
  local panel = setmetatable({ options = options or {}, used = { headers = 0, quests = 0, lines = 0 },
    pools = { headers = {}, quests = {}, lines = {} }, dirty = true }, Panel)
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
  row:SetScript("OnClick", function(self) QuestLogPanel.Choose(self.questID, self.panel) end)
  return row
end

function Panel:makeLine()
  local line = self.body:CreateFontString(nil, "ARTWORK", "BubbleQuestSmallFont")
  line:SetJustifyH("LEFT")
  return line
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
