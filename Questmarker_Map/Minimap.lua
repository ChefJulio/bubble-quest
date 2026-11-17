local ADDON_NAME, ns = ...

-- The square minimap and the column: Blizzard's own Minimap frame, restyled in place, with
-- Questmarker's tracker hanging under it. Design: docs/design/questmarker-map.md ("The minimap").
--
-- Blizzard's frame stays in its Edit Mode container: Edit Mode places and scales it, we never move it.
-- Everything else is our own frame or a widget setter on Blizzard's:
--   - `outer` (ours, on UIParent): the column's top. Centred on the minimap, the tracker's width,
--     holding the border; the tracker attaches under it (QuestmarkerAPI.SetTrackerAttach).
--   - Minimap:SetSize to the largest square `outer` holds (it's anchored at its container's centre,
--     Minimap.xml:62, so it grows evenly), SetMaskTexture square, the blob rings off, the compass ring
--     textures faded out (alpha: Blizzard re-sets their atlas, never their alpha). Forever re-applies
--     its mask on every rotate toggle (Camelot/Minimap.lua:42), so a post-hook on UpdateMinimapConfig
--     re-applies ours; it sets widget state only, calling no Blizzard update function.
--   - GetMinimapShape (global, the convention LibDBIcon and Questmarker's minimap areas read).
--
-- Not hooked: Edit Mode's apply path (SetEditModeScale; a hook there is how Questmarker's tracker
-- once tainted Edit Mode). Scale changes are noticed by a throttled check on our own frame instead.
--
-- Step 2 of the design's build order. Blizzard's zone text, tracking and indicators stay as they are
-- (sized for the round map, so they may overlap a larger one) until step 3 replaces them.

local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
local BORDER = { 0, 0, 0, 0.9 }
local BORDER_SIZE = 1
local WATCH_SECONDS = 0.25  -- how often scale and size are checked (Edit Mode changes, UI scale)
local FALLBACK_WIDTH = 262  -- before the tracker exists: its default width (250 + 2 * 6)

local Minimap_ = {
  shapeIsOurs = false,
  active = false,
}
ns.Minimap = Minimap_

local outer

-- Shape ------------------------------------------------------------------------------------------

local function applyShape()
  Minimap:SetMaskTexture(SQUARE_MASK)
  for _, ring in ipairs({ "ArchBlobRing", "QuestBlobRing", "TaskBlobRing" }) do
    Minimap["Set" .. ring .. "Scalar"](Minimap, 0)
    Minimap["Set" .. ring .. "Alpha"](Minimap, 0)
  end
  MinimapCompassTexture:SetAlpha(0)
  MinimapCompassTextureUnderlay:SetAlpha(0)
end

-- Size: the column's width from the tracker, the minimap the largest square inside ----------------

local function columnSize()
  local tracker = ns.API.GetTracker()
  local width = tracker and tracker:GetWidth() or FALLBACK_WIDTH
  return width, width  -- height: its own setting with step 3; square until then
end

local function applySize()
  local width, height = columnSize()
  outer:SetSize(width, height)
  -- Minimap's units differ from ours by Edit Mode's scale on its container.
  local side = math.min(width, height) * outer:GetEffectiveScale() / Minimap:GetEffectiveScale()
  Minimap:SetSize(side, side)
  Minimap_.appliedScale = Minimap:GetEffectiveScale()
  Minimap_.appliedWidth = width
end

-- The tracker hangs under `outer`, so resizing or moving `outer` moves its secure quest item buttons:
-- never in combat.
local function refresh()
  ns.AfterCombat("size", applySize)
end

-- Construction -----------------------------------------------------------------------------------

local function createOuter()
  local frame = CreateFrame("Frame", "QuestmarkerMapFrame", UIParent)
  frame:SetFrameStrata(Minimap:GetFrameStrata())
  frame:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
  frame:SetPoint("CENTER", Minimap, "CENTER")
  frame:EnableMouse(false)

  -- A 1 px border just outside the map (the tracker's panel continues below it).
  local edges = {
    { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
  }
  for _, e in ipairs(edges) do
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
    t:SetPoint(e[1], -BORDER_SIZE, BORDER_SIZE)
    t:SetPoint(e[2], BORDER_SIZE, -BORDER_SIZE)
    if e[3] then
      PixelUtil.SetHeight(t, BORDER_SIZE, BORDER_SIZE)
    else
      PixelUtil.SetWidth(t, BORDER_SIZE, BORDER_SIZE)
    end
  end

  -- Edit Mode rescales the minimap's container, and the UI scale can change: check, cheaply.
  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < WATCH_SECONDS then
      return
    end
    elapsed = 0
    if Minimap:GetEffectiveScale() ~= Minimap_.appliedScale then
      refresh()
    end
  end)
  return frame
end

function Minimap_:Activate()
  if self.active then
    return
  end
  self.active = true
  -- Ours, and only now: Compat:Other() has checked nobody else defines it.
  GetMinimapShape = function() return "SQUARE" end
  self.shapeIsOurs = true

  outer = createOuter()
  applyShape()
  hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", applyShape)
  applySize()  -- at login, out of combat
  ns.API.SetTrackerAttach(outer)
  ns.API.RegisterCallback("TrackerResized", refresh)
  ns.API.RegisterCallback("ProfileChanged", refresh)
end

---One line for bug reports (a /qm subcommand later).
---@return string
function Minimap_:Describe()
  if not self.active then
    return "inactive"
  end
  return ("column %dx%d, minimap %.0f (scale %.2f), shape %s"):format(outer:GetWidth(), outer:GetHeight(),
    Minimap:GetWidth(), Minimap:GetEffectiveScale(), GetMinimapShape())
end

ns.On("PLAYER_LOGIN", function()
  if not ns.enabled then
    return
  end
  local other = ns.Compat:Other()
  if other then
    C_Timer.After(5, function() ns.Compat:MaybePrompt(other) end)
    return
  end
  -- Questmarker creates its tracker on PLAYER_LOGIN too; which handler runs first isn't ours to pick.
  C_Timer.After(0, function() ns.AfterCombat("activate", function() Minimap_:Activate() end) end)
end)
