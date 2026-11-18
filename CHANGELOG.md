**Questmarker is now BubbleQuest**, the first of the BubbleSuite addons. Your settings, profiles and
pins carry over by themselves on your first login. A small "Questmarker (now BubbleQuest)" entry stays
in your AddOns list for a few releases to hand them over; leave it enabled. The command is `/bq` now
(`/qm` still works).

## What's new

### Quests on the map

- Quest areas on the world map: where each tracked quest's objectives are, shaded in one colour per
  quest (matched by a strip on its card) and a shade per objective, with a "?" at the turn-in of ready
  quests where the game doesn't show one. Hover an area for what's there, with your party's progress
  when you're grouped; click it, or a "?", to open the quest in your quest log
- Hovering a card, one of its objectives, or a quest in the quest log lights its areas up and draws a
  dotted line from you to where it takes you (to the turn-in once the quest is ready)
- The same areas on the minimap, plus a faint dotted guide line toward the quest you're hovering, your
  first pinned quest, or else the top card
- Quests you can pick up, on the world map and minimap (needs QuestieDB, now a required dependency on
  CurseForge; Questie itself isn't needed): a "!" at each quest giver (blue: repeatable), hover for its
  quests. Quests started by a drop (like Furlbrow's Deed) get a smaller bronze "!" where the mobs are;
  hover it to see their area and what to loot. Low-level quests and drop quests each have a toggle.
  Without QuestieDB, they still show, from BubbleQuest's own data (fewer checks)
- Holiday quests (Darkmoon Faire, Hallow's End, Winter Veil, ...) show while the holiday is on, read
  from the game's calendar (English clients)
- Talking to a quest giver corrects the map: a "!" for a quest they don't actually offer you goes away
  (it comes back after a level-up, a turn-in or the daily reset)
- Town services on the world map, each toggled from the map button's "Town services" menu: flight
  master, innkeeper, banker, auctioneer, repair, mailbox, weapon master, stable master, battlemaster,
  and every class's and profession's trainers. On by default: flight master, innkeeper, auctioneer,
  mailbox, your class's trainers, and the trainers of professions you have (a profession you learn
  switches its trainers on)
- Quest givers and town icons show on zone maps; on continent maps only if you switch that on
- Overlapping icons on the world map (a "?" under a trainer, quest givers side by side) glide into a row
  above the spot when you hover them, each with its own tooltip and a line down to where it is
- A BubbleQuest button on the world map (under Blizzard's, or in the same column as Questie's): click
  for a menu of what BubbleQuest shows on the maps
- Map settings: area opacity and size, icon size, minimap areas and the guide line, each with its own
  toggle

### The tracker

- Ready quests get their own "Ready to turn in" section: on top when you're nearer a turn-in than an
  objective (at a hub), under this zone's quests when you're out questing. The "Turn-ins first" sort
  mode is gone (the section does its job)
- Resize the tracker: unlock it and drag the bottom-right corner. This zone's cards fill the height
  you set (instead of "Cards for this zone"); unlocked the panel stays that size, locked it shrinks to
  fit. Right-click the corner for the default size
- Clearer section headers (Ready to turn in, Camping, Elsewhere, ...) with an open/closed arrow, and a
  proper collapse button on each card. Headers never scroll out of view: ones below dock at the bottom
  of the tracker, so a collapsed "Hidden" or "Elsewhere" is always one click away
- Progress bars take each objective's map colour
- Drop chances in tooltips: "Dropped by Gray Forest Wolf (45%), Prowler (30%)" (how often a kill drops
  it at all), and on drop-started quests on the map
- Picking up a single object (like Downstream's saw): "here" only within 5 yards, so the arrow guides
  you to the spot
- Arrow colours: green up close, yellow around 200 yards, orange around 500, red far off
- Hold Ctrl to hide BubbleQuest's tooltips (cards, map and minimap areas, buttons); let go to get the
  one under the cursor back

### Groups

- Cards show "+2" when party members don't have that quest and could take it (hover for who, click to
  share). It leaves out who can't: too low level, wrong class or race, and, when they run BubbleQuest
  too, already completed, an earlier quest missing, or a full quest log
- "Share next" in the tracker's header: shares the next quest in this zone someone lacks, and skips
  straight on when nobody can take it, saying why in chat ("Shima: already completed"). The button
  dims while it waits for your party's replies, so you can see when it's ready for the next click

### Profiles

- Profiles in the settings window: every character uses Global (one shared layout) unless you make a
  profile of its own. New profiles start as a copy of the current one; copy, delete and reset are
  there too. Pins, hidden quests and trainers stay per character either way

## Fixes

- The card order could stay wrong until you'd walked 100 yards (a quest 218 yd away above one at
  167 yd); it now re-sorts as soon as a card is clearly closer than the one above it
- A spot learned in play (where you stood when hovering an object) could pull an arrow away from the
  real spawn; learned spots now only fill in where the databases know nothing
- The resize corner is hidden while the tracker is minimized (it covered the header's buttons, and
  pressing it shrank the tracker to almost nothing)
