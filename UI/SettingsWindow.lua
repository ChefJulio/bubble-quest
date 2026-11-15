local ADDON_NAME, ns = ...

-- Questmark's own settings window, built from UI/SettingsSchema.lua (the same list Blizzard's
-- Options > AddOns panel is built from). Opened by /qm, the header and its settings button. Unlike
-- Blizzard's panel it doesn't reopen the game menu when closed, and it opens in combat.
--
-- Controls are Blizzard's templates: UICheckButtonTemplate, MinimalSliderWithSteppersTemplate and
-- WowStyle1DropdownTemplate (the modern menu-based dropdown). Every control reads its value from the
-- profile when the window opens or a setting changes (SettingChanged); `refreshing` stops those
-- refreshes from being taken as the player's changes.

local COLUMN_WIDTH = 270
local PAD = 16
local TOP = 34
local SECTION_HEIGHT = 26
local CHECKBOX_HEIGHT = 26
local LABELLED_HEIGHT = 46  -- label above a slider or dropdown

local Window = {
  frame = nil,
  controls = {},      -- { entry, refresh = function() }
  refreshing = false,
}
ns.SettingsWindow = Window

local function tooltip(owner, entry)
  owner:SetScript("OnEnter", function()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.label, 1, 1, 1)
    GameTooltip:AddLine(entry.tooltip, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function change(entry, value)
  if not Window.refreshing then
    ns.SettingsSchema:Set(entry, value)
  end
end

local builders = {}

function builders.section(parent, entry, x, y)
  local text = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("TOPLEFT", x, y - 6)
  text:SetText(entry.label)
  return SECTION_HEIGHT
end

function builders.checkbox(parent, entry, x, y)
  local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  box:SetPoint("TOPLEFT", x - 4, y)
  box:SetSize(26, 26)
  box.Text:SetFontObject("GameFontHighlight")
  box.Text:SetText(entry.label)
  box.Text:SetWidth(COLUMN_WIDTH - 30)
  box.Text:SetJustifyH("LEFT")
  box:SetScript("OnClick", function(self) change(entry, self:GetChecked()) end)
  tooltip(box, entry)
  return CHECKBOX_HEIGHT, function() box:SetChecked(entry.get(ns.DB.profile)) end
end

function builders.slider(parent, entry, x, y)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("TOPLEFT", x, y)
  label:SetText(entry.label)
  local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
  slider:SetPoint("TOPLEFT", x, y - 16)
  slider:SetWidth(COLUMN_WIDTH - 50)
  local steps = (entry.max - entry.min) / entry.step
  local formatters = { [MinimalSliderWithSteppersMixin.Label.Right] = entry.format }
  slider:Init(entry.get(ns.DB.profile), entry.min, entry.max, steps, formatters)
  slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    -- Dragging reports in-between values; keep whole steps.
    change(entry, entry.min + math.floor((value - entry.min) / entry.step + 0.5) * entry.step)
  end, slider)
  tooltip(slider, entry)
  return LABELLED_HEIGHT, function() slider:SetValue(entry.get(ns.DB.profile)) end
end

function builders.dropdown(parent, entry, x, y)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("TOPLEFT", x, y)
  label:SetText(entry.label)
  local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dropdown:SetPoint("TOPLEFT", x, y - 16)
  dropdown:SetWidth(COLUMN_WIDTH - 50)
  dropdown:SetupMenu(function(_, root)
    for _, option in ipairs(entry.options()) do
      local value = option[1]
      root:CreateRadio(option[2],
        function() return entry.get(ns.DB.profile) == value end,
        function() change(entry, value) end)
    end
  end)
  tooltip(dropdown, entry)
  return LABELLED_HEIGHT, function() dropdown:GenerateMenu() end
end

local function create()
  local frame = CreateFrame("Frame", "QuestmarkSettingsWindow", UIParent, "BasicFrameTemplateWithInset")
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame.TitleText:SetText("Questmark")
  tinsert(UISpecialFrames, "QuestmarkSettingsWindow")  -- Escape closes it

  local y = { -TOP, -TOP }
  for _, entry in ipairs(ns.SettingsSchema:Entries()) do
    local column = entry.column or 1
    local x = PAD + (column - 1) * (COLUMN_WIDTH + PAD)
    local height, refresh = builders[entry.kind](frame, entry, x, y[column])
    y[column] = y[column] - height
    if refresh then
      Window.controls[#Window.controls + 1] = refresh
    end
  end

  local note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  note:SetPoint("BOTTOMLEFT", PAD, 12)
  note:SetText("Also in Options > AddOns > Questmark")

  frame:SetSize(2 * COLUMN_WIDTH + 3 * PAD, -math.min(y[1], y[2]) + 34)
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
