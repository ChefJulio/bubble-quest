local ADDON_NAME, ns = ...

-- Quest lines on the game's own tooltips (Questie parity, docs/design/questie-parity.md "Tooltips"):
--   NPCs   a quest giver lists the quests it offers you (the engine behind the maps' "!",
--          Quests/Available.lua: level, class, prerequisites, what it told you it doesn't offer); the
--          NPC a ready quest is turned in to lists those quests.
--   Items  an item that starts a quest names it (and says when you've done it); an item a quest in
--          your log needs names that quest and your count.
--
-- Read from the tooltip's typed data (TooltipDataProcessor post-calls, the documented hook:
-- Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199), as Quests/Mouseover.lua does. An NPC is
-- known by its name only: its GUID, so its ID, is secret for any unit outside your group
-- (SecretWhenUnitIdentityRestricted, SecretPredicatesDocumentation.lua:130-133). Same-named givers are
-- told apart by the spawn nearest you. In combat the tooltip's data is secret too: nothing is added.
-- Holding Ctrl leaves these lines out, as with BubbleQuest's own tooltips (UI/Tooltips.lua).

local LINE_UNIT_NAME = Enum.TooltipDataLineType.UnitName  -- 2
local LINE_QUEST_TITLE = Enum.TooltipDataLineType.QuestTitle  -- 17
local HEADER = { 0.4, 0.8, 1 }       -- "BubbleQuest" blue, as the tracker's Share next
local DONE_COLOR = { 0.5, 0.5, 0.5 }
local WARN = { 1, 0.5, 0.15 }        -- "Keep for ...: don't sell", the orange of a warning

local WorldTooltips = {}
ns.WorldTooltips = WorldTooltips

local function readable(value)
  return value ~= nil and not issecretvalue(value)
end

local function settings()
  return ns.DB.profile and ns.DB.profile.tooltips
end

local function ours(tooltip)
  return (tooltip == GameTooltip or tooltip == rawget(_G, "ItemRefTooltip")) and not ns.Tooltips:Suppressed()
end

local function level(questID, fallback)
  local l = fallback or C_QuestLog.GetQuestDifficultyLevel(questID)
  return (l and l > 0) and l or UnitLevel("player")
end

-- NPCs ---------------------------------------------------------------------------------------------

-- The giver called `name` nearest the player (several NPCs can share a name: guards, vendors).
local function giverNamed(name)
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  local best, bestYards
  for _, giver in ipairs(ns.Available.givers) do
    if giver.kind == "npc" and giver.name == name then
      local yards = math.huge
      if north then
        for _, p in ipairs(giver.points or {}) do
          if p.map == instanceMap then
            yards = math.min(yards, (p.x - north) ^ 2 + (p.y - west) ^ 2)
          end
        end
      end
      if not best or yards < bestYards then
        best, bestYards = giver, yards
      end
    end
  end
  return best
end

-- Who takes a quest in, by name: forever-db's finisher and QuestieDB's (they can differ in spelling
-- or coverage). Cached: a quest's finisher doesn't change.
local turnInNamesCache = {}
local function turnInNames(questID)
  local names = turnInNamesCache[questID]
  if not names then
    names = {}
    local forever = ns.ForeverData:TurnInName(questID)
    if forever then
      names[forever] = true
    end
    if ns.QuestieData:Available() then
      local finishers = ns.QuestieData.Get("QuestDB", "finishedBy", questID)
      for _, npcID in ipairs(type(finishers) == "table" and finishers[1] or {}) do
        local name = ns.QuestieData.Get("NpcDB", "name", npcID)
        if type(name) == "string" then
          names[name] = true
        end
      end
    end
    turnInNamesCache[questID] = names
  end
  return names
end

local function onUnit(tooltip, data)
  local opts = settings()
  if not (opts and opts.npcs and ours(tooltip) and data and data.lines) then
    return
  end
  local name
  local listed = {}  -- quests the game's own lines already name (QuestTitle lines carry the quest's id)
  for _, line in ipairs(data.lines) do
    local lineType = line.type
    if readable(lineType) then
      if lineType == LINE_UNIT_NAME and not name then
        name = readable(line.leftText) and line.leftText or nil
      elseif lineType == LINE_QUEST_TITLE then
        -- `id` on a QuestTitle line is a real field the annotations don't declare (Quests/Nearby.lua).
        local id = (line --[[@as table]]).id
        if readable(id) then
          listed[id] = true
        end
      end
    end
  end
  if not name then
    return  -- secret (combat), or no name line
  end
  -- Quest items this mob drops that the game's own lines leave out (review: a Young Goretusk listed
  -- Westfall Stew's Goretusk Snout, not Goretusk Liver Pie's liver, which it drops too): each
  -- unfinished item objective whose sources (forever-db, else learned: DoLine.ItemSources) name it,
  -- of a quest the game didn't list, in the game's own style, with the drop chance when known.
  -- For quests the game does list, its line is its own text (not ours to change: never modify Blizzard
  -- UI), so the drop chance goes on a short line of ours after it (review: "it doesn't show the drop
  -- chance for the quest item I need"). A tooltip only grows at the bottom.
  local drops, chances = {}, {}
  for questID, quest in pairs(ns.QuestLog.quests) do
    if not quest.isComplete then
      for _, objective in ipairs(quest.objectives or {}) do
        if objective.type == "item" and not objective.finished then
          local itemName = ns.QuestLog.ObjectiveName(objective)
          local sources = ns.DoLine.ItemSources(questID, itemName)
          if sources and sources.kind == "npc" and tContains(sources.names, name) then
            local chance = sources.chances and sources.chances[name]
            if not listed[questID] then
              drops[#drops + 1] = { quest = quest, objective = objective, itemName = itemName, chance = chance }
            elseif chance then
              chances[#chances + 1] = { itemName = itemName, chance = chance }
            end
          end
        end
      end
    end
  end
  for _, c in ipairs(chances) do
    tooltip:AddLine(("%s: %s drop chance"):format(c.itemName, ns.DoLine.ChanceText(c.chance)), 0.6, 0.6, 0.6)
  end
  if #chances > 0 and #drops == 0 then
    tooltip:Show()
  end
  if #drops > 0 then
    local lastQuest
    for _, drop in ipairs(drops) do
      if drop.quest ~= lastQuest then
        tooltip:AddLine(drop.quest.title or "?", 1, 0.82, 0)
        lastQuest = drop.quest
      end
      local counted = drop.objective.required and drop.objective.required > 0
      local text = counted and ("  %d/%d %s"):format(drop.objective.fulfilled or 0, drop.objective.required, drop.itemName)
        or ("  " .. drop.itemName)
      if drop.chance then
        text = text .. " |cff999999(" .. ns.DoLine.ChanceText(drop.chance) .. ")|r"
      end
      tooltip:AddLine(text, 1, 1, 1)
    end
    tooltip:Show()
  end
  -- Ready quests turned in to this NPC.
  local ready = {}
  for questID, quest in pairs(ns.QuestLog.quests) do
    if quest.isComplete and turnInNames(questID)[name] then
      ready[#ready + 1] = quest
    end
  end
  -- Quests it offers you (low-level ones as the map shows them: setting map.availableTrivial).
  local offers = {}
  local giver = giverNamed(name)
  local trivialToo = ns.DB.profile.map.availableTrivial
  for _, q in ipairs(giver and giver.quests or {}) do
    if trivialToo or not q.trivial then
      offers[#offers + 1] = q
    end
  end
  if #ready == 0 and #offers == 0 then
    return
  end
  tooltip:AddLine(" ")
  for _, quest in ipairs(ready) do
    tooltip:AddDoubleLine(("? [%d] %s"):format(level(quest.questID, quest.level), quest.title or "?"),
      "Ready", 1, 0.82, 0, 0.3, 1, 0.3)
  end
  for _, q in ipairs(offers) do
    ns.MapAvailable.QuestLine(tooltip, q)
  end
  tooltip:Show()  -- resize to the new lines
end

-- Items --------------------------------------------------------------------------------------------

-- Quests started by an item: [itemID] = { record }, from the index (Available.records), built once
-- per index (a few thousand records, on the first item tooltip).
local startsIndex, startsFor
local function questsStartedBy(itemID)
  local records = ns.Available.records
  if not records then
    return nil
  end
  if startsFor ~= records then
    startsIndex, startsFor = {}, records
    for _, r in pairs(records) do
      for _, id in ipairs(r.items or {}) do
        startsIndex[id] = startsIndex[id] or {}
        table.insert(startsIndex[id], r)
      end
    end
  end
  return startsIndex[itemID]
end

local function onItem(tooltip, data)
  local opts = settings()
  if not (opts and opts.items and ours(tooltip) and data and readable(data.id)) then
    return
  end
  local itemID = data.id
  local added = false
  local function header()
    if not added then
      tooltip:AddLine(" ")
      added = true
    end
  end
  for _, r in ipairs(questsStartedBy(itemID) or {}) do
    header()
    local done = ns.Available.completed[r.questID] or C_QuestLog.IsQuestFlaggedCompleted(r.questID)
    local color = done and DONE_COLOR or HEADER
    tooltip:AddDoubleLine(("Starts a quest: [%d] %s"):format(level(r.questID, r.level), r.name or "?"),
      done and "Done" or "", color[1], color[2], color[3], 0.5, 0.5, 0.5)
  end
  -- Quests in your log that need it: an item objective named as the item, finished ones too (review:
  -- a Waterlogged Axe at 1/1 said nothing, and that's when you wonder what it's for); the count green
  -- when done. An item a vendor would buy (a Goretusk Snout, a pelt) gets a warning instead (review:
  -- "shouldn't the tooltip be more upfront that you should not sell this"): selling it, even at 3/3,
  -- takes the count down and the quest back from ready. Grey quest items can't be sold: plain "For:".
  local itemName = C_Item.GetItemNameByID(itemID)
  if readable(itemName) and itemName then
    -- apiguard: allow the item ID comes from the tooltip's data, read only when not secret (readable)
    local sellPrice = select(11, C_Item.GetItemInfo(itemID))
    local sellable = readable(sellPrice) and sellPrice > 0
    for questID, quest in pairs(ns.QuestLog.quests) do
      for _, objective in ipairs(quest.objectives or {}) do
        if objective.type == "item" and ns.QuestLog.ObjectiveName(objective) == itemName then
          header()
          local count = objective.finished and { 0.3, 1, 0.3 } or { 1, 1, 1 }
          local title = ("[%d] %s"):format(level(questID, quest.level), quest.title or "?")
          local progress = ("%d/%d"):format(objective.fulfilled or 0, objective.required or 0)
          if sellable then
            tooltip:AddDoubleLine(("Keep for %s: don't sell"):format(title), progress, WARN[1], WARN[2], WARN[3],
              count[1], count[2], count[3])
          else
            tooltip:AddDoubleLine("For: " .. title, progress, HEADER[1], HEADER[2], HEADER[3],
              count[1], count[2], count[3])
          end
        end
      end
    end
  end
  if added then
    tooltip:Show()
  end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnit)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
