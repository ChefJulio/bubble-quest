local ADDON_NAME, ns = ...

-- Cleanup only. BubbleMap briefly turned the game's QuestPOIs tracking filter off (2026-11-17), to stop
-- the game's minimap "?" and "!" doubling BubbleQuest's. It didn't: in game the filter was off and
-- filtered out, and the game still drew both (they're quest giver blips with no switch an addon can
-- reach). Worse, the player's state it recorded read "off" (tracking values aren't valid until the game
-- sends them; Blizzard waits for MINIMAP_UPDATE_TRACKING, Mainline/Minimap.lua:891-913), so its restore
-- would have left the filter off for good.
--
-- So this puts QuestPOIs back on (Blizzard keeps it always on: Camelot/MinimapConstants.lua:3-6) once
-- tracking is known, wherever BubbleMap's record of having changed it remains, and forgets the record.
-- Remove once no install has the record (BubbleMap was never released with the feature).

local function filterIndex()
  local wanted = Enum.MinimapTrackingFilter.QuestPOIs
  for index = 1, C_Minimap.GetNumTrackingTypes() do
    local filter = C_Minimap.GetTrackingFilter(index)
    if filter and filter.filterID == wanted then
      return index
    end
  end
  return nil
end

local done = false
local function cleanUp()
  if done or not ns.DB or ns.DB.questPOIs == nil then
    return
  end
  local index = filterIndex()
  if not index then
    return  -- tracking not known yet: the next MINIMAP_UPDATE_TRACKING
  end
  done = true
  local info = C_Minimap.GetTrackingInfo(index)
  if info and not info.active then
    C_Minimap.SetTracking(index, true)
  end
  ns.DB.questPOIs = nil
  ns.DB.hideGameQuestMarkers = nil
end

ns.On("MINIMAP_UPDATE_TRACKING", cleanUp)
ns.On("PLAYER_ENTERING_WORLD", cleanUp)
