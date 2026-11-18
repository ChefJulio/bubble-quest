local ADDON_NAME, ns = ...

-- Other addons doing BubbleMap's jobs. Two of them on the same job fight, so BubbleMap leaves that job
-- to the other one and says so once per login, with a button that turns the other addon off and
-- reloads (our own small window, as Blizzard's StaticPopup system taints when addons define dialogs; a
-- secure "/reload" macro button, as addon code can't call ReloadUI on Forever). "Don't ask again"
-- per job.
--
--   minimap: another minimap addon (SexyMap, ...) would also set the mask, size the map and define
--            GetMinimapShape. BubbleMap then leaves the minimap alone entirely.
--   buttons: another minimap button collector (ForeverCleanButtons, ...) would also hide and move
--            the buttons. BubbleMap's launcher list then stays off (Launchers.lua).

local PROMPT_DELAY = 5  -- seconds after login

local JOBS = {
  minimap = {
    -- Addons known to restyle the minimap. A minimap shape defined by anyone before we run counts too
    -- (the GetMinimapShape convention): that's someone shaping it, whatever its name.
    known = { "SexyMap", "BasicMinimap", "ElvUI", "Mappy", "SquareMinimap" },
    never = "other-minimap-never",
    title = "%s is styling the minimap too",
    text = "BubbleMap is leaving the minimap alone until one of them is off.",
  },
  buttons = {
    known = { "ForeverCleanButtons", "MinimapButtonButton", "MBB", "MinimapButtonBag" },
    never = "other-buttons-never",
    title = "%s is collecting minimap buttons too",
    text = "BubbleMap's addon list (the bar's Addons button) is off until one of them is off.",
  },
}

local Compat = {}
ns.Compat = Compat

---The first loaded addon doing `job`'s work (its folder name), "another addon" when only the minimap
---shape global gives one away, or nil when the job is ours.
---@param job string "minimap" | "buttons"
---@return string?
function Compat:Other(job)
  for _, name in ipairs(JOBS[job].known) do
    if C_AddOns.IsAddOnLoaded(name) then
      return name
    end
  end
  if job == "minimap" and rawget(_G, "GetMinimapShape") and not ns.Minimap.shapeIsOurs then
    return "another addon"
  end
  return nil
end

local function plainButton(parent, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(text)
  b:SetSize(math.max(96, b:GetFontString():GetStringWidth() + 24), 22)
  b:SetScript("OnClick", onClick)
  return b
end

local function createPrompt(job, other)
  local spec = JOBS[job]
  local frameName = "BubbleMapOtherPrompt_" .. job
  local frame = CreateFrame("Frame", frameName, UIParent)
  frame:SetFrameStrata("DIALOG")
  frame:SetPoint("TOP", 0, -140)
  frame:SetSize(440, 104)
  frame:EnableMouse(true)
  frame:Hide()
  tinsert(UISpecialFrames, frameName)  -- Escape closes it (= Not now)

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
  title:SetText(spec.title:format(other))
  local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  text:SetPoint("RIGHT", -14, 0)
  text:SetJustifyH("LEFT")
  text:SetText(spec.text)

  local last
  if other ~= "another addon" then
    -- apiguard: allow created out of combat (at login); only its macro runs later
    local off = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    off:SetText(("Turn %s off"):format(other))
    off:SetSize(math.max(96, off:GetFontString():GetStringWidth() + 24), 22)
    off:RegisterForClicks("AnyUp", "AnyDown")  -- either ActionButtonUseKeyDown setting
    off:SetAttribute("type", "macro")
    off:SetAttribute("macrotext", "/reload")
    off:SetScript("PreClick", function()
      C_AddOns.DisableAddOn(other)
    end)
    off:SetPoint("BOTTOMLEFT", 14, 12)
    last = off
  end
  local later = plainButton(frame, "Not now", function() frame:Hide() end)
  if last then
    later:SetPoint("LEFT", last, "RIGHT", 8, 0)
  else
    later:SetPoint("BOTTOMLEFT", 14, 12)
  end
  local never = plainButton(frame, "Don't ask again", function()
    ns.DB.notices[spec.never] = true
    frame:Hide()
  end)
  never:SetPoint("LEFT", later, "RIGHT", 8, 0)
  return frame
end

local prompts = {}

---Prompt about `other` doing `job` a few seconds after login, unless the player said "Don't ask again".
---@param job string "minimap" | "buttons"
---@param other string
function Compat:PromptSoon(job, other)
  C_Timer.After(PROMPT_DELAY, function()
    if ns.DB.notices[JOBS[job].never] or InCombatLockdown() then
      return
    end
    prompts[job] = prompts[job] or createPrompt(job, other)
    prompts[job]:Show()
  end)
end
