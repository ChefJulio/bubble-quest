local ADDON_NAME, ns = ...

-- A view of the terrain tiles (Data/Tiles.lua) centred on any world point at any scale: the map window
-- (MapWindow.lua) draws with it. Same grid as Terrain.lua: 64 x 64 tiles of 533.33 yards per continent,
-- col = 32 - west / T, row = 32 - north / T (UnitPosition's north and west), the tile's minimap texture
-- by FileDataID.
--
-- Textures are kept per tile while in view, and up to KEEP more after they leave it (hidden, image
-- loaded: panning back costs nothing); beyond that the longest unseen is reused for a new tile. So
-- SetTexture runs only for tiles that come into view.
--
-- REMAINING WORK: Terrain.lua (the minimap's padding and own map) has its own slot-grid version of this,
-- written first and tested in game; it should move onto TileView (one tile drawer), its rotation added
-- here. Recorded in docs/design/terrain-map.md.

local TILE_YARDS = 1600 / 3
local GRID = 64
local KEEP = 160  -- off-screen tiles kept loaded

local TileView = {}
TileView.__index = TileView
ns.TileView = TileView

---A view drawing into `frame` (which should clip its children).
---@param frame Frame
---@return table
function TileView.New(frame)
  return setmetatable({ frame = frame, live = {}, parked = {}, seen = {}, order = 0, loaded = 0, failed = 0 },
    TileView)
end

function TileView:Texture(key, fileID)
  local t = self.live[key] or self.parked[key]
  if t then
    self.parked[key] = nil
  else
    -- A new tile: a parked texture's slot (the longest unseen) once KEEP are parked, else a new one.
    local oldestKey, oldest
    local count = 0
    for k, p in pairs(self.parked) do
      count = count + 1
      if not oldest or self.seen[p] < self.seen[oldest] then
        oldestKey, oldest = k, p
      end
    end
    if oldest and count >= KEEP then
      self.parked[oldestKey] = nil
      t = oldest
    else
      t = self.frame:CreateTexture(nil, "ARTWORK")
      t:SetSnapToPixelGrid(false)
      t:SetTexelSnappingBias(0)
    end
    self.loaded = self.loaded + 1
    if not t:SetTexture(fileID) then
      self.failed = self.failed + 1
    end
  end
  self.live[key] = t
  return t
end

---Draw the tiles around world (north, west) on continent `mapID`, `ppy` pixels per yard, the point at
---the frame's centre. Tiles outside the frame go to the parked set.
---@param north number
---@param west number
---@param mapID number
---@param ppy number
function TileView:Draw(north, west, mapID, ppy)
  self.order = self.order + 1
  local tiles = ns.Tiles.maps[mapID]
  local wanted = {}
  if tiles then
    local w, h = self.frame:GetWidth(), self.frame:GetHeight()
    local tp = TILE_YARDS * ppy
    local colF, rowF = 32 - west / TILE_YARDS, 32 - north / TILE_YARDS
    local c0, c1 = math.floor(colF - w / 2 / tp), math.floor(colF + w / 2 / tp)
    local r0, r1 = math.floor(rowF - h / 2 / tp), math.floor(rowF + h / 2 / tp)
    for c = math.max(0, c0), math.min(GRID - 1, c1) do
      for r = math.max(0, r0), math.min(GRID - 1, r1) do
        local fileID = tiles[c * GRID + r]
        if fileID then
          local key = mapID * 4096 + c * GRID + r
          wanted[key] = true
          local t = self:Texture(key, fileID)
          self.seen[t] = self.order
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", self.frame, "CENTER", (c - colF) * tp, (rowF - r) * tp)
          t:SetSize(tp, tp)
          t:Show()
        end
      end
    end
  end
  for key, t in pairs(self.live) do
    if not wanted[key] then
      self.live[key] = nil
      t:Hide()
      self.parked[key] = t
    end
  end
end
