local ADDON_NAME, ns = ...

-- The launcher list (build step 4): every addon's minimap button and addon-compartment entry in one
-- condensed, deduplicated list, opened from a button on the map's bar. Their minimap buttons are put
-- away. Design: docs/design/questmarker-map.md ("The launcher list").
--
-- Sources, and what each row runs when clicked (exactly what the original ran):
--   - LibDataBroker launchers (most addons' minimap buttons come from LibDBIcon, which draws an LDB
--     object): obj.OnClick(row, button), tooltip obj.OnTooltipShow(GameTooltip) or obj.OnEnter(row).
--   - Blizzard's addon compartment (AddonCompartmentFrame.registeredAddons, read only: Blizzard sorts
--     it itself): entry.func(entry, { buttonName = button }, row), as Blizzard's menu calls it
--     (Mainline/AddonCompartment.lua:24, 127-129); funcOnEnter(row) / funcOnLeave(row).
--   - Stray minimap buttons (Buttons on Minimap that are neither LibDBIcon's nor Blizzard's, and not
--     protected): button:Click(mouseButton).
-- Duplicates: a compartment entry that LibDBIcon made for one of its own buttons
-- (lib.objects[name].compartmentData, LibDBIcon-1.0.lua:648) is dropped; otherwise an entry whose
-- name matches a launcher's (case and colour codes ignored) is dropped too, the launcher kept (richer
-- tooltip).
--
-- Putting buttons away never touches another addon's saved settings: LibDBIcon buttons are hidden with
-- Hide() (lib:Hide writes nothing, LibDBIcon-1.0.lua:391-396) plus an OnShow post-hook, as the library
-- shows them again on Refresh/Show; the compartment button and strays are faded (alpha 0, mouse off).
-- Another button collector loaded (ForeverCleanButtons, ...): BubbleMap leaves the buttons to it and
-- offers to turn it off (Compat.lua, job "buttons").

local ROW_HEIGHT = 20
local ICON = 16
local COLUMN_WIDTH = 190
local PAD = 6
local CLOSE_DELAY = 1.0  -- seconds after the mouse leaves the list and its button

local Launchers = {
  collecting = false,
  why = "not started",  -- why not collecting, for /bmap
}
ns.Launchers = Launchers

local function lib(name)
  local stub = rawget(_G, "LibStub")
  return stub and stub(name, true)
end

local function plain(text)
  return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

local function key(text)
  return plain(text):lower():gsub("%s+", "")
end

-- Gathering -------------------------------------------------------------------------------------------

local function launcherEntry(name, obj)
  return {
    key = key(name),
    label = plain(obj.label or name),
    icon = obj.icon,
    click = function(row, button)
      if obj.OnClick then
        obj.OnClick(row, button)
      end
    end,
    enter = function(row)
      if obj.OnTooltipShow then
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        obj.OnTooltipShow(GameTooltip)
        GameTooltip:Show()
      elseif obj.OnEnter then
        obj.OnEnter(row)
      end
    end,
    leave = function(row)
      if obj.OnLeave then
        obj.OnLeave(row)
      else
        GameTooltip:Hide()
      end
    end,
  }
end

local function compartmentEntry(data)
  return {
    key = key(data.text),
    label = plain(data.text),
    icon = data.icon,
    click = function(row, button)
      if data.func then
        data.func(data, { buttonName = button }, row)
      end
    end,
    enter = function(row)
      if data.funcOnEnter then
        data.funcOnEnter(row)
      end
    end,
    leave = function(row)
      if data.funcOnLeave then
        data.funcOnLeave(row)
      end
      GameTooltip:Hide()
    end,
  }
end

-- Minimap children that are addon buttons nobody else lists: named, not protected, not Blizzard's,
-- not LibDBIcon's, not ours.
local function strays()
  local found = {}
  for _, child in ipairs({ Minimap:GetChildren() }) do
    local name = child.GetName and child:GetName()
    if name and child:IsObjectType("Button") and not child:IsProtected()
        and not name:find("^LibDBIcon10_") and not name:find("^Minimap") and child ~= Minimap.ZoomIn
        and child ~= Minimap.ZoomOut then
      found[#found + 1] = child
    end
  end
  return found
end

local function strayIcon(button)
  local icon = button.icon or button.Icon
  if icon and icon.GetTexture then
    return icon:GetTexture()
  end
  local normal = button:GetNormalTexture()
  return normal and normal:GetTexture()
end

---Every launcher, deduplicated, sorted by name.
---@return table[]
function Launchers:Entries()
  local list, seen = {}, {}
  local function add(entry)
    if entry.key ~= "" and not seen[entry.key] then
      seen[entry.key] = true
      list[#list + 1] = entry
    end
  end

  local ldb = lib("LibDataBroker-1.1")
  if ldb then
    for name, obj in ldb:DataObjectIterator() do
      if obj.type == "launcher" or obj.OnClick then
        add(launcherEntry(name, obj))
      end
    end
  end

  local dbIcon = lib("LibDBIcon-1.0")
  local own = {}  -- LibDBIcon's own compartment entries
  if dbIcon then
    for name, button in pairs(dbIcon.objects) do
      if button.dataObject then
        add(launcherEntry(name, button.dataObject))
      end
      if button.compartmentData then
        own[button.compartmentData] = true
      end
    end
  end

  local compartment = rawget(_G, "AddonCompartmentFrame")
  if compartment and compartment.registeredAddons then
    for _, data in ipairs(compartment.registeredAddons) do
      if not own[data] then
        add(compartmentEntry(data))
      end
    end
  end

  for _, button in ipairs(strays()) do
    add({
      key = key(button:GetName()),
      label = plain(button:GetName()):gsub("MinimapButton$", ""):gsub("_", " "),
      icon = strayIcon(button),
      click = function(_, mouseButton) button:Click(mouseButton) end,
      enter = function() end,
      leave = function() GameTooltip:Hide() end,
    })
  end

  table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
  return list
end

-- Putting the buttons away ----------------------------------------------------------------------------

local hooked = {}

local function putAway(button)
  button:Hide()
  if not hooked[button] then
    hooked[button] = true
    button:HookScript("OnShow", function(self)
      if Launchers.collecting then
        self:Hide()
      end
    end)
  end
end

local function fade(frame)
  frame:SetAlpha(0)
  frame:EnableMouse(false)
end

local function collect()
  local dbIcon = lib("LibDBIcon-1.0")
  if dbIcon then
    for _, name in ipairs(dbIcon:GetButtonList()) do
      local button = dbIcon:GetMinimapButton(name)
      if button then
        putAway(button)
      end
    end
  end
  local compartment = rawget(_G, "AddonCompartmentFrame")
  if compartment then
    fade(compartment)
  end
  for _, button in ipairs(strays()) do
    fade(button)
  end
end

-- The list --------------------------------------------------------------------------------------------

local panel, rows, opener = nil, {}, nil
local outside = 0

local function setIcon(texture, icon)
  if type(icon) == "string" and C_Texture.GetAtlasInfo(icon) then
    texture:SetAtlas(icon)
  else
    texture:SetTexture(icon or 134400)  -- the question mark icon
  end
end

local function row(i)
  local r = rows[i]
  if r then
    return r
  end
  r = CreateFrame("Button", nil, panel)
  r:SetSize(COLUMN_WIDTH, ROW_HEIGHT)
  r:RegisterForClicks("AnyUp")
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ICON, ICON)
  r.icon:SetPoint("LEFT", 4, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.text:SetPoint("RIGHT", -4, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r:SetScript("OnClick", function(self, button)
    self:GetParent():Hide()
    self.entry.click(self, button)
  end)
  r:SetScript("OnEnter", function(self) self.entry.enter(self) end)
  r:SetScript("OnLeave", function(self) self.entry.leave(self) end)
  rows[i] = r
  return r
end

local function createPanel(parent)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(0.05, 0.05, 0.06, 0.94)
  frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  frame:EnableMouse(true)
  frame:Hide()
  -- Closes a moment after the mouse leaves it and its button.
  frame:SetScript("OnUpdate", function(self, delta)
    if self:IsMouseOver() or (opener and opener:IsMouseOver()) then
      outside = 0
      return
    end
    outside = outside + delta
    if outside >= CLOSE_DELAY then
      self:Hide()
    end
  end)
  return frame
end

---Open (or close) the list under `button`, as many columns as the screen's height needs.
---@param button Frame
function Launchers:Toggle(button)
  if panel and panel:IsShown() then
    panel:Hide()
    return
  end
  opener = button
  local list = panel or createPanel(button)
  panel = list
  local entries = self:Entries()
  local perColumn = math.max(1, math.floor((button:GetBottom() - 40) / ROW_HEIGHT))
  local columns = math.max(1, math.ceil(#entries / perColumn))
  local shown = math.min(#entries, perColumn)
  for i, entry in ipairs(entries) do
    local r = row(i)
    r.entry = entry
    setIcon(r.icon, entry.icon)
    r.text:SetText(entry.label)
    local column, line = math.floor((i - 1) / perColumn), (i - 1) % perColumn
    r:ClearAllPoints()
    r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -PAD - column * COLUMN_WIDTH, -PAD - line * ROW_HEIGHT)
    r:Show()
  end
  for i = #entries + 1, #rows do
    rows[i]:Hide()
  end
  list:SetSize(columns * COLUMN_WIDTH + 2 * PAD, math.max(1, shown) * ROW_HEIGHT + 2 * PAD)
  list:ClearAllPoints()
  list:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 4, -4)
  outside = 0
  list:Show()
end

-- Start -----------------------------------------------------------------------------------------------

---Whether BubbleMap is collecting buttons (the setting, and no other collector loaded).
---@return boolean
function Launchers:Active()
  return self.collecting
end

---One line for /bmap.
---@return string
function Launchers:Describe()
  if self.collecting then
    return ("addon list on (%d entries)"):format(#self:Entries())
  end
  return "addon list off: " .. self.why
end

table.insert(ns.Minimap.onActivate, function()
  if not ns.DB.show.launchers then
    Launchers.why = "its setting is off"
    return
  end
  local other = ns.Compat:Other("buttons")
  if other then
    Launchers.why = other .. " is collecting the buttons"
    ns.Compat:PromptSoon("buttons", other)
    return
  end
  Launchers.collecting = true
  collect()
  -- Addons that make their buttons a little after login.
  C_Timer.After(5, collect)
  local dbIcon = lib("LibDBIcon-1.0")
  if dbIcon then
    dbIcon.RegisterCallback(Launchers, "LibDBIcon_IconCreated", function(_, button)
      putAway(button)
    end)
  end
  ns.Around:Apply()
end)
