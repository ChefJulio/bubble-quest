local ADDON_NAME, ns = ...

-- Sharing quests with the party (review): which quests party members don't have (the card's "+2"),
-- sharing one (the card menu, the "+2"), and "Share next": one click shares the next quest in this zone
-- someone lacks; when that share fails for everyone (already done, not eligible, log full, ...), it
-- goes straight on to the next one, until a share reaches someone or none are left.
--
-- Who lacks a quest: C_QuestLog.IsUnitOnQuest per party member. Who CAN'T take it is only known from
-- the server's replies to a share, system chat lines built from the client's own strings
-- (ERR_QUEST_PUSH_*: "%s has completed that quest.", "Sharing quest with %s..."), matched as patterns
-- so it works in every language. Lasting refusals are remembered for the session, so the "+2" stops
-- counting them.
--
-- Sharing (QuestLogPushQuest) is restricted in combat (Patch 12.0.0 API notes; blocked in game): out
-- of combat only; a click in combat queues it for the end of combat. The automatic "next" after a
-- failed share isn't a click of its own [Assumes allowed out of combat: Blizzard's notes restrict
-- sharing in combat only; unverified in game].

local REPLY_WINDOW = 4    -- seconds to wait for every member's reply to a share
local NEXT_DELAY = 0.3    -- before sharing the next quest after a failed one

-- Sharer-side replies (enUS.ts: ERR_QUEST_PUSH_*_S; the _TO_RECIPIENT ones go to the other player).
-- outcome: "sharing" (reached them), "accepted", "declined", "lasting" (can't take it this session),
-- "transient" (busy, dead, too far: may work later). Lines without a name apply to everyone.
local REPLIES = {
  SUCCESS = "sharing", ACCEPTED = "accepted", DECLINED = "declined", ONQUEST = "lasting",
  ALREADY_DONE = "lasting", CLASS = "lasting", RACE = "lasting", HIGH_LEVEL = "lasting",
  LOW_LEVEL = "lasting", INVALID = "lasting", PREREQUISITE = "lasting", HIGH_FACTION = "lasting",
  LOW_FACTION = "lasting", WRONG_FACTION = "lasting", NOT_DAILY = "lasting",
  DIFFERENT_SERVER_DAILY = "lasting", EXPANSION = "lasting", NEW_PLAYER_EXPERIENCE = "lasting",
  WRONG_COVENANT = "lasting", NOT_GARRISON_OWNER = "lasting", CROSS_FACTION_RESTRICTED = "lasting",
  NOT_ALLOWED = "lasting",
  LOG_FULL = "transient", BUSY = "transient", DEAD = "transient", TOO_FAR = "transient",
  TIMER_EXPIRED = "transient", NOT_IN_PARTY = "transient",
}

local Party = {
  refused = {},    -- [name] = { [questID] = reply key }: lasting refusals this session
  patterns = nil,  -- { { pattern, outcome, key, named } }
  chain = { tried = {} },  -- Share next: quests already offered this round; pending share
}
ns.Party = Party

-- QuestLogPushQuest with the log-index argument Forever's quest map passes (QuestMapFrame.lua:1452);
-- the WoW API annotations describe the old no-argument version.
-- Called only out of combat: Party:Push checks, and the queue runs after combat.
---@type fun(questLogIndex: number)
local questLogPushQuest = QuestLogPushQuest  -- apiguard: allow combat-restricted; out of combat only

local function readable(value)
  return value ~= nil and not issecretvalue(value)
end

-- Party members (not the player), as { unit, name }; names unreadable are left out.
function Party:Members()
  local members = {}
  for i = 1, GetNumSubgroupMembers() do
    local unit = "party" .. i
    -- apiguard: allow secret names are skipped (readable)
    local name = UnitName(unit)
    if readable(name) and UnitIsConnected(unit) then
      members[#members + 1] = { unit = unit, name = name }
    end
  end
  return members
end

---Names of party members who don't have the quest and haven't refused it for good this session.
---@param questID number
---@return string[]
function Party:Missing(questID)
  local missing = {}
  if not IsInGroup() then
    return missing
  end
  for _, member in ipairs(self:Members()) do
    local onQuest = C_QuestLog.IsUnitOnQuest(member.unit, questID)
    local refused = self.refused[member.name] and self.refused[member.name][questID]
    if readable(onQuest) and not onQuest and not refused then
      missing[#missing + 1] = member.name
    end
  end
  return missing
end

---Can the quest be offered to anyone right now (shareable, someone lacks it)?
---@param questID number
---@return boolean
function Party:CanShare(questID)
  return IsInGroup() and C_QuestLog.IsPushableQuest(questID) and #self:Missing(questID) > 0
end

-- Sharing ----------------------------------------------------------------------------------------------

local function pushNow(questID)
  local index = C_QuestLog.GetLogIndexForQuestID(questID)
  if not index or not IsInGroup() then
    return false
  end
  questLogPushQuest(index)
  PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
  Party.lastShared = questID  -- replies (accepted, declined) can arrive after the chain moved on
  return true
end

---Share a quest with the party: now, or when combat ends (said in chat).
---@param questID number
function Party:Push(questID)
  if not InCombatLockdown() then
    pushNow(questID)
    return
  end
  local title = C_QuestLog.GetTitleForQuestID(questID) or "quest"
  ns.Debug:Print(("Sharing %s when combat ends."):format(title))
  ns.Combat:Run("share:" .. questID, function() pushNow(questID) end)
end

-- Share next ------------------------------------------------------------------------------------------

-- The next quest in this zone someone lacks, not yet offered this round, in quest log order.
local function nextCandidate(tried)
  local best
  for questID, quest in pairs(ns.QuestLog.quests) do
    if not tried[questID] and ns.Zone:IsInZone(quest) and Party:CanShare(questID)
        and (not best or (quest.order or 0) < (best.order or 0)) then
      best = quest
    end
  end
  return best
end

local function finishPending()
  local chain = Party.chain
  local pending = chain.pending
  chain.pending = nil
  if pending and not pending.reached and not InCombatLockdown() then
    -- Nobody could take it: straight on to the next one (review).
    C_Timer.After(NEXT_DELAY, function() Party:ShareNext(true) end)
  end
end

---Share the next quest in this zone that a party member lacks. `continuing`: called after a failed
---share (not a new click), so an empty list ends quietly-ish.
---@param continuing boolean?
function Party:ShareNext(continuing)
  if InCombatLockdown() then
    ns.Debug:Print("Sharing isn't possible in combat.")
    return
  end
  local chain = self.chain
  if chain.pending then
    return  -- still waiting for replies to the last one
  end
  local quest = nextCandidate(chain.tried)
  if not quest then
    if not continuing or next(chain.tried) then
      ns.Debug:Print("No more quests in this zone to share with your party.")
    end
    wipe(chain.tried)  -- the next click starts a new round
    return
  end
  chain.tried[quest.questID] = true
  local expected = {}
  for _, name in ipairs(self:Missing(quest.questID)) do
    expected[name] = true
  end
  chain.pending = { questID = quest.questID, expected = expected, reached = false }
  if not pushNow(quest.questID) then
    chain.pending = nil
    return
  end
  local pending = chain.pending
  C_Timer.After(REPLY_WINDOW, function()
    if chain.pending == pending then
      finishPending()
    end
  end)
end

-- Replies -----------------------------------------------------------------------------------------------

local function buildPatterns()
  local patterns = {}
  for key, outcome in pairs(REPLIES) do
    local text = rawget(_G, "ERR_QUEST_PUSH_" .. key .. "_S")
    if type(text) == "string" then
      -- Escape Lua pattern characters, then turn the client's "%s" into a capture.
      local escaped = text:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
      local named = escaped:find("%%s") ~= nil
      local pattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
      patterns[#patterns + 1] = { pattern = pattern, outcome = outcome, key = key, named = named }
    end
  end
  return patterns
end

ns.Events:On("CHAT_MSG_SYSTEM", function(message)
  if not readable(message) then
    return
  end
  Party.patterns = Party.patterns or buildPatterns()
  for _, p in ipairs(Party.patterns) do
    local name = message:match(p.pattern)
    if name or (not p.named and message:find(p.pattern)) then
      local pending = Party.chain.pending
      local questID = pending and pending.questID or Party.lastShared
      if p.outcome == "lasting" and questID and name then
        Party.refused[name] = Party.refused[name] or {}
        Party.refused[name][questID] = p.key
        ns.Stack:Request(false)  -- the card's "+N" drops them
      end
      if pending then
        if p.outcome == "sharing" or p.outcome == "accepted" then
          pending.reached = true
        end
        if name then
          pending.expected[name] = nil
        end
        if not p.named or not next(pending.expected) then
          finishPending()
        end
      end
      return
    end
  end
end)

-- The card's "+N" follows the party: who's in it, and their quest logs.
ns.Events:On("GROUP_ROSTER_UPDATE", function()
  ns.Stack:Request(false)
end)
ns.Events:On("UNIT_QUEST_LOG_CHANGED", function(unit)
  if type(unit) == "string" and unit:find("^party") then
    ns.Stack:Request(false)
  end
end)
