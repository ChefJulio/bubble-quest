# BubbleSuite: the suite, the rename, the shared code

Status: proposal, awaiting the user's review (2026-11-17). Nothing here is built yet.

## Goal

Ship ChefJulio's addons as one family, "BubbleSuite", where every addon installs, loads and works on
its own, and lights up extra features when its siblings are loaded too.

| Addon | Was | State |
|---|---|---|
| BubbleQuest | Questmarker (CurseForge 1806606, released up to v0.5.0) | live, to be renamed |
| BubbleMap | Questmarker_Map (companion in this repo, steps 1-2 built, unpushed) | in progress |
| BubbleFonts | - | exists, separate repo |
| BubbleBags | - | planned |
| BubbleBuffs | - | planned |

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
- **Tooling** (not shipped): lint.py with apiguard, package.py, the toolchain pin. These could live in
  a shared tools repo, or stay copied per repo; to be decided.

Extract it from BubbleQuest's code after the rename, not before: one move at a time.

## The rename: Questmarker to BubbleQuest

### What changes

| Today | After |
|---|---|
| folder and TOC `Questmarker` | `BubbleQuest` |
| `## Title: Questmarker` | `BubbleQuest` |
| SavedVariables `QuestmarkerDB`, `QuestmarkerCharDB` | `BubbleQuestDB`, `BubbleQuestCharDB` |
| `/qm`, `/questmarker` (SLASH_QUESTMARKER1/2) | `/bq`, `/bubblequest`; `/qm` kept as an alias |
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

## Open questions for the user

1. Are the names free? Check CurseForge and Wago for existing "BubbleQuest", "BubbleMap",
   "BubbleBags", "BubbleBuffs" and "BubbleSuite".
2. Repos: one per addon (recommended), or one monorepo?
3. Slash command: `/bq`? (`/bq` may clash with another addon; to check.)
4. Shared tooling: a shared tools repo, or a copy in each repo?
5. BubbleFonts: does it adopt the shared library and the standalone rule as is, or does it need
   changes? Its own session should look at it.

## Order of work

1. User reviews this doc; name check (question 1).
2. BubbleMap work pauses on anything named Questmarker (told to questmark-01, 2026-11-17).
3. The rename, with the stub migration, in this repo. Test an update over a real Questmarker install.
4. BubbleMap: own repo, BubbleMap names, OptionalDeps on BubbleQuest, checks the API exists.
5. Extract LibBubble from BubbleQuest; adopt it in BubbleMap, then BubbleFonts.
6. CurseForge: rename BubbleQuest's project, create BubbleMap's and the BubbleSuite pack.
