# Questmark competitive landscape (WoW Forever, client 1.60.1)

Researched 2026-11-14. Tags: **[Read]** = seen at the cited URL or local file;
**[Inferred]** = deduced from what was read, not directly confirmed. CurseForge
comment threads are rendered client-side and could not be read by the fetch tool,
so user complaints come from GitHub issue trackers, fan guide sites and the
addon pages' own "known issues" text instead. Reddit search returned nothing
usable for "WoW Forever" (search engine indexing issue, not proof of silence).

---

## Verdict

**The thesis is half right. "Calm, predictable per-zone cards" is still
unoccupied. "The hint layer is the feature nobody else has" is no longer true
at the data level, though it is still true at the presentation level.**

1. **Hint data already exists, openly licensed.** Polestar Guides (about 290K
   downloads, the biggest Forever-native guide addon) publishes `forever-db`, an
   open Forever quest database with a "how a quest is done" layer:
   1,059 `gotcha` step texts covering 966 quests (about 18% of 5,287 quests),
   plus 3,401 `mechanic` rows classifying quests (use-item-on-mob 71,
   use-item-at-place 139, summon-by-item 37, escort 45, timed 53,
   multi-step-in-one-objective 61, object-click 432, and others), and a `note`
   table with kinds timer/spawn/danger/requirement/tip (0 rows so far, schema
   ready). The step/mechanic/note layer is **CC BY 4.0**; the rest is GPL-3.0.
   It ships in-game as the `LibForeverData` library addon (about 3.6 MiB).
   [Read: github.com/fitzforge/polestar forever-db/README.md, index.json,
   data/step.jsonl, data/mechanic.jsonl]
   Sample gotchas [Read]: "The bauble disappears 5 minutes after you loot it,
   and the whole quest has a 30-minute timer." (quest 28); "The sacks are
   objects you click in the world, not mob drops, and they are spread over
   three zones." (49); "You need two salves for each plant..." (4467).
   Many gotchas are low-value for Questmark ("needs a raid group", "holiday
   only") but a real share are exactly the spec's Hint line.
2. **Questie has a small hint layer too.** Questie's `extraObjectives` put a map
   icon plus a sentence on non-obvious steps ("Slay Vale Screechers and use
   Yeh'kinya's Bramble on their corpse.", "Use the Altered Black Dragonflight
   Molt on Bael'gar's corpse."). About 78 Classic strings and 2 Forever-only
   strings. [Read: github.com/Questie/Questie
   Localization/Translations/ExtraObjectives/*.lua]
3. **Nobody shows hints the way the spec does.** No addon found puts a short
   Hint line on the objective row of *whatever quests the player happens to
   have*, independent of following a route. Polestar's knowledge lives in a
   guide/route product; whether its gotchas display in-game outside the guide
   build is unverified (in the guide files they appear as author comments)
   [Read: guides/forever/class/druid/cure-poison.guide] [Inferred: not shown
   as a tracker line]. Questie's extraObjectives show only as map-icon
   tooltips. Quest TLDR rewrites objectives into checklists but has no
   trick knowledge.
4. **Demand is proven, even inside the leader.** Polestar's own tracker has
   recent player reports asking for exactly this: #2326 (guide said "Kill
   Screecher Spirit"; you actually use Yeh'kinya's Bramble on a dead Vale
   Screecher and talk to the spirit), #1590 ("talk to Neeru" but you must click
   through dialogue), #2347 ("Old Habits - need extra info": hidden prereq
   chain), #2346 (collection objects not pointed at), #2358 ("flag tricky
   quests"). The maintainer said mechanic-aware step data is "planned for
   0.4.1". [Read: github.com/fitzforge/polestar/issues] So the gap is closing
   from the guide side within weeks. [Inferred]
5. **Calm tracking is genuinely open.** Questie's proximity sort re-sorts on a
   timer pulse ("The Proximity Timer only pulses every 5 secs while running")
   [Read: Questie/Modules/Tracker/QuestieTracker.lua:988]. Questie users ask
   for current-zone-first sorting (#8294) and to stop Blizzard's auto-focus on
   new quests (#8313, a user wrote their own addon for it). No tracker found
   has pinned + event-only re-sort + cap + Elsewhere group as a stated design.

### What should change in the spec

- **Rewrite the differentiator** from "hints nobody else has" to "the hint for
  the quest you're on, on the card, without following a guide", plus calm
  tracking. Credit forever-db rather than competing with it.
- **Make forever-db / LibForeverData the primary data source** (quest DB *and*
  first-pass hints). It answers three open questions at once: runtime vs baked
  DB (LibForeverData can be an OptionalDep or embedded), Forever-quest
  coverage (97.8% of 5,408 quests published), and licensing (GPL-3.0 +
  CC BY 4.0, compatible with a GPL-3.0 addon). Contribute hints back through
  its `corrections/notes.json` (`add` with kind `tip`) instead of a private
  table. Caveat: forever-db's gotchas were distilled partly from "web quest
  database" pages including comments ("A quote's origin class: `comment`"),
  rewritten as facts; it claims no copied text ships [Read: rust/crates/
  forge-data/src/kb.rs]. That is the same Wowhead-derived risk the spec
  avoids. Decide consciously.
- **Downgrade QuestieDB as a source.** QuestieDB's own LICENSE says data with
  unclear provenance should be considered "all rights reserved" [Read: local
  QuestieDB/LICENSE.md]. Polestar uses it only "with the Questie maintainers'
  agreement" and can rebuild `--no-questie` [Read: polestar THIRD_PARTY.md].
  Do not bake QuestieDB data into Questmark without asking.
- **Drop "Research first: Forever GuideMate".** The repo is archived,
  read-only, "no longer maintained", and its guides are "being ported to
  RestedXP" [Read: github.com/TylerAkins/forever-guide-mate README, issue
  #160]. Its GPLv3 text is still usable but it is a dead end for collaboration.
- **Fix the "nothing touches combat state" claim.** Tooltip quest data
  (quest ID, objective text, counters) becomes secret values in combat on
  Forever; string ops on them fail [Read: Questie docs/forever-tooltip-
  secrets.md]. The background-objective "nameplate lights up / tooltip shows
  the quest line" plan must be out-of-combat only, or use only the quest-log
  API (which stays public in combat per the same doc).
- **Handle Forever objective shapes.** Forever quests can gain objectives
  mid-quest, have optional objectives, and objectives in random order
  [Read: Questie issues #7929, #7930, #7931]. The Do-line model must allow
  objectives appearing and an "optional" marker.
- **Own Blizzard's super-track.** Native auto-focus on quest accept is a live
  complaint (#8313). Spec should say Questmark decides supertrack, or
  suppresses auto-focus when its native-waypoint setting is off.
- **Reconsider phases 10-11 (replace Questie and the quest log).** That space
  is saturated: Questie, ForeverQuest, Questdon, QuestForever, Everything
  Quests, Quester Forever, Quest Completist, Forever Quest Pins all do pins and
  quest browsing. Coexisting with a pin addon (Questie exposes a public API:
  `Public/RegisterForQuestUpdates.lua`, `GetQuestObjectiveIconForUnit.lua`
  [Read: local Questie_Forever.toc]) is cheaper and is where Questmark adds
  nothing unique anyway. Keep "Available nearby" only if data is free from
  LibForeverData.
- **Dungeon mode: keep in-dungeon cards, treat the pre-dungeon reminder as
  commodity.** At least six addons already do dungeon quest lists with
  missing/in-log/done states (see "Other Forever quest addons").

---

## Feature-overlap matrix

Y = has it, P = partial / weaker form, N = no, ? = could not verify.
Columns are Questmark features.

| Addon | Cards per quest | Do/Where lines | Live arrows | Calm tracking rules | Categories | Background objectives | Dungeon mode | Hints for tricky steps | In-game learning | Map pins | Quest log replacement |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Questie (Forever) | N (line tracker) | P (objective text; extraObjectives) | N (uses TomTom) [Inferred] | P (auto-track, sort modes incl. proximity on 5 s pulse) | P (filters) | N | N | P (~78 Classic + 2 Forever extraObjectives) | P (QuestieTrace collector) | Y | P (Journey browser + notes) |
| ForeverQuest | P (compact/focused/zone views) | P (Kill/Talk/Collect nameplate labels) | P (dotted minimap line, straight) | P (auto destination, pin, priorities) | ? | N | ? | N | P (per-char location corrections) | Y | P (quest details on right-click) |
| Dungeon Quests Forever | N (step timeline) | P (current objective) | Y | P (auto-track chain progress) | N | N | Y | P (pre-quest order) | N | Y | N |
| UpQuest Forever | ? | ? | Y (compass) | ? | ? | N | P ("dungeon Journeys") | N | N | ? | N |
| Everything Quests | N (tracker sections) | N | P (needs TomTom on Classic; Forever ?) | P (sort modes, filters, auto-hide) | P (sections) | N | N | N | N | Y | Y |
| QuestForever | N (pins only) | P ("Kill Kobold Vermin", "Use Wanted Poster" in tooltips) | P (on marker click) | N | P (profession/event gating) | P (camps grouped as one dot) | N | P (escort routes, explore spots) | Y (records givers, /qf export) | Y | N |
| TomTom | N | N | Y | N | N | N | N | N | N | P (waypoint pins) | N |
| Polestar Guides | N (guide window) | Y (guide steps) | Y (terrain-aware) | N (route-driven) | P (class/prof/rep guides) | P ("While you're here") | P (dungeon journal; hides in instances) | Y (forever-db gotchas, escort notes) | Y (Recorder, shares by default) | Y | N |
| Questdon | P (tracker tabs nearby/zone/level) | N | Y (compass) | P | ? | N | P (dungeon lists) | P (breadcrumb warning, /qd why) | Y (collect-only mode shares data) | Y | P (quest book) |
| Quest TLDR | N | Y (checklist, steps, text-derived location hints) | N | N | N | N | N | P (no trick data) | N | P (waypoint on click) | N |

---

## Addons in the spec's table

### Questie (Forever bundle)

- **What it is:** Questie + QuestieDB, Forever supported since 12.0.1; installed
  locally is v12.6.5 (TOC 16001) while CurseForge has v12.9.0 (Nov 14, 2026).
  222.9M downloads across all flavors; GPLv3 on CurseForge.
  [Read: local Questie_Forever.toc; curseforge.com/wow/addons/questie;
  mmonster.co questing-and-leveling]
- **Features:** map/minimap pins (givers, objectives, turn-ins), tracker
  (sort by complete/level/proximity/zone/zone-proximity; auto-track default on),
  nameplate and unit/object tooltips, auto accept/turn-in, Journey (quest
  browser, by zone/faction, player "Adventure Notes"), party objectives comms,
  DBM integration, quest item buttons. [Read: Questie_Forever.toc file list,
  QuestieOptionsTracker.lua:395-403, QuestieOptionsDefaults.lua:87,120]
- **Hint-like content:** extraObjectives (icon + sentence for odd steps);
  ~78 Classic, 2 Forever ("Use the Flutterfly Swatter", "Knock on Kuramaa's
  Stump"). Shipped Forever builds strip the correction bodies at package time
  ("Static body stripped at package time") [Read: local QuestieDB/src/
  corrections/Forever/legacy/classicQuestFixes.lua:24].
- **Data gaps:** Forever-new quests partly missing; Ruins of Lordaeron and
  Hall of Thanes dungeon quests not covered (Nov 12) [Read: space4games.com].
  Many open Forever data bugs (wrong availability for classes, missing
  prereqs, breadcrumbs) [Read: Questie issues #8264, #8281, #8286, #8291].
- **License:** Questie code moving to GPL-3.0; QuestieDB data effectively
  "all rights reserved" when in doubt [Read: local QuestieDB/LICENSE.md].
- **Complaints:** tracker auto-focus (#8313), zone order (#8294), minimized
  category lost on reload (#8321), tooltip quest lines vanish for quests it
  doesn't know (#8027), tracker visibility/tracking toggles out of sync (#8196).
- **Useful for Questmark:** remaining-work doc and tooltip-secrets doc are
  the best public notes on Forever API restrictions
  [Read: FOREVER_WORK_LEFT_TO_DO.md, docs/forever-tooltip-secrets.md].
  Note: installed QuestieTrace has only Classic-family TOCs
  (11509/20506/38002/50504), so that copy does not load on Forever
  [Read: local QuestieTrace-Classic.toc].

### ForeverQuest (AnacondaGaming)

- v0.22.x, updated Nov 14, 2026; 19,459 downloads; All Rights Reserved; no
  source link. [Read: curseforge.com/wow/addons/foreverquest]
- **Features:** clustered world-map markers, nearby pickup list sorted by
  distance, automatic or pinned destination, dotted straight-line minimap
  bearing, nameplate labels (Kill/Talk/Collect), replaceable tracker
  (compact, focused, zone-grouped), objective chooser (`/fq objectives`),
  skip one inaccessible spot, per-character location corrections
  (`/fq location`), auto accept/turn-in, reward comparison, profiles.
- **Weaknesses (fan guide):** bundles 3,772 legacy Classic quest records "not
  verified Forever locations"; guidance is straight-line, not terrain-aware;
  nearest-destination is distance only; temporary pins and skips reset on
  reload/logout. [Read: wowforeveraddons.wiki/questing/wow-forever-quest-addon]
- **Hints:** none.

### Dungeon Quests Forever (Daelerbackbi)

- v0.3.27beta, updated Nov 6, 2026; 9,584 downloads; All Rights Reserved; no
  source. [Read: curseforge.com/wow/addons/dungeon-quests-forever]
- **Features:** step-by-step guide per dungeon incl. pre-quests (faction
  filtered), auto tracking incl. chain validation at login, current-objective
  display, timeline with checkboxes, guide arrow to objective or entrance,
  multiple pins when a step can be done in several places, targets panel
  (target and mark NPC), quest item button, party sync, automation (Shift
  pauses), collapsible window, EN/FR, works with/without Questie and TomTom.
- **Gaps:** class quests not included; Ruins of Lordaeron and Hall of Thanes on
  beta data.
- **Hints:** none beyond chain order. Closest overlap to Dungeon mode's
  *pre-dungeon* part; it does not do in-dungeon descriptive Where text
  [Inferred from feature list].

### UpQuest Forever (Mathew64)

- Updated Nov 12, 2026; 382 downloads; All Rights Reserved; no source; site
  upquest.feebledgamer.workers.dev. [Read: curseforge.com/wow/addons/upquest-forever]
- **Features:** regional and dungeon "Journeys", objective tracking, navigation
  compass alongside Forever's tracker, item catalog search, group/guild
  tools (rosters, recruiting, guildmate location sharing). Broad and thin.
- **Hints:** none. Not a meaningful competitor at 382 downloads.

### Everything Quests (Wheelbarrel00)

- v2.10.0, Nov 8, 2026; 39,364 downloads; **MIT**; source
  github.com/wheelbarrel00/EverythingQuests (0 open issues).
  [Read: curseforge.com/wow/addons/everything-quests; gh api]
- **Features:** replaces Blizzard quest UI on Retail/Classic/TBC/Forever;
  separate EQ Objective Tracker (sort modes, filters, auto-hide rules,
  sections); nameplate icons; **bag-item tooltips showing which quest needs an
  item and how many** (Questmark's keep-item idea); Forever map markers from
  its own data; Chain Guide for every Forever chain; Quest Browser with
  "why you can't take this yet"; Quest History (5,000 turn-ins, cross-char);
  group progress; automation (Alt pauses); 6 translations.
- **Data:** Forever quest data "largely from AllTheThings, used under the MIT
  License" - confirms the spec's ATT/MIT note.
- **Known issues on its page:** same-name duplicate quests at givers, quests
  appearing too early, Zephras Isle / Moonglade quests shown to wrong
  characters, zone progress stops short of 100%.
- **Hints:** none.

### QuestForever (Solindius, ForeverUI project)

- v1.0.4, Nov 12, 2026; ~5,888 downloads; **GPLv3**; no repo link.
  [Read: curseforge.com/wow/addons/questforever]
- **Features:** "!"/"?" pins and objective dots on map/minimap; filtering by
  faction/race/class/level/reputation/chain progress; one icon per giver;
  mob camps as one dot; **plain-language step tooltips** ("Kill Kobold
  Vermin", "Use Wanted Poster"); waypoint arrow on marker click; item-drop
  quests show drop area, escorts/patrols show routes, Explore objectives show a
  spot; hides offers a giver doesn't actually have after you talk to them;
  holiday/invasion/profession gating; controller mode; records quest givers it
  sees with `/qf export` (the spec's "where collector" pattern, already shipped).
- **Hints:** partial (escort route, explore spot). No trick text.

### TomTom (Cladhaire, Ludovicus)

- v4.4.1-release, Nov 7, 2026; 93.1M downloads (all flavors); All Rights
  Reserved (TOC and CurseForge). TOC lists interface 16001 among others.
  [Read: local TomTom.toc; curseforge.com/wow/addons/tomtom]
- **How the arrow works on Forever [Read: local files]:**
  - Position: HereBeDragons `GetPlayerWorldPosition()` -> `UnitPosition("player")`
    (HereBeDragons-2.0.lua:661-667); map position via
    `C_Map.GetBestMapForUnit` + `C_Map.GetPlayerMapPosition` (core/position.lua:31,42).
  - Facing: `GetPlayerFacing()`; angle = bearing - facing (crazy_arrow.lua:395-406).
  - Rotation: sprite-sheet cell chosen via `SetTexCoord` per theme
    (theme_modern.lua:83-98); minimap arrows rotate by 8-arg `SetTexCoord`
    (minimap_pins.lua:117-121).
  - Hidden when distance is nil (other continent or instance) or facing is nil
    (crazy_arrow.lua:366-377, 398-404). Arrival arrow below arrive distance.
  - Distance callbacks are throttled in an OnUpdate ticker (distance.lua:91-95).
  - Only explicit secret-value handling: `issecretvalue(UnitName("target"))`
    in the coordinate block (coord_block.lua:230). Confirms the spec: position
    and facing are not restricted.
  - Quest objective waypoints work on Forever via `C_SuperTrack` /
    `C_Map.GetUserWaypoint` (modules/poi.lua; CHANGELOG v4.4.0).
  - For integration: public callbacks (`WaypointAdded`, `ArrowTargetChanged`,
    ...) and `TomTom:SuppressFeature(owner, feature)` (CHANGELOG v4.4.0).
- **Hints:** none (pure navigation).

---

## Other Forever quest/guide addons (not in the spec table)

All [Read] from their CurseForge pages unless noted; downloads as of Nov 14, 2026.

| Addon | What | Downloads | License / source | Hints? |
|---|---|---|---|---|
| **Polestar Guides** (0xFitz) | Full 1-60 leveling guide built by simulation; terrain-aware arrow; travel planner; quest pins; dungeon journal; Recorder + desktop client (shares play by default); community guides; publishes **forever-db / LibForeverData** | ~290,300; 301 GitHub stars, 459 open issues | GPL-3.0 + CC BY 4.0 data layer; github.com/fitzforge/polestar | **Yes** (data); escort notes; "talk through dialogue" lines |
| **Adventure Guide Forever** (cjber) | Zone chains as chapters, "Journeys", Shortest Path Forever routing, ready hand-ins first | 71,471 | GPL-3.0; github.com/cjber/adventure-guide-forever | No ("not a complete levelling walkthrough") |
| **Questdon** (DonCoohd) | Questie-like helper with own DB (DonData, DonMap): pins, nameplates, tracker tabs, compass, quest book, chains, breadcrumb warnings, `/qd why`, `/qd nothere`, collect-only mode | 18,792 | MIT; github.com/WoW-Forever-Addons/questdon | Partial (why-unavailable, breadcrumbs) |
| **Quester Forever** (HerrHaseGermany) | Lightweight pins, target-macro bar for quest mobs, learns NPC-objective links from tooltips | ~8,700 | MIT; github.com/HerrHaseGermany/Quester | No |
| **Nullgate's Quest Tracker Forever** (ex-Bleakfiber's) | Tracker replacement: zone/all views, collapsible zones, combat-safe item buttons, Wayfinder arrow, automation | 6,163 | All Rights Reserved | No |
| **Forever Dungeon Quests** (Sundee) | One window: dungeon quests tagged Missing / In Log / Done, giver + /way coords, key/attunement notes | 4,341 | MIT; github.com/ImSundee/forever-dungeon-quest | Partial (key notes) |
| **Forever GuideMate** (murgy) | Next-step guide tracker, class/dungeon/raid/leveling guides | 3,865 | GPLv3; **archived** | Some in guide text |
| **ForeverSecrets** (Loyftwa) | Secret/collectible guides (Dawn Waker, Cozy Sleeping Bag, library books) | 2,606 | All Rights Reserved | Puzzle steps only |
| **Loreward** (Renrut) | Completionist guide on RestedXP engine, lore notes, "Find your quest" | ~2,512 | CC BY-NC-SA 4.0 (incompatible with GPL) | Some (hand-written step text) |
| **(Forever) Quest TLDR** (AlexBrandson) | Condenses quest text into checklists and numbered steps; text-derived location hints ("In the mine, northeast") | 1,324 | All Rights Reserved | No trick data, but closest to Do/Where |
| **Forever Single Quest Hint** | Right-click "Hint" reveals one quest's objective on the map (for players playing with markers off) | 655 | All Rights Reserved | Name only; not a text hint |
| **Dungeon Assistant** (_Shadowblade_) | 326 dungeon quests from Wowhead Forever data, chains, routing incl. flights/boats | 617 | All Rights Reserved | Partial ("Needs step 3", pre-quest labels) |
| **Almanac** (Vedek) | Per-zone/dungeon quest lists with Available/Unavailable(reason)/Completed, XP/gold | 201 | MIT; github.com/NigelStruble/Almanac | Partial (unavailable reasons) |
| **Wayfinder Forever** (Beanson) | Free guide engine, in-game guide editor, danger warnings where testers died | 115 | MIT | No |
| RestedXP (Forever) | Paid speedrun guides; 1-20 free; 35-60 Forever routes WIP (Oct 2) | n/a | Proprietary | Unknown [Read: kami-labs.fr] |
| Others seen in search, not inspected | Leveldon, Navryk, Absolute Leveling, 4Ever Leveling, Quest Completist (~5,100 quests), Forever Quest Pins (ATT data), Forever Quest Tint (marks Forever-new quests), DungeonQuest: Forever, Forever Dungeon Journal, foreverautoquest, No Quest Hints - Forever | - | - | Not checked |

Takeaway: the Forever addon scene is about ten weeks old and already crowded
for pins, trackers, dungeon lists and guides. Hint *text attached to the
player's own quests* is the remaining open slot.

---

## Ideas worth taking

1. **forever-db as the hint and quest backbone** (see Verdict). Map its
   `mechanic` kinds to Hint templates: `use-item-on-mob` / `summon-by-item` /
   `use-item-at-place` / `escort` / `timed` / `multi-step-in-one-objective`
   are the spec's "non-obvious step" categories, already classified for
   3,401 rows. Use its stable step/note IDs as Questmark's hint keys so
   player notes can be submitted upstream.
2. **Hint confidence label.** forever-db marks `confidence: "unconfirmed"`;
   ForeverQuest shows a "location-source label" (legacy vs verified). Show a
   subtle marker on unconfirmed hints.
3. **Escort note** (Polestar): "if the NPC is not there, wait for respawn" -
   generic hint auto-generated for every escort quest.
4. **"Talk to" means click through dialogue** (Polestar #1590): auto-hint for
   talk objectives whose progress needs gossip.
5. **Breadcrumb warning** (Questdon): warn that accepting a breadcrumb removes
   another quest's XP.
6. **"Why can't I take this?"** (Questdon `/qd why`, EQ Quest Browser, Almanac):
   for the Available-nearby group, show the blocking reason.
7. **Skip one spot, not the quest** and **objective chooser** (ForeverQuest):
   fits the hysteresis/edge-targeting arrow model.
8. **"While you're here"** (Polestar): nearby progress for other quests - a
   good fit for background objectives.
9. **Combat-safe quest item buttons** (Nullgate tracker states they work in
   combat): pre-built secure buttons, as the spec already plans.
10. **Text-derived Where** (Quest TLDR): mine phrases like "in the cave
    northeast" from quest description text for indoor Where lines when no
    position exists. Cheap, no licensing issue (Blizzard text in client).
11. **Forever-new quest marker** (Forever Quest Tint): flag Forever-only quests
    on cards, since data and hints are thinnest there.
12. **Bug/report string** (Polestar bug button, `/fq debug`): one click
    produces a paste-ready report (quest ID, objective, position, build).
    Pairs with the spec's note-export.
13. **TomTom integration hooks**: listen to `ArrowTargetChanged` and use
    `SuppressFeature` rather than fighting TomTom when both are loaded.

## Complaints worth fixing

| Complaint | Source | Questmark answer |
|---|---|---|
| Guide doesn't say the target is summoned with an item on a corpse | Polestar #2326 [Read] | Hint line (core thesis) |
| "Talk to X" but you must click through dialogue | Polestar #1590 [Read] | Auto-hint for talk objectives |
| Hidden prerequisite chain not explained | Polestar #2347 [Read] | Hint kind "requirement" |
| Guide points at turn-in, not at the objects to collect | Polestar #2346 [Read] | Per-objective Where, not per-quest |
| Want tricky/hard quests flagged; "too hard alone" | Polestar #2358, #2357 [Read] | Elite/group flag + danger hint |
| Tracker re-sorts on a timer | Questie QuestieTracker.lua:988 [Read] | Event-only re-sort (rule 4) |
| Current zone should come first | Questie #8294 [Read] | Zone cards + Elsewhere group |
| New quests auto-focus and grab the arrow | Questie #8313 [Read] | Own supertrack; never auto-focus |
| Collapsed state lost on /reload | Questie #8321 [Read] | Persist collapse in SavedVariables |
| Route only the quests I pick | Adventure Guide #772 [Read] | Player-picked order (core non-goal of routing) |
| Keep the game's own quest markers alongside | Adventure Guide #764 [Read] | Don't hide native markers; optional native waypoint |
| Want an info-only mode with routes off | Adventure Guide #715 [Read] | Questmark is that mode |
| Old/unverified coordinates point to wrong spots | wowforeveraddons.wiki on ForeverQuest [Read] | Prefer verified data; label confidence |
| Pins/skips reset on reload | wowforeveraddons.wiki on ForeverQuest [Read] | Persist pins/ignores |
| Duplicate same-name quests, wrong class/race availability | EQ page, Questie #8264/#8281 [Read] | Use quest IDs everywhere; Forever-specific DB |
| Quest tooltip lines disappear for unknown quests | Questie #8027 [Read] | Never hide native rows you can't replace |

## Not verified

- CurseForge comment text for every addon (client-rendered; fetch returned only counts:
  ForeverQuest 6, DQF 8, EQ 66, QuestForever 19, Questdon 35).
- epiccarry.com Questie article (HTTP 403).
- Whether Polestar displays forever-db gotchas in-game today.
- UpQuest Forever internals (no source, sparse page).
- Everything Quests' arrow behavior on Forever specifically.
