# Questmark data sources and licenses

Research date: 2026-11-14. Answers the SPEC.md open question "Exact licenses for QuestieDB and
AllTheThings data", plus wiki coverage of new Forever quests and the licensing note.

Tags: **[Read]** = verified at the cited URL or local file during this research.
**[Inferred]** = my reasoning or interpretation, not stated by the source. This is not legal advice.

## Summary table

| Source | License (SPDX) | Evidence | Can Questmark use it, and how | Obligations |
| --- | --- | --- | --- | --- |
| Questie (addon + its `Database/`) | None. GitHub reports `NOASSERTION`. LICENSE.md: "when in doubt consider Questie as 'all rights reserved'", but team "is alright with others forking ... or copying code from it under the GPLv3 terms". Partial GPL-3.0 (named contributors only) | [LICENSE.md](https://github.com/Questie/Questie/blob/master/LICENSE.md); local `Questie\LICENSE.md` (identical to upstream) [Read] | Yes for reading data at runtime via QuestieDB (below). Copying under GPLv3 is tolerated by the team, with stated residual risk | If copied: GPLv3 terms, do not use the Questie name/logo, attribution |
| QuestieDB (separate addon/repo) | Same as Questie: `NOASSERTION`, all-rights-reserved fallback, team permits GPLv3 copying. Contributions after 2026-10-21 are GPLv3 | [Questie/QuestieDB LICENSE.md](https://github.com/Questie/QuestieDB/blob/master/LICENSE.md), [PROVENANCE.md](https://github.com/Questie/QuestieDB/blob/master/PROVENANCE.md); local `QuestieDB\LICENSE.md` [Read] | (a) Optional runtime dependency: yes, cleanest option. (b) Build-time bake-in with attribution: permitted per the team's GPLv3 statement, but not a clean license chain | (a) none beyond not bundling it. (b) GPLv3, credit, no Questie name/logo, provenance caveats below |
| AllTheThings (incl. Forever quest data) | `MIT` (repo-wide LICENSE, "Copyright (c) 2026 AllTheThings WoW Addon") | [LICENSE](https://github.com/ATTWoWAddon/AllTheThings/blob/master/LICENSE) [Read]; Forever data in `.contrib/.db/forever/` [Read] | Yes. Build-time input for Forever quest list, givers, coords, levels. MIT is GPLv3-compatible | Keep the MIT copyright + permission notice in shipped credits/LICENSE-THIRD-PARTY |
| Warcraft Wiki (warcraft.wiki.gg) text | `CC-BY-SA-4.0` (text). Media per file page. Blizzard IP noted | [Warcraft_Wiki:Copyrights](https://warcraft.wiki.gg/wiki/Warcraft_Wiki:Copyrights); API `rightsinfo` [Read] | Yes for hint text, adapted into GPLv3 (one-way compatible). Coverage of new Forever quests is poor (see section 3) | Attribution (page + history link, license, modification notice), share-alike: resulting hint data must be GPLv3 or BY-SA 4.0 |
| Guidelime (addon) | No SPDX. `X-License: All Rights Reserved` in the .toc. CurseForge: "All Rights Reserved" | [Guidelime-Vanilla.toc](https://github.com/max-ri/Guidelime/blob/master/Guidelime/Guidelime-Vanilla.toc), [CurseForge](https://www.curseforge.com/wow/addons/guidelime) [Read] | No reuse of code or text | n/a |
| Guidelime guide modules (TUGs, Sage) | TUGs: "All Rights Reserved" (CurseForge). Sage: unverified (page 404) | [guidelime_tugs](https://www.curseforge.com/wow/addons/guidelime_tugs) [Read] | No, unless an author grants explicit permission | n/a |
| LevelForge (addon) | `MIT` per CurseForge sidebar. No public source repo found | [CurseForge](https://www.curseforge.com/wow/addons/levelforge) [Read] | Code: yes, but nothing to reuse (no repo). Guides: no (user-authored on levelforge.dev, no license stated) | MIT notice if code used |
| Wowhead | Proprietary. ZAM ToS forbids spiders, robots, crawlers, data mining tools | [wowhead.com/tos](https://www.wowhead.com/tos) -> [ZAM terms](https://corp.fanbyte.com/legal/terms) [Read] | Manual only: read, then write the hint in our own words. No scraping, no copying comments | None if nothing is copied |

## 1. Questie and QuestieDB

### What the license files say [Read]

- `gh api repos/Questie/Questie/license` -> `spdx_id: NOASSERTION`, path `LICENSE.md`.
  Same for `Questie/QuestieDB`. Neither repo has an SPDX-recognizable license.
- Questie `LICENSE.md` (upstream and the installed copy at
  `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Questie\LICENSE.md` are byte-identical):
  - "Because Questie historically never had a proper license ... when in doubt consider Questie as 'all rights reserved'."
  - "the Questie team is alright with others forking the repository or copying code from it under the GPLv3 terms, but we can not promise all contributors are."
  - "This does NOT extend to the Questie name and logo!"
  - Named contributors (Muehe, Logon, TheCrux/BreakBB, Drejjmit, Cheeq, TechnoHunter, Yttrium, Sommos, anon1231823, HeresHavi) have put their contributions under GPLv3.
  - "submitting pull requests after 21.10.2026 will be counted as consent for licensing your contribution under the GPLv3 license."
  - Libraries in `Libs/` carry their own licenses; `Icons/` has its own `LICENSE.md` + `MIT.txt`.
- There is no separate data license. The license priority is: per-file notice, then subdirectory LICENSE, then root LICENSE.md. No file under the database was found with its own notice. The Questie README contains no license text (grep for licen/GPL/copyright: no matches).

### QuestieDB is a separate addon and repo [Read]

- Repo: [github.com/Questie/QuestieDB](https://github.com/Questie/QuestieDB), created 2026-07-27, active (pushed 2026-11-14).
- Installed copy: `...\AddOns\QuestieDB\` (v1.0.14, `QuestieDB_Forever.toc`, `## Interface: 16001`, `X-Flavor: Forever`, `X-Mode: baked`, `X-Contract-Version: 4`). Author line: "Code: Logonz Data: Muehe/TheCrux(BreakBB)/Drejjmit/Dyaxler/Cheeq/TechnoHunter/Yttrium/Everyone else".
- Questie's Forever toc lists `## OptionalDeps: QuestieDB, ...` and `## X-QuestieDB-Contract: 4`, so Questie itself consumes QuestieDB as a separate addon.
- QuestieDB `LICENSE.md` copies Questie's model and adds: "QuestieDB's initial data, schema and corrections were imported from Questie ... That content and its later modifications are subject to Questie's licensing". `PROVENANCE.md` records the import from Questie commit `454b9d0` (2026-09-15).
- It publishes a documented consumer API ([docs/api.md](https://github.com/Questie/QuestieDB/blob/master/docs/api.md)): globals `LibQuestieDB`, `QuestDB`, `NpcDB`, `ItemDB`, `ObjectDB`, plus a `RequireContract(n)` version check. The doc says to declare `## Dependencies: QuestieDB`.
- Data is stored as CBOR blocks in TOC metadata (Baked mode) and read at runtime "with no file I/O".

### Data provenance caveats [Read]

- Questie's scraper README: "This is a scraper that runs on wowhead.com/classic ... Currently, it is only used to scrape SoD related data." The item-drop README covers both Wowhead scraping and CMaNGOS DB extraction ([scraper/README.md](https://github.com/Questie/Questie/tree/master/ExternalScripts(DONOTINCLUDEINRELEASE)/scraper)).
- CMaNGOS: `cmangos/classic-db` is `GPL-3.0` and `cmangos/mangos-classic` is `GPL-2.0` (GitHub license API).
- QuestieDB's Forever layer: "This is not complete new Forever content". Its generated delta-base comes from an offline path (`/home/logon/projects/forever-base-db/...`) that is not public, so its upstream provenance **cannot be verified**.

### Can a GPLv3 addon use it?

- **(a) Optional runtime dependency: yes.** [Inferred] Questmark would only call QuestieDB's published API in a separately installed addon, without copying or distributing its files. That does not create a derivative distribution of QuestieDB, so its license does not bind Questmark's distribution. Use `## OptionalDeps: QuestieDB` (not `Dependencies`, which the API doc suggests) and degrade gracefully when it is absent. Check `RequireContract(4)` and handle failure. Do not ship QuestieDB inside the Questmark zip.
- **(b) Bake its data in at build time with attribution: permitted by the maintainers' stated position, but not a clean chain.** [Inferred]
  - The team explicitly allows copying "under the GPLv3 terms", and Questmark would be GPLv3, so the team's position allows this.
  - Residual risk: by the team's own statement, not all historic contributors consented, and they say "when in doubt consider ... all rights reserved".
  - Mitigating [Inferred]: bare facts such as quest IDs, NPC IDs and coordinates are weakly protected by copyright in the US. The EU has a sui generis database right, so this is jurisdiction-dependent.
  - Inherited taint: part of the data was scraped from Wowhead against ZAM's ToS (see section 5).
  - If baked: credit Questie/QuestieDB, record the source commit, do not use the "Questie" name or logo, and ship GPLv3.
  - Recommendation [Inferred]: prefer (a). Use (b) only for the narrow fields Questmark truly needs, and prefer ATT (MIT) for anything ATT covers.

## 2. AllTheThings (ATT)

- **License: MIT** [Read]. `gh api repos/ATTWoWAddon/AllTheThings/license` -> `spdx_id: MIT`, full text "MIT License / Copyright (c) 2026 AllTheThings WoW Addon". It is a repo-wide LICENSE with no separate data license; the data lives in the same repo under `.contrib/.db/`, so MIT covers it. The ATT org's other repos: the 2021-2024 archive is `NOASSERTION`, and the 2021-2026 archive is MIT.
- `DFortun81/AllTheThings` redirects to `ATTWoWAddon/AllTheThings` [Read].
- **Forever data exists** [Read]. `.contrib/.db/forever/` holds:
  - zones (incl. new ones: `riverglades.lua`, `shendralas.lua`, `zephras isle.lua`, `mount hyjal.lua`, `timbermaw hold.lua`)
  - dungeons (incl. new: `barrow deeps`, `hyjal summit`, `alcaz prison`, `blackmaw hold`, `hall of thanes`, `krol'dok stronghold`, `manor mistmantle`, `ruins of lordaeron`, `the drowned city`, `the shaper's terrace`)
  - `.nyi/quests.lua` and `.hqt/hidden quest triggers.lua`
  - `MissingQuests.txt` lists
  - Wago DB2 CSVs for build `1.60.1.70938`
- Sampled quest counts (lines matching `q(`, which include faction variants): Riverglades 179, Zephras Isle 161, Shen'dralas 39. Mount Hyjal has 1, so it is mostly exploration and flight paths so far.
- Fields per quest include `qg` (giver NPC), `coord`, `lvl` and `timeline = { TIMELINE.ADDED_1_60_1 }`. These are structural data, not hint prose.
- **Spec claim "MIT, per Everything Quests": confirmed** [Read]. The Everything Quests CurseForge page says: "Much of WoW Forever's quest data comes from AllTheThings, used under the MIT License," and "Everything Quests knows 570 quests new to Forever, and 552 of them have a marker". The ATT LICENSE itself confirms MIT.
- Obligation: include ATT's copyright and permission notice in a third-party notices file. MIT can be combined into a GPLv3 work [Inferred, standard FSF compatibility].
- Provenance note [Inferred]: ATT data is community-curated. I found no evidence of Wowhead scraping in the README; one credit line mentions a Wowhead guide. Not exhaustively audited.

## 3. Warcraft Wiki (warcraft.wiki.gg)

### License [Read]

- [Warcraft_Wiki:Copyrights](https://warcraft.wiki.gg/wiki/Warcraft_Wiki:Copyrights): "All textual and graphical content on Warcraft Wiki that we may lawfully license is licensed to you" under CC BY-SA 4.0.
  - Images and audio: licensed per file page.
  - "Warcraft content and materials are the intellectual property of Blizzard Entertainment."
  - Pages created before Oct 2023 are adapted from Fandom's Wowpedia.
- The MediaWiki API `meta=siteinfo&siprop=rightsinfo` returns `https://creativecommons.org/licenses/by-sa/4.0`.
- Caveat [Inferred]: quoted quest text (Description/Progress/Completion sections) is Blizzard's text, not the wiki's to license. Only community-written prose (Notes, walkthrough) is cleanly CC BY-SA.

### CC BY-SA 4.0 -> GPLv3 compatibility [Read]

- [CC compatible licenses](https://creativecommons.org/share-your-work/licensing-considerations/compatible-licenses/): GPLv3 was declared BY-SA-compatible for 4.0 "on 8 October 2015". "compatibility with the GPLv3 is one-way only": you may license adaptations of BY-SA 4.0 material under GPLv3, but not the reverse.
- [ShareAlike compatibility: GPLv3](https://wiki.creativecommons.org/wiki/ShareAlike_compatibility:_GPLv3) sets these conditions:
  - "the adapter has to comply with the BY-SA attribution and marking requirements"
  - "GPL-style attribution would satisfy the expectations of BY-SA licensors"
  - comply with the GPL source requirement ("Do not apply the GPLv3 if you cannot comply with the source requirement")
  - "both licenses apply and downstream users must comply with both licenses"

### What Questmark must do (from BY-SA 4.0 legal code s.3(a), s.3(b)) [Read], applied [Inferred]

1. Per hint entry, keep `source` = wiki page title + revision URL (`oldid`). In a shipped `CREDITS` file, name "Warcraft Wiki contributors", link each source page or its history, and link CC BY-SA 4.0. Section 3(a)(2) allows doing this "by providing a URI or hyperlink to a resource that includes the required information".
2. State that the text was modified (LLM rewrite plus human edit).
3. License the hint data (and the addon) GPL-3.0-or-later and include the GPL text (s.3(b)(1)-(2)). The hint table is plain Lua, so it is its own preferred form and the source requirement is trivially met.
4. Add no extra restrictions or DRM.

### Coverage of new Forever quests [Read], from MediaWiki API queries on 2026-11-14

- Wiki zone pages exist: Riverglades (8.4 KB), Zephras Isle, Shen'dralas, Skyborne, Krol'dok Stronghold, World of Warcraft: Forever, Forever map comparison.
- Quest category sizes vs ATT quest counts:

| Zone | Wiki `Category:<zone> quests` members | ATT `q(` entries |
| --- | --- | --- |
| Riverglades | 11 | 179 |
| Zephras Isle | 38 | 161 |
| Shen'dralas | 0 | 39 |

- Spot check of 13 Forever quests taken from ATT (by exact title, main namespace; title searches for the missing ones also returned nothing):

| Quest (ATT ID) | Zone | Wiki page? | Useful notes? |
| --- | --- | --- | --- |
| A Blast Ye Scurvy Dogs! (95123) | Riverglades | No | - |
| A Taste of the Sea (95121) | Riverglades | Yes | No Notes section |
| Bristle Hills Bandits (94535) | Riverglades | No | - |
| Feathers for Fletching (96107) | Riverglades | No | - |
| A Brief History Lesson (93016) | Shen'dralas | No | - |
| Powering the Pylons (96018) | Shen'dralas | No | - |
| What They've Done to My Peonies (93362) | Shen'dralas | No | - |
| A Firm Response (93746) | Zephras Isle | Yes | Notes section is a stub ("...") |
| Aid For The Refugees (94896) | Zephras Isle | No | - |
| Crab Season (93317) | Zephras Isle | No | - |
| Infestation Investigation (92462) | Zephras Isle | Yes | One-line where note ("flood the grove to the southeast of town") |
| Restocking the Larders (92553) | Zephras Isle | No | - |
| Camping 101: First Aid (97965) | Zephras Isle | Yes | Notes list quest givers and coords, no trick |

- Result: 4/13 pages exist, 2/13 have any note, 0/13 contain a real "trick" hint.
- Category data puts page coverage at about 6% (Riverglades), 24% (Zephras) and 0% (Shen'dralas).
- Two extra pages from the Riverglades category ("Fetch 'n' Fletch", "Jom-Jom's Escape") have no Notes either.
- Conclusion [Inferred]: the wiki is a viable hint source for **original classic** quests, which are long-documented and inherited from Wowpedia. For **new Forever quests** it is currently thin. The confusion detector and manual hints will have to carry those.
- Quest pages use plain titles, with "(quest)" or "(Forever)" disambiguators. There is no `Quest:` namespace, so the pipeline should resolve pages by quest ID (the `{{Questbox}}`/infobox ID) rather than by title.

## 4. Guidelime and LevelForge

- **Guidelime addon: All Rights Reserved** [Read].
  - The repo has no LICENSE file; the GitHub license API returns null.
  - `Guidelime/Guidelime-Vanilla.toc` contains `## X-License: All Rights Reserved`.
  - CurseForge sidebar: "All Rights Reserved".
  - `Icons/ArrowLicense.txt` covers one 3D model: non-commercial use permitted.
  - README: "World of Warcraft **Forever** will be fully supported and guides are already being worked on."
- **Guide modules** ([GuideList wiki](https://github.com/max-ri/Guidelime/wiki/GuideList), no license mentions) [Read]:
  - Forever-tagged: TUGs (CurseForge license "All Rights Reserved") [Read] and Sage (CurseForge page returned 404; license **unverified**).
  - The spec's "some GPL-3" claim was not confirmed for any Guidelime guide checked. I did not audit the other ~25 classic-era modules individually.
- **LevelForge** [Read]: CurseForge sidebar "MIT License"; description "MIT licensed."
  - No source repository link. Guides are "written and shared by players on levelforge.dev", with no license stated for guide content.
  - Practical use: none. There is no code worth reusing, and the guide text is unlicensed.
- **Forever GuideMate** (spec "Research first"; outside this task's scope but relevant) [Read]:
  - Repo `TylerAkins/forever-guide-mate` is now **archived**. The README says: "Forever GuideMate is no longer maintained ... Guides from this addon are being ported to RestedXP soon."
  - License is still `GPL-3.0` per the GitHub API, so the existing snapshot stays usable under GPLv3. There will be no upstream updates, and future guide versions will likely be in a proprietary product.

## 5. Wowhead [Read]

- [wowhead.com/tos](https://www.wowhead.com/tos) points to "End User License Agreement and Terms of Service, maintained by ZAM Network, LLC DBA Fanbyte" at [corp.fanbyte.com/legal/terms](https://corp.fanbyte.com/legal/terms) (Last Updated May 14, 2025).
- Section 8, Prohibited Conduct: forbids attempting to "access or search the Service or download content from the Service" through means "(including spiders, robots, crawlers, data mining tools or the like)" other than ZAM's software or generally available browsers. It also prohibits attempts to "datamine".
- Section 4: "You may not modify, alter, reproduce, or distribute the Service."
- Section 15: "Except as expressly authorized by ZAM, you may not make use of the Materials", which covers "compilation, information, data".
- Section 6, User Content: commenters "retain copyright". Other users get only "a non-exclusive license to access and use that User Content" within the Service. Comments are not openly licensed.
- `robots.txt` disallows `/` for AI crawlers (ClaudeBot, GPTBot, CCBot, etc.) and Scrapy.
- **The spec's "Manual only" policy is confirmed and is the only safe use.** Read comments for understanding, then write original hints, never paraphrasing closely. Do not record Wowhead as a `source` for shipped text.
- Inherited risk: Questie's own scraper targets Wowhead (section 1), so baking in Questie data inherits that question.

## Recommendation: addon license

**License Questmark GPL-3.0-or-later** (SPDX `GPL-3.0-or-later`) [Inferred, based on the evidence above].

- It is required if any Warcraft Wiki text is adapted: BY-SA 4.0 only flows one way into GPLv3, and an MIT or "GPL-3.0-only" release would not accept it as cleanly. "-or-later" matches CC's "this version or later" spirit and keeps future options open.
- It is required if Forever GuideMate guide text is used (GPL-3.0).
- It matches the only terms under which the Questie team permits copying ("under the GPLv3 terms").
- It is compatible with ATT (MIT) and LevelForge code (MIT); keep their notices.
- Conflicts and things to avoid:
  - Guidelime and its guides (All Rights Reserved; TUGs ARR; Sage unverified): do not use.
  - LevelForge user guides (no license): do not use.
  - Wowhead content (ToS forbids automated access; comments are user-copyrighted): manual inspiration only.
  - Blizzard quest text quoted on the wiki: do not ship it as "CC BY-SA" text. The in-game API supplies it at runtime anyway.
  - Questie name and logo: never use them in Questmark's name, UI or icons.
- Practical setup:
  - root `LICENSE` (GPL-3.0 text)
  - `THIRD-PARTY-NOTICES` with the ATT MIT notice, Questie/QuestieDB credit and source commit if any data is baked, and Warcraft Wiki attribution plus a CC BY-SA 4.0 link
  - a generated `CREDITS` that lists per-quest wiki sources with revision links
  - `source` fields kept in the hint table
- Preferred data strategy [Inferred]:
  - Where data: QuestieDB as an **optional runtime dependency**, plus ATT (MIT) baked in for the Forever quest list, givers and coords.
  - Hint text: wiki and GuideMate, mostly useful for classic quests.
  - New Forever quests: manual hints driven by the confusion detector.
  - Avoid baking QuestieDB unless ATT is missing a field Questmark truly needs.
