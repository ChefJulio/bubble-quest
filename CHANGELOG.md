## What's new

- Cards are sectioned by zone: your zone's section on top, then one per other zone, nearest first
  (this replaces "Elsewhere"). With Smart sorting, entering a zone opens its section and closes the
  others; you can still open or close any by hand
- Ready quests are back among the others, sorted by the distance to their turn-in (the separate
  "Ready to turn in" section is gone: the zone sections do its job). They keep their green "Turn in
  to ..." line
- "Unhide all" at the end of the Hidden list (click twice)

- Quests on the game's tooltips. Hover a quest giver to see the quests it offers you (the same ones
  as the map's "!"), or the NPC a ready quest goes to for "? [10] Downstream  Ready". Items say which
  quest they start ("Starts a quest", greyed once done) and which quest in your log needs them, with
  your count. Each has a toggle under Tooltips in the settings. Not in combat: the game hides that
  data then

- Quest colours on the maps are picked against the quests around them: a new quest takes the colour
  most unlike its neighbours' (quests far apart can share one), keeps it, and keeps it across logins.
  Each objective's shade stays closer to its quest's colour, so it no longer drifts towards another
  quest's

## Fixes

- Quest givers showed two "!" on the minimap, the game's and BubbleQuest's, a few pixels apart.
  Where the game draws its own (the middle of the minimap), BubbleQuest now leaves the "!" to it, as
  on Blizzard's minimap. Quests started by a drop, and low-level ones the game hides, still get ours
- Turn-in "?" on the minimap: where the game draws its own, BubbleQuest leaves it to the game, and
  takes over right where the game's stops near the edge (no gap, no doubled "?")
- The minimap showed several "?" for one turn-in where the databases know more than one spot; now
  one, at the spot nearest you. Quest givers' "!" that would overlap (a giver's spawns, or givers side
  by side) share one icon, whose tooltip lists all their quests
- A turn-in "?" near the corner of a square minimap could go missing: the game doesn't draw its own
  "?" in the corners, and BubbleQuest skipped it there too
