# Research (2026-11-14)

Research the spec asked for before building. Four reports:

| Report | Question |
| --- | --- |
| [guidemate.md](guidemate.md) | Forever GuideMate: coverage, hint quality, provenance, fit |
| [sources-and-licenses.md](sources-and-licenses.md) | Licenses of every data source; Questmark's own license |
| [landscape.md](landscape.md) | Existing Forever quest addons; is the hint layer unoccupied? |
| [forever-api-and-questiedb.md](forever-api-and-questiedb.md) | Forever quest/map/settings APIs, hiding the tracker, QuestieDB |

## Headline findings

1. **forever-db (Polestar) is the strongest data source found.** Open Forever quest database:
   5,287 quests, spawns, prerequisites, plus a "how it's done" layer: 3,401 mechanic rows and
   1,059 `gotcha` tips over 966 quests. Database GPL-3.0, tips/mechanics CC BY 4.0. Ships in-game
   as the `LibForeverData` library (~3.6 MiB memory) with a documented API.
2. **GuideMate is unusable as a source.** Archived on 2026-11-14; its leveling text is
   machine-imported from Zygor Guides (commercial) without credit. At most, its quest IDs with
   real tricks can serve as a to-do list for hints we write ourselves.
3. **Warcraft Wiki barely covers new Forever quests** (spot check: 0 of 13 with a real hint).
   Useful for original classic quests only.
4. **Guidelime and its guides are All Rights Reserved**, contrary to the spec's "some GPL-3".
5. **The hint layer is taken at the data level, open at the presentation level.** Nobody shows
   a hint on a card for the quests you happen to have. Calm, event-driven tracking has no
   competitor at all (Questie re-sorts on a 5 s timer; its users ask for exactly the spec's rules).
6. **Phase 1 APIs all exist on Forever without restrictions.** Quest log cap is 40
   (`C_QuestLog.GetMaxNumQuestsCanAccept()`). Hiding Blizzard's tracker needs an `OnShow`
   re-hide hook; a one-time `Hide()` does not stick.
7. **Recommended license: GPL-3.0-or-later.**

## Verification notes

Spot-checked by the main session after the reports came in:

- forever-db `index.json` (release 2026.11.1, client build 1.60.1.70532): `note` table has 0 rows;
  the tips live in `step.jsonl` as `action: "gotcha"`. Counted directly: 1,059 gotcha rows,
  966 distinct quests. [Read]
- Gotcha quality is mixed. Real tricks ("Hurley only shows up after the kegs in the Grim Guzzler
  are smashed", "the ticket disappears after 600 seconds") sit next to generic ones ("needs a
  group", "only during the Lunar Festival"), which Questmark should show as tags, not hints. [Read]
- Provenance: forever-db's NOTICE credits EG Link (CC BY 4.0), CMaNGOS, VMaNGOS/Factoruide,
  ForeverTDB, QuestieDB, pfQuest and client tables. Its pipeline code
  (`rust/crates/forge-data/src/kb.rs:58,1135-1140`) records that gotcha evidence includes web
  quest-database pages and their comments, rewritten as facts; it states no quoted text ships.
  This is the spec's manual Wowhead rule ("read, then write in your own words") done at scale
  upstream. A conscious decision, not a blocker. [Read]
