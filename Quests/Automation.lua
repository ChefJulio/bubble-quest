local ADDON_NAME, ns = ...

-- Auto accept and auto turn-in (settings, both off by default; asked for in review).
--
-- The quest-window functions (AcceptQuest, CompleteQuest, GetQuestReward, SelectAvailableQuest, ...)
-- aren't in Forever's API docs, so the guard can't vouch for them. Evidence they're open to addons:
-- Blizzard's own QuestFrame.lua calls them on this client, and Leatrix Plus's quest automation calls
-- them from an addon and works in game. Its safety rules are followed here (our own code):
--   - turn in only with 0 or 1 reward to choose; never pay gold or currency; never hand over
--     crafting reagents (the player may want them), or items whose info hasn't loaded;
--   - skip NPCs whose dialogue has special options (coloured or "<...>", e.g. "skip the intro");
--   - the override key (Shift, Ctrl or Alt) held while talking: do nothing; or with "only while
--     holding the key", automate only then;
--   - regular, daily and weekly quests are accepted by separate settings;
--   - stand aside while Leatrix Plus's own quest automation is on (both would act on every NPC).
-- Escort-style confirmations (QUEST_ACCEPT_CONFIRM) are left to the player: dismissing that popup
-- would mean calling into Blizzard's StaticPopup code, which taints it.
--
-- A quest picked from an NPC's list but not accepted (log full, requirements) would be picked again
-- every time the list reappears; each quest is tried at most once per RETRY_SECONDS.

local RETRY_SECONDS = 5

-- The greeting list's selectors take the list index on Forever (QuestFrame.lua:474-476, Blizzard's
-- own title buttons); the WoW API annotations still describe the old no-argument versions.
---@type fun(index: number)
local selectActiveQuest = SelectActiveQuest
---@type fun(index: number)
local selectAvailableQuest = SelectAvailableQuest

local Automation = {
  tried = {},  -- [questID] = GetTime() of the last pick from a gossip/greeting list
}
ns.Automation = Automation

local function readable(value)
  return value ~= nil and not issecretvalue(value)
end

local function leatrixAutomates()
  local db = rawget(_G, "LeaPlusDB")
  return C_AddOns.IsAddOnLoaded("Leatrix_Plus") and type(db) == "table" and db.AutomateQuests == "On"
end

local KEY_DOWN = { SHIFT = IsShiftKeyDown, CTRL = IsControlKeyDown, ALT = IsAltKeyDown }

-- The override key: held pauses automation, or with requireKey, holding it is required.
local function keyAllows(settings)
  local isDown = KEY_DOWN[settings.key] or IsShiftKeyDown
  return settings.requireKey == (isDown() == true)
end

-- Setting for accepting a quest of this frequency (Enum.QuestFrequency; nil = regular).
local ACCEPT_SETTING = {
  [Enum.QuestFrequency.Default] = "accept",
  [Enum.QuestFrequency.Daily] = "acceptDaily",
  [Enum.QuestFrequency.Weekly] = "acceptWeekly",
  [Enum.QuestFrequency.ResetByScheduler] = "acceptWeekly",
}

---Is automation of this kind on right now? kind: "turnIn", or "accept" with the quest's frequency.
---@param kind string
---@param frequency number? Enum.QuestFrequency, for "accept"
---@return boolean
function Automation:Active(kind, frequency)
  local settings = ns.DB.profile and ns.DB.profile.automation
  if not settings or leatrixAutomates() or not keyAllows(settings) then
    return false
  end
  if kind == "accept" then
    kind = ACCEPT_SETTING[frequency or Enum.QuestFrequency.Default] or "accept"
  end
  return settings[kind] == true
end

---Is any kind of accepting on (the lists are only scanned then)?
local function acceptingAny()
  return Automation:Active("accept") or Automation:Active("accept", Enum.QuestFrequency.Daily)
    or Automation:Active("accept", Enum.QuestFrequency.Weekly)
end

-- The frequency of the quest in the open details window. QuestIsDaily/QuestIsWeekly aren't in
-- Forever's UI source; Leatrix Plus calls them on this client, but guard them anyway.
local function detailFrequency()
  local isDaily, isWeekly = rawget(_G, "QuestIsDaily"), rawget(_G, "QuestIsWeekly")
  if isDaily and isDaily() then
    return Enum.QuestFrequency.Daily
  elseif isWeekly and isWeekly() then
    return Enum.QuestFrequency.Weekly
  end
  return Enum.QuestFrequency.Default
end

-- Picked recently without result: skip it, so a quest that can't be taken doesn't loop.
local function recentlyTried(questID)
  local at = questID and Automation.tried[questID]
  return at ~= nil and GetTime() - at < RETRY_SECONDS
end

local function markTried(questID)
  if questID then
    Automation.tried[questID] = GetTime()
  end
end

-- Dialogue with special options (coloured text, "<Skip ...>") is the player's to read.
local function hasSpecialGossip()
  for _, option in ipairs(C_GossipInfo.GetOptions() or {}) do
    local name = option.name
    if readable(name) and (name:upper():find("|C", 1, true) or name:find("<", 1, true)) then
      return true
    end
  end
  return false
end

-- Does turning in ask for anything the player might want to keep or decide on?
local function turnInCosts()
  if (GetQuestMoneyToGet() or 0) > 0 or (GetNumQuestCurrencies() or 0) > 0 then
    return true
  end
  for i = 1, GetNumQuestItems() do
    local itemID = select(6, GetQuestItemInfo("required", i))
    if not itemID then
      return true  -- unknown item: be safe
    end
    local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, isCraftingReagent = C_Item.GetItemInfo(itemID)
    if not name or isCraftingReagent then
      return true
    end
  end
  return false
end

-- Events ------------------------------------------------------------------------------------------

-- The quest's details are shown: accept it (or close the window if the game already accepted it).
ns.Events:On("QUEST_DETAIL", function()
  if not Automation:Active("accept", detailFrequency()) then
    return
  end
  if QuestGetAutoAccept() then
    CloseQuest()
  else
    AcceptQuest()
  end
end)

-- "Do you have the items?": continue when complete and free.
ns.Events:On("QUEST_PROGRESS", function()
  if Automation:Active("turnIn") and IsQuestCompletable() and not turnInCosts() then
    CompleteQuest()
  end
end)

-- Rewards: take them when there's nothing to choose.
ns.Events:On("QUEST_COMPLETE", function()
  if not Automation:Active("turnIn") or (GetQuestMoneyToGet() or 0) > 0 then
    return
  end
  local choices = GetNumQuestChoices()
  if choices <= 1 then
    GetQuestReward(choices)
  end
end)

-- An NPC with a gossip list: completed quests first, then new ones.
ns.Events:On("GOSSIP_SHOW", function()
  if hasSpecialGossip() then
    return
  end
  if Automation:Active("turnIn") then
    for _, info in ipairs(C_GossipInfo.GetActiveQuests()) do
      if info.isComplete and info.questID and not recentlyTried(info.questID) then
        markTried(info.questID)
        C_GossipInfo.SelectActiveQuest(info.questID)
        return
      end
    end
  end
  if acceptingAny() then
    for _, info in ipairs(C_GossipInfo.GetAvailableQuests()) do
      if info.questID and not recentlyTried(info.questID) and Automation:Active("accept", info.frequency) then
        markTried(info.questID)
        C_GossipInfo.SelectAvailableQuest(info.questID)
        return
      end
    end
  end
end)

-- An NPC with the older quest greeting list (no gossip): same, by list index. No quest IDs here, so
-- the retry guard keys on the title.
ns.Events:On("QUEST_GREETING", function()
  if Automation:Active("turnIn") then
    for i = 1, GetNumActiveQuests() do
      local title, isComplete = GetActiveTitle(i)
      if title and isComplete and not recentlyTried(title) then
        markTried(title)
        selectActiveQuest(i)
        return
      end
    end
  end
  if acceptingAny() then
    for i = 1, GetNumAvailableQuests() do
      local title = GetAvailableTitle(i)
      local _, frequency = GetAvailableQuestInfo(i)
      if title and not recentlyTried(title) and Automation:Active("accept", frequency) then
        markTried(title)
        selectAvailableQuest(i)
        return
      end
    end
  end
end)
