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

## Also in this phase

- Sorting (phase 3) switches from the single marker to these better distances, through the same
  hysteresis.
- `/qm where` debug command.

## Open questions

1. **Focus:** the spec says "clicking a card makes it the focused quest (big arrow)" but also "no
   large standalone arrow". Proposal: clicking a card focuses it by setting Blizzard's own waypoint
   (the in-world beacon and map pin) on its target, instead of a big arrow of ours. One click, the
   game's native navigation, no extra UI. Optional setting, off = clicking does nothing.
2. **Update rate:** 10 per second is smooth for walking and cheap. Fine, or do you want it
   smoother (20)?

## In-game test (after build)

1. `/qm where` next to a creature: bearing and distance look right (verifies the axes).
2. Walk around a quest area: the arrow tracks smoothly, distance counts down.
3. Enter the area: diamond, row highlighted. Leave: arrow again.
4. Two packs of mobs at similar distances: no flip-flopping.
5. A quest whose turn-in is in another zone: the zone name shows.
6. Enter a building/instance: arrows disappear, no errors.
