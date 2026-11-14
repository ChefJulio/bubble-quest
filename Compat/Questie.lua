local ADDON_NAME, ns = ...

-- Questmark runs alongside Questie and replaces only its quest tracker. If Questie's tracker is on,
-- say once (per character) where to turn it off. Never change Questie's settings ourselves.
--
-- Questie is an AceAddon global; its tracker toggle is Questie.db.profile.trackerEnabled
-- (Questie/Modules/Options/NativeOptions/NativeOptionsTracker.lua:101). Every step is guarded, so a
-- Questie update that renames things means "no notice", never an error.

local NOTICE = "questie-tracker"

local function questieTrackerEnabled()
  local questie = rawget(_G, "Questie")
  local profile = type(questie) == "table" and questie.db and questie.db.profile
  return type(profile) == "table" and profile.trackerEnabled == true
end

local checked = false

ns.Events:On("PLAYER_ENTERING_WORLD", function()
  if checked then
    return
  end
  checked = true
  -- Questie finishes setting up its database during login; check once things have settled.
  C_Timer.After(5, function()
    local notices = ns.DB.char.notices
    if notices[NOTICE] or not questieTrackerEnabled() then
      return
    end
    notices[NOTICE] = true
    ns.Debug:Print("Questie's quest tracker is also on. Questmark replaces it: turn it off in "
      .. "Questie's options under Tracker > Enable Tracker.")
  end)
end)
