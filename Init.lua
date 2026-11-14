local ADDON_NAME, ns = ...

-- Startup order: every module registered its events when its file loaded. SavedVariables become
-- available at our ADDON_LOADED, before PLAYER_LOGIN and PLAYER_ENTERING_WORLD, so anything that
-- needs settings can rely on ns.DB from those events on.

local loaded = false

ns.Events:On("ADDON_LOADED", function(name)
  if loaded or name ~= ADDON_NAME then
    return
  end
  loaded = true
  ns.DB:Load()
  ns.Settings:Register()
end)
