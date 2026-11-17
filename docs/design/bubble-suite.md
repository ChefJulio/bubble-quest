# BubbleSuite: the suite, the rename, the shared code

Status: approved by the user (2026-11-17). Built so far: the rename below (BubbleQuest, with the
Questmarker stub) and BubbleMap's rename, both in this repo. Not yet: the repo split, LibBubble,
bubble-tools, the CurseForge changes.

## Goal

Ship ChefJulio's addons as one family, "BubbleSuite", where every addon installs, loads and works on
its own, and lights up extra features when its siblings are loaded too.

| Addon | Was | State |
|---|---|---|
| BubbleQuest | Questmarker (CurseForge 1806606, released up to v0.5.0) | live; renamed in this repo, unreleased |
| BubbleMap | Questmarker_Map (companion in this repo) | in progress |
| BubbleFonts | - | exists, separate repo |
| BubbleBags | - | planned |
| BubbleBuffs | - | planned |

BubbleQuest status (2026-11-17): renamed in this repo (TOC, `BubbleQuestDB`/`BubbleQuestCharDB`, `/bq`,
`BubbleQuestAPI`, every global and setting ID); the `Questmarker/` stub hands the old settings over
(Core/DB.lua takeOverQuestmarker). The party message prefix stays "Questmarker" on the wire, so old and
new versions still talk. Logo: "BQ" in the BubbleFonts style (tools/logo.py). GitHub repo renamed to
ChefJulio/bubble-quest (the old URL redirects). CurseForge project renamed to BubbleQuest, slug
`bubblequest`, same ID 1806606, new logo (2026-11-17).

BubbleMap status (2026-11-17): renamed to BubbleMap in this repo (folder, TOC, `BubbleMapDB`, `/bmap`),
standalone with `## OptionalDeps: BubbleQuest, Questmarker`; quest features gated on the API. Repo
split pending.

## Rules

1. **Standalone first.** No Bubble addon requires another (`## Dependencies`). Sibling features are
   `## OptionalDeps` plus a runtime check that the sibling's API exists. BubbleMap without BubbleQuest:
   the square minimap, terrain and column still work; the quest layers and the attached tracker don't
   appear. (This reverses the earlier "Questmarker_Map requires Questmarker" decision.)
2. **No required core addon.** Shared code (below) is embedded in each addon, not installed separately.
3. **One public API per addon**, versioned (`API = 1`), read-only data plus callbacks. Siblings never
   reach into another addon's private namespace.
4. **One look and one settings model** across the suite (the shared library provides them).

## Distribution

- **One CurseForge project per addon.** Each is found, installed and updated on its own.
- **"BubbleSuite" pack:** an empty CurseForge project whose Required Dependencies are every Bubble
  addon. Installing it pulls the whole suite; it ships no code (at most a stub TOC, if CurseForge needs
  a file).
- This replaces the earlier plan of shipping Questmarker_Map in Questmarker's zip (`move-folders` in
  `.pkgmeta`). That plan made two addons share one release and one project, which doesn't fit a suite
  where each addon is chosen separately.

## Repos

Recommended: **one repo per addon**, plus one for the shared library.

- This repo (`ChefJulio/questmarker`) becomes BubbleQuest. GitHub keeps redirects after a repo rename.
- BubbleMap moves out to its own repo (its history so far can come along with `git subtree split`).
- BubbleFonts already has its own repo.
- The shared library gets its own repo and is pulled into each addon at package time through the
  BigWigs packager's `externals` (in `.pkgmeta`), into `Libs/`.

The alternative, one monorepo for the suite, needs one release workflow per addon and makes tags
ambiguous (`v1.2.0` of what?). It's not recommended.

## Shared library: LibBubble (working name)

Embedded in each addon, LibStub-style: every addon ships a copy, and the newest version loaded wins.
It holds what every Bubble addon would otherwise copy:

- **Settings:** the settings window, the schema format and the Blizzard Settings panel registration
  (today UI/SettingsWindow.lua, UI/SettingsSchema.lua).
- **Profiles:** Global by default, opt-in per-character profiles, per-character data kept apart
  (today in Core/DB.lua).
- **Look:** fonts, colours, the tooltip border and section header styles.
- **Small utilities:** the Ctrl-held tooltip suppression (UI/Tooltips.lua), the event helper, the
  combat queue.
- Tooling is not part of the library: it lives in `bubble-tools` (Decisions, 4).

Extract it from BubbleQuest's code after the rename, not before: one move at a time.

## The rename: Questmarker to BubbleQuest

### What changes

| Today | After |
|---|---|
| folder and TOC `Questmarker` | `BubbleQuest` |
| `## Title: Questmarker` | `BubbleQuest` |
| SavedVariables `QuestmarkerDB`, `QuestmarkerCharDB` | `BubbleQuestDB`, `BubbleQuestCharDB` |
| `/qm`, `/questmarker` (SLASH_QUESTMARKER1/2) | `/bq`, `/bquest`, `/bubblequest`; `/qm`, `/questmarker` kept as aliases |
| setting IDs `QUESTMARKER_*` | `BUBBLEQUEST_*` (not saved anywhere, free to rename) |
| font objects `QuestmarkerLineFont`, ... | `BubbleQuest*` |
| `QuestmarkerMinimapTooltip`, `QuestmarkerMenu`, `QuestmarkerSettings` | `BubbleQuest*` |
| AddonCompartment functions `Questmarker_On...` | `BubbleQuest_On...` |
| `QuestmarkerAPI` (new, unreleased) | `BubbleQuestAPI` |
| addon message prefix `Questmarker` (party queries) | `BubbleQuest`; listen on both for a while |
| `## IconTexture` path, media paths `Interface\AddOns\Questmarker\...` | `...\BubbleQuest\...` |
| `## X-Curse-Project-ID: 1806606` | unchanged: same project, renamed |

### Saved settings: the migration

WoW stores an addon's saved variables in a file named after its folder
(`WTF/Account/<account>/SavedVariables/Questmarker.lua`, and per character under
`<realm>/<character>/SavedVariables/`). A renamed folder can't read the old file, even if it declares
the old variable names. [Inferred from how the client loads SavedVariables; verify in game.]

The usual fix is a **stub addon**:

- For a few releases, the BubbleQuest zip also ships a tiny `Questmarker` folder. Its TOC declares
  `QuestmarkerDB` and `QuestmarkerCharDB`, has no code but a hand-off, and `## LoadOnDemand` is not set
  (it must load to read its saved variables).
- On PLAYER_LOGIN, BubbleQuest checks whether `QuestmarkerDB` / `QuestmarkerCharDB` hold data and its
  own DBs are empty. If so, it copies them over and clears the old ones (so the stub's file empties on
  logout).
- Once every character has logged in, the stub has nothing left. Drop it after a few releases.
- Shipping the stub folder in the zip also covers the "old folder left behind" problem: an update
  overwrites `Questmarker/` with the stub instead of leaving the old full addon there to load twice.
  [Assumes the CurseForge app writes every folder in the zip; it may also delete folders an update
  stops shipping. Verify with a test update before the real one.]

### CurseForge and GitHub

- Rename the CurseForge project (title, and the slug if CurseForge allows it). The project ID stays, so
  existing installs keep updating.
- Rename the GitHub repo. Update the README, the release workflow name and the links.
- The first release after the rename says so at the top of its changelog: "Questmarker is now
  BubbleQuest; your settings carry over."

### When

As one dedicated change, before the next release and before BubbleMap goes further. The longer it
waits, the more names (the API above all) a second addon depends on.

## Decisions (2026-11-17)

1. **Names:** a web search (CurseForge, WowInterface, GitHub) found no WoW addon named BubbleQuest,
   BubbleMap, BubbleSuite, BubbleBags or BubbleBuffs. Nearest: "Bubble-Collector" and "nBubble"
   (speech bubbles), and a Pathfinder mod called BubbleBuffs (another game). Search engines don't
   index everything: confirm when creating each CurseForge project, which rejects a taken slug.
2. **Repos:** one per addon, plus one for LibBubble (as recommended above).
3. **Slash commands:** `/bq`, `/bquest`, `/bubblequest`, plus `/qm` and `/questmarker` kept as
   aliases through the stub period. If another addon also registers `/bq`, the longer ones still work.
4. **Tooling: one shared repo, `bubble-tools`.** BubbleFonts' tools began as copies of this repo's and
   have already drifted both ways (its lint.py declares Forever API namespaces missing from the
   annotations, ensure_doc_namespaces; the toolchain pins differ). Each addon repo keeps a thin
   `tools/lint.py` and `tools/package.py` that fetch `bubble-tools` at a commit pinned in
   `tools/toolchain.json` into `.tools/`, the way lint.py already fetches wow-ui-source. Then a fix
   lands once and each addon takes it by bumping the pin. Per-addon settings (shipped files, globals,
   companions) stay in each repo.
5. **BubbleFonts** (`../bubble-fonts`, CurseForge 1809013) already fits: its own repo, standalone, its
   own names (BubbleFontsDB, `BubbleFonts_On...`). It uses LibSharedMedia; whatever LibBubble offers
   for fonts should build on that rather than compete with it. Later it adopts LibBubble (settings
   look) and bubble-tools.

## Order of work

1. User reviews this doc. Decisions recorded above.
2. BubbleMap work pauses on anything named Questmarker (told to questmark-01, 2026-11-17).
3. The rename, with the stub migration, in this repo. Test an update over a real Questmarker install.
4. BubbleMap: own repo, BubbleMap names, OptionalDeps on BubbleQuest, checks the API exists.
5. Extract LibBubble from BubbleQuest; adopt it in BubbleMap, then BubbleFonts.
6. CurseForge: rename BubbleQuest's project, create BubbleMap's and the BubbleSuite pack.
