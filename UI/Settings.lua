local ADDON_NAME, ns = ...

-- Settings panel in the game's Options > AddOns. Settings are proxies onto the *active profile*,
-- so switching profiles later needs no re-registration.

local SettingsPanel = {
  category = nil,
}
ns.Settings = SettingsPanel

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
function SettingsPanel:Register()
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

  Settings.RegisterAddOnCategory(category)
  self.category = category
end

-- Opening goes through C_SettingsUtil.OpenSettingsPanel, which is HasRestrictions on Forever with no
-- stated rule; assume combat is the restriction and don't try then.
function SettingsPanel:Open()
  if InCombatLockdown() then
    ns.Debug:Print("Settings can't be opened in combat.")
    return
  end
  -- apiguard: allow called only out of combat (checked above), from a typed /qm command
  Settings.OpenToCategory(self.category:GetID())
end
