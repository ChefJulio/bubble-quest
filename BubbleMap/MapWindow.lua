local ADDON_NAME, ns = ...

-- BubbleMap's own map window: every continent on one map (World.lua lays them out as the world map
-- does), dragged to pan across zones and continents, wheeled to zoom far further in and out than
-- Blizzard's world map (which can't: its zoom levels come from its map art and a pan stops at the zone;
-- changing either taints it). Design: docs/design/questmarker-map.md ("The world map").
--
-- A view is a centre on World's plane (X east, Y south, yards) and a scale (pixels per yard). Each
-- continent in view is drawn in its own yards, centred where the plane's centre falls on it, by its own
-- layers (a "slot"): terrain tiles (TileView) or the painted art (Art), BubbleQuest's quest layer,
-- Blizzard's map points (MapPoints), group members (Group). Far out the terrain gives way to the
-- continents' art (thousands of tiles otherwise). It follows the player until dragged; "Centre on me" or
-- reopening follows again. Opened with /bmap map, a key binding, and a right-click on the world map's
-- terrain button.
--
-- Drawn, bottom up: the sea's colour where nothing is (ns.SEA: the coast's tile grid doesn't show),
-- terrain or art, the hovered zone's highlight, the quest layer, map points, group members, waypoints
-- (Waypoints.lua), zone names when zoomed out, the player's arrow. The title names the zone under the
-- cursor; the bottom bar gives your coordinates and the cursor's (zone %, as the world map) and the
-- style switch (Terrain / Map art, the window's own setting: windowStyle).
--
-- The zone highlight is Blizzard's own, the glow its world map shows over a zone on a continent map
-- (C_Map.GetMapHighlightInfoAtPosition, as MapHighlightDataProvider.lua): asked at the cursor's place
-- on the continent's UI map, its rectangle (0..1 on that map) turned into world yards and so drawn at
-- our scale.
--
-- Clicks (Waypoints.lua): a click drops your waypoint, Shift+click shares it with your party,
-- right-click on a waypoint clears it.

local MIN_PPY, MAX_PPY = 0.004, 4   -- the whole world .. a few yards a tile pixel
local TILES_FROM_PPY = 0.012        -- nearer: terrain tiles; farther: the continents' art (Art.lua)
local ZONE_ART_FROM_PPY = 0.02      -- nearer: zones' art over the continent's (Map art style)
local LABELS_UNTIL_PPY, LABELS_FADE = 0.07, 0.025  -- zone names out to here, fading over the last stretch
local WHEEL_STEP = 1.25
local DEFAULT_PPY = 0.25
local TITLE_HEIGHT, FOOTER_HEIGHT = 22, 20
local CLICK_SLOP = 4                -- pixels the mouse may move for a press to count as a click
local ARROW = "Interface\\Minimap\\MinimapArrow"
local HIGHLIGHT_ALPHA = 0.7

local MapWindow = {
  following = true,  -- the view stays on the player until dragged
}
ns.MapWindow = MapWindow

local window, content, arrow, title, highlight, footerLeft, footerRight, styleButton
local layers = {}   -- frames shared by every slot, by kind: tiles, art, highlight, points, group, labels
local slots = {}    -- [instance map] = { e (World entry), tiles, art, quests, points, group, labels }
local centre = { x = 0, y = 0 }
local ppy = DEFAULT_PPY
local drag  -- { x, y, cx, cy, moved } while the left button is down

local function playerPosition()
  local north, west, _, map = UnitPosition("player")
  if north == nil or issecretvalue(north) then
    return nil
  end
  return north, west, map
end

local function cursorOffset()
  local x, y = GetCursorPosition()
  local s = content:GetEffectiveScale()
  local cx, cy = content:GetCenter()
  return x / s - cx, y / s - cy
end

-- The plane point under a screen offset (pixels right and up of the content's centre).
local function planeAt(dx, dy)
  return centre.x + dx / ppy, centre.y - dy / ppy
end

-- A slot's projection: screen offset of a point in its continent's yards.
local function projector(e)
  local cn, cw = e.ay - centre.y, e.ax - centre.x  -- the view's centre in this continent's yards
  return function(north, west)
    return (cw - west) * ppy, (north - cn) * ppy
  end, cn, cw
end

---Screen offset of a point on any of our continents (nil when that map isn't on the plane). For
---layers drawing several continents at once (Waypoints.lua).
---@param map number
---@param north number
---@param west number
---@return number?
---@return number?
function MapWindow.Project(map, north, west)
  local x, y = ns.World.ToPlane(map, north, west)
  if not x then
    return nil
  end
  return (x - centre.x) * ppy, (centre.y - y) * ppy
end

-- The zone (UI map info) at a point of continent `e`, or the continent's own when between zones.
local function zoneAt(e, north, west)
  if not e.ui then
    return nil
  end
  -- Without an override GetMapPosFromWorldPos answers with the continent (seen: "Eastern Kingdoms" over
  -- Westfall), so the zone is looked up on the continent's map at that place.
  local _, pos = C_Map.GetMapPosFromWorldPos(e.map, CreateVector2D(north, west), e.ui)
  local info = pos and C_Map.GetMapInfoAtPosition(e.ui, pos.x, pos.y)
  if not info then
    info = C_Map.GetMapInfo(e.ui)
  end
  return info
end

-- Zone % coordinates of a point ("44.1, 61.7"), on the zone's map.
local function coords(map, uiMap, north, west)
  local _, pos = C_Map.GetMapPosFromWorldPos(map, CreateVector2D(north, west), uiMap)
  if not pos then
    return nil
  end
  return ("%.1f, %.1f"):format(pos.x * 100, pos.y * 100)
end

-- The zone under the cursor, highlighted as Blizzard's continent map does it.
local function drawHighlight(e, north, west, project)
  local fileID, atlas, texX, texY, w, h, left, top
  if e and e.ui and project then
    local _, pos = C_Map.GetMapPosFromWorldPos(e.map, CreateVector2D(north, west), e.ui)
    if pos then
      fileID, atlas, texX, texY, w, h, left, top = C_Map.GetMapHighlightInfoAtPosition(e.ui, pos.x, pos.y)
    end
  end
  local x1, y1, x2, y2
  if ((fileID and fileID > 0) or atlas) and w and w > 0 and h > 0 then
    local _, a = C_Map.GetWorldPosFromMapPos(e.ui, CreateVector2D(left, top))
    local _, b = C_Map.GetWorldPosFromMapPos(e.ui, CreateVector2D(left + w, top + h))
    if a and b then
      x1, y1 = project(a.x, a.y)
      x2, y2 = project(b.x, b.y)
    end
  end
  if not x1 then
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

-- The area label: the big name at the map's top while hovering, as the world map's
-- (AreaLabelDataProvider.lua): the explored area under the cursor (MapUtil.FindBestAreaNameAtMouse: its
-- explored area IDs on the zone's map, C_Map.GetAreaInfo), else the zone with its level range coloured
-- for you (C_Map.GetMapLevels, GetQuestDifficultyColor).
local areaLabel

local function areaText(e, zone, north, west)
  if not (zone and e.ui) then
    return nil
  end
  if zone.mapID ~= e.ui then
    local _, pos = C_Map.GetMapPosFromWorldPos(e.map, CreateVector2D(north, west), zone.mapID)
    local areas = pos and C_MapExplorationInfo.GetExploredAreaIDsAtPosition(zone.mapID, pos)
    for _, areaID in ipairs(areas or {}) do
      local name = C_Map.GetAreaInfo(areaID)
      if name and name ~= "" then
        return name
      end
    end
  else
    return nil  -- between zones: nothing, as the world map
  end
  local name = zone.name
  local low, high = C_Map.GetMapLevels(zone.mapID)
  if name and low and high and low > 0 and high > 0 then
    local level = UnitLevel("player")
    local color
    if level < low then
      color = GetQuestDifficultyColor(low)
    elseif level > high then
      color = GetQuestDifficultyColor(high - 2)  -- zones wholly below you aren't yellow (as Blizzard)
    else
      color = QuestDifficultyColors["difficult"]
    end
    local range = low ~= high and (low .. "-" .. high) or tostring(high)
    name = ("%s%s (%s)|r"):format(name, RGBTableToColorCode(color), range)
  end
  return name
end

-- Zone names ------------------------------------------------------------------------------------------

-- A continent's zones with their names and middles (their map's centre, in the continent's yards), once.
local zoneLabels = {}
local function labelsOf(e)
  local list = zoneLabels[e.map]
  if not list then
    list = {}
    for _, zone in ipairs(e.ui and ns.Art.Zones(e.ui) or {}) do
      local info = C_Map.GetMapInfo(zone)
      local cont, mid = C_Map.GetWorldPosFromMapPos(zone, CreateVector2D(0.5, 0.5))
      if info and cont == e.map and mid then
        list[#list + 1] = { name = info.name, north = mid.x, west = mid.y }
      end
    end
    zoneLabels[e.map] = list
  end
  return list
end

local function drawLabels(slot, project, alpha)
  local strings = slot.labels
  local count = 0
  if alpha > 0 then
    local halfW, halfH = content:GetWidth() / 2, content:GetHeight() / 2
    for _, label in ipairs(labelsOf(slot.e)) do
      local x, y = project(label.north, label.west)
      if math.abs(x) <= halfW and math.abs(y) <= halfH then
        count = count + 1
        local s = strings[count]
        if not s then
          s = layers.labels:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
          strings[count] = s
        end
        s:SetText(label.name)
        s:ClearAllPoints()
        s:SetPoint("CENTER", content, "CENTER", x, y)
        s:SetAlpha(alpha)
        s:Show()
      end
    end
  end
  for i = count + 1, #strings do
    strings[i]:Hide()
  end
end

-- Slots -----------------------------------------------------------------------------------------------

local function slotFor(e)
  local slot = slots[e.map]
  if not slot then
    slot = { e = e, labels = {}, shown = false }
    slot.tiles = ns.TileView.New(layers.tiles)
    slot.art = ns.Art.New(layers.art)
    local quest = ns.Quest
    if quest and quest.CreateQuestView then
      -- BubbleQuest's quest areas, givers' "!", turn-in "?", the guide line and town services (less
      -- flight masters: MapPoints draws those, with their discovered state), the same as on its minimap
      -- and the world map (one renderer: its UI/QuestView.lua). Its hover takes `content` as the frame
      -- under the cursor (content takes the mouse for drag and wheel).
      slot.quests = quest.CreateQuestView(content,
        { guide = true, hover = true, services = { exclude = { flight = true } } })
      slot.quests:GetFrame():SetFrameLevel(content:GetFrameLevel() + 6)
    end
    slot.points = ns.MapPoints.NewLayer(layers.points)
    slot.group = ns.Group.NewLayer(layers.group)
    slots[e.map] = slot
  end
  return slot
end

local function hideSlot(slot)
  if not slot.shown then
    return
  end
  slot.shown = false
  slot.tiles:Draw(0, 0, -1, ppy)  -- a map with no tiles: everything parked
  slot.art:Hide()
  if slot.quests then
    slot.quests:Hide()
  end
  slot.points:Draw(nil, 0, 0)
  slot.group:Draw(nil)
  drawLabels(slot, nil, 0)
end

-- Drawing ---------------------------------------------------------------------------------------------

local function redraw()
  if not window:IsShown() then
    return
  end
  local pn, pw, pmap = playerPosition()
  if MapWindow.following and pn then
    local x, y = ns.World.ToPlane(pmap, pn, pw)
    if x then
      centre.x, centre.y = x, y
    end
  end

  -- The plane point under the cursor, while it's over the map and not dragging it.
  local hoverEntry, hoverNorth, hoverWest
  if content:IsMouseOver() and not (drag and drag.moved) then
    hoverEntry, hoverNorth, hoverWest = ns.World.FromPlane(planeAt(cursorOffset()))
  end

  local halfW, halfH = content:GetWidth() / 2 / ppy, content:GetHeight() / 2 / ppy
  local style = ns.DB.windowStyle
  local labelAlpha = math.max(0, math.min(1, (LABELS_UNTIL_PPY - ppy) / LABELS_FADE))
  local hoverProject
  -- Tooltips, one continent's at a time (the one under the cursor): BubbleQuest's right of the cursor,
  -- a member's name left of it (both show); a point's only when neither is up.
  for _, e in ipairs(ns.World.Continents()) do
    local inView = e.x1 >= centre.x - halfW and e.x0 <= centre.x + halfW
      and e.y1 >= centre.y - halfH and e.y0 <= centre.y + halfH
    local slot = slots[e.map]
    if inView then
      slot = slotFor(e)
      slot.shown = true
      local project, cn, cw = projector(e)
      -- A continent without a UI map (one the world map doesn't know) has no art: terrain at any zoom.
      if (style == "art" or ppy < TILES_FROM_PPY) and e.ui then
        slot.tiles:Draw(0, 0, -1, ppy)
        slot.art:Draw(cn, cw, e.map, ppy, 0, nil, ppy < ZONE_ART_FROM_PPY)
      else
        slot.art:Hide()
        slot.tiles:Draw(cn, cw, e.map, ppy)
      end
      if slot.quests then
        slot.quests:Show()
        slot.quests:Draw(cn, cw, e.map, ppy, 0)  -- north up: no turn
      end
      local questTip = slot.quests and slot.quests.IsHovering and slot.quests:IsHovering() or false
      slot.group:Draw(e.map, project)
      slot.points:Draw(e.map, cn, cw, project, questTip or slot.group:IsHovering())
      drawLabels(slot, project, labelAlpha)
      if e == hoverEntry then
        hoverProject = project
      end
    elseif slot then
      hideSlot(slot)
    end
  end
  drawHighlight(hoverEntry, hoverNorth, hoverWest, hoverProject)
  if ns.Waypoints then
    ns.Waypoints:DrawWindow(layers.waypoints, MapWindow.Project)
  end

  -- The player's arrow, where they are (hidden off our continents or out of view).
  local ax, ay = nil, nil
  if pn and pw and pmap then
    ax, ay = MapWindow.Project(pmap, pn, pw)
  end
  if ax and ay and math.abs(ax) <= halfW * ppy and math.abs(ay) <= halfH * ppy then
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", content, "CENTER", ax, ay)
    arrow:SetRotation(GetPlayerFacing() or 0)
    arrow:Show()
  else
    arrow:Hide()
  end

  -- Title: the zone under the cursor, else under the centre. Footer: coordinates.
  local hoverZone = hoverEntry and zoneAt(hoverEntry, hoverNorth, hoverWest)
  local centreEntry, centreNorth, centreWest = ns.World.FromPlane(centre.x, centre.y)
  local centreZone = centreEntry and zoneAt(centreEntry, centreNorth, centreWest)
  title:SetText((hoverZone or centreZone or {}).name or "BubbleMap")
  areaLabel:SetText(hoverEntry and hoverNorth and hoverWest and areaText(hoverEntry, hoverZone, hoverNorth, hoverWest)
    or "")
  local here = C_Map.GetBestMapForUnit("player")
  local mine = pn and pw and pmap and here and coords(pmap, here, pn, pw)
  footerLeft:SetText(mine and ("Player: " .. mine) or "")
  local cursor = hoverZone and hoverNorth and hoverWest and coords(hoverEntry.map, hoverZone.mapID, hoverNorth,
    hoverWest)
  footerRight:SetText(cursor and ("Cursor: " .. cursor) or "")
end

local function zoomAt(delta)
  local old = ppy
  ppy = math.max(MIN_PPY, math.min(MAX_PPY, ppy * WHEEL_STEP ^ delta))
  if ppy == old then
    return
  end
  -- Keep the point under the cursor where it is: zoom toward it.
  local dx, dy = cursorOffset()
  local x, y = centre.x + dx / old, centre.y - dy / old
  centre.x, centre.y = x - dx / ppy, y + dy / ppy
  MapWindow.following = false
  redraw()
end

local function updateStyleButton()
  styleButton:SetText(ns.DB.windowStyle == "art" and "Map art" or "Terrain")
  styleButton:SetWidth(styleButton:GetFontString():GetStringWidth() + 20)
end

local function saveFrame()
  local left, top = window:GetLeft(), window:GetTop()
  if left and top then
    ns.DB.window = { left = left, top = top, width = window:GetWidth(), height = window:GetHeight() }
  end
end

-- A click on the map (no drag): waypoints (Waypoints.lua).
local function click(button)
  if not ns.Waypoints then
    return
  end
  local dx, dy = cursorOffset()
  local e, north, west = ns.World.FromPlane(planeAt(dx, dy))
  if button == "RightButton" then
    ns.Waypoints:RemoveNear(MapWindow.Project, dx, dy)
  elseif e then
    ns.Waypoints:Set(e.map, north, west, IsShiftKeyDown())
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

  -- Footer: coordinates, the style switch.
  local footer = CreateFrame("Frame", nil, window)
  footer:SetPoint("BOTTOMLEFT", 1, 1)
  footer:SetPoint("BOTTOMRIGHT", -1, 1)
  footer:SetHeight(FOOTER_HEIGHT)
  local footerBand = footer:CreateTexture(nil, "BACKGROUND")
  footerBand:SetAllPoints()
  footerBand:SetColorTexture(0, 0, 0, 0.6)
  footerLeft = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footerLeft:SetPoint("LEFT", 8, 0)
  footerRight = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footerRight:SetPoint("LEFT", footer, "CENTER", -40, 0)
  styleButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
  styleButton:SetHeight(16)
  styleButton:SetPoint("RIGHT", -20, 0)  -- clear of the resize grip
  styleButton:SetScript("OnClick", function()
    ns.DB.windowStyle = ns.DB.windowStyle == "art" and "terrain" or "art"
    updateStyleButton()
  end)
  styleButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Map style: " .. (ns.DB.windowStyle == "art" and "map art" or "terrain"), 1, 1, 1)
    GameTooltip:AddLine("Click to switch between the real terrain and the world map's painted art. "
      .. "Zoomed far out, the continents' art shows either way.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  styleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  updateStyleButton()

  -- The map: clipped; drag to pan, wheel to zoom, click for waypoints.
  content = CreateFrame("Frame", nil, window)
  content:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
  content:SetClipsChildren(true)
  content:EnableMouse(true)
  content:EnableMouseWheel(true)
  -- The layers every continent's slot draws into, bottom up (the quest layers sit at + 6).
  local function layer(level)
    local frame = CreateFrame("Frame", nil, content)
    frame:SetAllPoints()
    frame:SetFrameLevel(content:GetFrameLevel() + level)
    return frame
  end
  layers.tiles = content  -- TileView anchors to its frame's centre, under everything else
  layers.art = layer(0)
  local highlightFrame = layer(5)  -- over the art view's three frames (Art.New: + 1 .. + 3)
  highlight = highlightFrame:CreateTexture(nil, "ARTWORK")
  highlight:SetBlendMode("ADD")  -- as Blizzard's (MapHighlightDataProvider.xml)
  highlight:SetAlpha(HIGHLIGHT_ALPHA)
  highlight:Hide()
  layers.points = layer(7)
  layers.group = layer(8)
  layers.waypoints = layer(9)
  layers.labels = layer(10)
  -- The area label, at the top as the world map's (its template: scale 0.695, 10 px down).
  local labelFrame = layer(12)
  labelFrame:SetScale(0.695)
  areaLabel = labelFrame:CreateFontString(nil, "OVERLAY", "WorldMapTextFont")
  areaLabel:SetPoint("TOP", labelFrame, "TOP", 0, -10 / 0.695)
  areaLabel:SetTextColor(1.0, 0.9294, 0.7607)  -- AREA_NAME_FONT_COLOR (defined only in some clients' constants)
  local arrowFrame = layer(11)
  arrow = arrowFrame:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(28, 28)
  arrow:SetTexture(ARROW)

  content:SetScript("OnMouseWheel", function(_, delta) zoomAt(delta) end)
  content:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      local x, y = GetCursorPosition()
      drag = { x = x, y = y, cx = centre.x, cy = centre.y, moved = false }
    end
  end)
  content:SetScript("OnMouseUp", function(_, button)
    local wasDrag = drag and drag.moved
    drag = nil
    if not wasDrag and content:IsMouseOver() then
      click(button)
    end
  end)

  -- Resize from the bottom-right corner.
  local grip = CreateFrame("Button", nil, window)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(content:GetFrameLevel() + 14)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    window:StopMovingOrSizing()
    saveFrame()
  end)

  -- Every frame while shown: drag panning, following the player, everything's position. Cheap: tiles
  -- and art are only (re)textured when they come into view.
  window:SetScript("OnUpdate", function()
    if drag then
      local x, y = GetCursorPosition()
      local s = content:GetEffectiveScale()
      local dx, dy = (x - drag.x) / s, (y - drag.y) / s
      if drag.moved or math.abs(dx) > CLICK_SLOP or math.abs(dy) > CLICK_SLOP then
        drag.moved = true
        MapWindow.following = false
        centre.x, centre.y = drag.cx - dx / ppy, drag.cy + dy / ppy
      end
    end
    redraw()
  end)
  window:SetScript("OnShow", function()
    MapWindow.following = true
    ns.MapPoints.Refresh()  -- flight points learned, events begun since it was last open
    redraw()
  end)
  window:SetScript("OnHide", function()
    for _, slot in pairs(slots) do
      hideSlot(slot)  -- drops their tooltips, if up
    end
    if ns.Waypoints then
      ns.Waypoints:DrawWindow(layers.waypoints, nil)
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
  if not window then
    return "map window not opened yet"
  end
  local loaded, failed, shown = 0, 0, {}
  for map, slot in pairs(slots) do
    loaded, failed = loaded + slot.tiles.loaded, failed + slot.tiles.failed
    if slot.shown then
      shown[#shown + 1] = ("%d (UI map %s, %d points)"):format(map, tostring(slot.e.ui),
        #ns.MapPoints.For(map, slot.e.ay - centre.y, slot.e.ax - centre.x))
    end
  end
  local placed = {}
  for _, e in ipairs(ns.World.Continents()) do
    placed[#placed + 1] = ("%d%s"):format(e.map, e.rect and "" or " (placed by hand)")
  end
  return ("map window: %.4f px/yd, style %s; continents %s; drawing %s; %d tiles loaded, %d failed; zone "
    .. "highlight %s"):format(ppy, ns.DB.windowStyle, table.concat(placed, ", "),
    #shown > 0 and table.concat(shown, ", ") or "none", loaded, failed,
    highlight.key and tostring(highlight.key) or "never shown")
end

-- The key binding (Bindings.xml): Options > Keybindings > AddOns > BubbleMap.
BINDING_HEADER_BUBBLEMAP = "BubbleMap"
BINDING_NAME_BUBBLEMAP_TOGGLE_MAP = "Open or close BubbleMap's map"
function BubbleMap_ToggleMap()
  MapWindow:Toggle()
end
