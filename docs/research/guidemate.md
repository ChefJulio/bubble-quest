# Forever GuideMate: research findings

Researched 2026-11-14 against https://github.com/TylerAkins/forever-guide-mate at
commit 342c82d (HEAD of main, full history fetched: 545 commits). Local clone:
`.tools/research/forever-guide-mate` (gitignored). No code from the clone was run.
Counts come from a Python Lua-table parser in the session scratchpad
(`scratchpad/research/luaparse.py`, `analyze.py`), cross-checked against grep.

Paths below are relative to the clone root unless they start with `docs/` of this repo.

---

## Verdict

**Do not ship GuideMate data or text inside Questmark, and do not treat
`useClientText = false` as a hint marker. Use GuideMate only as a private lookup
for which quests need a hint, then write the hints ourselves. The one clean, reusable
piece is the shape of its dungeon guides, as a design template for the pre-dungeon
reminder.**

Why:

1. **The license chain is not clean.** [Inferred, high confidence] The 1-60 leveling
   spine (Leveling + Class + Loremaster, about 90% of all goals) was machine-imported
   from a Zygor Guides Classic dump. Zygor is a commercial, proprietary guide.
   Loremaster ordering also reads "Zygor Guides Remaster 3.3.5a" (ErebusAres), a
   redistribution of old Zygor guides. GuideMate's GPL-3.0 notice cannot grant rights
   to that material. `sourceStep` is literally the step index in the Zygor source
   guide. Details in Q3.
2. **`useClientText = false` is a display flag, not a hint flag.** [Read] It is set on
   19,421 of 22,326 goals (87%), and 85% of those texts are generated templates
   ("Accept X from Y.", "Kill 6 Z."). Random sample of 50: 2 real tricks. Details in Q2.
3. **The project is archived as of today.** [Read] `README.md:3`: "This project is
   archived... Guides from this addon are being ported to RestedXP soon." So there is
   no upstream to contribute hints back to. The spec's "contact the author" idea is
   moot unless it targets the RestedXP port.
4. **Coordinates were never validated in the Forever client.** [Read] `README.md:9`,
   `docs/zone-loremaster-guides.md:47-50`.

How to use it anyway (all [Inferred]):

- **Hint triage list.** About 230-280 distinct quests have hand-written text that
  describes a real mechanic (item use, forms, escort quirks, /sit, waiting on an NPC,
  rep gates). Extract the quest IDs only, then write our own hints from licensed
  sources (Warcraft Wiki CC BY-SA) or in-game testing. A quest ID list is a fact,
  not expression. That is our biggest win from this repo: a pre-filtered "these
  quests are confusing" list, about 7-8% of 3,041 quests, which matches the spec's
  5-10% target.
- **Dungeon guides as a design reference.** The 39 hand-authored dungeon files map
  instance ID -> quests -> giver pins -> prerequisites in exactly the shape the
  pre-dungeon reminder needs (Q4). Rebuild that table ourselves from QuestieDB plus
  Wowhead's per-dungeon quest lists, which is what GuideMate itself cites
  (`Guides/Dungeons/Deadmines.lua:3-4`).
- **Where data.** Take it from QuestieDB (spawn areas, givers), not GuideMate. GuideMate's
  objective pins are single points from the Zygor `goto` lines, not areas.

Risks if any GuideMate text or route data were copied anyway: Zygor-derived
expression in a GPL addon, verbatim Blizzard quest text (579 "For X: <objective
text>" goals), and unverified coordinates.

---

## Q1. Coverage

### How counted

- Parsed all 221 `ns:RegisterGuide({...})` tables in `Guides/**.lua`, plus `ClassChains.lua`
  (`ns.classActions`, 1,418 shared actions that 3,117 goals reference via `classAction`).
  The result was 22,326 goals.
- A quest ID counts when a goal of kind `accept` / `turnin` / `objective` / `gossip`
  carries it in `complete.quest.id` or `complete.questObjective.id` (the completion
  condition the engine checks), or in the goal id convention
  `accept-<id>-...` / `turnin-<id>-...` / `objective-<id>-...` (see
  `docs/guide-authoring.md:63-69`).
- IDs that appear only in `requiredQuests` (prerequisites) are excluded: 41 more.
- Faction comes from `conditions` (`{ faction = "Alliance" }`) on the goal or guide.
- "New Forever" means quest ID >= 90000, the repo's own rule:
  `.agents/skills/era-forever-weave/SKILL.md:15` says "id >= 90000 in schema v2 exports".
- Cross-check by grep: 3,083 unique IDs appear anywhere in `quest = { id = N }` /
  `QuestState(N` tables, including exclusion conditions. That is consistent.

### Numbers [Read: computed from files]

| Slice | Unique quest IDs | Of which ID >= 90000 |
| --- | ---: | ---: |
| **All guides** | **3,041** (3,017 in TOC-loaded files) | 463 |
| Alliance-only | 1,297 | |
| Horde-only | 1,127 | |
| Both / no faction gate | 617 | |
| Leveling (86 files, 1-60 "Casual" spine + starters) | 2,334 | 366 |
| Loremaster (40 zone files) | 2,142 (only 229 not also in another folder) | 379 |
| Dungeons + raids (45 files) | 595 | 52 |
| Class (9 files) | 577 | 100 |
| Zephras Isle (Skyborne starter, Leveling + Loremaster) | 151 | |
| Miscellaneous (exploration, books) | 3 | 0 |

ID-range histogram: 0-9999: 2,547; 60000-89999: 31 ([Inferred] post-Classic-era IDs reused on Forever,
e.g. 76160 "Stalk With The Earthmother", `CHANGELOG.md:306`); 90000+: 463.

Per-dungeon quest counts (unique IDs in that file):
BRD 56, UBRS 51, Scholomance 40, Uldaman 39, Strat-Undead 21, LBRS 20,
Ruins of Lordaeron 20 (16 new), Strat-Live 14, SM Library 17, ZF 15,
Excavation Site: Wetlands 15 (14 new), WC 13, Gnomeregan 13, Deadmines 12, BFD 12,
City of Dalaran 11 (11 new), Maraudon 11, RFC 10, Stockade 9, RFK 8, RFD 7,
Dalaran Attunement 7 (5 new), Hall of Thanes 6 (6 new), Drowned City 1 (new),
Tier 0.5 questline 106, Onyxia attunement 30, Sunken Temple raid 58 (not in TOC).
Five raid files are not loaded by the TOC: BFD Raid, BWL, MC, Naxx attunements, ST Raid.

Per-class guide: Warlock 102, Warrior 83, Paladin 79 (28 new), Priest 66, Shaman 64 (27 new),
Druid 61 (22 new), Rogue 59, Hunter 53, Mage 53.

Gaps [Read]: Riverglades, Mount Hyjal, and Shen'dralas are not covered
(`docs/guide-authoring.md:11`, `docs/zone-loremaster-guides.md:62-63`). Six starter
quests are deliberately unauthored (`docs/zone-loremaster-guides.md:31-35`).

---

## Q2. Hint quality

### What `useClientText` actually means [Read]

`GuideEngine.lua:534-544`: for objective goals, `useClientText` defaults to `true`,
which shows Blizzard's live objective row. `false` means "show the authored `text` field
instead" (`UI.lua:1209-1216`). The importer and generators set `false` on almost
everything:

| Folder | `false` | `nil` |
| --- | ---: | ---: |
| Leveling | 9,308 | 0 |
| Loremaster | 8,336 | 788 |
| Class | 1,718 | 0 |
| Dungeons | 59 | 2,071 |

So the flag does not select hint-worthy steps. The hand-written dungeon text, which
holds some of the best tips, is mostly `nil` and a `false` filter would miss it.

Of the 19,421 `false` goals, 16,490 (85%) match pure templates: `Accept X [from Y].`,
`Turn in X [to Y].`, `Kill [N] X.`, `Collect N X.`, `Reach level N...`. These are
generated by `internal/itineraryimport/import.go:277-338`. The remaining 2,931 goals
have 1,295 distinct texts across 974 quests (heavy duplication between Leveling,
Loremaster, and Alliance/Horde copies).

### Sample A: 50 random `useClientText = false` goals

Seeded shuffle, at most one per file, spread over 50 files.

| Class | Count |
| --- | ---: |
| Real trick (non-obvious mechanic) | 2 |
| Useful but templated (item-started quest) | 1 |
| Level-gate note ("Reach level N before continuing") | 4 |
| Restates the objective (3 of these add a mob or zone name) | 43 |

### Sample B: 50 random goals from the 2,931 non-template subset

Same method. This is where hints would live if they exist.

| Class | Count |
| --- | ---: |
| Real trick | 11 |
| Templated item/loot starter ("Read X in your bags", "Loot X... Keep it for the next pickup", "Use X to accept") | 10 |
| Routing note | 1 |
| Restates the objective (about 10 are verbatim Blizzard objective text, "For <Quest>: ...") | 28 |

[Inferred] Extrapolating sample B: about 22% of 1,295 distinct texts are real
tricks, about 280 texts. An independent keyword scan (escort, wait, /sit, form,
assemble, behind, cave, timer, elite, etc., excluding templates) flags 506 goals,
265 distinct texts, and 232 distinct quests. That scan overcounts a bit, because
"This is an elite. Bring a group." is frequent. Both methods land at roughly 230-280
quests, 7-9% of coverage.

### Representative real tricks [Read]

1. `Guides/Leveling/horde-ungoro-crater.lua:1078` -- "Escort Ringo north to Spraggle Frock at Marshal's Refuge. Stay close and protect him. When he faints, use Spraggle's Canteen beside him, then continue the escort." (escort quirk + item use)
2. `Guides/Leveling/teldrassil.lua:2116` -- "Type /sit beside Lyreena Duskblade's Basic Campfire and wait until you receive the Boosted Rest buff." (hidden emote mechanic, Forever quest)
3. `Guides/Loremaster/Ashenvale.lua:5341` -- "Use Dartol's Rod of Transformation here to enter Furbolg Form before speaking with Krolg." (item use / form)
4. `Guides/Leveling/alliance-winterspring-and-felwood.lua:2659` -- "Reach Neutral reputation with Timbermaw Hold before speaking with the furbolgs inside the hold." (hidden gate)
5. `ClassChains.lua:5817` -- "Polymorph Spitelash naga in Azshara and wait for the clones to appear. Kill 50 Polymorph Clones." (non-obvious mechanic)
6. `ClassChains.lua:11427` -- "Wait beside Serge Hinott while he prepares the cure, then speak with him." (timing / talk twice)
7. `Guides/Leveling/alliance-stranglethorn-vale.lua:963` -- "Use Cozzle's Key to open his footlocker inside the nearby building. Collect the Fuel Regulator Blueprints." (item use + hidden location)
8. `Guides/Leveling/alliance-hillsbrad-foothills-and-arathi-highlands.lua:1243` -- "Buy 1 Hillman's Cloak at the Stormwind Auction House if available. Keep it for Bartolo Ginsetti in Southshore." (shortcut)
9. `Guides/Leveling/alliance-searing-gorge.lua:176` -- "Speak with Kalaran Windblade and ask what drives his vengeance. Follow his story until the quest is ready to turn in." (multi-step gossip)
10. `Guides/Dungeons/Deadmines.lua:733-734` -- "Take the Gnoam Sprecklesprocket from Sneed's Shredder. Clear the room first. Terrify fears. When the shredder dies, Sneed jumps out and disarms the tank, so let the tank pick him up." (dungeon tip; `useClientText` is nil here)

### Representative restatements [Read]

1. `Guides/Leveling/alliance-winterspring.lua:130` -- "Collect 10 Thick Yeti Fur."
2. `ClassChains.lua:2719` -- "Kill 7 Young Nightsaber."
3. `Guides/Leveling/alliance-darkshore.lua:1082` -- "Collect 3 Thresher Eye."
4. `Guides/Leveling/alliance-darkshore-part-2.lua:4058` -- "Kill Murkdeep." ([Inferred, game knowledge] omits that Murkdeep only spawns after waves of Greymist, a real trick it misses)
5. `Guides/Leveling/horde-stonetalon-mountains.lua:242` -- "Use Toxic Fogger."
6. `Guides/Leveling/alliance-western-and-eastern-plaguelands.lua:1762` -- "Turn in Duke Nicholas Zverenhoff to Duke Nicholas Zverenhoff." (generator artifact)
7. `Guides/Leveling/alliance-western-and-eastern-plaguelands.lua:627` -- "Accept Return to Chillwind Camp."
8. `ClassChains.lua:3584` -- "For The Principal Source: Use the Empty Dreadmist Peak Sampler to draw a sample of water from a pool at the top of the peak. ..." (verbatim Blizzard objective text)
9. `Guides/Leveling/alliance-blasted-lands-and-burning-steppes.lua:587` -- "For A Boar's Vitality: Bring three Blasted Boar Lungs, two Scorpok Pincers, and one Basilisk Brain to Bloodmage Drazial." (verbatim quest text)
10. `Guides/Leveling/mulgore.lua:519` -- "Read Simple Note in your bags. Turn in Simple Note to Harutt Thunderhorn." (templated starter, mildly useful)

---

## Q3. Provenance

### What `sourceStep` is [Read]

`internal/itineraryimport/import.go:394-403`: the importer splits each source guide
body on lines reading `step`, and records `SourceStep = <1-based index of that step>`.
So `sourceStep = 27` means "derived from step 27 of the source guide". It is used
to check route order against reference fixtures (`tests/lua/catalog.lua:69-108`,
`tests/fixtures/reference_itineraries.json`, which carries `sourceHashes` of the
Alliance and Horde source files). It appears on 10,985 goals (84 Leveling files,
39 Loremaster, 9 Class, 2 Dungeons).

### Where the source guide comes from

- [Read] `cmd/import-classic-leveling/main.go:18`: the default input is
  `~/Downloads/classic-leveling-dump/Guides-Classic/Leveling/` with files
  `LevelingHordeCLASSIC.lua` and `LevelingAllianceCLASSIC.lua` (lines 40, 43).
- [Read] The parser expects `<Addon>:RegisterGuide("Leveling Guides\...", {...}, [[ ... ]])`
  (`import.go:368, 372`), `step` separators (394), and line syntax
  `accept Name##id`, `turnin Name##id`, `kill N Name##id`, `talk NPC##id`,
  `|goto Zone x,y`, `|q id/obj`, `|only if Human`, `stickystart`, `ding`, `tip`,
  `|confirm` (`import.go:66-80`). It also skips titles containing "season of discovery",
  "startup guide", "hidden guides", "hardcore" (`import.go:64`).
- [Inferred, high confidence] That is the Zygor Guides Viewer guide language and file
  layout (`Guides-Classic/Leveling/Leveling*CLASSIC.lua`). The source is a dump of
  **Zygor Guides Classic**, a commercial subscription product with no open license.
- [Read] Loremaster tooling names Zygor outright:
  `internal/zoneauthoring/authoring.go:27-31`
  (`UpstreamRepo = "https://github.com/ErebusAres/ZygorGuidesRemaster-3.3.5a_WOTLK"`,
  pinned commit `9087c457...`), `cmd/author-zone-loremaster/main.go:33`
  ("clean Zygor Guides Remaster checkout"), and every `docs/loremaster/*.json` records
  hashes of `ZygorGuidesViewerRM/Guides/Leveling/ZygorGuidesAlliance.lua` and others
  (e.g. `docs/loremaster/alterac-mountains.json:12090-12097`). It is described as
  "advisory ordering evidence only" (`docs/zone-loremaster-guides.md:12-13`).
- [Read] The leveling guides were first committed on 2026-09-24 as "Ports ... the
  classic Horde paths" / "follows the classic route" (commits 094e10e, 26c44fa; the
  original file header said "This follows the classic route and is not rewritten for
  Forever yet."). Repo docs call it "the supplied reference" / "the supplied archive"
  (`docs/guide-authoring.md:41, 49`) and never name it in README or LICENSE.
- [Read] Other inputs: AllTheThings Forever data for giver IDs and pins
  (`docs/guide-authoring.md:97`), Wowhead Forever pages, WCLBox, the author's own
  `wow-database` export, QuestieDB/Questie for Loremaster facts
  (`docs/DEVELOPMENT.md:42-50`). A RestedXP Forever guide download was compared but
  "No starter route changes have been applied" (`docs/starter-rxp-comparison.md:3`).
  The Zephras Isle route branch was named `zephras-rxp-route` (PR #65), and its
  commit says "Reorder Zephras Isle onto the Skyborne speedrun" (a78419e). [Inferred]
  That ordering likely follows RestedXP. RXP's license was not checked.
- [Read] README and LICENSE carry no credits and no third-party notices. LICENSE is
  plain GPL-3.0 text, and the README says "GPL-3.0-or-later" (`README.md:93-95`).
- [Read] Contributors: one human, Tyler Akins (two emails; 213 commits co-authored by
  his own `t.akins@icloud.com`, consistent with agent-driven commits), plus 3 dependabot.

### What text is original

[Inferred] Imported text is generated by templates from the Zygor action lines.
The importer drops Zygor `tip` lines (`import.go:260`), so Zygor's prose tips were not
copied directly by this tool. The hand-written tricks in Q2 were added in later bulk
commits (e.g. Dartol's Rod and Ringo's canteen first appear in 53bc3cb "v0.4.0",
which added 17,945 lines of `ClassChains.lua`). Their origin cannot be determined from
the repo. Dungeon guides (`71745a3`, "Add a dungeon guide for every classic instance")
look hand-written and cite Wowhead dungeon quest lists.

### License chain verdict

[Inferred] **Not clean for the leveling, class, and Loremaster data.** Quest IDs and
coordinates are facts, but the step order, decomposition, and pin selection come from
a proprietary guide, and GuideMate offers no license grant from Zygor. About 579 goals
also embed Blizzard quest text verbatim. The dungeon guides are probably the author's
own GPL work. Still, given the rest of the repo, provenance cannot be proven step by
step. Safe use for a GPLv3 Questmark: read GuideMate as a pointer to which quests are
confusing, never as copied text or data.

---

## Q4. Fit

### Route data -> "Where" line [Read]

Shape: `route = { { mapID = <UiMapID>, x = <0..1>, y = <0..1>, label = "<NPC or place>", offMapText = "Travel to <NPC> in <Zone>." }, ... }`.
mapIDs are retail UiMapIDs (1432 Loch Modan, 1436 Westfall, 1453 Stormwind, 2521
Zephras Isle; 46 distinct). Coordinates are normalized, so they plug straight into
`C_Map` / world-position math.

| Goal kind | Goals with a route |
| --- | --- |
| accept | 96% (Leveling), 82% (Dungeons) |
| turnin | 99% (Leveling), 86% (Dungeons) |
| objective | 82-87% (Leveling/Loremaster), 29% (Dungeons) |

Totals: 17,861 points, 17,849 with `offMapText`. Only 108 goals have more than one point.

Fit [Inferred]: good for giver and turn-in pins. Weak for objective "Where":
- Objective pins are single points copied from Zygor `|goto` lines
  (`import.go:181-195`), not areas, so they cannot drive nearest-edge targeting
  or background-objective detection.
- `offMapText` is formulaic ("Travel to X in Zone.").
- Nothing is validated in the Forever client.

Indoor or dungeon descriptive text exists only in the hand-written dungeon files, e.g.
`Guides/Dungeons/HallOfThanes.lua:122` "Enter the Hall of Thanes from the cobwebbed corridor
left of the High Seat. Follow it down past the lava bridge." QuestieDB spawn data is the
better Where source.

### `dependsOn` / `requiredQuests` -> pre-dungeon reminder [Read]

- `dependsOn` is a list of **goal-ID strings local to one guide** (routing order). It
  is not a list of quest IDs. It can be resolved to quest IDs only through the
  `accept-<id>-` naming convention.
- `requiredQuests` is the portable one: `{ { mode = "all"|"any", quests = { <questID>, ... }, conditions = {...} } }`.
  Non-empty on 9,946 goals. A separate catalog `QuestPrerequisites.lua` has 530
  `ns:RegisterQuestPrerequisite({ quest = 759, mode = "any", quests = { 758 } })` entries.
- Dungeon guides already encode the reminder. Each of 33 dungeon files has a travel goal
  completed by `complete = { instance = <instanceID> }`, whose `dependsOn` lists every
  pickup for that dungeon. Example, `Guides/Dungeons/Deadmines.lua:668-683`:

```lua
        {
            id = "enter-deadmines",
            kind = "travel",
            conditions = ALLIANCE,
            text = "Enter the Deadmines through the Defias Hideout in Moonbrook. The instance portal is at the bottom of the mine.",
            dependsOn = {
                "accept-red-silk-bandanas",
                "accept-defias-brotherhood",
                "accept-collecting-memories",
                "accept-oh-brother",
                "accept-underground-assault",
            },
            complete = { instance = DEADMINES },
            persistCompletion = true,
            route = Westfall(0.426, 0.717, "Defias Hideout in Moonbrook"),
        },
```

  Each listed accept carries the giver pin, level/faction/race `conditions`, and its
  `requiredQuests`. That is everything needed for "You have 3 quests for this dungeon,
  and could still pick up X from Y at Z". The prerequisite chain comes from
  `prerequisite-*` goals (e.g. Red Leather Bandanas 153 -> Red Silk Bandanas 214,
  `Deadmines.lua:596`).
  Instance IDs used: 33 Shadowfang, 34 Stockade, 36 Deadmines, 47 RFK, 48 BFD,
  70 Uldaman, 90 Gnomeregan, 109 Sunken Temple, 129 RFD, 189 SM (4 wings),
  209 ZF, 229 LBRS/UBRS, 230 BRD, 289 Scholo, 329 Strat (2), 349 Maraudon (5), 389 RFC,
  429 Dire Maul (4).

Fit [Inferred]: the structure is exactly right and worth copying as a design. The data
itself should be rebuilt from QuestieDB plus Wowhead dungeon quest lists, for the
licensing reasons in Q3. Wings that share one instance ID (SM, Maraudon, DM, Strat,
LBRS/UBRS) need a wing-level split, which instance ID alone cannot provide.

---

## Format notes

### Guide file format [Read]

Plain Lua. Each file calls `ns:RegisterGuide({ id, title, category, revision, routeMode = "ordered", conditions, goals = { ... } })`.
Leveling, Class, and Loremaster files are fully literal tables. Dungeon files use local
helpers (`QuestState`, `Point`, `Westfall(...)`), and Miscellaneous files build goals in
`for` loops. The `goals` array order is the route order (`docs/guide-authoring.md:23`).
Goal kinds: accept, turnin, objective, gossip, note, travel, confirm.

One complete goal, verbatim (`Guides/Dungeons/Deadmines.lua:561-593`):

```lua
        {
            text = "Turn in The Defias Brotherhood to Gryan Stoutmantle.",
            route = {
                { y = 0.4752, mapID = 1436, label = "Gryan Stoutmantle", offMapText = "Travel to Gryan Stoutmantle in Westfall.", x = 0.5633 },
            },
            dependsOn = { "prerequisite-accept-155-the-defias-brotherhood", "prerequisite-objective-155-reviewed-escort" },
            id = "prerequisite-turnin-155-the-defias-brotherhood",
            kind = "turnin",
            conditions = {
                all = {
                    { faction = "Alliance" },
                    {
                        level = { min = 14 },
                    },
                    {
                        race = { 1, 3, 4, 7, 95 },
                    },
                },
            },
            complete = {
                quest = { id = 155, state = "completed" },
            },
            sourceStep = 27,
            requiredQuests = {
                {
                    mode = "any",
                    quests = { 142 },
                    conditions = {},
                },
            },
            useClientText = false,
            useClientPin = false,
        },
```

Other goal fields seen (counts of `key =` lines): `classAction` 3,205 (shared actions
in `ClassChains.lua`), `sourceGuide` / `sourceActionID` about 4,300 (Loremaster pointing
back at GuideMate's own leveling goals), `checkpointQuest` 2,335, `requiredLevel` 2,564,
`excludeWhen` 3,346, `useQuestNavigation` 3,534, `instructionOnly` 210,
`rememberPreparation` 71, `taxiDestination` 58.

### Size [Read]

| Folder | Bytes | Lines |
| --- | ---: | ---: |
| Loremaster | 22,450,794 | 315,550 |
| Leveling | 9,302,808 | 259,530 |
| Class | 1,580,677 | 44,498 |
| Dungeons | 1,223,943 | 25,799 |
| Miscellaneous | 105,755 | 3,092 |
| **Guides total** | **34,663,977 (about 33,850 KB)** | |
| `ClassChains.lua` | 626,596 | |
| `QuestPrerequisites.lua` | 76,996 | |

[Inferred] Most of the size is repeated per-goal `conditions` blocks and full
Leveling/Loremaster duplication. The unique hint-bearing content is a tiny fraction.

### Cadence and contributors [Read]

- First commit 2026-09-23 (`48d5a93`). Last commit 2026-11-14 (`342c82d`, "Mark project
  archived in README"). 545 commits: 317 in Sep, 217 in Oct, 11 in Nov.
- 93 release tags, v0.1.0 to v0.9.3. v0.9.3 is dated 2026-11-07.
- Guide commits: daily bursts 2026-09-23 to 2026-10-22 (up to 30 a day), then one
  a day on 11-03 to 11-07, then archive.
- Contributors: 1 human (Tyler Akins) + dependabot. Interface 16001 (`AGENTS.md:4`),
  the same as Questmark.
