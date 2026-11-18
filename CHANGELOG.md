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
