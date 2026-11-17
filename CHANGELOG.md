## What's new

- Ready quests get their own "Ready to turn in" section: on top when you're nearer a turn-in than an
  objective (at a hub), under this zone's quests when you're out questing. The "Turn-ins first" sort
  mode is gone (the section does its job)
- Resize the tracker: unlock it and drag the bottom-right corner. This zone's cards fill the height
  you set (instead of "Cards for this zone"); unlocked the panel stays that size, locked it shrinks to
  fit. Right-click the corner for the default size
- Quests you can pick up, on the world map and minimap (needs QuestieDB, now a required dependency on
  CurseForge; Questie itself isn't needed): a "!" at each quest giver (blue: repeatable), hover for its
  quests. Quests started by a drop (like Furlbrow's Deed) get a smaller bronze "!" where the mobs are;
  hover it to see their area and what to loot. Low-level quests and drop quests each have a toggle
- Holiday quests (Darkmoon Faire, Hallow's End, Winter Veil, ...) show while the holiday is on, read
  from the game's calendar (English clients)
- Drop chances in tooltips: "Dropped by Gray Forest Wolf (45%), Prowler (30%)" (how often a kill drops
  it at all), and on drop-started quests on the map
- Without QuestieDB installed, quests to pick up still show, from Questmarker's own data (fewer checks)
- Talking to a quest giver corrects the map: a "!" for a quest they don't actually offer you goes away
  (it comes back after a level-up, a turn-in or the daily reset)
- Town services on the world map, each toggled from the map button's "Town services" menu: flight
  master, innkeeper, banker, auctioneer, repair, mailbox, your class trainer, weapon master, stable
  master, battlemaster, spirit healer, and profession trainers one by one. On by default: flight
  master, innkeeper, auctioneer, mailbox, class trainer, and the trainers of professions you have
  (a profession you learn switches its trainers on)
- A Questmarker button on the world map (under Blizzard's, or in the same column as Questie's): click
  for a menu of what Questmarker shows on the maps
- Picking up a single object (like Downstream's saw): "here" only within 5 yards, so the arrow guides
  you to the spot
- In a group, hovering quest areas on the map or minimap shows your party's progress on that quest too
- Section headers never scroll out of view: ones below dock at the bottom of the tracker, so a
  collapsed "Hidden" or "Elsewhere" is always one click away
- Profiles in the settings window: every character uses Global (one shared layout) unless you make a
  profile of its own. New profiles start as a copy of the current one; copy, delete and reset are
  there too. Pins, hidden quests and trainers stay per character either way
- Class trainers are a list like profession trainers (your own class on), so you can look up any
  class's trainers
- Hold Ctrl to hide Questmarker's tooltips (cards, map and minimap areas, buttons); let go to get the
  one under the cursor back
- Clearer section headers (Ready to turn in, Camping, Elsewhere, ...) with an open/closed arrow, and a
  proper collapse button on each card
- In a group, cards show "+2" when party members don't have that quest and could take it (hover for
  who, click to share). It leaves out who can't: too low level, wrong class or race, and, when they run
  Questmarker too, already completed, an earlier quest missing, or a full quest log
- "Share next" in the tracker's header: shares the next quest in this zone someone lacks, and skips
  straight on when nobody can take it (already done, not eligible, ...)

- Timed quests show a countdown under the title ("Time left 2:12": orange under a minute, red under
  20 seconds) and in the tooltip, and go to the top of the tracker while the timer runs
- Quests with several objectives: each unfinished objective gets its own arrow and distance, as their
  areas can be far apart; the tooltip shows each one's distance and direction too ("180 yd NE")

- Quest areas on the world map: where each tracked quest's objectives are, shaded in one colour per
  quest (matched by a strip on its card), with a "?" at the turn-in of ready quests where the game
  doesn't show one. Hover an area for what's there; hovering a card, one of its objectives, or a quest
  in the quest log lights its areas up and draws a dotted line from you to where it takes you
- The same areas on the minimap, plus a faint dotted guide line toward the quest you're hovering, your
  first pinned quest, or else the top card
- Map settings: area opacity and size, minimap areas and the guide line, each with its own toggle

## Fixes

- A spot learned in play (where you stood when hovering an object) could pull an arrow away from the
  real spawn; learned spots now only fill in where the databases know nothing

- The card order could stay wrong until you'd walked 100 yards (a quest 218 yd away above one at
  167 yd); it now re-sorts as soon as a card is clearly closer than the one above it
- The resize corner is hidden while the tracker is minimized (it covered the header's buttons, and
  pressing it shrank the tracker to almost nothing)

- Arrows skipped nearby groups of a mob that lives all over a zone (one dense starting-area patch made
  every normal group look too small to count); only lone strays of 1-2 spawns are ignored now
