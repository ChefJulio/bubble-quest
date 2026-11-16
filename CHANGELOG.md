## What's new

- Resize the tracker: unlock it and drag the bottom-right corner to set the width and the most it may
  grow (right-click the corner for the default size)
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
  quest (matched by a strip on its card), with a "?" at the turn-in of ready quests. Hover an area for
  what's there; hovering a card, one of its objectives, or a quest in the quest log lights its areas up
- The same areas on the minimap, plus a faint dotted guide line toward the quest you're hovering, your
  first pinned quest, or else the top card
- Map settings: area opacity and size, minimap areas and the guide line, each with its own toggle

## Fixes

- Arrows skipped nearby groups of a mob that lives all over a zone (one dense starting-area patch made
  every normal group look too small to count); only lone strays of 1-2 spawns are ignored now
