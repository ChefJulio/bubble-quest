# Quest Companion — WoW Forever Addon Spec

Nov 14, 2026 · @Hunter Graves

Revised Nov 14, 2026 with the pre-build research in [docs/research/](research/README.md). Decisions taken: license GPL-3.0-or-later; forever-db (LibForeverData) as quest database and first-pass hint source; Blizzard tracker hidden with an `OnShow` re-hide hook.

## Overview

A quest tracker for WoW Forever that answers two questions for every active quest: **what do I do** and **where do I go**, with a hint when the quest has a confusing step.

**Problem.** Blizzard's quest log and existing trackers (Questie included) show map pins and objective counts, but go silent on obscure steps such as "use the item on the corpse" or "talk to the NPC twice." Players end up on Wowhead comments. Automatic tracking also reshuffles constantly and tracks the wrong things.

**Goals**

- Show every relevant quest in the current zone as its own card, so the player picks the order.
- Give each objective a plain Do / Where / Hint line.
- Real-time direction arrows for outdoor objectives.
- Auto-tracking that is predictable: pinned quests stay, the rest follow zone and distance, nothing jumps around.
- Keep side content (professions, pet battles, etc.) out of the way.
- Useful inside dungeons with descriptive hints.

**Non-goals**

- Not a leveling guide or route optimizer. The player still decides what to do next; the addon removes confusion, not thinking.
- No combat logic. Nothing reacts to combat state.
- No network calls, no accounts. All data ships with the addon or stays in the player's local SavedVariables.

## Quest cards

The tracker is a stack of cards, one per quest, replacing Blizzard's objective tracker (which is hidden, not modified).

**When in a zone with active quests:** one card per relevant quest, no forced order. Questing usually means three or four quests in one area done together, so the cards present them side by side rather than merging them into a route.

**Each card shows**

- Quest title, level, and a small arrow + distance to the nearest unfinished objective.
- One row per objective:
  - **Do:** a verb-first action. "Kill 6 Riverglade Snappers." "Use Ember Totem on a fallen scout." Built from the objective text, rewritten by the hint data when the raw text is unclear.
  - **Where:** distance and direction outdoors; a short description indoors or when no position exists ("cave behind the waterfall").
  - **Hint:** shown only when the quest has a known confusing step. Hidden otherwise to keep cards short.
- Progress (3/6) and a completed state. When all objectives are done, the card turns into a turn-in card pointing at the quest giver.
- Forever quests can gain objectives partway through, mark objectives optional, and accept them in any order (Questie issues #7929–#7931). Rows are keyed by objective, not by position; a newly appeared objective gets a row without reshuffling the others, and optional objectives carry an "optional" marker and never block the turn-in state.

**Card behavior**

- Cards for quests ready to turn in near you sort to the top.
- A card can be collapsed to its title line.
- Clicking a card makes it the focused quest (big arrow, see Navigation).
- Quests outside the current zone live in a collapsed "Elsewhere" group, listed by zone.

## Navigation arrows

Outdoors, every card carries a small live arrow and distance ("↗ 140 yd"), inline on the card's title line. Minimal by design: no large standalone arrow. TomTom has a Forever version, so live arrows are proven to work on this client.

**How it works:** read player map position and facing, compute bearing to the target, rotate an arrow texture. Position and facing are not combat state, so the secret-value restrictions don't apply. Both are unavailable inside instances.

**Rules**

- **Target the nearest edge of the objective area**, not its center. Once inside the area, the arrow becomes a green in-area marker that changes shape too (e.g. filled dot), not just color, for colorblind players and quick glances. The matching objective row highlights so it's clear which one you're standing in. Turn-in cards behave the same with the quest giver as target.
- **Hysteresis:** switch to a different objective spot only when it is meaningfully closer (e.g. 20%+), so the arrow never flip-flops.
- **Cross-zone:** compute distance in world coordinates. When the target is in another zone, show the zone name and direction instead of yards.
- **Throttle:** update every few frames, not every frame.
- **Optional:** set the target as Blizzard's native waypoint (in-world beacon + map pin) instead of, or alongside, the custom arrow. Setting.
- Indoors / instances: arrows hidden, Where text shown instead.

## Tracking

The addon owns tracking with its own rules; the player's manual choices always win.

1. **Pinned quests always show** and are never auto-removed.
2. **Everything else is chosen by zone,** then sorted by distance to the nearest unfinished objective.
3. **Turn-ins near you jump to the top.**
4. **Re-sort only on events:** zone change, objective progress, quest accepted/completed/abandoned, or moving past a distance threshold. Never on a timer, never during combat.
5. **Cap visible cards** (default 5, configurable). The rest sit one click away.
6. **Ignore list:** a quest can be hidden until unhidden.

Rule 4 is the core fix for "automatic tracking sucks": the list stays still while you're playing.

## Quest categories

Side content gets its own group so it doesn't crowd normal questing.

- Categories: Normal, Dungeon, Profession, Pet battle, Class, Seasonal/Event, Repeatable.
- Per category, the player chooses: **Show with zone cards**, **Separate group** (collapsed section), or **Hide**.
- Classification comes from the quest API's tags/classification where available, then from the quest database, then from a small hand-maintained list of quest IDs for anything that slips through.

## Background objectives

Some objectives are meant to be done while doing other things, such as boars and bears spread over a whole starting zone. Showing every spawn clutters the map and the cards. These get a quieter "background" mode.

**Detection:** an objective is background when its spawns spread over a large share of the zone or form many separate clusters (thresholds tuned during testing). The player can also toggle it manually per objective.

**Behavior while background**

- **Card:** a slim row, "Crag Boar Ribs 3/8 · as you go," with no arrow and no distance.
- **Map:** no zone-wide dots. Show only spawns within a short radius of the player, or nothing (setting).
- **When one is nearby:** addons can't see mob positions, but they can see when a matching mob's nameplate appears on screen. When that happens, the row lights up briefly, and the mob's tooltip shows the quest line. Out of combat only: on Forever, tooltip quest data (quest ID, objective text, counters) becomes secret in combat, so string work on it fails. The quest-log API itself stays readable in combat.

**Promotion to active:** a background objective becomes a normal one, with an arrow, when it is the last unfinished objective for the player in the zone, or the player pins it. The arrow then points to the nearest dense cluster of spawns, not to every spawn point.

## Dungeon mode

Inside a dungeon, the cards show only that dungeon's quests, with Do and Hint lines and a descriptive Where ("drops from the final boss," "item on the table behind the second boss"). Arrows are off because the game hides player position in instances.

**Pre-dungeon reminder:** near a dungeon entrance or in its zone, show "You have 3 quests for this dungeon" plus any quests for it you could still pick up, with where to get them. Missing a dungeon quest and having to run it again is a classic annoyance, and this fixes it cheaply.

## Hint system and sourcing

Hint *data* already exists: Polestar's open forever-db has 1,059 tips over 966 quests. What nobody does is show the hint on the card of the quest you are on, without following a guide. That presentation, plus calm tracking, is the differentiator. Hints start from forever-db, get triaged, and grow through in-game learning that flags which quests are confusing.

**Data model:** a Lua table keyed by quest ID → objective key → `{do, where, hint, source}`. Shipped with the addon, regenerated per release. `source` keeps attribution for licensed content.

### Sources

| Source | What it gives | License / risk | Use |
| --- | --- | --- | --- |
| [forever-db / LibForeverData](https://github.com/fitzforge/polestar/tree/next/forever-db) (Polestar) | 5,287 Forever quests: givers, turn-ins, objectives, prerequisites, 88k spawn points, items and drop sources. Plus 3,401 mechanic rows (use-item, escort, timed, ...) and 1,059 `gotcha` tips over 966 quests | Database GPL-3.0; mechanics/steps/tips CC BY 4.0. Tips were rewritten as facts from evidence that includes web quest-database pages and comments; no quoted text ships | **Primary.** Quest database at runtime via the `LibForeverData` library addon (~3.6 MiB), and first-pass **Hint** input. Contribute fixes back through its `corrections/` |
| [QuestieDB](https://github.com/Questie/QuestieDB) | Quest givers, objectives, spawn coordinates; 5,682 quests, versioned runtime API (`LibQuestieDB.RequireContract`) | No real license: "treat as all rights reserved when in doubt"; team permits GPLv3 copying, not all past contributors agreed | Fallback only, as an optional runtime dependency. Never baked in |
| [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Warcraft_Wiki:Copyrights) | Quest pages with objectives, notes, walkthrough text | CC BY-SA 4.0: reuse allowed with attribution and share-alike (one-way into GPLv3) | **Hint** text for original classic quests. Covers new Forever quests poorly (spot check: 0 of 13 with a real hint) |
| AllTheThings Forever quest data | Forever quest coverage, incl. new zones | MIT (confirmed in its LICENSE) | Gap-filler if forever-db misses quests |
| Open leveling guides ([Guidelime](https://github.com/max-ri/Guidelime) modules, [LevelForge](https://www.curseforge.com/wow/addons/levelforge)) | Step text written by guide authors | Guidelime and its Forever guides are All Rights Reserved; LevelForge has no source and unlicensed player guides | Not usable |
| [Forever GuideMate](https://github.com/TylerAkins/forever-guide-mate) | 3,041 quest IDs of guide steps | Code GPL-3.0, but leveling text machine-imported from Zygor Guides (commercial) without credit; archived | No text or data. At most a to-do list of quest IDs whose steps hold a real trick |
| In-game quest text (API) | Objective and description text | Blizzard's text, already in the client | Raw input for generating **Do** lines |
| Wowhead comments | Best "how do I actually do this" notes | Terms not verified; reported to block scraping. Comments are authored by users | Manual only: read, then write the hint in your own words. No scraping |

### Research outcome: Forever GuideMate

The spec originally named GuideMate the most promising hint source. Research ([guidemate.md](research/guidemate.md)) ruled it out: archived on Nov 14, 2026; its 1-60 text was machine-imported from Zygor Guides without credit; `useClientText = false` is set on 87% of steps and is not a hint marker (2 real tricks in a random 50). Its dungeon guides' "enter the instance" step, listing every pickup for that dungeon with giver, level and prerequisites, is a good *design* for the pre-dungeon reminder; rebuild the data from forever-db.

### Pipeline (build time, outside the game)

1. Pull quests, objectives, mechanics and `gotcha` tips from forever-db.
2. Triage tips: generic ones ("needs a group", "raid", "holiday only") become card tags or categories, not hints; real tricks (timers, hidden spawns, item use, talk-twice, escort quirks) become **Hint** candidates.
3. For quests without a usable tip, gather licensed text (wiki notes for classic quests, in-game description).
4. LLM pass: rewrite each objective into a verb-first **Do** line; produce a **Hint** only when the sources describe a non-obvious step. Otherwise no hint.
5. Keep `source` + attribution per entry. Generate a credits file.
6. Human review queue for quests flagged as confusing (below), prioritized over everything else. Fixes to forever-db's facts go back upstream through its `corrections/`.

### In-game learning (local, opt-in export)

- **Where collector:** record where objectives actually progress (position at objective update, loot source, item-use location) to fill gaps for new quests. Proven pattern: [PosLog](https://www.curseforge.com/wow/addons/poslog) and Questie's community data collectors do this.
- **Confusion detector:** flag a quest as "probably confusing" when signals stack up: long time on one objective, repeated abandons, many visits to the area with no progress, or a quest item used many times before progress. These flags decide which quests need a hint written, instead of guessing.
- **Player notes:** a "note this step" button writes a hint to SavedVariables. Players export notes as a text string; good ones get merged into the shipped table.
- All local. No network code. Export is a manual copy-paste.

### Licensing note

Decided: the addon is **GPL-3.0-or-later**. Compatible with forever-db (GPL-3.0 database, CC BY 4.0 tips), the wiki (CC BY-SA 4.0 adapts one-way into GPLv3), and AllTheThings (MIT). Ship `LICENSE`, a `THIRD-PARTY-NOTICES` file (forever-db and AllTheThings notices, wiki attribution) once any third-party data is included, and a generated `CREDITS` listing each wiki page used. Never include Guidelime guides, Wowhead text, Blizzard quest text quoted on the wiki, or Questie's name and logo.

## Card extras

Small features that remove common questing friction.

- **Quest item buttons:** a clickable button on the objective row for any usable quest item, next to its hint. Secure buttons can't be created or changed in combat; build them out of combat and queue changes.
- **"Don't leave yet" warning:** when leaving a zone with turn-ins there, or turn-ins that unlock more quests in the same area, show one line ("2 turn-ins in Lakeshire unlock 3 more quests here"). Needs quest chain data.
- **Keep-this-item tooltips:** add a line to bag item tooltips for items a later or current quest needs ("Needed for The Lighthouse"), so players don't vendor them.
- **Elite / group flag:** tag elite or group quests on the card, with target level relative to the player.
- **Party progress:** show party members' objective counts on shared quests ("Kara 4/6") via addon messages. Overworld only; addon communication is restricted in instances.

## Replacing Questie, the tracker, and the quest log

The goal is for this addon to replace Questie, Blizzard's objective tracker, and Blizzard's quest log. That adds these requirements.

**From Questie**

- **World map and minimap pins:** available quest givers, objective areas (clustered), and turn-ins. Use the standard map-pin approach other addons use rather than a custom map.
- **Available-quest filtering:** by level, faction, race, class, prerequisites, exclusive and breadcrumb quests. This is the hardest data problem; it needs a complete quest database.
- **Available nearby (collapsed group):** quests in the current zone the player can pick up but hasn't, with where to get them. Required if the map pins are the only other place this appears.
- **Unit and object tooltips:** "Quest: Name 3/8" on mobs and objects that count toward a quest.
- **Hide trivial quests** option, and level coloring.
- **Completed-quest awareness:** never show already-completed quests as available.
- Optional: auto-accept / auto-turn-in with a modifier key to bypass.

**From the quest log**

- **Full quest view:** description, objectives, rewards with item tooltips and an upgrade indicator, follow-up quest in the chain.
- **Actions:** abandon (with confirm), share to party, link in chat, track/untrack (pin).
- **Organization:** grouped by zone and by category, matching the card categories; search.
- **Log capacity indicator:** Forever caps the log at 40 accepted quests; read it at runtime with `C_QuestLog.GetMaxNumQuestsCanAccept()`.
- **Opening it:** own keybind and slash command. Don't hook or override Blizzard's quest log toggle, which risks taint; leave Blizzard's log reachable as a fallback.

**General**

- **Quest database:** decided: forever-db through the `LibForeverData` library at runtime (~3.6 MiB memory, decodes records on first read), as a dependency or embedded. Bake in only Questmark's own data: hints, category overrides, background-objective clusters, the dungeon-quest index. QuestieDB is an optional fallback, never baked in.
- **Profiles and settings** shared across characters.
- **Localization:** UI and game strings can come from the client; hint data starts English-only.

## Platform constraints

Forever runs on the modern client, so retail-style APIs apply, and the Midnight addon restrictions are active there too ([details](https://epiccarry.com/blogs/?p=41550)). Features avoid combat state, with two exceptions: tooltip quest data is secret in combat (see Background objectives), and secure frames are locked in combat (see Combat).

- **Addon folder:** Forever has its own `_forever_\Interface\AddOns` directory. Interface version **16001** (client build 1.60.1).
- **API reference:** Claude Code's API knowledge is out of date. Ground it in Blizzard's current UI source (the `Gethe/wow-ui-source` mirror, `forever` branch) and Ketho's WoW API annotations. `python tools/lint.py` checks every call against both; it must pass.
- **Position:** map position and facing work outdoors; both return nothing inside instances. `UnitPosition` + `GetPlayerFacing` (TomTom's approach on Forever).
- **Combat:** don't rebuild or re-sort frames during combat; queue changes until combat ends. Avoids taint errors.
- **Blizzard tracker:** hide it rather than modify it. A one-time `Hide()` does not stick (Blizzard re-shows it when it has content), so hide it and add an `OnShow` post-hook (`HookScript`) that hides it again, deferring to `PLAYER_REGEN_ENABLED` if the frame is protected in combat. Never call Blizzard's tracker update functions. Hiding it also hides quest auto-complete popups and the scenario UI; Questmark must cover those later.
- **No user scripts:** Forever disables `/dump`, `/run` and `/script` (silently). Debugging goes through Questmark's own slash commands.
- **Testing:** must happen in-game. Use `/reload` loops and BugSack + !BugGrabber to capture Lua errors and paste them back to Claude Code.

## Existing landscape

Several Forever quest addons already ship arrows and trackers, and Polestar's forever-db already holds hint data. The differentiator is presentation: the hint for the quest you're on, on its card, without following a guide, plus calm per-zone cards with event-only re-sorting. Nobody does either (Questie re-sorts on a 5 s timer; its users ask for this spec's rules). Polestar plans richer step data soon, so the hint gap may narrow. Full survey: [landscape.md](research/landscape.md).

| Addon | Overlap |
| --- | --- |
| [Polestar Guides](https://github.com/fitzforge/polestar) | Largest Forever guide (~290K downloads): route guide, terrain-aware arrow, dungeon journal. Publishes forever-db, which Questmark builds on |
| [Questie (Forever bundle)](https://epiccarry.com/blogs/?p=44611) | Map pins, tracker, quest database; ~80 hint sentences shown only on map icons |
| [ForeverQuest](https://www.curseforge.com/wow/addons/foreverquest) | Questie-style tracker, map markers, minimap guidance |
| [Dungeon Quests Forever](https://www.curseforge.com/wow/addons/dungeon-quests-forever) | Step-by-step dungeon quests with arrow and auto-tracking. Closest overlap with Dungeon mode |
| [UpQuest Forever](https://www.curseforge.com/wow/addons/upquest-forever) | Directional arrow HUD, item navigation |
| [Everything Quests](https://www.curseforge.com/wow/addons/everything-quests) | Quest browser and chain guide with Forever data |
| [QuestForever](https://www.curseforge.com/wow/addons/questforever) | Records quest giver locations for new Forever quests |
| TomTom | Waypoint arrows |

## Implementation plan

Build in this order; each phase is usable on its own.

1. **Skeleton:** .toc, SavedVariables, settings panel, hide Blizzard tracker, read the quest log.
2. **Cards:** per-zone card stack with Do/Where from raw objective text; Elsewhere group; collapse.
3. **Tracking rules:** pins, zone selection, event-driven re-sort, cap, ignore list.
4. **Categories:** classification + Show/Separate/Hide per category.
5. **Arrows:** per-card mini arrows, focus arrow, edge targeting, hysteresis, optional native waypoint.
6. **Dungeon mode:** instance detection, dungeon-only cards, pre-dungeon reminder.
7. **Hint data:** data format and loader first, then the build-time pipeline (separate repo folder, not shipped): forever-db tips triaged first, then quests the confusion detector flags.
8. **In-game learning:** where collector, confusion detector, note button, export string.

**Later phases:** 9. card extras (item buttons, don't-leave-yet, keep-item tooltips, elite flag, party progress). 10. Questie replacement (database, map and minimap pins, available quests, tooltips). 11. Quest log replacement window.

## Open questions

Resolved by the research:

- ~~Depend on QuestieDB at runtime, or bake its data in?~~ Neither: forever-db via LibForeverData at runtime; QuestieDB optional fallback.
- ~~Warcraft Wiki coverage of new Forever quests?~~ Thin; useful for classic quests only.
- ~~Licenses for QuestieDB and AllTheThings?~~ QuestieDB: none (all rights reserved when in doubt). AllTheThings: MIT.
- ~~Profession/pet classifications in the API?~~ Partly. Quest tags cover Dungeon, Raid, PvP, Group, Elite; frequency/classification cover Repeatable/Daily/Weekly. Profession and Pet battle tags apply only to world quests, so Profession, Class and Seasonal come from the quest database plus a small manual list.

Still open:

- Name for the addon (working name: Questmark).
- Phases 10–11 (Questie and quest log replacement): the map-pin space is crowded. Build them, or coexist with a pin addon?
- Event order on Forever: does `QUEST_TURNED_IN` fire before `QUEST_REMOVED`? Needed to tell turn-ins from abandons. Verify in-game.
- Ship LibForeverData as a required dependency, or embed it in Questmark's folder?
