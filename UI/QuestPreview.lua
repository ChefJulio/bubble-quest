local ADDON_NAME, ns = ...

-- A preview card for quests you can pick up (review: "clicking on available quests on the map/minimap
-- should open a preview of that quest"): a click on a quest giver's "!" (the world map: UI/MapAvailable.lua;
-- the minimap and BubbleMap's window: QuestView's Click) opens it at the click. Several quests under the
-- "!" stack in the one card.
--
-- What it can show before a quest is in the log (the game gives its text only then): title and level,
-- who offers it and who takes it in, the objectives (QuestieDB's objective text, else built from
-- forever-db's objectives), rewards (forever-db: experience, money, items with tooltips, reputation),
-- what it follows (forever-db's prerequisites) and tips (forever-db's guide).
--
-- Closes on a click anywhere else (GLOBAL_MOUSE_DOWN) or Escape (UISpecialFrames).

local WIDTH = 300
local PAD = 10
local REWARD_SIZE = 22
local CARD_QUESTS = 4       -- quests listed before "+N more"
local MAX_TIPS = 2
local NAME = "BubbleQuestPreview"
local GREY = { 0.65, 0.65, 0.65 }
local TEXT = { 0.9, 0.9, 0.9 }
local TIP = { 0.45, 0.75, 1 }

local QuestPreview = {}
ns.QuestPreview = QuestPreview

local card
local used = { lines = 0, rewards = 0 }
local pools = { lines = {}, rewards = {} }

local function acquire(kind, make)
  used[kind] = used[kind] + 1
  local item = pools[kind][used[kind]]
  if not item then
    item = make()
    pools[kind][used[kind]] = item
  end
  item:Show()
  return item
end

local function create()
  card = CreateFrame("Frame", NAME, UIParent, "TooltipBackdropTemplate")
  card:SetFrameStrata("FULLSCREEN_DIALOG")  -- above the world map, maximised too
  card:SetWidth(WIDTH)
  card:SetClampedToScreen(true)
  card:EnableMouse(true)
  card:Hide()
  -- Escape closes it, as Blizzard's own panels (by name).
  table.insert(UISpecialFrames, NAME)
  return card
end

local function makeLine()
  local fs = card:CreateFontString(nil, "ARTWORK", "BubbleQuestSmallFont")
  fs:SetJustifyH("LEFT")
  fs:SetWidth(WIDTH - 2 * PAD)
  return fs
end

local function makeReward()
  local button = CreateFrame("Button", nil, card)
  button:SetSize(REWARD_SIZE, REWARD_SIZE)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  button.count:SetPoint("BOTTOMRIGHT", -1, 1)
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetScript("OnEnter", function(self)
    if ns.Tooltips:Take(self, "ANCHOR_RIGHT") then
      GameTooltip:SetItemByID(self.itemID)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return button
end

-- Content -----------------------------------------------------------------------------------------

local y
local function line(text, color, gap)
  y = y + (gap or 0)
  local fs = acquire("lines", makeLine)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", PAD, -y)
  fs:SetText(text)
  fs:SetTextColor(color[1], color[2], color[3])
  y = y + fs:GetStringHeight() + 2
end

local VERBS = { kill = "Kill %d %s", item = "Collect %d %s", object = "Use %s", talk = "Talk to %s" }
local KINDS = { kill = "npc", item = "item", object = "object", talk = "npc" }

-- The objectives as lines: QuestieDB's own objective text when it has it, else forever-db's objectives.
local function objectiveLines(questID, record)
  local lines = {}
  local text = ns.QuestieData:Installed() and ns.QuestieData.Get("QuestDB", "objectivesText", questID)
  if type(text) == "table" then
    for _, s in ipairs(text) do
      if type(s) == "string" and s ~= "" then
        lines[#lines + 1] = s
      end
    end
  end
  if #lines == 0 and record then
    for _, o in ipairs(record.objectives or {}) do
      local verb, kind = VERBS[o.kind], KINDS[o.kind]
      local name = kind and o.target and ns.ForeverData:Name(kind, o.target)
      if verb and name then
        lines[#lines + 1] = verb:find("%%d") and verb:format(o.count or 1, name) or verb:format(name)
      end
    end
  end
  return lines
end

local function rewards(record)
  if not record then
    return
  end
  local parts = {}
  if record.xp and record.xp > 0 then
    parts[#parts + 1] = BreakUpLargeNumbers(record.xp) .. " XP"
  end
  if record.money and record.money > 0 then
    parts[#parts + 1] = GetMoneyString(record.money)
  end
  for _, r in ipairs(record.rewards or {}) do
    if r.kind == "rep" and r.id then
      local faction = C_Reputation.GetFactionDataByID(r.id)
      if faction and faction.name then
        parts[#parts + 1] = ("+%d %s"):format(r.count or 0, faction.name)
      end
    end
  end
  if #parts > 0 then
    line("Rewards: " .. table.concat(parts, "   "), TEXT, 2)
  end
  -- Items, then the choices (one of them).
  for _, group in ipairs({ { kind = "item" }, { kind = "choice", label = "Choose one:" } }) do
    local x, any = PAD, false
    for _, r in ipairs(record.rewards or {}) do
      if r.kind == group.kind and r.id then
        if not any then
          any = true
          if group.label then
            line(group.label, GREY)
          end
          y = y + 2
        end
        if x + REWARD_SIZE > WIDTH - PAD then
          x, y = PAD, y + REWARD_SIZE + 3
        end
        local button = acquire("rewards", makeReward)
        button.itemID = r.id
        button.icon:SetTexture(C_Item.GetItemIconByID(r.id))
        button.count:SetText(r.count and r.count > 1 and r.count or "")
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", x, -y)
        x = x + REWARD_SIZE + 3
      end
    end
    if any then
      y = y + REWARD_SIZE + 4
    end
  end
end

-- One quest of an entry: { record (the available index's), trivial }; `giver` the entry's giver.
local function quest(q, giver)
  local r = q.record
  local questID = r.questID
  local fdb = ns.ForeverData:Quest(questID)
  local level = (r.level and r.level > 0) and r.level or UnitLevel("player")
  local color = GetQuestDifficultyColor(level)
  local tag = q.trivial and " |cff999999(Trivial)|r" or ns.Available.Repeatable(r) and " |cff999999(Repeatable)|r" or ""
  line(("[%d] %s%s"):format(level, r.name or "?", tag), { color.r, color.g, color.b })
  if giver.kind == "item" then
    line(("Starts from %s"):format(giver.name or "an item"), GREY)
  else
    line(("From %s"):format(giver.name or "?"), GREY)
  end
  local turnIn = ns.ForeverData:TurnInName(questID)
  if turnIn and turnIn ~= giver.name then
    line(("Turn in to %s"):format(turnIn), GREY)
  end
  for i, text in ipairs(objectiveLines(questID, fdb)) do
    line(text, TEXT, i == 1 and 4 or 0)
  end
  rewards(fdb)
  local follows = {}
  for _, pre in ipairs(fdb and fdb.prereqs or {}) do
    local preQuest = pre.quest and not pre.breadcrumb and ns.ForeverData:Quest(pre.quest)
    if preQuest and preQuest.name then
      follows[#follows + 1] = preQuest.name
    end
  end
  if #follows > 0 then
    line("Follows " .. table.concat(follows, ", "), GREY, 2)
  end
  for i, tip in ipairs(ns.ForeverData:Tips(questID)) do
    if i > MAX_TIPS then
      break
    end
    line("Tip: " .. tip, TIP, i == 1 and 2 or 0)
  end
end

---Open the card at the cursor for `entries` (UI/MapAvailable.lua's: { giver, quests }).
---@param entries table[]
function QuestPreview.ShowAvailable(entries)
  card = card or create()
  for kind, pool in pairs(pools) do
    for i = 1, #pool do
      pool[i]:Hide()
    end
    used[kind] = 0
  end
  y = PAD
  local shown, total = 0, 0
  for _, entry in ipairs(entries) do
    for _, q in ipairs(entry.quests) do
      total = total + 1
      if shown < CARD_QUESTS then
        if shown > 0 then
          y = y + 8
        end
        quest(q, entry.giver)
        shown = shown + 1
      end
    end
  end
  if total > shown then
    line(("+%d more"):format(total - shown), GREY, 6)
  end
  card:SetHeight(y + PAD)
  -- At the click, a little right and below; the screen's edge keeps it whole (SetClampedToScreen).
  local scale = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  card:ClearAllPoints()
  card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 12, cy / scale - 12)
  card:Show()
  QuestPreview.openedAt = GetTime()
end

function QuestPreview.Hide()
  if card then
    card:Hide()
  end
end

-- A click anywhere but the card closes it (not the click that opened it: GLOBAL_MOUSE_DOWN comes first).
ns.Events:On("GLOBAL_MOUSE_DOWN", function()
  if card and card:IsShown() and not card:IsMouseOver() then
    card:Hide()
  end
end)
