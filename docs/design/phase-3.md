# Phase 3 design: tracking rules

Spec, Tracking: "The addon owns tracking with its own rules; the player's manual choices always
win." Rules: (1) pinned quests always show; (2) the rest are chosen by zone and sorted by distance;
(3) turn-ins near you jump to the top; (4) re-sort only on events, never on a timer, never in
combat; (5) cap visible cards (default 5), the rest one click away; (6) ignore list.

Evidence tags: [Read] verified in the Forever UI source or in game; [Assumes] to confirm in game.

## What you see

```
 Questmark                12/40  [L] [S] [-]   <- header row (below)
 [2] Rest and Relaxation          (pin)  -     <- pinned: always shown, any zone
     Ready to turn in
 [2] Wolves Across the Border            -     <- ready turn-in in this zone: top
     Ready to turn in
 [2] Kobold Camp Cleanup                 -     <- this zone, nearest first
     Kill Kobold Vermin                 6/10
 [2] Rascally Rodents                    -
     Collect Stolen Book                 2/8
 + 2 more here                                 <- over the cap: one click away
 + Elsewhere (3)
 + Hidden (1)                                  <- ignored quests: unhide from here
```

### Header row

Requested in review. One line above the cards:

- **"Questmark"** title.
- **Quest count** "12/40": quests in the log / `C_QuestLog.GetMaxNumQuestsCanAccept()` (40 on
  Forever [Read: research A1]). Orange from 35, red at the cap. This is the spec's log capacity
  indicator, placed where it's always visible.
- **Lock** button: toggles the position lock. Unlocked, the header is the drag handle (replaces
  phase 2's blue overlay, which covered the cards).
- **Settings** button: opens Questmark's settings (out of combat, as `/qm`).
- **Minimize** `-` / `+`: collapses the whole tracker to the header row. Saved per character.
- Icons from textures/atlases verified in Forever's UI source at build time; plain-text
  fallbacks otherwise. Tooltips on each button.

Right-click a card: **Pin / Unpin**, **Hide**, **Collapse / Expand**. Right-click a quest under
Hidden: **Unhide**. Built on Blizzard's current menu system, `MenuUtil.CreateContextMenu`
[Read: Blizzard_Menu/MenuUtil.lua:151, used by AddonList.lua:937], not the old `UIDropDownMenu`
code that is known to spread taint. Not a restricted wrapper (apiguard's index).

## Order

1. **Pinned quests**, in the order they were pinned, wherever they are. A pinned quest from
   another zone shows its zone after the title. Never cut by the cap (rule 1).
2. **Ready turn-ins in this zone**, nearest first (rule 3). "Near" = in this zone: the zone map is
   the unit the spec's cards are built around, and a distance cutoff would make the rule flicker
   at its edge.
3. **Other quests in this zone**, nearest first (rule 2). Quests with no map marker go last, in
   quest-log order.
4. **Cap (rule 5):** groups 2 and 3 together show at most N cards (default 5, setting 1-15).
   Pinned cards are on top of the cap, so pinning never pushes the zone's quests off.
   The rest: "+ N more here", which expands in place.
5. **Elsewhere (N)** and **Hidden (N)**, collapsed groups at the bottom.

## Distance

- Quest position: the map marker `C_QuestLog.GetQuestsOnMap(zone map)` returns, already used by
  phase 2 for zone membership [Read: `/qm map`, e.g. Kobold Camp Cleanup at 0.497, 0.363 on
  Elwynn Forest]. For a ready quest the marker is the turn-in [Read: Rest and Relaxation's marker
  sat at the Goldshire inn].
- Player position: `C_Map.GetPlayerMapPosition(zone map, "player")`. Both are fractions of the
  zone map; `C_Map.GetMapWorldSize(zone map)` turns the difference into yards. No restriction
  flags on any of the three [Read: apiguard]. Nil in instances: then nothing has a distance and
  order falls back to quest-log order.
- One marker per quest is approximate ("nearest unfinished objective" and nearest-edge targeting
  are phase 5's arrow work). Good enough to order a handful of cards.

## When the order changes (rule 4)

Re-sort only on:
- `QuestLogChanged` (accepted, removed, objective progress, turned ready),
- a zone change,
- **moving more than 100 yards** from where the last sort happened.

The movement check is the only periodic code: once a second it reads the player's map position
and compares it with the position saved at the last sort. It never re-sorts by itself; crossing
100 yards *requests* a re-sort, like any other event. Outside the zone map (instances) it does
nothing.

**Hysteresis:** a re-sort starts from the current order and swaps two neighbours only when the
lower one is at least 20% closer (the spec's arrow rule, applied to the list). Two quests at
similar distances never trade places back and forth.

**Never in combat:** as in phase 2, re-sorts wait for the end of combat; progress still updates
in place. The player's own actions (pin, hide, collapse, expanding a group) apply at once.

## Saved data (per character)

- `pins[questID] = order number` (order of pinning). `ignored[questID] = true`.
- Both are cleared for a quest when it leaves the log (`QuestRemoved`), so they never grow stale.
- Collapse state (phase 2) unchanged. Expanded state of "more here" / Elsewhere / Hidden saved.
- New profile setting: `cards.cap = 5`, slider in settings.

## Files

| File | Job |
| --- | --- |
| `Quests/Tracking.lua` | The rules: builds the view (pinned, zone visible, overflow, elsewhere, hidden), distances, hysteresis, movement watch |
| `Quests/Zone.lua` | Also keeps each in-zone quest's marker position |
| `UI/Cards/Menu.lua` | Right-click menus |
| `UI/Cards/Stack.lua` | Draws the view; no ordering logic left in it |

`Tracking` decides, `Stack` draws. Phase 4 (categories) adds its Show / Separate / Hide groups in
`Tracking` without touching drawing.

## Verified in game (Nov 14, 2026)

Passed: header (count, minimize, lock + drag by header, settings), pin/unpin, hide/unhide, cap with
"+ N more here", distance re-sort at a reasonable pace without flip-flopping. Combat deferral
assumed (same mechanism as phase 2). Pins on top of the cap confirmed as intended.

Added after review: translucent panel (opacity setting, default 25%), darker header band, faint
dividers between cards and stronger ones before group lines, inner padding.

## In-game test (after build)

1. With more than 5 quests in the zone: 5 cards, then "+ N more here"; click shows the rest.
2. Walk from one quest area to another (over 100 yards): the order changes once, after you've
   moved, not continuously. Standing between two equally distant areas: no flip-flopping.
3. Right-click > Pin a quest, walk into another zone (or have one from elsewhere): it stays at
   the top with its zone name. Unpin: it returns to its normal place.
4. Right-click > Hide: the card moves into "Hidden (1)"; right-click it there > Unhide.
5. Finish a quest's objectives mid-fight: the card updates in place, moves to the top after the
   fight.
6. Turn in or abandon a pinned or hidden quest; `/reload`: no leftover pin or hidden entry.
7. Settings: change the cap; the stack follows.
8. Header: count matches the quest log; lock button lets you drag by the header; settings button
   opens settings; minimize collapses to the header and survives `/reload`.
