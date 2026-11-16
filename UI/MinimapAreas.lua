local ADDON_NAME, ns = ...

-- Quest areas on the minimap (review): the world map's circles (UI/MapAreas.lua) around you, same
-- colours, same turn-in "?", clipped to the minimap's shape by a mask so they fade off at its edge
-- rather than pop. Hover them for the world map's tooltip. Plus the guide: a line of dots drifting from
-- you toward one quest's nearest objective you aren't already at (its turn-in when ready). Which quest
-- (decided in review): the card you're hovering, else your first pinned quest, else the top card.
--
-- How: our own mouse-disabled frame on the Minimap, textures placed by hand each frame (the minimap
-- moves and may rotate every frame). The view's size comes from C_Minimap.GetViewRadius (yards from
-- the centre to the edge), as Blizzard's HybridMinimap does. UnitPosition is nil in instances, which
-- hides everything there.

local DOT_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Map\\dot"  -- tools/make_blob.py
local MARKER_SIZE = 14       -- the turn-in "?", pixels
local DOT_SIZE = 6           -- guide dots, pixels
local DOT_SPACING = 12       -- pixels between guide dots
local DOT_SPEED = 14         -- pixels a second the dots drift toward the target
local DOT_ALPHA = 0.9
local PLAYER_GAP = 10        -- no dots this close to the centre (the player's arrow)
local TARGET_SECONDS = 0.1   -- how often the guide's target is worked out again (the arrows' rate)
local HOVER_SECONDS = 0.05   -- how often the hover is checked while the cursor is on the minimap
local ROUND_MASK = "Interface/CharacterFrame/TempPortraitAlphaMask"
local SQUARE_MASK = "Interface/BUTTONS/WHITE8X8"

local MinimapAreas = {
  version = -1,     -- MapAreas.version the point list was built for
  points = {},      -- { x, y (world yards), map, color, questID, objective (nil: turn-in) }
  hits = {},        -- circles drawn this frame: { x, y (pixels from the centre), questID, objective }
}
ns.MinimapAreas = MinimapAreas

local function settings()
  return ns.DB.profile and ns.DB.profile.map
end

-- Shape and rotation ------------------------------------------------------------------------------

-- Minimap addons that make it square define the global GetMinimapShape (a long-standing convention).
local function isSquare()
  local shape = rawget(_G, "GetMinimapShape")
  return shape ~= nil and shape() == "SQUARE"
end

local function rotation()
  -- apiguard: allow the argument is a constant string, never a secret value
  if not GetCVarBool("rotateMinimap") or C_Minimap.IsRotateMinimapIgnored() then
    return 0
  end
  return GetPlayerFacing() or 0
end

-- Textures ----------------------------------------------------------------------------------------

local layer, mask
local blobs, markers, dots = {}, {}, {}
local used = { blobs = 0, markers = 0, dots = 0 }

local function acquire(pool, kind, texture, drawLayer)
  used[kind] = used[kind] + 1
  local t = pool[used[kind]]
  if not t then
    t = layer:CreateTexture(nil, drawLayer)
    t:SetTexture(texture)
    t:AddMaskTexture(mask)
    pool[used[kind]] = t
  end
  t:Show()
  return t
end

local function hideUnused(pool, kind)
  for i = used[kind] + 1, #pool do
    pool[i]:Hide()
  end
  used[kind] = 0
end

local function place(t, x, y, size)
  t:SetSize(size, size)
  t:ClearAllPoints()
  t:SetPoint("CENTER", layer, "CENTER", x, y)
end

-- The point list ----------------------------------------------------------------------------------
-- Rebuilt when the world map's would be (MapAreas.version): the cards' quests, merged spawns.

local function rebuild()
  wipe(MinimapAreas.points)
  MinimapAreas.version = ns.MapAreas.version
  for questID in pairs(ns.Stack.visible) do
    local quest = ns.QuestLog:Get(questID)
    if quest then
      local color = ns.MapAreas:ColorFor(questID)
      for _, entry in ipairs(ns.MapAreas:QuestPoints(quest)) do
        local p = entry.point
        MinimapAreas.points[#MinimapAreas.points + 1] = {
          x = p.x, y = p.y, map = p.map, color = color, questID = questID, objective = entry.objective,
        }
      end
    end
  end
end

-- The guide ---------------------------------------------------------------------------------------

-- Its quest: hovered card, else first pinned, else top card.
local function guidedQuest()
  local hovered = ns.MapAreas.cardHover
  if hovered and ns.Stack.visible[hovered] then
    return hovered
  end
  local pins, best, bestOrder = ns.DB.char.pins, nil, nil
  for _, questID in ipairs(ns.Stack.order) do
    local order = pins[questID]
    if order and (not bestOrder or order < bestOrder) then
      best, bestOrder = questID, order
    end
  end
  return best or ns.Stack.order[1]
end

-- Its target: the nearest of the quest's current objectives (or its turn-in) you aren't already in.
-- Not the card's arrow target: that one is "here" while you're in an area (review: no line showed
-- while killing one objective's mobs with the other's elsewhere).
local function guideTarget(questID)
  local quest = ns.QuestLog:Get(questID)
  if not quest then
    return nil
  end
  local best
  for key in pairs(ns.Navigation:Targets(quest).byObjective) do
    local nav = ns.Navigation:ObjectiveNav(quest, key)
    if nav and nav.point and not nav.inArea and (not best or nav.distance < best.distance) then
      best = nav
    end
  end
  return best and best.point
end

local guide = { elapsed = TARGET_SECONDS }  -- questID, point: refreshed every TARGET_SECONDS

-- Drawing -----------------------------------------------------------------------------------------

-- World offset (yards north, yards west of the player) to minimap pixels from its centre.
local function project(north, west, cos, sin, scale)
  local x, y = -west * scale, north * scale  -- north up, east right
  return x * cos + y * sin, -x * sin + y * cos
end

local function drawAreas(north, west, instanceMap, cos, sin, scale, half, square)
  local size = 2 * ns.MapAreas.blobYards() * scale
  local alpha = ns.MapAreas.blobAlpha()
  local reach = half + size / 2  -- a circle partly inside still shows its inside part
  local hits = MinimapAreas.hits
  wipe(hits)
  MinimapAreas.radius = size / 2 * 0.7  -- the circle's visible core, as on the world map
  for _, p in ipairs(MinimapAreas.points) do
    if p.map == instanceMap then
      local x, y = project(p.x - north, p.y - west, cos, sin, scale)
      local inside
      if square then
        inside = math.abs(x) <= reach and math.abs(y) <= reach
      else
        inside = x * x + y * y <= reach * reach
      end
      if inside then
        local blob = acquire(blobs, "blobs", ns.MapAreas.BLOB_TEXTURE, "ARTWORK")
        blob:SetVertexColor(p.color[1], p.color[2], p.color[3], alpha)
        place(blob, x, y, size)
        if not p.objective then
          place(acquire(markers, "markers", ns.MapAreas.TURNIN_TEXTURE, "OVERLAY"), x, y, MARKER_SIZE)
        end
        hits[#hits + 1] = { x = x, y = y, questID = p.questID, objective = p.objective }
      end
    end
  end
end

local function drawGuide(north, west, instanceMap, cos, sin, scale, half, square, delta)
  guide.elapsed = guide.elapsed + delta
  if guide.elapsed >= TARGET_SECONDS then
    guide.elapsed = 0
    guide.questID = guidedQuest()
    guide.point = guide.questID and guideTarget(guide.questID)
  end
  local target = guide.point
  if not target or target.map ~= instanceMap then
    return
  end
  local x, y = project(target.x - north, target.y - west, cos, sin, scale)
  local length = math.sqrt(x * x + y * y)
  if length <= PLAYER_GAP + DOT_SPACING then
    return  -- right next to it
  end
  -- Stop at the target, or at the edge when it's off the minimap.
  local edge = square and half / math.max(math.abs(x), math.abs(y)) * length or half
  local stop = math.min(length, edge - DOT_SIZE)
  local dx, dy = x / length, y / length
  local color = ns.MapAreas:ColorFor(guide.questID)
  local offset = (GetTime() * DOT_SPEED) % DOT_SPACING
  for d = PLAYER_GAP + offset, stop, DOT_SPACING do
    local dot = acquire(dots, "dots", DOT_TEXTURE, "OVERLAY")
    -- Fade in from the player, so the line starts softly.
    local fade = math.min(1, (d - PLAYER_GAP) / (2 * DOT_SPACING))
    dot:SetVertexColor(color[1], color[2], color[3], DOT_ALPHA * fade)
    place(dot, dx * d, dy * d, DOT_SIZE)
  end
end

-- Hover -------------------------------------------------------------------------------------------
-- As on the world map: worked out from the cursor (the circles take no mouse), the same tooltip, and
-- out of the way when another tooltip is up (a minimap blip, a Questie icon).

local hoverElapsed, hovering = 0, false
local function updateHover(delta)
  hoverElapsed = hoverElapsed + delta
  if hoverElapsed < HOVER_SECONDS then
    return
  end
  hoverElapsed = 0
  local found
  if Minimap:IsMouseOver() and #MinimapAreas.hits > 0 then
    local cx, cy = GetCursorPosition()
    local scale = layer:GetEffectiveScale()
    local mx, my = layer:GetCenter()
    found = ns.MapAreas.Under(MinimapAreas.hits, MinimapAreas.radius, cx / scale - mx, cy / scale - my)
  end
  local tooltipBusy = GameTooltip:IsShown() and GameTooltip:GetOwner() ~= layer
  if found and not tooltipBusy then
    ns.MapAreas.ShowTooltip(layer, found)
    hovering = true
  elseif hovering and not found then
    if GameTooltip:GetOwner() == layer then
      GameTooltip:Hide()
    end
    hovering = false
  end
end

local function update(_, delta)
  local map = settings()
  local showAreas, showGuide = map and map.minimapAreas, map and map.guide
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  wipe(MinimapAreas.hits)
  if north and (showAreas or showGuide) then
    if showAreas and MinimapAreas.version ~= ns.MapAreas.version then
      rebuild()
    end
    local square = isSquare()
    if square ~= MinimapAreas.square then
      MinimapAreas.square = square
      mask:SetTexture(square and SQUARE_MASK or ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    local half = Minimap:GetWidth() / 2
    local scale = half / C_Minimap.GetViewRadius()  -- pixels per yard
    local facing = rotation()
    local cos, sin = math.cos(facing), math.sin(facing)
    if showAreas then
      drawAreas(north, west, instanceMap, cos, sin, scale, half, square)
    end
    if showGuide then
      drawGuide(north, west, instanceMap, cos, sin, scale, half, square, delta)
    end
  end
  hideUnused(blobs, "blobs")
  hideUnused(markers, "markers")
  hideUnused(dots, "dots")
  updateHover(delta)
end

local function create()
  if layer then
    return
  end
  layer = CreateFrame("Frame", nil, Minimap)
  layer:SetAllPoints(Minimap)
  layer:EnableMouse(false)
  layer:SetFrameLevel(Minimap:GetFrameLevel() + 2)
  mask = layer:CreateMaskTexture()
  mask:SetAllPoints(layer)
  -- Every frame while the minimap shows: it moves (and may turn) every frame.
  layer:SetScript("OnUpdate", update)
  layer:SetScript("OnHide", function()
    if hovering and GameTooltip:GetOwner() == layer then
      GameTooltip:Hide()
    end
    hovering = false
  end)
end

ns.Events:On("PLAYER_LOGIN", create)
