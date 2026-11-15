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

local COLUMN_WIDTH = 270
local PAD = 18
local HEADER_HEIGHT = 30
local SECTION_HEIGHT = 30
local CHECKBOX_HEIGHT = 26
local LABELLED_HEIGHT = 48     -- label above a slider or dropdown
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

local function tooltip(owner, title, text)
  owner:SetScript("OnEnter", function()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if text then
      GameTooltip:AddLine(text, nil, nil, nil, true)
    end
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

-- Builders: build(parent, entry, x, y) -> height used, refresh function (optional).
local builders = {}

function builders.section(parent, entry, x, y)
  local text = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("TOPLEFT", x, y - 8)
  text:SetText(entry.label)
  divider(parent, x, y - 24, COLUMN_WIDTH)
  return SECTION_HEIGHT
end

function builders.checkbox(parent, entry, x, y)
  local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  box:SetPoint("TOPLEFT", x - 4, y)
  box:SetSize(24, 24)
  box.Text:SetFontObject("GameFontHighlight")
  box.Text:SetText(entry.label)
  box.Text:SetWidth(COLUMN_WIDTH - 28)
  box.Text:SetJustifyH("LEFT")
  box:SetScript("OnClick", function(self) change(entry, self:GetChecked()) end)
  tooltip(box, entry.label, entry.tooltip)
  return CHECKBOX_HEIGHT, function() box:SetChecked(entry.get(ns.DB.profile)) end
end

function builders.slider(parent, entry, x, y)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("TOPLEFT", x, y - 2)
  label:SetText(entry.label)
  local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
  slider:SetPoint("TOPLEFT", x - 4, y - 18)
  slider:SetWidth(COLUMN_WIDTH - 40)
  local formatters = { [MinimalSliderWithSteppersMixin.Label.Right] = entry.format }
  slider:Init(entry.get(ns.DB.profile), entry.min, entry.max, (entry.max - entry.min) / entry.step, formatters)
  slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    -- Dragging reports in-between values; keep whole steps.
    change(entry, entry.min + math.floor((value - entry.min) / entry.step + 0.5) * entry.step)
  end, slider)
  tooltip(slider, entry.label, entry.tooltip)
  return LABELLED_HEIGHT, function() slider:SetValue(entry.get(ns.DB.profile)) end
end

function builders.dropdown(parent, entry, x, y)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("TOPLEFT", x, y - 2)
  label:SetText(entry.label)
  local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dropdown:SetPoint("TOPLEFT", x, y - 18)
  dropdown:SetWidth(COLUMN_WIDTH - 40)
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
  return LABELLED_HEIGHT, function() dropdown:GenerateMenu() end
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
  local gridsBuilt = {}
  local entries = ns.SettingsSchema:Entries()
  for _, entry in ipairs(entries) do
    local column = entry.column or 1
    local x = PAD + (column - 1) * (COLUMN_WIDTH + PAD * 2)
    local height, refresh = 0, nil
    if entry.grid then
      if not gridsBuilt[entry.grid] then
        gridsBuilt[entry.grid] = true
        local members = {}
        for _, other in ipairs(entries) do
          if other.grid == entry.grid then
            members[#members + 1] = other
          end
        end
        height, refresh = buildGrid(frame, members, x, y[column])
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
