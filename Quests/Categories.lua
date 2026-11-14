local ADDON_NAME, ns = ...

-- Quest categories (spec, Quest categories). Classification, first match wins:
--   1. manual overrides (Data/CategoryOverrides.lua)
--   2. Dungeon: the game's quest tag 81 (Dungeon) / 62 (Raid), or forever-db's type
--   3. the quest-log header the game files the quest under:
--      a class name (from the client, any language) -> Class
--      a name in HEADERS -> Camping / Profession / Seasonal / PetBattle
--   4. Class: forever-db's class mask is set (the quest is restricted to some classes)
--   5. Repeatable: daily/weekly frequency, Recurring classification, or forever-db's flag
--   6. Normal
--
-- STOPGAP: HEADERS is English. On other client languages, step 3 matches only class names; the rest
-- falls through to later rules until the list is localized.

local Categories = {}
ns.Categories = Categories

-- Display order, labels, and default behaviour (profile.categories overrides).
Categories.ORDER = { "Normal", "Dungeon", "Class", "Profession", "Camping", "Seasonal", "Repeatable", "PetBattle" }
Categories.LABELS = {
  Normal = "Normal",
  Dungeon = "Dungeons",
  Class = "Class quests",
  Profession = "Professions",
  Camping = "Camping",
  Seasonal = "Seasonal & events",
  Repeatable = "Repeatable",
  PetBattle = "Pet battles",
}
Categories.DEFAULT_MODES = {
  Normal = "show",
  Dungeon = "show",
  Class = "show",
  Profession = "separate",
  Camping = "separate",
  Seasonal = "separate",
  Repeatable = "separate",
  PetBattle = "separate",
}

local TAG_DUNGEON, TAG_RAID = 81, 62

local HEADERS = {
  Camping = "Camping",

  Alchemy = "Profession", Blacksmithing = "Profession", Cooking = "Profession", Enchanting = "Profession",
  Engineering = "Profession", ["First Aid"] = "Profession", Fishing = "Profession", Herbalism = "Profession",
  Leatherworking = "Profession", Mining = "Profession", Skinning = "Profession", Tailoring = "Profession",
  Jewelcrafting = "Profession", Inscription = "Profession", Archaeology = "Profession",

  Seasonal = "Seasonal", ["Lunar Festival"] = "Seasonal", ["Love is in the Air"] = "Seasonal",
  Noblegarden = "Seasonal", ["Children's Week"] = "Seasonal", ["Midsummer"] = "Seasonal",
  ["Midsummer Fire Festival"] = "Seasonal", ["Harvest Festival"] = "Seasonal", ["Hallow's End"] = "Seasonal",
  Brewfest = "Seasonal", ["Day of the Dead"] = "Seasonal", ["Pilgrim's Bounty"] = "Seasonal",
  ["Feast of Winter Veil"] = "Seasonal", ["Winter Veil"] = "Seasonal", ["Darkmoon Faire"] = "Seasonal",

  ["Pet Battles"] = "PetBattle", ["Pet Battle"] = "PetBattle",
}

local classNames
local function isClassName(text)
  if not classNames then
    classNames = {}
    for _, isFemale in ipairs({ false, true }) do
      for _, name in pairs(LocalizedClassList(isFemale) or {}) do
        classNames[name] = true
      end
    end
  end
  return classNames[text] == true
end

---@param quest table from ns.QuestLog
---@return string category one of Categories.ORDER
---@return string rule which rule decided it (for /qm quest)
function Categories:For(quest)
  local questID = quest.questID
  local override = ns.CategoryOverrides[questID]
  if override then
    return override, "override"
  end

  local record = ns.ForeverData:Quest(questID)
  if quest.tagID == TAG_DUNGEON or quest.tagID == TAG_RAID then
    return "Dungeon", "game tag"
  end
  if record and (record.type == TAG_DUNGEON or record.type == TAG_RAID) then
    return "Dungeon", "forever-db type"
  end

  local header = quest.group
  if header then
    if isClassName(header) then
      return "Class", "header"
    end
    if HEADERS[header] then
      return HEADERS[header], "header"
    end
  end

  if record and record.classes and record.classes ~= 0 then
    return "Class", "forever-db classes"
  end

  if (quest.frequency or 0) ~= 0 then
    return "Repeatable", "frequency"
  end
  if quest.classification == Enum.QuestClassification.Recurring then
    return "Repeatable", "classification"
  end
  if record and record.repeatable then
    return "Repeatable", "forever-db repeatable"
  end
  return "Normal", "default"
end

---"show" | "separate" | "hide" for a category, from the profile.
function Categories:Mode(category)
  return ns.DB.profile.categories[category] or self.DEFAULT_MODES[category] or "show"
end
