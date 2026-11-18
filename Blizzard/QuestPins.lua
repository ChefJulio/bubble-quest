local ADDON_NAME, ns = ...

-- Blizzard's quest pins on the world map (review: an alt showed the game's round "..." and "?" quest
-- pins, the main didn't): they follow the world map filter "Show Quest Objectives", the questPOI CVar
-- (Blizzard_WorldMap/Blizzard_WorldMapTemplates.lua:309, 360), saved per character. BubbleQuest draws
-- its own areas and turn-in "?" (UI/MapAreas.lua, which leaves the "?" to a Blizzard pin where there
-- is one), so with the setting map.hideBlizzardPins (on by default) every character has the filter off
-- and the same map. Each character's own value is kept first (char.questPOIBefore) and put back when
-- the setting goes off. Hiding, not changing Blizzard's code: the same switch the map's menu sets.

local CVAR = "questPOI"

local function apply()
  local map, char = ns.DB.profile.map, ns.DB.char
  if map.hideBlizzardPins then
    if char.questPOIBefore == nil then
      -- apiguard: allow the CVar name is a constant string, never a secret value
      char.questPOIBefore = GetCVar(CVAR) or "1"
    end
    -- apiguard: allow the CVar name is a constant string, never a secret value
    if GetCVarBool(CVAR) then
      -- apiguard: allow constant name and value, never secret values
      SetCVar(CVAR, "0")
    end
  elseif char.questPOIBefore ~= nil then
    -- apiguard: allow constant name; the value is our own saved string ("0"/"1"), never a secret value
    SetCVar(CVAR, char.questPOIBefore)
    char.questPOIBefore = nil
  end
end

local QuestPins = {}
ns.QuestPins = QuestPins

---Apply the setting now (or after combat).
function QuestPins:Apply()
  ns.Combat:Run("questPins", apply)
end

ns.Events:On("PLAYER_LOGIN", function() QuestPins:Apply() end)
ns.Bus:On("ProfileChanged", function() QuestPins:Apply() end)
