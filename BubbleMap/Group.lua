local ADDON_NAME, ns = ...

-- Group members on our maps. With Blizzard's minimap hidden (Zoom.lua, our map) its party and raid dots
-- go with it, so we draw them: a dot per member in their class colour, where UnitPosition says they are.
-- Hover a dot (or a few overlapping) for the names. Two layers: the minimap's (only in our map: in
-- gather mode Blizzard draws them), at the terrain's scale and turn (Terrain:Projection), and the map
-- window's (MapWindow.lua), at its own. Each layer takes a projection, so the dots line up with the
-- ground at any zoom.
--
-- UnitPosition (UnitDocumentation.lua:2714): world yards (north, west) and the instance map; nothing in
-- instances, so no dots there (Blizzard's minimap shows there anyway). A member on another map, or one
-- whose position reads as a secret value, is skipped. Class: UnitClass's classFilename (not a secret,
-- unlike its localized name) into C_ClassColor.GetClassColor.

local DOT_SIZE = 9
local RING = { 0, 0, 0, 0.9 }      -- a dark ring, so the dot reads on any ground
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"  -- a white disc (its alpha is the circle)
local HOVER_RADIUS = 7             -- pixels
local UPDATE_SECONDS = 0.05

local Group = {}
ns.Group = Group

local Layer = {}
Layer.__index = Layer

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

local function classColor(unit)
  -- apiguard: allow its classFilename is checked with issecretvalue (readable) before any use
  local _, class = UnitClass(unit)
  return readable(class) and C_ClassColor.GetClassColor(class) or nil
end

---A layer of group dots over `frame` (which should clip its children); its frame takes no mouse.
---@param frame Frame
---@return table
function Group.NewLayer(frame)
  local layer = CreateFrame("Frame", nil, frame)
  layer:SetAllPoints()
  layer:EnableMouse(false)
  return setmetatable({ frame = layer, dots = {}, shown = {}, hovering = false }, Layer)
end

function Layer:Dot(i)
  local d = self.dots[i]
  if not d then
    local frame = self.frame
    d = {}
    -- Round: a white disc texture, tinted. Not a mask per dot (review: the minimap's dot drew as a square
    -- now and then; masks on textures in a clipping frame have failed before, see questmarker-map.md).
    d.ring = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    d.ring:SetSize(DOT_SIZE + 3, DOT_SIZE + 3)
    d.ring:SetTexture(DISC)
    d.ring:SetVertexColor(RING[1], RING[2], RING[3], RING[4])
    d.fill = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    d.fill:SetSize(DOT_SIZE, DOT_SIZE)
    d.fill:SetPoint("CENTER", d.ring)
    d.fill:SetTexture(DISC)
    self.dots[i] = d
  end
  return d
end

function Layer:HideFrom(from)
  for i = from, #self.dots do
    self.dots[i].ring:Hide()
    self.dots[i].fill:Hide()
  end
end

---Draw the members on instance map `map`, each where `project(north, west)` puts it: pixels right and
---up of the frame's centre. Nothing when `project` is nil. Then the hover, unless `noHover` (another
---layer's tooltip is up).
---@param map number?
---@param project? fun(north: number, west: number): number, number
---@param noHover boolean?
function Layer:Draw(map, project, noHover)
  wipe(self.shown)
  if not (map and project) then
    self:HideFrom(1)
    self:Hover(true)
    return
  end
  local frame = self.frame
  local halfW, halfH = frame:GetWidth() / 2, frame:GetHeight() / 2
  local count = 0
  for _, unit in ipairs(units()) do
    local un, uw, _, umap = UnitPosition(unit)
    if readable(un) and readable(uw) and umap == map then
      local x, y = project(un, uw)
      if math.abs(x) <= halfW and math.abs(y) <= halfH then
        count = count + 1
        local d = self:Dot(count)
        local color = classColor(unit)
        if color then
          d.fill:SetVertexColor(color.r, color.g, color.b, 1)
        else
          d.fill:SetVertexColor(0.8, 0.8, 0.8, 1)
        end
        d.ring:ClearAllPoints()
        d.ring:SetPoint("CENTER", frame, "CENTER", x, y)
        d.ring:Show()
        d.fill:Show()
        self.shown[#self.shown + 1] = { x = x, y = y, unit = unit }
      end
    end
  end
  self:HideFrom(count + 1)
  self:Hover(noHover)
end

-- Hover: the names of the members under the cursor (the dots take no mouse; worked out from the cursor,
-- as BubbleQuest's areas are).
function Layer:Hover(noHover)
  local frame = self.frame
  local over = {}
  if not noHover and #self.shown > 0 and frame:IsVisible() and frame:IsMouseOver() then
    local cx, cy = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local mx, my = frame:GetCenter()
    local x, y = cx / scale - mx, cy / scale - my
    for _, p in ipairs(self.shown) do
      if (p.x - x) ^ 2 + (p.y - y) ^ 2 <= HOVER_RADIUS ^ 2 then
        over[#over + 1] = p.unit
      end
    end
  end
  if #over == 0 then
    if self.hovering then
      self.hovering = false
      GameTooltip:Hide()
    end
    return
  end
  self.hovering = true
  GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
  for _, unit in ipairs(over) do
    -- apiguard: allow the name is checked with issecretvalue (readable) before it's shown
    local name = UnitName(unit)
    local color = classColor(unit)
    if readable(name) then
      GameTooltip:AddLine(name, color and color.r or 1, color and color.g or 1, color and color.b or 1)
    end
  end
  GameTooltip:Show()
end

---Whether the cursor is over one of this layer's dots (its tooltip is up).
---@return boolean
function Layer:IsHovering()
  return self.hovering
end

-- The minimap's layer: relative to the player, turned as the terrain and BubbleQuest's areas are.
table.insert(ns.Minimap.onActivate, function(outer)
  local layer = Group.NewLayer(outer)
  layer.frame:SetFrameStrata("LOW")  -- over our terrain (BACKGROUND), under the bar and arrow (Around.lua)
  layer.frame:SetClipsChildren(true)
  local elapsed = 0
  layer.frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < UPDATE_SECONDS then
      return
    end
    elapsed = 0
    -- Over BubbleQuest's quest layer, which puts itself 2 over the higher of our frame and the minimap
    -- (review: its areas, 0.6 alpha, covered the dots: "not showing consistently").
    local level = math.max(outer:GetFrameLevel(), Minimap:GetFrameLevel()) + 4
    if layer.frame:GetFrameLevel() ~= level then
      layer.frame:SetFrameLevel(level)
    end
    if not ns.Zoom.own then
      layer:Draw(nil, nil)
      return
    end
    local pn, pw, _, pmap = UnitPosition("player")
    local s, turn = ns.Terrain:Projection()
    if not (readable(pn) and readable(pw) and s) then
      layer:Draw(nil, nil)
      return
    end
    local cos, sin = math.cos(turn), math.sin(turn)
    layer:Draw(pmap, function(north, west)
      -- East right, north up; turned.
      local x, y = (pw - west) * s, (north - pn) * s
      return x * cos + y * sin, -x * sin + y * cos
    end)
  end)
end)
