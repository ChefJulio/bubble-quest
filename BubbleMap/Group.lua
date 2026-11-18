local ADDON_NAME, ns = ...

-- Group members on our map. With Blizzard's minimap hidden (Zoom.lua, our map) its party and raid dots
-- go with it, so we draw them: a dot per member in their class colour, where UnitPosition says they are,
-- at the terrain's scale and turn (Terrain:Projection), so they line up with the ground at any zoom.
-- Hover a dot (or a few overlapping) for the names. Only in our map: in gather mode Blizzard draws them.
--
-- UnitPosition (UnitDocumentation.lua:2714): world yards (north, west) and the instance map; nothing in
-- instances, so no dots there (Blizzard's minimap shows there anyway). A member on another map, or one
-- whose position reads as a secret value, is skipped. Class: UnitClass's classFilename (not a secret,
-- unlike its localized name) into C_ClassColor.GetClassColor.

local DOT_SIZE = 9
local RING = { 0, 0, 0, 0.9 }      -- a dark ring, so the dot reads on any ground
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HOVER_RADIUS = 7             -- pixels
local UPDATE_SECONDS = 0.05

local Group = {}
ns.Group = Group

local dots = {}
local shown = {}  -- this frame's dots: { x, y, unit }

local function readable(v)
  return v ~= nil and not issecretvalue(v)
end

-- In a raid the player is one of raidN too: their dot sits under our arrow, so it isn't sorted out
-- (UnitIsUnit can return a secret value under the unit comparison restriction).
local function units()
  local list = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      list[#list + 1] = "raid" .. i
    end
  else
    for i = 1, GetNumSubgroupMembers() do
      list[#list + 1] = "party" .. i
    end
  end
  return list
end

local function dot(layer, i)
  local d = dots[i]
  if not d then
    d = {}
    d.ring = layer:CreateTexture(nil, "ARTWORK", nil, 1)
    d.ring:SetSize(DOT_SIZE + 2, DOT_SIZE + 2)
    d.ring:SetColorTexture(RING[1], RING[2], RING[3], RING[4])
    d.fill = layer:CreateTexture(nil, "ARTWORK", nil, 2)
    d.fill:SetSize(DOT_SIZE, DOT_SIZE)
    d.fill:SetPoint("CENTER", d.ring)
    -- Round: a mask per dot, the size of its ring, where it sits.
    d.mask = layer:CreateMaskTexture()
    d.mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.mask:SetAllPoints(d.ring)
    d.ring:AddMaskTexture(d.mask)
    d.fill:AddMaskTexture(d.mask)
    dots[i] = d
  end
  return d
end

local function hide(from)
  for i = from, #dots do
    dots[i].ring:Hide()
    dots[i].fill:Hide()
  end
end

local function draw(layer)
  wipe(shown)
  if not ns.Zoom.own then
    hide(1)
    return
  end
  local pn, pw, _, pmap = UnitPosition("player")
  local s, turn = ns.Terrain:Projection()
  if not (readable(pn) and readable(pw) and s) then
    hide(1)
    return
  end
  local cos, sin = math.cos(turn), math.sin(turn)
  local halfW, halfH = layer:GetWidth() / 2, layer:GetHeight() / 2
  local count = 0
  for _, unit in ipairs(units()) do
    local un, uw, _, umap = UnitPosition(unit)
    if readable(un) and readable(uw) and umap == pmap then
      -- East right, north up; turned as the terrain and BubbleQuest's areas are.
      local x, y = (pw - uw) * s, (un - pn) * s
      x, y = x * cos + y * sin, -x * sin + y * cos
      if math.abs(x) <= halfW and math.abs(y) <= halfH then
        count = count + 1
        local d = dot(layer, count)
        -- apiguard: allow its classFilename is checked with issecretvalue (readable) before any use
        local _, class = UnitClass(unit)
        local color = readable(class) and C_ClassColor.GetClassColor(class)
        if color then
          d.fill:SetColorTexture(color.r, color.g, color.b, 1)
        else
          d.fill:SetColorTexture(0.8, 0.8, 0.8, 1)
        end
        d.ring:ClearAllPoints()
        d.ring:SetPoint("CENTER", layer, "CENTER", x, y)
        d.ring:Show()
        d.fill:Show()
        shown[#shown + 1] = { x = x, y = y, unit = unit }
      end
    end
  end
  hide(count + 1)
end

-- Hover: the names of the members under the cursor (the dots take no mouse; worked out from the cursor,
-- as BubbleQuest's areas are).
local hovering = false
local function hover(layer)
  local over = {}
  if #shown > 0 and layer:IsMouseOver() then
    local cx, cy = GetCursorPosition()
    local scale = layer:GetEffectiveScale()
    local mx, my = layer:GetCenter()
    local x, y = cx / scale - mx, cy / scale - my
    for _, p in ipairs(shown) do
      if (p.x - x) ^ 2 + (p.y - y) ^ 2 <= HOVER_RADIUS ^ 2 then
        over[#over + 1] = p.unit
      end
    end
  end
  if #over == 0 then
    if hovering then
      hovering = false
      GameTooltip:Hide()
    end
    return
  end
  hovering = true
  GameTooltip:SetOwner(layer, "ANCHOR_CURSOR")
  for _, unit in ipairs(over) do
    -- apiguard: allow the name is checked with issecretvalue (readable) before it's shown
    local name = UnitName(unit)
    -- apiguard: allow its classFilename is checked with issecretvalue (readable) before any use
    local _, class = UnitClass(unit)
    local color = readable(class) and C_ClassColor.GetClassColor(class)
    if readable(name) then
      GameTooltip:AddLine(name, color and color.r or 1, color and color.g or 1, color and color.b or 1)
    end
  end
  GameTooltip:Show()
end

table.insert(ns.Minimap.onActivate, function(outer)
  local layer = CreateFrame("Frame", nil, outer)
  layer:SetAllPoints()
  layer:SetFrameStrata("LOW")  -- over our terrain (BACKGROUND), under the bar and arrow (Around.lua)
  layer:SetClipsChildren(true)
  layer:EnableMouse(false)
  local elapsed = 0
  layer:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < UPDATE_SECONDS then
      return
    end
    elapsed = 0
    draw(layer)
    hover(layer)
  end)
end)
