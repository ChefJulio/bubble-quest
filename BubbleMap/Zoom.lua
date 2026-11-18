local ADDON_NAME, ns = ...

-- Whose map, and zoom (build step 6, as decided with the user 2026-11-17). Design:
-- docs/design/questmarker-map.md ("Zoom").
--
-- Blizzard's minimap blips (herbs, ore, tracking, party, the game's quest "?" and "!") are only right
-- at Blizzard's own zoom levels and size: scaling its frame (behind a mask or a clipping parent) put
-- them in wrong places (experiments, 2026-11-17), and at alpha 0 the engine still drew them. So the map
-- is either ours (Blizzard's minimap hidden) or Blizzard's (shown, at one of its own levels), never a mix.
--
-- ONE ZOOM SCALE for everything (review: gather mode on Blizzard's six levels and our map on its own
-- steps gave a slider that lost track, less zoom-in in gather mode and uneven notches): STEPS, x1.5
-- each, six in and six out of Blizzard's farthest view (the slider's gold middle notch).
--
--   - OUR MAP (the usual): Blizzard's minimap hidden, its zoom fixed at its farthest level; BubbleMap
--     draws everything: terrain (Terrain.lua), our player arrow, BubbleQuest's quest layer (told the game
--     draws nothing: SetMinimapZoom(k, true)).
--   - GATHER MODE: at the steps where one of Blizzard's own levels matches ours (within MATCH: the
--     middle step and three in, as it happens: 1, 0.67, 0.44, 0.30 against Blizzard's 1, 0.71, 0.43,
--     0.29), Blizzard's minimap shows at that level, for its live blips, our terrain under it at its
--     exact scale. At every other step, deeper in or out, our map: the blips would be wrong there.
--   - No Ctrl peek (there was one, Blizzard's minimap while Ctrl was held; dropped 2026-11-18, user's
--     call: Ctrl hides BubbleQuest's quest layer instead, in that addon). Gather mode is the way to the
--     game's blips.
--   - INDOORS and off our data (instances, maps not in Data/Tiles.lua): Blizzard's minimap with its own
--     zoom, untouched; it has the interior maps.
--
-- Gather mode is a setting (BubbleMapDB.gatherMode): "never" (default: our map), "auto"
-- (while a tracking spell such as Find Herbs is on) or "always"; the bar's gather button toggles it.
--
-- The wheel: our map frame takes it over the padding; over Blizzard's square, Blizzard's minimap takes it
-- (the wheel isn't covered by turning its mouse off) and zooms its own level, so a post-hook puts the
-- level back and steps ours instead. One path for both: Zoom:Step.

local STEP_RATIO, STEPS_EACH_WAY = 1.5, 6
local STEPS = {}
for i = -STEPS_EACH_WAY, STEPS_EACH_WAY do
  STEPS[#STEPS + 1] = STEP_RATIO ^ i
end
local DEFAULT_STEP = STEPS_EACH_WAY + 1  -- 1: Blizzard's farthest view
-- Blizzard's outdoor levels as shares of its farthest view [Inferred: classic's radii, 233.3 down to
-- 66.7 yd; they matched the user's measurements at levels 0 and 1].
local LEVEL_SHARES = { 1, 6 / 7, 5 / 7, 4 / 7, 3 / 7, 2 / 7 }
local MATCH = 1.1  -- a Blizzard level stands in for a step within this ratio

local SLIDER_HOLD, SLIDER_FADE = 1.2, 0.4  -- seconds shown after the last zoom, then fading out
local ARROW = "Interface\\Minimap\\MinimapArrow"
local ARROW_SIZE = 32

local Zoom = {
  own = false,        -- our map is showing (else Blizzard's minimap)
  step = DEFAULT_STEP,
}
ns.Zoom = Zoom

local arrow, arrowTexture
local showSlider  -- set when the slider is created (below)

-- Our terrain is under the player: outdoors, on a continent we have tiles for.
local function terrainHere()
  if IsIndoors() then
    return false
  end
  local _, _, _, mapID = UnitPosition("player")
  return mapID ~= nil and ns.Tiles.maps[mapID] ~= nil
end

-- A tracking spell is on (Find Herbs, Find Minerals, Track Beasts, ...): the game marks what it finds
-- only on its own minimap.
local function trackingSpellOn()
  for index = 1, C_Minimap.GetNumTrackingTypes() do
    local info = C_Minimap.GetTrackingInfo(index)
    if info and info.active and info.type == "spell" then
      return true
    end
  end
  return false
end

-- The player's tracking spells (Find Herbs, Find Minerals, Track Beasts, ...): { index, name, texture,
-- active }. The game runs one at a time.
local function trackingSpells()
  local list = {}
  for index = 1, C_Minimap.GetNumTrackingTypes() do
    local info = C_Minimap.GetTrackingInfo(index)
    if info and info.type == "spell" then
      list[#list + 1] = { index = index, name = info.name, texture = info.texture, active = info.active }
    end
  end
  return list
end

---The tracking spell the gather button shows: the active one, else the last one used (by name), else
---the first. nil when the player has none.
---@return table?
function Zoom:GatherSpell()
  local spells = trackingSpells()
  local last
  for _, s in ipairs(spells) do
    if s.active then
      return s
    end
    if s.name == ns.DB.lastGather then
      last = s
    end
  end
  return last or spells[1]
end

local function gathering()
  local mode = ns.DB.gatherMode
  if mode == "always" then
    return true
  elseif mode == "never" then
    return false
  end
  return trackingSpellOn()
end

---Gather mode is on (the setting, and for "auto" a tracking spell).
---@return boolean
function Zoom:Gathering()
  return gathering()
end

---The bar's gather button: a hard toggle of the mode (user's call): gather mode on (the game's minimap
---and its live blips) or off (our map only, whatever is tracked). Tracking itself is left alone.
function Zoom:ToggleGather()
  ns.DB.gatherMode = self:Gathering() and "never" or "always"
  self:Update()
end

-- The Blizzard level (0 farthest) that stands in for a step, or nil when none is close enough.
local function levelFor(step)
  local k = STEPS[step]
  for i, share in ipairs(LEVEL_SHARES) do
    if i - 1 < Minimap:GetZoomLevels() and math.max(k / share, share / k) <= MATCH then
      return i - 1
    end
  end
  return nil
end

-- Whose map: "ours", "blizzard" (at a level), or "native" (indoors / no terrain: Blizzard's own zoom).
local function mode()
  if not terrainHere() then
    return "native"
  end
  if gathering() and levelFor(Zoom.step) then
    return "blizzard"
  end
  return "ours"
end

local function apply()
  local m = mode()
  local own = m == "ours"
  Zoom.own = own
  local k = 1
  if own then
    Minimap:SetZoom(0)  -- our scale is relative to Blizzard's farthest view
    k = STEPS[Zoom.step]
  elseif m == "blizzard" then
    Minimap:SetZoom(levelFor(Zoom.step))
  end
  -- Hidden, not faded: at alpha 0 the engine still drew its blips over our map, at its own scale (seen
  -- in game). BubbleQuest's quest layer lives on our map frame (its SetMinimapView), so it stays.
  Minimap:SetShown(not own)
  -- Not own, our terrain follows Blizzard's actual radius at its level (zoom 1: its GetViewRadius).
  ns.Terrain.zoom = k
  -- One ground in both: ours (Blizzard's was duller: the colour changed with the mode, seen in game).
  -- Indoors and off our data Terrain leaves Blizzard's ground on.
  ns.Terrain.force = true
  if arrow then
    arrow:SetShown(own)
  end
  local quest = ns.Quest
  if quest and quest.SetMinimapZoom then
    quest.SetMinimapZoom(k, own)
  end
end

local lastState  -- what apply() last ran for, so it runs only on a change

---Re-decide whose map shows (tracking changed, indoors, the setting, the step).
function Zoom:Update()
  local m = mode()
  local state = ("%s:%d"):format(m, self.step)
  if state ~= lastState then
    lastState = state
    apply()
  end
end

---One wheel notch or zoom button: delta > 0 zooms in, < 0 out.
---@param delta number
function Zoom:Step(delta)
  if mode() == "native" then
    local level = Minimap:GetZoom() + (delta > 0 and 1 or -1)
    if level >= 0 and level < Minimap:GetZoomLevels() then
      Minimap:SetZoom(level)
    end
    return
  end
  local step = math.max(1, math.min(#STEPS, self.step - (delta > 0 and 1 or -1)))
  if step ~= self.step then
    self.step = step
    self:Update()
  end
  showSlider()
end

-- Every frame: whose map, re-decided (cheap: a few API reads); the arrow turns with the player.
local function update()
  Zoom:Update()
  if not Zoom.own then
    return
  end
  -- apiguard: allow the argument is a constant string, never a secret value
  local rotating = GetCVarBool("rotateMinimap") and not C_Minimap.IsRotateMinimapIgnored()
  arrowTexture:SetRotation(rotating and 0 or (GetPlayerFacing() or 0))
end

---One line for /bmap.
---@return string
function Zoom:Describe()
  local m = mode()
  if m == "native" then
    return ("Blizzard's minimap (no terrain here), level %d"):format(Minimap:GetZoom())
  end
  return ("zoom x%.2f of Blizzard's farthest: %s (gather mode %s)"):format(STEPS[self.step],
    self.own and "our map" or ("Blizzard's minimap at level %d"):format(Minimap:GetZoom()), ns.DB.gatherMode)
end

-- The zoom slider (user's design): vertical, at the map's right edge while zooming, closer at the top.
-- A tick per step, the same in both modes; the middle tick wider and gold: Blizzard's farthest view.
-- In gather mode the steps Blizzard's minimap shows at are marked with a dot. Log scale: equal gaps.
local SLIDER_HEIGHT, SLIDER_INSET = 120, 8
local slider, sliderTicks, sliderDots, sliderMarker, sliderShown = nil, {}, {}, nil, 0
local LOG_MIN, LOG_MAX = math.log(STEPS[1]), math.log(STEPS[#STEPS])

local function sliderY(k)
  -- 0 at the bottom (farthest out), SLIDER_HEIGHT at the top (closest in).
  return (LOG_MAX - math.log(k)) / (LOG_MAX - LOG_MIN) * SLIDER_HEIGHT
end

local function layoutSlider(frame, marker)
  local gather = gathering()
  for i, k in ipairs(STEPS) do
    local tick = sliderTicks[i]
    if not tick then
      tick = frame:CreateTexture(nil, "ARTWORK")
      sliderTicks[i] = tick
    end
    local middle = i == DEFAULT_STEP
    tick:SetSize(middle and 14 or 7, middle and 2 or 1)
    if middle then
      tick:SetColorTexture(1, 0.82, 0, 1)
    else
      tick:SetColorTexture(1, 1, 1, 0.6)
    end
    tick:ClearAllPoints()
    tick:SetPoint("CENTER", frame, "BOTTOM", 0, sliderY(k))
    local dot = sliderDots[i]
    if not dot then
      dot = frame:CreateTexture(nil, "ARTWORK", nil, 1)
      dot:SetSize(3, 3)
      dot:SetColorTexture(0.4, 0.9, 0.4, 1)
      sliderDots[i] = dot
    end
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", frame, "BOTTOM", -8, sliderY(k))
    dot:SetShown(gather and levelFor(i) ~= nil)
  end
  marker:ClearAllPoints()
  marker:SetPoint("CENTER", frame, "BOTTOM", 0, sliderY(STEPS[Zoom.step]))
end

local function createSlider(outer)
  slider = CreateFrame("Frame", nil, outer)
  ns.Around.OverMap(slider)
  slider:SetSize(16, SLIDER_HEIGHT)
  slider:SetPoint("RIGHT", outer, "RIGHT", -SLIDER_INSET, 0)
  slider:SetAlpha(0)
  local back = slider:CreateTexture(nil, "BACKGROUND")
  back:SetPoint("TOPLEFT", -6, 6)
  back:SetPoint("BOTTOMRIGHT", 2, -6)
  back:SetColorTexture(0, 0, 0, 0.45)
  local track = slider:CreateTexture(nil, "BORDER")
  track:SetPoint("TOP")
  track:SetPoint("BOTTOM")
  track:SetWidth(1)
  track:SetColorTexture(1, 1, 1, 0.35)
  sliderMarker = slider:CreateTexture(nil, "OVERLAY")
  sliderMarker:SetSize(8, 8)
  sliderMarker:SetColorTexture(1, 1, 1, 1)
  slider:SetScript("OnUpdate", function(self, delta)
    sliderShown = sliderShown + delta
    if sliderShown >= SLIDER_HOLD + SLIDER_FADE then
      self:SetAlpha(0)
      self:Hide()
    elseif sliderShown > SLIDER_HOLD then
      self:SetAlpha(1 - (sliderShown - SLIDER_HOLD) / SLIDER_FADE)
    end
  end)
  slider:Hide()
end

showSlider = function()
  local frame, marker = slider, sliderMarker
  if not frame or not marker or mode() == "native" then
    return
  end
  layoutSlider(frame, marker)
  sliderShown = 0
  frame:SetAlpha(1)
  frame:Show()
end

table.insert(ns.Minimap.onActivate, function(outer)
  createSlider(outer)
  -- Our player arrow, over the map at its centre (the player).
  arrow = CreateFrame("Frame", nil, outer)
  ns.Around.OverMap(arrow)
  arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  arrow:SetPoint("CENTER", outer, "CENTER")
  arrowTexture = arrow:CreateTexture(nil, "OVERLAY")
  arrowTexture:SetAllPoints()
  arrowTexture:SetTexture(ARROW)
  arrow:Hide()

  -- The wheel over our frame (the padding; all of it while Blizzard's minimap is hidden). Created out
  -- of combat: activation waits for it.
  outer:EnableMouseWheel(true)
  outer:SetScript("OnMouseWheel", function(_, delta) Zoom:Step(delta) end)
  -- Over Blizzard's square its handler has zoomed its own level: put it back (apply) and step ours. Not
  -- indoors / off our terrain: there its own zoom is the zoom. A post-hook: its handler runs untouched.
  Minimap:HookScript("OnMouseWheel", function(_, delta)
    if mode() == "native" then
      return
    end
    lastState = nil  -- re-apply: Blizzard's level back where the step puts it
    Zoom:Step(delta)
    Zoom:Update()
  end)

  local driver = CreateFrame("Frame", nil, outer)
  driver:SetScript("OnUpdate", update)
  Zoom:Update()
end)
