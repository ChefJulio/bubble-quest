local ADDON_NAME, ns = ...

-- Quest areas on the minimap (review): the world map's circles (UI/MapAreas.lua) around you, same
-- colours, same turn-in "?", clipped to the minimap's shape by a mask so they fade off at its edge
-- rather than pop. Hover them for the world map's tooltip. Plus the guide: a line of dots drifting from
-- you toward one quest's nearest objective you aren't already at (its turn-in when ready). Which quest
-- (decided in review): the card you're hovering, else your first pinned quest, else the top card.
--
-- How: our own mouse-disabled frame on the Minimap, textures placed by hand each frame (the minimap
-- moves and may rotate every frame). BubbleMap can point it at its whole map frame instead
-- (BubbleQuestAPI.SetMinimapView): the frame is wider or taller than Blizzard's square and filled with
-- terrain, so the areas draw over all of it, centred on the player as before; width and height are
-- handled apart (halfW, halfH), as the frame needn't be square. The view's size comes from C_Minimap.GetViewRadius (yards from
-- the centre to the edge), as Blizzard's HybridMinimap does. UnitPosition is nil in instances, which
-- hides everything there.

local DOT_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Map\\dot"  -- tools/make_blob.py
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
  zoom = 1,         -- how many times further than Blizzard's minimap the view reaches (SetZoom); any value
                    -- in BubbleMap's own map
  gameHidden = false, -- BubbleMap has Blizzard's minimap hidden (its own map): the game draws no markers
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
      for _, entry in ipairs(ns.MapAreas:QuestPoints(quest)) do
        local p = entry.point
        MinimapAreas.points[#MinimapAreas.points + 1] = {
          x = p.x, y = p.y, map = p.map, questID = questID, objective = entry.objective,
          color = ns.MapAreas:ShadeFor(questID, entry.objective),  -- each objective its shade
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
local MERGE_SHARE = 0.8  -- icons closer than this share of their size merge into one (givers' "!")
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

-- Where the game draws its own minimap markers (the "?" of many ready quests, quest givers' "!"):
-- within its view radius (C_Minimap.GetViewRadius) of the centre, a circle, even when the minimap is
-- masked square (review, two BubbleMap zoom levels: a "?" in the square's corner went missing, as the
-- game no longer drew it and a square test still skipped ours). Ours is skipped only there: drawn in
-- the corners and in BubbleMap's padding, and everywhere while BubbleMap draws its own map with
-- Blizzard's minimap hidden (gameDraws).
-- Not the whole view circle: the game's own turn-in "?" vanished at 186.5 yd with a 233.3 yd view
-- radius and at 159.5 yd with 200 yd (measured in game, two zoom levels): 0.799 and 0.7975 of the
-- radius. Ours goes just inside that, as a marker shown twice at the edge beats none (review: the full
-- radius left a ring where neither showed; 0.78 still doubled one at 183 yd). Quest givers' "!"
-- assumed the same until measured.
local GAME_MARKER_SHARE = 0.795

-- Yards from the minimap's centre to its edge at Blizzard's zoom. The last good value when the game
-- gives none (BubbleMap hides Blizzard's minimap in its own map; it may not report while hidden), so
-- the scale never divides by nothing. 233.33: Blizzard's farthest outdoor level, before any reading.
local lastRadius = 233.33
local function viewRadius()
  local radius = C_Minimap.GetViewRadius()
  if type(radius) == "number" and radius > 0 then
    lastRadius = radius
  end
  return lastRadius
end

-- Half of Blizzard's minimap, in the layer's units: the layer may live on BubbleMap's frame (SetView),
-- whose scale needn't be the minimap's (Edit Mode scales the minimap).
local function minimapHalf()
  return Minimap:GetWidth() / 2 * Minimap:GetEffectiveScale() / layer:GetEffectiveScale()
end

local function inGameView(x, y)
  local reach = minimapHalf() * GAME_MARKER_SHARE
  return x * x + y * y <= reach * reach
end

-- Whether the game draws its quest markers on the minimap at all: not while BubbleMap draws its own map
-- with Blizzard's minimap hidden (SetZoom's gameHidden). There's no switch for them otherwise: with the QuestPOIs
-- tracking filter off, the game still drew its "?" and "!" (seen in game), so that filter isn't read.
local function gameDraws()
  return not MinimapAreas.gameHidden
end

-- The game's quest-giver "!" (review: two "!" a few pixels apart): drawn by the client, not readable
-- by addons (no API lists them, and the minimap blips aren't frames), for the givers it knows about:
-- those the server has sent, within its visibility range of the player. That range isn't documented
-- (players report 40-70 yd in the open world on classic-era clients), so this errs short: too short
-- leaves a few doubled "!" near its edge, too long would hide givers the game doesn't mark at all.
-- Tune with /bq givers. Low-level givers only while the game's "Low-level quests" tracking is on.
-- Drop-started quests have no giver for the game to mark.
local GAME_GIVER_YARDS = 50

local function gameMarksGiver(p, dNorth, dWest, x, y, trivialHidden)
  return not p.drop and inGameView(x, y) and dNorth * dNorth + dWest * dWest <= GAME_GIVER_YARDS ^ 2
    and not (p.entry.trivial and trivialHidden)
end

---For /bq givers: the `count` nearest quest givers on this map, nearest first, as lines "name: N yd",
---marked when within GAME_GIVER_YARDS (ours hidden there, inside the game's view). Measuring: walk
---away from a giver and note the distance at which the game's own "!" vanishes.
---@param count number
---@return string[]
function MinimapAreas:NearestGivers(count)
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  local nearest = {}
  if north then
    for _, p in ipairs(giverPoints) do
      if p.map == instanceMap and not p.drop then
        local yards = math.sqrt((p.x - north) ^ 2 + (p.y - west) ^ 2)
        nearest[#nearest + 1] = { yards = yards, name = p.entry.giver.name or "?" }
      end
    end
  end
  table.sort(nearest, function(a, b) return a.yards < b.yards end)
  local lines = { gameDraws()
    and ("Leaving the \"!\" to the game within %d yd (GAME_GIVER_YARDS)."):format(GAME_GIVER_YARDS)
    or "BubbleMap is drawing its own map: the game's minimap markers are hidden and every \"!\" is "
      .. "ours. To measure the game's range, use BubbleMap's gather mode (Blizzard's minimap shown)." }
  for i = 1, math.min(count, #nearest) do
    local g = nearest[i]
    lines[#lines + 1] = ("%s: %d yd%s"):format(g.name, g.yards + 0.5,
      gameDraws() and g.yards <= GAME_GIVER_YARDS and " (game's \"!\")" or "")
  end
  if #nearest == 0 then
    lines[#lines + 1] = "No quest givers known on this map (minimap layer off, or none)."
  end
  return lines
end

local function drawGivers(north, west, instanceMap, cos, sin, scale, halfW, halfH, square)
  local hits = MinimapAreas.giverHits
  local iconScale = ns.MapAreas.iconScale()
  local pad = GIVER_SIZE * iconScale / 2
  local reachW, reachH = halfW + pad, halfH + pad
  local dedupe = gameDraws()
  local trivialHidden = dedupe and C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.TrivialQuests)
  for _, p in ipairs(giverPoints) do
    if p.map == instanceMap then
      local dNorth, dWest = p.x - north, p.y - west
      local x, y = project(dNorth, dWest, cos, sin, scale)
      local inside
      if square then
        inside = math.abs(x) <= reachW and math.abs(y) <= reachH
      else
        inside = x * x + y * y <= reachW * reachW
      end
      if inside and not (dedupe and gameMarksGiver(p, dNorth, dWest, x, y, trivialHidden)) then
        local size = (p.drop and DROP_ICON_SIZE or GIVER_SIZE) * iconScale
        -- One "!" per spot (review: doubled "!" zoomed out): a giver's spawns, or givers side by side,
        -- that would overlap on screen share the first one drawn; its tooltip lists all their quests.
        local merged
        for _, hit in ipairs(hits) do
          if hit.drop == p.drop and math.abs(hit.x - x) < size * MERGE_SHARE
              and math.abs(hit.y - y) < size * MERGE_SHARE then
            merged = hit
            break
          end
        end
        if merged then
          if not tContains(merged.entries, p.entry) then
            merged.entries[#merged.entries + 1] = p.entry
          end
        else
          place(acquireGiver(p.entry), x, y, size)
          hits[#hits + 1] = {
            x = x, y = y, radius = math.max(size / 2, HOVER_MIN), entries = { p.entry }, drop = p.drop,
          }
        end
      end
    end
  end
end

-- The guide ---------------------------------------------------------------------------------------

-- Its target: Navigation:GuidePoint, shared with the world map's line (UI/MapAreas.lua).
local function guideTarget(questID)
  local quest = ns.QuestLog:Get(questID)
  return quest and ns.Navigation:GuidePoint(quest) or nil
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

-- The game shows its own "?" for this quest on the minimap right now: it marks the quest, and its
-- marker (where the game itself places it, Navigation:MarkerPoint) is inside the circle it draws in.
-- Decided by the game's position, not ours (review: walking from 182 to 190 yd, the game's "?" went
-- and ours didn't come, as our spot for the quest, a few yards nearer, was still inside the circle).
local function gameShowsTurnIn(questID, north, west, instanceMap, cos, sin, scale)
  if not ns.MapAreas.GameMarksTurnIn(questID) then
    return false
  end
  local marker = ns.Navigation:MarkerPoint(questID)
  if not marker or marker.map ~= instanceMap then
    return false
  end
  local x, y = project(marker.x - north, marker.y - west, cos, sin, scale)
  return inGameView(x, y)
end

local function drawAreas(north, west, instanceMap, cos, sin, scale, halfW, halfH, square)
  local size = 2 * ns.MapAreas.blobYards() * scale
  local alpha = ns.MapAreas.blobAlpha()
  -- A circle partly inside still shows its inside part.
  local reachW, reachH = halfW + size / 2, halfH + size / 2
  local hits = MinimapAreas.hits
  wipe(hits)
  wipe(placedMarkers)
  markerSize = ns.MapAreas.turninSize(GIVER_SIZE) * ns.MapAreas.iconScale()  -- matches the givers' "!"
  -- The whole circle: on the minimap they're small (the world map's 70% core was too fiddly in review).
  MinimapAreas.radius = math.max(size / 2, HOVER_MIN)
  local skipMarked = gameDraws()  -- once per frame, not per point
  -- One "?" per quest (review: two for one turn-in): where the sources know several spots (two
  -- databases a little apart, an NPC with more than one spawn), the one nearest you, as the arrow
  -- and its distance take.
  local nearestTurnin, nearestYards = {}, {}
  for _, p in ipairs(MinimapAreas.points) do
    if p.map == instanceMap and not p.objective then
      local yards = (p.x - north) ^ 2 + (p.y - west) ^ 2
      if not nearestYards[p.questID] or yards < nearestYards[p.questID] then
        nearestTurnin[p.questID], nearestYards[p.questID] = p, yards
      end
    end
  end
  for _, p in ipairs(MinimapAreas.points) do
    if p.map == instanceMap and (p.objective or nearestTurnin[p.questID] == p) then
      local x, y = project(p.x - north, p.y - west, cos, sin, scale)
      local inside
      if square then
        inside = math.abs(x) <= reachW and math.abs(y) <= reachH
      else
        inside = x * x + y * y <= reachW * reachW
      end
      if inside and p.objective then
        local blob = acquire(blobs, "blobs", ns.MapAreas.BLOB_TEXTURE, "ARTWORK")
        blob:SetVertexColor(p.color[1], p.color[2], p.color[3], alpha)
        place(blob, x, y, size)
        hits[#hits + 1] = { x = x, y = y, questID = p.questID, objective = p.objective }
      elseif inside and not (skipMarked and gameShowsTurnIn(p.questID, north, west, instanceMap, cos, sin, scale))
          and not markerNear(x, y) then
        -- A turn-in: just the "?" (review: the circle under it added nothing), still hoverable.
        place(acquire(markers, "markers", ns.MapAreas.setTurninArt, "OVERLAY"), x, y, markerSize)
        placedMarkers[#placedMarkers + 1] = x
        placedMarkers[#placedMarkers + 1] = y
        hits[#hits + 1] = { x = x, y = y, questID = p.questID }
      end
    end
  end
end

local function drawGuide(north, west, instanceMap, cos, sin, scale, halfW, halfH, square, delta)
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
  local edge = square and math.min(halfW / math.max(math.abs(x), 1e-6), halfH / math.max(math.abs(y), 1e-6))
    * length or halfW
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

-- The cursor is on the minimap itself, not just inside its rectangle: a frame over it (BubbleMap's
-- bar, an addon's minimap button) is what the mouse is on then, and the areas under it flashed their
-- tooltips through it (seen in review). The view frame counts as the map too (BubbleMap's, SetView:
-- it takes the mouse wheel for its zoom, so it's the mouse focus over its map), and so does the game
-- world, under the cursor where nothing takes the mouse.
local function onMinimap()
  if not layer:IsMouseOver() then
    return false
  end
  local foci = GetMouseFoci()
  local focus = foci and foci[1]
  -- WorldFrame: the engine makes it (no XML), so lint has no declaration for it.
  return focus == Minimap or (focus ~= nil and focus == MinimapAreas.view)
    or focus == rawget(_G, "WorldFrame")
end

local hoverElapsed = 0
local function updateHover(delta)
  hoverElapsed = hoverElapsed + delta
  if hoverElapsed < HOVER_SECONDS then
    return
  end
  hoverElapsed = 0
  -- A quest giver under the cursor first (its icon sits on top), else the quest areas.
  local found, offers
  if onMinimap() and (#MinimapAreas.hits > 0 or #MinimapAreas.giverHits > 0) then
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

---For /bq turnin: one quest's minimap "?", every input and decision of drawAreas, as of now.
---@param quest table
---@return string[]
function MinimapAreas:DiagnoseTurnin(quest)
  local lines = {}
  local function add(text, ...)
    lines[#lines + 1] = text:format(...)
  end
  local questID = quest.questID
  add("Quest %d %s, ready=%s, on a card=%s", questID, tostring(quest.title), tostring(quest.isComplete),
    tostring(ns.Stack.visible[questID] ~= nil))
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  if not north or not layer then
    add("No player position or no layer.")
    return lines
  end
  local radius, rawRadius = viewRadius(), C_Minimap.GetViewRadius()
  local half = minimapHalf()
  local scale = half / (radius * self.zoom)
  add("View: radius %s (game reports %s), zoom %s, gameHidden=%s -> gameDraws=%s", tostring(radius),
    tostring(rawRadius), tostring(self.zoom), tostring(self.gameHidden), tostring(gameDraws()))
  add("Minimap half %.1f px (layer units), %.3f px/yd, game circle %.1f px = %.1f yd", half, scale,
    half * GAME_MARKER_SHARE, half * GAME_MARKER_SHARE / scale)
  add("Layer %.0f x %.0f, parent %s, view %s", layer:GetWidth(), layer:GetHeight(),
    tostring(layer:GetParent() and layer:GetParent():GetName()), tostring(self.view and self.view:GetName()))
  local facing = rotation()
  local cos, sin = math.cos(facing), math.sin(facing)
  local marks = ns.MapAreas.GameMarksTurnIn(questID)
  local marker = ns.Navigation:MarkerPoint(questID)
  if marker then
    local mx, my = project(marker.x - north, marker.y - west, cos, sin, scale)
    add("Game marker: marks=%s, %.1f yd away (map %s, player map %s), %.1f px from centre, inGameView=%s",
      tostring(marks), math.sqrt((marker.x - north) ^ 2 + (marker.y - west) ^ 2), tostring(marker.map),
      tostring(instanceMap), math.sqrt(mx * mx + my * my), tostring(inGameView(mx, my)))
  else
    add("Game marker: marks=%s, no marker point", tostring(marks))
  end
  add("Skip ours (gameDraws and gameShowsTurnIn): %s",
    tostring(gameDraws() and gameShowsTurnIn(questID, north, west, instanceMap, cos, sin, scale)))
  local count = 0
  for _, p in ipairs(self.points) do
    if p.questID == questID and not p.objective then
      count = count + 1
      local x, y = project(p.x - north, p.y - west, cos, sin, scale)
      add("Our spot %d: %.1f yd (map %s), at %.0f, %.0f px, markerNear=%s", count,
        math.sqrt((p.x - north) ^ 2 + (p.y - west) ^ 2), tostring(p.map), x, y, tostring(markerNear(x, y)))
    end
  end
  if count == 0 then
    add("No turn-in spots of ours for this quest (not ready, no card, or areas off).")
  end
  add("Turn-in markers drawn last frame: %d", self.markersDrawn or 0)
  add("Layer strata %s level %d; view %s %d; Minimap %s %d, shown=%s", layer:GetFrameStrata(),
    layer:GetFrameLevel(), self.view and self.view:GetFrameStrata() or "-",
    self.view and self.view:GetFrameLevel() or 0, Minimap:GetFrameStrata(), Minimap:GetFrameLevel(),
    tostring(Minimap:IsShown()))
  return lines
end

-- Above Blizzard's minimap as well as the view (review, /bq turnin: a "?" was drawn, but under
-- Blizzard's minimap, shown again in BubbleMap's gather mode, as the layer sat just above the view).
-- Rechecked every frame: Edit Mode and BubbleMap's modes can change either level.
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
  FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function raiseLayer()
  local parent = layer:GetParent()
  local strata = parent:GetFrameStrata()
  if (STRATA_RANK[Minimap:GetFrameStrata()] or 0) > (STRATA_RANK[strata] or 0) then
    strata = Minimap:GetFrameStrata()
  end
  local level = math.max(parent:GetFrameLevel(), Minimap:GetFrameLevel()) + 2
  if layer:GetFrameStrata() ~= strata then
    layer:SetFrameStrata(strata)
  end
  if layer:GetFrameLevel() ~= level then
    layer:SetFrameLevel(level)
  end
end

local function update(_, delta)
  local map = settings()
  local showAreas, showGuide = map and map.minimapAreas, map and map.guide
  local showGivers = ns.MapAvailable:Enabled()
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  raiseLayer()
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
    -- Pixels per yard (layer units): Blizzard's minimap shows GetViewRadius yards from its centre to
    -- its edge, times BubbleMap's zoom. The layer may be BubbleMap's child and bigger (SetView).
    local scale = minimapHalf() / (viewRadius() * MinimapAreas.zoom)
    local halfW, halfH = layer:GetWidth() / 2, layer:GetHeight() / 2
    local facing = rotation()
    local cos, sin = math.cos(facing), math.sin(facing)
    if showAreas then
      drawAreas(north, west, instanceMap, cos, sin, scale, halfW, halfH, square)
    end
    if showGivers then
      ns.MapAvailable:Entries()
      if giversBuiltFor ~= ns.MapAvailable.builtFor then
        rebuildGivers()
      end
      drawGivers(north, west, instanceMap, cos, sin, scale, halfW, halfH, square)
    end
    if showGuide then
      drawGuide(north, west, instanceMap, cos, sin, scale, halfW, halfH, square, delta)
    end
  end
  MinimapAreas.dotsDrawn = used.dots  -- for /bq minimap (hideUnused resets the count)
  MinimapAreas.markersDrawn = used.markers  -- for /bq turnin
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
  layer:EnableMouse(false)
  -- Blizzard's minimap faded out (alpha) mustn't take our areas with it.
  layer:SetIgnoreParentAlpha(true)
  mask = layer:CreateMaskTexture()
  mask:SetAllPoints(layer)
  -- Every frame while the map shows: it moves (and may turn) every frame.
  layer:SetScript("OnUpdate", update)
  tooltip = CreateFrame("GameTooltip", "BubbleQuestMinimapTooltip", UIParent, "GameTooltipTemplate")
  layer:SetScript("OnHide", function() tooltip:Hide() end)
  MinimapAreas:SetView(MinimapAreas.view)
end

ns.Events:On("PLAYER_LOGIN", create)

---The view reaches `factor` times further than Blizzard's minimap shows (BubbleMap's own zoom,
---Blizzard's minimap faded out); 1 is Blizzard's own view.
---@param factor number
---@param gameHidden boolean? Blizzard's minimap is hidden (default: factor ~= 1, as it can't draw at
---another scale)
function MinimapAreas:SetZoom(factor, gameHidden)
  self.zoom = factor
  if gameHidden == nil then
    gameHidden = factor ~= 1
  end
  self.gameHidden = gameHidden
end

---Draw over `frame` instead of the minimap alone (nil: back to the minimap). BubbleMap's map frame:
---centred on the minimap, wider or taller, filled with terrain at the minimap's scale.
---@param frame Frame?
function MinimapAreas:SetView(frame)
  self.view = frame
  if layer then
    -- The view's child, not the minimap's: BubbleMap's own map hides Blizzard's minimap outright
    -- (at alpha 0 the game's blips still drew), which would hide a child of it. Above the view's own
    -- textures (its terrain), as above the minimap's.
    local parent = frame or Minimap
    layer:SetParent(parent)
    layer:ClearAllPoints()
    layer:SetAllPoints(parent)
    raiseLayer()
  end
end

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
