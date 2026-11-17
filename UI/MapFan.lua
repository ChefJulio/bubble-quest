local ADDON_NAME, ns = ...

-- Fanning out overlapping icons on the world map (review: a turn-in "?" sat under a trainer's icon in
-- Goldshire). When the cursor rests on two or more of our icons that overlap (quest givers' "!",
-- turn-in "?", town services), they glide into a row just above that spot (below it near the map's
-- top edge), on a dark strip with a tooltip border, ordered left to right by where they are, each with a thin line
-- down to its real place and its own tooltip. Leaving the area they glide back. (The first version
-- was a ring that opened at once: "kinda ugly", review asked for a row and a smooth move.)
--
-- The icon layers (UI/MapAvailable.lua, UI/MapServices.lua, UI/MapAreas.lua's turn-ins) each keep a
-- list of their icons (fanItems: texture, x, y on the canvas, base size, fill(tooltip), and click() when
-- clicking it does something: a turn-in opens its quest) and register
-- it here. While a row is open this file owns the tooltip; the layers' own hovers stand aside
-- (MapFan.fanned), and a redraw or zoom folds it back at once (Collapse), as textures move or go.

local HOVER_SECONDS = 0.05
local ANIMATE_SECONDS = 0.15
local ROW_SPACING = 1.35      -- icon sizes between icons in the row
local ROW_LIFT = 1.9          -- icon sizes from the cluster's top to the row
local STRIP_PAD = 0.4         -- icon sizes of strip around the row
local STRIP_EDGE = 12         -- the border's thickness, pixels on screen
-- The strip: a dark panel with Blizzard's tooltip border (review: the plain box "looks kinda weird",
-- a soft shadow under it was "wrong"; it wanted a styled edge), like the tooltips its icons show.
local STRIP_FILL = { 0.05, 0.05, 0.06, 0.85 }
local STRIP_BORDER = { 0.6, 0.6, 0.6, 0.95 }
local LINE_ALPHA = 0.5
local KEEP_PAD = 0.6          -- icon sizes of margin around what's open before it folds back
-- The open row (strip, lines, stand-ins) over every layer of ours (2004-2008, UI/MapAreas.lua), so it
-- covers icons that aren't in it; at least this, and above Blizzard's topmost pins (raiseAbovePins).
local BACKDROP_LEVEL = 2010

local MapFan = {
  lists = {},       -- registered fanItems lists, by layer name
  fanned = nil,     -- the open row: { items, t (0 closed .. 1 open), closing, box, size, scale }
}
ns.MapFan = MapFan

---A layer's icons (its fanItems list, kept up to date by the layer).
---@param name string
---@param list table[]
function MapFan:Register(name, list)
  self.lists[name] = list
end

-- Created with the world map (create(), below); everything here runs only after that.
local frame ---@type table
local canvas ---@type table
local strip ---@type table
local overlay ---@type table  -- above the strip: lines and stand-ins
local lines = {}
-- Stand-ins: while a row is open the grouped icons are drawn here, on top of everything of ours
-- (review: another "?" showed over the strip), copies of the originals, which turn invisible in place.
local proxies = {}
local overProxies = {}  -- an item's second layer (`over`: a turn-in's "?" on its disc)

local function copyLook(from, to)
  local atlas = from:GetAtlas()
  if atlas then
    to:SetAtlas(atlas)
  else
    to:SetTexture(from:GetTexture())
    to:SetTexCoord(from:GetTexCoord())
  end
  to:SetDesaturated(from:IsDesaturated())
  to:SetVertexColor(from:GetVertexColor())
  to:SetSize(from:GetSize())
end

-- An icon's size on the canvas per unit of its base size (the scales, read once per use).
local function sizeFactor()
  return ns.MapAreas.iconScale() * UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
end

local function place(texture, x, y)
  texture:ClearAllPoints()
  texture:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
end

local function ease(t)  -- smooth start and end
  return t * t * (3 - 2 * t)
end

-- Draw the row at progress t: icons between their place and the row, lines and strip fading in.
local function render(fanned)
  local e = ease(fanned.t)
  for i, item in ipairs(fanned.items) do
    item.curX = item.x + (item.fanX - item.x) * e
    item.curY = item.y + (item.fanY - item.y) * e
    place(proxies[i], item.curX, item.curY)
    if item.over then
      place(overProxies[i], item.curX, item.curY)
    end
    local line = lines[i]
    line:SetStartPoint("TOPLEFT", canvas, item.x, -item.y)
    line:SetEndPoint("TOPLEFT", canvas, item.curX, -item.curY)
    line:SetAlpha(e)
    line:Show()
  end
  strip:SetAlpha(e)
  strip:Show()
end

local function finish()
  local fanned = MapFan.fanned
  MapFan.fanned = nil
  if fanned then
    for _, item in ipairs(fanned.items) do
      item.texture:SetAlpha(1)  -- the original, back
      if item.over then
        item.over:SetAlpha(1)
      end
    end
  end
  for _, proxy in ipairs(proxies) do
    proxy:Hide()
  end
  for _, proxy in ipairs(overProxies) do
    proxy:Hide()
  end
  for _, line in ipairs(lines) do
    line:Hide()
  end
  if strip then
    strip:Hide()
  end
  if frame and GameTooltip:GetOwner() == frame then
    GameTooltip:Hide()
  end
end

---Fold the row back at once (icons to their places): before a layer redraws or resizes its icons.
function MapFan:Collapse()
  if self.fanned then
    finish()
  end
end

-- Crowding, measured on screen relative to the icons' size (review: "hard to decide what should be
-- included by distance with zoom"): two icons are neighbours when their gap is under LINK_GAP of an
-- icon, and a group is everything linked to the hovered icon through neighbours (A near B near C).
-- Zoomed out a town's icons chain into one row; zoomed in they part, and there's nothing to untangle.
local LINK_GAP = 0.6
-- At most this many in a row, the nearest the cursor (review: on a continent map a whole kingdom's
-- icons chained into one strip across the map).
local MAX_ROW = 6

-- The icon under (x, y) and every icon linked to it, or nil when it stands alone.
local function cluster(x, y)
  local factor = sizeFactor()  -- this runs 20 times a second
  local all, first = {}, nil
  for _, list in pairs(MapFan.lists) do
    for _, item in ipairs(list) do
      if item.texture:IsShown() then
        local r = item.base * factor / 2
        all[#all + 1] = item
        if not first and (item.x - x) ^ 2 + (item.y - y) ^ 2 <= r * r then
          first = item
        end
      end
    end
  end
  if not first then
    return nil
  end
  local group, inGroup, i = { first }, { [first] = true }, 1
  while group[i] do
    local a = group[i]
    for _, b in ipairs(all) do
      if not inGroup[b] then
        local reach = ((a.base + b.base) / 2 + LINK_GAP * math.max(a.base, b.base)) * factor
        if (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < reach * reach then
          inGroup[b] = true
          group[#group + 1] = b
        end
      end
    end
    i = i + 1
  end
  if #group > MAX_ROW then
    table.sort(group, function(a, b)
      return (a.x - x) ^ 2 + (a.y - y) ^ 2 < (b.x - x) ^ 2 + (b.y - y) ^ 2
    end)
    for j = #group, MAX_ROW + 1, -1 do
      group[j] = nil
    end
  end
  return #group >= 2 and group or nil
end

-- The open row goes above everything on the map canvas, Blizzard's pins included (review: its spirit
-- healer pin showed over the row; the pin manager's "topmost" level wasn't the highest in use). Every
-- pin is a child frame of the canvas: the highest level among them and their own children, read only,
-- once per opening.
local function highestOnCanvas()
  local highest = 0
  for _, child in ipairs({ canvas:GetChildren() }) do
    if child ~= frame then
      highest = math.max(highest, child:GetFrameLevel())
      for _, grandchild in ipairs({ child:GetChildren() }) do
        highest = math.max(highest, grandchild:GetFrameLevel())
      end
    end
  end
  return highest
end

local function raiseAbovePins()
  local level = math.max(BACKDROP_LEVEL, highestOnCanvas() + 1)
  if frame:GetFrameLevel() ~= level then
    frame:SetFrameLevel(level)
    strip:SetFrameLevel(level + 1)
    overlay:SetFrameLevel(level + 2)
  end
end

local function open(group)
  raiseAbovePins()
  local factor = sizeFactor()
  local size, cx, top, bottom = 0, 0, math.huge, -math.huge
  for _, item in ipairs(group) do
    size = math.max(size, item.base * factor)
    cx = cx + item.x
    top, bottom = math.min(top, item.y), math.max(bottom, item.y)
  end
  cx = cx / #group
  -- Left to right as they lie, so the lines don't cross.
  table.sort(group, function(a, b) return a.x < b.x end)
  local spacing = size * ROW_SPACING
  local rowY = top - size * ROW_LIFT
  if rowY < size then
    rowY = bottom + size * ROW_LIFT  -- near the map's top edge: below the spot
  end
  local width = canvas:GetWidth()
  local half = spacing * (#group - 1) / 2
  cx = math.max(half + size, math.min(width - half - size, cx))  -- the row stays on the map
  local scale = UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for i, item in ipairs(group) do
    item.fanX, item.fanY = cx - half + (i - 1) * spacing, rowY
    x1, x2 = math.min(x1, item.x, item.fanX), math.max(x2, item.x, item.fanX)
    y1, y2 = math.min(y1, item.y, item.fanY), math.max(y2, item.y, item.fanY)
    local line = lines[i]
    if not line then
      line = overlay:CreateLine(nil, "ARTWORK")
      line:SetColorTexture(1, 1, 1, LINE_ALPHA)
      lines[i] = line
    end
    line:SetThickness(1.2 * scale)
    -- The stand-in takes the icon's look; the original turns invisible where it is.
    local proxy = proxies[i]
    if not proxy then
      proxy = overlay:CreateTexture(nil, "OVERLAY")
      proxies[i] = proxy
    end
    copyLook(item.texture, proxy)
    place(proxy, item.x, item.y)
    proxy:Show()
    item.texture:SetAlpha(0)
    if item.over then
      local over = overProxies[i]
      if not over then
        over = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
        overProxies[i] = over
      end
      copyLook(item.over, over)
      place(over, item.x, item.y)
      over:Show()
      item.over:SetAlpha(0)
    end
  end
  -- The strip around the row; its border sized for the zoom (it's on the canvas, which scales).
  local edge = STRIP_EDGE * scale
  strip:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = edge, insets = { left = edge / 4, right = edge / 4, top = edge / 4, bottom = edge / 4 },
  })
  strip:SetBackdropColor(STRIP_FILL[1], STRIP_FILL[2], STRIP_FILL[3], STRIP_FILL[4])
  strip:SetBackdropBorderColor(STRIP_BORDER[1], STRIP_BORDER[2], STRIP_BORDER[3], STRIP_BORDER[4])
  strip:ClearAllPoints()
  strip:SetPoint("CENTER", canvas, "TOPLEFT", cx, -rowY)
  strip:SetSize(2 * half + size * (1 + 2 * STRIP_PAD), size * (1 + 2 * STRIP_PAD))
  local keep = size * KEEP_PAD
  MapFan.fanned = {
    items = group, t = 0, closing = false, size = size, scale = canvas:GetEffectiveScale(),
    box = { x1 - keep, y1 - keep, x2 + keep, y2 + keep },  -- what's open, plus a margin
  }
end

-- Every frame while something is open or moving: the glide.
local function animate(delta)
  local fanned = MapFan.fanned
  if not fanned then
    return
  end
  local step = delta / ANIMATE_SECONDS
  if fanned.closing then
    fanned.t = fanned.t - step
    if fanned.t <= 0 then
      finish()
      return
    end
  elseif fanned.t < 1 then
    fanned.t = math.min(1, fanned.t + step)
  else
    return  -- open and still
  end
  render(fanned)
end

-- The open row's icon at canvas pixels x, y, or nil.
local function itemAt(x, y)
  local fanned = MapFan.fanned
  if not fanned or fanned.closing then
    return nil
  end
  local factor = sizeFactor()
  for _, item in ipairs(fanned.items) do
    local r = item.base * factor / 2
    if item.curX and (x - item.curX) ^ 2 + (y - item.curY) ^ 2 <= r * r then
      return item
    end
  end
  return nil
end

-- A left-click on an icon in the open row that does something (its click()); anything else is the map's.
-- Through the map's canvas click handlers, ahead of UI/MapAreas.lua's (priority), as the row covers it.
local function onCanvasClick(_, button, nx, ny)
  if button ~= "LeftButton" or IsModifierKeyDown() or InCombatLockdown() or issecretvalue(nx)
      or issecretvalue(ny) then
    return false
  end
  local width, height = canvas:GetSize()
  local item = itemAt(nx * width, ny * height)
  if not (item and item.click) then
    return false
  end
  item.click()
  return true
end

local elapsed = 0
local function hover(map, delta)
  elapsed = elapsed + delta
  if elapsed < HOVER_SECONDS then
    return
  end
  elapsed = 0
  local nx, ny = map:GetNormalizedCursorPosition()
  local over = map:IsMouseOver() and nx and ny and not issecretvalue(nx) and not issecretvalue(ny)
  local width, height = canvas:GetSize()
  local x, y = over and nx * width or 0, over and ny * height or 0
  local fanned = MapFan.fanned
  if fanned then
    if fanned.scale ~= canvas:GetEffectiveScale() then
      finish()  -- zoomed: positions are stale
      return
    end
    local box = fanned.box
    local inside = over and x >= box[1] and x <= box[3] and y >= box[2] and y <= box[4]
    if not inside then
      if not fanned.closing then
        fanned.closing = true  -- glide back
        if GameTooltip:GetOwner() == frame then
          GameTooltip:Hide()
        end
      end
      return
    end
    fanned.closing = false  -- came back in while it was folding: open again
    local item = itemAt(x, y)
    if item then
      local tooltip = ns.Tooltips:Take(frame, "ANCHOR_CURSOR")  -- nil while Ctrl hides ours
      if tooltip then
        item.fill(tooltip)
      end
      return
    end
    if GameTooltip:GetOwner() == frame then
      GameTooltip:Hide()
    end
    return
  end
  if over then
    local group = cluster(x, y)
    if group then
      open(group)
    end
  end
end

local function create()
  local map = rawget(_G, "WorldMapFrame")
  if frame or not map then
    return
  end
  canvas = map:GetCanvas()
  frame = CreateFrame("Frame", nil, canvas)
  frame:SetAllPoints(canvas)
  frame:EnableMouse(false)
  frame:SetFrameLevel(BACKDROP_LEVEL)
  strip = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  strip:EnableMouse(false)
  strip:SetFrameLevel(BACKDROP_LEVEL + 1)
  strip:Hide()
  -- Lines and stand-ins on a frame above the strip: a child frame draws over its parent's textures, so
  -- on `frame` itself they went under the strip (review).
  overlay = CreateFrame("Frame", nil, frame)
  overlay:SetAllPoints(canvas)
  overlay:EnableMouse(false)
  overlay:SetFrameLevel(BACKDROP_LEVEL + 2)
  frame:SetScript("OnUpdate", function(_, delta)
    hover(map, delta)
    animate(delta)
  end)
  frame:SetScript("OnHide", finish)
  map:AddCanvasClickHandler(onCanvasClick, 1)
end

ns.Events:On("PLAYER_LOGIN", create)
ns.Events:On("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then
    create()
  end
end)
