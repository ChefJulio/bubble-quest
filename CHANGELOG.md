## Fixes

- Quest givers close to you showed two "!" on the minimap, the game's and BubbleQuest's, a few pixels
  apart. Within the game's own range BubbleQuest now leaves the "!" to the game (and keeps showing the
  ones further out, which the game doesn't mark). `/bq givers` lists the nearest givers and their
  distance
- A turn-in "?" near the corner of a square minimap could go missing: the game doesn't draw its own
  "?" in the corners, and BubbleQuest skipped it there too
