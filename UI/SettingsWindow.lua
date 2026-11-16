local ADDON_NAME, ns = ...

-- Questmarker's own settings window, built from UI/SettingsSchema.lua (the same list Blizzard's
-- Options > AddOns panel is built from). Opened by /qm, the header and its settings button. Unlike
-- Blizzard's panel it doesn't reopen the game menu when closed, and it opens in combat.
--
-- Look: the tracker's style (flat dark panel, thin border, header band, gold section titles with
-- faint dividers). Controls are Blizzard's templates: UICheckButtonTemplate,
-- MinimalSliderWithSteppersTemplate, WowStyle1DropdownTemplate (menu-based) and UIRadioButtonTemplate.
-- Entries sharing a `grid` (the quest categories) render as one table: a row each, a radio per option.
--
-- Every control reads its value from the profile when the window opens or a setting changes
-- (SettingChanged); `refreshing` stops those refreshes from counting as the player's changes.

local COLUMN_WIDTH = 300
local PAD = 18
local HEADER_HEIGHT = 30
local SECTION_HEIGHT = 30
local CHECKBOX_HEIGHT = 26
local INLINE_HEIGHT = 30       -- label and slider or dropdown on one row (review: half the height)
local INLINE_LABEL_WIDTH = 135  -- fits "Background opacity" on one line
local SLIDER_VALUE_WIDTH = 36  -- room right of the slider for its value ("100%")
local GRID_LABEL_WIDTH = 120
local GRID_COLUMN_WIDTH = 50
local GRID_ROW_HEIGHT = 24
local DIVIDER_ALPHA = 0.12
local MENU_SCROLL_AFTER = 15   -- dropdown entries before the menu scrolls
local MENU_MAX_HEIGHT = 360

local Window = {
  frame = nil,
  controls = {},      -- refresh functions
  refreshing = false,
}
ns.SettingsWindow = Window

-- Tooltips (review: hovering often showed nothing). A tooltip is hooked (HookScript, so templates keep
-- their own hover highlights) onto the control and onto every mouse-enabled part of it: a slider's
-- frame takes no mouse input itself, its bar and stepper buttons do. Each row also gets a hover area
-- under its controls (hoverArea), so its label shows the tooltip too.
local function showTooltip(owner, title, text)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(title, 1, 1, 1)
  if text then
    GameTooltip:AddLine(text, nil, nil, nil, true)
  end
  GameTooltip:Show()
end

local function tooltip(owner, title, text)
  local targets = { owner }
  for _, child in ipairs({ owner:GetChildren() }) do
    targets[#targets + 1] = child
  end
  for _, target in ipairs(targets) do
    target:HookScript("OnEnter", function() showTooltip(owner, title, text) end)
    target:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end
end

-- An invisible, mouse-enabled area for a row's tooltip, beneath the row's controls (at the panel's own
-- frame level; controls sit one above), so the label shows it and the controls still get the mouse.
local function hoverArea(parent, x, y, width, height, title, text)
  local area = CreateFrame("Frame", nil, parent)
  area:SetPoint("TOPLEFT", x - 4, y)
  area:SetSize(width + 8, height)
  area:SetFrameLevel(parent:GetFrameLevel())
  area:EnableMouse(true)
  area:SetScript("OnEnter", function() showTooltip(area, title, text) end)
  area:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return area
end

local function change(entry, value)
  if not Window.refreshing then
    ns.SettingsSchema:Set(entry, value)
  end
end

local function divider(parent, x, y, width)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, DIVIDER_ALPHA)
  line:SetPoint("TOPLEFT", x, y)
  line:SetSize(width, 1)
  PixelUtil.SetHeight(line, 1, 1)
  return line
end

-- Greyed out while entry.enabledWhen(profile) says so (applied on every refresh).
local function enabledNow(entry)
  return entry.enabledWhen == nil or entry.enabledWhen(ns.DB.profile) and true or false
end

local function setTextEnabled(fontString, enabled)
  local color = enabled and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR
  fontString:SetTextColor(color:GetRGB())
end

-- Builders: build(parent, entry, x, y) -> height used, refresh function (optional).
local builders = {}

function builders.section(parent, entry, x, y)
  local text = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("TOPLEFT", x, y - 8)
  text:SetText(entry.label)
  divider(parent, x, y - 24, COLUMN_WIDTH)
  return SECTION_HEIGHT
end

-- A checkbox; `label` overrides entry.label (rows use the short label). Returns the box too, for rows.
local function checkbox(parent, entry, x, y, label)
  local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  box:SetPoint("TOPLEFT", x - 4, y)
  box:SetSize(24, 24)
  box.Text:SetFontObject("GameFontHighlight")
  box.Text:SetText(label or entry.label)
  box.Text:SetJustifyH("LEFT")
  box:SetScript("OnClick", function(self) change(entry, self:GetChecked()) end)
  -- The label is part of the button: hovering or clicking the text works, as in Blizzard's options.
  box:SetHitRectInsets(0, -(box.Text:GetStringWidth() + 6), 0, 0)
  tooltip(box, entry.label, entry.tooltip)
  local refresh = function()
    box:SetChecked(entry.get(ns.DB.profile))
    local enabled = enabledNow(entry)
    box:SetEnabled(enabled)
    setTextEnabled(box.Text, enabled)
  end
  return box, refresh
end

function builders.checkbox(parent, entry, x, y)
  local box, refresh = checkbox(parent, entry, x, y)
  box.Text:SetWidth(COLUMN_WIDTH - 28)
  return CHECKBOX_HEIGHT, refresh
end

-- The label left, the control right of it, on one row.
local function inlineLabel(parent, entry, x, y)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("LEFT", parent, "TOPLEFT", x, y - INLINE_HEIGHT / 2)
  label:SetWidth(INLINE_LABEL_WIDTH - 6)
  label:SetJustifyH("LEFT")
  label:SetText(entry.label)
  return label
end

function builders.slider(parent, entry, x, y)
  hoverArea(parent, x, y, COLUMN_WIDTH, INLINE_HEIGHT, entry.label, entry.tooltip)
  inlineLabel(parent, entry, x, y)
  local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
  slider:SetPoint("LEFT", parent, "TOPLEFT", x + INLINE_LABEL_WIDTH - 4, y - INLINE_HEIGHT / 2)
  slider:SetWidth(COLUMN_WIDTH - INLINE_LABEL_WIDTH - SLIDER_VALUE_WIDTH)
  local formatters = { [MinimalSliderWithSteppersMixin.Label.Right] = entry.format }
  slider:Init(entry.get(ns.DB.profile), entry.min, entry.max, (entry.max - entry.min) / entry.step, formatters)
  slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    -- Dragging reports in-between values; keep whole steps.
    change(entry, entry.min + math.floor((value - entry.min) / entry.step + 0.5) * entry.step)
  end, slider)
  tooltip(slider, entry.label, entry.tooltip)
  return INLINE_HEIGHT, function() slider:SetValue(entry.get(ns.DB.profile)) end
end

-- A dropdown `width` wide at x, vertically centred on the row at y. Returns it and its refresh.
local function dropdownAt(parent, entry, x, y, width)
  local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dropdown:SetPoint("LEFT", parent, "TOPLEFT", x, y - INLINE_HEIGHT / 2)
  dropdown:SetWidth(width)
  dropdown:SetupMenu(function(_, root)
    local options = entry.options()
    if #options > MENU_SCROLL_AFTER then
      root:SetScrollMode(MENU_MAX_HEIGHT)  -- long lists (fonts) scroll instead of running off screen
    end
    for _, option in ipairs(options) do
      local value = option[1]
      local radio = root:CreateRadio(option[2],
        function() return entry.get(ns.DB.profile) == value end,
        function() change(entry, value) end)
      local font = entry.preview and entry.preview(value)
      if font then
        -- Draw the option in its own font, the guide's way (Blizzard_Menu/
        -- 11_0_0_MenuImplementationGuide.lua:202-205): SetFontObject. Menu font strings disallow
        -- SetFont (Compositor.lua:166-169), which errored once per entry.
        local object = ns.Fonts:PreviewObject(font)
        radio:AddInitializer(function(button)
          button.fontString:SetFontObject(object)
        end)
      end
    end
  end)
  tooltip(dropdown, entry.label, entry.tooltip)
  return dropdown, function()
    dropdown:GenerateMenu()
    dropdown:SetEnabled(enabledNow(entry))
  end
end

function builders.dropdown(parent, entry, x, y)
  hoverArea(parent, x, y, COLUMN_WIDTH, INLINE_HEIGHT, entry.label, entry.tooltip)
  local label = inlineLabel(parent, entry, x, y)
  local _, refresh = dropdownAt(parent, entry, x + INLINE_LABEL_WIDTH, y, COLUMN_WIDTH - INLINE_LABEL_WIDTH)
  return INLINE_HEIGHT, function()
    refresh()
    setTextEnabled(label, enabledNow(entry))
  end
end

-- A label, a live status and a button on one row (e.g. Questie's tracker: "On  [Turn off]").
function builders.status(parent, entry, x, y)
  hoverArea(parent, x, y, COLUMN_WIDTH, INLINE_HEIGHT, entry.label, entry.tooltip)
  inlineLabel(parent, entry, x, y)
  local state = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  state:SetPoint("LEFT", parent, "TOPLEFT", x + INLINE_LABEL_WIDTH, y - INLINE_HEIGHT / 2)
  local action = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  action:SetText(entry.actionLabel)
  action:SetSize(90, 22)
  action:SetPoint("RIGHT", parent, "TOPLEFT", x + COLUMN_WIDTH, y - INLINE_HEIGHT / 2)
  action:SetScript("OnClick", function() entry.action() end)
  tooltip(action, entry.label, entry.tooltip)
  return INLINE_HEIGHT, function()
    local text, color = entry.status()
    state:SetText(text)
    state:SetTextColor((color or HIGHLIGHT_FONT_COLOR):GetRGB())
    action:SetEnabled(entry.actionEnabled == nil or entry.actionEnabled())
  end
end

-- Entries sharing a `row`, left to right on one line: the first one's rowLabel, then each control
-- (checkboxes with their short label, dropdowns `width` wide). Greys the row label with the first.
local function buildRow(parent, members, x, y)
  local cursor = x
  local refreshes = {}
  local lead
  if members[1].rowLabel then
    lead = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lead:SetPoint("LEFT", parent, "TOPLEFT", x, y - INLINE_HEIGHT / 2)
    lead:SetText(members[1].rowLabel)
    cursor = cursor + math.max(lead:GetStringWidth() + 10, members[1].kind == "dropdown" and INLINE_LABEL_WIDTH or 0)
  end
  for _, entry in ipairs(members) do
    if entry.kind == "checkbox" then
      local box, refresh = checkbox(parent, entry, cursor, y - (INLINE_HEIGHT - 24) / 2, entry.short)
      cursor = cursor + 24 + box.Text:GetStringWidth() + 14
      refreshes[#refreshes + 1] = refresh
    elseif entry.kind == "dropdown" then
      local width = entry.width or 90
      local _, refresh = dropdownAt(parent, entry, cursor, y, width)
      cursor = cursor + width + 12
      refreshes[#refreshes + 1] = refresh
    end
  end
  return INLINE_HEIGHT, function()
    for _, refresh in ipairs(refreshes) do
      refresh()
    end
    if lead then
      setTextEnabled(lead, enabledNow(members[1]))
    end
  end
end

-- A table for entries sharing a grid: column headings from the options, a row per entry with one
-- radio button per option.
local function buildGrid(parent, entries, x, y)
  local options = entries[1].options()
  local short = { show = "Show", separate = "Separate", hide = "Hide" }
  local top = y
  for i, option in ipairs(options) do
    local heading = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    heading:SetPoint("TOP", parent, "TOPLEFT", x + GRID_LABEL_WIDTH + (i - 0.5) * GRID_COLUMN_WIDTH, y - 2)
    heading:SetText(short[option[1]] or option[2])
  end
  y = y - 18

  local refreshes = {}
  for row, entry in ipairs(entries) do
    if row % 2 == 0 then
      local stripe = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
      stripe:SetColorTexture(1, 1, 1, 0.03)
      stripe:SetPoint("TOPLEFT", x - 4, y)
      stripe:SetSize(GRID_LABEL_WIDTH + #options * GRID_COLUMN_WIDTH + 8, GRID_ROW_HEIGHT)
    end
    hoverArea(parent, x, y, GRID_LABEL_WIDTH + #options * GRID_COLUMN_WIDTH, GRID_ROW_HEIGHT, entry.label,
      entry.tooltip)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", parent, "TOPLEFT", x, y - GRID_ROW_HEIGHT / 2)
    label:SetText(entry.label)
    local radios = {}
    for i, option in ipairs(options) do
      local value = option[1]
      local radio = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
      radio:SetPoint("CENTER", parent, "TOPLEFT", x + GRID_LABEL_WIDTH + (i - 0.5) * GRID_COLUMN_WIDTH,
        y - GRID_ROW_HEIGHT / 2)
      radio:SetScript("OnClick", function() change(entry, value) end)
      tooltip(radio, ("%s: %s"):format(entry.label, option[2]), entry.tooltip)
      radios[value] = radio
    end
    refreshes[#refreshes + 1] = function()
      local current = entry.get(ns.DB.profile)
      for value, radio in pairs(radios) do
        radio:SetChecked(value == current)
      end
    end
    y = y - GRID_ROW_HEIGHT
  end

  local note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", x, y - 8)
  note:SetWidth(COLUMN_WIDTH)
  note:SetJustifyH("LEFT")
  note:SetText("Show: with this zone's cards.  Separate: in its own collapsed group.  Hide: not shown. "
    .. "Pinned quests always show.")
  y = y - 8 - note:GetStringHeight()

  return top - y, function()
    for _, refresh in ipairs(refreshes) do
      refresh()
    end
  end
end

local function createPanel()
  local frame = CreateFrame("Frame", "QuestmarkerSettingsWindow", UIParent)
  -- New frames start shown; start hidden so the first Toggle opens it (and runs OnShow's refresh).
  frame:Hide()
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "QuestmarkerSettingsWindow")  -- Escape closes it

  local background = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
  background:SetAllPoints()
  background:SetColorTexture(0.05, 0.05, 0.06, 0.94)
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetPoint(edge[1])
    line:SetPoint(edge[2])
    PixelUtil.SetHeight(line, 1, 1)
  end
  for _, edge in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetPoint(edge[1])
    line:SetPoint(edge[2])
    PixelUtil.SetWidth(line, 1, 1)
  end

  -- Header band: title, drag handle, close button.
  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER_HEIGHT)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() frame:StartMoving() end)
  header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  local band = header:CreateTexture(nil, "BACKGROUND", nil, 1)
  band:SetAllPoints()
  band:SetColorTexture(0, 0, 0, 0.45)
  local title = header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
  title:SetPoint("LEFT", PAD - 4, 0)
  title:SetText("Questmarker settings")
  local close = CreateFrame("Button", nil, header, "UIPanelCloseButtonNoScripts")
  close:SetPoint("RIGHT", -2, 0)
  close:SetScript("OnClick", function() frame:Hide() end)
  divider(frame, 0, -HEADER_HEIGHT, 1):SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT)
  return frame
end

local function create()
  local frame = createPanel()
  local y = { -HEADER_HEIGHT - 6, -HEADER_HEIGHT - 6 }
  local groupsBuilt = {}  -- grids and rows are built once, at their first entry
  local entries = ns.SettingsSchema:Entries()
  local function membersOf(field, name)
    local members = {}
    for _, other in ipairs(entries) do
      if other[field] == name then
        members[#members + 1] = other
      end
    end
    return members
  end
  for _, entry in ipairs(entries) do
    local column = entry.column or 1
    local x = PAD + (column - 1) * (COLUMN_WIDTH + PAD * 2)
    local height, refresh = 0, nil
    local group = entry.grid and ("grid:" .. entry.grid) or entry.row and ("row:" .. entry.row)
    if entry.onlyIf and not entry.onlyIf() then
      -- left out (e.g. the Questie section without Questie)
    elseif group then
      if not groupsBuilt[group] then
        groupsBuilt[group] = true
        if entry.grid then
          height, refresh = buildGrid(frame, membersOf("grid", entry.grid), x, y[column])
        else
          height, refresh = buildRow(frame, membersOf("row", entry.row), x, y[column])
        end
      end
    else
      height, refresh = builders[entry.kind](frame, entry, x, y[column])
    end
    y[column] = y[column] - height
    if refresh then
      Window.controls[#Window.controls + 1] = refresh
    end
  end

  local note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  note:SetPoint("BOTTOMRIGHT", -PAD, 10)
  note:SetText("Also in Options > AddOns > Questmarker")

  frame:SetSize(2 * COLUMN_WIDTH + 4 * PAD, -math.min(y[1], y[2]) + 32)
  frame:SetScript("OnShow", function() Window:Refresh() end)
  return frame
end

function Window:Refresh()
  if not self.frame or not self.frame:IsShown() then
    return
  end
  self.refreshing = true
  for _, refresh in ipairs(self.controls) do
    refresh()
  end
  self.refreshing = false
end

function Window:Toggle()
  self.frame = self.frame or create()
  self.frame:SetShown(not self.frame:IsShown())
end

ns.Bus:On("SettingChanged", function()
  Window:Refresh()
end)
