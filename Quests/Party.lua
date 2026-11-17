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
  remote = {},     -- [name] = { [questID] = "ok" | reason }: answers from their BubbleQuest
  asking = {},     -- [questID] = true: to ask in the next query
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

-- Eligibility (review, researched: no API reveals another player's completed quests, quest log or
-- reputation; Party Sync is off on Forever). Three layers, first answer wins:
--   1. Pre-check, anyone: their level, class, race and faction against the quest's requirements
--      (forever-db; Questie's max level). Party members' class and race are readable (secret only
--      for units outside the party: SecretPredicatesDocumentation.lua:130-133).
--   2. Ask their BubbleQuest (when they run it): it answers for its own player (completed, earlier
--      quest missing, log full) over addon messages. See "BubbleQuest to BubbleQuest" below.
--   3. Share replies: lasting refusals from a share this session (Party.refused).
local REASONS = {
  low = "too low level", high = "too high level", class = "wrong class", race = "wrong race",
  faction = "other faction", done = "already completed", pre = "needs an earlier quest",
  full = "quest log full", onq = "already has it",
  ALREADY_DONE = "already completed", CLASS = "wrong class", RACE = "wrong race",
  HIGH_LEVEL = "too high level", LOW_LEVEL = "too low level", PREREQUISITE = "needs an earlier quest",
  INVALID = "not eligible", ONQUEST = "already has it", LOG_FULL = "quest log full",
}

-- A quest's requirements from forever-db (client masks: bit n-1 for race/class n, 0 = any; side 1
-- Alliance, 2 Horde), plus Questie's maximum level when it has one.
local function requirements(questID)
  local record = ns.ForeverData:Quest(questID)
  local req = {
    minLevel = record and record.minLevel, races = record and record.races or 0,
    classes = record and record.classes or 0, side = record and record.side or 0,
  }
  local questDB = rawget(_G, "QuestDB")
  if ns.QuestieData:Available() and type(questDB) == "table" and type(questDB.requiredMaxLevel) == "function" then
    local ok, maxLevel = pcall(questDB.requiredMaxLevel, questID)
    req.maxLevel = ok and type(maxLevel) == "number" and maxLevel > 0 and maxLevel or nil
  end
  return req
end

local function hasBit(mask, id)
  return mask == 0 or (type(id) == "number" and bit.band(mask, bit.lshift(1, id - 1)) ~= 0)
end

-- Layer 1: a reason this member obviously can't take the quest, or nil.
local function precheck(unit, req)
  local level = UnitLevel(unit)
  if readable(level) and level > 0 then
    if req.minLevel and level < req.minLevel then return "low" end
    if req.maxLevel and level > req.maxLevel then return "high" end
  end
  -- apiguard: allow party units are readable (secret only outside the party); secrets skipped anyway
  local _, _, classID = UnitClass(unit)
  if readable(classID) and not hasBit(req.classes, classID) then return "class" end
  -- apiguard: allow party units are readable (secret only outside the party); secrets skipped anyway
  local _, _, raceID = UnitRace(unit)
  if readable(raceID) and not hasBit(req.races, raceID) then return "race" end
  local faction = UnitFactionGroup(unit)
  if readable(faction) and ((req.side == 1 and faction ~= "Alliance") or (req.side == 2 and faction ~= "Horde")) then
    return "faction"
  end
  return nil
end

---Party members without the quest, split into who can take it and who can't (with why).
---@param questID number
---@return string[] can
---@return table[] cannot { { name, reason } }
function Party:Status(questID)
  local can, cannot = {}, {}
  if not IsInGroup() then
    return can, cannot
  end
  local req = requirements(questID)
  for _, member in ipairs(self:Members()) do
    local onQuest = C_QuestLog.IsUnitOnQuest(member.unit, questID)
    if readable(onQuest) and not onQuest then
      local remote = self.remote[member.name] and self.remote[member.name][questID]
      local refused = self.refused[member.name] and self.refused[member.name][questID]
      local reason = precheck(member.unit, req) or (remote ~= "ok" and remote) or refused
      if reason then
        cannot[#cannot + 1] = { name = member.name, reason = REASONS[reason] or "not eligible" }
      else
        can[#can + 1] = member.name
        if remote == nil then
          self:Ask(questID)
        end
      end
    end
  end
  return can, cannot
end

---Names of party members who don't have the quest and could take it, as far as we know.
---@param questID number
---@return string[]
function Party:Missing(questID)
  return (self:Status(questID))
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

-- BubbleQuest to BubbleQuest ---------------------------------------------------------------------------
-- The only way to know a party member's completed quests, prerequisites or log space before sharing
-- (review, researched): ask their BubbleQuest, which answers for its own player. Party channel, prefix
-- "Questmarker" (the addon's name before the rename, kept on the wire so the new version and the old
-- one still understand each other; players never see it):
--   "Q1:123,456"         which of these can you take? (debounced: one query for everything unknown)
--   "A1:123=ok,456=done" the answer, to the whole party (every BubbleQuest learns it)
-- Codes: ok, done (completed), pre (an earlier quest missing, per forever-db), full (log full), onq.
-- Members without BubbleQuest never answer; layers 1 and 3 still apply to them. Addon messages are
-- refused during chat lockdown (InChatMessagingLockdown: restricted content); nothing is sent then.

local PREFIX = "Questmarker"  -- the wire name, unchanged by the rename (see above)
local ASK_DELAY = 1  -- seconds to gather quests into one query
local MAX_MESSAGE = 240

local function send(text)
  if C_ChatInfo.InChatMessagingLockdown() or not IsInGroup() then
    return
  end
  -- apiguard: allow arguments are our own plain strings (never secret); not sent during chat lockdown
  C_ChatInfo.SendAddonMessage(PREFIX, text, IsInRaid() and "RAID" or "PARTY")
end

-- Send a list in as many messages as it takes ("Q1:" + ids, each under the size limit).
local function sendList(head, items)
  local line = head
  for _, item in ipairs(items) do
    local piece = (line == head and "" or ",") .. item
    if #line + #piece > MAX_MESSAGE then
      send(line)
      line, piece = head, item
    end
    line = line .. piece
  end
  if line ~= head then
    send(line)
  end
end

local askTimer
---Ask the party's BubbleQuests about a quest (gathered into one query shortly after).
---@param questID number
function Party:Ask(questID)
  if self.asking[questID] ~= nil then
    return
  end
  self.asking[questID] = true
  if not askTimer then
    askTimer = C_Timer.NewTimer(ASK_DELAY, function()
      askTimer = nil
      local ids = {}
      for id, pending in pairs(Party.asking) do
        if pending then
          ids[#ids + 1] = tostring(id)
          Party.asking[id] = false  -- asked; asked again only after their log changes
        end
      end
      sendList("Q1:", ids)
    end)
  end
end

-- Our own answer for one quest.
local function ownAnswer(questID)
  if C_QuestLog.IsQuestFlaggedCompleted(questID) then
    return "done"
  end
  if C_QuestLog.GetLogIndexForQuestID(questID) then
    return "onq"
  end
  local record = ns.ForeverData:Quest(questID)
  if record then
    for _, pre in ipairs(record.preQuestGroup or {}) do
      if not C_QuestLog.IsQuestFlaggedCompleted(pre) then
        return "pre"
      end
    end
    local any = record.preQuestSingle
    if any and #any > 0 then
      local met = false
      for _, pre in ipairs(any) do
        met = met or C_QuestLog.IsQuestFlaggedCompleted(pre)
      end
      if not met then
        return "pre"
      end
    end
  end
  local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
  if numQuests >= C_QuestLog.GetMaxNumQuestsCanAccept() then
    return "full"
  end
  return "ok"
end

local function baseName(name)
  return (name:match("^([^%-]+)")) or name
end

ns.Events:On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
  if prefix ~= PREFIX or not readable(text) or not readable(sender) then
    return
  end
  -- apiguard: allow our own name, to skip our own messages (readable checked)
  local me = UnitName("player")
  local from = baseName(sender)
  if from == me then
    return
  end
  local kind, body = text:match("^(%a)1:(.*)$")
  if kind == "Q" then
    local answers = {}
    for id in body:gmatch("%d+") do
      answers[#answers + 1] = id .. "=" .. ownAnswer(tonumber(id))
    end
    sendList("A1:", answers)
  elseif kind == "A" then
    Party.remote[from] = Party.remote[from] or {}
    for id, code in body:gmatch("(%d+)=(%a+)") do
      Party.remote[from][tonumber(id)] = code
    end
    ns.Stack:Request(false)  -- the cards' "+N" follow
  end
end)

ns.Events:On("PLAYER_LOGIN", function()
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end)

-- The card's "+N" follows the party: who's in it, and their quest logs. A member's log changing (they
-- accepted, finished or dropped a quest) makes their answers stale: forget them and ask again.
ns.Events:On("GROUP_ROSTER_UPDATE", function()
  ns.Stack:Request(false)
end)
ns.Events:On("UNIT_QUEST_LOG_CHANGED", function(unit)
  if type(unit) == "string" and unit:find("^party") then
    -- apiguard: allow names: secret ones are skipped (readable)
    local name = UnitName(unit)
    if readable(name) then
      Party.remote[name] = nil
    end
    wipe(Party.asking)
    ns.Stack:Request(false)
  end
end)
