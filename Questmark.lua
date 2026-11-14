local ADDON_NAME, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name == ADDON_NAME then
    QuestmarkDB = QuestmarkDB or {}
    ns.db = QuestmarkDB
    self:UnregisterEvent("ADDON_LOADED")
  end
end)

SLASH_QUESTMARK1 = "/questmark"
SLASH_QUESTMARK2 = "/qm"
SlashCmdList.QUESTMARK = function(msg)
  print("Questmark loaded.")
end
