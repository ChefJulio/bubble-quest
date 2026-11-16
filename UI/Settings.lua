local ADDON_NAME, ns = ...

-- Settings. Every setting is defined once in UI/SettingsSchema.lua. This file:
--   - registers them in Blizzard's Options > AddOns > Questmarker panel (proxies onto the active
--     profile, so switching profiles later needs no re-registration);
--   - opens Questmarker's own window (UI/SettingsWindow.lua) for /qm, the header and its button.
--     Blizzard's panel always reopens the game menu when it closes
--     (Blizzard_SettingsPanel.lua:295-302, TransitionBackOpeningPanel); our window doesn't, and as a
--     plain frame it also opens in combat.

local QuestmarkerSettings = {
  category = nil,  -- Blizzard panel category, once registered
}
ns.Settings = QuestmarkerSettings

local VAR_TYPE = { checkbox = "Boolean", slider = "Number", dropdown = "String" }

local function register(category, layout, entry)
  if entry.windowOnly or (entry.onlyIf and not entry.onlyIf()) then
    return  -- Questmarker's window only (e.g. the Questie status row: not a setting)
  end
  if entry.kind == "section" then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(entry.label))
    return
  end
  local setting = Settings.RegisterProxySetting(category, entry.id, Settings.VarType[VAR_TYPE[entry.kind]],
    entry.label, entry.default,
    function() return entry.get(ns.DB.profile) end,
    function(value) ns.SettingsSchema:Set(entry, value) end)
  if entry.kind == "checkbox" then
    Settings.CreateCheckbox(category, setting, entry.tooltip)
  elseif entry.kind == "slider" then
    local options = Settings.CreateSliderOptions(entry.min, entry.max, entry.step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, entry.format)
    Settings.CreateSlider(category, setting, options, entry.tooltip)
  elseif entry.kind == "dropdown" then
    Settings.CreateDropdown(category, setting, function()
      local container = Settings.CreateControlTextContainer()
      for _, option in ipairs(entry.options()) do
        container:Add(option[1], option[2])
      end
      return container:GetData()
    end, entry.tooltip)
  end
end

-- Called once SavedVariables are loaded.
function QuestmarkerSettings:Register()
  local category = Settings.RegisterVerticalLayoutCategory("Questmarker")
  -- SettingsPanel is Blizzard's global frame. (This module's table was once a local of the same name,
  -- which hid it: the panel never registered.)
  local layout = SettingsPanel:GetLayout(category)
  for _, entry in ipairs(ns.SettingsSchema:Entries()) do
    register(category, layout, entry)
  end
  Settings.RegisterAddOnCategory(category)
  self.category = category
end

---Change a setting from outside both UIs (the header's lock button).
---@param id string
function QuestmarkerSettings:SetValue(id, value)
  local entry = ns.SettingsSchema:Find(id)
  if entry then
    ns.SettingsSchema:Set(entry, value)
  end
end

---Open Questmarker's own settings window.
function QuestmarkerSettings:Open()
  ns.SettingsWindow:Toggle()
end

-- Keep Blizzard's panel in step when a setting changes elsewhere (our window, the lock button).
ns.Bus:On("SettingChanged", function(id)
  if QuestmarkerSettings.category then
    Settings.NotifyUpdate(id)
  end
end)
