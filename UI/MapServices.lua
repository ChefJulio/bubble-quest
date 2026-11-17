local ADDON_NAME, ns = ...

-- Town services on the world map (docs/design/town-services.md): flight masters, innkeepers,
-- trainers, mailboxes... each toggled from the map button's menu (UI/MapButton.lua), all off by default.
--
-- Found once, in the background, the first time any is switched on: QuestieDB's NPC flags (as Questie's
-- Townsfolk.lua), NPC subtitles for trainers ("Warrior Trainer", "Expert Leatherworker", "Weapon
-- Master": the in-game title, so every trainer in the data counts, no hand-kept lists), forever-db
-- objects named Mailbox. Friendly NPCs only, except spirit healers.
--
-- World map only (the minimap has Blizzard's own tracking for these). Same approach as the other
-- layers: our own mouse-disabled frame on the canvas, hover from the cursor; an available-quest "!"
-- under the cursor wins (UI/MapAvailable.lua), and the quest areas yield to both.

local ICON_SIZE = 14          -- pixels at 100% (setting map.iconSize)
local MERGE_PIXELS = 10
local FRAME_LEVEL = 2006      -- above the areas (2005), under quest givers' "!" (2007) and turn-ins (2008)
local HOVER_SECONDS = 0.05
local BUILD_PER_FRAME = 400
local TRACKING = "Interface\\Minimap\\tracking\\"

-- The services, in menu order. flag: a QuestieDB npcFlags name; or a match on the NPC's subtitle.
local SERVICES = {
  { key = "flight", label = "Flight master", icon = TRACKING .. "flightmaster", flag = "FLIGHT_MASTER" },
  { key = "inn", label = "Innkeeper", icon = TRACKING .. "innkeeper", flag = "INNKEEPER" },
  { key = "bank", label = "Banker", icon = TRACKING .. "banker", flag = "BANKER" },
  { key = "auction", label = "Auctioneer", icon = TRACKING .. "auctioneer", flag = "AUCTIONEER" },
  { key = "repair", label = "Repair", icon = TRACKING .. "repair", flag = "REPAIR" },
  { key = "mailbox", label = "Mailbox", icon = TRACKING .. "mailbox" },
  { key = "weapon", label = "Weapon master", icon = TRACKING .. "class" },
  { key = "stable", label = "Stable master", icon = TRACKING .. "stablemaster", flag = "STABLEMASTER" },
  { key = "battle", label = "Battlemaster", icon = TRACKING .. "battlemaster", flag = "BATTLEMASTER" },
  { key = "spirit", label = "Spirit healer", icon = "Interface\\RaidFrame\\Raid-Icon-Rez", flag = "SPIRIT_HEALER",
    anyFaction = true },
}

-- Professions: a trainer's subtitle names the profession or its practitioner ("Cooking Trainer",
-- "Expert Leatherworker"), matched in English (recorded in the design doc); the third value is its
-- skill line ID, to know which ones you have in any language.
local PROFESSIONS = {
  { "Alchemy", "Alchemist", 171 }, { "Blacksmithing", "Blacksmith", 164 }, { "Cooking", "Cook", 185 },
  { "Enchanting", "Enchanter", 333 }, { "Engineering", "Engineer", 202 }, { "First Aid", "Physician", 129 },
  { "Fishing", "Fisherman", 356 }, { "Herbalism", "Herbalist", 182 }, { "Leatherworking", "Leatherworker", 165 },
  { "Mining", "Miner", 186 }, { "Skinning", "Skinner", 393 }, { "Tailoring", "Tailor", 197 },
}

-- Classes, by their localised names (C_CreatureInfo.GetClassInfo): a class trainer's subtitle is
-- "<class> Trainer". A list like the professions (review: a priest can look up warrior trainers for a
-- friend); your own class is switched on the first time it's seen.
local classes
local function classList()
  if not classes then
    classes = {}
    for id = 1, 20 do
      local info = C_CreatureInfo.GetClassInfo(id)
      if info and info.className then
        classes[#classes + 1] = info.className
      end
    end
    table.sort(classes)
  end
  return classes
end

local MapServices = {
  lists = nil,      -- [service key | "trainer:" .. profession] = { { kind, id, name, title } }, once built
  building = false,
  hits = {},
  icons = {},
  fanItems = {},    -- the icons for fanning out (UI/MapFan.lua)
  hovering = false,
}
ns.MapServices = MapServices
MapServices.SERVICES = SERVICES
MapServices.PROFESSIONS = PROFESSIONS

---The classes for the menu: those with trainers in the data once it's built, else every class.
---@return string[]
function MapServices:Classes()
  if not self.lists then
    return classList()
  end
  local out = {}
  for _, name in ipairs(classList()) do
    if self.lists["class:" .. name] then
      out[#out + 1] = name
    end
  end
  return out
end

-- Where a key's on/off lives: services in the profile (map.services), profession trainers per
-- character (char.professionTrainers, by profession name). Off is stored as false, not removed, so a
-- default never comes back after you turned it off.
local function storeFor(key)
  local profession = key:match("^trainer:(.+)$")
  if profession then
    return ns.DB.char.professionTrainers, profession
  end
  local class = key:match("^class:(.+)$")
  if class then
    return ns.DB.char.classTrainers, class
  end
  return ns.DB.profile.map.services, key
end

---Is this service (or "trainer:<profession>") switched on?
function MapServices:IsOn(key)
  if not (ns.DB.profile and ns.DB.char) then
    return false
  end
  local store, name = storeFor(key)
  return store[name] == true
end

local function anyOn()
  for _, on in pairs(ns.DB.profile.map.services) do
    if on then
      return true
    end
  end
  for _, store in ipairs({ ns.DB.char.professionTrainers, ns.DB.char.classTrainers }) do
    for _, on in pairs(store) do
      if on then
        return true
      end
    end
  end
  return false
end

function MapServices:Toggle(key)
  local store, name = storeFor(key)
  store[name] = not store[name]
  self:MarkDirty()
  if store[name] then
    self:Build()
  end
end

-- Professions you have switch their trainers on, the first time each is seen (at login, or when you
-- learn one: SKILL_LINES_CHANGED). Turned off later, it stays off: only a never-seen one is switched.
local function adoptProfessions()
  local skillInfo = rawget(_G, "C_SkillInfo")  -- SkillInfoDocumentation.lua; not in the type stubs
  if not (skillInfo and skillInfo.GetNumSkillLines and ns.DB.char) then
    return
  end
  local known = {}
  for i = 1, skillInfo.GetNumSkillLines() do
    local line = skillInfo.GetSkillLineInfo(i)
    if line and line.skillID then
      known[line.skillID] = true
    end
  end
  local trainers, changed = ns.DB.char.professionTrainers, false
  for _, p in ipairs(PROFESSIONS) do
    if known[p[3]] and trainers[p[1]] == nil then
      trainers[p[1]] = true
      changed = true
    end
  end
  -- Your own class's trainers, the same way.
  -- apiguard: allow our own character ("player") is never identity-restricted; a secret name is skipped
  local className = UnitClass("player")
  if className and not issecretvalue(className) and ns.DB.char.classTrainers[className] == nil then
    ns.DB.char.classTrainers[className] = true
    changed = true
  end
  if changed then
    MapServices:MarkDirty()
    MapServices:Build()
  end
end

-- The index ----------------------------------------------------------------------------------------

local function hasFlag(flags, flag)
  return flags and flag and flag > 0 and (flags % (2 * flag)) >= flag
end

local function build()
  local lists = {}
  local function add(key, entry)
    lists[key] = lists[key] or {}
    table.insert(lists[key], entry)
  end
  local lib = ns.QuestieData:Installed() and ns.QuestieData.Library()
  if lib and lib.Npc then
    local flags = lib.Enum and lib.Enum.npcFlags or {}
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local classNames = classList()
    local n = 0
    for _, id in ipairs(lib.Npc.GetAllIds()) do
      local ok, v = pcall(lib.Npc.GetAll, id, { "npcFlags", "subName", "friendlyToFaction", "name" })
      if ok and v then
        local npcFlags, title, friendly, name = v[1], v[2], v[3], v[4]
        local mine = friendly == nil or friendly == "AH" or friendly == faction
        local entry = { kind = "npc", id = id, name = name, title = title }
        for _, s in ipairs(SERVICES) do
          if s.flag and hasFlag(npcFlags, flags[s.flag]) and (mine or s.anyFaction) then
            add(s.key, entry)
          end
        end
        if mine and type(title) == "string" and hasFlag(npcFlags, flags.TRAINER) then
          local matched = false
          if title == "Weapon Master" then
            add("weapon", entry)
            matched = true
          end
          for _, class in ipairs(classNames) do
            if not matched and title:find(class, 1, true) then
              add("class:" .. class, entry)
              matched = true
            end
          end
          for _, p in ipairs(PROFESSIONS) do
            if not matched and (title:find(p[1], 1, true) or title:find(p[2], 1, true)) then
              add("trainer:" .. p[1], entry)
              matched = true
            end
          end
        end
      end
      n = n + 1
      if n % BUILD_PER_FRAME == 0 then
        coroutine.yield()
      end
    end
  end
  -- Mailboxes: forever-db objects by name (QuestieDB lists them only through Questie's own module).
  local n = 0
  for _, id in ipairs(ns.ForeverData:ObjectIds()) do
    if ns.ForeverData:Name("object", id) == "Mailbox" then
      add("mailbox", { kind = "object", id = id, name = "Mailbox" })
    end
    n = n + 1
    if n % (BUILD_PER_FRAME * 4) == 0 then
      coroutine.yield()
    end
  end
  MapServices.lists = lists
  MapServices.building = false
  MapServices:MarkDirty()
end

function MapServices:Build()
  if self.building or self.lists then
    return
  end
  self.building = true
  local co = coroutine.create(build)
  local ticker
  ticker = C_Timer.NewTicker(0, function()
    local ok, err = coroutine.resume(co)
    if not ok then
      ticker:Cancel()
      self.building = false
      geterrorhandler()(err)
    elseif coroutine.status(co) == "dead" then
      ticker:Cancel()
    end
  end)
end

local function pointsOf(entry)
  if entry.kind == "object" then
    return ns.ForeverData:EntityPoints("object", entry.id)
  end
  return ns.QuestieData:EntityPoints("npc", entry.id)
end

-- Icon of a key: a service's, or a profession trainer's.
local function iconOf(key)
  for _, s in ipairs(SERVICES) do
    if s.key == key then
      return s.icon
    end
  end
  return key:find("^class:") and TRACKING .. "class" or TRACKING .. "profession"
end

-- World map ---------------------------------------------------------------------------------------

local layer, iconPool, vector

local function iconSize(canvas)
  return ICON_SIZE * ns.MapAreas.iconScale() * UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
end

function MapServices:Redraw()
  local map = rawget(_G, "WorldMapFrame")
  if not map or not layer then
    return
  end
  ns.MapFan:Collapse()  -- an open ring holds textures that are about to go
  iconPool:ReleaseAll()
  wipe(self.hits)
  wipe(self.icons)
  wipe(self.fanItems)
  local canvas = map:GetCanvas()
  local mapID = map:GetMapID()
  local width, height = canvas:GetSize()
  self.drawnFor = { mapID = mapID, width = width, scale = canvas:GetEffectiveScale() }
  if not self.lists or not mapID or not width or width == 0 then
    return
  end
  local size = iconSize(canvas)
  vector = vector or CreateVector2D(0, 0)
  for key, entries in pairs(self.lists) do
    if self:IsOn(key) then
      local icon = iconOf(key)
      local placed = {}
      for _, entry in ipairs(entries) do
        for _, p in ipairs(pointsOf(entry) or {}) do
          vector:SetXY(p.x, p.y)
          local _, pos = C_Map.GetMapPosFromWorldPos(p.map, vector, mapID)
          if pos and pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1 then
            local x, y = pos.x * width, pos.y * height
            local near = false
            for _, q in ipairs(placed) do
              if (q[1] - x) ^ 2 + (q[2] - y) ^ 2 < MERGE_PIXELS * MERGE_PIXELS then
                near = true
                break
              end
            end
            if not near then
              placed[#placed + 1] = { x, y }
              local texture = iconPool:Acquire()
              texture:SetTexture(icon)
              texture:SetSize(size, size)
              texture:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
              self.icons[#self.icons + 1] = texture
              local hit = { x = x, y = y, entry = entry, key = key }
              self.hits[#self.hits + 1] = hit
              self.fanItems[#self.fanItems + 1] = {
                texture = texture, x = x, y = y, base = ICON_SIZE,
                fill = function(tooltip) MapServices.FillTooltip(tooltip, { hit }) end,
              }
            end
          end
        end
      end
    end
  end
end

local function labelOf(key)
  for _, s in ipairs(SERVICES) do
    if s.key == key then
      return s.label
    end
  end
  return (key:gsub("^trainer:", ""):gsub("^class:", "")) .. " trainer"
end

---Fills `tooltip` (owned and anchored by the caller) for service icons: name, and title or service.
function MapServices.FillTooltip(tooltip, hits)
  tooltip:ClearLines()
  for i, hit in ipairs(hits) do
    if i > 1 then
      tooltip:AddLine(" ")
    end
    tooltip:AddLine(hit.entry.name or "?", 1, 1, 1)
    local title = hit.entry.title
    tooltip:AddLine(title and title ~= "" and title or labelOf(hit.key), 0.8, 0.8, 0.8)
  end
  tooltip:Show()
end

local hoverElapsed = 0
local function updateHover(map, delta)
  hoverElapsed = hoverElapsed + delta
  if hoverElapsed < HOVER_SECONDS then
    return
  end
  hoverElapsed = 0
  local found
  -- An open ring of fanned-out icons owns the tooltip (UI/MapFan.lua).
  if map:IsMouseOver() and #MapServices.hits > 0 and not ns.MapAvailable.hovering and not ns.MapFan.fanned then
    local nx, ny = map:GetNormalizedCursorPosition()
    if nx and ny and not issecretvalue(nx) and not issecretvalue(ny) then
      local width, height = map:GetCanvas():GetSize()
      local x, y = nx * width, ny * height
      local r = iconSize(map:GetCanvas()) / 2
      found = {}
      for _, hit in ipairs(MapServices.hits) do
        if (hit.x - x) ^ 2 + (hit.y - y) ^ 2 <= r * r then
          found[#found + 1] = hit
        end
      end
      found = #found > 0 and found or nil
    end
  end
  if found then
    local tooltip = ns.Tooltips:Take(layer, "ANCHOR_CURSOR")  -- nil while Ctrl hides ours
    if tooltip then
      MapServices.FillTooltip(tooltip, found)
    end
    MapServices.hovering = tooltip ~= nil
  elseif MapServices.hovering then
    if GameTooltip:GetOwner() == layer then
      GameTooltip:Hide()
    end
    MapServices.hovering = false
  end
end

local function createLayer()
  local map = rawget(_G, "WorldMapFrame")
  if layer or not map then
    return
  end
  local canvas = map:GetCanvas()
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:EnableMouse(false)
  layer:SetFrameLevel(FRAME_LEVEL)
  ns.MapFan:Register("services", MapServices.fanItems)
  iconPool = ns.CreatePool(function()
    return layer:CreateTexture(nil, "OVERLAY")
  end)
  layer:SetScript("OnUpdate", function(_, delta)
    local drawn = MapServices.drawnFor
    if not drawn or drawn.mapID ~= map:GetMapID() or drawn.width ~= canvas:GetWidth() then
      MapServices:Redraw()
    elseif drawn.scale ~= canvas:GetEffectiveScale() then
      ns.MapFan:Collapse()
      drawn.scale = canvas:GetEffectiveScale()
      local size = iconSize(canvas)
      for _, icon in ipairs(MapServices.icons) do
        icon:SetSize(size, size)
      end
    end
    updateHover(map, delta)
  end)
  layer:SetScript("OnHide", function()
    if MapServices.hovering and GameTooltip:GetOwner() == layer then
      GameTooltip:Hide()
    end
    MapServices.hovering = false
  end)
end

function MapServices:MarkDirty()
  self.drawnFor = nil
end

ns.Events:On("PLAYER_LOGIN", function()
  createLayer()
  adoptProfessions()
  if anyOn() then
    MapServices:Build()
  end
end)
ns.Events:On("SKILL_LINES_CHANGED", adoptProfessions)
-- Another profile: other services on (the per-character trainers stay as they are).
ns.Bus:On("ProfileChanged", function()
  MapServices:MarkDirty()
  if layer and anyOn() then
    MapServices:Build()
  end
end)
ns.Events:On("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then
    createLayer()
  end
end)
