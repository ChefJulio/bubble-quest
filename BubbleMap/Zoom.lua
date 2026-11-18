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
--
-- Gather mode is a setting (BubbleMapDB.gatherMode): "auto" (while a tracking spell such as Find Herbs
-- is on: the player is gathering), "always" or "never". Indoors and wherever our terrain doesn't reach
-- (instances, maps not in Data/Tiles.lua), Blizzard's minimap is shown too: it has the interior maps.
--
-- The wheel: our map frame takes it over the padding. Over Blizzard's square, Blizzard's minimap takes it
-- (even at alpha 0, mouse off: the wheel is separate) and zooms its own level: in gather mode that's the
-- zoom; in our map a post-hook puts Blizzard's level back and steps ours (the blank-map bug, review).

local STEPS = { 0.35, 0.5, 0.7, 1, 1.4, 2, 3, 4.5, 6 }  -- our map: times Blizzard's farthest view
local DEFAULT_STEP = 4                                -- 1: Blizzard's farthest view
local ARROW = "Interface\\Minimap\\MinimapArrow"
local ARROW_SIZE = 32

local Zoom = {
  own = false,        -- our map is showing (else Blizzard's minimap)
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

---The bar's gather button: a tracking spell on turns it off (our map, all its zoom); none on turns the
---last used one on (gather mode, when its setting is automatic). Blizzard's own tracking menu sets
---tracking the same way, from ordinary UI code.
function Zoom:ToggleGather()
  local spell = self:GatherSpell()
  if not spell then
    return
  end
  if spell.active then
    C_Minimap.SetTracking(spell.index, false)
  else
    C_Minimap.SetTracking(spell.index, true)
    ns.DB.lastGather = spell.name
    self.beyond = false  -- on: straight to gather mode
  end
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
  ns.Terrain.force = own
  if arrow then
    arrow:SetShown(own)
  end
  local quest = ns.Quest
  if quest and quest.SetMinimapZoom then
    quest.SetMinimapZoom(k, own)
  end
end

---Re-decide whose map shows (tracking changed, indoors, the setting, zoomed past Blizzard's levels).
---Gathering, the map is Blizzard's at its zoom levels and ours beyond them (user's design): zooming out
---past Blizzard's farthest level leaves gather mode for our map, zooming back in returns to it. The
---tracking spell stays on throughout.
function Zoom:Update()
  local gather = gathering()
  if not gather then
    self.beyond = false
  end
  local own = terrainHere() and (not gather or self.beyond)
  if own ~= self.own then
    self.own = own
    apply()
  end
end

---One wheel notch or zoom button: delta > 0 zooms in, < 0 out.
---@param delta number
function Zoom:Step(delta)
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

table.insert(ns.Minimap.onActivate, function(outer)
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
  Minimap:HookScript("OnMouseWheel", function(_, delta)
    if Zoom.own then
      Minimap:SetZoom(0)
      Zoom:Step(delta)
    elseif delta < 0 and lastLevel == 0 then
      Zoom:Step(delta)
    end
    lastLevel = Minimap:GetZoom()
  end)

  local driver = CreateFrame("Frame", nil, outer)
  driver:SetScript("OnUpdate", update)
  Zoom:Update()
end)
