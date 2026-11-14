# Phase 1 design: skeleton

Spec: "Skeleton: .toc, SavedVariables, settings panel, hide Blizzard tracker, read the quest log."
Phase 1 shows no cards. Its job is the foundation every later phase builds on, plus debug commands
to see that foundation working in game (Forever disables `/dump`, so these are our only window).

Evidence tags: [Read] verified in the Forever UI source or installed addons; [Assumes] must be
confirmed in game (each one has a debug command or test step below).

## Files

Load order in `Questmark.toc`. Each file starts with `local ADDON_NAME, ns = ...` and adds one
module to `ns`; nothing but SavedVariables and slash globals touches `_G`.

| File | Module | Job |
| --- | --- | --- |
| `Core/Bus.lua` | `ns.Bus`, `ns.Events` | Internal callbacks (`ns.Bus:On(name, fn)`, `:Fire(name, ...)`) and one game-event frame (`ns.Events:On(event, fn)`) |
| `Core/Combat.lua` | `ns.Combat` | `ns.Combat:Run(key, fn)`: run now, or queue until combat ends (latest call per key wins) |
| `Core/DB.lua` | `ns.DB` | SavedVariables: defaults, schema version, migrations, active profile |
| `Core/Debug.lua` | `ns.Debug` | `ns.Debug:Print(...)`, event logging toggle |
| `Quests/QuestLog.lua` | `ns.QuestLog` | The quest-log model (below) |
| `Blizzard/Tracker.lua` | `ns.BlizzardTracker` | Hide / release Blizzard's objective tracker |
| `Compat/Questie.lua` | `ns.Compat.Questie` | Detect Questie's tracker, tell the player once |
| `UI/Settings.lua` | `ns.Settings` | Settings panel in the game's AddOns options |
| `Slash.lua` | | `/qm` command router |
| `Init.lua` | | Wires it together on `ADDON_LOADED` / `PLAYER_LOGIN` |

The current `Questmark.lua` becomes `Init.lua` + `Slash.lua`.

**Why an internal bus.** Later phases (cards, tracking rules, arrows) react to quest-log changes.
They subscribe to `ns.Bus` events ("QuestAdded", ...) instead of game events, so the quest log is
read in exactly one place and every consumer sees the same model. This is also what makes the
spec's tracking rule 4 ("re-sort only on events") enforceable: the bus is the list of events.

## SavedVariables

```
## SavedVariables: QuestmarkDB                  -- account-wide
## SavedVariablesPerCharacter: QuestmarkCharDB  -- this character
```

```lua
QuestmarkDB = {
  schema = 1,
  profiles = {
    Default = {
      blizzardTracker = { hide = true },
    },
  },
}

QuestmarkCharDB = {
  schema = 1,
  profile = "Default",   -- which account-wide profile this character uses
  pins = {},             -- [questID] = true         (phase 3)
  ignored = {},          -- [questID] = true         (phase 3)
  collapsed = {},        -- [questID] = true         (phase 2)
  notices = {},          -- [noticeKey] = true       one-time messages already shown
}
```

- Settings live in profiles so they are shared across characters (spec, General). Phase 1 ships
  only "Default"; profile create/copy/switch UI comes when there is more than one setting worth
  sharing.
- Defaults are deep-filled into the saved tables on load (missing keys only), so a new setting
  added in a later version appears for existing users without wiping theirs.
- `schema` + an ordered list of migration functions: when a later version changes the shape,
  one migration rewrites old data, once.
- Both globals go into `.luarc.json` `diagnostics.globals`.

## Quest-log model

`ns.QuestLog.quests[questID]`, keyed by quest ID, never by log index (indices shift when headers
collapse or quests are added) [Read: research A1].

```lua
{
  questID = 783, title = "A Threat Within", level = 1, difficultyLevel = 1,
  group = "Elwynn Forest",        -- the quest-log header it sits under (zone or category)
  frequency = 0, classification = 7, tagID = nil, tagName = nil, suggestedGroup = 0,
  isComplete = false, readyForTurnIn = false, isFailed = false, isAutoComplete = false,
  objectives = {
    { key = "monster:Kobold Vermin", text = "Kobold Vermin slain: 3/8", type = "monster",
      finished = false, fulfilled = 3, required = 8 },
  },
}
```

All fields come from `C_QuestLog.GetInfo`, `GetQuestObjectives`, `IsComplete`, `ReadyForTurnIn`,
`IsFailed` and `GetQuestTagInfo`; none carries a restriction flag on Forever [Read: research A1].

### Refresh

1. Every `QUEST_LOG_UPDATE` (the client sends at most one per frame) rebuilds a fresh snapshot
   and diffs it against the model. (As built: no dirty flag. The diff already says what changed,
   and a full read of at most 40 quests is cheap. Of the payload events, only `QUEST_TURNED_IN`
   is used, for turn-in vs abandon; the others are registered so `/qm events` shows them.)
2. The diff: Per quest, a short signature string (state flags + each
   objective's fulfilled/finished) makes "did anything change" one string compare.
3. The diff fires bus events: `QuestAdded(quest)`, `QuestChanged(quest, old)`,
   `QuestRemoved(questID, how)`, then `QuestLogRefreshed()`.

Cost: at most 40 quests [Read: log cap] times a few objectives per refresh. Negligible; no
throttling needed.

### Collapsed headers

Blizzard's own quest-log search expands collapsed headers before iterating, then restores them
[Read: Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:160-190], so quests under a collapsed
header are not returned by the index loop. Handling, cheapest first:

1. Iterate the visible entries.
2. Quests already in the model stay if `C_QuestLog.GetLogIndexForQuestID(questID)` still finds
   them (that lookup is by ID, so collapse doesn't hide them) [Assumes].
3. Only if the count found is still below `GetNumQuestLogEntries()`'s `numQuests`: do what
   Blizzard's search does: expand collapsed headers (`ExpandQuestHeader`), read, collapse them
   back, with a guard so our own expand/collapse events don't trigger another refresh. Out of
   combat only, via `ns.Combat`. This normally happens once, at login, and only for players who
   collapse headers.

### Turn-in vs abandon

The game has no abandon event. `QUEST_REMOVED(questID)` fires for both; `QUEST_TURNED_IN` fires
only for turn-ins [Read: event list]. Resolution is order-independent: on `QUEST_REMOVED`, wait
one frame (`C_Timer.After(0, ...)`), then `how = "turnin"` if a `QUEST_TURNED_IN` arrived for that
quest or `C_QuestLog.IsQuestFlaggedCompleted(questID)` is true, else `"abandon"`. Phase 1 only
reports it; phase 8 (confusion detector) counts abandons.

### Objective keys

The spec requires rows keyed by objective, not position, because Forever quests can gain
objectives mid-quest and accept them in any order. Key = `type .. ":" .. text with the progress
counter stripped` ("Kobold Vermin slain: 3/8" becomes "monster:Kobold Vermin slain"), with "#2",
"#3" suffixes for exact duplicates. [Assumes] the counter format; `/qm quest <id>` prints raw
objective text so we can confirm it and refine the rule before phase 2 depends on it.

Optional objectives: the API has no "optional" field [Read: QuestObjectiveInfo]. Phase 1 records
raw text and type only; the marker is decided in phase 2 once we've seen real optional objectives
in the debug output.

## Hiding Blizzard's tracker

Questie's proven Forever pattern [Read: research A5]:

- At `PLAYER_ENTERING_WORLD`: `ObjectiveTrackerFrame:Hide()`, and install
  `ObjectiveTrackerFrame:HookScript("OnShow", ...)` once; the hook hides it again while our
  "hide" setting is on.
- Both go through `ns.Combat:Run` when `ObjectiveTrackerFrame:IsProtected()` is true in combat.
- Never call Blizzard's tracker `Update()` or any of its layout methods.
- Setting "Hide Blizzard quest tracker" (default on). Turning it off calls `Show()` and leaves the
  hook inert. No reload needed.
- Known side effect, accepted for phase 1: quest auto-complete popups and the scenario UI live in
  that frame and disappear with it. The settings tooltip says so; Questmark takes these over in a
  later phase.

## Questie

- If `Questie` is loaded and `Questie.db.profile.trackerEnabled` is true [Read: Questie
  NativeOptionsTracker.lua:101], print once per character: "Questie's tracker is also on. Turn it
  off in Questie's options: Tracker > Enable Tracker." Recorded in `QuestmarkCharDB.notices`.
- Questmark never writes Questie's settings. Both addons hiding Blizzard's tracker is harmless.
- Read guarded (`Questie and Questie.db and Questie.db.profile`), after `PLAYER_LOGIN`, so a
  Questie update that renames things degrades to "no notice", never an error.

## Settings panel

`Settings.RegisterVerticalLayoutCategory("Questmark")` + `Settings.RegisterAddOnCategory`
[Read: research A6]. Settings use `Settings.RegisterProxySetting` with getter/setter on the
*active profile*, so switching profiles later needs no re-registration. Phase 1 contents:

- Checkbox: Hide Blizzard quest tracker.

`/qm` opens it (`Settings.OpenToCategory`). The .toc gets `## Category: Quests` so the addon list
files it with Questie.

## Slash commands

| Command | Does |
| --- | --- |
| `/qm` | Open settings |
| `/qm quests` | One line per quest in the model: ID, title, group, state, objective counts |
| `/qm quest <id>` | Everything about one quest, including raw objective `type` and `text` |
| `/qm events` | Toggle printing quest events and bus events as they fire |
| `/qm tracker` | Hidden/shown state, protected or not, hook installed |

## Not in phase 1

Cards and any visible UI besides settings (phase 2), pins/ignore/re-sort rules (phase 3),
categories and LibForeverData (phase 4), positions and arrows (phase 5).

## In-game test (after build)

1. `/reload`: no BugSack errors; Blizzard's tracker is gone; `/qm tracker` reports hidden.
2. `/qm quests` lists every quest in your log; the count matches the game's quest log.
3. Collapse a header in the quest log, `/reload`, `/qm quests`: still every quest.
4. `/qm events` on, kill a quest mob: `QuestChanged` with the new count.
5. Accept a quest: `QuestAdded`. Abandon one: `QuestRemoved ... abandon`. Turn one in:
   `QuestRemoved ... turnin`.
6. `/qm quest <id>` on a few quests, including a Forever-new one if you have it: paste me the
   output (confirms the objective text format for keys).
7. Settings: untick "Hide Blizzard quest tracker": it comes back without a reload; tick it: gone.
8. With Questie's tracker on: the one-time notice appears once, not on the next `/reload`.
