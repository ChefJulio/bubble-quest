local ADDON_NAME, ns = ...

-- Fonts for the tracker (setting: font face and text size). The tracker's text uses Questmark's own
-- font objects, created here as copies of the Blizzard fonts it used before; changing the font sets
-- these objects once and every font string using them follows.
--
-- Faces come from LibSharedMedia-3.0 when any addon has loaded it (most setups have it: BugSack, DBM,
-- Details, Plater, Prat, MSBT embed it), which lists every font any addon registered, e.g. MSBT's
-- "MSBT Porky". Questmark doesn't bundle it; without it the list is WoW's four built-in fonts. A face
-- registered after Questmark loads (MSBT loading later) is applied when it registers.

local DEFAULT = "default"

local BUILTIN = {
  { "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
  { "Arial Narrow", "Fonts\\ARIALN.TTF" },
  { "Morpheus", "Fonts\\MORPHEUS.TTF" },
  { "Skurri", "Fonts\\skurri.ttf" },
}

local Fonts = {
  -- name = Blizzard font object it starts as a copy of
  objects = {
    { name = "QuestmarkHeaderFont", base = "ObjectiveTrackerHeaderFont" },
    { name = "QuestmarkLineFont", base = "ObjectiveTrackerLineFont" },
    { name = "QuestmarkSmallFont", base = "GameFontNormalSmall" },
    { name = "QuestmarkSmallHighlightFont", base = "GameFontHighlightSmall" },
  },
}
ns.Fonts = Fonts

local function sharedMedia()
  local libStub = rawget(_G, "LibStub")
  return libStub and libStub("LibSharedMedia-3.0", true)
end

-- Created at load, before any frame uses them by name. Each remembers its default face, size, flags.
for _, object in ipairs(Fonts.objects) do
  object.font = CreateFont(object.name)
  object.font:CopyFontObject(object.base)
  object.path, object.size, object.flags = object.font:GetFont()
end

---The file for a face name, or nil for the game default (or an unknown face).
---@param face string
---@return string?
function Fonts:Path(face)
  if not face or face == DEFAULT then
    return nil
  end
  local media = sharedMedia()
  local path = media and media:Fetch("font", face, true)
  if path then
    return path
  end
  for _, builtin in ipairs(BUILTIN) do
    if builtin[1] == face then
      return builtin[2]
    end
  end
  return nil
end

---{ value, label } choices for the font setting: game default, then every known face.
---@return table[]
function Fonts:Options()
  local options = { { DEFAULT, "Game default" } }
  local media = sharedMedia()
  local names = {}
  if media then
    for _, name in ipairs(media:List("font")) do
      names[#names + 1] = name
    end
  else
    for _, builtin in ipairs(BUILTIN) do
      names[#names + 1] = builtin[1]
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    options[#options + 1] = { name, name }
  end
  return options
end

---Set every Questmark font object from the profile (face, size percent), then relayout.
function Fonts:Apply()
  local settings = ns.DB.profile.font
  local path = self:Path(settings.face)
  local scale = (settings.scale or 100) / 100
  for _, object in ipairs(self.objects) do
    local size = math.floor(object.size * scale + 0.5)
    -- SetFont returns false when the file can't be loaded: fall back to the default face.
    if not (path and object.font:SetFont(path, size, object.flags)) then
      object.font:SetFont(object.path, size, object.flags)
    end
  end
  ns.Bus:Fire("FontsChanged")
end

-- A face registered after we loaded (another addon loading later) may be the saved one.
local function watchSharedMedia()
  local media = sharedMedia()
  if not media then
    return
  end
  media.RegisterCallback(Fonts, "LibSharedMedia_Registered", function(_, mediaType, key)
    if mediaType == "font" and ns.DB.profile and key == ns.DB.profile.font.face then
      Fonts:Apply()
    end
  end)
end

ns.Events:On("PLAYER_LOGIN", function()
  watchSharedMedia()
  Fonts:Apply()
end)
