local ADDON_NAME, ns = ...

-- Fanning out overlapping icons on the world map (review: a turn-in "?" sat under a trainer's icon in
-- Goldshire). When the cursor rests on two or more of our icons that overlap (quest givers' "!",
-- turn-in "?", town services), they spread into a small ring around that spot, each with a thin line
-- back to where it really is, each hoverable for its own tooltip. Leaving the ring folds them back.
--
-- The icon layers (UI/MapAvailable.lua, UI/MapServices.lua, UI/MapAreas.lua's turn-ins) each keep a
-- list of their icons (fanItems: texture, x, y on the canvas, base size, fill(tooltip)) and register
-- it here. While a ring is open this file owns the tooltip; the layers' own hovers stand aside
-- (MapFan.fanned), and any redraw or zoom folds the ring first (Collapse), as textures move or go.

local HOVER_SECONDS = 0.05
local RING_GAP = 1.15         -- ring radius in icon sizes, at least (more icons, a wider ring)
local LINE_ALPHA = 0.55
local FRAME_LEVEL = 2009      -- above every layer of ours (lines over icons), under Questie's (2015+)

local MapFan = {
  lists = {},       -- registered fanItems lists, by layer name
  fanned = nil,     -- the open ring: { items, cx, cy, radius }
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
local lines = {}

local function iconSize(base)
  return base * ns.MapAreas.iconScale() * UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
end

local function place(texture, x, y)
  texture:ClearAllPoints()
  texture:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
end

---Fold the ring back (icons to their places); call before a layer redraws or resizes its icons.
function MapFan:Collapse()
  local fanned = self.fanned
  if not fanned then
    return
  end
  self.fanned = nil
  for _, item in ipairs(fanned.items) do
    place(item.texture, item.x, item.y)
  end
  for _, line in ipairs(lines) do
    line:Hide()
  end
  if frame and GameTooltip:GetOwner() == frame then
    GameTooltip:Hide()
  end
end

-- Every icon of every layer under (x, y), and then everything overlapping the first of them.
local function cluster(x, y)
  -- Icon sizes on the canvas: the scales read once per check (this runs 20 times a second).
  local factor = iconSize(1)
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
  local cx, cy, size = 0, 0, 0
  for _, item in ipairs(group) do
    cx, cy = cx + item.x, cy + item.y
    size = math.max(size, iconSize(item.base))
  end
  cx, cy = cx / #group, cy / #group
  -- A ring wide enough that neighbours don't touch: circumference about 1.3 icons per icon.
  local radius = math.max(size * RING_GAP, size * #group * 1.3 / (2 * math.pi))
  local scale = UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
  for i, item in ipairs(group) do
    local angle = -math.pi / 2 + 2 * math.pi * (i - 1) / #group
    item.fanX, item.fanY = cx + radius * math.cos(angle), cy + radius * math.sin(angle)
    place(item.texture, item.fanX, item.fanY)
    local line = lines[i]
    if not line then
      line = frame:CreateLine(nil, "OVERLAY")
      line:SetColorTexture(1, 1, 1, LINE_ALPHA)
      lines[i] = line
    end
    line:SetThickness(1.5 * scale)
    line:SetStartPoint("TOPLEFT", canvas, item.x, -item.y)
    line:SetEndPoint("TOPLEFT", canvas, item.fanX, -item.fanY)
    line:Show()
  end
  MapFan.fanned = { items = group, cx = cx, cy = cy, radius = radius, size = size, scale = canvas:GetEffectiveScale() }
end

local elapsed = 0
local function update(map, delta)
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
    -- Zoomed, or the cursor left the ring: fold back.
    if not over or fanned.scale ~= canvas:GetEffectiveScale()
        or (x - fanned.cx) ^ 2 + (y - fanned.cy) ^ 2 > (fanned.radius + fanned.size) ^ 2 then
      MapFan:Collapse()
      return
    end
    for _, item in ipairs(fanned.items) do
      local r = iconSize(item.base) / 2
      if (x - item.fanX) ^ 2 + (y - item.fanY) ^ 2 <= r * r then
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
  frame:SetFrameLevel(FRAME_LEVEL)
  frame:SetScript("OnUpdate", function(_, delta) update(map, delta) end)
  frame:SetScript("OnHide", function() MapFan:Collapse() end)
end

ns.Events:On("PLAYER_LOGIN", create)
ns.Events:On("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then
    create()
  end
end)
