local ADDON_NAME, ns = ...

-- Zoom past Blizzard's farthest minimap level (build step 6, zooming out): the overview. Design:
-- docs/design/questmarker-map.md ("Zoom").
--
-- One range: Blizzard's own levels (Minimap:SetZoom, 0 farthest), then OVERVIEW steps beyond level 0,
-- each reaching FACTORS[step] times further than level 0 shows. In overview:
--   - Blizzard's minimap is faded out (alpha 0): its ground and blips only exist at its own scale.
--     That loses the blips (herbs, ore, party): the honest limit of an overview.
--   - Our terrain (Terrain.lua) is the whole map, at the wider scale; we draw the player's arrow.
--   - BubbleQuest's quest areas scale with it (BubbleQuestAPI.SetMinimapZoom) and stay visible.
-- Only where our terrain exists: outdoors, on a continent in Data/Tiles.lua. Anywhere else (indoors,
-- instances) the overview ends and Blizzard's minimap comes back.
--
-- The mouse wheel: over Blizzard's square it reaches Minimap's own OnMouseWheel first (Blizzard zooms,
-- Mainline/Minimap.lua:146-152), and a post-hook (HookScript) carries it on: out past level 0 into the
-- overview, in from the overview back to level 0 (undoing Blizzard's step in, which has already
-- happened). Over the padding nothing of Blizzard's takes the wheel, so our map frame does, through
-- the same Step.

local FACTORS = { 1.6, 2.5, 4, 6 }  -- per overview step: times level 0's reach
local ARROW = "Interface\\Minimap\\MinimapArrow"
local ARROW_SIZE = 32

local Zoom = {
  step = 0,  -- 0: Blizzard's own levels; 1..#FACTORS: overview
}
ns.Zoom = Zoom

local arrow, arrowTexture, lastZoom

local function factor()
  return Zoom.step > 0 and FACTORS[Zoom.step] or 1
end

-- The overview needs our terrain under the player.
local function available()
  if IsIndoors() then
    return false
  end
  local _, _, _, mapID = UnitPosition("player")
  return mapID ~= nil and ns.Tiles.maps[mapID] ~= nil
end

local function apply()
  local k = factor()
  ns.Terrain.zoom = k
  Minimap:SetAlpha(k > 1 and 0 or 1)
  if arrow then
    arrow:SetShown(k > 1)
  end
  local quest = ns.Quest
  if quest and quest.SetMinimapZoom then
    quest.SetMinimapZoom(k)
  end
end

local function setStep(step)
  step = math.max(0, math.min(#FACTORS, step))
  if step ~= Zoom.step then
    Zoom.step = step
    apply()
  end
end

---One wheel notch or zoom button: delta > 0 zooms in, < 0 out, across Blizzard's levels and ours.
---@param delta number
function Zoom:Step(delta)
  local level = Minimap:GetZoom()
  if delta < 0 then
    if self.step > 0 or level == 0 then
      if available() then
        setStep(self.step + 1)
      end
    else
      Minimap:SetZoom(level - 1)
    end
  elseif delta > 0 then
    if self.step > 0 then
      setStep(self.step - 1)
    elseif level < Minimap:GetZoomLevels() - 1 then
      Minimap:SetZoom(level + 1)
    end
  end
  lastZoom = Minimap:GetZoom()
end

-- After Blizzard's own wheel handler on the minimap: it has zoomed already (or couldn't).
local function afterBlizzardWheel(_, delta)
  local level = Minimap:GetZoom()
  if delta < 0 and level == 0 and lastZoom == 0 then
    -- Blizzard was already at its farthest: on into the overview.
    if available() then
      setStep(Zoom.step + 1)
    end
  elseif delta > 0 and Zoom.step > 0 then
    -- In the overview Blizzard's step in went to level 1: back to 0, and one overview step in instead.
    Minimap:SetZoom(0)
    setStep(Zoom.step - 1)
  end
  lastZoom = Minimap:GetZoom()
end

-- Every frame while the map shows: the arrow turns with the player, and the overview ends where our
-- terrain doesn't reach.
local function update()
  lastZoom = Minimap:GetZoom()
  if Zoom.step == 0 then
    return
  end
  if not available() then
    setStep(0)
    return
  end
  -- apiguard: allow the argument is a constant string, never a secret value
  local rotating = GetCVarBool("rotateMinimap") and not C_Minimap.IsRotateMinimapIgnored()
  arrowTexture:SetRotation(rotating and 0 or (GetPlayerFacing() or 0))
end

---One line for /bmap.
---@return string
function Zoom:Describe()
  return ("zoom: Blizzard level %d of %d, overview %s"):format(Minimap:GetZoom(), Minimap:GetZoomLevels() - 1,
    self.step > 0 and ("x%.1f"):format(factor()) or "off")
end

table.insert(ns.Minimap.onActivate, function(outer)
  -- The player's arrow in the overview, over the map at its centre (the player).
  arrow = CreateFrame("Frame", nil, outer)
  ns.Around.OverMap(arrow)
  arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  arrow:SetPoint("CENTER", Minimap, "CENTER")
  arrowTexture = arrow:CreateTexture(nil, "OVERLAY")
  arrowTexture:SetAllPoints()
  arrowTexture:SetTexture(ARROW)
  arrow:Hide()

  -- The wheel over the padding (our frame; it takes no clicks, only the wheel). Created out of combat
  -- (activation waits for it).
  outer:EnableMouseWheel(true)
  outer:SetScript("OnMouseWheel", function(_, delta) Zoom:Step(delta) end)
  Minimap:HookScript("OnMouseWheel", afterBlizzardWheel)

  local driver = CreateFrame("Frame", nil, outer)
  driver:SetScript("OnUpdate", update)
  lastZoom = Minimap:GetZoom()
end)
