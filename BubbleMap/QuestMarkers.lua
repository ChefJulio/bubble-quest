local ADDON_NAME, ns = ...

-- The game's own quest markers on the minimap off, while BubbleQuest draws its own (decided with the
-- user, 2026-11-17): the game's "?" (and, to be confirmed in game, its "!") are drawn by the engine at
-- ranges that change with Blizzard's zoom, so they came and went beside BubbleQuest's and doubled them.
--
-- The only switch is the tracking filter QuestPOIs (Enum.MinimapTrackingFilter; Blizzard keeps it always
-- on and out of its tracking menu, Camelot/MinimapConstants.lua:3-6). It's a saved game setting, so the
-- player's own state is recorded first and put back:
--   - before turning it off, its state goes into BubbleMapDB.questPOIs (written first, so a crash
--     between the two leaves the record, not a lost setting);
--   - put back when the setting is turned off, and at logout (the record is cleared then);
--   - a record still there at login (a crash, a disconnect) is the player's original state: kept, and
--     the filter turned off again.
-- Only with BubbleQuest loaded: without it nothing would draw quest markers.

local QuestMarkers = {}
ns.QuestMarkers = QuestMarkers

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

local function active(index)
  local info = C_Minimap.GetTrackingInfo(index)
  return info ~= nil and info.active == true
end

---Turn the game's quest markers off (recording the player's state first). False when the filter
---isn't there.
---@return boolean
function QuestMarkers:Hide()
  local index = filterIndex()
  if not index then
    return false
  end
  if ns.DB.questPOIs == nil then
    ns.DB.questPOIs = { active = active(index) }
  end
  if active(index) then
    C_Minimap.SetTracking(index, false)
  end
  return true
end

---Put the player's own state back and forget the record.
function QuestMarkers:Restore()
  local record = ns.DB.questPOIs
  if record == nil then
    return
  end
  local index = filterIndex()
  if index and active(index) ~= record.active then
    C_Minimap.SetTracking(index, record.active)
  end
  ns.DB.questPOIs = nil
end

---Apply the setting (BubbleMapDB.hideGameQuestMarkers) and whether BubbleQuest is there.
function QuestMarkers:Apply()
  if ns.Quest and ns.DB.hideGameQuestMarkers then
    self:Hide()
  else
    self:Restore()
  end
end

---One line for /bmap.
---@return string
function QuestMarkers:Describe()
  local index = filterIndex()
  return ("game quest markers %s%s"):format(index and (active(index) and "on" or "off") or "unknown",
    ns.DB.questPOIs and (" (yours: %s)"):format(ns.DB.questPOIs.active and "on" or "off") or "")
end

-- The tracking types are known only once the game has sent them (Blizzard's own tracking button waits
-- for these events too, Mainline/Minimap.lua:891-913).
local applied = false
local function tryApply()
  if not applied and ns.Minimap.active and filterIndex() then
    applied = true
    QuestMarkers:Apply()
  end
end

table.insert(ns.Minimap.onActivate, tryApply)
ns.On("MINIMAP_UPDATE_TRACKING", tryApply)
ns.On("PLAYER_LOGOUT", function()
  QuestMarkers:Restore()
end)
