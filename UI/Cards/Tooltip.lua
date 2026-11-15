local ADDON_NAME, ns = ...

-- Hover tooltip for a card: what doesn't fit on the card, kept short (the quest description and click
-- help were dropped in review as too wordy). Title, level and category, every objective in full with
-- all known item sources, the turn-in, distance, and party members' progress when grouped. Uses the
-- shared GameTooltip, as addons normally do.

local WHITE, GRAY, GREEN = { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.2, 1, 0.2 }
local MAX_TOOLTIP_SOURCES = 4

local QuestTooltip = {}
ns.QuestTooltip = QuestTooltip

local function add(text, color, wrap)
  GameTooltip:AddLine(text, color[1], color[2], color[3], wrap)
end

-- Every known source of an item objective: forever-db's, else learned in play.
local function sourcesLine(questID, objective)
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

-- Party progress --------------------------------------------------------------------------------
-- What the server reports for party members on the quest: the same data Blizzard's tracker and
-- quest map show on hover (GameTooltip:SetQuestPartyProgress, Blizzard_QuestObjectiveTracker.lua:149,
-- QuestMapFrame.lua:2301). Works for every party member, no addon needed on their side. It comes as
-- tooltip lines: a member's name, then their objectives ("0/3 Bear Meat", seen in game). A line with
-- a counter is an objective of the member above it; any other line starts a new member.

local function colorize(text, color)
  if not color then
    return text
  end
  return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text)
end

---@param questID number
---@return table? { members = { { name, color, counts = { [objective name] = "1/3" } } },
---  unmatched = { line text } (filled in by partyColumn's caller); nil when solo or nothing known
local function partyProgress(questID)
  if not IsInGroup() then
    return nil
  end
  -- omitTitle: we show it; ignoreActivePlayer: your own progress is the left column.
  local data = C_TooltipInfo.GetQuestPartyProgress(questID, true, true)
  local members, member = {}, nil
  for _, line in ipairs(data and data.lines or {}) do
    local text = line.leftText
    if type(text) == "string" and not issecretvalue(text) and text ~= "" then
      local done, total = text:match("(%d+)%s*/%s*(%d+)")
      if done and member then
        member.counts[ns.QuestLog.StripProgress(text)] = { text = done .. "/" .. total, used = false }
      elseif not done then
        member = { name = text, color = line.leftColor, counts = {} }
        members[#members + 1] = member
      end
    end
  end
  if #members == 0 then
    return nil
  end
  return { members = members, unmatched = {} }
end

-- Every member's count for one of our objectives, side by side: "Blinken 1/3  Bob 0/3". Matched by
-- name, or one name containing the other (the arrows' rule). Matched counts are marked used, so the
-- leftovers can be listed after the objectives.
local function partyColumn(party, objectiveName)
  local parts = {}
  for _, member in ipairs(party.members) do
    for name, count in pairs(member.counts) do
      if name == objectiveName or name:find(objectiveName, 1, true) or objectiveName:find(name, 1, true) then
        count.used = true
        parts[#parts + 1] = ("%s %s"):format(colorize(member.name, member.color), count.text)
        break
      end
    end
  end
  return #parts > 0 and table.concat(parts, "  ") or nil
end

-- After the objectives: counts that matched none of ours, as "Name: 1/3 Thing".
local function collectUnmatched(party)
  for _, member in ipairs(party.members) do
    for name, count in pairs(member.counts) do
      if not count.used then
        party.unmatched[#party.unmatched + 1] = ("%s: %s %s"):format(colorize(member.name, member.color),
          count.text, name)
      end
    end
  end
end

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

  -- Objectives show on ready quests too (greyed, done), so the tooltip still says what the quest
  -- was (asked for in review); sources only for unfinished ones. Grouped, each party member's count
  -- for the objective sits on the same line, on the right (asked for in review).
  local party = partyProgress(questID)
  for _, objective in ipairs(quest.objectives) do
    local text = "- " .. (objective.text or "?")
    local c = (objective.finished or quest.readyForTurnIn) and GRAY or WHITE
    local right = party and partyColumn(party, ns.QuestLog.ObjectiveName(objective))
    if right then
      GameTooltip:AddDoubleLine(text, right, c[1], c[2], c[3], 1, 1, 1)
    else
      add(text, c, true)
    end
    local sources = not quest.readyForTurnIn and sourcesLine(questID, objective)
    if sources then
      add("    " .. sources, GRAY, true)
    end
  end
  if quest.readyForTurnIn then
    local turnIn = ns.ForeverData:TurnInName(questID)
    add(turnIn and ("Turn in to " .. turnIn) or "Ready to turn in", GREEN)
  elseif #quest.objectives == 0 then
    add("No objectives listed.", GRAY)
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
  -- Party counts no objective of ours matched (wording differs): listed under the rest.
  if party then
    collectUnmatched(party)
  end
  if party and #party.unmatched > 0 then
    add(" ", WHITE)
    for _, line in ipairs(party.unmatched) do
      add(line, WHITE, true)
    end
  end
  GameTooltip:Show()
end

function QuestTooltip:Hide()
  GameTooltip:Hide()
end
