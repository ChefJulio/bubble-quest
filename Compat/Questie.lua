local ADDON_NAME, ns = ...

-- Questmarker runs alongside Questie and replaces only its quest tracker (spec decision). When
-- Questie's tracker is on too, offer to turn it off, by Questie's own switch: a prompt at login (our
-- own small window: Blizzard's StaticPopup system taints when addons define dialogs) and a status
-- row in the settings window (UI/SettingsSchema.lua). Asked for in review: make it easy.
--
-- Turning it off runs QuestieTracker:Disable(), what Questie's own "Enable Tracker" checkbox runs
-- (Questie/Modules/Options/TrackerTab/QuestieOptionsTracker.lua:105-111): it clears the setting,
-- cleans up its tracker and reloads the UI (QuestieTracker.lua:576-584). Only on the player's click,
-- and not in combat (a reload then would be refused, and Questie's checkbox is disabled in combat too).
-- If a Questie update moves that function, the button opens Questie's options instead
-- (QuestieOptions:ToggleConfigWindow, QuestieOptions.lua:103) with a chat hint. Every step is guarded:
-- a renamed field means "fallback", never an error.

local NEVER = "questie-tracker-never"   -- char notice: "Don't ask again"
local PROMPT_DELAY = 5                  -- seconds after login: Questie finishes setting up first

local Questie = {}
ns.Questie = Questie

local function questieGlobal()
  local questie = rawget(_G, "Questie")
  return type(questie) == "table" and questie or nil
end

local function importModule(name)
  local loader = rawget(_G, "QuestieLoader")
  if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
    return nil
  end
  local ok, module = pcall(loader.ImportModule, loader, name)
  return ok and type(module) == "table" and module or nil
end

---Is Questie loaded?
---@return boolean
function Questie:Installed()
  return C_AddOns.IsAddOnLoaded("Questie") and questieGlobal() ~= nil
end

---Questie's tracker setting: true on, false off, nil when unknown (not loaded, not ready, renamed).
---@return boolean?
function Questie:TrackerEnabled()
  local questie = questieGlobal()
  local profile = questie and questie.db and questie.db.profile
  if type(profile) ~= "table" or type(profile.trackerEnabled) ~= "boolean" then
    return nil
  end
  return profile.trackerEnabled
end

local function openQuestieOptions()
  local options = importModule("QuestieOptions")
  if options and type(options.ToggleConfigWindow) == "function" and rawget(_G, "QuestieConfigFrame") then
    pcall(options.ToggleConfigWindow, options)
  end
  ns.Debug:Print("In Questie's options, untick Tracker > Enable Tracker.")
end

---Turn Questie's tracker off with Questie's own switch (reloads the UI). Out of combat only.
function Questie:TurnOffTracker()
  if InCombatLockdown() then
    ns.Debug:Print("Leave combat first: turning off Questie's tracker reloads the UI.")
    return
  end
  local tracker = importModule("QuestieTracker")
  if tracker and type(tracker.Disable) == "function" then
    tracker:Disable()  -- reloads the UI
  else
    openQuestieOptions()
  end
end

-- The prompt -----------------------------------------------------------------------------------------

local prompt

local function button(parent, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(text)
  b:SetSize(math.max(96, b:GetFontString():GetStringWidth() + 24), 22)
  b:SetScript("OnClick", onClick)
  return b
end

local function createPrompt()
  local frame = CreateFrame("Frame", "QuestmarkerQuestiePrompt", UIParent)
  frame:SetFrameStrata("DIALOG")
  frame:SetPoint("TOP", 0, -140)
  frame:SetSize(400, 104)
  frame:EnableMouse(true)
  frame:Hide()
  tinsert(UISpecialFrames, "QuestmarkerQuestiePrompt")  -- Escape closes it (= Not now)

  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.05, 0.05, 0.06, 0.94)
  local border = frame:CreateTexture(nil, "BORDER")
  border:SetPoint("TOPLEFT")
  border:SetPoint("TOPRIGHT")
  border:SetColorTexture(0.95, 0.75, 0.15, 0.8)
  PixelUtil.SetHeight(border, 2, 2)

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Questie's quest tracker is on too")
  local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  text:SetPoint("RIGHT", -14, 0)
  text:SetJustifyH("LEFT")
  text:SetText("Questmarker replaces it. Turn Questie's tracker off? Your UI reloads.")

  local off = button(frame, "Turn it off", function()
    frame:Hide()
    Questie:TurnOffTracker()
  end)
  off:SetPoint("BOTTOMLEFT", 14, 12)
  local later = button(frame, "Not now", function() frame:Hide() end)
  later:SetPoint("LEFT", off, "RIGHT", 8, 0)
  local never = button(frame, "Don't ask again", function()
    ns.DB.char.notices[NEVER] = true
    frame:Hide()
  end)
  never:SetPoint("LEFT", later, "RIGHT", 8, 0)
  return frame
end

---Show the prompt if Questie's tracker is on and the player hasn't said "Don't ask again".
function Questie:MaybePrompt()
  if self:TrackerEnabled() ~= true or ns.DB.char.notices[NEVER] or InCombatLockdown() then
    return
  end
  prompt = prompt or createPrompt()
  prompt:Show()
end

-- Once per session, after login has settled.
local checked = false
ns.Events:On("PLAYER_ENTERING_WORLD", function()
  if checked then
    return
  end
  checked = true
  C_Timer.After(PROMPT_DELAY, function() Questie:MaybePrompt() end)
end)
