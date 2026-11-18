local ADDON_NAME, ns = ...

-- The square minimap and the column: Blizzard's own Minimap frame, restyled in place, with the quest
-- addon's tracker hanging under it when that addon is loaded. Design: docs/design/questmarker-map.md
-- ("The minimap").
--
-- Blizzard's frame stays in its Edit Mode container: Edit Mode scales it, we never move the container.
-- Everything else is our own frame or a widget setter on Blizzard's:
--   - `outer` (ours, on UIParent): the column's top, holding the border. Its width is the tracker's
--     with the quest addon (which then attaches its tracker under it: SetTrackerAttach), else our own
--     width setting; its height a percentage of that. It hangs from the top corner of
--     Edit Mode's minimap box nearest the screen edge, so it grows inward: centred on the box (where
--     Blizzard anchors the minimap, Minimap.xml:62), a map wider than the box ran off the screen (seen
--     in review; Edit Mode clamps only its own box).
--   - Minimap re-anchored to `outer`'s centre, inside its own container: Blizzard only ever positions
--     the container, never the Minimap frame itself, so this anchor stays.
--   - Minimap:SetSize to the largest square `outer` holds, SetMaskTexture square, the blob rings off, the compass ring
--     textures faded out (alpha: Blizzard re-sets their atlas, never their alpha). Forever re-applies
--     its mask on every rotate toggle (Camelot/Minimap.lua:42), so a post-hook on UpdateMinimapConfig
--     re-applies ours; it sets widget state only, calling no Blizzard update function.
--   - GetMinimapShape (global, the convention LibDBIcon and the quest addon's minimap areas read).
--
-- Not hooked: Edit Mode's apply path (SetEditModeScale; a hook there is how the quest addon's tracker
-- once tainted Edit Mode). Scale changes are noticed by a throttled check on our own frame instead.
--
-- Step 2 of the design's build order. Blizzard's zone text, tracking and indicators stay as they are
-- (sized for the round map, so they may overlap a larger one) until step 3 replaces them.

local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
local BORDER = { 0, 0, 0, 0.9 }
local BORDER_SIZE = 1
local WATCH_SECONDS = 0.25  -- how often scale and size are checked (Edit Mode changes, UI scale)

local Minimap_ = {
  shapeIsOurs = false,
  active = false,
  outer = nil,       ---@type Frame? -- the column's top (see the header)
  onActivate = {},   -- fn(outer) for each, once the map is ours (Around.lua)
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

-- Size: the column's width (the tracker's, or our setting), the minimap the largest square inside -

local function columnSize()
  local tracker = ns.Quest and ns.Quest.GetTracker()
  local width = tracker and tracker:GetWidth() or ns.DB.width
  return width, math.floor(width * ns.DB.heightPercent / 100 + 0.5)
end

local function applySize()
  local width, height = columnSize()
  outer:SetSize(width, height)
  -- Minimap's units differ from ours by Edit Mode's scale on its container.
  local side = math.min(width, height) * outer:GetEffectiveScale() / Minimap:GetEffectiveScale()
  local resized = math.abs(Minimap:GetWidth() - side) > 0.5
  Minimap:SetSize(side, side)
  Minimap_.appliedScale = Minimap:GetEffectiveScale()
  Minimap_.appliedWidth = width
  if resized then
    -- The engine keeps drawing the ground at the old size until something redraws it (seen in game: a
    -- small square of ground in one corner until the map was moved). A zoom step and back does, the
    -- usual minimap-addon remedy. Next frame, once the new size has applied.
    C_Timer.After(0, function()
      local zoom = Minimap:GetZoom()
      Minimap:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
      Minimap:SetZoom(zoom)
    end)
  end
end

-- Which top corner of Edit Mode's box `outer` hangs from: the one nearest the screen edge.
local function corner()
  local x = MinimapCluster:GetCenter()
  local center = UIParent:GetCenter()
  if not x or not center then
    return "TOPRIGHT"
  end
  local onRight = x * MinimapCluster:GetEffectiveScale() > center * UIParent:GetEffectiveScale()
  return onRight and "TOPRIGHT" or "TOPLEFT"
end

-- Where the column is: where it was dragged to (by the quest addon's tracker header, or our own bar),
-- else hanging from Edit Mode's box. Our frame is the one source of truth for the map's position; Blizzard's
-- minimap follows it and its Edit Mode box is never moved by us.
local function applyAnchor()
  outer:ClearAllPoints()
  local saved = ns.DB.position
  if saved then
    outer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved[1], saved[2])
    Minimap_.appliedCorner = nil
    return
  end
  local point = corner()
  outer:SetPoint(point, MinimapCluster, point)
  Minimap_.appliedCorner = point
end

-- After a drag: StartMoving may have re-anchored `outer` by any point; pin its top-left so it grows
-- only right and down (the tracker's resize grip), and save that.
function Minimap_:SavePosition()
  local left, top = outer:GetLeft(), outer:GetTop()
  if not left or not top then
    return
  end
  ns.DB.position = { left, top }
  applyAnchor()
end

---Back to hanging from Edit Mode's minimap box.
function Minimap_:ResetPosition()
  ns.DB.position = nil
  ns.AfterCombat("size", function() applyAnchor() end)
end

-- The tracker hangs under `outer`, so resizing or moving `outer` moves its secure quest item buttons:
-- never in combat.
local function refresh()
  ns.AfterCombat("size", function()
    applyAnchor()
    applySize()
  end)
end

---Size or position settings changed.
function Minimap_:Refresh()
  if self.active then
    refresh()
  end
end

-- Construction -----------------------------------------------------------------------------------

local function createOuter()
  local frame = CreateFrame("Frame", "BubbleMapFrame", UIParent)
  -- One strata below the minimap's: our border and the terrain (Terrain.lua) must stay under it. Same
  -- strata and a lower level wasn't enough: the terrain's frames tied the minimap's level and drew over
  -- it (seen in game), and MinimapCluster is toplevel, so levels move whenever it's clicked.
  local below = { LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH" }
  frame:SetFrameStrata(below[Minimap:GetFrameStrata()] or "BACKGROUND")
  frame:EnableMouse(false)
  frame:SetMovable(true)  -- dragged by the quest addon's tracker header (TrackerAttachMoved) or our bar
  frame:SetClampedToScreen(true)

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

  -- Edit Mode rescales and moves the minimap's box, and the UI scale can change: check, cheaply.
  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < WATCH_SECONDS then
      return
    end
    elapsed = 0
    local moved = not ns.DB.position and corner() ~= Minimap_.appliedCorner
    if Minimap:GetEffectiveScale() ~= Minimap_.appliedScale or moved then
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
  applyAnchor()  -- at login, out of combat
  applySize()
  Minimap:ClearAllPoints()
  Minimap:SetPoint("CENTER", outer, "CENTER")

  -- With the quest addon: one column, its tracker under the map.
  local quest = ns.Quest
  if quest then
    quest.SetTrackerAttach(outer)
    quest.RegisterCallback("TrackerResized", refresh)
    quest.RegisterCallback("ProfileChanged", refresh)
    quest.RegisterCallback("TrackerAttachMoved", function() Minimap_:SavePosition() end)
    -- Its quest areas over the whole frame, padding included (an API 1 member added later: check).
    if quest.SetMinimapView then
      quest.SetMinimapView(outer)
    end
  end

  self.outer = outer
  for _, fn in ipairs(self.onActivate) do
    fn(outer)
  end
end

---Drag the column (our bar's drag handle). Not while locked, not in combat: with the quest addon its
---tracker, carrying secure quest item buttons, hangs under us.
function Minimap_:StartDrag()
  if self.active and not ns.DB.locked and not InCombatLockdown() then
    self.dragging = true
    outer:StartMoving()
  end
end

function Minimap_:StopDrag()
  if self.dragging then
    self.dragging = false
    outer:StopMovingOrSizing()
    self:SavePosition()
  end
end

---One line for bug reports (/bmap).
---@return string
function Minimap_:Describe()
  if not self.active then
    return "inactive"
  end
  return ("column %dx%d, minimap %.0f (scale %.2f), shape %s, %s; %s"):format(outer:GetWidth(),
    outer:GetHeight(), Minimap:GetWidth(), Minimap:GetEffectiveScale(), GetMinimapShape(),
    ns.Quest and "with the quest tracker" or "standalone", ns.Launchers:Describe() .. "; " .. ns.Terrain:Describe() .. "; " .. ns.Zoom:Describe() .. "; " .. ns.QuestMarkers:Describe())
end

-- /bmap: status; /bmap reset: back to Edit Mode's position. (Settings come with step 3.)
SLASH_BUBBLEMAP1 = "/bmap"
SLASH_BUBBLEMAP2 = "/bubblemap"
SlashCmdList.BUBBLEMAP = function(input)
  local command = (input or ""):lower():match("^%s*(%S*)")
  if command == "reset" then
    Minimap_:ResetPosition()
    print("|cffffd100BubbleMap|r: back at the minimap's Edit Mode position.")
  elseif command == "tracking" then
    for _, line in ipairs(ns.QuestMarkers:Report()) do
      print("|cffffd100BubbleMap|r " .. line)
    end
  elseif command == "tiles" then
    for _, line in ipairs(ns.Terrain:Report()) do
      print("|cffffd100BubbleMap|r " .. line)
    end
  else
    print("|cffffd100BubbleMap|r: " .. Minimap_:Describe() .. ". /bmap reset: back at the minimap's Edit "
      .. "Mode position.")
  end
end

ns.On("PLAYER_LOGIN", function()
  local other = ns.Compat:Other("minimap")
  if other then
    ns.Compat:PromptSoon("minimap", other)
    return
  end
  -- The quest addon creates its tracker on PLAYER_LOGIN too; which handler runs first isn't ours to pick.
  C_Timer.After(0, function() ns.AfterCombat("activate", function() Minimap_:Activate() end) end)
end)
