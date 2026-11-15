local ADDON_NAME, ns = ...

-- Hover tooltip for a card: what doesn't fit on the card. Title and level, category, a short
-- description, every objective in full with all known item sources, the turn-in, distance, and
-- what the clicks do. Uses the shared GameTooltip, as addons normally do.

local DESCRIPTION_CHARS = 240
local WHITE, GRAY, GREEN, DIM = { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.2, 1, 0.2 }, { 0.5, 0.5, 0.5 }

local QuestTooltip = {}
ns.QuestTooltip = QuestTooltip

local function add(text, color, wrap)
  GameTooltip:AddLine(text, color[1], color[2], color[3], wrap)
end

-- The quest's description from the quest log, shortened. Blizzard's own quest tooltip reads it the
-- same way (Blizzard_GameTooltip/Mainline/GameTooltip.lua:707-709).
local function description(questID)
  local index = C_QuestLog.GetLogIndexForQuestID(questID)
  if not index then
    return nil
  end
  local text = GetQuestLogQuestText(index)
  if type(text) ~= "string" or issecretvalue(text) or text == "" then
    return nil
  end
  if #text > DESCRIPTION_CHARS then
    text = text:sub(1, DESCRIPTION_CHARS):gsub("%s+%S*$", "") .. "..."
  end
  return text
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

  local text = description(questID)
  if text then
    add(text, DIM, true)
  end

  GameTooltip:AddLine(" ")
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

  GameTooltip:AddLine(" ")
  if ns.DB.profile.cards.clickOpensMap then
    add("Left-click: show on the map", DIM)
  end
  add("Right-click: pin, hide, collapse", DIM)
  GameTooltip:Show()
end

function QuestTooltip:Hide()
  GameTooltip:Hide()
end
