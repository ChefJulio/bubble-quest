# Town services on the world map

Part 3 of the map work, 2026-11-17. Questie's "Townsfolk" menu, rebuilt on what Questmarker already reads.

## What and from where

| Service | How it's found |
| --- | --- |
| Flight master, innkeeper, banker, auctioneer, repair, stable master, spirit healer, battlemaster | QuestieDB NPC flags (`LibQuestieDB.Enum.npcFlags`, as Questie's Townsfolk.lua) |
| Class trainer (yours) | NPC subtitle "<your class> Trainer" (the in-game title, e.g. "Warrior Trainer") |
| Profession trainers, one toggle per profession | NPC subtitle "<profession> Trainer" (any trainer subtitle that isn't a class) |
| Weapon master | NPC subtitle "Weapon Master" |
| Mailbox | forever-db objects of type 19 (mailbox) |

Questie keeps hand-made ID lists for trainers, weapon masters and mailboxes; reading the subtitle and the
object type finds every one in the data, Forever's new ones included, with nothing to maintain.

Friendly NPCs only (QuestieDB's friendlyToFaction), except spirit healers. Built once in the background,
only once a service is switched on.

## How it's shown

On the world map, and in quest views (UI/QuestView.lua) wherever Blizzard's own tracking doesn't draw
them: BubbleMap's map window (`BubbleQuestAPI.CreateQuestView(frame, { services = true })`, or
`{ services = { exclude = { flight = true } } }` where BubbleMap draws its own flight points), and the
minimap only while BubbleMap has Blizzard's hidden (`SetMinimapZoom`'s `gameHidden`; review: "the
townsfolk POI aren't visible at all on our in-house map"). With Blizzard's minimap showing, its tracking
menu handles them there, as before. Blizzard's minimap-tracking icons (`Interface\Minimap\tracking\*`), close spawns merged, a tooltip with the NPC's
name and title. Toggled from the map button's menu ("Town services" submenu). On by default (review):
flight master, innkeeper, auctioneer, mailbox, class trainer. Profession trainers are per character:
each profession you have switches its trainers on the first time it's seen (login, or learning one:
SKILL_LINES_CHANGED, by skill line ID so any language works); turned off, it stays off.

## Remaining (recorded)

- Vendors by what they sell (food, drink, ammo, reagents, poisons, bags): Questie builds these from item
  lists; a bigger job, later.
- Without QuestieDB: no NPC flags or subtitles in forever-db's NPC records beyond the subtitle, so only
  mailboxes and subtitle-based trainers could work; not done yet.
- Subtitles are matched in English, like holidays.
