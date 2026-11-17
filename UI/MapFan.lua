local ADDON_NAME, ns = ...

-- Fanning out overlapping icons on the world map (review: a turn-in "?" sat under a trainer's icon in
-- Goldshire). When the cursor rests on two or more of our icons that overlap (quest givers' "!",
-- turn-in "?", town services), they glide into a row just above that spot (below it near the map's
-- top edge), on a soft dark strip, ordered left to right by where they are, each with a thin line
-- down to its real place and its own tooltip. Leaving the area they glide back. (The first version
-- was a ring that opened at once: "kinda ugly", review asked for a row and a smooth move.)
--
-- The icon layers (UI/MapAvailable.lua, UI/MapServices.lua, UI/MapAreas.lua's turn-ins) each keep a
-- list of their icons (fanItems: texture, x, y on the canvas, base size, fill(tooltip)) and register
-- it here. While a row is open this file owns the tooltip; the layers' own hovers stand aside
-- (MapFan.fanned), and a redraw or zoom folds it back at once (Collapse), as textures move or go.

local HOVER_SECONDS = 0.05
local ANIMATE_SECONDS = 0.15
local ROW_SPACING = 1.35      -- icon sizes between icons in the row
local ROW_LIFT = 1.9          -- icon sizes from the cluster's top to the row
local STRIP_PAD = 0.35        -- icon sizes of strip around the row
local STRIP_ALPHA = 0.6
local LINE_ALPHA = 0.5
local KEEP_PAD = 0.6          -- icon sizes of margin around what's open before it folds back
-- The strip and lines go under the icons (their layers are 2006-2008): a frame of their own at 2004,
-- below the quest areas too. The hover runs on a frame of no particular level.
local BACKDROP_LEVEL = 2004

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
local lines = {}

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
    place(item.texture, item.curX, item.curY)
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
      place(item.texture, item.x, item.y)
    end
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

-- Every icon of every layer under (x, y), and then everything overlapping the first of them.
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
  local group = {}
  for _, item in ipairs(all) do
    local reach = (first.base + item.base) * factor / 2 * 0.9
    if (item.x - first.x) ^ 2 + (item.y - first.y) ^ 2 < reach * reach then
      group[#group + 1] = item
    end
  end
  return #group >= 2 and group or nil
end

local function open(group)
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
      line = frame:CreateLine(nil, "ARTWORK")
      line:SetColorTexture(1, 1, 1, LINE_ALPHA)
      lines[i] = line
    end
    line:SetThickness(1.2 * scale)
  end
  local pad = size * STRIP_PAD
  strip:ClearAllPoints()
  strip:SetPoint("TOPLEFT", canvas, "TOPLEFT", cx - half - size / 2 - pad, -(rowY - size / 2 - pad))
  strip:SetSize(2 * half + size + 2 * pad, size + 2 * pad)
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
    local factor = sizeFactor()
    for _, item in ipairs(fanned.items) do
      local r = item.base * factor / 2
      if item.curX and (x - item.curX) ^ 2 + (y - item.curY) ^ 2 <= r * r then
        local tooltip = ns.Tooltips:Take(frame, "ANCHOR_CURSOR")  -- nil while Ctrl hides ours
        if tooltip then
          item.fill(tooltip)
        end
        return
      end
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
  strip = frame:CreateTexture(nil, "BACKGROUND")
  strip:SetColorTexture(0.05, 0.04, 0.03, STRIP_ALPHA)
  strip:Hide()
  frame:SetScript("OnUpdate", function(_, delta)
    hover(map, delta)
    animate(delta)
  end)
  frame:SetScript("OnHide", finish)
end

ns.Events:On("PLAYER_LOGIN", create)
ns.Events:On("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then
    create()
  end
end)
