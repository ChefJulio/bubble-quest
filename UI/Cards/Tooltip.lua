local ADDON_NAME, ns = ...

-- Hover tooltip for a card: what doesn't fit on the card, kept short (the quest description and click
-- help were dropped in review as too wordy). Title, level and category, every objective in full with
-- all known item sources, the turn-in, distance. Uses the shared GameTooltip, as addons normally do.

local WHITE, GRAY, GREEN = { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.2, 1, 0.2 }

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
  local sources = ns.ForeverData:ItemSources(questID, name, 20)
  local names = sources and sources.names or ns.Learned:Sources(questID, name)
  if not names or #names == 0 then
    return nil
  end
  local verb = sources and sources.kind == "object" and "Gathered from" or "Dropped by"
  return ("%s %s"):format(verb, table.concat(names, ", "))
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

  if quest.readyForTurnIn then
    local turnIn = ns.ForeverData:TurnInName(questID)
    add(turnIn and ("Turn in to " .. turnIn) or "Ready to turn in", GREEN)
  else
    for _, objective in ipairs(quest.objectives) do
      add("- " .. (objective.text or "?"), objective.finished and GRAY or WHITE, true)
      local sources = sourcesLine(questID, objective)
      if sources then
        add("    " .. sources, GRAY, true)
      end
    end
    if #quest.objectives == 0 then
      add("No objectives listed.", GRAY)
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
