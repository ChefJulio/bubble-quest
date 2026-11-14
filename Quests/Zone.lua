local ADDON_NAME, ns = ...

-- Which quests are "in this zone", and which zone every other quest belongs to.
--
-- Uses the client's own quest map markers (verified on Forever with /qm map):
--   C_QuestLog.GetQuestsOnMap(zone map)       quests in the player's zone
--   C_QuestLog.GetQuestsOnMap(continent map)  every quest on the continent, each with its zone map
-- Quests without a marker (e.g. Camping) fall back to their quest-log header.
--
-- STOPGAP until phase 4: forever-db gives every quest its zone (quest.zone_area). This module is
-- the only place that decides zone membership, so that swap touches only this file.

local Zone = {
  mapID = nil,       -- the player's zone map (first Zone-type map up the chain), nil in instances
  name = nil,        -- its name
  inZone = {},       -- [questID] = true: has a marker on the player's zone map
  questZone = {},    -- [questID] = zone name, from the continent query
}
ns.Zone = Zone

local mapNames = {}
local function mapName(mapID)
  if mapNames[mapID] == nil then
    local info = C_Map.GetMapInfo(mapID)
    mapNames[mapID] = info and info.name or false
  end
  return mapNames[mapID] or nil
end

-- Re-read the player's position in the map tree and the quest markers. Cheap: a few map lookups and
-- two marker queries.
function Zone:Update()
  local zoneInfo, continentID
  local mapID = C_Map.GetBestMapForUnit("player")
  while mapID and mapID > 0 do
    local info = C_Map.GetMapInfo(mapID)
    if not info then
      break
    end
    if not zoneInfo and info.mapType == Enum.UIMapType.Zone then
      zoneInfo = info
    elseif info.mapType == Enum.UIMapType.Continent then
      continentID = info.mapID
    end
    mapID = info.parentMapID
  end
  self.mapID = zoneInfo and zoneInfo.mapID
  self.name = zoneInfo and zoneInfo.name

  wipe(self.inZone)
  wipe(self.questZone)
  if continentID then
    for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(continentID) or {}) do
      self.questZone[poi.questID] = mapName(poi.mapID)
    end
  end
  if self.mapID then
    for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(self.mapID) or {}) do
      self.inZone[poi.questID] = true
      self.questZone[poi.questID] = self.questZone[poi.questID] or self.name
    end
  end
end

---@param quest table from ns.QuestLog
---@return boolean
function Zone:IsInZone(quest)
  if self.inZone[quest.questID] then
    return true
  end
  if self.questZone[quest.questID] then
    return false  -- has a marker, in another zone
  end
  local group = quest.group
  return group ~= nil and (group == self.name or group == GetSubZoneText())
end

---Heading for a quest in the Elsewhere group.
---@param quest table
---@return string
function Zone:NameFor(quest)
  return self.questZone[quest.questID] or quest.group or "Other"
end
