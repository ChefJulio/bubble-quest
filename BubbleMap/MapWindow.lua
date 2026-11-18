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
-- First part: terrain, pan, zoom, the player's arrow, zone names. Next (docs): BubbleQuest's quest layers
-- (needs a BubbleQuest renderer for any centre and scale), Blizzard-style points (flight masters, dungeon
-- entrances, area events), group members.

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

local window, content, view, arrow, title
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
  local uiMap = C_Map.GetMapPosFromWorldPos(centre.map, CreateVector2D(north, west))
  local info = uiMap and C_Map.GetMapInfo(uiMap)
  return info and info.name
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
    return
  end
  view:Draw(centre.north, centre.west, centre.map, ppy)

  -- The player's arrow, where they are (hidden off this continent or out of view).
  local north, west, map = playerPosition()
  if north and map == centre.map then
    local x, y = (centre.west - west) * ppy, (north - centre.north) * ppy
    local halfW, halfH = content:GetWidth() / 2, content:GetHeight() / 2
    arrow:SetShown(math.abs(x) <= halfW and math.abs(y) <= halfH)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", content, "CENTER", x, y)
    arrow:SetRotation(GetPlayerFacing() or 0)
  else
    arrow:Hide()
  end

  local name
  if content:IsMouseOver() then
    name = zoneName(worldAt(cursorOffset()))
  end
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
  window:SetBackdropColor(0.05, 0.06, 0.07, 1)
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
  content:SetScript("OnMouseWheel", function(_, delta) zoomAt(delta) end)
  content:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      local x, y = GetCursorPosition()
      drag = { x = x, y = y, north = centre.north, west = centre.west }
    end
  end)
  content:SetScript("OnMouseUp", function() drag = nil end)

  local arrowFrame = CreateFrame("Frame", nil, content)
  arrowFrame:SetAllPoints()
  arrowFrame:SetFrameLevel(content:GetFrameLevel() + 5)
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
    redraw()
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
  return ("map window: %d tiles loaded, %d failed, %.3f px/yd"):format(view.loaded, view.failed, ppy)
end

-- The key binding (Bindings.xml): Options > Keybindings > AddOns > BubbleMap.
BINDING_HEADER_BUBBLEMAP = "BubbleMap"
BINDING_NAME_BUBBLEMAP_TOGGLE_MAP = "Open or close BubbleMap's map"
function BubbleMap_ToggleMap()
  MapWindow:Toggle()
end
