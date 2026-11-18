local ADDON_NAME, ns = ...

-- BubbleMap's own map window (build step 8): the whole continent's real terrain, seamless, dragged to
-- pan across zones and wheeled to zoom far further in and out than Blizzard's world map (which can't:
-- its zoom levels come from its map art and a pan stops at the zone; changing either taints it). Design:
-- docs/design/questmarker-map.md ("The world map").
--
-- A view is a centre (world north, west on a continent) and a scale (pixels per yard); TileView.lua draws
-- the tiles. It follows the player until dragged; "Centre on me" or reopening follows again. The zone
-- under the cursor (or the centre) is named in the title (C_Map.GetMapPosFromWorldPos gives the map
-- there). Opened with /bmap map, a key binding, and a right-click on the world map's terrain button.
--
-- Drawn, bottom up: the sea's colour where there's no tile (ns.SEA: the coast's tile grid doesn't
-- show), terrain, the hovered zone's highlight, BubbleQuest's quest layer (when it's loaded), Blizzard's
-- map points (MapPoints.lua), group members (Group.lua), the player's arrow; the hovered zone named in
-- the title.
--
-- The zone highlight is Blizzard's own, the glow its world map shows over a zone on a continent map
-- (C_Map.GetMapHighlightInfoAtPosition, as MapHighlightDataProvider.lua): asked at the cursor's place
-- on the continent's UI map, its rectangle (0..1 on that map) turned into world yards and so drawn at
-- our scale.

local TILE_YARDS = 1600 / 3
local MIN_PPY, MAX_PPY = 0.015, 4   -- a whole continent .. a few yards a tile pixel
local WHEEL_STEP = 1.25
local DEFAULT_PPY = 0.25
local TITLE_HEIGHT = 22
local ARROW = "Interface\\Minimap\\MinimapArrow"

local MapWindow = {
  following = true,  -- the view stays on the player until dragged
}
ns.MapWindow = MapWindow

local HIGHLIGHT_ALPHA = 0.7

local window, content, view, arrow, title, highlight, points, group
local quests  -- BubbleQuest's quest view on our map, when BubbleQuest is loaded (BubbleQuestAPI.CreateQuestView)
local centre = { north = 0, west = 0, map = nil }
local ppy = DEFAULT_PPY
local drag  -- { x, y, north, west } while dragging

local function playerPosition()
  local north, west, _, map = UnitPosition("player")
  if north == nil or issecretvalue(north) then
    return nil
  end
  return north, west, map
end

-- World point under a screen offset (pixels right and up of the content's centre).
local function worldAt(dx, dy)
  return centre.north + dy / ppy, centre.west - dx / ppy
end

local function cursorOffset()
  local x, y = GetCursorPosition()
  local s = content:GetEffectiveScale()
  local cx, cy = content:GetCenter()
  return x / s - cx, y / s - cy
end

local function zoneName(north, west)
  if not centre.map then
    return nil
  end
  -- Without an override GetMapPosFromWorldPos answers with the continent (seen: "Eastern Kingdoms"
  -- over Westfall), so the zone is looked up on the continent's map at that place.
  local continent = ns.MapPoints.Continent(centre.map, north, west)
  if not continent then
    return nil
  end
  local _, pos = C_Map.GetMapPosFromWorldPos(centre.map, CreateVector2D(north, west), continent)
  local info = pos and C_Map.GetMapInfoAtPosition(continent, pos.x, pos.y)
  if not info or info.mapID == continent then
    info = C_Map.GetMapInfo(continent)
  end
  return info and info.name
end

-- Screen offset (from the content's centre) of a world point.
local function project(north, west)
  return (centre.west - west) * ppy, (north - centre.north) * ppy
end

-- Screen offset of a point on UI map `uiMap` (0..1), or nil when it isn't on this continent.
local function projectMapPos(uiMap, x, y)
  local cont, world = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(x, y))
  if cont ~= centre.map or not world then
    return nil
  end
  return project(world.x, world.y)
end

-- The zone under the cursor, highlighted as Blizzard's continent map does it.
local function drawHighlight(north, west)
  local continent = north and ns.MapPoints.Continent(centre.map, north, west)
  local _, pos
  if continent then
    _, pos = C_Map.GetMapPosFromWorldPos(centre.map, CreateVector2D(north, west), continent)
  end
  local fileID, atlas, texX, texY, w, h, left, top
  if pos then
    fileID, atlas, texX, texY, w, h, left, top = C_Map.GetMapHighlightInfoAtPosition(continent, pos.x, pos.y)
  end
  local x1, y1, x2, y2
  if ((fileID and fileID > 0) or atlas) and w and w > 0 and h > 0 then
    x1, y1 = projectMapPos(continent, left, top)
    x2, y2 = projectMapPos(continent, left + w, top + h)
  end
  if not (x1 and x2) then
    highlight:Hide()
    return
  end
  local key = atlas or fileID
  if highlight.key ~= key then
    highlight.key = key
    if atlas then
      highlight:SetAtlas(atlas)
    else
      highlight:SetTexture(fileID, nil, nil, "TRILINEAR")
      highlight:SetTexCoord(0, texX, 0, texY)
    end
  end
  highlight:ClearAllPoints()
  highlight:SetPoint("TOPLEFT", content, "CENTER", x1, y1)
  highlight:SetPoint("BOTTOMRIGHT", content, "CENTER", x2, y2)
  highlight:Show()
end

local function redraw()
  if not window:IsShown() then
    return
  end
  if MapWindow.following then
    local north, west, map = playerPosition()
    if north then
      centre.north, centre.west, centre.map = north, west, map
    end
  end
  if not centre.map then
    title:SetText("BubbleMap")
    highlight:Hide()
    points:Draw(nil, 0, 0)
    group:Draw(nil)
    return
  end
  -- The world point under the cursor, while it's over the map and not dragging it.
  local hoverNorth, hoverWest
  if content:IsMouseOver() and not drag then
    hoverNorth, hoverWest = worldAt(cursorOffset())
  end

  view:Draw(centre.north, centre.west, centre.map, ppy)
  drawHighlight(hoverNorth, hoverWest)
  if quests then
    quests:Draw(centre.north, centre.west, centre.map, ppy, 0)  -- north up: no turn
  end
  -- Tooltips: BubbleQuest's (a giver, service or quest area) right of the cursor, a member's name left of
  -- it (both show); a point's only when neither is up (it's at the cursor too). IsHovering is newer than
  -- API 1's first handles: absent, the point's shows too.
  local questTip = quests and quests.IsHovering and quests:IsHovering() or false
  group:Draw(centre.map, project)
  points:Draw(centre.map, centre.north, centre.west, project, questTip or group:IsHovering())

  -- The player's arrow, where they are (hidden off this continent or out of view).
  local north, west, map = playerPosition()
  if north and map == centre.map then
    local x, y = project(north, west)
    local halfW, halfH = content:GetWidth() / 2, content:GetHeight() / 2
    arrow:SetShown(math.abs(x) <= halfW and math.abs(y) <= halfH)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", content, "CENTER", x, y)
    arrow:SetRotation(GetPlayerFacing() or 0)
  else
    arrow:Hide()
  end

  local name = hoverNorth and zoneName(hoverNorth, hoverWest)
  title:SetText(name or zoneName(centre.north, centre.west) or "BubbleMap")
end

local function zoomAt(delta)
  local old = ppy
  ppy = math.max(MIN_PPY, math.min(MAX_PPY, ppy * WHEEL_STEP ^ delta))
  if ppy == old then
    return
  end
  -- Keep the point under the cursor where it is: zoom toward it.
  local dx, dy = cursorOffset()
  local north, west = centre.north + dy / old, centre.west - dx / old
  centre.north, centre.west = north - dy / ppy, west + dx / ppy
  MapWindow.following = false
  redraw()
end

local function saveFrame()
  local left, top = window:GetLeft(), window:GetTop()
  if left and top then
    ns.DB.window = { left = left, top = top, width = window:GetWidth(), height = window:GetHeight() }
  end
end

local function create()
  window = CreateFrame("Frame", "BubbleMapWindow", UIParent, "BackdropTemplate")
  window:SetFrameStrata("HIGH")
  window:SetClampedToScreen(true)
  window:SetMovable(true)
  window:SetResizable(true)
  window:SetResizeBounds(320, 240)
  local saved = ns.DB.window
  if saved then
    window:SetSize(saved.width, saved.height)
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
  else
    window:SetSize(760, 520)
    window:SetPoint("CENTER")
  end
  window:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
  })
  window:SetBackdropColor(ns.SEA[1], ns.SEA[2], ns.SEA[3], ns.SEA[4])
  window:SetBackdropBorderColor(0, 0, 0, 1)
  window:Hide()
  tinsert(UISpecialFrames, "BubbleMapWindow")  -- Escape closes it

  -- Title bar: drags the window; the zone's name; centre-on-me and close.
  local bar = CreateFrame("Frame", nil, window)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(TITLE_HEIGHT)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() window:StartMoving() end)
  bar:SetScript("OnDragStop", function()
    window:StopMovingOrSizing()
    saveFrame()
  end)
  local band = bar:CreateTexture(nil, "BACKGROUND")
  band:SetAllPoints()
  band:SetColorTexture(0, 0, 0, 0.6)
  title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", 8, 0)
  local close = CreateFrame("Button", nil, bar, "UIPanelCloseButtonNoScripts")
  close:SetPoint("RIGHT", 2, 0)
  close:SetSize(24, 24)
  close:SetScript("OnClick", function() window:Hide() end)
  local me = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
  me:SetText("Centre on me")
  me:SetSize(me:GetFontString():GetStringWidth() + 20, 18)
  me:SetPoint("RIGHT", close, "LEFT", -4, 0)
  me:SetScript("OnClick", function()
    MapWindow.following = true
    redraw()
  end)

  -- The map: clipped; drag to pan, wheel to zoom.
  content = CreateFrame("Frame", nil, window)
  content:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", -1, 1)
  content:SetClipsChildren(true)
  content:EnableMouse(true)
  content:EnableMouseWheel(true)
  view = ns.TileView.New(content)
  local highlightFrame = CreateFrame("Frame", nil, content)
  highlightFrame:SetAllPoints()
  highlightFrame:SetFrameLevel(content:GetFrameLevel() + 1)
  highlight = highlightFrame:CreateTexture(nil, "ARTWORK")
  highlight:SetBlendMode("ADD")  -- as Blizzard's (MapHighlightDataProvider.xml)
  highlight:SetAlpha(HIGHLIGHT_ALPHA)
  highlight:Hide()
  content:SetScript("OnMouseWheel", function(_, delta) zoomAt(delta) end)
  content:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      local x, y = GetCursorPosition()
      drag = { x = x, y = y, north = centre.north, west = centre.west }
    end
  end)
  content:SetScript("OnMouseUp", function() drag = nil end)

  -- BubbleQuest's quest areas, givers' "!", turn-in "?" and the guide line, the same as on its minimap
  -- and the world map (one renderer: its UI/QuestView.lua), over our tiles and under our arrow. Its hover
  -- takes `content` as the frame under the cursor (content takes the mouse for drag and wheel).
  local quest = ns.Quest
  if quest and quest.CreateQuestView then
    -- Town services too (its Town services toggles), less flight masters: MapPoints draws those, with
    -- their discovered state.
    quests = quest.CreateQuestView(content, { guide = true, hover = true, services = { exclude = { flight = true } } })
    quests:GetFrame():SetFrameLevel(content:GetFrameLevel() + 3)
  end

  -- Blizzard's map points and the group's dots, over the quest layer (their icons are small and few).
  points = ns.MapPoints.NewLayer(content)
  points.frame:SetFrameLevel(content:GetFrameLevel() + 4)
  group = ns.Group.NewLayer(content)
  group.frame:SetFrameLevel(content:GetFrameLevel() + 5)

  local arrowFrame = CreateFrame("Frame", nil, content)
  arrowFrame:SetAllPoints()
  arrowFrame:SetFrameLevel(content:GetFrameLevel() + 6)
  arrow = arrowFrame:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(28, 28)
  arrow:SetTexture(ARROW)

  -- Resize from the bottom-right corner.
  local grip = CreateFrame("Button", nil, window)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(content:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    window:StopMovingOrSizing()
    saveFrame()
  end)

  -- Every frame while shown: drag panning, following the player, the arrow, the zone name. Cheap: tiles
  -- are only (re)textured when they come into view (TileView).
  window:SetScript("OnUpdate", function()
    if drag then
      local x, y = GetCursorPosition()
      local s = content:GetEffectiveScale()
      local dx, dy = (x - drag.x) / s, (y - drag.y) / s
      if dx ~= 0 or dy ~= 0 then
        MapWindow.following = false
        centre.north, centre.west = drag.north - dy / ppy, drag.west + dx / ppy
      end
    end
    redraw()
  end)
  window:SetScript("OnShow", function()
    MapWindow.following = true
    ns.MapPoints.Refresh()  -- flight points learned, events begun since it was last open
    if quests then
      quests:Show()
    end
    redraw()
  end)
  window:SetScript("OnHide", function()
    points:Draw(nil, 0, 0)  -- drops their tooltips, if up
    group:Draw(nil)
    if quests then
      quests:Hide()
    end
  end)
end

---Open or close the map window.
function MapWindow:Toggle()
  if not window then
    create()
  end
  window:SetShown(not window:IsShown())
end

---One line for /bmap.
---@return string
function MapWindow:Describe()
  if not view then
    return "map window not opened yet"
  end
  local continent = centre.map and ns.MapPoints.Continent(centre.map, centre.north, centre.west)
  local count = continent and #ns.MapPoints.For(centre.map, centre.north, centre.west) or 0
  return ("map window: %d tiles loaded, %d failed, %.3f px/yd; map %s, continent UI map %s, %d points, "
    .. "zone highlight %s"):format(view.loaded, view.failed, ppy, tostring(centre.map), tostring(continent),
    count, highlight.key and tostring(highlight.key) or "never shown")
end

-- The key binding (Bindings.xml): Options > Keybindings > AddOns > BubbleMap.
BINDING_HEADER_BUBBLEMAP = "BubbleMap"
BINDING_NAME_BUBBLEMAP_TOGGLE_MAP = "Open or close BubbleMap's map"
function BubbleMap_ToggleMap()
  MapWindow:Toggle()
end
