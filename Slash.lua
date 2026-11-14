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
