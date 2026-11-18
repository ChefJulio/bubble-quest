local ADDON_NAME, ns = ...

-- A quest view: BubbleQuest's quest areas, turn-in "?", quest givers' "!" and the guide line drawn
-- into a frame around any world point, at any scale and turn. One renderer for every map-like frame
-- (review: BubbleMap's map window wanted the minimap's markers too): the minimap (UI/MinimapAreas.lua)
-- is one view, BubbleMap's window another (BubbleQuestAPI.CreateQuestView). Colours, areas and givers
-- come from the world map's code (UI/MapAreas.lua, UI/MapAvailable.lua), so every view matches it.
--
-- How: textures on the view's own mouse-disabled frame, placed by hand on every Draw (the owner calls it
-- whenever what it shows changes; the minimap does every frame, as it moves and may turn). Hover is
-- worked out from the cursor, into the view's own tooltip (on the minimap Blizzard's Minimap_OnUpdate
-- takes GameTooltip every frame for its blips: SetMinimapMouseover, Blizzard_Minimap/Mainline/
-- Minimap.lua:279, so ours never lasted a frame there).
--
-- Options (QuestView.New):
--   mask          a mask texture's shape for the layer: function() -> "round" | "square" | nil (no mask:
--                 the owner's frame clips)
--   round         function() -> true when the visible area is a circle (the minimap), for what's "inside"
--   iconScale     function(view) -> the icons' size factor (default: the map.iconSize setting)
--   gameMarkers   function(view) -> reach (pixels from the centre where the game draws its own "?" and
--                 "!"; nil: it draws none), trivialHidden (the game hides low-level givers' "!")
--   guide         draw the guide line (from the player's position, wherever it is in the view)
--   areasSetting  the Map setting that turns the areas on (default "areas", the world map's; the
--                 minimap: "minimapAreas")
--   guideSetting  the Map setting the guide line also needs (the minimap: "guide"; default none)
--   services      function(view) -> true to draw the town services switched on (UI/MapServices.lua):
--                 where the game's own tracking doesn't draw them (BubbleMap's window, its own minimap)
--   servicesExclude   { [MapServices key] = true }: services left out (the owner draws its own)
--   focus         function(focus) -> true when the mouse focus counts as being on the view
--   minCircle, minIcon   smallest on-screen sizes, pixels (a far-out window keeps its marks visible)
--   tooltipName   a global name for the view's tooltip (default "BubbleQuestViewTooltip<n>")

local DOT_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Map\\dot"  -- tools/make_blob.py
-- Pixels, not yards: a minimap is small (140 px across for 233 yd each way in review, 0.3 px a yard),
-- so "too close for a line" is the arrows' "here" (yards, Navigation), never a pixel threshold.
local DOT_SIZE = 5           -- guide dots
local DOT_SPACING = 8        -- between guide dots
local DOT_SPEED = 10         -- a second, the dots' drift toward the target
local DOT_ALPHA = 0.9
local PLAYER_GAP = 7         -- no dots this close to the player (their arrow)
local HOVER_MIN = 6          -- a circle's hover radius at least this, however far out the view
local TARGET_SECONDS = 0.1   -- how often the guide's target is worked out again (the arrows' rate)
local HOVER_SECONDS = 0.05   -- how often the hover is checked while the cursor is on the view
local BLIP_OFFSET = 24       -- pixels right of the cursor for ours while GameTooltip is up (updateHover)
local ROUND_MASK = "Interface/CharacterFrame/TempPortraitAlphaMask"
local SQUARE_MASK = "Interface/BUTTONS/WHITE8X8"
local MERGE_SHARE = 0.8      -- icons closer than this share of their size merge into one (givers' "!")
-- Below this scale a view shows a continent's worth: quest givers' "!" only with the setting for
-- continent maps (map.continentIcons), as on the world map (UI/MapAreas.lua ShowsIcons), where
-- thousands of them were clutter; and slow to merge every frame. Zone maps and the minimap are well
-- above it (a zone ~0.3-1 px a yard, the minimap ~0.3+).
local GIVER_MIN_PPY = 0.08

-- Quest givers' "!": pixels at 100% (setting map.iconSize), times the view's iconScale. Matched on the
-- minimap to the game's own blips in two side-by-sides (UI/MinimapAreas.lua says how); the "?" box is
-- the same (TURNIN_SHARE).
local GIVER_SIZE, DROP_ICON_SIZE = 14, 11
local TURNIN_SHARE = 1

local QuestView = {
  points = {},       -- { x, y (world yards), map, color, questID, objective (nil: turn-in) }, shared
  version = -1,      -- MapAreas.version the points were built for
  giverPoints = {},  -- { x, y, map, entry, drop }, shared
  giversBuiltFor = nil,
  guide = { at = 0 },  -- questID, point: the guide's target, worked out at most every TARGET_SECONDS
}
ns.QuestView = QuestView
QuestView.GIVER_SIZE = GIVER_SIZE

local function settings()
  return ns.DB.profile and ns.DB.profile.map
end

-- World offset (yards north, yards west of the centre) to pixels from the view's centre.
local function project(north, west, cos, sin, scale)
  local x, y = -west * scale, north * scale  -- north up, east right
  return x * cos + y * sin, -x * sin + y * cos
end
QuestView.project = project

-- Shared data ---------------------------------------------------------------------------------------

-- The cards' quests' area points, rebuilt when the world map's would be (MapAreas.version).
local function rebuildPoints()
  local points = QuestView.points
  wipe(points)
  QuestView.version = ns.MapAreas.version
  for questID in pairs(ns.Stack.visible) do
    local quest = ns.QuestLog:Get(questID)
    if quest then
      for _, entry in ipairs(ns.MapAreas:QuestPoints(quest)) do
        local p = entry.point
        points[#points + 1] = {
          x = p.x, y = p.y, map = p.map, questID = questID, objective = entry.objective,
          color = ns.MapAreas:ShadeFor(questID, entry.objective),  -- each objective its shade
        }
      end
    end
  end
end

-- Quest givers' "!" at their spawns; quests from drops as the uniform bronze "!" at each droppers'
-- cluster centre (no areas here: views are small). Rebuilt when the entries are.
local function rebuildGivers()
  local giverPoints = QuestView.giverPoints
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
  QuestView.giversBuiltFor = ns.MapAvailable.builtFor
end

-- The guide's quest: the hovered card (that one only: it's what you're asking about), else the pinned
-- quests in pin order, then the cards top to bottom: the first with somewhere to go on this continent
-- (a pinned "raise your skill" quest has nowhere, and shouldn't hide the line). Its target:
-- Navigation:GuidePoint, shared with the world map's line (UI/MapAreas.lua).
local function guideTarget(questID)
  local quest = ns.QuestLog:Get(questID)
  return quest and ns.Navigation:GuidePoint(quest) or nil
end

function QuestView.Candidates()
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
  for _, questID in ipairs(QuestView.Candidates()) do
    local point = guideTarget(questID)
    if point then
      return questID, point
    end
  end
  return nil, nil
end

local function currentGuide()
  local guide = QuestView.guide
  local now = GetTime()
  if now - guide.at >= TARGET_SECONDS then
    guide.at = now
    guide.questID, guide.point = pickGuide()
  end
  return guide.questID, guide.point
end

-- A view ----------------------------------------------------------------------------------------------

local View = {}
View.__index = View
local viewCount = 0  -- for the views' tooltip names

---A view drawing into `parent` (its layer fills it).
---@param parent Frame
---@param options table? see the top of this file
---@return table
function QuestView.New(parent, options)
  local view = setmetatable({ options = options or {}, hits = {}, giverHits = {}, serviceHits = {},
    radius = 0, placed = {}, markerSize = 0,
    used = { blobs = 0, markers = 0, dots = 0, givers = 0, services = 0 },
    pools = { blobs = {}, markers = {}, dots = {}, givers = {}, services = {} }, hoverAt = 0 }, View)
  local layer = CreateFrame("Frame", nil, parent)
  layer:SetAllPoints(parent)
  layer:EnableMouse(false)
  -- A parent faded out (alpha; BubbleMap fades Blizzard's minimap) mustn't take the marks with it.
  layer:SetIgnoreParentAlpha(true)
  view.layer = layer
  if view.options.mask then
    view.mask = layer:CreateMaskTexture()
    view.mask:SetAllPoints(layer)
  end
  -- Always named: GameTooltipTemplate names its lines "$parentTextLeft1"..., so an unnamed one made
  -- globals off UIParent's name, shared by every unnamed view (review, BugSack: "UIParentTextLeft1").
  viewCount = viewCount + 1
  local name = view.options.tooltipName or ("BubbleQuestViewTooltip" .. viewCount)
  local tooltip = CreateFrame("GameTooltip", name, UIParent, "GameTooltipTemplate")
  ---@cast tooltip GameTooltip
  view.tooltip = tooltip
  -- Hidden, it keeps no anchors: nothing of ours stays tied to another frame (see updateHover).
  tooltip:HookScript("OnHide", function() tooltip:ClearAllPoints() end)
  layer:SetScript("OnHide", function() view.tooltip:Hide() end)
  return view
end

---Move the view into another frame (it fills that one instead).
---@param parent Frame
function View:SetParent(parent)
  self.layer:SetParent(parent)
  self.layer:ClearAllPoints()
  self.layer:SetAllPoints(parent)
end

function View:Hide()
  self.layer:Hide()
end

---The view's tooltip is up (the cursor is on one of its marks).
---@return boolean
function View:IsHovering()
  return self.tooltip:IsShown() and self.tooltip:GetOwner() == self.layer
end

function View:Show()
  self.layer:Show()
end

function View:acquire(kind, art, drawLayer, subLevel)
  local used, pool = self.used, self.pools[kind]
  used[kind] = used[kind] + 1
  local t = pool[used[kind]]
  if not t then
    t = self.layer:CreateTexture(nil, drawLayer, nil, subLevel)
    if type(art) == "function" then
      art(t)  -- sets its own art (the turn-in "?": an atlas)
    elseif art then
      t:SetTexture(art)
    end
    if self.mask then
      t:AddMaskTexture(self.mask)
    end
    pool[used[kind]] = t
  end
  t:Show()
  return t
end

function View:place(t, x, y, size)
  t:SetSize(size, size)
  t:ClearAllPoints()
  t:SetPoint("CENTER", self.layer, "CENTER", x, y)
end

function View:hideUnused()
  self.markersDrawn, self.dotsDrawn = self.used.markers, self.used.dots  -- for the diagnostics
  for kind, pool in pairs(self.pools) do
    for i = self.used[kind] + 1, #pool do
      pool[i]:Hide()
    end
    self.used[kind] = 0
  end
end

-- Inside the view's visible area (a circle on a round minimap, else its rectangle), with a margin.
function View:inside(x, y, pad)
  if self.round then
    local reach = self.halfW + pad
    return x * x + y * y <= reach * reach
  end
  return math.abs(x) <= self.halfW + pad and math.abs(y) <= self.halfH + pad
end

function View:iconScale()
  return self.options.iconScale and self.options.iconScale(self) or ns.MapAreas.iconScale()
end

-- One "?" per spot (review: two showed, a little apart): the same turn-in from two sources a few yards
-- apart, or two quests handed in to one NPC.
function View:MarkerNear(x, y)
  local limit = self.markerSize * 0.75
  local placed = self.placed
  for i = 1, #placed, 2 do
    if math.abs(placed[i] - x) < limit and math.abs(placed[i + 1] - y) < limit then
      return true
    end
  end
  return false
end

-- The game shows its own "?" for this quest in the view right now: it marks the quest, and its marker
-- (where the game itself places it, Navigation:MarkerPoint) is within its reach. Decided by the game's
-- position, not ours (review: walking from 182 to 190 yd, the game's "?" went and ours didn't come, as
-- our spot for the quest, a few yards nearer, was still within).
function View:GameShowsTurnIn(questID)
  local reach = self.gameReach
  if not reach or not ns.MapAreas.GameMarksTurnIn(questID) then
    return false
  end
  local marker = ns.Navigation:MarkerPoint(questID)
  if not marker or marker.map ~= self.map then
    return false
  end
  local x, y = project(marker.x - self.north, marker.y - self.west, self.cos, self.sin, self.scale)
  return x * x + y * y <= reach * reach
end

-- The game's quest-giver "!" (review: two "!" a few pixels apart) is drawn by the client for the givers
-- it has loaded, which isn't a set distance, and no addon API lists them. So within its reach the "!"
-- is left to the game entirely, as on Blizzard's own minimap (decided in review). Ours still draws there
-- for quests the game never marks: started by a drop, or low-level while it hides those.
function View:gameMarksGiver(p, x, y)
  local reach = self.gameReach
  return reach ~= nil and not p.drop and x * x + y * y <= reach * reach
    and not (p.entry.trivial and self.trivialHidden)
end

function View:drawAreas()
  local scale, north, west = self.scale, self.north, self.west
  local size = math.max(2 * ns.MapAreas.blobYards() * scale, self.options.minCircle or 0)
  local alpha = ns.MapAreas.blobAlpha()
  local hits = self.hits
  wipe(self.placed)
  self.markerSize = math.max(ns.MapAreas.turninSize(GIVER_SIZE) * TURNIN_SHARE * self:iconScale(),
    self.options.minIcon or 0)
  -- The whole circle: on small views they're small (the world map's 70% core was too fiddly in review).
  self.radius = math.max(size / 2, HOVER_MIN)
  -- One "?" per quest (review: two for one turn-in): where the sources know several spots (two
  -- databases a little apart, an NPC with more than one spawn), the one nearest the player, as the
  -- arrow and its distance take.
  local px, py = self.playerNorth or north, self.playerWest or west
  local nearestTurnin, nearestYards = {}, {}
  for _, p in ipairs(QuestView.points) do
    if p.map == self.map and not p.objective then
      local yards = (p.x - px) ^ 2 + (p.y - py) ^ 2
      if not nearestYards[p.questID] or yards < nearestYards[p.questID] then
        nearestTurnin[p.questID], nearestYards[p.questID] = p, yards
      end
    end
  end
  for _, p in ipairs(QuestView.points) do
    if p.map == self.map and (p.objective or nearestTurnin[p.questID] == p) then
      local x, y = project(p.x - north, p.y - west, self.cos, self.sin, scale)
      if p.objective then
        if self:inside(x, y, size / 2) then  -- a circle partly inside still shows its inside part
          local blob = self:acquire("blobs", ns.MapAreas.BLOB_TEXTURE, "ARTWORK")
          blob:SetVertexColor(p.color[1], p.color[2], p.color[3], alpha)
          self:place(blob, x, y, size)
          hits[#hits + 1] = { x = x, y = y, questID = p.questID, objective = p.objective }
        end
      elseif self:inside(x, y, self.markerSize / 2) and not self:GameShowsTurnIn(p.questID)
          and not self:MarkerNear(x, y) then
        -- A turn-in: just the "?" (review: the circle under it added nothing), still hoverable.
        self:place(self:acquire("markers", ns.MapAreas.setTurninArt, "OVERLAY"), x, y, self.markerSize)
        self.placed[#self.placed + 1] = x
        self.placed[#self.placed + 1] = y
        hits[#hits + 1] = { x = x, y = y, questID = p.questID }
      end
    end
  end
end

-- A giver icon, its art set only when what it shows changes (several looks share one pool).
function View:acquireGiver(entry)
  local t = self:acquire("givers", nil, "OVERLAY", 2)
  local art = entry.giver.kind == "item" and "drop"
    or ((entry.repeatable and "r" or "n") .. (entry.trivial and "t" or ""))
  if t.art ~= art then
    t.art = art
    ns.MapAvailable.SetArt(t, entry)
  end
  return t
end

function View:drawGivers()
  local hits = self.giverHits
  local sizeScale = self:iconScale()
  local minIcon = self.options.minIcon or 0
  for _, p in ipairs(QuestView.giverPoints) do
    if p.map == self.map then
      local x, y = project(p.x - self.north, p.y - self.west, self.cos, self.sin, self.scale)
      local size = math.max((p.drop and DROP_ICON_SIZE or GIVER_SIZE) * sizeScale, minIcon)
      if self:inside(x, y, size / 2) and not self:gameMarksGiver(p, x, y) then
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
          self:place(self:acquireGiver(p.entry), x, y, size)
          hits[#hits + 1] = {
            x = x, y = y, radius = math.max(size / 2, HOVER_MIN), entries = { p.entry }, drop = p.drop,
          }
        end
      end
    end
  end
end

-- Town services (UI/MapServices.lua), under the quest marks as on the world map. Spawns of one service
-- that would overlap on screen merge into the first drawn (the world map's rule), so a far-out view
-- isn't carpeted with mailboxes; different services side by side both show.
function View:drawServices()
  local points = ns.MapServices:WorldPoints()[self.map]
  if not points then
    return
  end
  local hits = self.serviceHits
  local exclude = self.options.servicesExclude
  local size = math.max(ns.MapServices.ICON_SIZE * self:iconScale(), self.options.minIcon or 0)
  local near = size * MERGE_SHARE
  local radius = math.max(size / 2, HOVER_MIN)
  for _, p in ipairs(points) do
    if not (exclude and exclude[p.key]) then
      local x, y = project(p.x - self.north, p.y - self.west, self.cos, self.sin, self.scale)
      if self:inside(x, y, size / 2) then
        local merged = false
        for _, hit in ipairs(hits) do
          if hit.key == p.key and math.abs(hit.x - x) < near and math.abs(hit.y - y) < near then
            merged = true
            break
          end
        end
        if not merged then
          local t = self:acquire("services", nil, "OVERLAY", -1)
          if t.icon ~= p.icon then
            t.icon = p.icon
            t:SetTexture(p.icon)
          end
          self:place(t, x, y, size)
          hits[#hits + 1] = { x = x, y = y, radius = radius, key = p.key, entry = p.entry }
        end
      end
    end
  end
end

-- The guide: dots drifting from the player toward one quest's target (see currentGuide), where they
-- fall inside the view (the player may be anywhere in a window, or outside it).
function View:drawGuide()
  local questID, target = currentGuide()
  if not target or target.map ~= self.map or not self.playerNorth then
    return
  end
  local cos, sin, scale = self.cos, self.sin, self.scale
  local sx, sy = project(self.playerNorth - self.north, self.playerWest - self.west, cos, sin, scale)
  local tx, ty = project(target.x - self.north, target.y - self.west, cos, sin, scale)
  local dx, dy = tx - sx, ty - sy
  local length = math.sqrt(dx * dx + dy * dy)
  if length <= PLAYER_GAP then
    return  -- under the player's arrow
  end
  dx, dy = dx / length, dy / length
  local color = ns.MapAreas:ColorFor(questID)
  local offset = (GetTime() * DOT_SPEED) % DOT_SPACING
  for d = PLAYER_GAP + offset, length, DOT_SPACING do
    local x, y = sx + dx * d, sy + dy * d
    if self:inside(x, y, -DOT_SIZE) then
      local dot = self:acquire("dots", DOT_TEXTURE, "OVERLAY")
      -- Fade in from the player, so the line starts softly.
      local fade = math.min(1, (d - PLAYER_GAP) / DOT_SPACING)
      dot:SetVertexColor(color[1], color[2], color[3], DOT_ALPHA * fade)
      self:place(dot, x, y, DOT_SIZE)
    end
  end
end

-- Hover ---------------------------------------------------------------------------------------------

-- The cursor is on the view itself, not just inside its rectangle: a frame over it (a map's bar, an
-- addon's minimap button) is what the mouse is on then, and the marks under it flashed their tooltips
-- through it (seen in review). What counts as the view is the owner's call (options.focus); the game
-- world, under the cursor where nothing takes the mouse, always does.
function View:onView()
  if not self.layer:IsMouseOver() then
    return false
  end
  local foci = GetMouseFoci()
  local focus = foci and foci[1]
  -- WorldFrame: the engine makes it (no XML), so lint has no declaration for it.
  if focus == rawget(_G, "WorldFrame") then
    return true
  end
  return focus ~= nil and self.options.focus ~= nil and self.options.focus(focus) == true
end

function View:updateHover()
  local now = GetTime()
  if now - self.hoverAt < HOVER_SECONDS then
    return
  end
  self.hoverAt = now
  local tooltip = self.tooltip
  -- A quest giver under the cursor first (its icon sits on top), then town services, else the quest
  -- areas (the world map's order).
  local found, offers, services
  if (#self.hits > 0 or #self.giverHits > 0 or #self.serviceHits > 0) and self:onView() then
    local cx, cy = GetCursorPosition()
    local scale = self.layer:GetEffectiveScale()
    local mx, my = self.layer:GetCenter()
    local x, y = cx / scale - mx, cy / scale - my
    offers = ns.MapAvailable.Under(self.giverHits, x, y)
    if not offers then
      for _, hit in ipairs(self.serviceHits) do
        if (hit.x - x) ^ 2 + (hit.y - y) ^ 2 <= hit.radius * hit.radius then
          services = services or {}
          services[#services + 1] = hit
        end
      end
    end
    found = not (offers or services) and ns.MapAreas.Under(self.hits, self.radius, x, y) or nil
  end
  if not (found or offers or services) or ns.Tooltips:Suppressed() then  -- Ctrl hides ours (UI/Tooltips.lua)
    tooltip:Hide()
    return
  end
  -- Anchored to the cursor only, never with SetPoint (review, error twice: "SetPoint would result in
  -- anchor family connection". Hung under GameTooltip by anchoring to it, then by its screen position
  -- on UIParent: both joined the family GameTooltip is in, and Blizzard re-anchoring it then failed).
  -- With a blip's tooltip (GameTooltip, at the cursor: Minimap_OnUpdate) up too, ours goes to the
  -- cursor's right, as Blizzard's flight map does (FM_ZoneSummaryDataProvider.lua:48), so both read.
  if GameTooltip:IsShown() then
    ns.Tooltips:Take(self.layer, "ANCHOR_CURSOR_RIGHT", nil, tooltip, BLIP_OFFSET, 0)
  else
    ns.Tooltips:Take(self.layer, "ANCHOR_CURSOR", nil, tooltip)
  end
  if offers then
    ns.MapAvailable.FillTooltip(tooltip, offers)
  elseif services then
    ns.MapServices.FillTooltip(tooltip, services)
  else
    ns.MapAreas.FillTooltip(tooltip, found)
  end
end

-- Drawing -------------------------------------------------------------------------------------------

---Draw around the world point (`north`, `west` yards) on instance map `map`, at `ppy` pixels a yard
---(the layer's units), turned by `turn` radians (a rotating minimap; 0: north up). What shows follows
---the Map settings: areas (options.areasSetting), the guide (options.guide and guideSetting), givers,
---town services (options.services, and which are switched on).
---@param north number
---@param west number
---@param map number
---@param ppy number
---@param turn number?
function View:Draw(north, west, map, ppy, turn)
  local opts = self.options
  local mapSettings = settings()
  local showAreas = mapSettings and mapSettings[opts.areasSetting or "areas"]
  local showGuide = opts.guide and (not opts.guideSetting or (mapSettings and mapSettings[opts.guideSetting]))
  -- A continent's worth of icons only with map.continentIcons, as the world map (ShowsIcons).
  local iconsHere = ppy ~= nil and (ppy >= GIVER_MIN_PPY or (mapSettings and mapSettings.continentIcons))
  local showGivers = iconsHere and ns.MapAvailable:Enabled()
  local showServices = iconsHere and opts.services ~= nil and opts.services(self) and ns.MapServices.lists ~= nil
  wipe(self.hits)
  wipe(self.giverHits)
  wipe(self.serviceHits)
  if north and ppy and ppy > 0 and (showAreas or showGuide or showGivers or showServices) then
    turn = turn or 0
    self.north, self.west, self.map, self.scale = north, west, map, ppy
    self.cos, self.sin = math.cos(turn), math.sin(turn)
    self.halfW, self.halfH = self.layer:GetWidth() / 2, self.layer:GetHeight() / 2
    self.round = opts.round and opts.round() or false
    local playerNorth, playerWest, playerMap = ns.Navigation:PlayerPosition()
    if playerMap == map then
      self.playerNorth, self.playerWest = playerNorth, playerWest
    else
      self.playerNorth, self.playerWest = nil, nil
    end
    if self.mask then
      local shape = opts.mask()
      if shape ~= self.maskShape then
        self.maskShape = shape
        self.mask:SetTexture(shape == "square" and SQUARE_MASK or ROUND_MASK, "CLAMPTOBLACKADDITIVE",
          "CLAMPTOBLACKADDITIVE")
      end
    end
    if opts.gameMarkers then
      self.gameReach, self.trivialHidden = opts.gameMarkers(self)
    else
      self.gameReach, self.trivialHidden = nil, nil
    end
    if showAreas then
      if QuestView.version ~= ns.MapAreas.version then
        rebuildPoints()
      end
      self:drawAreas()
    end
    if showGivers then
      ns.MapAvailable:Entries()
      if QuestView.giversBuiltFor ~= ns.MapAvailable.builtFor then
        rebuildGivers()
      end
      self:drawGivers()
    end
    if showServices then
      self:drawServices()
    end
    if showGuide then
      self:drawGuide()
    end
  end
  self:hideUnused()
  self:updateHover()
end
