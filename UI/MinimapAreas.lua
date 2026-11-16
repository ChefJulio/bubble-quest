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
local MARKER_SIZE = 16       -- the turn-in "?", pixels at 100% (setting map.iconSize)
-- Pixels, not yards: a minimap is small (140 px across for 233 yd each way in review, 0.3 px a yard),
-- so "too close for a line" is the arrows' "here" (yards, Navigation), never a pixel threshold.
local DOT_SIZE = 5           -- guide dots
local DOT_SPACING = 8        -- between guide dots
local DOT_SPEED = 10         -- a second, the dots' drift toward the target
local DOT_ALPHA = 0.9
local PLAYER_GAP = 7         -- no dots this close to the centre (the player's arrow)
local HOVER_MIN = 6          -- a circle's hover radius at least this, however far out the minimap zooms
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
local blobs, markers, dots, givers = {}, {}, {}, {}
local used = { blobs = 0, markers = 0, dots = 0, givers = 0 }

local function acquire(pool, kind, texture, drawLayer)
  used[kind] = used[kind] + 1
  local t = pool[used[kind]]
  if not t then
    t = layer:CreateTexture(nil, drawLayer)
    if type(texture) == "function" then
      texture(t)  -- sets its own art (the turn-in "?": an atlas)
    else
      t:SetTexture(texture)
    end
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

-- World offset (yards north, yards west of the player) to minimap pixels from its centre.
local function project(north, west, cos, sin, scale)
  local x, y = -west * scale, north * scale  -- north up, east right
  return x * cos + y * sin, -x * sin + y * cos
end

-- Available quests (UI/MapAvailable.lua's entries) ----------------------------------------------------
-- Quest givers' "!" at their spawns; quests from drops as the uniform bronze "!" at each droppers'
-- cluster centre (no areas here: the minimap is small). Rebuilt when the entries are.

local GIVER_SIZE, DROP_ICON_SIZE = 12, 9  -- pixels at 100% (setting map.iconSize)
local giverPoints, giversBuiltFor = {}, nil
MinimapAreas.giverHits = {}

local function rebuildGivers()
  wipe(giverPoints)
  for _, entry in ipairs(ns.MapAvailable:Entries()) do
    if entry.giver.kind == "item" then
      for _, cluster in ipairs(entry.clusters) do
        local c = cluster.centre
        giverPoints[#giverPoints + 1] = { x = c.x, y = c.y, map = c.map, entry = entry, drop = true }
      end
    else
      for _, p in ipairs(entry.giver.points) do
        giverPoints[#giverPoints + 1] = { x = p.x, y = p.y, map = p.map, entry = entry }
      end
    end
  end
  giversBuiltFor = ns.MapAvailable.builtFor
end

-- A giver icon, its art set only when what it shows changes (several looks share one pool).
local function acquireGiver(entry)
  used.givers = used.givers + 1
  local t = givers[used.givers]
  if not t then
    t = layer:CreateTexture(nil, "OVERLAY", nil, 2)
    t:AddMaskTexture(mask)
    givers[used.givers] = t
  end
  local art = entry.giver.kind == "item" and "drop"
    or ((entry.repeatable and "r" or "n") .. (entry.trivial and "t" or ""))
  if t.art ~= art then
    t.art = art
    ns.MapAvailable.SetArt(t, entry)
  end
  t:Show()
  return t
end

local function drawGivers(north, west, instanceMap, cos, sin, scale, half, square)
  local hits = MinimapAreas.giverHits
  local iconScale = ns.MapAreas.iconScale()
  local reach = half + GIVER_SIZE * iconScale / 2
  for _, p in ipairs(giverPoints) do
    if p.map == instanceMap then
      local x, y = project(p.x - north, p.y - west, cos, sin, scale)
      local inside
      if square then
        inside = math.abs(x) <= reach and math.abs(y) <= reach
      else
        inside = x * x + y * y <= reach * reach
      end
      if inside then
        local size = (p.drop and DROP_ICON_SIZE or GIVER_SIZE) * iconScale
        place(acquireGiver(p.entry), x, y, size)
        hits[#hits + 1] = { x = x, y = y, radius = math.max(size / 2, HOVER_MIN), entries = { p.entry } }
      end
    end
  end
end

-- The guide ---------------------------------------------------------------------------------------

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

-- Its quest: the hovered card (that one only: it's what you're asking about), else the pinned quests
-- in pin order, then the cards top to bottom: the first with somewhere to go on this continent (a
-- pinned "raise your skill" quest has nowhere, and shouldn't hide the line).
local function candidates()
  local pins = ns.DB.char.pins
  local list = {}
  for _, questID in ipairs(ns.Stack.order) do
    if pins[questID] then
      list[#list + 1] = questID
    end
  end
  table.sort(list, function(a, b) return pins[a] < pins[b] end)
  for _, questID in ipairs(ns.Stack.order) do
    if not pins[questID] then
      list[#list + 1] = questID
    end
  end
  return list
end

local function pickGuide()
  local hovered = ns.MapAreas.cardHover
  if hovered and ns.Stack.visible[hovered] then
    return hovered, guideTarget(hovered)
  end
  for _, questID in ipairs(candidates()) do
    local point = guideTarget(questID)
    if point then
      return questID, point
    end
  end
  return nil, nil
end

local guide = { elapsed = TARGET_SECONDS }  -- questID, point: refreshed every TARGET_SECONDS

-- Drawing -----------------------------------------------------------------------------------------

-- One "?" per spot (review: two showed, a little apart): the same turn-in from two sources a few yards
-- apart, or two quests handed in to one NPC.
local placedMarkers, markerSize = {}, 0  -- x1, y1, x2, y2, ... this frame
local function markerNear(x, y)
  local limit = markerSize * 0.75
  for i = 1, #placedMarkers, 2 do
    if math.abs(placedMarkers[i] - x) < limit and math.abs(placedMarkers[i + 1] - y) < limit then
      return true
    end
  end
  return false
end

local function drawAreas(north, west, instanceMap, cos, sin, scale, half, square)
  local size = 2 * ns.MapAreas.blobYards() * scale
  local alpha = ns.MapAreas.blobAlpha()
  local reach = half + size / 2  -- a circle partly inside still shows its inside part
  local hits = MinimapAreas.hits
  wipe(hits)
  wipe(placedMarkers)
  markerSize = MARKER_SIZE * ns.MapAreas.iconScale()
  -- The whole circle: on the minimap they're small (the world map's 70% core was too fiddly in review).
  MinimapAreas.radius = math.max(size / 2, HOVER_MIN)
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
        if not p.objective and not ns.MapAreas.GameMarksTurnIn(p.questID) and not markerNear(x, y) then
          place(acquire(markers, "markers", ns.MapAreas.setTurninArt, "OVERLAY"), x, y, markerSize)
          placedMarkers[#placedMarkers + 1] = x
          placedMarkers[#placedMarkers + 1] = y
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
    guide.questID, guide.point = pickGuide()
  end
  local target = guide.point
  if not target or target.map ~= instanceMap then
    return
  end
  local x, y = project(target.x - north, target.y - west, cos, sin, scale)
  local length = math.sqrt(x * x + y * y)
  if length <= PLAYER_GAP then
    return  -- under the player's arrow
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
    local fade = math.min(1, (d - PLAYER_GAP) / DOT_SPACING)
    dot:SetVertexColor(color[1], color[2], color[3], DOT_ALPHA * fade)
    place(dot, dx * d, dy * d, DOT_SIZE)
  end
end

-- Hover -------------------------------------------------------------------------------------------
-- As on the world map: worked out from the cursor (the circles take no mouse), the same content. In our
-- own tooltip, not GameTooltip: while the cursor is on the minimap, Blizzard's Minimap_OnUpdate takes
-- GameTooltip every frame for the blips under it (SetMinimapMouseover, Blizzard_Minimap/Mainline/
-- Minimap.lua:279), hiding it when there are none, so ours never lasted a frame (seen in review). When a
-- blip's tooltip is up too, ours hangs under it instead of covering it.

local tooltip  -- created with the layer
local hoverElapsed = 0
local function updateHover(delta)
  hoverElapsed = hoverElapsed + delta
  if hoverElapsed < HOVER_SECONDS then
    return
  end
  hoverElapsed = 0
  -- A quest giver under the cursor first (its icon sits on top), else the quest areas.
  local found, offers
  if Minimap:IsMouseOver() and (#MinimapAreas.hits > 0 or #MinimapAreas.giverHits > 0) then
    local cx, cy = GetCursorPosition()
    local scale = layer:GetEffectiveScale()
    local mx, my = layer:GetCenter()
    local x, y = cx / scale - mx, cy / scale - my
    offers = ns.MapAvailable.Under(MinimapAreas.giverHits, x, y)
    found = not offers and ns.MapAreas.Under(MinimapAreas.hits, MinimapAreas.radius, x, y) or nil
  end
  if not (found or offers) or ns.Tooltips:Suppressed() then  -- Ctrl hides our tooltips (UI/Tooltips.lua)
    tooltip:Hide()
    return
  end
  local blip = GameTooltip:IsShown()
  ns.Tooltips:Take(layer, blip and "ANCHOR_NONE" or "ANCHOR_CURSOR", nil, tooltip)
  if blip then
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2)
  end
  if offers then
    ns.MapAvailable.FillTooltip(tooltip, offers)
  else
    ns.MapAreas.FillTooltip(tooltip, found)
  end
end

local function update(_, delta)
  local map = settings()
  local showAreas, showGuide = map and map.minimapAreas, map and map.guide
  local showGivers = ns.MapAvailable:Enabled()
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  wipe(MinimapAreas.hits)
  wipe(MinimapAreas.giverHits)
  if north and (showAreas or showGuide or showGivers) then
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
    if showGivers then
      ns.MapAvailable:Entries()
      if giversBuiltFor ~= ns.MapAvailable.builtFor then
        rebuildGivers()
      end
      drawGivers(north, west, instanceMap, cos, sin, scale, half, square)
    end
    if showGuide then
      drawGuide(north, west, instanceMap, cos, sin, scale, half, square, delta)
    end
  end
  MinimapAreas.dotsDrawn = used.dots  -- for /qm minimap (hideUnused resets the count)
  hideUnused(blobs, "blobs")
  hideUnused(markers, "markers")
  hideUnused(dots, "dots")
  hideUnused(givers, "givers")
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
  tooltip = CreateFrame("GameTooltip", "QuestmarkerMinimapTooltip", UIParent, "GameTooltipTemplate")
  layer:SetScript("OnHide", function() tooltip:Hide() end)
end

ns.Events:On("PLAYER_LOGIN", create)

---For /qm minimap: what the minimap layer sees right now, one frame run under pcall so an error shows.
---@return string[]
function MinimapAreas:Diagnose()
  local lines = {}
  local function add(text, ...)
    lines[#lines + 1] = text:format(...)
  end
  local map = settings()
  add("Settings: areas=%s guide=%s", tostring(map and map.minimapAreas), tostring(map and map.guide))
  add("Layer: %s, shown=%s visible=%s", layer and "created" or "MISSING", tostring(layer and layer:IsShown()),
    tostring(layer and layer:IsVisible()))
  if not layer then
    return lines
  end
  local ok, err = pcall(update, layer, 0)
  add("One frame: %s", ok and "ok" or ("ERROR " .. tostring(err)))
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  add("Player: %s, %s on map %s", tostring(north), tostring(west), tostring(instanceMap))
  add("Minimap: width %.1f, view radius %s yd, square=%s, rotation %.2f", Minimap:GetWidth(),
    tostring(C_Minimap.GetViewRadius()), tostring(isSquare()), rotation())
  add("Points %d (version %s of %s), circles drawn %d, hover radius %.1f px", #self.points, tostring(self.version),
    tostring(ns.MapAreas.version), #self.hits, self.radius or 0)
  add("Guide: quest %s, point %s, dots drawn %d", tostring(guide.questID),
    guide.point and ("%.1f, %.1f map %s"):format(guide.point.x, guide.point.y, tostring(guide.point.map)) or "none",
    self.dotsDrawn or 0)
  for _, questID in ipairs(candidates()) do
    local quest = ns.QuestLog:Get(questID)
    local keys = {}
    for key in pairs(quest and ns.Navigation:Targets(quest).byObjective or {}) do
      local nav = ns.Navigation:ObjectiveNav(quest, key)
      keys[#keys + 1] = ("%s=%s"):format(tostring(key), not nav and "nil" or nav.zone and ("zone " .. nav.zone)
        or ("%.0fyd%s"):format(nav.distance, nav.inArea and " here" or ""))
    end
    add("  candidate %d %s%s: %s", questID, quest and tostring(quest.title) or "?",
      ns.DB.char.pins[questID] and " (pinned)" or "", #keys > 0 and table.concat(keys, ", ") or "no targets")
  end
  local cx, cy = GetCursorPosition()
  local scale = layer:GetEffectiveScale()
  local mx, my = layer:GetCenter()
  local px, py = cx / scale - mx, cy / scale - my
  local nearest
  for _, hit in ipairs(self.hits) do
    local d = math.sqrt((hit.x - px) ^ 2 + (hit.y - py) ^ 2)
    nearest = nearest and math.min(nearest, d) or d
  end
  add("Mouse over minimap: %s; cursor from centre %.1f, %.1f px; nearest circle %s px away",
    tostring(Minimap:IsMouseOver()), px, py, nearest and ("%.1f"):format(nearest) or "-")
  add("Our tooltip: shown=%s; GameTooltip (blips): shown=%s", tostring(tooltip:IsShown()),
    tostring(GameTooltip:IsShown()))
  return lines
end
