local ADDON_NAME, ns = ...

-- /qm and /questmark. Forever disables /dump and /run, so the inspection commands here are how we
-- look inside the addon in game.

local print = function(...) ns.Debug:Print(...) end

local function flags(quest)
  local out = {}
  if quest.readyForTurnIn then out[#out + 1] = "ready" end
  if quest.isComplete then out[#out + 1] = "complete" end
  if quest.isFailed then out[#out + 1] = "FAILED" end
  return #out > 0 and table.concat(out, ",") or "active"
end

local function objectivesDone(quest)
  local done = 0
  for _, objective in ipairs(quest.objectives) do
    if objective.finished then done = done + 1 end
  end
  return ("%d/%d"):format(done, #quest.objectives)
end

---@type table<string, {help: string, run: fun(arg: string)}>
local commands = {}

commands[""] = {
  help = "open settings",
  run = function() ns.Settings:Open() end,
}

local function sortedQuests()
  local list = {}
  for _, quest in pairs(ns.QuestLog.quests) do
    list[#list + 1] = quest
  end
  table.sort(list, function(a, b)
    if (a.group or "") ~= (b.group or "") then return (a.group or "") < (b.group or "") end
    return (a.title or "") < (b.title or "")
  end)
  return list
end

local function describeQuest(quest, lines)
  local keys = {}
  for key, value in pairs(quest) do
    if type(value) ~= "table" and key ~= "signature" then keys[#keys + 1] = key end
  end
  table.sort(keys)
  lines[#lines + 1] = ("Quest %d %s"):format(quest.questID, tostring(quest.title))
  for _, key in ipairs(keys) do
    lines[#lines + 1] = ("  %s = %s"):format(key, tostring(quest[key]))
  end
  for i, objective in ipairs(quest.objectives) do
    lines[#lines + 1] = ("  objective %d: type=%s text=%q fulfilled=%s required=%s finished=%s"):format(i,
      tostring(objective.type), objective.text, tostring(objective.fulfilled), tostring(objective.required),
      tostring(objective.finished))
    lines[#lines + 1] = ("    key=%q"):format(objective.key)
  end
end

commands.quests = {
  help = "list every quest Questmark sees (copy window)",
  run = function()
    local list = sortedQuests()
    local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
    local lines = { ("%d quests in the model (game reports %d)"):format(#list, numQuests) }
    for _, quest in ipairs(list) do
      lines[#lines + 1] = ("  %d %s [%s] %s, objectives %s"):format(quest.questID, tostring(quest.title),
        tostring(quest.group), flags(quest), objectivesDone(quest))
    end
    ns.CopyWindow:Show("Questmark: quests", lines)
  end,
}

commands.quest = {
  help = "[questID]: everything about one quest, or every quest if no ID (copy window)",
  run = function(arg)
    local lines = {}
    if arg == "" then
      for _, quest in ipairs(sortedQuests()) do
        describeQuest(quest, lines)
      end
    else
      local quest = ns.QuestLog:Get(tonumber(arg) or 0)
      if not quest then
        print(("No quest %q in the model. /qm quests lists IDs."):format(arg))
        return
      end
      describeQuest(quest, lines)
    end
    ns.CopyWindow:Show("Questmark: quest details", lines)
  end,
}

-- Phase 2 research: which quests does the client place on the player's map (and its parents),
-- and do quest-log headers match the zone names? Decides how "quests in this zone" is computed.
commands.map = {
  help = "where you are, and which quests the game places on this map (copy window)",
  run = function()
    local lines = {}
    lines[#lines + 1] = ("Zone texts: zone=%q real=%q subzone=%q minimap=%q"):format(GetZoneText(), GetRealZoneText(),
      GetSubZoneText(), GetMinimapZoneText())

    local chain, names = {}, {}
    local mapID = C_Map.GetBestMapForUnit("player")
    while mapID and mapID > 0 do
      local info = C_Map.GetMapInfo(mapID)
      if not info then break end
      chain[#chain + 1] = info
      names[info.name] = true
      mapID = info.parentMapID
    end
    if #chain == 0 then
      lines[#lines + 1] = "No player map (instance?)"
    end

    for _, info in ipairs(chain) do
      lines[#lines + 1] = ("Map %d %q type=%s parent=%s"):format(info.mapID, info.name, tostring(info.mapType),
        tostring(info.parentMapID))
      for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(info.mapID) or {}) do
        local quest = ns.QuestLog:Get(poi.questID)
        lines[#lines + 1] = ("  quest %d %s at %.3f,%.3f (map %d) objectives=%d start=%s"):format(poi.questID,
          quest and tostring(quest.title) or "?", poi.x, poi.y, poi.mapID, poi.numObjectives, tostring(poi.isQuestStart))
      end
    end

    lines[#lines + 1] = "Quest-log headers vs this map chain:"
    for _, quest in ipairs(sortedQuests()) do
      lines[#lines + 1] = ("  %d %s [%s] header matches map: %s"):format(quest.questID, tostring(quest.title),
        tostring(quest.group), tostring(names[quest.group or ""] == true))
    end
    ns.CopyWindow:Show("Questmark: map", lines)
  end,
}

commands.copy = {
  help = "recent Questmark chat output, including /qm events lines (copy window)",
  run = function()
    ns.CopyWindow:Show("Questmark: recent output", ns.Debug.history)
  end,
}

commands.events = {
  help = "toggle printing quest and Questmark events as they fire",
  run = function()
    local enabled = not ns.Debug:EventsEnabled()
    ns.Debug:SetEventsEnabled(enabled)
    print("event printing " .. (enabled and "on" or "off"))
  end,
}

commands.tracker = {
  help = "Blizzard tracker state",
  run = function()
    local state = ns.BlizzardTracker:State()
    print(("Blizzard tracker: exists=%s shown=%s protected=%s hooked=%s setting=%s"):format(
      tostring(state.exists), tostring(state.shown), tostring(state.protected), tostring(state.hooked), state.setting))
  end,
}

commands.help = {
  help = "this list",
  run = function()
    local names = {}
    for name in pairs(commands) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      print(("  /qm %s - %s"):format(name, commands[name].help))
    end
  end,
}

SLASH_QUESTMARK1 = "/questmark"
SLASH_QUESTMARK2 = "/qm"
SlashCmdList.QUESTMARK = function(msg)
  local name, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
  local command = commands[name:lower()]
  if not command then
    print(("Unknown command %q."):format(name))
    command = commands.help
  end
  command.run(arg)
end
