local ADDON_NAME, ns = ...

-- Questmarker_Map: the square minimap made for Questmarker's tracker. Design:
-- docs/design/questmarker-map.md. Talks to Questmarker only through QuestmarkerAPI, never its
-- private namespace.

local API_NEEDED = 1  -- the QuestmarkerAPI version this addon is written against

-- Required by the TOC, so Questmarker has loaded; an older one without the members we use is the case
-- left to catch.
local api = rawget(_G, "QuestmarkerAPI")
ns.enabled = api ~= nil and api.API >= API_NEEDED
ns.API = api

if not ns.enabled then
  print(("|cffffd100Questmarker Map|r is off: it needs a newer Questmarker (API %d, found %s)."):format(
    API_NEEDED, api and tostring(api.API) or "none"))
end
