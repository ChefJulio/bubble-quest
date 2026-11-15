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
  -- was (asked for in review); sources only for unfinished ones.
  for _, objective in ipairs(quest.objectives) do
    add("- " .. (objective.text or "?"), (objective.finished or quest.readyForTurnIn) and GRAY or WHITE, true)
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
  QuestTooltip:AddParty(questID)
  GameTooltip:Show()
end

---Party members' progress on the quest, as the server reports it: the same data Blizzard's tracker
---and quest map show on hover (GameTooltip:SetQuestPartyProgress, Blizzard_QuestObjectiveTracker.lua:149,
---QuestMapFrame.lua:2301), read as lines so they follow ours. Works for every party member, no addon
---needed on their side. Lines are copied as given: their text and colors are Blizzard's.
---@param questID number
function QuestTooltip:AddParty(questID)
  if not IsInGroup() then
    return
  end
  -- omitTitle: we already show it; ignoreActivePlayer: your own progress is the card.
  local data = C_TooltipInfo.GetQuestPartyProgress(questID, true, true)
  local lines = data and data.lines
  if not lines or #lines == 0 then
    return
  end
  add(" ", WHITE)
  add("Party", { NORMAL_FONT_COLOR:GetRGB() })
  for _, line in ipairs(lines) do
    local left, right = line.leftText, line.rightText
    if type(left) == "string" and not issecretvalue(left) then
      local lc = line.leftColor or HIGHLIGHT_FONT_COLOR
      if type(right) == "string" and right ~= "" and not issecretvalue(right) then
        local rc = line.rightColor or HIGHLIGHT_FONT_COLOR
        GameTooltip:AddDoubleLine(left, right, lc.r, lc.g, lc.b, rc.r, rc.g, rc.b)
      else
        GameTooltip:AddLine(left, lc.r, lc.g, lc.b, line.wrapText)
      end
    end
  end
end

function QuestTooltip:Hide()
  GameTooltip:Hide()
end
