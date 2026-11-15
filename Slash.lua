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
  local category, rule = ns.Categories:For(quest)
  lines[#lines + 1] = ("  category = %s (by %s; mode %s)"):format(category, rule, ns.Categories:Mode(category))
  local record = ns.ForeverData:Quest(quest.questID)
  if record then
    lines[#lines + 1] = ("  forever-db: type=%s zone=%s (%s) classes=%s repeatable=%s turn-in=%s"):format(
      tostring(record.type), tostring(record.zone), tostring(ns.ForeverData:AreaName(quest.questID)),
      tostring(record.classes), tostring(record.repeatable), tostring(ns.ForeverData:TurnInName(quest.questID)))
  else
    lines[#lines + 1] = "  forever-db: no record"
  end
  local hintData = ns.Hints:Raw(quest.questID)
  for _, hint in ipairs(hintData and hintData.hints or {}) do
    lines[#lines + 1] = ("  hint: %s  [%s]"):format(hint[1], hint[2])
  end
  for name, line in pairs(hintData and hintData.objectives or {}) do
    lines[#lines + 1] = ("  do (%s): %s  [%s]"):format(name, line[1], line[2])
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

-- Phase 5 verification: are the world-coordinate axes right? Prints the player's position and
-- facing, and for each card its target, bearing and distance, with the raw numbers side by side.
commands.where = {
  help = "your world position and every card's arrow target (copy window)",
  run = function()
    local lines = {}
    local north, west, instanceMap = ns.Navigation:PlayerPosition()
    local facing = GetPlayerFacing()
    lines[#lines + 1] = ("Player: UnitPosition = %s, %s on map %s; facing = %s rad (0 = north, counter-clockwise)")
      :format(tostring(north), tostring(west), tostring(instanceMap), tostring(facing))
    lines[#lines + 1] = ("Zone map %s (%s), continent map %s"):format(tostring(ns.Zone.mapID), tostring(ns.Zone.name),
      tostring(ns.Zone.continentID))
    for questID in pairs(ns.Stack.visible) do
      local quest = ns.QuestLog:Get(questID)
      if quest then
        local targets = ns.Navigation.targets[questID]
        local nav = ns.Navigation:Compute(quest)
        lines[#lines + 1] = ("Quest %d %s: %d target points (%s)"):format(questID, tostring(quest.title),
          targets and #targets.points or 0, targets and (targets.spawnBased and "spawns" or "marker") or "none")
        local last = ns.Navigation.current[questID]
        if nav and last then
          lines[#lines + 1] = ("  target %.1f, %.1f -> %.0f yd, arrow %.2f rad (%.0f deg left of facing)%s%s"):format(
            last.x, last.y, nav.distance or -1, nav.angle or 0, math.deg(nav.angle or 0) % 360,
            nav.inArea and ", IN AREA" or "", nav.zone and (", zone " .. nav.zone) or "")
        elseif nav then
          lines[#lines + 1] = ("  no target on this map; zone %s"):format(tostring(nav.zone))
        end
        local marker = ns.Zone.markers[questID]
        if marker and ns.Zone.continentID then
          local m, world = C_Map.GetWorldPosFromMapPos(ns.Zone.continentID, CreateVector2D(marker.x, marker.y))
          lines[#lines + 1] = ("  marker: continent %.3f, %.3f -> world %s, %s on map %s"):format(marker.x, marker.y,
            world and ("%.1f"):format(world.x) or "?", world and ("%.1f"):format(world.y) or "?", tostring(m))
        end
      end
    end
    ns.CopyWindow:Show("Questmark: where", lines)
  end,
}

-- Arrow art preview: every candidate the client has, unrotated (should point up) and turned a
-- quarter to the left, to pick the one that reads best at card size.
local arrowPreview
commands.arrows = {
  help = "preview the arrow styles (pick one in settings)",
  run = function()
    if not arrowPreview then
      arrowPreview = CreateFrame("Frame", "QuestmarkArrowPreview", UIParent, "BasicFrameTemplateWithInset")
      arrowPreview:SetPoint("CENTER")
      arrowPreview:SetFrameStrata("DIALOG")
      arrowPreview.TitleText:SetText("Questmark arrows (Escape closes)")
      tinsert(UISpecialFrames, "QuestmarkArrowPreview")
      local y = -34
      for _, style in ipairs(ns.Card.ARROW_STYLES) do
        local label = arrowPreview:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", 16, y - 6)
        label:SetText(style.label)
        for j, size in ipairs({ 16, 24 }) do
          for k, rotation in ipairs({ 0, math.pi / 2 }) do
            local texture = arrowPreview:CreateTexture(nil, "ARTWORK")
            ns.Card.PrepareRotatingTexture(texture)
            if ns.Card.ApplyArrowStyle(texture, style.key) then
              texture:SetVertexColor(1, 0.82, 0)
            end
            texture:SetSize(size, size)
            texture:SetPoint("TOPLEFT", 230 + (j - 1) * 70 + (k - 1) * 32, y)
            texture:SetRotation(rotation)
          end
        end
        y = y - 36
      end
      arrowPreview:SetSize(390, -y + 12)
    end
    arrowPreview:Show()
  end,
}

-- Research for nameplate-based "you're in the area" (quests with no spawn data, e.g. Rascally
-- Rodents): what the client tells an addon about a creature. Tooltip line fields aren't documented,
-- so this prints every field. Tooltip quest data is secret in combat on Forever: secret values
-- print as <secret> instead of erroring.
local function show(value)
  if issecretvalue(value) then
    return "<secret>"
  end
  return tostring(value)
end

commands.unit = {
  help = "your target: is it part of a quest, and every tooltip line (copy window)",
  run = function()
    if not UnitExists("target") then
      print("Target a creature first.")
      return
    end
    local lines = {
      -- apiguard: allow name only displayed, through show(), which prints secret values as <secret>
      ("Target %s; related to an active quest: %s; in combat: %s"):format(show(UnitName("target")),
        show(C_QuestLog.UnitIsRelatedToActiveQuest("target")), tostring(InCombatLockdown())),
    }
    local data = C_TooltipInfo.GetUnit("target")
    if not data then
      lines[#lines + 1] = "No tooltip data."
    else
      local top = {}
      for key, value in pairs(data) do
        if key ~= "lines" then top[#top + 1] = key .. "=" .. show(value) end
      end
      table.sort(top)
      lines[#lines + 1] = "data: " .. table.concat(top, " ")
      for i, line in ipairs(data.lines or {}) do
        local fields = {}
        for key, value in pairs(line) do
          fields[#fields + 1] = key .. "=" .. show(value)
        end
        table.sort(fields)
        lines[#lines + 1] = ("line %d: %s"):format(i, table.concat(fields, " "))
      end
    end
    ns.CopyWindow:Show("Questmark: unit", lines)
  end,
}

commands.memory = {
  help = "Questmark's memory use, including the bundled quest data",
  run = function()
    UpdateAddOnMemoryUsage()
    local kb = GetAddOnMemoryUsage(ADDON_NAME)
    print(("Questmark uses %.1f MB (forever-db %s)"):format(kb / 1024,
      ns.ForeverData:Available() and tostring(ns.ForeverData:Version()) or "not loaded"))
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
