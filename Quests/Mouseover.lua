local ADDON_NAME, ns = ...

-- Objective sources learned from world-object mouseover tooltips (spec, In-game learning). Objects
-- have no nameplates, so Quests/Nearby.lua never sees them; but hovering one shows its quest lines,
-- e.g. a Snowdrift: "[10] Data Hoarders / 1/7 Gnomeregan Archival Data" (Forever-new quest 95041,
-- whose item forever-db has no source for; asked for in review).
--
-- Read from the tooltip's typed data (TooltipDataProcessor post-call for TooltipDataType.Object, the
-- documented hook: Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199), never its text: a
-- QuestTitle line (type 17) carries the quest's id, the lines after it name the objectives. When
-- grouped there is one line per player ("1/7 Gnomeregan Archival Data (Name)"), so an objective
-- matches when a line contains its name, the same rule the arrows use. The first line is the
-- object's name. Secret values (combat) are skipped.
--
-- Each match teaches Data/Learned.lua the object as a source ("Gather ... from Snowdrift") and the
-- player's position as a spot for the arrow (mouseover range, so within a few dozen yards).

local LINE_QUEST_TITLE = Enum.TooltipDataLineType.QuestTitle  -- 17

local function readable(value)
  return value ~= nil and not issecretvalue(value)
end

-- Unfinished objectives of a quest in the log whose name appears in the line.
local function matching(quest, text)
  local found = {}
  for _, objective in ipairs(quest.objectives) do
    local name = ns.QuestLog.ObjectiveName(objective)
    if not objective.finished and name and name ~= "" and text:find(name, 1, true) then
      found[#found + 1] = name
    end
  end
  return found
end

local function onObjectTooltip(tooltip, data)
  if tooltip ~= GameTooltip or not data or not data.lines then
    return
  end
  local first = data.lines[1]
  local objectName = first and readable(first.leftText) and first.leftText or nil
  if not objectName or objectName == "" then
    return
  end
  local quest
  for i = 2, #data.lines do
    -- `id` on a QuestTitle line is a real field the annotations don't declare (see Quests/Nearby.lua).
    local line = data.lines[i] --[[@as table]]
    if not readable(line.type) then
      return
    end
    if line.type == LINE_QUEST_TITLE then
      quest = readable(line.id) and ns.QuestLog.quests[line.id] or nil
    elseif quest and readable(line.leftText) then
      for _, name in ipairs(matching(quest, line.leftText)) do
        ns.Learned:RecordSource(quest.questID, name, objectName, "object")
        ns.Learned:Record(quest.questID, name, "object")
      end
    end
  end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, onObjectTooltip)
