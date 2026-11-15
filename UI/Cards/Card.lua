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
  { key = "classic", label = "Arrow", file = media("classic") },
  { key = "dart", label = "Dart", file = media("dart") },
  { key = "thin", label = "Thin arrow", file = media("thin") },
  { key = "minimap", label = "Minimap arrow", file = "Interface\\Minimap\\MinimapArrow" },
  { key = "chevron", label = "Chevron (Blizzard)", atlas = "NPE_ArrowUp" },
}

---Put arrow style `key` on a texture (unknown keys fall back to the first style).
function Card.ApplyArrowStyle(texture, key)
  local style = Card.ARROW_STYLES[1]
  for _, candidate in ipairs(Card.ARROW_STYLES) do
    if candidate.key == key then
      style = candidate
    end
  end
  if style.atlas then
    texture:SetAtlas(style.atlas)
  else
    texture:SetTexture(style.file)
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
---@param onClick fun(questID: number) left-click
function Card.Create(parent, onToggleCollapse, onMenu, onClick)
  local self = setmetatable({ rows = {} }, Card)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(WIDTH)
  frame:EnableMouse(true)
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

  self.title = frame:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
  self.title:SetPoint("TOPLEFT", 0, 0)
  self.title:SetWidth(WIDTH - TOGGLE_WIDTH)  -- narrowed by SetNavigation while an arrow shows
  self.title:SetJustifyH("LEFT")
  self.title:SetWordWrap(false)

  -- Arrow / in-area diamond and the distance or zone name, right-aligned before the toggle.
  self.navText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  self.navText:SetPoint("TOPRIGHT", -TOGGLE_WIDTH, -2)
  self.navText:SetJustifyH("RIGHT")
  self.arrow = frame:CreateTexture(nil, "ARTWORK")
  self.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  self.arrow:SetPoint("RIGHT", self.navText, "LEFT", -3, 0)
  self.arrow:Hide()
  self.inArea = frame:CreateTexture(nil, "ARTWORK")
  self.inArea:SetAtlas(IN_AREA_ATLAS)
  self.inArea:SetSize(ARROW_SIZE, ARROW_SIZE)
  self.inArea:SetPoint("RIGHT", self.navText, "LEFT", -3, 0)
  self.inArea:SetVertexColor(0.2, 1, 0.2)
  self.inArea:Hide()

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
    row.highlight:Hide()
  end
  self.highlighted = nil
  local style = ns.DB.profile.cards.arrowStyle
  if style ~= self.arrowStyle then
    Card.ApplyArrowStyle(self.arrow, style)
    self.arrowStyle = style
  end
  self:SetNavigation(nil)  -- the driver fills it in on its next tick

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
  end
  self.inArea:SetShown(inArea)
  if highlight ~= self.highlighted then
    for i, row in ipairs(self.rows) do
      row.highlight:SetShown(i == highlight)
    end
    self.highlighted = highlight
  end
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
