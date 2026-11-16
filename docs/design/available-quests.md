# Available quests on the maps

Proposed 2026-11-16. Not started. Part 2 of the map work (part 1: quest areas, minimap, guide line).
Then part 3, town services, on the same menu. Research: QuestieDB, Questie's AvailableQuests,
LibForeverData and the Forever API (file references below are from that pass).

## Goal

Quest givers you can pick up from, on the world map and the minimap, as Questie does, with fewer
false promises: never mark something "available" that isn't, and say plainly when a quest starts from
a drop. Toggled from a map button with a Questie-style menu.

## Data

| Source | When | What it can do |
| --- | --- | --- |
| QuestieDB (LibQuestieDB, contract 4) | Questie installed and ready | Everything: starters (NPC, object, item), finishers, levels, race/class masks, prerequisites (single/group), exclusiveTo, nextQuestInChain, breadcrumbs, skill, reputation, max level, parent/child, daily/weekly flags, NPC spawns and faction, item droppers |
| LibForeverData (bundled) | Always (fallback) | Starters (npc/object/item), levels, side, race/class, prerequisites (all/any, breadcrumb), repeatable, item drop chances. No exclusiveTo, chains, skill, reputation, daily/weekly |
| Client | Always | Completed quests (`C_QuestLog.GetAllCompletedQuestIDs`, `IsQuestFlaggedCompleted`), trivial range (`GetTrivialRange`), quests in the log. `C_QuestLine.GetAvailableQuestLines(uiMap)` returns quest-giver positions per map (Blizzard's own map uses it) but may not cover classic quests: probe in game first (`/qm offers`) |

Hidden/blacklisted quests (event, removed, unobtainable) are Questie-internal, not in QuestieDB.
Done: tools/extract_questie_hidden.py evaluates Questie's QuestieQuestBlacklist.lua for Forever (Era
rules) into Data/QuestieHidden.lua (hidden, or map-only), plus its Scourge Invasion and AQ War Effort
lists; re-run when Questie updates it.

Stopgap, remaining: holiday quests (zoneOrSort holiday categories) are always hidden. Questie shows
them while the event runs (QuestieEvent's dates); event awareness is still to do.

Forever race masks use bits 32-33 (Skyborne): test with arithmetic, `(mask % (2 * bit)) >= bit`, not
`bit.band` (truncates to 32 bits). QuestieDB's `startedBy` is sparse (`{[3] = {1972}}`): index 1-3,
never `ipairs`. Every QuestieDB read decodes CBOR: cache on our side.

## Which quests are available

A quest is shown when all hold (QuestieDB.IsDoable's checks, ported; the fallback skips what its data
lacks):

1. Not completed, not in the log (failed ones in the log: shown, to retake), not hidden by the player.
2. Level: `requiredLevel <= player level` (0 means the quest level), within `requiredMaxLevel`; trivial
   (grey) quests only with "Trivial quests" on. Scaling quests (level -1) use the player's level.
3. Race, class (masks), side; the starting NPC not hostile.
4. Prerequisites: any of `preQuestSingle` done; all of `preQuestGroup` done (or one of each one's
   `exclusiveTo`); `parentQuest` active.
5. Not superseded: no `exclusiveTo` quest done or active; `nextQuestInChain` not done or active;
   breadcrumbs hidden once their target is done or active.
6. Skill and reputation requirements met; dailies: once per day.
7. A quest the NPC didn't offer when you talked to them (gossip/greeting lists what's really offered):
   hidden until the daily reset, as Questie does. This also corrects our own mistakes as you play.

Recomputed on QUEST_LOG_UPDATE batches (accepted, completed, abandoned), level-up, skill and
reputation changes; never per frame. Built per zone in a coroutine, a few hundred quests per frame,
cached until one of those events.

## How they're drawn

- NPC and object starters: Blizzard's yellow "!" (atlas checked at runtime, fallback texture), grey for
  trivial quests, blue for repeatable/daily. Same size setting as the turn-in "?". One icon per
  starter spawn, merged when close; several quests from one NPC share one icon.
- Hover: the area tooltip's style. NPC name, then each quest "[12] Title" with its level colour and
  "(Daily)" etc.; in a group, who in your party could take it (the "+N" logic).
- Minimap: the same icons, clipped like the areas.

### Quests started by an item drop (handle with care)

Quest 184, Furlbrow's Deed: started by item 1972, which Defias mobs drop at a few percent. Questie puts
the normal "!" on every one of those mobs and labels them "(Available)", as if the mob gave the quest.
Proposed instead:

- A separate toggle, "Quests from drops", and a distinct look: no "!" on the mobs. The droppers' area,
  in a faint neutral tint, with a small loot-bag "!" at its centre (one per area, not one per mob).
- The tooltip says what it is: "Furlbrow's Deed: loot a Furlbrow's Deed from Defias Thugs (3%) to start
  this quest". Drop chance from LibForeverData when known.
- Hidden once you have the item: then it's in your bags (a card hint could say "use it to start the
  quest": later).
- Hostile droppers only (a vendor that sells the item is a vendor, not a dropper).

## The map menu

A button on the world map, under Blizzard's and Questie's buttons (Questie uses the shared
Krowi_WorldMapButtons library, which stacks every addon's button; using it too keeps them in a
column). Left-click: show or hide Questmarker's map drawing; right-click: the menu.

Menu (Blizzard's MenuUtil, verified before use): Quest areas, Turn-ins, Available quests, Trivial
quests, Quests from drops; later (part 3) town services: Flight master, Innkeeper, Banker, Auctioneer,
Repair, Mailbox, trainers and vendors. Each mirrors a setting in the Map section.

## Coexistence with Questie

If Questie draws available quests too, both sets of "!" overlap. Questmarker's "Available quests" is
off by default while Questie's own available-quest icons are on (read from its settings, guarded),
with a one-line note in the menu; on otherwise.

## Decisions (review, 2026-11-16)

1. Quests from drops: the honest area above, not a "!" on every dropper.
2. Questmarker is heading for replacing Questie, not sitting beside it. Available quests on by default;
   if Questie's own available-quest icons are on, a one-time prompt offers to turn them off (as with
   its tracker). The "Coexistence" section above is superseded.
3. Levels: Questie's window (required level met; trivial quests only with "Trivial quests" on).

## Prerequisite: QuestieDB without Questie

Data/QuestieData.lua needs Questie itself (Questie.API.isReady, Questie's ZoneDB for area -> uiMap).
QuestieDB ships as its own addon and publishes everything used here, including the area -> uiMap table
(`LibQuestieDB.Support.Get("ZoneDB").private.areaIdToUiMapId`, untested). Switch the adapter to depend
on QuestieDB alone (Questie's ZoneDB only as a fallback), so players can drop Questie and keep its
data; LibForeverData stays the fallback when QuestieDB is missing.
