local ADDON_NAME, ns = ...

-- Whose map, and zoom (build step 6, as decided with the user 2026-11-17). Design:
-- docs/design/questmarker-map.md ("Zoom").
--
-- Blizzard's minimap blips (herbs, ore, tracking, party, the game's quest "?" and "!") are only right
-- at Blizzard's own zoom levels and size: scaling its frame (behind a mask or a clipping parent) put
-- them in wrong places (experiments, 2026-11-17). So there are two modes, never a mix:
--
--   - OUR MAP (the usual): Blizzard's minimap hidden (Hide: at alpha 0 its blips still drew) with its zoom fixed at its
--     farthest level, and BubbleMap draws the whole map: our terrain (Terrain.lua), our player arrow,
--     BubbleQuest's quest layer (told the game draws nothing: SetMinimapZoom(k, true)). Our own zoom,
--     in and out, STEPS times Blizzard's farthest view.
--   - GATHER MODE: Blizzard's minimap shown, for its live blips, and the zoom is Blizzard's own levels
--     only, so the blips are always right. Our terrain is the ground under it.
--   - THE PEEK: Ctrl held, gather mode for as long as it's held (Zoom:Update).
--
-- Gather mode is a setting (BubbleMapDB.gatherMode): "auto" (while a tracking spell such as Find Herbs
-- is on: the player is gathering), "always" or "never". Indoors and wherever our terrain doesn't reach
-- (instances, maps not in Data/Tiles.lua), Blizzard's minimap is shown too: it has the interior maps.
--
-- The wheel: our map frame takes it over the padding. Over Blizzard's square, Blizzard's minimap takes it
-- (even at alpha 0, mouse off: the wheel is separate) and zooms its own level: in gather mode that's the
-- zoom; in our map a post-hook puts Blizzard's level back and steps ours (the blank-map bug, review).

-- Our map: times Blizzard's farthest view, x1.5 a step, as many in as out, so Blizzard's farthest view
-- sits in the middle of the zoom slider (user's call). Six each way (user: further and closer): out to a
-- zone or so, in until the tiles go soft (256 px per 533 yd; quest markers stay sharp).
local STEP_RATIO, STEPS_EACH_WAY = 1.5, 6
local STEPS = {}
for i = -STEPS_EACH_WAY, STEPS_EACH_WAY do
  STEPS[#STEPS + 1] = STEP_RATIO ^ i
end
local DEFAULT_STEP = STEPS_EACH_WAY + 1  -- 1: Blizzard's farthest view
-- Blizzard's outdoor levels as shares of its farthest view [Inferred: classic's radii, 233.3 down to
-- 66.7 yd; they matched the user's measurements at levels 0 and 1]: where gather mode sits on the slider.
local LEVEL_SHARES = { 1, 6 / 7, 5 / 7, 4 / 7, 3 / 7, 2 / 7 }

local SLIDER_HOLD, SLIDER_FADE = 1.2, 0.4  -- seconds shown after the last zoom, then fading out
local showSlider  -- set when the slider is created (below)
local ARROW = "Interface\\Minimap\\MinimapArrow"
local ARROW_SIZE = 32

local Zoom = {
  own = false,        -- our map is showing (else Blizzard's minimap)
  peeking = false,    -- Ctrl held in our map: the game's minimap for a look (Zoom:Update)
  step = DEFAULT_STEP,
  beyond = false,     -- gathering, but zoomed out past Blizzard's farthest level: our map until back in
}

local lastLevel  -- Blizzard's zoom level as of the last frame (to see its wheel hit its farthest)
ns.Zoom = Zoom

local arrow, arrowTexture

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

---The bar's gather button: a hard toggle of the mode (user's call): gather mode on (the game's minimap
---and its live blips) or off (our map only, whatever is tracked). Tracking itself is left alone.
function Zoom:ToggleGather()
  ns.DB.gatherMode = self:Gathering() and "never" or "always"
  self.beyond = false
  self:Update()
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

local function apply()
  local own = Zoom.own
  local k = own and STEPS[Zoom.step] or 1
  if own then
    Minimap:SetZoom(0)  -- our scale is relative to Blizzard's farthest view
  end
  -- Hidden, not faded: at alpha 0 the engine still drew its blips (herbs, the game's "?") over our map,
  -- at its own scale (seen in game). A hidden frame isn't drawn at all. BubbleQuest's quest layer lives
  -- on our map frame (its SetMinimapView), so it stays.
  Minimap:SetShown(not own)
  ns.Terrain.zoom = k
  -- One ground in both modes: ours. In gather mode Blizzard's minimap then draws only its blips over it
  -- (Terrain turns its ground off outdoors): its own ground was duller than our tiles, so the colour
  -- changed with the mode (seen in game). Indoors and off our data, Terrain leaves Blizzard's ground on.
  ns.Terrain.force = true
  if arrow then
    arrow:SetShown(own)
  end
  local quest = ns.Quest
  if quest and quest.SetMinimapZoom then
    quest.SetMinimapZoom(k, own)
  end
end

---Gather mode is on (the setting, and for "auto" a tracking spell).
---@return boolean
function Zoom:Gathering()
  return gathering()
end

---Re-decide whose map shows (tracking changed, indoors, the setting, zoomed past Blizzard's levels, the
---Ctrl peek).
---Gathering, the map is Blizzard's at its zoom levels and ours beyond them (user's design): zooming out
---past Blizzard's farthest level leaves gather mode for our map, zooming back in returns to it. The
---tracking spell stays on throughout.
function Zoom:Update()
  local gather = gathering()
  if not gather then
    self.beyond = false
  end
  -- The peek (user's idea): Ctrl held shows the game's minimap and its live blips at its farthest level,
  -- the widest its blips allow, whatever our zoom (user's call: a peek is "what's around me"); our terrain
  -- matched to it. No zooming while it's held (user's call): released, our map at exactly the zoom it
  -- had. Any Ctrl, anywhere: a flicker during Ctrl keybinds is fine (user's call). Only from our map: in
  -- gather mode the game's minimap is already showing, and a Ctrl there did nothing at some zooms and
  -- jumped at others (review), so there it does nothing at all and the wheel zooms as usual.
  local ours = terrainHere() and (not gather or self.beyond)
  self.peeking = ours and IsControlKeyDown()
  local own = ours and not self.peeking
  if own ~= self.own then
    if self.peeking then
      Minimap:SetZoom(0)
    end
    self.own = own
    apply()
  end
end

---One wheel notch or zoom button: delta > 0 zooms in, < 0 out.
---@param delta number
function Zoom:Step(delta)
  if self.peeking then
    return  -- the peek: no zooming while it's held
  end
  if self.own then
    -- Gathering and zooming back in to Blizzard's range: gather mode, at its farthest level.
    if self.beyond and delta > 0 and STEPS[self.step - 1] and STEPS[self.step - 1] <= 1 then
      self.beyond = false
      self:Update()
      return
    end
    local step = math.max(1, math.min(#STEPS, self.step - (delta > 0 and 1 or -1)))
    if step ~= self.step then
      self.step = step
      apply()
      showSlider()
    end
    return
  end
  -- Blizzard's map: out past its farthest level is our map (blips hidden: they'd be wrong there).
  if delta < 0 and Minimap:GetZoom() == 0 and terrainHere() then
    self.beyond = true
    self.step = DEFAULT_STEP + 1  -- the first step out past Blizzard's farthest
    self:Update()
    return
  end
  local level = Minimap:GetZoom() + (delta > 0 and 1 or -1)
  if level >= 0 and level < Minimap:GetZoomLevels() then
    Minimap:SetZoom(level)
    showSlider()
  end
end

-- Every frame: the arrow turns with the player; whose map, re-decided (cheap: a few API reads).
local function update()
  Zoom:Update()
  if not Zoom.own then
    lastLevel = Minimap:GetZoom()
    return
  end
  -- apiguard: allow the argument is a constant string, never a secret value
  local rotating = GetCVarBool("rotateMinimap") and not C_Minimap.IsRotateMinimapIgnored()
  arrowTexture:SetRotation(rotating and 0 or (GetPlayerFacing() or 0))
end

---One line for /bmap.
---@return string
function Zoom:Describe()
  if self.own then
    return ("our map, zoom x%.2f of Blizzard's farthest (gather mode %s%s)"):format(STEPS[self.step],
      ns.DB.gatherMode, self.beyond and ", zoomed out past it" or "")
  end
  return ("Blizzard's minimap, level %d of %d (gather mode %s%s)"):format(Minimap:GetZoom(),
    Minimap:GetZoomLevels() - 1, ns.DB.gatherMode, terrainHere() and "" or ", no terrain here")
end

-- The zoom slider (user's design): vertical, at the map's right edge while zooming, closer at the top.
-- A tick per step (in gather mode: per Blizzard level), the middle tick wider and gold: Blizzard's
-- farthest view. Placed on a log scale, so equal steps are equal gaps.
local SLIDER_HEIGHT, SLIDER_INSET = 120, 8
local slider, sliderTicks, sliderMarker, sliderShown = nil, {}, nil, 0
local LOG_MIN, LOG_MAX = math.log(STEPS[1]), math.log(STEPS[#STEPS])

local function sliderY(k)
  -- 0 at the bottom (farthest out), SLIDER_HEIGHT at the top (closest in).
  return (LOG_MAX - math.log(k)) / (LOG_MAX - LOG_MIN) * SLIDER_HEIGHT
end

local function sliderTick(frame, i)
  local tick = sliderTicks[i]
  if not tick then
    tick = frame:CreateTexture(nil, "ARTWORK")
    sliderTicks[i] = tick
  end
  return tick
end

local function layoutSlider(frame, marker)
  -- Gathering, one picture across both modes (review: the ticks changed as the wheel crossed into our
  -- map): Blizzard's levels above the middle, our steps out below it, where the wheel takes you next.
  local shares = STEPS
  if gathering() then
    shares = {}
    for _, k in ipairs(LEVEL_SHARES) do
      shares[#shares + 1] = k
    end
    for _, k in ipairs(STEPS) do
      if k > 1 then
        shares[#shares + 1] = k
      end
    end
  end
  local count = 0
  for _, k in ipairs(shares) do
    if k >= STEPS[1] then
      count = count + 1
      local tick = sliderTick(frame, count)
      local middle = math.abs(k - 1) < 0.001
      tick:SetSize(middle and 14 or 7, middle and 2 or 1)
      if middle then
        tick:SetColorTexture(1, 0.82, 0, 1)
      else
        tick:SetColorTexture(1, 1, 1, 0.6)
      end
      tick:ClearAllPoints()
      tick:SetPoint("CENTER", frame, "BOTTOM", 0, sliderY(k))
      tick:Show()
    end
  end
  for i = count + 1, #sliderTicks do
    sliderTicks[i]:Hide()
  end
  local k = Zoom.own and STEPS[Zoom.step] or (LEVEL_SHARES[Minimap:GetZoom() + 1] or 1)
  marker:ClearAllPoints()
  marker:SetPoint("CENTER", frame, "BOTTOM", 0, sliderY(k))
end

local function createSlider(outer)
  slider = CreateFrame("Frame", nil, outer)
  ns.Around.OverMap(slider)
  slider:SetSize(16, SLIDER_HEIGHT)
  slider:SetPoint("RIGHT", outer, "RIGHT", -SLIDER_INSET, 0)
  slider:SetAlpha(0)
  local back = slider:CreateTexture(nil, "BACKGROUND")
  back:SetPoint("TOPLEFT", -2, 6)
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
  if not frame or not marker then
    return
  end
  layoutSlider(frame, marker)
  -- Again next frame: Blizzard's zoom level may only read as changed then.
  C_Timer.After(0, function() layoutSlider(frame, marker) end)
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

  -- The wheel over our frame: all of it in our map, the padding in gather mode. (Created out of combat:
  -- activation waits for it.)
  outer:EnableMouseWheel(true)
  outer:SetScript("OnMouseWheel", function(_, delta) Zoom:Step(delta) end)
  -- Over Blizzard's square its minimap takes the wheel even with its mouse off (the wheel is separate),
  -- and zooms its own level. In our map that's not the zoom: put its level back (fixed at its farthest)
  -- and step ours instead. A post-hook: Blizzard's handler runs untouched.
  -- In gather mode Blizzard's handler zooms; at its farthest level already, the wheel out goes on into
  -- our map.
  -- During the Ctrl peek Blizzard's handler zoomed: back to its farthest level, the peek's view.
  Minimap:HookScript("OnMouseWheel", function(_, delta)
    if Zoom.peeking then
      Minimap:SetZoom(0)
    elseif Zoom.own then
      Minimap:SetZoom(0)
      Zoom:Step(delta)
    elseif delta < 0 and lastLevel == 0 then
      Zoom:Step(delta)
    else
      showSlider()  -- gather mode: Blizzard's handler zoomed; the slider shows it (it didn't: review)
    end
    lastLevel = Minimap:GetZoom()
  end)

  local driver = CreateFrame("Frame", nil, outer)
  driver:SetScript("OnUpdate", update)
  Zoom:Update()
end)
