local ADDON_NAME, ns = ...

-- Fonts for the tracker (setting: font face and text size). The tracker's text uses Questmarker's own
-- font objects, created here as copies of the Blizzard fonts it used before; changing the font sets
-- these objects once and every font string using them follows.
--
-- Faces come from LibSharedMedia-3.0 when any addon has loaded it (most setups have it: BugSack, DBM,
-- Details, Plater, Prat, MSBT embed it), which lists every font any addon registered, e.g. MSBT's
-- "MSBT Porky". Questmarker doesn't bundle it; without it the list is WoW's four built-in fonts. A face
-- registered after Questmarker loads (MSBT loading later) is applied when it registers.

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
    { name = "QuestmarkerHeaderFont", base = "ObjectiveTrackerHeaderFont" },
    { name = "QuestmarkerLineFont", base = "ObjectiveTrackerLineFont" },
    { name = "QuestmarkerSmallFont", base = "GameFontNormalSmall" },
    { name = "QuestmarkerSmallHighlightFont", base = "GameFontHighlightSmall" },
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

local previewObjects = {}  -- [font file] = Font object, for drawing menu entries in their own font
local previewCount = 0     -- names them uniquely (CreateFont names are global)

---A Font object in the given face at menu size, created once per face. Menu entries can't take
---SetFont (Blizzard_Menu/Compositor.lua:166-169 disallows it on their font strings), only
---SetFontObject.
---@param path string font file
---@return table
function Fonts:PreviewObject(path)
  local object = previewObjects[path]
  if not object then
    previewCount = previewCount + 1
    object = CreateFont(("QuestmarkerPreviewFont%d"):format(previewCount))
    object:CopyFontObject("GameFontHighlight")
    local _, size = object:GetFont()
    object:SetFont(path, size or 12, "")
    previewObjects[path] = object
  end
  return object
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

---Set every Questmarker font object from the profile (face, size percent), then relayout.
function Fonts:Apply()
  local settings = ns.DB.profile.font
  local path = self:Path(settings.face)
  local scale = (settings.scale or 100) / 100
  for _, object in ipairs(self.objects) do
    local size = math.floor(object.size * scale + 0.5)
    local flags = object.flags or ""
    -- A Font object's SetFont returns nothing (unlike a FontString's, which returns success:
    -- SimpleFontAPIDocumentation.lua:199 vs SimpleFontStringAPIDocumentation.lua:500), so treating
    -- its result as a failure put the default face straight back. Ask the object what it holds.
    if path then
      object.font:SetFont(path, size, flags)
    end
    if not path or not object.font:GetFont() then
      object.font:SetFont(object.path, size, flags)
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
