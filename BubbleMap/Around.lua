local ADDON_NAME, ns = ...

-- Everything around the minimap, ours: a bar along the map's top (zone name; tracking, calendar and
-- mail buttons; the clock), coordinates and zoom buttons, each a setting. Design:
-- docs/design/questmarker-map.md ("Around the minimap").
--
-- Blizzard's own versions are always hidden while BubbleMap styles the map: they're laid out for the
-- round map and sat inside the square one (seen in game). Hidden by alpha 0 and the mouse off, never
-- Hide(): Show() doesn't reset alpha, so Blizzard re-showing one (the zoom buttons on every mouse-over,
-- Minimap.lua:257; the clock's alarm) changes nothing visible and needs no hook. And MinimapCluster is
-- a ResizeLayoutFrame measuring its shown children (LayoutFrame.lua:488-520), so Hide() would shrink
-- Edit Mode's selection box; alpha leaves it alone. None of these frames is secure.
--
-- Not replaced (Forever has no such frame): crafting orders, instance difficulty. Left alone: the
-- queue eye (QueueStatusButton), its own Edit Mode system; the addon compartment ("13", the addon
-- count) until the launcher list replaces it (build step 4).

-- One strata above the minimap's. MinimapCluster is toplevel (Minimap.xml:3): a click on the map
-- raises it, Minimap and all, over anything at its strata, and the bar vanished under the map after a
-- ping (seen in review). A higher strata can't be raised over.
local STRATA_ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG" }

local BAR_HEIGHT = 20
local BAR_BAND = { 0, 0, 0, 0.45 }
local ICON = 15
local GAP = 4
local PAD = 6
local CLOCK_SECONDS = 1
local COORDS_SECONDS = 0.2

local Around = {}
ns.Around = Around

local bar, zone, clock, buttons, coords, zoomIn, zoomOut

-- Fonts: the quest addon's (its face and size settings) when it's there, else the game's.
local function font(kind)
  local theme = ns.Quest and ns.Quest.Theme()
  local name = theme and theme.fonts[kind]
  if name and rawget(_G, name) then
    return name
  end
  return kind == "header" and "GameFontNormal" or "GameFontHighlightSmall"
end

-- Our frames over the map: above the minimap's strata (see STRATA_ABOVE).
local function overMap(frame)
  frame:SetFrameStrata(STRATA_ABOVE[Minimap:GetFrameStrata()] or "MEDIUM")
end

local function tooltip(owner, fill)
  owner:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    fill()
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Blizzard's versions -----------------------------------------------------------------------------

local function fade(frame, ...)
  if frame then
    frame:SetAlpha(0)
    frame:EnableMouse(false)
  end
  for i = 1, select("#", ...) do
    local child = select(i, ...)
    if child then
      child:EnableMouse(false)
    end
  end
end

local function hideBlizzard()
  local cluster = MinimapCluster
  fade(cluster.ZoneTextButton)
  fade(GameTimeFrame)
  fade(cluster.Tracking, cluster.Tracking and cluster.Tracking.Button)
  fade(cluster.IndicatorFrame, cluster.IndicatorFrame and cluster.IndicatorFrame.MailFrame)
  fade(Minimap.ZoomIn)
  fade(Minimap.ZoomOut)
  fade(nil, Minimap.ZoomHitArea)
  fade(MinimapBackdrop, ExpansionLandingPageMinimapButton, MinimapBackdrop.ExternalEventURLButton)
  fade(cluster.DielFrame)
  fade(cluster.MinimapContainer.PlayerCoords)
  -- The clock is load-on-demand (Blizzard loads it at login).
  EventUtil.ContinueOnAddOnLoaded("Blizzard_TimeManager", function()
    fade(TimeManagerClockButton)
  end)
end

-- Zone --------------------------------------------------------------------------------------------

local PVP_COLORS = {
  sanctuary = { 0.41, 0.8, 0.94 },
  arena = { 1, 0.1, 0.1 },
  friendly = { 0.1, 1, 0.1 },
  hostile = { 1, 0.1, 0.1 },
  contested = { 1, 0.7, 0 },
  combat = { 1, 0.1, 0.1 },
}

local function updateZone()
  zone.text:SetText(GetMinimapZoneText())
  local color = PVP_COLORS[C_PvP.GetZonePVPInfo() or ""] or { NORMAL_FONT_COLOR:GetRGB() }
  zone.text:SetTextColor(color[1], color[2], color[3])
end

local function zoneTooltip()
  local pvpType, _, faction = C_PvP.GetZonePVPInfo()
  GameTooltip:AddLine(GetZoneText(), 1, 1, 1)
  local sub = GetSubZoneText()
  if sub ~= "" and sub ~= GetZoneText() then
    local color = PVP_COLORS[pvpType or ""] or { NORMAL_FONT_COLOR:GetRGB() }
    GameTooltip:AddLine(sub, color[1], color[2], color[3])
  end
  if faction and faction ~= "" and (pvpType == "friendly" or pvpType == "hostile") then
    GameTooltip:AddLine(("Controlled by %s"):format(faction), 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("Click: world map", 0.6, 0.6, 0.6)
end

-- Buttons on the bar --------------------------------------------------------------------------------

local function iconButton(atlas)
  local b = CreateFrame("Button", nil, bar)
  b:SetSize(ICON, ICON)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetAtlas(atlas)
  b:SetHighlightAtlas(atlas, "ADD")
  return b
end

-- Tracking changes land a moment after SetTracking (spell tracking like Find Herbs is an aura), so the
-- menu re-read the old state and kept a box ticked that had just been turned off (seen in review).
-- As Blizzard's menu does (its predicted tracking state, Mainline/Minimap.lua:80, 628-636): what was
-- clicked shows until MINIMAP_UPDATE_TRACKING confirms it, then the open menu is redrawn (one spell
-- tracking on turns another off, which only the event tells).
local predicted = {}   -- [index] = the state clicked, until the game confirms
local trackingOpen     -- the open menu, if any

local function trackingActive(index)
  if predicted[index] ~= nil then
    return predicted[index]
  end
  local info = C_Minimap.GetTrackingInfo(index)
  return info ~= nil and info.active == true
end

local function trackingMenu(owner)
  trackingOpen = MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Tracking")
    for index = 1, C_Minimap.GetNumTrackingTypes() do
      local filter = C_Minimap.GetTrackingFilter(index)
      -- Blizzard's own rule for which types its menu lists (Mainline/Minimap.lua:619-626).
      if filter and (MinimapConstants.OPTIONAL_FILTERS[filter.filterID] or filter.spellID) then
        local info = C_Minimap.GetTrackingInfo(index)
        if info then
          root:CreateCheckbox(info.name,
            function() return trackingActive(index) end,
            function()
              local on = not trackingActive(index)
              predicted[index] = on
              C_Minimap.SetTracking(index, on)
            end)
        end
      end
    end
  end)
end

ns.On("MINIMAP_UPDATE_TRACKING", function()
  wipe(predicted)
  if trackingOpen and trackingOpen:IsShown() then
    trackingOpen:ReinitializeAll()
  end
end)

local function updateMail()
  buttons.mail.has = HasNewMail() and true or false
end

local function updateCalendar()
  local invites = C_Calendar.GetNumPendingInvites()
  buttons.calendar.count:SetText(invites > 0 and tostring(invites) or "")
end

local function createButtons()
  buttons = {}

  local tracking = iconButton("ui-hud-minimap-tracking-button")
  tracking:SetScript("OnClick", function(self) trackingMenu(self) end)
  tooltip(tracking, function() GameTooltip:AddLine("Tracking", 1, 1, 1) end)
  buttons.tracking = tracking

  local calendar = iconButton("ui-hud-minimap-calendar-button")
  calendar.count = calendar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  calendar.count:SetPoint("BOTTOMRIGHT", 3, -2)
  calendar:SetScript("OnClick", function()
    if InCombatLockdown() then
      return  -- the calendar opens as a UI panel: out of combat only
    end
    ToggleCalendar()
  end)
  tooltip(calendar, function()
    GameTooltip:AddLine("Calendar", 1, 1, 1)
    local invites = C_Calendar.GetNumPendingInvites()
    if invites > 0 then
      GameTooltip:AddLine(("%d invite%s waiting"):format(invites, invites == 1 and "" or "s"),
        NORMAL_FONT_COLOR:GetRGB())
    end
  end)
  buttons.calendar = calendar

  local mail = iconButton("ui-hud-minimap-mail-icon")
  mail:SetScript("OnClick", nil)
  tooltip(mail, function()
    local senders = { GetLatestThreeSenders() }
    FormatUnreadMailTooltip(GameTooltip, #senders > 0 and "New mail from:" or "You have new mail", senders)
  end)
  buttons.mail = mail
end

-- Clock -------------------------------------------------------------------------------------------

local function alarmFiring()
  local firing = rawget(_G, "TimeManager_IsAlarmFiring")
  return firing ~= nil and firing() == true
end

local function updateClock()
  clock.text:SetText(GameTime_GetTime(true))
  if alarmFiring() then
    clock.text:SetTextColor(1, 0.2, 0.2)
  else
    clock.text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
  end
end

local function createClock()
  clock = CreateFrame("Button", nil, bar)
  clock:SetHeight(BAR_HEIGHT)
  clock.text = clock:CreateFontString(nil, "OVERLAY", font("small"))
  clock.text:SetPoint("RIGHT")
  clock:SetScript("OnClick", function()
    local turnOff = rawget(_G, "TimeManager_TurnOffAlarm")
    if alarmFiring() and turnOff then
      turnOff()
    else
      ToggleTimeManager()
    end
  end)
  tooltip(clock, function()
    GameTime_UpdateTooltip()
    GameTooltip:AddLine("Click: " .. (alarmFiring() and "stop the alarm" or "clock settings"), 0.6, 0.6, 0.6)
  end)
  local elapsed = CLOCK_SECONDS
  clock:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= CLOCK_SECONDS then
      elapsed = 0
      updateClock()
      clock:SetWidth(clock.text:GetStringWidth() + 2)
    end
  end)
end

-- The bar -----------------------------------------------------------------------------------------

local function createBar(outer)
  bar = CreateFrame("Frame", nil, outer)
  overMap(bar)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(BAR_HEIGHT)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() ns.Minimap:StartDrag() end)
  bar:SetScript("OnDragStop", function() ns.Minimap:StopDrag() end)

  local band = bar:CreateTexture(nil, "BACKGROUND")
  band:SetAllPoints()
  band:SetColorTexture(BAR_BAND[1], BAR_BAND[2], BAR_BAND[3], BAR_BAND[4])

  zone = CreateFrame("Button", nil, bar)
  zone:SetPoint("TOPLEFT", PAD, 0)
  zone:SetPoint("BOTTOMLEFT", PAD, 0)
  zone:RegisterForDrag("LeftButton")  -- the name is most of the bar: dragging it drags the map too
  zone:SetScript("OnDragStart", function() ns.Minimap:StartDrag() end)
  zone:SetScript("OnDragStop", function() ns.Minimap:StopDrag() end)
  zone.text = zone:CreateFontString(nil, "OVERLAY", font("small"))
  zone.text:SetAllPoints()
  zone.text:SetJustifyH("LEFT")
  zone.text:SetWordWrap(false)
  zone:SetScript("OnClick", function() ToggleWorldMap() end)
  tooltip(zone, zoneTooltip)

  createButtons()
  createClock()
end

-- Right to left: clock, mail (when there is mail), calendar, tracking; the zone name takes the rest.
local function layoutBar()
  local show = ns.DB.show
  bar:SetShown(show.bar)
  local right = -PAD
  local anchor = nil
  local function place(frame, visible, width)
    frame:SetShown(visible)
    if not visible then
      return
    end
    frame:ClearAllPoints()
    if anchor then
      frame:SetPoint("RIGHT", anchor, "LEFT", -GAP, 0)
    else
      frame:SetPoint("RIGHT", bar, "RIGHT", right, 0)
    end
    if width then
      frame:SetWidth(width)
    end
    anchor = frame
  end
  place(clock, show.clock)
  place(buttons.mail, show.mail and buttons.mail.has)
  place(buttons.calendar, show.calendar)
  place(buttons.tracking, show.tracking)
  zone:SetShown(show.zone)
  if anchor then
    zone:SetPoint("RIGHT", anchor, "LEFT", -GAP, 0)
  else
    zone:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
  end
end

-- Coordinates and zoom --------------------------------------------------------------------------------

local function createCoords(outer)
  coords = CreateFrame("Frame", nil, outer)
  overMap(coords)
  coords:SetSize(80, 14)
  coords:SetPoint("BOTTOMLEFT", PAD, 4)
  coords.text = coords:CreateFontString(nil, "OVERLAY", font("small"))
  coords.text:SetAllPoints()
  coords.text:SetJustifyH("LEFT")
  coords.text:SetShadowOffset(1, -1)
  local elapsed = COORDS_SECONDS
  coords:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < COORDS_SECONDS then
      return
    end
    elapsed = 0
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    coords.text:SetText(pos and ("%.1f, %.1f"):format(pos.x * 100, pos.y * 100) or "")
  end)
end

local function zoomButton(outer, label, step)
  local b = CreateFrame("Button", nil, outer)
  overMap(b)
  b:SetSize(16, 16)
  local back = b:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.5)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.text:SetPoint("CENTER", 0, 1)
  b.text:SetText(label)
  b:SetHighlightTexture("Interface\\BUTTONS\\WHITE8X8", "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.15)
  b:SetScript("OnClick", function()
    local zoom = Minimap:GetZoom() + step
    if zoom >= 0 and zoom < Minimap:GetZoomLevels() then
      Minimap:SetZoom(zoom)
    end
  end)
  return b
end

local function createZoom(outer)
  zoomOut = zoomButton(outer, "-", -1)
  zoomOut:SetPoint("BOTTOMRIGHT", -PAD, 4)
  zoomIn = zoomButton(outer, "+", 1)
  zoomIn:SetPoint("RIGHT", zoomOut, "LEFT", -2, 0)
end

-- Public ------------------------------------------------------------------------------------------

---Apply the "show" settings.
function Around:Apply()
  if not bar then
    return
  end
  layoutBar()
  coords:SetShown(ns.DB.show.coords)
  zoomIn:SetShown(ns.DB.show.zoom)
  zoomOut:SetShown(ns.DB.show.zoom)
end

table.insert(ns.Minimap.onActivate, function(outer)
  hideBlizzard()
  createBar(outer)
  createCoords(outer)
  createZoom(outer)
  updateZone()
  updateMail()
  updateCalendar()
  Around:Apply()
end)

for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
  ns.On(event, function()
    if bar then
      updateZone()
    end
  end)
end
ns.On("UPDATE_PENDING_MAIL", function()
  if bar then
    updateMail()
    layoutBar()
  end
end)
ns.On("CALENDAR_UPDATE_PENDING_INVITES", function()
  if bar then
    updateCalendar()
  end
end)
