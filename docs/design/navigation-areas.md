# Navigation: areas, not points

Replaces the arrows' "nearest known point" model (phase 5). Decided in review, 2026-11-16.

## Problem

The arrow aimed at the single nearest point among everything known: forever-db spawns, spots learned
from nameplates, the map marker. Every point counted the same, so one stray sighting far from where a
mob really lives pulled the arrow as hard as the camp itself. "Here" meant "a nameplate is up, or you
are within 40 yards of any one point".

## Rule

> Group an objective's locations into areas. Ignore areas that are tiny compared with the objective's
> biggest area. The arrow points at the nearest edge of the nearest remaining area.

"Tiny" is relative: less than a quarter of the biggest area's weight. No tuning trade-off between
density and distance.

- A 25-spawn camp and one stray spawn: the stray is 4% of the camp, ignored.
- A named mob with one spawn: the only area is the biggest, kept.
- Mobs spread over many similar groups: all comparable, all kept, nearest wins.
- A single learned sighting never outweighs spawn data; it matters only where it is all we know.

## Pieces

**Sources** (weighted points per objective, world yards on the instance map):

| Source | Weight | Notes |
|---|---|---|
| Questie (`LibQuestieDB`, read at runtime from the player's install, never bundled) | 1 per spawn | when installed, contract 4, `Questie.API.isReady`; setting "Use Questie's location data" |
| forever-db (`LibForeverData`, bundled) | 1 per spawn | |
| Learned in play | sightings, capped at 3 | a spot seen again gains weight |
| Client quest marker | 1 | only when nothing else is known; never claims "here" |

The same spawn from two sources counts once (points within 4 yards merge, keeping the larger weight).

**Areas**: occupied 50-yard grid cells joined with their 8 neighbours; each connected group of cells is
one area. Linear in the number of points, built once per quest objective and cached; rebuilt when
progress, sources or learned data change.

**Target**: over the kept areas of every unfinished objective (or the turn-in's areas when ready), the
nearest by distance to the area's nearest point; the arrow aims at that point (the area's near edge).
Hysteresis as in card sorting: switch only when another area is at least 20% closer.

**Here**: near a point of a kept, spawn-based area, or a nameplate of an objective mob up
(Quests/Nearby.lua, now a confirmation rather than the main mechanism). How near depends on what the
area is (every point carries its kind; an area takes the kind most of its points have):

| Kind | Here within | Why |
|---|---|---|
| turn-in | 10 yd | you must be at it; not 5, as location data is often a few yards off the NPC |
| object (gather, use) | 20 yd | objects don't move: near one |
| exploration | 30 yd | a place, not a thing |
| npc (kill, loot) | 40 yd | mobs roam; nameplates confirm it too |

**Debug**: `/qm areas <questID>` lists each objective's areas: weight, distance, kept or ignored, which
is targeted.

## Files

- `Data/QuestieData.lua`: Questie objective spawns via `QuestDB`/`NpcDB`/`ObjectDB`/`ItemDB`; area IDs
  to uiMap via Questie's `ZoneDB:GetUiMapIdByAreaId` (internal; a miss skips the spawn).
- `Quests/Areas.lua`: merging, clustering, the "tiny" filter, nearest-area queries.
- `Quests/Navigation.lua`: sources -> areas -> target, here, hysteresis.
- `Data/Learned.lua`: sighting counts per spot.
