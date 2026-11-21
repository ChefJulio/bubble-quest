local ADDON_NAME, ns = ...

-- Quest areas on the minimap (review): the world map's circles (UI/MapAreas.lua) around you, same
-- colours, same turn-in "?", quest givers' "!", clipped to the minimap's shape by a mask so they fade
-- off at its edge rather than pop. Hover them for the world map's tooltip. Plus the guide: a line of
-- dots drifting from you toward one quest's nearest objective you aren't already at (its turn-in when
-- ready). The drawing is a quest view (UI/QuestView.lua, shared with BubbleMap's map window); this file
-- is what's particular to the minimap:
--   - centred on the player, turned with a rotating minimap, at the minimap's scale: C_Minimap's view
--     radius (yards from the centre to the edge, as Blizzard's HybridMinimap uses), times BubbleMap's
--     zoom (SetZoom);
--   - BubbleMap can point it at its whole map frame (BubbleQuestAPI.SetMinimapView): wider or taller
--     than Blizzard's square, filled with terrain at the minimap's scale;
--   - the game draws its own "?" and "!" on the minimap, so ours stand aside where it does;
--   - town services (UI/MapServices.lua) only with Blizzard's minimap hidden (its tracking draws them);
--   - icons sized as the game's blips are.
-- UnitPosition is nil in instances, which hides everything there.

local MinimapAreas = {
  zoom = 1,           -- how many times further than Blizzard's minimap the view reaches (SetZoom); any
                      -- value in BubbleMap's own map
  gameHidden = false, -- BubbleMap has Blizzard's minimap hidden (its own map): the game draws no markers
}
ns.MinimapAreas = MinimapAreas

local view  -- the quest view, created at login

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

-- Scale -------------------------------------------------------------------------------------------

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

-- Half of Blizzard's minimap, in the view's units: the view may live on BubbleMap's frame (SetView),
-- whose scale needn't be the minimap's (Edit Mode scales the minimap).
local function minimapHalf()
  return Minimap:GetWidth() / 2 * Minimap:GetEffectiveScale() / view.layer:GetEffectiveScale()
end

-- Pixels a yard: the minimap shows GetViewRadius yards from its centre to its edge, times BubbleMap's zoom.
local function pixelsPerYard()
  return minimapHalf() / (viewRadius() * MinimapAreas.zoom)
end

-- Our icons' size factor, as the game's blips get it (review: "exactly the same size as Blizzard's";
-- matched in two side-by-sides: its "!" and "?" are both ~16 px tall on screen, ours at 25 units came
-- out ~28 px, so QuestView's 14): the minimap's scale (Edit Mode's minimap Size; the view may live on
-- BubbleMap's frame, at another scale) times Edit Mode's minimap "Icon Scale" (Minimap:SetIconScale,
-- from the minimap system's setting: EditModeSystemTemplates.lua:1811-1813; the minimap has no
-- getter), times our own setting (map.iconSize).
local function iconScale()
  local scale = Minimap:GetEffectiveScale() / view.layer:GetEffectiveScale() * ns.MapAreas.iconScale()
  local cluster = rawget(_G, "MinimapCluster")
  -- IconScale (3) is in Forever's API docs (EditModeManagerConstantsDocumentation.lua:583), not in the
  -- annotations lint uses.
  local setting = Enum.EditModeMinimapSetting and rawget(Enum.EditModeMinimapSetting, "IconScale")
  if cluster and setting and type(cluster.GetSettingValue) == "function" then
    local ok, percent = pcall(cluster.GetSettingValue, cluster, setting)
    if ok and type(percent) == "number" and percent > 0 then  -- 0: Edit Mode not initialised yet
      scale = scale * percent / 100
    end
  end
  return scale
end

-- The game's own markers --------------------------------------------------------------------------

-- Where the game draws its own minimap markers (the "?" of many ready quests, quest givers' "!"):
-- within a circle around the centre, even when the minimap is masked square (review, two BubbleMap zoom
-- levels: a "?" in the square's corner went missing, as the game no longer drew it and a square test
-- still skipped ours). Not the whole view circle: the game's own turn-in "?" vanished at 186.5 yd with
-- a 233.3 yd view radius and at 159.5 yd with 200 yd (measured in game, two zoom levels): 0.799 and
-- 0.7975 of the radius. Ours goes between the two (review: the full radius left a ring where neither
-- showed; 0.78 doubled one at 183 yd, 0.795 still overlapped about a yard). Quest givers' "!" assumed
-- the same until measured. Ours stands aside only there: drawn in the corners and in BubbleMap's
-- padding, and everywhere while BubbleMap draws its own map with Blizzard's minimap hidden.
local GAME_MARKER_SHARE = 0.798

-- Whether the game draws its quest markers on the minimap at all: not while BubbleMap draws its own map
-- with Blizzard's minimap hidden (SetZoom's gameHidden). There's no switch for them otherwise: with the
-- QuestPOIs tracking filter off, the game still drew its "?" and "!" (seen in game), so that filter
-- isn't read.
local function gameDraws()
  return not MinimapAreas.gameHidden
end

-- An area circle's radius: the setting (map.size), halved indoors (review, a cave: the minimap zooms in
-- a long way indoors and mobs stand close, so outdoor-sized circles merged into one blob).
local INDOOR_SHARE = 0.5
local function circleYards()
  return ns.MapAreas.blobYards() * (IsIndoors() and INDOOR_SHARE or 1)
end

-- For the view: how far from the centre the game draws (pixels; nil: nowhere), and whether it hides
-- low-level quest givers (its "Low-level quests" tracking off: ours show for those).
local function gameMarkers()
  if not gameDraws() then
    return nil, nil
  end
  return minimapHalf() * GAME_MARKER_SHARE, C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.TrivialQuests)
end

-- Layering ----------------------------------------------------------------------------------------

-- Above Blizzard's minimap as well as the view (review, /bq turnin: a "?" was drawn, but under
-- Blizzard's minimap, shown again in BubbleMap's gather mode, as the layer sat just above the view).
-- Rechecked every frame: Edit Mode and BubbleMap's modes can change either level.
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
  FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function raiseLayer()
  local layer = view.layer
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

-- The view ----------------------------------------------------------------------------------------

local function update()
  raiseLayer()
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  -- BubbleMap's own map can be dragged away from the player (SetCentre): the view centres there; the
  -- player stays the player (the guide's start, "here"). An error in its function falls back to the
  -- player rather than stopping the minimap.
  local centre = MinimapAreas.centre
  if centre and north then
    local ok, n, w = pcall(centre)
    if ok and type(n) == "number" and type(w) == "number" then
      north, west = n, w
    end
  end
  view:Draw(north, west, instanceMap, pixelsPerYard(), rotation())
end

local function create()
  if view then
    return
  end
  view = ns.QuestView.New(Minimap, {
    mask = function() return isSquare() and "square" or "round" end,
    round = function() return not isSquare() end,
    iconScale = iconScale,
    gameMarkers = gameMarkers,
    -- Town services only while Blizzard's minimap is hidden: showing, its own tracking draws them.
    services = function() return MinimapAreas.gameHidden end,
    guide = true,
    areasSetting = "minimapAreas",
    circleYards = circleYards,
    guideSetting = "guide",
    -- The minimap itself, or BubbleMap's map frame (it takes the mouse wheel for its zoom, so it's the
    -- mouse focus over its map).
    focus = function(focus) return focus == Minimap or focus == MinimapAreas.view end,
    tooltipName = "BubbleQuestMinimapTooltip",
  })
  -- Every frame while the map shows: it moves (and may turn) every frame.
  view.layer:SetScript("OnUpdate", update)
  MinimapAreas:SetView(MinimapAreas.view)
end

ns.Events:On("PLAYER_LOGIN", create)

---A click on the minimap view (BubbleQuestAPI.MinimapClick: BubbleMap's frames take the mouse first):
---see QuestView's View:Click. True when it took the click.
---@param button string
---@return boolean
function MinimapAreas:Click(button)
  return view ~= nil and view:Click(button)
end

-- Blizzard's own minimap (no BubbleMap view): its clicks, after Blizzard's handler (a post-hook: the
-- ping still happens, nothing replaced). Only a click, not the end of a drag (minimap addons drag it):
-- the cursor must be where it was pressed.
local pressedAt
ns.Events:On("PLAYER_LOGIN", function()
  Minimap:HookScript("OnMouseDown", function()
    pressedAt = { GetCursorPosition() }
  end)
  Minimap:HookScript("OnMouseUp", function(_, button)
    local x, y = GetCursorPosition()
    local still = pressedAt and math.abs(x - pressedAt[1]) < 4 and math.abs(y - pressedAt[2]) < 4
    pressedAt = nil
    if still and not MinimapAreas.view then
      MinimapAreas:Click(button)
    end
  end)
end)

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
  self:applyView(frame)
end

---Where the view centres: fn() -> north, west (world yards on the player's instance map), or nil for
---the player; nil fn: always the player.
---@param fn function?
function MinimapAreas:SetCentre(fn)
  self.centre = fn
end

function MinimapAreas:applyView(frame)
  self.view = frame
  if view then
    -- The frame's child, not the minimap's: BubbleMap's own map hides Blizzard's minimap outright
    -- (at alpha 0 the game's blips still drew), which would hide a child of it. Above the frame's own
    -- textures (its terrain), as above the minimap's.
    view:SetParent(frame or Minimap)
    -- On Blizzard's minimap the marks ignore its alpha (BubbleMap fades it out: QuestView.New); on
    -- BubbleMap's frame they follow it, so its minimap opacity setting fades them too (review). Ctrl's
    -- see-through is the layer's own alpha, on top of either.
    view.layer:SetIgnoreParentAlpha(frame == nil)
    raiseLayer()
  end
end

-- Diagnostics -------------------------------------------------------------------------------------

---For /bq turnin: one quest's minimap "?", every input and decision of the view, as of now.
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
  if not north or not view then
    add("No player position or no view.")
    return lines
  end
  local layer = view.layer
  local radius, rawRadius = viewRadius(), C_Minimap.GetViewRadius()
  local half = minimapHalf()
  local scale = pixelsPerYard()
  add("View: radius %s (game reports %s), zoom %s, gameHidden=%s -> gameDraws=%s", tostring(radius),
    tostring(rawRadius), tostring(self.zoom), tostring(self.gameHidden), tostring(gameDraws()))
  add("Minimap half %.1f px (layer units), %.3f px/yd, game circle %.1f px = %.1f yd", half, scale,
    half * GAME_MARKER_SHARE, half * GAME_MARKER_SHARE / scale)
  add("Layer %.0f x %.0f, parent %s, view %s", layer:GetWidth(), layer:GetHeight(),
    tostring(layer:GetParent() and layer:GetParent():GetName()), tostring(self.view and self.view:GetName()))
  local facing = rotation()
  local cos, sin = math.cos(facing), math.sin(facing)
  local project = ns.QuestView.project
  local marks = ns.MapAreas.GameMarksTurnIn(questID)
  local marker = ns.Navigation:MarkerPoint(questID)
  if marker then
    local mx, my = project(marker.x - north, marker.y - west, cos, sin, scale)
    local reach = half * GAME_MARKER_SHARE
    add("Game marker: marks=%s, %.1f yd away (map %s, player map %s), %.1f px from centre, within reach=%s",
      tostring(marks), math.sqrt((marker.x - north) ^ 2 + (marker.y - west) ^ 2), tostring(marker.map),
      tostring(instanceMap), math.sqrt(mx * mx + my * my), tostring(mx * mx + my * my <= reach * reach))
  else
    add("Game marker: marks=%s, no marker point", tostring(marks))
  end
  add("Skip ours (as of the last frame): %s", tostring(view.north ~= nil and view:GameShowsTurnIn(questID)))
  local count = 0
  for _, p in ipairs(ns.QuestView.points) do
    if p.questID == questID and not p.objective then
      count = count + 1
      local x, y = project(p.x - north, p.y - west, cos, sin, scale)
      add("Our spot %d: %.1f yd (map %s), at %.0f, %.0f px, markerNear=%s", count,
        math.sqrt((p.x - north) ^ 2 + (p.y - west) ^ 2), tostring(p.map), x, y, tostring(view:MarkerNear(x, y)))
    end
  end
  if count == 0 then
    add("No turn-in spots of ours for this quest (not ready, no card, or areas off).")
  end
  add("Turn-in markers drawn last frame: %d", view.markersDrawn or 0)
  add("Layer strata %s level %d; view %s %d; Minimap %s %d, shown=%s", layer:GetFrameStrata(),
    layer:GetFrameLevel(), self.view and self.view:GetFrameStrata() or "-",
    self.view and self.view:GetFrameLevel() or 0, Minimap:GetFrameStrata(), Minimap:GetFrameLevel(),
    tostring(Minimap:IsShown()))
  return lines
end

---For /bq minimap: what the minimap's view sees right now, one frame run under pcall so an error shows.
---@return string[]
function MinimapAreas:Diagnose()
  local lines = {}
  local function add(text, ...)
    lines[#lines + 1] = text:format(...)
  end
  local map = ns.DB.profile and ns.DB.profile.map
  add("Settings: areas=%s guide=%s", tostring(map and map.minimapAreas), tostring(map and map.guide))
  local layer = view and view.layer
  add("Layer: %s, shown=%s visible=%s", layer and "created" or "MISSING", tostring(layer and layer:IsShown()),
    tostring(layer and layer:IsVisible()))
  if not layer then
    return lines
  end
  -- The frames' own draws, before ours below (review: blank in a cave while this frame drew 50).
  local last = view.lastDraw
  add("Frame draws so far %d; last: north %s west %s map %s ppy %s turn %s", view.drawCount or 0,
    tostring(last and last.north), tostring(last and last.west), tostring(last and last.map),
    tostring(last and last.ppy), tostring(last and last.turn))
  local ok, err = pcall(update)
  add("One frame: %s", ok and "ok" or ("ERROR " .. tostring(err)))
  -- What the textures actually are after it: shown, visible, where, how big, how opaque, masked.
  add("Layer alpha %.2f (effective %.2f), scale %.2f, mask %s (shape %s, shown %s), regions %d",
    layer:GetAlpha(), layer:GetEffectiveAlpha(), layer:GetEffectiveScale(), tostring(view.mask ~= nil),
    tostring(view.maskShape), tostring(view.mask and view.mask:IsShown()), layer:GetNumRegions())
  local layerX, layerY = layer:GetCenter()
  local mask = view.mask
  local maskX, maskY
  if mask then
    maskX, maskY = mask:GetCenter()
  end
  add("Layer %.0fx%.0f at %s; view half %s x %s; mask %s at %s", layer:GetWidth(), layer:GetHeight(),
    layerX and ("%.0f, %.0f"):format(layerX, layerY) or "nil", tostring(view.halfW), tostring(view.halfH),
    mask and ("%.0fx%.0f"):format(mask:GetWidth(), mask:GetHeight()) or "-",
    maskX and ("%.0f, %.0f"):format(maskX, maskY) or "nil")
  for kind, pool in pairs(view.pools) do
    local shown, visible = 0, 0
    for _, t in ipairs(pool) do
      shown = shown + (t:IsShown() and 1 or 0)
      visible = visible + (t:IsVisible() and 1 or 0)
    end
    add("  %s: pool %d, shown %d, visible %d", kind, #pool, shown, visible)
    local t = pool[1]
    if t and t:IsShown() then
      local tx, ty = t:GetCenter()
      local lx, ly = layer:GetCenter()
      local r, g, b, a = t:GetVertexColor()
      add("    first: %.0fx%.0f at %s, %s from centre; alpha %.2f, colour %.2f %.2f %.2f %.2f; layer %s; masks %d",
        t:GetWidth(), t:GetHeight(), tx and ("%.0f, %.0f"):format(tx, ty) or "nil",
        tx and lx and ("%.0f, %.0f"):format(tx - lx, ty - ly) or "-", t:GetAlpha(), r or 0, g or 0, b or 0,
        a or 0, tostring(t:GetDrawLayer()), t:GetNumMaskTextures())
    end
  end
  local north, west, instanceMap = ns.Navigation:PlayerPosition()
  add("Player: %s, %s on map %s", tostring(north), tostring(west), tostring(instanceMap))
  add("Minimap: width %.1f, view radius %s yd, square=%s, rotation %.2f", Minimap:GetWidth(),
    tostring(C_Minimap.GetViewRadius()), tostring(isSquare()), rotation())
  add("Points %d (version %s of %s), circles drawn %d, hover radius %.1f px", #ns.QuestView.points,
    tostring(ns.QuestView.version), tostring(ns.MapAreas.version), #view.hits, view.radius or 0)
  local guide = ns.QuestView.guide
  add("Guide: quest %s, point %s, dots drawn %d", tostring(guide.questID),
    guide.point and ("%.1f, %.1f map %s"):format(guide.point.x, guide.point.y, tostring(guide.point.map)) or "none",
    view.dotsDrawn or 0)
  for _, questID in ipairs(ns.QuestView.Candidates()) do
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
  for _, hit in ipairs(view.hits) do
    local d = math.sqrt((hit.x - px) ^ 2 + (hit.y - py) ^ 2)
    nearest = nearest and math.min(nearest, d) or d
  end
  add("Mouse over minimap: %s; cursor from centre %.1f, %.1f px; nearest circle %s px away",
    tostring(Minimap:IsMouseOver()), px, py, nearest and ("%.1f"):format(nearest) or "-")
  add("Our tooltip: shown=%s; GameTooltip (blips): shown=%s", tostring(view.tooltip:IsShown()),
    tostring(GameTooltip:IsShown()))
  return lines
end
