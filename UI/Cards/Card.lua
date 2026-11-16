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
local ROW_NAV_WIDTH = 56   -- an objective row's own arrow and distance ("888 yd")
local ROW_ARROW_SIZE = 11
local ARROW_SIZE = 16
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local IN_AREA_ATLAS = "Navigation-Tracked-Icon"

local Card = {}
Card.__index = Card
ns.Card = Card
Card.WIDTH = WIDTH

---Set the card width (the tracker's resize grip: review). Locals are shared by every function here,
---so cards pick it up on their next SetQuest; the stack calls this before each layout.
---@param width number
function Card.SetWidth(width)
  WIDTH = width
  BAR_WIDTH = width - ROW_INDENT
  Card.WIDTH = width
end

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

-- Progress bars: a dark track and a fill whose width is the progress; segment marks when the progress
-- is a small count. One under the card (the quest), or one under each objective (quests with two or
-- more objectives: review, "a bar per objective, not grouped together").

local function createBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.12)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetHeight(BAR_HEIGHT)
  bar.dividers = {}
  return bar
end

-- Thin dark gaps across the bar at each step boundary, so 7/10 reads as seven of ten segments.
local function setSegments(bar, total)
  local dividers = bar.dividers
  for i = 1, math.max(#dividers, (total or 1) - 1) do
    local divider = dividers[i]
    if total and i < total then
      if not divider then
        divider = bar:CreateTexture(nil, "OVERLAY")
        divider:SetColorTexture(0, 0, 0, 0.85)
        PixelUtil.SetWidth(divider, 1, 1)
        divider:SetHeight(BAR_HEIGHT)
        dividers[i] = divider
      end
      divider:ClearAllPoints()
      divider:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_WIDTH * i / total, 0)
      divider:Show()
    elseif divider then
      divider:Hide()
    end
  end
end

---@param fraction number 0..1
---@param segments number? steps to mark, nil for a smooth bar
---@param complete boolean green (done) instead of gold
local function setBar(bar, fraction, segments, complete)
  bar:SetWidth(BAR_WIDTH)  -- the card width can change (resize grip)
  setSegments(bar, segments)
  bar.fill:SetWidth(math.max(1, BAR_WIDTH * fraction))
  bar.fill:SetShown(fraction > 0)
  if complete then
    bar.fill:SetColorTexture(0.2, 0.85, 0.2, 0.9)
  else
    bar.fill:SetColorTexture(0.95, 0.75, 0.15, 0.9)
  end
end

-- One objective's bar: its own count (segmented when 2..MAX_SEGMENTS), or full/empty without one.
local function setObjectiveBar(bar, objective)
  local required = objective.required or 0
  if required > 0 then
    local done = math.min(objective.fulfilled or 0, required)
    local segments = required >= 2 and required <= MAX_SEGMENTS and required or nil
    setBar(bar, done / required, segments, objective.finished or done >= required)
  else
    setBar(bar, objective.finished and 1 or 0, nil, objective.finished)
  end
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
  -- Each unfinished objective of a quest with several gets its own arrow and distance, left of the
  -- counter (review: "all separate objectives to have arrow/dist"; their areas can be far apart).
  row.navText = row:CreateFontString(nil, "ARTWORK", "QuestmarkerSmallHighlightFont")
  row.navText:SetPoint("TOPRIGHT", -COUNTER_WIDTH, -1)
  row.navText:SetJustifyH("RIGHT")
  row.navText:SetWordWrap(false)
  row.navArrow = row:CreateTexture(nil, "ARTWORK")
  row.navArrow:SetSize(ROW_ARROW_SIZE, ROW_ARROW_SIZE)
  row.navArrow:SetPoint("RIGHT", row.navText, "LEFT", -2, 0)  -- right next to the text, whatever its length
  Card.PrepareRotatingTexture(row.navArrow)
  row.navArrow:Hide()
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

  -- "+2": party members who don't have this quest (review); click shares it. Placed left of the arrow
  -- and distance by SetNavigation, which fits the title around both.
  local party = CreateFrame("Button", nil, frame)
  party:SetHeight(TITLE_HEIGHT)
  party.label = party:CreateFontString(nil, "ARTWORK", "QuestmarkerSmallFont")
  party.label:SetPoint("CENTER")
  party.label:SetTextColor(0.4, 0.8, 1)
  party:SetScript("OnClick", function()
    if self.questID then
      ns.Party:Push(self.questID)
    end
  end)
  party:SetScript("OnEnter", function()
    GameTooltip:SetOwner(party, "ANCHOR_LEFT")
    GameTooltip:SetText("Could take this quest", 1, 1, 1)
    for _, name in ipairs(self.partyMissing or {}) do
      GameTooltip:AddLine(name, 0.4, 0.8, 1)
    end
    -- Members without it who can't take it, and why (Quests/Party.lua: level, class, their
    -- Questmarker's answer, or a share's reply).
    for _, entry in ipairs(self.partyCannot or {}) do
      GameTooltip:AddDoubleLine(entry.name, entry.reason, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Click to share it.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  party:SetScript("OnLeave", function() GameTooltip:Hide() end)
  party:Hide()
  self.party = party

  -- The card's progress bar (the whole quest); objective rows get their own when they need one.
  self.bar = createBar(frame)

  -- Timed quests: "Time left 2:12" under the title (review: Iverron's Antidote's timer was missing).
  self.timer = frame:CreateFontString(nil, "ARTWORK", "QuestmarkerLineFont")
  self.timer:SetJustifyH("LEFT")
  self.timer:Hide()

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
  -- The width may have changed since this card was last filled (resize grip).
  self.frame:SetWidth(WIDTH)
  self.lastNavText = nil  -- so SetNavigation re-fits the title to the current width

  -- Party members who lack the quest (only when it can be shared).
  if C_QuestLog.IsPushableQuest(quest.questID) then
    self.partyMissing, self.partyCannot = ns.Party:Status(quest.questID)
  else
    self.partyMissing, self.partyCannot = {}, {}
  end
  if #self.partyMissing > 0 then
    self.party.label:SetText("+" .. #self.partyMissing)
    self.party:SetWidth(self.party.label:GetStringWidth() + 6)
    self.party:Show()
  else
    self.party:Hide()
  end
  self.rowCount = Card.RowCount(quest, collapsed)
  self.title:SetText(titleText(quest, options))
  self.toggle.label:SetText(collapsed and "+" or "-")

  for _, row in ipairs(self.rows) do
    row:Hide()
    row.highlight:Hide()
    row.navShown = false
    row.navText:SetText("")
    row.navArrow:Hide()
    row.text:SetWidth(WIDTH - ROW_INDENT - COUNTER_WIDTH)
  end
  self.highlighted = nil
  -- Per-objective arrows: quests with two or more objectives, not ready, not collapsed; each
  -- unfinished objective's row (set below, filled by UpdateObjectiveNavigation every tick).
  local rowNav = not quest.readyForTurnIn and not collapsed and #quest.objectives >= 2
  local style = ns.DB.profile.cards.arrowStyle
  if style ~= self.arrowStyle then
    self.arrowTintable = Card.ApplyArrowStyle(self.arrow, style)
    self.arrowStyle = style
  end
  self:SetNavigation(nil)  -- the driver fills it in on its next tick

  -- Bars (setting, default on): with two or more objectives in progress, one under each objective
  -- (review); otherwise one under the card. Collapsed and ready cards keep the single bar.
  local showBar = ns.DB.profile.cards.progressBar
  local barPerObjective = showBar and not collapsed and not quest.readyForTurnIn and #quest.objectives >= 2

  local y = TITLE_HEIGHT + 2

  -- A running quest timer, first under the title, collapsed cards included (it's urgent).
  self.timerEnd = Card.TimerEnd(quest.questID)
  self.timerShown = nil
  if self.timerEnd then
    self.timer:ClearAllPoints()
    self.timer:SetPoint("TOPLEFT", self.frame, "TOPLEFT", ROW_INDENT, -y)
    self.timer:Show()
    self:UpdateTimer()
    y = y + self.timer:GetStringHeight() + ROW_GAP
  else
    self.timer:Hide()
  end

  for i = 1, self.rowCount do
    local row = self.rows[i] or createRow(self)
    self.rows[i] = row
    local objectiveBar = false
    if quest.readyForTurnIn and i == self.rowCount then
      -- The turn-in line: last, below any kept objectives.
      local turnIn = ns.ForeverData:TurnInName(quest.questID)
      setRow(row, turnIn and ("Turn in to " .. turnIn) or "Ready to turn in", nil, false)
      row.text:SetTextColor(0.2, 1, 0.2)
    else
      local objective = quest.objectives[i]
      row.navShown = rowNav and not objective.finished
      if row.navShown then
        row.text:SetWidth(WIDTH - ROW_INDENT - COUNTER_WIDTH - ROW_NAV_WIDTH)
      end
      local text, counter = ns.DoLine:For(objective, quest.questID)
      setRow(row, text, counter, objective.finished or quest.readyForTurnIn)
      objectiveBar = barPerObjective
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -y)
    local height = row.text:GetStringHeight()
    if objectiveBar then
      row.bar = row.bar or createBar(row)
      row.bar:ClearAllPoints()
      row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_INDENT, -(height + BAR_GAP))
      row.bar:Show()
      setObjectiveBar(row.bar, quest.objectives[i])
      height = height + BAR_GAP + BAR_HEIGHT
    elseif row.bar then
      row.bar:Hide()
    end
    row:SetSize(WIDTH, height)
    row:Show()
    y = y + height + ROW_GAP
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
    if row.bar then
      row.bar:Hide()  -- rows are reused: this one may have been an objective with a bar
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -y)
    row:SetSize(WIDTH, row.text:GetStringHeight())
    row:Show()
    y = y + row.text:GetStringHeight() + ROW_GAP
  end

  -- Progress bar under the card, unless each objective has its own; shown on collapsed cards too, as a
  -- summary.
  local cardBar = showBar and not barPerObjective
  self.bar:SetShown(cardBar)
  if cardBar then
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
    local partyWidth = 0
    if self.party:IsShown() then
      self.party:ClearAllPoints()
      self.party:SetPoint("TOPRIGHT", -(TOGGLE_WIDTH + navWidth), 0)
      partyWidth = self.party:GetWidth() + 2
    end
    self.title:SetWidth(WIDTH - TOGGLE_WIDTH - navWidth - partyWidth)
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

---Each objective row's own arrow and distance (rows with navShown). Called 10 times a second with the
---card's arrow; only touches what changed.
---@param quest table
function Card:UpdateObjectiveNavigation(quest)
  local show = ns.DB.profile.cards.show
  for i, row in ipairs(self.rows) do
    if row.navShown then
      local nav = ns.Navigation:ObjectiveNav(quest, i)
      local text, arrow = "", false
      if nav then
        if nav.zone then
          text = nav.zone
        elseif nav.inArea then
          text = "|cff33ff33here|r"
        else
          text = ("%d yd"):format(nav.distance)
          arrow = nav.angle ~= nil
        end
      end
      if not show.distance then
        text = ""
      end
      arrow = arrow and show.arrow
      if text ~= row.lastNavText then
        -- Sized to the text (so the arrow sits right beside it), capped to the row's nav space so a
        -- long zone name is cut instead of covering the objective.
        row.navText:SetWidth(0)
        row.navText:SetText(text)
        local maxWidth = ROW_NAV_WIDTH - ROW_ARROW_SIZE - 2
        if row.navText:GetStringWidth() > maxWidth then
          row.navText:SetWidth(maxWidth)
        end
        row.lastNavText = text
      end
      if arrow and row.arrowStyle ~= self.arrowStyle then
        row.arrowTintable = Card.ApplyArrowStyle(row.navArrow, self.arrowStyle)
        row.arrowStyle = self.arrowStyle
      end
      row.navArrow:SetShown(arrow)
      if arrow and nav then
        row.navArrow:SetRotation(nav.angle)
        if row.arrowTintable then
          if ns.DB.profile.cards.arrowColorByDistance then
            row.navArrow:SetVertexColor(distanceColor(nav.distance))
          else
            row.navArrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
          end
        end
      end
    end
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

---When a quest's timer runs out (GetTime() scale), or nil when it has no running timer. The same
---call Blizzard's tracker uses for its timer bar (Blizzard_QuestObjectiveTracker.lua:372-374).
---@param questID number
---@return number?
function Card.TimerEnd(questID)
  local total, elapsed = C_QuestLog.GetTimeAllowed(questID)
  if type(total) ~= "number" or type(elapsed) ~= "number" or issecretvalue(total) or issecretvalue(elapsed)
      or total <= 0 or elapsed >= total then
    return nil
  end
  return GetTime() + (total - elapsed)
end

---Refresh the countdown text (called on every navigation tick; only changes once a second).
function Card:UpdateTimer()
  if not self.timerEnd then
    return
  end
  local left = math.max(0, math.ceil(self.timerEnd - GetTime()))
  if left == self.timerShown then
    return
  end
  self.timerShown = left
  if left == 0 then
    self.timer:SetText("Time's up")
    self.timer:SetTextColor(1, 0.2, 0.2)
    return
  end
  self.timer:SetText(("Time left %d:%02d"):format(math.floor(left / 60), left % 60))
  if left <= 20 then
    self.timer:SetTextColor(1, 0.2, 0.2)
  elseif left <= 60 then
    self.timer:SetTextColor(1, 0.55, 0.1)
  else
    self.timer:SetTextColor(1, 0.85, 0.2)
  end
end

---Update the bars: the card's (one quest-wide bar), or each objective row's.
---@param quest table
function Card:UpdateBar(quest)
  if self.bar:IsShown() then
    local done, total = steps(quest)
    setBar(self.bar, done and done / total or progressOf(quest), total, quest.readyForTurnIn)
  end
  for i, row in ipairs(self.rows) do
    if row.bar and row.bar:IsShown() and quest.objectives[i] then
      setObjectiveBar(row.bar, quest.objectives[i])
    end
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
