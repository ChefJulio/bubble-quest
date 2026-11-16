local ADDON_NAME, ns = ...

-- The card stack: a header row, then what ns.Tracking:View() says to show:
--   pinned cards, this zone's cards (capped), "+ N more here", one group per separated category
--   ("+ Camping (2)"), "Elsewhere (N)", "Hidden (N)".
-- Tracking decides order and membership; this file only draws.
--
-- When things change (spec: nothing jumps around):
--   - Progress updates in place, any time, combat included (Card:UpdateInPlace).
--   - Re-sorts happen on QuestLogChanged, zone changes and Tracking's movement trigger, and never in
--     combat: they wait for the end of combat (ns.Combat). A calm-UI rule; the frames are plain.
--   - The player's own clicks (collapse, pin, hide, groups, header buttons) apply at once, even in
--     combat; a re-sort still waiting stays queued until combat ends.
--
-- Look (approved in game): a translucent panel (opacity setting, default 25%), a darker header band, faint dividers between
-- cards and stronger ones before each group line.

local DEFAULT_POSITION = { "TOPRIGHT", "TOPRIGHT", -60, -230 }
local PAD = 6                -- inner padding of the panel
local HEADER_HEIGHT = 22
local LINE_HEIGHT = 16
local HALF_GAP = 5           -- space above and below a divider
local BUTTON_SIZE_X, BUTTON_SIZE_Y = 18, 19  -- Blizzard's tracker header buttons
local DIVIDER_ALPHA = { card = 0.08, section = 0.2 }
local BOTTOM_MARGIN = 12     -- the panel stops this far above the screen's bottom edge, then scrolls
local DEFAULT_WIDTH, MIN_WIDTH, MAX_WIDTH = 250, 200, 450  -- card width (resize grip)
local MIN_SCROLL_HEIGHT = 48 -- the resize grip can't make the scroll area smaller than this
local SCROLL_STEP = 40       -- pixels per mouse wheel notch

-- The first atlas the client has, from candidates seen in Forever's UI source. Atlases referenced
-- only by retail-only files might not exist on Forever, so ask the client rather than assume.
local function firstAtlas(...)
  for i = 1, select("#", ...) do
    local atlas = select(i, ...)
    if C_Texture.GetAtlasInfo(atlas) then
      return atlas
    end
  end
  return nil
end

local Stack = {
  container = nil,  ---@type Frame?
  visible = {},     -- [questID] = card currently on screen
  resortPending = false,
}
ns.Stack = Stack

local cardPool, headingPool, linePool, dividerPool

-- Drawing ----------------------------------------------------------------------------------------

-- Layout state for one pass: y offset inside the body, and whether anything was placed yet.
local cursor = { y = 0, any = false }

local function separate(kind)
  if not cursor.any then
    return
  end
  cursor.y = cursor.y + HALF_GAP
  local divider = dividerPool:Acquire()
  divider:SetPoint("TOPLEFT", Stack.body, "TOPLEFT", 0, -cursor.y)
  divider:SetPoint("TOPRIGHT", Stack.body, "TOPRIGHT", 0, -cursor.y)
  divider:SetColorTexture(1, 1, 1, DIVIDER_ALPHA[kind])
  cursor.y = cursor.y + HALF_GAP
end

local function placeCard(quest, options)
  separate("card")
  local card = cardPool:Acquire()
  card.frame:SetPoint("TOPLEFT", Stack.body, "TOPLEFT", 0, -cursor.y)
  Stack.visible[quest.questID] = card
  card.ready = quest.readyForTurnIn
  cursor.y = cursor.y + card:SetQuest(quest, ns.DB.char.collapsed[quest.questID] == true, options)
  cursor.any = true
  ns.ItemButtons:Attach(card, quest, Stack.container)  -- refused in combat; the queued layout adds it
end

local function placeHeading(text)
  separate("card")
  local heading = headingPool:Acquire()
  heading:SetPoint("TOPLEFT", Stack.body, "TOPLEFT", 0, -cursor.y)
  heading:SetText(text)
  cursor.y = cursor.y + LINE_HEIGHT
  cursor.any = false  -- no divider between a heading and its first card
end

---A clickable text line: group toggles, and quests in the Hidden group.
---@param onClick fun(line: table, button: string)
---@param kind string? "section" puts a divider above; nil for a line inside a group
local function placeLine(text, onClick, kind, indent)
  if kind then
    separate(kind)
  end
  local line = linePool:Acquire()
  line:SetWidth(ns.Card.WIDTH - (indent or 0))  -- the width can change (resize grip)
  line:SetPoint("TOPLEFT", Stack.body, "TOPLEFT", indent or 0, -cursor.y)
  line.label:SetText(text)
  line.onClick = onClick
  cursor.y = cursor.y + LINE_HEIGHT
  cursor.any = true
end

local function toggleGroup(state)
  return function()
    state.expanded = not state.expanded
    Stack:Request(false, true)
  end
end

local function updateHeader()
  local header = Stack.header
  local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
  local max = C_QuestLog.GetMaxNumQuestsCanAccept()
  local r, g, b = 0.8, 0.8, 0.8
  if numQuests >= max then
    r, g, b = 1, 0.2, 0.2
  elseif numQuests >= max - 5 then
    r, g, b = 1, 0.6, 0.1
  end
  header.count:SetText(("%d/%d"):format(numQuests, max))
  header.count:SetTextColor(r, g, b)

  local minimized = ns.DB.char.minimized
  header.minimize:SetNormalAtlas(minimized and "ui-questtrackerbutton-expand-all" or "ui-questtrackerbutton-collapse-all")
  header.minimize:SetPushedAtlas(minimized and "ui-questtrackerbutton-expand-all-pressed"
    or "ui-questtrackerbutton-collapse-all-pressed")

  local locked = ns.DB.profile.cards.locked
  header.lock:SetAlpha(locked and 1 or 0.4)
  if header.lock.fallback then
    header.lock.fallback:SetText(locked and "L" or "U")
  end
end

function Stack:ApplyBackground()
  if self.background then
    self.background:SetColorTexture(0, 0, 0, ns.DB.profile.cards.opacity / 100)
  end
end

function Stack:Layout()
  if not self.container then
    return
  end
  -- Quest item buttons are secure: nothing they're anchored to may move in combat. Request() already
  -- defers; this is the backstop.
  if InCombatLockdown() and ns.ItemButtons:AnyShown() then
    return
  end
  ns.ItemButtons:ReleaseAll()
  self:ApplyWidth()
  cardPool:ReleaseAll()
  headingPool:ReleaseAll()
  linePool:ReleaseAll()
  dividerPool:ReleaseAll()
  wipe(self.visible)
  updateHeader()

  local char = ns.DB.char
  if char.minimized then
    self.scroll:Hide()
    self.headerDivider:Hide()
    self:Fit()
    return
  end
  self.scroll:Show()

  local view = ns.Tracking:View()
  cursor.y, cursor.any = 0, false

  for _, quest in ipairs(view.pinned) do
    local elsewhere = not ns.Zone:IsInZone(quest) and ns.Zone:NameFor(quest) or nil
    placeCard(quest, { pinned = true, zone = elsewhere })
  end
  for _, quest in ipairs(view.zone) do
    placeCard(quest)
  end

  if #view.overflow > 0 then
    if char.overflow.expanded then
      for _, quest in ipairs(view.overflow) do
        placeCard(quest)
      end
      placeLine("- Show fewer", toggleGroup(char.overflow), "section")
    else
      placeLine(("+ %d more here"):format(#view.overflow), toggleGroup(char.overflow), "section")
    end
  end

  for _, group in ipairs(view.groups) do
    local category = group.category
    local expanded = char.groups[category] == true
    placeLine(("%s %s (%d)"):format(expanded and "-" or "+", group.label, #group.quests), function()
      char.groups[category] = not expanded or nil
      Stack:Request(false, true)
    end, "section")
    if expanded then
      for _, quest in ipairs(group.quests) do
        placeCard(quest)
      end
    end
  end

  if #view.elsewhere > 0 then
    local expanded = char.elsewhere.expanded
    placeLine(("%s Elsewhere (%d)"):format(expanded and "-" or "+", #view.elsewhere), toggleGroup(char.elsewhere),
      "section")
    if expanded then
      local byZone, zones = {}, {}
      for _, quest in ipairs(view.elsewhere) do
        local zone = ns.Zone:NameFor(quest)
        if not byZone[zone] then
          byZone[zone] = {}
          zones[#zones + 1] = zone
        end
        table.insert(byZone[zone], quest)
      end
      table.sort(zones)
      for _, zone in ipairs(zones) do
        placeHeading(zone)
        table.sort(byZone[zone], function(a, b) return (a.order or 0) < (b.order or 0) end)
        for _, quest in ipairs(byZone[zone]) do
          placeCard(quest)
        end
      end
    end
  end

  if #view.hidden > 0 then
    local expanded = char.hidden.expanded
    placeLine(("%s Hidden (%d)"):format(expanded and "-" or "+", #view.hidden), toggleGroup(char.hidden), "section")
    if expanded then
      for _, quest in ipairs(view.hidden) do
        placeLine(quest.title or "?", function(line)
          ns.Menu:OpenForHidden(line, quest)
        end, nil, 14)
      end
    end
  end

  local y = cursor.y
  self.headerDivider:SetShown(y > 0)
  self.body:SetHeight(math.max(y, 1))
  self:Fit()
end

-- Scrolling ----------------------------------------------------------------------------------------
-- The cards scroll inside the panel instead of growing past the screen bottom (the clamp then pushed
-- the whole stack up; seen in review). The panel is as tall as its contents, at most down to
-- BOTTOM_MARGIN above the screen's bottom edge. Mouse wheel scrolls; a thin thumb shows where.
--
-- Quest item buttons sit outside the panel (left of their card), so the scroll area can't clip them:
-- a button is hidden while its card is scrolled out of view. They're secure, so that happens out of
-- combat only, and while any is up, scrolling in combat is paused (scrolling would move them).

-- Height the scroll area may use: from the panel's top down to BOTTOM_MARGIN above the screen, and no
-- more than the height set with the resize grip (cards.maxHeight; 0 = no limit of its own).
function Stack:MaxScrollHeight()
  local top = self.container:GetTop()
  local room = top and math.max(MIN_SCROLL_HEIGHT, top - HEADER_HEIGHT - 2 * PAD - BOTTOM_MARGIN) or math.huge
  local cap = ns.DB.profile.cards.maxHeight or 0
  return cap > 0 and math.min(room, cap) or room
end

-- Width ------------------------------------------------------------------------------------------

---The card width from the profile, to every part that depends on it.
function Stack:ApplyWidth()
  local width = ns.DB.profile.cards.width or ns.Card.WIDTH
  ns.Card.SetWidth(width)
  self.container:SetWidth(width + 2 * PAD)
  self.scroll:SetWidth(width)
  self.body:SetWidth(width)
end

-- Resize grip (review: "the lock button allows corner dragging"): bottom-right corner, shown while the
-- cards are unlocked. Dragging sets the card width and the most the panel may grow (cards.maxHeight);
-- the panel still shrinks to its contents. While dragging, the panel shows its full height, so you see
-- what you set. Not in combat: quest item buttons are secure and anchored to the cards. Right-click
-- resets both.

local RESIZE_STEP_SECONDS = 0.05

local function cursorPosition()
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  return x / scale, y / scale
end

function Stack:StartResize()
  if InCombatLockdown() then
    return
  end
  -- Grow right and down: pin the top-left corner first (a default position is anchored top-right).
  ns.DB.profile.cards.position = self:AnchorTopLeft() or ns.DB.profile.cards.position
  local x, y = cursorPosition()
  self.resizing = {
    x = x, y = y,
    width = ns.DB.profile.cards.width,
    height = self.scroll:GetHeight(),
    elapsed = 0,
  }
  self.grip:SetScript("OnUpdate", function(_, delta)
    local r = self.resizing
    r.elapsed = r.elapsed + delta
    if r.elapsed >= RESIZE_STEP_SECONDS then
      r.elapsed = 0
      self:ResizeTo()
    end
  end)
end

function Stack:ResizeTo()
  local r = self.resizing
  if not r or InCombatLockdown() then
    return
  end
  local x, y = cursorPosition()
  local cards = ns.DB.profile.cards
  local width = math.floor(math.max(MIN_WIDTH, math.min(MAX_WIDTH, r.width + (x - r.x))) + 0.5)
  local height = math.floor(math.max(MIN_SCROLL_HEIGHT, r.height + (r.y - y)) + 0.5)
  if width ~= cards.width or height ~= cards.maxHeight then
    cards.width, cards.maxHeight = width, height
    self:Layout()
  end
end

function Stack:StopResize()
  if not self.resizing then
    return
  end
  self:ResizeTo()
  self.resizing = nil
  self.grip:SetScript("OnUpdate", nil)
  self:Layout()  -- back to fitting the contents
end

function Stack:ResetSize()
  if InCombatLockdown() then
    return
  end
  ns.DB.profile.cards.width, ns.DB.profile.cards.maxHeight = DEFAULT_WIDTH, 0
  self:Layout()
end

-- Size the panel to its contents (capped), keep the scroll offset in range, update the thumb.
function Stack:Fit()
  local content = self.body:GetHeight()
  if self.headerDivider:IsShown() == false then
    self.scroll:SetHeight(1)
    self.container:SetHeight(HEADER_HEIGHT)
    self:ScrollTo(0)
    return
  end
  local view = math.min(content, self:MaxScrollHeight())
  if self.resizing then
    view = self:MaxScrollHeight()  -- while dragging, show the full height being set
  end
  self.scroll:SetHeight(view)
  self.container:SetHeight(HEADER_HEIGHT + PAD + view + PAD)
  self:ScrollTo(self.scroll:GetVerticalScroll())
end

---@param offset number pixels from the top; clamped to the scrollable range
function Stack:ScrollTo(offset)
  local scroll = self.scroll
  local range = math.max(0, self.body:GetHeight() - scroll:GetHeight())
  offset = math.max(0, math.min(offset, range))
  scroll:SetVerticalScroll(offset)

  local thumb = self.thumb
  if range <= 0 then
    thumb:Hide()
  else
    local view = scroll:GetHeight()
    local size = math.max(16, view * view / (view + range))
    thumb:SetHeight(size)
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", PAD - 2, -(view - size) * offset / range)
    thumb:Show()
  end
  -- Out of combat only (secure); in combat nothing moved, as scrolling is paused while they're up.
  if not InCombatLockdown() then
    local top, bottom = scroll:GetTop(), scroll:GetBottom()
    ns.ItemButtons:ShowWhere(function(questID)
      local card = self.visible[questID]
      local cardTop = card and card.frame:GetTop()
      return cardTop ~= nil and top ~= nil and cardTop <= top + 0.5 and cardTop >= bottom + 10
    end)
  end
end

local function onMouseWheel(_, delta)
  if InCombatLockdown() and ns.ItemButtons:AnyShown() then
    return
  end
  Stack:ScrollTo(Stack.scroll:GetVerticalScroll() - delta * SCROLL_STEP)
end

-- Re-sort (rule 4) and layout, applying the combat rule. Player actions lay out at once; anything
-- else waits for the end of combat, and a pending re-sort never runs in combat.
function Stack:Flush()
  if self.resortPending or ns.Tracking:HasUnranked() then
    self.resortPending = false
    ns.Tracking:Resort()
  end
  self:Layout()
end

---@param resort boolean the order may change (an event from rule 4)
---@param playerAction boolean? the player's own click: lay out now
function Stack:Request(resort, playerAction)
  if resort then
    self.resortPending = true
  end
  if not InCombatLockdown() then
    self:Flush()
    return
  end
  -- The player's own click lays out at once, unless a secure quest item button is up: then nothing
  -- anchored to it may move until combat ends, so even clicks wait.
  if playerAction and not ns.ItemButtons:AnyShown() then
    self:Layout()
  end
  ns.Combat:Run("cards", function() self:Flush() end)
end

-- Position and lock ------------------------------------------------------------------------------

-- Until the player drags the stack, it sits exactly where Blizzard's (hidden) tracker is: the
-- game's layout system places that frame below the minimap and its widgets (timers, buffs), and
-- anchoring to it follows any change to that layout. Anchoring ours to theirs changes nothing of
-- theirs; ObjectiveTrackerFrame is not protected on Forever (/qm tracker).
function Stack:ApplyPosition()
  local container, saved = self.container, ns.DB.profile.cards.position
  if not container then
    return
  end
  container:ClearAllPoints()
  if saved then
    container:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    if saved[1] ~= "TOPLEFT" then
      -- Saved before positions were normalized: convert once, so the stack grows only downward.
      ns.DB.profile.cards.position = Stack:AnchorTopLeft() or saved
    end
  elseif ObjectiveTrackerFrame then
    container:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "TOPRIGHT")
  else
    local p = DEFAULT_POSITION
    container:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  end
end

function Stack:ApplyLock()
  if self.header then
    updateHeader()
  end
  if self.grip then
    self.grip:SetShown(not ns.DB.profile.cards.locked)
  end
end

-- Pin the stack's top-left corner where it is now, so changes in height only grow or shrink it
-- downward. (After StartMoving the frame can be anchored by another point, e.g. its center, and
-- would then grow both up and down.) Returns the position to save, or nil if not laid out yet.
function Stack:AnchorTopLeft()
  local container = self.container
  local left, top = container and container:GetLeft(), container and container:GetTop()
  if not container or not left or not top then
    return nil
  end
  container:ClearAllPoints()
  container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  return { "TOPLEFT", "BOTTOMLEFT", left, top }
end

local function savePosition()
  local container = Stack.container
  if not container then
    return
  end
  container:StopMovingOrSizing()
  ns.DB.profile.cards.position = Stack:AnchorTopLeft() or ns.DB.profile.cards.position
  Stack:Request(false, true)  -- the room below changed: refit the scroll area
end

-- Construction -------------------------------------------------------------------------------------

local function headerButton(parent, tooltip, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(BUTTON_SIZE_X, BUTTON_SIZE_Y)
  button:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(tooltip(), 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return button
end

local function createHeader(container)
  local header = CreateFrame("Frame", nil, container)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER_HEIGHT)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  -- Drag (when unlocked) moves the stack; a plain left click opens settings. A drag that ends over
  -- the header also produces a mouse-up, so remember whether the press turned into a drag.
  header:SetScript("OnMouseDown", function()
    header.dragged = false
  end)
  header:SetScript("OnDragStart", function()
    header.dragged = true
    if not ns.DB.profile.cards.locked then
      container:StartMoving()
    end
  end)
  header:SetScript("OnDragStop", savePosition)
  header:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and not header.dragged and header:IsMouseOver() then
      ns.Settings:Open()
    end
  end)

  -- Darker band behind the header, on top of the panel background.
  local band = header:CreateTexture(nil, "BACKGROUND", nil, 1)
  band:SetAllPoints()
  band:SetColorTexture(0, 0, 0, 0.35)

  header.title = header:CreateFontString(nil, "ARTWORK", "QuestmarkerHeaderFont")
  header.title:SetPoint("LEFT", PAD, 0)
  header.title:SetText("Questmarker")

  header.minimize = headerButton(header, function()
    return ns.DB.char.minimized and "Show Questmarker's cards" or "Minimize to this header"
  end, function()
    ns.DB.char.minimized = not ns.DB.char.minimized
    Stack:Request(false, true)
  end)
  header.minimize:SetPoint("RIGHT", -PAD + 2, 0)

  header.settings = headerButton(header, function() return "Questmarker settings" end, function()
    ns.Settings:Open()
  end)
  header.settings:SetNormalAtlas("ui-questtrackerbutton-filter")
  header.settings:SetPushedAtlas("ui-questtrackerbutton-filter-pressed")
  header.settings:SetPoint("RIGHT", header.minimize, "LEFT", -2, 0)

  header.lock = headerButton(header, function()
    return ns.DB.profile.cards.locked and "Locked. Click to unlock, then drag this header to move the cards."
      or "Unlocked: drag this header to move the cards. Click to lock."
  end, function()
    -- Through the setting, so both settings UIs follow (their checkboxes refresh on SettingChanged).
    ns.Settings:SetValue("QUESTMARKER_LOCK_CARDS", not ns.DB.profile.cards.locked)
  end)
  header.lock:SetPoint("RIGHT", header.settings, "LEFT", -2, 0)
  local lockAtlas = firstAtlas("worldquest-tracker-lock", "honorsystem-bar-lock", "groupfinder-icon-lock")
  if lockAtlas then
    header.lock:SetNormalAtlas(lockAtlas)
  else
    header.lock.fallback = header.lock:CreateFontString(nil, "ARTWORK", "QuestmarkerSmallHighlightFont")
    header.lock.fallback:SetPoint("CENTER")
  end

  header.count = header:CreateFontString(nil, "ARTWORK", "QuestmarkerSmallFont")
  header.count:SetPoint("RIGHT", header.lock, "LEFT", -6, 0)

  return header
end

function Stack:Create()
  local container = CreateFrame("Frame", "QuestmarkerStack", UIParent)
  container:SetSize(ns.Card.WIDTH + 2 * PAD, HEADER_HEIGHT)
  container:SetMovable(true)
  container:SetClampedToScreen(true)
  self.container = container

  self.background = container:CreateTexture(nil, "BACKGROUND", nil, 0)
  self.background:SetAllPoints()
  self:ApplyBackground()

  self.header = createHeader(container)

  self.headerDivider = container:CreateTexture(nil, "ARTWORK")
  self.headerDivider:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT")
  self.headerDivider:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT")
  self.headerDivider:SetColorTexture(1, 1, 1, DIVIDER_ALPHA.section)
  PixelUtil.SetHeight(self.headerDivider, 1, 1)

  -- The cards live on `body`, the scroll child of `scroll` (see Scrolling).
  local scroll = CreateFrame("ScrollFrame", nil, container)
  scroll:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", PAD, -PAD)
  scroll:SetSize(ns.Card.WIDTH, 1)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", onMouseWheel)
  self.scroll = scroll

  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(ns.Card.WIDTH, 1)
  scroll:SetScrollChild(body)
  self.body = body

  self.thumb = container:CreateTexture(nil, "OVERLAY")
  self.thumb:SetWidth(2)
  self.thumb:SetColorTexture(1, 1, 1, 0.3)
  self.thumb:Hide()

  -- The resize grip (see Width): Blizzard's chat-frame corner art.
  local grip = CreateFrame("Button", nil, container)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(container:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      Stack:StartResize()
    end
  end)
  grip:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" then
      Stack:StopResize()
    end
  end)
  grip:SetScript("OnClick", function() Stack:ResetSize() end)  -- right-click
  grip:SetScript("OnEnter", function()
    GameTooltip:SetOwner(grip, "ANCHOR_RIGHT")
    GameTooltip:SetText("Resize", 1, 1, 1)
    GameTooltip:AddLine("Drag to set the width and the most the cards may grow. Right-click: default size. "
      .. "Lock the cards to hide this.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  grip:Hide()
  self.grip = grip

  cardPool = ns.CreatePool(function()
    return ns.Card.Create(body, function(questID)
      ns.Tracking:ToggleCollapsed(questID)
    end, function(card, questID)
      local quest = ns.QuestLog:Get(questID)
      if quest then
        ns.Menu:OpenForCard(card.frame, quest)
      end
    end, function(questID)
      if ns.DB.profile.cards.clickOpensMap then
        ns.Navigation:ShowOnMap(questID)
      end
    end)
  end, function(card)
    card.questID = nil
  end)

  headingPool = ns.CreatePool(function()
    local heading = body:CreateFontString(nil, "ARTWORK", "QuestmarkerSmallFont")
    heading:SetTextColor(0.7, 0.7, 0.7)
    return heading
  end)

  linePool = ns.CreatePool(function()
    local line = CreateFrame("Button", nil, body)
    line:SetSize(ns.Card.WIDTH, LINE_HEIGHT)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    line.label = line:CreateFontString(nil, "ARTWORK", "QuestmarkerLineFont")
    line.label:SetPoint("LEFT")
    line:SetScript("OnClick", function(self, button)
      if self.onClick then
        self.onClick(self, button)
      end
    end)
    return line
  end, function(line)
    line.onClick = nil
  end)

  dividerPool = ns.CreatePool(function()
    local divider = body:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetHeight(divider, 1, 1)
    return divider
  end)

  self:ApplyPosition()
  self:ApplyLock()  -- the resize grip shows while unlocked
end

-- Events -------------------------------------------------------------------------------------------

ns.Events:On("PLAYER_LOGIN", function()
  Stack:Create()
end)

-- Rule 4: these may change the order.
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
  ns.Events:On(event, function() Stack:Request(true) end)
end
ns.Bus:On("QuestLogChanged", function() Stack:Request(true) end)
ns.Bus:On("TrackingResortWanted", function() Stack:Request(true) end)
ns.Bus:On("NearbyQuestEntered", function() Stack:Request(true) end)
-- A newly learned item source changes a Do line ("Loot Stolen Book from ..."): redraw, no re-sort.
ns.Bus:On("LearnedSourcesChanged", function() Stack:Request(false) end)

-- These can change membership (subzone fallback, map markers) but are not re-sort events.
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "QUEST_POI_UPDATE" }) do
  ns.Events:On(event, function() Stack:Request(false) end)
end

-- The screen's size or UI scale changed: the room below the panel did too (scroll area height).
for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
  ns.Events:On(event, function() Stack:Request(false) end)
end

-- Font face or size changed: text heights change, so lay out again (no re-sort).
ns.Bus:On("FontsChanged", function() Stack:Request(false, true) end)

-- Pin, hide, collapse: the player's own actions.
ns.Bus:On("TrackingChanged", function() Stack:Request(false, true) end)

ns.Bus:On("QuestChanged", function(quest)
  local card = Stack.visible[quest.questID]
  if not card then
    return
  end
  local collapsed = ns.DB.char.collapsed[quest.questID] == true
  if card.ready == quest.readyForTurnIn and card.rowCount == ns.Card.RowCount(quest, collapsed) then
    card:UpdateInPlace(quest)
  end
  -- Otherwise (turned ready, an objective appeared) the QuestLogChanged that closes this batch
  -- lays it out, after combat.
end)

ns.Bus:On("ProfileChanged", function()
  if Stack.container then
    Stack:ApplyPosition()
    Stack:ApplyBackground()
    Stack:Request(false, true)
  end
end)
