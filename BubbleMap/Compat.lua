local ADDON_NAME, ns = ...

-- Another minimap addon (SexyMap, ...) and ours would both set the mask, size the map and define
-- GetMinimapShape, and fight. So if one is loaded, Questmarker Map leaves the minimap alone and says so
-- once per login (a prompt like Questmarker's Questie one: our own small window, as Blizzard's
-- StaticPopup system taints when addons define dialogs). The fix is one of them off in the AddOns list;
-- the prompt's button does that for the other addon and reloads (a secure "/reload" macro button: addon
-- code can't call ReloadUI on Forever, Questmarker's Compat/Questie.lua).

local NEVER = "other-minimap-never"
local PROMPT_DELAY = 5  -- seconds after login

-- Addons known to restyle the minimap. A minimap shape defined by anyone before we run counts too
-- (the GetMinimapShape convention): that's someone shaping it, whatever its name.
local KNOWN = { "SexyMap", "BasicMinimap", "ElvUI", "Mappy", "SquareMinimap" }

local Compat = {}
ns.Compat = Compat

---The first loaded minimap addon's folder name, "another addon" when only the shape global gives one
---away, or nil when the minimap is ours to style.
---@return string?
function Compat:Other()
  for _, name in ipairs(KNOWN) do
    if C_AddOns.IsAddOnLoaded(name) then
      return name
    end
  end
  if rawget(_G, "GetMinimapShape") and not ns.Minimap.shapeIsOurs then
    return "another addon"
  end
  return nil
end

local prompt

local function plainButton(parent, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(text)
  b:SetSize(math.max(96, b:GetFontString():GetStringWidth() + 24), 22)
  b:SetScript("OnClick", onClick)
  return b
end

local function createPrompt(other)
  local frame = CreateFrame("Frame", "QuestmarkerMapOtherPrompt", UIParent)
  frame:SetFrameStrata("DIALOG")
  frame:SetPoint("TOP", 0, -140)
  frame:SetSize(420, 104)
  frame:EnableMouse(true)
  frame:Hide()
  tinsert(UISpecialFrames, "QuestmarkerMapOtherPrompt")  -- Escape closes it (= Not now)

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
  title:SetText(("%s is styling the minimap too"):format(other))
  local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  text:SetPoint("RIGHT", -14, 0)
  text:SetJustifyH("LEFT")
  text:SetText("Questmarker Map is leaving the minimap alone until one of them is off.")

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
    ns.DB.notices[NEVER] = true
    frame:Hide()
  end)
  never:SetPoint("LEFT", later, "RIGHT", 8, 0)
  return frame
end

function Compat:MaybePrompt(other)
  if ns.DB.notices[NEVER] or InCombatLockdown() then
    return
  end
  prompt = prompt or createPrompt(other)
  prompt:Show()
end
