# Phase 4 design: categories and forever-db

Spec, Quest categories: "Side content gets its own group so it doesn't crowd normal questing."
Categories: Normal, Dungeon, Profession, Pet battle, Class, Seasonal/Event, Repeatable. Per
category the player chooses Show with zone cards / Separate group / Hide. Classification: quest
API first, then the quest database, then a small hand-maintained list.

This phase also brings in forever-db (decided in the research) and uses it for turn-in names.

Evidence tags: [Read] verified in the LibForeverData release, the Forever UI source, or in game;
[Assumes] to confirm in game.

## LibForeverData, bundled

- Release `lib-v1.2026.11.1` (forever-db 2026.11.1, client 1.60.1.70532), 1.4 MB zipped,
  3.7 MB unpacked, SHA-256 matches the release's `SHA256SUMS` [Read].
- **Vendored in the repo** at `Libs/LibForeverData/`, unmodified, with its `LICENSE.txt`
  (GPL-3.0), `LICENSE-CC-BY-4.0.txt` and `NOTICE.md`. Its files are listed first in
  `Questmark.toc`. Designed for this: "embed the folder; the newest copy loaded wins" — if Polestar
  or another addon loads a newer copy, ours steps aside [Read: Core.lua:6-7, 37-41].
- Writes only `ns.LuaChunks`, `ns.LibForeverData` and the global `LibForeverData` [Read:
  LuaChunks.lua:146, Core.lua:44-45]. No clash with our names.
- **Memory:** records are kept as text and decoded on first read into a cache, about 3.6 MiB after
  loading [Read: forever-db README]. Measured in game after build (`/qm memory`).
- `tools/vendor.py` updates it: downloads a pinned release tag, checks SHA-256 against the
  release's `SHA256SUMS`, replaces `Libs/LibForeverData/`. Pin lives in `tools/toolchain.json`.
- LuaLS skips `Libs/` (generated data, 70k lines); `LibForeverData` is declared as a global and
  only touched through one adapter (below), so the lint still checks every use.
- `THIRD-PARTY-NOTICES` at the repo root: what is bundled, its licences, the CC BY 4.0
  attribution for its steps/notes layer. Required now that we redistribute it.

### API we use [Read: Core.lua:9-30]

`LibForeverData.Quest(id)` -> `{ id, name, level, minLevel, races, classes, side, xp, type, zone,
repeatable, start, finish, objectives, prereqs, rewards }`. `start` / `finish` are lists of
`{ kind = "npc" | "object" | "item", id }`; `Name(kind, id)` gives a name. `type` matches the game's
quest tags (81 Dungeon, 62 Raid, 1 Group, 41 PvP). `zone` is an AreaTable id, often a subzone
(Kobold Camp Cleanup: 9, Northshire Valley); missing for 1,372 of 5,287 quests, including Camping
and holiday quests [Read: counted]. `Steps(id)` / `Notes(id)` hold the hint layer for phase 7.

### Adapter: `Data/ForeverData.lua` (`ns.ForeverData`)

The only file that touches the library. Checks `LibForeverData.api == 1` and degrades to "no data"
otherwise, so a future breaking release turns features off instead of erroring.

- `Quest(questID)`: the record, cached per session.
- `TurnInName(questID)`: name of the first `finish` entry (Nibbled-On Book -> Brother Paxton,
  npc 951 [Read]).
- `AreaName(questID)`: `C_Map.GetAreaInfo(record.zone)` [Read: unrestricted].

## Zone membership (phase 2 stopgap, revisited)

The plan was to replace the map-marker rule with forever-db's zone. The data says otherwise:
`zone` is often a subzone and missing for a quarter of quests, while the client's markers are
exact and already verified. So markers stay the rule (no longer a stopgap); forever-db's area name
replaces the quest-log header as the fallback for quests without a marker, header after that.

## Classification

`ns.Categories:For(quest)`, first match wins:

1. **Manual overrides**: `Data/CategoryOverrides.lua`, `[questID] = "Profession"` etc. Starts empty;
   the spec's "small hand-maintained list for anything that slips through".
2. **Dungeon**: game tag 81 (Dungeon) or 62 (Raid) from `GetQuestTagInfo` [Read: research A2], or
   forever-db `type` 81/62.
3. **Quest-log header** (the game files quests by category under headers like "Camping",
   "Blacksmithing", "Lunar Festival", "Warrior"):
   - Class: header equals a class name from `LocalizedClassList()` (language-independent).
   - Camping, Profession, Seasonal, Pet battle: header in a hand-kept English name list. **Stopgap**: other
     client languages fall through to the next rules until the list is localized.
4. **Class**: forever-db `classes` mask is not 0 (restricted to some classes).
5. **Repeatable**: game frequency daily/weekly, classification Recurring, or forever-db
   `repeatable`.
6. **Normal**.

**Camping** (Forever's new category, "Camping 101: Blacksmithing" etc. [Read: phase 1 test]) is its
own category (decided in review): Forever may grow it into its own system, and a category of its
own keeps that open. Detected by its quest-log header, like Profession.

## Per-category behaviour

Setting per category, in the profile: **Show** with zone cards / **Separate** group / **Hide**.

| Category | Default |
| --- | --- |
| Normal | Show |
| Dungeon | Show (dungeon mode, phase 6, builds on these) |
| Class | Show |
| Profession | Separate |
| Camping | Separate |
| Seasonal/Event | Separate |
| Repeatable | Separate |
| Pet battle | Separate |

- **Separate**: a collapsed group line per category ("+ Professions (4)") between the zone cards
  and Elsewhere. A separate group holds all quests of that category, in any zone; side content is
  rarely tied to where you are.
- **Hide**: not shown. Undo in settings. (The per-quest Hidden group stays for the ignore list.)
- **Pinned quests always show**, whatever their category (tracking rule 1 wins).
- Settings: one dropdown per category (`Settings.CreateDropdown` [Read]).

## Turn-in cards

"Turn in to Brother Paxton" from `ForeverData:TurnInName`; "Ready to turn in" when forever-db has
no record (new or unpublished quests).

## Debug

- `/qm quest <id>` adds the category, the rule that decided it, and the forever-db record summary.
- `/qm memory`: Questmark's memory use (`UpdateAddOnMemoryUsage`, `GetAddOnMemoryUsage`).

## Files

| File | Job |
| --- | --- |
| `Libs/LibForeverData/` | Vendored library, unmodified |
| `Data/ForeverData.lua` | Adapter |
| `Data/CategoryOverrides.lua` | Manual category list |
| `Quests/Categories.lua` | Classification |
| `Quests/Tracking.lua` | Category groups in the view |
| `tools/vendor.py` | Library updater with checksum check |
| `THIRD-PARTY-NOTICES` | Attribution |

## In-game test (after build)

1. `/qm memory` before and after: Questmark's memory with the library loaded.
2. Camping 101 quests appear under "+ Camping (N)", not as zone cards.
3. A turn-in card says "Turn in to <name>".
4. Settings: set Camping to Show: Camping quests become zone/Elsewhere cards; Hide: gone.
5. `/qm quest <id>` on a few quests: category and rule look right.
6. Pin a Camping quest: it shows at the top even though Profession is Separate.
