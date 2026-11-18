local ADDON_NAME, ns = ...

-- BubbleMap's settings: its own page in Blizzard's Options > AddOns. STOPGAP until the suite's shared
-- library (LibBubble, docs/design/bubble-suite.md) brings the one settings window and schema every
-- Bubble addon uses; these entries move into it then.

local function show(key)
  return function() return ns.DB.show[key] end, function(value)
    ns.DB.show[key] = value
    ns.Around:Apply()
  end
end

-- kind, id, label, tooltip, default, get, set (+ min, max, step, format for sliders)
local ENTRIES = {
  { kind = "section", label = "Map" },
  { kind = "checkbox", id = "BUBBLEMAP_LOCKED", label = "Lock the map", default = true,
    tooltip = "Untick to drag the map by its top bar.",
    get = function() return ns.DB.locked end, set = function(v) ns.DB.locked = v end },
  { kind = "slider", id = "BUBBLEMAP_WIDTH", label = "Width", default = 220, min = 140, max = 450, step = 5,
    tooltip = "The map's width. With BubbleQuest it follows the tracker's width instead (drag the "
      .. "tracker's corner).",
    format = function(v) return ("%d"):format(v) end,
    get = function() return ns.DB.width end,
    set = function(v) ns.DB.width = v; ns.Minimap:Refresh() end },
  { kind = "slider", id = "BUBBLEMAP_HEIGHT", label = "Height", default = 100, min = 50, max = 150, step = 5,
    tooltip = "The map's height, as a percentage of its width.",
    format = function(v) return ("%d%%"):format(v) end,
    get = function() return ns.DB.heightPercent end,
    set = function(v) ns.DB.heightPercent = v; ns.Minimap:Refresh() end },

  { kind = "section", label = "Around the map" },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_BAR", label = "Top bar", default = true,
    tooltip = "The bar along the map's top: zone name, buttons and clock. Untick to hide all of it." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_ZONE", label = "Zone name", default = true,
    tooltip = "Click it to open the world map." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_CLOCK", label = "Clock", default = true,
    tooltip = "Local or realm time, 12 or 24 hours: the game's clock settings (click the clock)." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_CALENDAR", label = "Calendar button", default = true,
    tooltip = "Shows how many invites are waiting." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_TRACKING", label = "Tracking button", default = true,
    tooltip = "What the minimap shows: flight masters, trainers, ..." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_MAIL", label = "New mail", default = true,
    tooltip = "An envelope when there's new mail; hover it for the senders." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_COORDS", label = "Coordinates", default = false,
    tooltip = "Your position, bottom left of the map. (BubbleQuest's header shows them too.)" },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_ZOOM", label = "Zoom buttons", default = false,
    tooltip = "+ and - at the map's bottom right. The mouse wheel zooms either way." },
  { kind = "checkbox", id = "BUBBLEMAP_LAUNCHERS", label = "Collect addon buttons", default = true,
    tooltip = "Every addon's minimap button and addon-menu entry in one list, opened from the bar; their "
      .. "buttons are put away. With another button collector on (MinimapButtonButton, ...) this waits, "
      .. "and BubbleMap offers to turn that one off. Takes effect after /reload." },
}

local SHOW_KEYS = {
  BUBBLEMAP_SHOW_BAR = "bar", BUBBLEMAP_SHOW_ZONE = "zone", BUBBLEMAP_SHOW_CLOCK = "clock",
  BUBBLEMAP_SHOW_CALENDAR = "calendar", BUBBLEMAP_SHOW_TRACKING = "tracking",
  BUBBLEMAP_SHOW_MAIL = "mail", BUBBLEMAP_SHOW_COORDS = "coords", BUBBLEMAP_SHOW_ZOOM = "zoom",
  BUBBLEMAP_LAUNCHERS = "launchers",
}

local VAR_TYPE = { checkbox = "Boolean", slider = "Number" }

local function register()
  local category = Settings.RegisterVerticalLayoutCategory("BubbleMap")
  local layout = SettingsPanel:GetLayout(category)
  for _, entry in ipairs(ENTRIES) do
    if entry.kind == "section" then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(entry.label))
    else
      local get, set = entry.get, entry.set
      if SHOW_KEYS[entry.id] then
        get, set = show(SHOW_KEYS[entry.id])
      end
      local setting = Settings.RegisterProxySetting(category, entry.id, Settings.VarType[VAR_TYPE[entry.kind]],
        entry.label, entry.default, get, set)
      if entry.kind == "checkbox" then
        Settings.CreateCheckbox(category, setting, entry.tooltip)
      else
        local options = Settings.CreateSliderOptions(entry.min, entry.max, entry.step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, entry.format)
        Settings.CreateSlider(category, setting, options, entry.tooltip)
      end
    end
  end
  Settings.RegisterAddOnCategory(category)
end

ns.On("ADDON_LOADED", function(name)
  if name == ADDON_NAME then
    register()  -- after Init.lua's handler (registered first): ns.DB is set
  end
end)
