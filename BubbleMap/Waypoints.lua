local ADDON_NAME, ns = ...

-- Waypoints: one of yours, and one per party member running BubbleMap who shared theirs. Placed in the
-- map window (MapWindow.lua): a click drops yours (only you see it), Shift+click drops it shared with
-- your group, a right-click on a waypoint clears it (yours: for everyone it was shared with; someone
-- else's: hidden for you until they place a new one). Yours clears itself when you get there.
-- Drawn in the map window and on the minimap, where one out of view sits at the map's edge.
--
-- Sharing: addon messages to the party or raid (C_ChatInfo.SendAddonMessage, prefix PREFIX), text:
--   "1:SET:<map>:<north>:<west>"  my shared waypoint is here (instance map, world yards)
--   "1:CLR"                       I have none
--   "1:REQ"                       send me yours (on joining a group, or logging in in one)
-- A send refused (throttled, or addon messages locked down: SendAddonMessageResult) stays pending and
-- is retried every RETRY seconds; only the latest state matters, so a newer one replaces it. Received
-- messages are never restricted (CHAT_MSG_ADDON isn't a lockdown event). Waypoints of people who left
-- the group go (GROUP_ROSTER_UPDATE).
--
-- Positions are what a click picked (never a secret value). Not tested with a second BubbleMap user
-- yet (2026-11-18): the message flow is written to the API docs only.

local PREFIX = "BubbleMap"
local VERSION = "1"
local ARRIVE_YARDS = 12
local RETRY = 2
local PIN_SIZE = 22
local REMOVE_RADIUS = 14      -- pixels: a right-click this near a waypoint clears it
local MINE_ATLAS, THEIRS_ATLAS = "Waypoint-MapPin-Tracked", "Waypoint-MapPin-Untracked"

local Waypoints = {
  mine = nil,     -- { map, north, west, shared }
  others = {},    -- [short name] = { map, north, west, name }
}
ns.Waypoints = Waypoints

local function say(text)
  print("|cffffd100BubbleMap|r: " .. text)
end

local function shortName(full)
  return Ambiguate(full, "none")
end

local function readable(v)
  return v ~= nil and not issecretvalue(v)
end

-- Comms -----------------------------------------------------------------------------------------------

local pending  -- the message waiting to go out (refused once already, or not in a group yet)
local retrying = false

local function channel()
  if IsInRaid() then
    return "RAID"
  elseif IsInGroup() then
    return "PARTY"
  end
end

local function flush()
  if not pending then
    return
  end
  local chat = channel()
  if not chat then
    pending = nil  -- no one to tell; joining a group sends the current state again
    return
  end
  -- apiguard: allow the arguments are our constant prefix, text we formatted from click positions and a constant channel: never secret
  local result = C_ChatInfo.SendAddonMessage(PREFIX, pending, chat)
  if result == Enum.SendAddonMessageResult.Success then
    pending = nil
  elseif not retrying then
    retrying = true
    C_Timer.After(RETRY, function()
      retrying = false
      flush()
    end)
  end
end

local function send(text)
  pending = VERSION .. ":" .. text
  flush()
end

local function sendState()
  local mine = Waypoints.mine
  if mine and mine.shared then
    send(("SET:%d:%.1f:%.1f"):format(mine.map, mine.north, mine.west))
  else
    send("CLR")
  end
end

local function zoneText(map, north, west)
  local uiMap = C_Map.GetMapPosFromWorldPos(map, CreateVector2D(north, west))
  local info = uiMap and C_Map.GetMapInfo(uiMap)
  return info and info.name or "somewhere"
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
  if prefix ~= PREFIX or not (readable(text) and readable(sender)) then
    return
  end
  local name = shortName(sender)
  -- apiguard: allow the result is checked with issecretvalue (readable) before it's compared
  local me = UnitName("player")
  if readable(me) and name == me then
    return
  end
  local version, command, rest = text:match("^(%d+):(%u+):?(.*)$")
  if version ~= VERSION then
    return  -- another version's format: ignored rather than misread
  end
  if command == "SET" then
    local map, north, west = rest:match("^(%-?%d+):(%-?[%d.]+):(%-?[%d.]+)$")
    map, north, west = tonumber(map), tonumber(north), tonumber(west)
    if map and north and west then
      local old = Waypoints.others[name]
      Waypoints.others[name] = { map = map, north = north, west = west, name = name }
      if not (old and old.map == map and math.abs(old.north - north) < 1 and math.abs(old.west - west) < 1) then
        say(("%s shared a waypoint in %s."):format(name, zoneText(map, north, west)))
      end
    end
  elseif command == "CLR" then
    Waypoints.others[name] = nil
  elseif command == "REQ" then
    if Waypoints.mine and Waypoints.mine.shared then
      sendState()
    end
  end
end)

local inGroup = false
local function rosterChanged()
  local now = IsInGroup()
  if now and not inGroup then
    -- Joined (or logged in in a group): ask for theirs, tell ours.
    send("REQ")
    if Waypoints.mine and Waypoints.mine.shared then
      C_Timer.After(1, sendState)  -- after the REQ, which a pending send would replace
    end
  end
  inGroup = now
  for name in pairs(Waypoints.others) do
    local stays = false
    if now then
      -- apiguard: allow the result is checked with issecretvalue (readable): a secret one keeps the waypoint
      local raidIndex = UnitInRaid(name)
      stays = UnitInParty(name) or not readable(raidIndex) or raidIndex ~= nil
    end
    if not stays then
      Waypoints.others[name] = nil
    end
  end
end
ns.On("GROUP_ROSTER_UPDATE", rosterChanged)

ns.On("PLAYER_LOGIN", function()
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  Waypoints.mine = ns.DB.waypoint  -- kept across sessions
  rosterChanged()
end)

-- Placing ---------------------------------------------------------------------------------------------

---Drop your waypoint at world (north, west) on instance map `map`; `shared` tells your group.
---@param map number
---@param north number
---@param west number
---@param shared boolean
function Waypoints:Set(map, north, west, shared)
  local wasShared = self.mine and self.mine.shared
  self.mine = { map = map, north = north, west = west, shared = shared }
  ns.DB.waypoint = self.mine
  if shared then
    if not IsInGroup() then
      say("waypoint set; not in a group, so it's yours only for now (it's shared when you join one).")
    end
    sendState()
  elseif wasShared then
    send("CLR")
  end
end

---One line for /bmap.
---@return string
function Waypoints:Describe()
  local mine = self.mine
  local names = {}
  for name in pairs(self.others) do
    names[#names + 1] = name
  end
  return ("waypoints: yours %s; from your group: %s; %s."):format(
    mine and ((mine.shared and "shared, in " or "in ") .. zoneText(mine.map, mine.north, mine.west)) or "none",
    #names > 0 and table.concat(names, ", ") or "none",
    pending and "a message waiting to send (throttled or locked down)" or "nothing waiting to send")
end

---Clear your waypoint (and tell your group, if it was shared).
function Waypoints:Clear()
  local wasShared = self.mine and self.mine.shared
  self.mine = nil
  ns.DB.waypoint = nil
  if wasShared then
    send("CLR")
  end
end

-- Every waypoint as { map, north, west, mine, name }.
local function all()
  local list = {}
  local mine = Waypoints.mine
  if mine then
    list[#list + 1] = { map = mine.map, north = mine.north, west = mine.west, mine = true, shared = mine.shared }
  end
  for name, w in pairs(Waypoints.others) do
    list[#list + 1] = { map = w.map, north = w.north, west = w.west, name = name }
  end
  return list
end

---Right-click at screen offset (dx, dy): clear the nearest waypoint within REMOVE_RADIUS pixels.
---@param project fun(map: number, north: number, west: number): number?, number?
---@param dx number
---@param dy number
function Waypoints:RemoveNear(project, dx, dy)
  local best, bestDistance
  for _, w in ipairs(all()) do
    local x, y = project(w.map, w.north, w.west)
    if x and y then
      -- From the pin's middle: it stands on the spot (drawn above it).
      local d = math.sqrt((x - dx) ^ 2 + (y + PIN_SIZE / 2 - dy) ^ 2)
      if d <= REMOVE_RADIUS and (not bestDistance or d < bestDistance) then
        best, bestDistance = w, d
      end
    end
  end
  if best and best.mine then
    self:Clear()
  elseif best then
    self.others[best.name] = nil  -- hidden for you; their next one shows again
  end
end

-- Arrival: yours clears within ARRIVE_YARDS.
local function checkArrival()
  local mine = Waypoints.mine
  if not mine then
    return
  end
  local north, west, _, map = UnitPosition("player")
  if readable(north) and readable(west) and map == mine.map
    and (north - mine.north) ^ 2 + (west - mine.west) ^ 2 <= ARRIVE_YARDS ^ 2 then
    Waypoints:Clear()
    say("waypoint reached.")
  end
end
C_Timer.NewTicker(0.5, checkArrival)

-- Drawing ---------------------------------------------------------------------------------------------

-- A pin pool per frame: { pin, label } per waypoint drawn.
local pools = setmetatable({}, { __mode = "k" })

local function classColor(name)
  -- apiguard: allow its classFilename is checked with issecretvalue (readable) before any use
  local _, class = UnitClass(name)
  return readable(class) and C_ClassColor.GetClassColor(class) or nil
end

local function pin(frame, i)
  local pool = pools[frame]
  if not pool then
    pool = {}
    pools[frame] = pool
  end
  local p = pool[i]
  if not p then
    p = {}
    p.icon = frame:CreateTexture(nil, "OVERLAY")
    p.icon:SetSize(PIN_SIZE, PIN_SIZE)
    p.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    p.label:SetPoint("TOP", p.icon, "BOTTOM", 0, 2)
    pool[i] = p
  end
  return p
end

local function hideFrom(frame, from)
  for i = from, #(pools[frame] or {}) do
    pools[frame][i].icon:Hide()
    pools[frame][i].label:Hide()
  end
end

-- Draw every waypoint into `frame`, at project(map, north, west) (nil: not on this view). `edge`:
-- half-size of the view; one out of it is drawn at its edge, faded (the minimap), else skipped.
local function draw(frame, project, edgeW, edgeH)
  local count = 0
  if project then
    local halfW, halfH = frame:GetWidth() / 2, frame:GetHeight() / 2
    for _, w in ipairs(all()) do
      local x, y = project(w.map, w.north, w.west)
      if x and y then
        local outside = math.abs(x) > halfW or math.abs(y) > halfH
        local alpha = 1
        if outside and edgeW then
          -- On the view's edge, toward it.
          local k = math.min((edgeW - PIN_SIZE / 2) / math.max(math.abs(x), 1),
            (edgeH - PIN_SIZE / 2) / math.max(math.abs(y), 1))
          x, y, alpha = x * k, y * k, 0.7
          outside = false
        end
        if not outside then
          count = count + 1
          local p = pin(frame, count)
          p.icon:SetAtlas(w.mine and MINE_ATLAS or THEIRS_ATLAS)
          p.icon:ClearAllPoints()
          p.icon:SetPoint("BOTTOM", frame, "CENTER", x, y)  -- the pin's point on the spot
          p.icon:SetAlpha(alpha)
          p.icon:Show()
          if w.name then
            local color = classColor(w.name)
            p.label:SetText(w.name)
            p.label:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
            p.label:SetAlpha(alpha)
            p.label:Show()
          elseif w.shared then
            p.label:SetText("shared")
            p.label:SetTextColor(0.8, 0.8, 0.8)
            p.label:SetAlpha(alpha)
            p.label:Show()
          else
            p.label:Hide()
          end
        end
      end
    end
  end
  hideFrom(frame, count + 1)
end

---The map window's waypoints, into `frame`, at `project` (MapWindow.Project); nil hides them.
---@param frame Frame
---@param project? fun(map: number, north: number, west: number): number?, number?
function Waypoints:DrawWindow(frame, project)
  draw(frame, project)
end

-- The minimap: relative to the player, turned as the terrain is (Terrain:Projection), over BubbleQuest's
-- quest layer and the group's dots.
table.insert(ns.Minimap.onActivate, function(outer)
  local layer = CreateFrame("Frame", nil, outer)
  layer:SetAllPoints()
  layer:SetFrameStrata("LOW")
  layer:EnableMouse(false)
  layer:SetScript("OnUpdate", function()
    local level = math.max(outer:GetFrameLevel(), Minimap:GetFrameLevel()) + 5
    if layer:GetFrameLevel() ~= level then
      layer:SetFrameLevel(level)
    end
    local pn, pw, _, pmap = UnitPosition("player")
    local s, turn = ns.Terrain:Projection()
    if not (readable(pn) and readable(pw) and s) then
      draw(layer, nil)
      return
    end
    local cos, sin = math.cos(turn), math.sin(turn)
    draw(layer, function(map, north, west)
      if map ~= pmap then
        return nil
      end
      local x, y = (pw - west) * s, (north - pn) * s
      return x * cos + y * sin, -x * sin + y * cos
    end, layer:GetWidth() / 2, layer:GetHeight() / 2)
  end)
end)
