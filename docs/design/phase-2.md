# Phase 2 design: cards

Spec: "Cards: per-zone card stack with Do/Where from raw objective text; Elsewhere group; collapse."
This is the first visible UI. It reads only from `ns.QuestLog` (phase 1) and its bus events.

Evidence tags: [Read] verified in the Forever UI source or in game; [Assumes] to confirm in game.

## What you see

```
 [2] Nibbled-On Book                      [-]
     Ready to turn in
 [2] Kobold Camp Cleanup                  [-]
     Kill Kobold Vermin                  1/10
 [2] Wolves Across the Border             [-]
     Collect Tough Wolf Meat              3/8
 + Elsewhere (4)
```

- One card per quest in the current zone. Level in brackets, colored by difficulty like the quest
  log (`GetQuestDifficultyColor`, Blizzard Lua [Read: DifficultyUtil.lua:68]).
- A tag after the title when the quest has one: Elite, Dungeon, Group, Raid, PvP (`tagName`).
- `[-]` collapses the card to its title line; `[+]` expands it. Saved per character.
- The title line keeps an empty slot on the right for phase 5's arrow and distance.

## Which quests are "in this zone"

**Decided from `/qm map` in game (Elwynn Forest, Northshire):** `GetQuestsOnMap` is filled on
Forever. On the zone map (1429) it returned both Northshire quests with positions; on the continent
map (1415) it returned them too, each with `mapID = 1429`, its zone. The quest-log header
("Northshire Valley") matched no map name, since Northshire is not a separate map. So:

- **In this zone:** returned by `GetQuestsOnMap(zone map)`, where the zone map is the first map of
  type `Zone` (`Enum.UIMapType.Zone = 3`) up the player's map chain.
- **Elsewhere, grouped by zone:** `GetQuestsOnMap(continent map)` gives each quest's zone map;
  its name is the group heading.
- **No map marker** (e.g. Camping quests): in this zone if its header equals the zone or subzone
  text (`GetSubZoneText()`), otherwise under its header in Elsewhere.
- [Assumes] turn-in-ready quests keep a marker; check in game after build.

The candidates considered:

1. **The client's own map data.** `C_QuestLog.GetQuestsOnMap(uiMapID)` returns the quests with a
   marker on that map, with an x/y position [Read: QuestInfoSharedDocumentation.lua:27-41].
   Asked for the player's map and each parent map (`C_Map.GetBestMapForUnit`, `GetMapInfo`'s
   `parentMapID`). If Forever fills this for its quests, it is exact, and phase 5 gets positions
   for free. [Assumes] it is filled; `/qm map` checks.
2. **Quest-log header names.** A quest's header ("Northshire Valley", "Dun Morogh") matched against
   the names of the player's map chain. Works offline from the log, but headers are not always
   zones ("Camping"), and a subzone header may not match the map name.

**Stopgap:** whichever is used is replaced in phase 4, when forever-db gives every quest its
zone (`quest.zone_area`). The rule lives in one function (`ns.Zone:IsInZone(quest)`) so that
swap touches one place.

## Card content

### Do line (from raw objective text)

Forever's objective text puts the counter first [Read: in game, phase 1 test]. The counter moves
to the right edge, and only rewrites whose meaning is certain are made:

| Objective | Shown as |
| --- | --- |
| `monster` "1/10 Kobold Vermin slain" | "Kill Kobold Vermin" ........ 1/10 |
| `item` "3/8 Tough Wolf Meat" | "Collect Tough Wolf Meat" ...... 3/8 |
| any other type with a counter | text without the counter ........ x/y |
| no counter (`log`, skill, events) | the text as is |

- Rewrites apply on English clients only (they match English words like "slain"); other locales
  show the text with the counter moved. Phase 7's hint data overrides the Do line per objective.
- Finished objectives are dimmed, with a check mark texture.

### Turn-in card

When `readyForTurnIn`: the objective rows are replaced by one green line, "Ready to turn in".
Naming the NPC ("Turn in to Brother Paxton") needs quest-end data: phase 4 (forever-db).

### Quests with no objectives

Some have none (A Visitor to Dun Morogh [Read: phase 1 test]). Not ready: the card shows only its
title line. Ready: the turn-in line.

### Where line

Not in phase 2. Outdoors, Where is phase 5's arrow and distance; indoors and descriptive Where
text come from hint data (phase 7). In the Elsewhere group, the zone heading is the Where.

## Elsewhere group

- One line at the bottom: "+ Elsewhere (N)", collapsed by default.
- Expanded: a small zone heading per zone (the quest-log header), with that zone's cards under it.
- Expanded/collapsed is saved per character.

## Order and when the list changes

- Turn-in cards first (spec, Card behavior), then quest-log order, so the order is stable and
  predictable. Distance ordering arrives with tracking rules (phase 3) and positions (phase 5).
- **Progress updates in place, any time**, combat included: a row's text and counter change, the
  layout doesn't.
- **Cards appear, disappear or move only on `QuestLogChanged` or a zone change, and never in
  combat**: those wait until combat ends (`ns.Combat`). This is the spec's "nothing jumps around"
  rule, not a taint issue; the cards are ordinary frames.
- The `QuestChanged` that follows a fresh `QuestAdded` (objectives arriving a moment after accept
  [Read: phase 1 test]) is not treated as progress.

## Container

- Anchored where Blizzard's tracker sits (right side of the screen), fixed width (~260 px),
  growing downward.
- Movable when unlocked; position saved in the profile. New setting: "Lock card position".
- **Stopgap:** no height limit in phase 2. With many quests in one zone the stack can run off the
  screen until phase 3 adds the visible-card cap (default 5) and the "rest one click away" line.

## Frames

- Plain `Frame`/`FontString`/`Texture`, no secure templates (quest item buttons are phase 9).
- Cards and rows come from a small pool of our own (acquire / release). Blizzard's
  `CreateFramePool` is an alias for `CreateSecureFramePool` on Forever [Read: Pools.lua:857]; ours
  avoids depending on what "secure" means there.
- One rebuild function lays out the whole stack from the current view list; rows update text in
  place on `QuestChanged`.

## Files

| File | Job |
| --- | --- |
| `UI/Pool.lua` | Acquire/release pool |
| `Quests/Zone.lua` | `ns.Zone`: player's map chain, `IsInZone(quest)` (the stopgap rule) |
| `Quests/DoLine.lua` | `ns.DoLine:For(objective)` -> text, counter |
| `UI/Cards/Card.lua` | One card: title line, rows, collapse button, turn-in state |
| `UI/Cards/Stack.lua` | Container, ordering, Elsewhere group, rebuild/defer logic |

## Verified in game (Nov 14, 2026)

Passed: cards and Do lines, difficulty colors, counters updating in place, turn-in card moving to
the top, card removed on turn-in, collapse, drag and lock, settings panel. Deferred: crossing into
another zone (test character too low for Westfall); check when leveling there.

Changed after testing: the default position anchors to Blizzard's hidden `ObjectiveTrackerFrame`
(the game's layout puts it below the minimap and its widgets) instead of a fixed screen offset,
which overlapped a "1:24" timer under the minimap. A minimap scaled by another addon (SexyMap)
isn't known to Blizzard's layout, so the stack can still overlap one; dragging it fixes that.

## In-game test (after build)

1. Cards for this zone's quests appear where Blizzard's tracker was; other quests are under
   "Elsewhere (N)".
2. Kill a quest mob: the counter updates in place; nothing moves.
3. Complete a quest's objectives: it becomes a turn-in card and moves to the top (after combat
   if you were fighting).
4. Collapse and expand a card; `/reload`; the state is kept.
5. Walk into another zone: cards swap between the zone stack and Elsewhere.
6. Accept and abandon a quest: its card appears and disappears, no flicker from the objectives
   arriving late.
7. Unlock, drag the stack, lock, `/reload`: position kept.
