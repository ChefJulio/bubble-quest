# Phase 5 design: arrows

Spec, Navigation arrows: every card carries a small live arrow and distance on its title line,
pointing at the nearest unfinished objective (or the turn-in). Minimal by design.

Evidence tags: [Read] verified in the Forever UI source, LibForeverData, or in game; [Assumes] to
confirm in game (each has a debug command or test step).

## What you see

```
 [2] Kobold Camp Cleanup          ^ 140 yd  -     <- arrow + distance, live
     Kill Kobold Vermin                  6/10
 [2] Rascally Rodents             <> here   -     <- inside the area: diamond, row highlighted
   > Collect Stolen Book                  2/8
 [5] Rest and Relaxation          > Goldshire -   <- target in another zone: zone name
     Turn in to Innkeeper Farley
```

- Arrow: Blizzard's own navigation arrow (`Navigation-Tracked-Arrow`, the one the in-world
  beacon uses, rotated with `SetRotation` [Read: Blizzard_QuestNavigation/SuperTrackedFrame.lua:152]).
- In the area: the arrow becomes a green diamond (`Navigation-Tracked-Icon`): a different shape,
  not just a different colour (spec: colourblind-friendly), and the matching objective row lights
  up.
- Indoors / instances (no position): no arrow, no distance.

## Targets

For each card, the target is the nearest *unfinished* objective, or the turn-in when ready.
Where the positions come from, best first:

1. **forever-db spawn points** (world yards, `LibForeverData.Spawns` [Read: Core.lua:12-13]):
   - kill objective: the creature's spawns (matched by name);
   - collect objective: spawns of the creatures or objects that drop it (phase 4's item sources);
   - turn-in: the finishing NPC's spawns.
   Spawn points sit inside the area, so the nearest one is the nearest edge of the area (spec:
   "target the nearest edge, not the centre").
2. **The client's quest marker** (`GetQuestsOnMap`, already used for zones and sorting): one point
   per quest, for everything forever-db has no spawns for, which includes most Forever-new quests.
   Converted to world yards with `C_Map.GetWorldPosFromMapPos`.

**In the area:** within 40 yards of the nearest spawn point (tune in testing). Marker-only targets
never claim "in the area": one point can't tell inside from near.

## Rules (spec)

- **Hysteresis:** the arrow switches to a different spawn point or objective only when the new one
  is at least 20% closer. No flip-flopping between two packs of wolves.
- **Cross-zone:** distances in world yards. If the target is in another zone on the same continent,
  show the zone's name instead of yards (arrow still points). Another continent: zone name, no arrow.
- **Throttle:** one update driver for all cards, 10 times a second, visible cards only. Target point
  lists are built once per quest and rebuilt only on `QuestChanged` / zone change, so a tick is a
  few hundred distance computations at most.
- Not combat state: position and facing aren't restricted [Read: research A4], so arrows update in
  combat too. Arrows never move cards.

## Maths

Player: `UnitPosition("player")` (world yards + map id) and `GetPlayerFacing()` (radians,
0 = north, counter-clockwise) [Read: research A4; TomTom uses the same pair]. Bearing to the
target minus facing = the arrow's rotation.

[Assumes] the axis order: forever-db stores "x north, y west" [Read: forever-db README]; whether
`UnitPosition`'s first value is the same axis is verified first with a debug command
(`/qm where`: your position, the nearest spawn of a creature next to you, and the bearing).

**Verified in game** (`/qm where`, Northshire): `UnitPosition`, `GetWorldPosFromMapPos` and
forever-db agree on (north, west). Rest and Relaxation's turn-in marker converts to (-9463.0, 16.0);
forever-db puts Innkeeper Farley at (-9462.5, 16.0). Bearing to Goldshire 153 degrees left of a
north-facing player, correct. Kobold Camp Cleanup: 4 yd, in area. `SetRotation` turns counter-
clockwise (the preview's up-arrow turned left), matching the maths.

**Fixed after testing:** LibForeverData's `ToUiMap` picks the smallest map rectangle holding a point,
which fails where rectangles overlap at zone borders (Northshire's Defias Thugs came out as Burning
Steppes). Whether a target is in the player's zone is now asked of the client
(`GetMapPosFromWorldPos` with the zone map).

**Arrow art:** Blizzard's arrows (`Navigation-Tracked-Arrow`, `NPE_ArrowUp`, ...) all read as chevrons
or triangles at card size. Questmarker draws its own (`tools/make_arrows.py` -> `Media/Arrows/*.tga`):
arrow (default), dart, thin; plus the minimap arrow and Blizzard's chevron. Setting "Arrow style";
`/qm arrows` previews them.

**Added after review (all verified in game):**

- Arrow colour by distance (green close, yellow, orange, red far or other zone); setting, off = gold.
  The art is white-filled and tinted in game. Camera-relative arrows were asked for but aren't
  possible: no addon API gives the camera's direction (only barbershop/commentator cameras).
- Nameplates mark "here" (`Quests/Nearby.lua`): `C_QuestLog.UnitIsRelatedToActiveQuest`, then the
  unit's tooltip data: `QuestTitle` lines (type 17) carry the quest `id`, `QuestObjective` lines
  (type 8) the objective text and `completed`, the `UnitName` line (type 2) the creature's name
  [Read: `/qm unit` on Kobold Worker and Kobold Vermin]. Secret in combat: skipped, re-read after.
  A quest gaining its first nearby creature is a re-sort event, and sorts as distance 0.
- Learned in play (`Data/Learned.lua`, account-wide): spots where an objective's creatures were seen
  (arrow targets where forever-db has no spawns) and which creatures count for it (Do line: "Loot
  Stolen Book from Kobold Vermin, Kobold Worker"). The spec's phase 8 "where collector", pulled
  forward for Forever-new quests.
- Ready turn-ins jump to the top only within 250 yd (in-zone alone put a 700 yd turn-in on top).
- Progress bar under each card (setting, default on), segmented when progress is a whole-number
  count of 2-20 steps.
- Hover tooltip: description (`GetQuestLogQuestText`, as Blizzard's quest tooltip), every
  objective, all item sources, turn-in, distance, click help.

## Also in this phase

- Sorting (phase 3) switches from the single marker to these better distances, through the same
  hysteresis.
- `/qm where` debug command.

## Clicking a card (decided in review)

The spec's "focused quest (big arrow)" conflicts with its "no large standalone arrow". Decided:
left-clicking a card **highlights the quest and opens the map to it**:

1. `C_SuperTrack.SetSuperTrackedQuestID(questID)`: makes it the game's tracked quest (map highlight,
   in-world beacon). Unrestricted [Read: apiguard].
2. `QuestMapFrame_OpenToQuestDetails(questID)`: Blizzard's own "open the quest log on the map at this
   quest" [Read: Mainline/QuestMapFrame.lua:1179-1183]. It opens the map through
   `WorldMapFrame:HandleUserActionOpenQuestLog`, the normal player path, not the restricted
   `C_Map.OpenWorldMap` [Read: Blizzard_WorldMap.lua:1421-1427]. Loads on Forever: Forever is a
   mainline variant (`QuestMapFrameUtils` is loaded for mainline *excluding camelot*, replaced by a
   camelot version [Read: Blizzard_UIPanels_Game.toc:177-178]).

Out of combat only (a click in combat does nothing): calling Blizzard UI code from an addon can
taint it, which only bites when that code later meets a protected action in combat. Test step 7
checks for that. A setting turns the click off.

Update rate: 10 per second (agreed).

## In-game test (after build)

1. `/qm where` next to a creature: bearing and distance look right (verifies the axes).
2. Walk around a quest area: the arrow tracks smoothly, distance counts down.
3. Enter the area: diamond, row highlighted. Leave: arrow again.
4. Two packs of mobs at similar distances: no flip-flopping.
5. A quest whose turn-in is in another zone: the zone name shows.
6. Enter a building/instance: arrows disappear, no errors.
7. Click a card: the map opens at that quest, highlighted. Close it, then fight something: no
   "action blocked" errors in BugSack.
