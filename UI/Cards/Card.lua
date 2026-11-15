local ADDON_NAME, ns = ...

-- One quest card: a title line ([level] Title (tag)   [-]) and one row per objective, or a single
-- "Ready to turn in" line. Cards are pooled by the stack; SetQuest fills one in and returns its
-- height. Plain frames only (no secure templates), so updating them in combat is safe.

local WIDTH = 250
local TITLE_HEIGHT = 16
local ROW_INDENT = 14
local COUNTER_WIDTH = 44
local ROW_GAP = 1
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"

local Card = {}
Card.__index = Card
ns.Card = Card
Card.WIDTH = WIDTH

local function createRow(card)
  local row = CreateFrame("Frame", nil, card.frame)
  row.check = row:CreateTexture(nil, "ARTWORK")
  row.check:SetTexture(CHECK_TEXTURE)
  row.check:SetSize(12, 12)
  row.check:SetPoint("TOPLEFT", 0, 0)
  row.text = row:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
  row.text:SetPoint("TOPLEFT", ROW_INDENT, 0)
  row.text:SetWidth(WIDTH - ROW_INDENT - COUNTER_WIDTH)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(true)
  row.counter = row:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
  row.counter:SetPoint("TOPRIGHT", 0, 0)
  row.counter:SetWidth(COUNTER_WIDTH)
  row.counter:SetJustifyH("RIGHT")
  return row
end

---@param onToggleCollapse fun(questID: number)
---@param onMenu fun(card: table, questID: number) right-click
function Card.Create(parent, onToggleCollapse, onMenu)
  local self = setmetatable({ rows = {} }, Card)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(WIDTH)
  frame:EnableMouse(true)
  frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and self.questID then
      onMenu(self, self.questID)
    end
  end)
  self.frame = frame

  self.title = frame:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
  self.title:SetPoint("TOPLEFT", 0, 0)
  self.title:SetWidth(WIDTH - 20)
  self.title:SetJustifyH("LEFT")
  self.title:SetWordWrap(false)

  local toggle = CreateFrame("Button", nil, frame)
  toggle:SetSize(16, TITLE_HEIGHT)
  toggle:SetPoint("TOPRIGHT", 0, 0)
  toggle.label = toggle:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  toggle.label:SetPoint("CENTER")
  toggle:SetScript("OnClick", function()
    if self.questID then
      onToggleCollapse(self.questID)
    end
  end)
  self.toggle = toggle
  return self
end

-- Pool interface (see UI/Pool.lua).
function Card:Show() self.frame:Show() end
function Card:Hide() self.frame:Hide() end
function Card:ClearAllPoints() self.frame:ClearAllPoints() end

local PIN_MARKUP = "|A:Waypoint-MapPin-Tracked:14:14|a "

---@param options table? { pinned = bool, zone = string? (shown for pinned quests elsewhere) }
local function titleText(quest, options)
  local color = GetQuestDifficultyColor(quest.level or 0)
  local level = ("|cff%02x%02x%02x[%d]|r"):format(color.r * 255, color.g * 255, color.b * 255, quest.level or 0)
  local tag = quest.tagName and (" |cff999999(" .. quest.tagName .. ")|r") or ""
  local pin = options and options.pinned and PIN_MARKUP or ""
  local zone = options and options.zone and (" |cff999999- " .. options.zone .. "|r") or ""
  return ("%s%s %s%s%s"):format(pin, level, quest.title or "?", tag, zone)
end

-- How many rows the card shows for this quest; the stack compares it to decide whether a change
-- can be applied in place (same rows) or needs a re-layout.
function Card.RowCount(quest, collapsed)
  if collapsed then
    return 0
  end
  if quest.readyForTurnIn then
    return 1
  end
  return #quest.objectives
end

local function setRow(row, text, counter, finished)
  row.text:SetText(text)
  row.counter:SetText(counter or "")
  row.check:SetShown(finished)
  local r, g, b = 0.8, 0.8, 0.8
  if finished then
    r, g, b = 0.5, 0.5, 0.5
  end
  row.text:SetTextColor(r, g, b)
  row.counter:SetTextColor(r, g, b)
end

---Fill the card. Returns its height (spacing between cards is the stack's job).
---@param quest table from ns.QuestLog
---@param collapsed boolean
---@param options table? see titleText
---@return number
function Card:SetQuest(quest, collapsed, options)
  self.questID = quest.questID
  self.options = options
  self.rowCount = Card.RowCount(quest, collapsed)
  self.title:SetText(titleText(quest, options))
  self.toggle.label:SetText(collapsed and "+" or "-")

  for _, row in ipairs(self.rows) do
    row:Hide()
  end

  local y = TITLE_HEIGHT + 2
  for i = 1, self.rowCount do
    local row = self.rows[i] or createRow(self)
    self.rows[i] = row
    if quest.readyForTurnIn then
      local turnIn = ns.ForeverData:TurnInName(quest.questID)
      setRow(row, turnIn and ("Turn in to " .. turnIn) or "Ready to turn in", nil, false)
      row.text:SetTextColor(0.2, 1, 0.2)
    else
      local objective = quest.objectives[i]
      local text, counter = ns.DoLine:For(objective, quest.questID)
      setRow(row, text, counter, objective.finished)
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -y)
    row:SetSize(WIDTH, row.text:GetStringHeight())
    row:Show()
    y = y + row.text:GetStringHeight() + ROW_GAP
  end

  self.frame:SetHeight(y)
  return y
end

---Update texts in place (same rows, same layout). Used for progress, including in combat.
---@param quest table
function Card:UpdateInPlace(quest)
  self.title:SetText(titleText(quest, self.options))
  if quest.readyForTurnIn then
    return
  end
  for i = 1, self.rowCount do
    local objective = quest.objectives[i]
    if objective then
      local text, counter = ns.DoLine:For(objective, quest.questID)
      setRow(self.rows[i], text, counter, objective.finished)
    end
  end
end
