local ADDON_NAME, ns = ...

-- Which holidays are on today, so their quests show while they run (docs/design/available-quests.md).
-- Questie keeps its own date tables (Database/Corrections/Holidays/QuestieEvent.lua); here the game's
-- calendar says: today's events of the HOLIDAY kind. Their titles are matched against Questie's event
-- names (Data/QuestieEvents.lua: "Darkmoon Faire", "Winter Veil", ...) by containment, which covers
-- the calendar's longer titles ("Feast of Winter Veil", "Midsummer Fire Festival").
--
-- Limits (recorded in the design doc): titles are localised, so on a non-English client no holiday
-- matches and their quests stay hidden, as before this existed. The calendar is asked once a session
-- (OpenCalendar, as Questie does) and read again on its updates and at the daily reset.

local Holidays = {
  active = {},  -- [Questie event name] = true
}
ns.Holidays = Holidays

local EVENT_NAMES = {}  -- the event names in Data/QuestieEvents.lua, lower case -> as written
for _, name in pairs(ns.QuestieEvents) do
  EVENT_NAMES[name:lower()] = name
end

---Is this Questie event (Data/QuestieEvents.lua) on today?
---@param name string
---@return boolean
function Holidays:Active(name)
  return self.active[name] == true
end

local function read()
  local today = C_DateAndTime.GetCurrentCalendarTime()
  local found = {}
  for i = 1, C_Calendar.GetNumDayEvents(0, today.monthDay) do
    -- apiguard: allow a secret title (chat messaging lockdown) is checked with issecretvalue and skipped
    local event = C_Calendar.GetDayEvent(0, today.monthDay, i)
    local title = event and event.title
    -- Secret while chat messaging is locked down (CalendarDocumentation.lua: GetDayEvent): skipped.
    if event and event.calendarType == "HOLIDAY" and type(title) == "string" and not issecretvalue(title) then
      local lower = title:lower()
      for key, name in pairs(EVENT_NAMES) do
        if lower:find(key, 1, true) then
          found[name] = true
        end
      end
    end
  end
  local changed = false
  for name in pairs(found) do
    changed = changed or not Holidays.active[name]
  end
  for name in pairs(Holidays.active) do
    changed = changed or not found[name]
  end
  if changed then
    Holidays.active = found
    ns.Available:Refresh()
  end
end

ns.Events:On("PLAYER_LOGIN", function()
  C_Calendar.OpenCalendar()  -- asks the server for this month's events: CALENDAR_UPDATE_EVENT_LIST
  -- A holiday can start or end at the daily reset while you play.
  C_Timer.After(C_DateAndTime.GetSecondsUntilDailyReset() + 60, function()
    C_Calendar.OpenCalendar()
  end)
end)
ns.Events:On("CALENDAR_UPDATE_EVENT_LIST", read)
