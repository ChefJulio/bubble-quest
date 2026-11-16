local ADDON_NAME, ns = ...

-- Questmarker runs alongside Questie and replaces only its quest tracker (spec decision). When
-- Questie's tracker is on too, offer to turn it off, by Questie's own switch: a prompt at login (our
-- own small window: Blizzard's StaticPopup system taints when addons define dialogs) and a status
-- row in the settings window (UI/SettingsSchema.lua). Asked for in review: make it easy.
--
-- Turning it off: Questie's own switch, QuestieTracker:Disable() (QuestieTracker.lua:576-584), clears
-- the setting and then calls ReloadUI, which Forever blocks for addon code: "AddOn 'Questie' tried to
-- call the protected function 'Reload()'" (BugSack, when we called it). So the button is a secure
-- macro button running "/reload" (SECURE_ACTIONS.macro -> C_Macro.RunMacroText, SecureTemplates.lua:450:
-- Blizzard's code runs the reload on the player's click), and its PreClick first turns Questie's
-- setting off (Questie.db.profile.trackerEnabled, the field Disable() clears; the rest of Disable is
-- frame-position cleanup a reload resets anyway). If that field can't be found (a Questie update),
-- PreClick cancels the reload and opens Questie's options (QuestieOptions:ToggleConfigWindow,
-- QuestieOptions.lua:103) with a chat hint instead. Every step is guarded: never an error.

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

-- Turn Questie's tracker setting off. Returns false if the setting can't be found.
local function setTrackerOff()
  local questie = questieGlobal()
  local profile = questie and questie.db and questie.db.profile
  if type(profile) ~= "table" or type(profile.trackerEnabled) ~= "boolean" then
    return false
  end
  profile.trackerEnabled = false
  return true
end

---A button that turns Questie's tracker off and reloads the UI (see the header: a secure "/reload"
---macro, the setting changed in PreClick). Create out of combat.
---@param parent table
---@param text string
---@return table
function Questie:CreateTurnOffButton(parent, text)
  -- apiguard: allow created out of combat (prompt at login, settings window); only its macro runs later
  local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
  button:SetText(text)
  button:RegisterForClicks("AnyUp", "AnyDown")  -- either ActionButtonUseKeyDown setting
  button:SetAttribute("type", "macro")
  button:SetAttribute("macrotext", "/reload")
  button:SetScript("PreClick", function(btn)
    if not setTrackerOff() and not InCombatLockdown() then
      btn:SetAttribute("type", nil)  -- no reload: nothing changed
      openQuestieOptions()
    end
  end)
  button:SetScript("PostClick", function(btn)
    if not InCombatLockdown() then
      btn:SetAttribute("type", "macro")
    end
  end)
  return button
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

  local off = Questie:CreateTurnOffButton(frame, "Turn it off")
  off:SetSize(math.max(96, off:GetFontString():GetStringWidth() + 24), 22)
  off:SetPoint("BOTTOMLEFT", 14, 12)
  off:HookScript("PostClick", function() frame:Hide() end)  -- the fallback path doesn't reload
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
