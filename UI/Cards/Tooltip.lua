local ADDON_NAME, ns = ...

-- Hover tooltip for a card: what doesn't fit on the card, kept short (the quest description and click
-- help were dropped in review as too wordy). Title, level and category, every objective, the turn-in,
-- distance, all known item sources. Uses the shared GameTooltip, as addons normally do.
--
-- Solo, each objective is one line with your count ("- 0/3 Bear Meat"). Grouped (decided in review),
-- the objective names are listed once, then one uniform row per player, you first: the name and a
-- mini progress bar with the count for each objective, in the same order ("You  [==] 0/3  [==] 2/3").
-- Item sources come after the rows, so nothing sits between your progress and the party's.

local WHITE, GRAY, GREEN = { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.2, 1, 0.2 }
local MAX_TOOLTIP_SOURCES = 4
local BAR_WIDTH, BAR_HEIGHT = 24, 6
local BAR_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Bar\\"  -- tools/make_bars.py

local QuestTooltip = {}
ns.QuestTooltip = QuestTooltip

local function add(text, color, wrap)
  GameTooltip:AddLine(text, color[1], color[2], color[3], wrap)
end

local function colorize(text, color)
  if not color then
    return text
  end
  return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text)
end

-- Sources ------------------------------------------------------------------------------------------

-- Every known source of an item objective: forever-db's, else learned in play.
local function sourcesText(questID, objective)
  if objective.type ~= "item" or objective.finished then
    return nil
  end
  local name = ns.QuestLog.ObjectiveName(objective)
  -- At most MAX_TOOLTIP_SOURCES names, nearest first, then "+N more" (all 20 was a wall of text).
  local sources = ns.ForeverData:ItemSources(questID, name, MAX_TOOLTIP_SOURCES)
  local names, kind, more
  if sources then
    names, kind, more = sources.names, sources.kind, sources.more
  else
    names, kind = ns.Learned:Sources(questID, name)
    more = names and math.max(0, #names - MAX_TOOLTIP_SOURCES) or 0
    if more > 0 then
      names = { unpack(names, 1, MAX_TOOLTIP_SOURCES) }
    end
  end
  if not names or #names == 0 then
    return nil
  end
  local verb = kind == "object" and "Gathered from" or "Dropped by"
  local text = ("%s %s"):format(verb, table.concat(names, ", "))
  return more > 0 and ("%s +%d more"):format(text, more) or text
end

-- Mini bars ----------------------------------------------------------------------------------------
-- Inline textures (|T...|t), one solid-colour file per colour: tinting an inline texture isn't
-- something Blizzard's UI does anywhere, so it isn't relied on.

local function texture(name, width)
  return ("|T%s%s:%d:%d|t"):format(BAR_PATH, name, BAR_HEIGHT, width)
end

---A mini bar and its count: "[====    ] 2/3". done/total nil: no count (e.g. "Talk to ..."), the bar
---is full or empty by `finished`.
---@return string
local function barAndCount(done, total, finished)
  local fraction = (done and total and total > 0) and math.min(1, done / total) or (finished and 1 or 0)
  local filled = math.floor(BAR_WIDTH * fraction + 0.5)
  local parts = {}
  if filled > 0 then
    parts[#parts + 1] = texture(fraction >= 1 and "done" or "fill", filled)
  end
  if filled < BAR_WIDTH then
    parts[#parts + 1] = texture("empty", BAR_WIDTH - filled)
  end
  local bar = table.concat(parts)
  return (done and total) and ("%s %d/%d"):format(bar, done, total) or bar
end

-- Party progress -----------------------------------------------------------------------------------
-- What the server reports for party members on the quest: the same data Blizzard's tracker and quest
-- map show on hover (GameTooltip:SetQuestPartyProgress, Blizzard_QuestObjectiveTracker.lua:149,
-- QuestMapFrame.lua:2301). Works for every party member, no addon needed on their side. It comes as
-- tooltip lines: a member's name, then their objectives ("0/3 Bear Meat", seen in game). A line with
-- a counter is an objective of the member above it; any other line starts a new member.

-- Names of the other group members (party1-4, or raid1-40), for telling a member's name line from a
-- status line like "Ready for turn-in" (seen in review: it was taken for a player).
local function rosterNames()
  local names = {}
  local prefix, count = "party", GetNumSubgroupMembers()
  if IsInRaid() then
    prefix, count = "raid", GetNumGroupMembers()
  end
  for i = 1, count do
    -- apiguard: allow secret names are skipped (issecretvalue below); none readable -> fallback rule
    local name = UnitName(prefix .. i)
    if type(name) == "string" and not issecretvalue(name) then
      names[name] = true
    end
  end
  return names
end

-- Is this line a member's name? Exact, or "Name-Realm" for someone from another realm.
local function isMemberName(text, roster)
  return roster[text] or roster[(text:match("^([^%-]+)%-") or "")] or false
end

-- The game draws member names in the normal gold (NORMAL_FONT_COLOR), statuses in green or grey and
-- counts in white [seen in game: La Lunaa / Ready for turn-in / Not on quest]. A second test besides
-- the roster, which can miss (hidden names, display names that differ).
local function isNameColor(color)
  if not color then
    return false
  end
  local r, g, b = NORMAL_FONT_COLOR:GetRGB()
  return math.abs(color.r - r) < 0.05 and math.abs(color.g - g) < 0.05 and math.abs(color.b - b) < 0.05
end

---@param questID number
---@return table[]? members { name, color, status?, statusColor?, counts = { { name, done, total, used } } };
---  nil when solo
local function partyMembers(questID)
  if not IsInGroup() then
    return nil
  end
  local roster = rosterNames()
  local knowNames = next(roster) ~= nil
  -- omitTitle: we show it; ignoreActivePlayer: your own row comes from the quest log.
  local data = C_TooltipInfo.GetQuestPartyProgress(questID, true, true)
  local members, member = {}, nil
  for _, line in ipairs(data and data.lines or {}) do
    local text = line.leftText
    if type(text) == "string" and not issecretvalue(text) and text ~= "" then
      local done, total = text:match("(%d+)%s*/%s*(%d+)")
      if done and member then
        member.counts[#member.counts + 1] = {
          name = ns.QuestLog.StripProgress(text), done = tonumber(done), total = tonumber(total), used = false,
        }
      elseif not done then
        -- A name starts a member; any other line is the current member's status ("Ready for
        -- turn-in", "Not on quest"). A name: in the roster, or in the name colour. With neither
        -- readable, fall back to: the first such line at the start or after a member's counts.
        local isName = isMemberName(text, roster) or isNameColor(line.leftColor)
          or (not knowNames and not line.leftColor and (not member or #member.counts > 0))
        if isName or not member then
          member = { name = text, color = line.leftColor, counts = {}, texts = {} }
          members[#members + 1] = member
        else
          -- A status, or an objective without a counter ("Scout through the Jasperlode Mine"):
          -- told apart when drawn, against the quest's objectives (addGroupedProgress).
          member.texts[#member.texts + 1] = { text = text, color = line.leftColor }
        end
      end
    end
  end
  return #members > 0 and members or nil
end

-- A member's count for one of our objectives: same name, or one containing the other (the arrows'
-- rule). Marked used, so leftovers can be listed.
local function countFor(member, objectiveName)
  for _, count in ipairs(member.counts) do
    local name = count.name
    if not count.used and (name == objectiveName or name:find(objectiveName, 1, true)
        or objectiveName:find(name, 1, true)) then
      count.used = true
      return count
    end
  end
  return nil
end

-- Finished, by the colour the game draws an objective line in: grey or green, not white.
local function looksFinished(color)
  if not color then
    return false
  end
  local grey = math.abs(color.r - color.g) < 0.05 and math.abs(color.g - color.b) < 0.05 and color.r < 0.8
  local green = color.g > 0.7 and color.r < 0.5 and color.b < 0.5
  return grey or green
end

-- A member's lines without a counter: one naming one of our objectives is their progress on it (an
-- objective with no counter, e.g. exploration: seen in review as plain "Scout through the Jasperlode
-- Mine"), counted against our objective's total; any other line is their status ("Ready for turn-in").
local function sortTexts(member, objectives)
  for _, line in ipairs(member.texts) do
    local matched
    for _, objective in ipairs(objectives) do
      local name = ns.QuestLog.ObjectiveName(objective)
      if name ~= "" and (line.text == name or line.text:find(name, 1, true) or name:find(line.text, 1, true)) then
        matched = objective
        break
      end
    end
    if matched then
      local total = (matched.required and matched.required > 0) and matched.required or 1
      member.counts[#member.counts + 1] = {
        name = ns.QuestLog.ObjectiveName(matched), done = looksFinished(line.color) and total or 0, total = total,
        used = false,
      }
    else
      member.status, member.statusColor = line.text, line.color
    end
  end
end

local function addRow(name, cells)
  GameTooltip:AddDoubleLine(name, table.concat(cells, "   "), 1, 1, 1, 1, 1, 1)
end

-- Grouped: objective names once, then a uniform row per player (you first), then leftovers.
local function addGroupedProgress(quest, members)
  local done = quest.readyForTurnIn
  for _, objective in ipairs(quest.objectives) do
    local c = (objective.finished or done) and GRAY or WHITE
    add("- " .. ns.QuestLog.ObjectiveName(objective), c, true)
  end

  local mine = {}
  for i, objective in ipairs(quest.objectives) do
    local finished = objective.finished or done
    mine[i] = barAndCount(objective.required and objective.required > 0 and objective.fulfilled or nil,
      objective.required and objective.required > 0 and objective.required or nil, finished)
  end
  addRow("You", mine)

  for _, member in ipairs(members) do
    sortTexts(member, quest.objectives)
  end
  for _, member in ipairs(members) do
    local cells = {}
    if #member.counts == 0 and member.status then
      -- No counts, just a status (e.g. "Ready for turn-in"): that's the row.
      cells[1] = colorize(member.status, member.statusColor)
    else
      for i, objective in ipairs(quest.objectives) do
        local count = countFor(member, ns.QuestLog.ObjectiveName(objective))
        cells[i] = count and barAndCount(count.done, count.total) or "-"
      end
    end
    addRow(colorize(member.name, member.color), cells)
  end

  -- Counts that matched none of our objectives (wording differs): listed as given.
  for _, member in ipairs(members) do
    for _, count in ipairs(member.counts) do
      if not count.used then
        add(("%s: %d/%d %s"):format(colorize(member.name, member.color), count.done, count.total, count.name),
          WHITE, true)
      end
    end
  end
end

-- The tooltip ----------------------------------------------------------------------------------------

---@param owner table the card's frame
---@param quest table
function QuestTooltip:Show(owner, quest)
  local questID = quest.questID
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  local color = GetQuestDifficultyColor(quest.level or 0)
  GameTooltip:SetText(quest.title or "?", color.r, color.g, color.b)

  local category = ns.Categories.LABELS[(ns.Categories:For(quest))]
  local facts = { ("Level %d"):format(quest.level or 0), category }
  if quest.tagName then
    facts[#facts + 1] = quest.tagName
  end
  add(table.concat(facts, "  -  "), GRAY)

  -- Objectives show on ready quests too (greyed, done), so the tooltip still says what the quest was.
  local members = #quest.objectives > 0 and partyMembers(questID)
  if members then
    addGroupedProgress(quest, members)
  else
    for _, objective in ipairs(quest.objectives) do
      add("- " .. (objective.text or "?"), (objective.finished or quest.readyForTurnIn) and GRAY or WHITE, true)
    end
  end
  if quest.readyForTurnIn then
    local turnIn = ns.ForeverData:TurnInName(questID)
    add(turnIn and ("Turn in to " .. turnIn) or "Ready to turn in", GREEN)
  elseif #quest.objectives == 0 then
    add("No objectives listed.", GRAY)
  end

  -- Item sources, after the progress: "Bear Meat: Dropped by ..." (unfinished objectives only).
  if not quest.readyForTurnIn then
    for _, objective in ipairs(quest.objectives) do
      local sources = sourcesText(questID, objective)
      if sources then
        add(("%s: %s"):format(ns.QuestLog.ObjectiveName(objective), sources), GRAY, true)
      end
    end
  end

  local nav = ns.Navigation:Compute(quest)
  if nav then
    if nav.inArea then
      add("You're in the area.", GREEN)
    elseif nav.zone then
      add("In " .. nav.zone, GRAY)
    elseif nav.distance then
      add(("%d yards away"):format(nav.distance), GRAY)
    end
  end
  GameTooltip:Show()
end

function QuestTooltip:Hide()
  GameTooltip:Hide()
end
