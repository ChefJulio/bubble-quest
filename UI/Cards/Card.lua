local ADDON_NAME, ns = ...

-- One quest card: a title line ([level] Title (tag)   arrow distance  [-]) and one row per
-- objective, or a single turn-in line. Cards are pooled by the stack; SetQuest fills one in and
-- returns its height. Plain frames only (no secure templates), so updating them in combat is safe.
--
-- Arrow (phase 5): Blizzard's navigation arrow, rotated to the target; inside the objective's area
-- it becomes a green diamond (a different shape, not just colour) and that objective's row lights up.

local WIDTH = 250
local TITLE_HEIGHT = 16
local ROW_INDENT = 14
local COUNTER_WIDTH = 44
local ROW_GAP = 1
local TOGGLE_WIDTH = 20  -- the collapse button at the right of the title line
local HINT_COLOR = { 0.55, 0.8, 1 }  -- soft blue "Tip:" lines
local BAR_HEIGHT = 4     -- progress bar under the card
local MAX_SEGMENTS = 20  -- more steps than this and segments get too thin to read: smooth bar
local BAR_GAP = 3
local BAR_WIDTH = WIDTH - ROW_INDENT
local ARROW_SIZE = 16
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local IN_AREA_ATLAS = "Navigation-Tracked-Icon"

local Card = {}
Card.__index = Card
ns.Card = Card
Card.WIDTH = WIDTH

-- Arrow art (setting cards.arrowStyle). Every style points up unrotated; the angle maths relies on
-- it. Blizzard's own arrows all read as chevrons or triangles at card size (compared in game), so
-- the default is our own drawing (tools/make_arrows.py -> Media/Arrows). /qm arrows previews them.
local function media(name)
  return ("Interface\\AddOns\\%s\\Media\\Arrows\\%s"):format(ADDON_NAME, name)
end
Card.ARROW_STYLES = {
  { key = "classic", label = "Arrow", file = media("classic"), tintable = true },
  { key = "dart", label = "Dart", file = media("dart"), tintable = true },
  { key = "thin", label = "Thin arrow", file = media("thin"), tintable = true },
  { key = "minimap", label = "Minimap arrow", file = "Interface\\Minimap\\MinimapArrow" },
  { key = "chevron", label = "Chevron (Blizzard)", atlas = "NPE_ArrowUp" },
}

---Put arrow style `key` on a texture (unknown keys fall back to the first style).
---@return boolean tintable our own (white-filled) art takes colour; Blizzard's art keeps its own
function Card.ApplyArrowStyle(texture, key)
  local style = Card.ARROW_STYLES[1]
  for _, candidate in ipairs(Card.ARROW_STYLES) do
    if candidate.key == key then
      style = candidate
    end
  end
  texture:SetVertexColor(1, 1, 1)
  if style.atlas then
    texture:SetAtlas(style.atlas)
  else
    -- TRILINEAR: mipmapped, so the 128px art stays smooth shrunk to card size (Blizzard loads its
    -- scaled map tiles this way, Blizzard_MapCanvasDetailLayer.lua:68); plain sampling looked jagged
    -- when the arrow rotated.
    texture:SetTexture(style.file, nil, nil, "TRILINEAR")
  end
  return style.tintable == true
end

---Settings for a texture that gets rotated: pixel-grid snapping (on by default, crisp for still
---art) makes rotated art jitter and stair-step; Blizzard turns it off the same way for rotating art.
function Card.PrepareRotatingTexture(texture)
  texture:SetSnapToPixelGrid(false)
  texture:SetTexelSnappingBias(0)
end

-- Arrow colour. By distance (setting, default on): green close, through yellow and orange, to red far;
-- a target in another zone counts as far. Always alongside the distance text, never the only cue.
local GOLD = { 1, 0.82, 0 }
local DISTANCE_COLORS = {  -- { yards, r, g, b }, blended between stops
  { 0, 0.3, 1, 0.3 },
  { 100, 1, 0.9, 0.2 },
  { 400, 1, 0.55, 0.1 },
  { 1000, 1, 0.25, 0.2 },
}
local function distanceColor(yards)
  if not yards then
    local far = DISTANCE_COLORS[#DISTANCE_COLORS]
    return far[2], far[3], far[4]
  end
  for i = 2, #DISTANCE_COLORS do
    local a, b = DISTANCE_COLORS[i - 1], DISTANCE_COLORS[i]
    if yards <= b[1] then
      local t = (yards - a[1]) / (b[1] - a[1])
      return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
    end
  end
  local far = DISTANCE_COLORS[#DISTANCE_COLORS]
  return far[2], far[3], far[4]
end

local function createRow(card)
  local row = CreateFrame("Frame", nil, card.frame)
  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetPoint("TOPLEFT", -2, 1)
  row.highlight:SetPoint("BOTTOMRIGHT", 2, -1)
  row.highlight:SetColorTexture(0.2, 1, 0.2, 0.15)
  row.highlight:Hide()
  row.check = row:CreateTexture(nil, "ARTWORK")
  row.check:SetTexture(CHECK_TEXTURE)
  row.check:SetSize(12, 12)
  row.check:SetPoint("TOPLEFT", 0, 0)
  row.text = row:CreateFontString(nil, "ARTWORK", "QuestmarkerLineFont")
  row.text:SetPoint("TOPLEFT", ROW_INDENT, 0)
  row.text:SetWidth(WIDTH - ROW_INDENT - COUNTER_WIDTH)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(true)
  row.counter = row:CreateFontString(nil, "ARTWORK", "QuestmarkerLineFont")
  row.counter:SetPoint("TOPRIGHT", 0, 0)
  row.counter:SetWidth(COUNTER_WIDTH)
  row.counter:SetJustifyH("RIGHT")
  return row
end

---@param onToggleCollapse fun(questID: number)
---@param onMenu fun(card: table, questID: number) right-click
---@param onClick fun(questID: number) left-click
function Card.Create(parent, onToggleCollapse, onMenu, onClick)
  local self = setmetatable({ rows = {} }, Card)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(WIDTH)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function()
    local quest = self.questID and ns.QuestLog:Get(self.questID)
    if quest then
      ns.QuestTooltip:Show(frame, quest)
    end
  end)
  frame:SetScript("OnLeave", function()
    ns.QuestTooltip:Hide()
  end)
  frame:SetScript("OnMouseUp", function(_, button)
    if not self.questID or not frame:IsMouseOver() then
      return
    end
    if button == "RightButton" then
      onMenu(self, self.questID)
    elseif button == "LeftButton" then
      onClick(self.questID)
    end
  end)
  self.frame = frame

  self.title = frame:CreateFontString(nil, "ARTWORK", "QuestmarkerHeaderFont")
  self.title:SetPoint("TOPLEFT", 0, 0)
  self.title:SetWidth(WIDTH - TOGGLE_WIDTH)  -- narrowed by SetNavigation while an arrow shows
  self.title:SetJustifyH("LEFT")
  self.title:SetWordWrap(false)

  -- Arrow / in-area diamond and the distance or zone name, right-aligned before the toggle.
  self.navText = frame:CreateFontString(nil, "ARTWORK", "QuestmarkerSmallHighlightFont")
  self.navText:SetPoint("TOPRIGHT", -TOGGLE_WIDTH, -2)
  self.navText:SetJustifyH("RIGHT")
  self.arrow = frame:CreateTexture(nil, "ARTWORK")
  self.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  Card.PrepareRotatingTexture(self.arrow)
  self.arrow:SetPoint("RIGHT", self.navText, "LEFT", -3, 0)
  self.arrow:Hide()
  self.inArea = frame:CreateTexture(nil, "ARTWORK")
  self.inArea:SetAtlas(IN_AREA_ATLAS)
  self.inArea:SetSize(ARROW_SIZE, ARROW_SIZE)
  self.inArea:SetPoint("RIGHT", self.navText, "LEFT", -3, 0)
  self.inArea:SetVertexColor(0.2, 1, 0.2)
  self.inArea:Hide()

  -- Progress bar: a dark track and a fill whose width is the progress.
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.12)
  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT")
  fill:SetHeight(BAR_HEIGHT)
  self.bar, self.barFill, self.barDividers = bar, fill, {}

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
-- The title line's parts follow the card settings ("Show: Name, Level"); the pin and zone always show.
local function titleText(quest, options)
  local show = ns.DB.profile.cards.show
  local parts = {}
  if options and options.pinned then
    parts[#parts + 1] = PIN_MARKUP
  end
  if show.level then
    local color = GetQuestDifficultyColor(quest.level or 0)
    parts[#parts + 1] = ("|cff%02x%02x%02x[%d]|r "):format(color.r * 255, color.g * 255, color.b * 255, quest.level or 0)
  end
  if show.name then
    parts[#parts + 1] = (quest.title or "?") .. (quest.tagName and (" |cff999999(" .. quest.tagName .. ")|r") or "")
  end
  if options and options.zone then
    parts[#parts + 1] = " |cff999999- " .. options.zone .. "|r"
  end
  return table.concat(parts)
end

-- Ready quests keep their finished objectives above the turn-in line (setting, default on: review,
-- "I lose track of which quest it was").
local function keepDone(quest)
  return quest.readyForTurnIn and ns.DB.profile.cards.keepDone and #quest.objectives > 0
end

-- How many rows the card shows for this quest; the stack compares it to decide whether a change
-- can be applied in place (same rows) or needs a re-layout.
function Card.RowCount(quest, collapsed)
  if collapsed then
    return 0
  end
  if quest.readyForTurnIn then
    return keepDone(quest) and #quest.objectives + 1 or 1
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
    row.highlight:Hide()
  end
  self.highlighted = nil
  local style = ns.DB.profile.cards.arrowStyle
  if style ~= self.arrowStyle then
    self.arrowTintable = Card.ApplyArrowStyle(self.arrow, style)
    self.arrowStyle = style
  end
  self:SetNavigation(nil)  -- the driver fills it in on its next tick

  local y = TITLE_HEIGHT + 2
  for i = 1, self.rowCount do
    local row = self.rows[i] or createRow(self)
    self.rows[i] = row
    if quest.readyForTurnIn and i == self.rowCount then
      -- The turn-in line: last, below any kept objectives.
      local turnIn = ns.ForeverData:TurnInName(quest.questID)
      setRow(row, turnIn and ("Turn in to " .. turnIn) or "Ready to turn in", nil, false)
      row.text:SetTextColor(0.2, 1, 0.2)
    else
      local objective = quest.objectives[i]
      local text, counter = ns.DoLine:For(objective, quest.questID)
      setRow(row, text, counter, objective.finished or quest.readyForTurnIn)
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -y)
    row:SetSize(WIDTH, row.text:GetStringHeight())
    row:Show()
    y = y + row.text:GetStringHeight() + ROW_GAP
  end

  -- Hint lines (phase 7): after the objectives, only for quests with a known tricky step; shown on
  -- ready cards too ("keep the item, you hand it in"), not on collapsed ones. Setting, default on.
  -- They come after the objective rows, so UpdateInPlace (objective rows only) never touches them.
  local hints = not collapsed and ns.DB.profile.cards.hints and ns.Hints:ForQuest(quest)
  for h, hint in ipairs(hints or {}) do
    local i = self.rowCount + h
    local row = self.rows[i] or createRow(self)
    self.rows[i] = row
    setRow(row, "Tip: " .. hint, nil, false)
    row.text:SetTextColor(HINT_COLOR[1], HINT_COLOR[2], HINT_COLOR[3])
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -y)
    row:SetSize(WIDTH, row.text:GetStringHeight())
    row:Show()
    y = y + row.text:GetStringHeight() + ROW_GAP
  end

  -- Progress bar under the card (setting, default on); shown on collapsed cards too, as a summary.
  local showBar = ns.DB.profile.cards.progressBar
  self.bar:SetShown(showBar)
  if showBar then
    y = y + BAR_GAP
    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", ROW_INDENT, -y)
    self:UpdateBar(quest)
    y = y + BAR_HEIGHT
  end

  self.frame:SetHeight(y)
  return y
end

---Show the arrow state from ns.Navigation:Compute (nil = nothing to show). Called 10 times a
---second, so it only touches what changed.
---@param nav table?
function Card:SetNavigation(nav)
  local text, arrow, inArea, highlight = "", false, false, nil
  if nav then
    if nav.inArea then
      inArea, text, highlight = true, "here", nav.objective
    else
      arrow = nav.angle ~= nil
      text = nav.zone or (nav.distance and ("%d yd"):format(nav.distance)) or ""
    end
  end
  -- Card settings: "Arrow" is the arrow and the in-area marker; "Distance" the text beside them.
  local show = ns.DB.profile.cards.show
  if not show.arrow then
    arrow, inArea = false, false
  end
  if not show.distance then
    text = ""
  end
  local icon = arrow or inArea
  if text ~= self.lastNavText or icon ~= self.lastNavIcon then
    self.navText:SetText(text)
    self.lastNavText, self.lastNavIcon = text, icon
    -- The title gets whatever the arrow text doesn't need ("721 yd" is short, a zone name isn't).
    local navWidth = (text ~= "" and self.navText:GetStringWidth() + 6 or 0) + (icon and ARROW_SIZE + 3 or 0)
    self.title:SetWidth(WIDTH - TOGGLE_WIDTH - navWidth)
  end
  self.arrow:SetShown(arrow)
  if arrow and nav then
    self.arrow:SetRotation(nav.angle)
    if self.arrowTintable then
      if ns.DB.profile.cards.arrowColorByDistance then
        self.arrow:SetVertexColor(distanceColor(not nav.zone and nav.distance or nil))
      else
        self.arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
      end
    end
  end
  self.inArea:SetShown(inArea)
  if highlight ~= self.highlighted then
    for i, row in ipairs(self.rows) do
      row.highlight:SetShown(i == highlight)
    end
    self.highlighted = highlight
  end
end

-- How far along a quest is, 0..1: the average over its objectives of each one's fraction (3/8 counts
-- 0.375; an objective without a counter counts 0 or 1). Ready to turn in is 1.
local function progressOf(quest)
  if quest.readyForTurnIn then
    return 1
  end
  local total, count = 0, 0
  for _, objective in ipairs(quest.objectives) do
    count = count + 1
    if objective.finished then
      total = total + 1
    elseif (objective.required or 0) > 0 then
      total = total + math.min(objective.fulfilled or 0, objective.required) / objective.required
    end
  end
  return count > 0 and total / count or 0
end

-- Whole-number progress: every objective has a count (7/10 kobolds, 3/8 + 1/12 ...), at most
-- MAX_SEGMENTS steps in total. Returns done, total; nil when the bar should stay smooth.
local function steps(quest)
  if quest.readyForTurnIn or #quest.objectives == 0 then
    return nil
  end
  local done, total = 0, 0
  for _, objective in ipairs(quest.objectives) do
    local required = objective.required or 0
    if required <= 0 then
      return nil
    end
    total = total + required
    done = done + math.min(objective.fulfilled or 0, required)
  end
  if total < 2 or total > MAX_SEGMENTS then
    return nil
  end
  return done, total
end

-- Thin dark gaps across the bar at each step boundary, so 7/10 reads as seven of ten segments.
function Card:SetSegments(total)
  local dividers = self.barDividers
  for i = 1, math.max(#dividers, (total or 1) - 1) do
    local divider = dividers[i]
    if total and i < total then
      if not divider then
        divider = self.bar:CreateTexture(nil, "OVERLAY")
        divider:SetColorTexture(0, 0, 0, 0.85)
        PixelUtil.SetWidth(divider, 1, 1)
        divider:SetHeight(BAR_HEIGHT)
        dividers[i] = divider
      end
      divider:ClearAllPoints()
      divider:SetPoint("TOPLEFT", self.bar, "TOPLEFT", BAR_WIDTH * i / total, 0)
      divider:Show()
    elseif divider then
      divider:Hide()
    end
  end
end

---@param quest table
function Card:UpdateBar(quest)
  if not self.bar:IsShown() then
    return
  end
  local done, total = steps(quest)
  local progress = done and done / total or progressOf(quest)
  self:SetSegments(total)
  self.barFill:SetWidth(math.max(1, BAR_WIDTH * progress))
  self.barFill:SetShown(progress > 0)
  if quest.readyForTurnIn then
    self.barFill:SetColorTexture(0.2, 0.85, 0.2, 0.9)
  else
    self.barFill:SetColorTexture(0.95, 0.75, 0.15, 0.9)
  end
end

---Update texts in place (same rows, same layout). Used for progress, including in combat.
---@param quest table
function Card:UpdateInPlace(quest)
  self:UpdateBar(quest)
  self.title:SetText(titleText(quest, self.options))
  if quest.readyForTurnIn and not keepDone(quest) then
    return
  end
  -- Objective rows (on a ready card, all but the last, the turn-in line).
  local objectiveRows = quest.readyForTurnIn and self.rowCount - 1 or self.rowCount
  for i = 1, objectiveRows do
    local objective = quest.objectives[i]
    if objective then
      local text, counter = ns.DoLine:For(objective, quest.questID)
      setRow(self.rows[i], text, counter, objective.finished or quest.readyForTurnIn)
    end
  end
end
