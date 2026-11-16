local ADDON_NAME, ns = ...

-- Quest areas on the minimap (review): the world map's circles (UI/MapAreas.lua) around you, same
-- colours, same turn-in "?", clipped to the minimap's shape by a mask so they fade off at its edge
-- rather than pop. Plus the guide: a faint line of dots drifting from you toward one quest's target,
-- the point its card's arrow aims at (Navigation.current). Which quest (decided in review): the card
-- you're hovering, else your first pinned quest, else the top card.
--
-- How: our own mouse-disabled frame on the Minimap, textures placed by hand each frame (the minimap
-- moves and may rotate every frame). The view's size comes from C_Minimap.GetViewRadius (yards from
-- the centre to the edge), as Blizzard's HybridMinimap does. Nothing outdoors-only: UnitPosition is
-- nil in instances, which hides everything.

local MARKER_SIZE = 14       -- the turn-in "?", pixels
local DOT_SIZE = 5           -- guide dots, pixels
local DOT_SPACING = 11       -- pixels between guide dots
local DOT_SPEED = 14         -- pixels a second the dots drift toward the target
local DOT_ALPHA = 0.8
local PLAYER_GAP = 10        -- no dots this close to the centre (the player's arrow)
local ROUND_MASK = "Interface/CharacterFrame/TempPortraitAlphaMask"
local SQUARE_MASK = "Interface/BUTTONS/WHITE8X8"

local MinimapAreas = {
  version = -1,     -- MapAreas.version the point list was built for
  points = {},      -- { x, y (world yards), map, color, turnin }
}
ns.MinimapAreas = MinimapAreas

local profile = function() return ns.DB.profile and ns.DB.profile.map end

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
          x = p.x, y = p.y, map = p.map, color = color, turnin = not entry.objective,
        }
      end
    end
  end
end

-- The guide's quest: hovered card, else first pinned, else top card.
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
        if p.turnin then
          place(acquire(markers, "markers", ns.MapAreas.TURNIN_TEXTURE, "OVERLAY"), x, y, MARKER_SIZE)
        end
      end
    end
  end
end

local function drawGuide(north, west, instanceMap, cos, sin, scale, half, square)
  local questID = guidedQuest()
  local target = questID and ns.Navigation.current[questID]
  if not target or target.map ~= instanceMap then
    return
  end
  local x, y = project(target.x - north, target.y - west, cos, sin, scale)
  local length = math.sqrt(x * x + y * y)
  if length <= PLAYER_GAP + DOT_SPACING then
    return  -- you're there
  end
  -- Stop at the target, or at the edge when it's off the minimap.
  local edge = square and half / math.max(math.abs(x), math.abs(y)) * length or half
  local stop = math.min(length, edge - DOT_SIZE)
  local dx, dy = x / length, y / length
  local color = ns.MapAreas:ColorFor(questID)
  local offset = (GetTime() * DOT_SPEED) % DOT_SPACING
  for d = PLAYER_GAP + offset, stop, DOT_SPACING do
    local dot = acquire(dots, "dots", ns.MapAreas.BLOB_TEXTURE, "OVERLAY")
    -- Fade in from the player, so the line starts softly.
    local fade = math.min(1, (d - PLAYER_GAP) / (2 * DOT_SPACING))
    dot:SetVertexColor(color[1], color[2], color[3], DOT_ALPHA * fade)
    place(dot, dx * d, dy * d, DOT_SIZE)
  end
end

local function update()
  local settings = profile()
  local areas, guide = settings and settings.minimapAreas, settings and settings.guide
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  if north and (areas or guide) then
    if areas and MinimapAreas.version ~= ns.MapAreas.version then
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
    if areas then
      drawAreas(north, west, instanceMap, cos, sin, scale, half, square)
    end
    if guide then
      drawGuide(north, west, instanceMap, cos, sin, scale, half, square)
    end
  end
  hideUnused(blobs, "blobs")
  hideUnused(markers, "markers")
  hideUnused(dots, "dots")
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
end

ns.Events:On("PLAYER_LOGIN", create)
