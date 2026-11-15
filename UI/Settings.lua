local ADDON_NAME, ns = ...

-- Settings panel in the game's Options > AddOns. Settings are proxies onto the *active profile*,
-- so switching profiles later needs no re-registration.

local QuestmarkSettings = {
  category = nil,
}
ns.Settings = QuestmarkSettings

---@param category table
---@param variable string unique setting id
---@param name string
---@param tooltip string
---@param default boolean
---@param get fun(profile: table): boolean
---@param set fun(profile: table, value: boolean)
local function addCheckbox(category, variable, name, tooltip, default, get, set)
  local setting = Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, name, default,
    function() return get(ns.DB.profile) end,
    function(value) set(ns.DB.profile, value) end)
  Settings.CreateCheckbox(category, setting, tooltip)
end

-- Called once SavedVariables are loaded.
function QuestmarkSettings:Register()
  local category = Settings.RegisterVerticalLayoutCategory("Questmark")

  addCheckbox(category, "QUESTMARK_HIDE_BLIZZARD_TRACKER", "Hide Blizzard quest tracker",
    "Hide the game's objective tracker so Questmark's cards replace it. Quest auto-complete "
    .. "popups and the scenario tracker are part of it and hide too.",
    true,
    function(profile) return profile.blizzardTracker.hide end,
    function(profile, value)
      profile.blizzardTracker.hide = value
      ns.BlizzardTracker:Apply()
    end)

  addCheckbox(category, "QUESTMARK_LOCK_CARDS", "Lock card position",
    "Untick to drag Questmark's cards somewhere else on screen; tick again to lock them there.",
    true,
    function(profile) return profile.cards.locked end,
    function(profile, value)
      profile.cards.locked = value
      ns.Stack:ApplyLock()
    end)

  addCheckbox(category, "QUESTMARK_CLICK_OPENS_MAP", "Click a card to show its quest on the map",
    "Left-clicking a card makes it your tracked quest (map highlight and in-world beacon) and opens "
    .. "the map at it. Out of combat only.",
    true,
    function(profile) return profile.cards.clickOpensMap end,
    function(profile, value) profile.cards.clickOpensMap = value end)

  local arrowSetting = Settings.RegisterProxySetting(category, "QUESTMARK_ARROW_STYLE", Settings.VarType.String,
    "Arrow style", "classic",
    function() return ns.DB.profile.cards.arrowStyle end,
    function(value)
      ns.DB.profile.cards.arrowStyle = value
      ns.Stack:Request(false, true)
    end)
  Settings.CreateDropdown(category, arrowSetting, function()
    local container = Settings.CreateControlTextContainer()
    for _, style in ipairs(ns.Card.ARROW_STYLES) do
      container:Add(style.key, style.label)
    end
    return container:GetData()
  end, "The arrow on each card. /qm arrows shows them all side by side.")

  addCheckbox(category, "QUESTMARK_ARROW_COLOR", "Color arrows by distance",
    "Green when close, through yellow and orange, to red when far (or in another zone). Off: gold. "
    .. "Applies to Questmark's own arrow styles.",
    true,
    function(profile) return profile.cards.arrowColorByDistance end,
    function(profile, value) profile.cards.arrowColorByDistance = value end)

  local capSetting = Settings.RegisterProxySetting(category, "QUESTMARK_CARD_CAP", Settings.VarType.Number,
    "Cards shown for this zone", 5,
    function() return ns.DB.profile.cards.cap end,
    function(value)
      ns.DB.profile.cards.cap = value
      ns.Stack:Request(false, true)
    end)
  local capOptions = Settings.CreateSliderOptions(1, 15, 1)
  capOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
  Settings.CreateSlider(category, capSetting, capOptions,
    "How many of this zone's quests get a card before the rest go behind \"+ N more here\". "
    .. "Pinned quests always show and don't count.")

  local opacitySetting = Settings.RegisterProxySetting(category, "QUESTMARK_BACKGROUND_OPACITY",
    Settings.VarType.Number, "Background opacity", 25,
    function() return ns.DB.profile.cards.opacity end,
    function(value)
      ns.DB.profile.cards.opacity = value
      ns.Stack:ApplyBackground()
    end)
  local opacityOptions = Settings.CreateSliderOptions(0, 100, 5)
  opacityOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
    return ("%d%%"):format(value)
  end)
  Settings.CreateSlider(category, opacitySetting, opacityOptions,
    "How dark the panel behind the cards is. 0% shows no panel.")

  -- Quest categories: Show with zone cards / Separate group / Hide, per category.
  -- SettingsPanel is Blizzard's global frame. (This module's table was once a local of the same name,
  -- which hid it: this line errored and the whole panel never registered.)
  SettingsPanel:GetLayout(category):AddInitializer(CreateSettingsListSectionHeaderInitializer("Quest categories"))
  local function modeOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add("show", "Show with zone cards")
    container:Add("separate", "Separate group")
    container:Add("hide", "Hide")
    return container:GetData()
  end
  for _, name in ipairs(ns.Categories.ORDER) do
    local setting = Settings.RegisterProxySetting(category, "QUESTMARK_CATEGORY_" .. name:upper(),
      Settings.VarType.String, ns.Categories.LABELS[name], ns.Categories.DEFAULT_MODES[name],
      function() return ns.Categories:Mode(name) end,
      function(value)
        ns.DB.profile.categories[name] = value
        ns.Stack:Request(true, true)
      end)
    Settings.CreateDropdown(category, setting, modeOptions,
      "Show: as normal cards with this zone's quests. Separate: in their own collapsed group. "
      .. "Hide: not shown (pinned quests always show).")
  end

  Settings.RegisterAddOnCategory(category)
  self.category = category
end

---Change the lock from outside the panel (the header's lock button). Settings.SetValue runs our
---setter and refreshes the checkbox if the panel is open.
---@param locked boolean
function QuestmarkSettings:SetLocked(locked)
  if self.category then
    Settings.SetValue("QUESTMARK_LOCK_CARDS", locked)
  else
    ns.DB.profile.cards.locked = locked
    ns.Stack:ApplyLock()
  end
end

-- Opening goes through C_SettingsUtil.OpenSettingsPanel, which is HasRestrictions on Forever with no
-- stated rule; assume combat is the restriction and don't try then.
function QuestmarkSettings:Open()
  if InCombatLockdown() then
    ns.Debug:Print("Settings can't be opened in combat.")
    return
  end
  if not self.category then
    ns.Debug:Print("Settings failed to load; BugSack has the error.")
    return
  end
  -- apiguard: allow called only out of combat (checked above), from a typed /qm command
  Settings.OpenToCategory(self.category:GetID())
end
