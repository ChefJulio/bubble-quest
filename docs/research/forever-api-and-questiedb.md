# Forever API and QuestieDB research

Date: 2026-11-14. Client: WoW Forever build 1.60.1 (70938), TOC interface 16001.

Ground truth checked:
- Blizzard UI source, `forever` branch, commit `bebcb6bf` "1.60.1 (70938)".
- Installed addons, read only: Questie 12.6.5, QuestieDB 1.0.14 and TomTom v4.4.1.

Path shorthands used in citations:
- `UI/` = `.tools/wow-ui-source/Interface/AddOns/`
- `DOC/` = `UI/Blizzard_APIDocumentationGenerated/`
- `FA/` = `C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/`

Evidence tags:
- **[Read]**: I read the cited file:line.
- **[Inferred]**: deduced from patterns or naming, not confirmed by code.
- **[Assumes]**: needs in-game verification.

A note on the restriction flags. Nearly every quest and map API carries `SecretArguments = "AllowedWhenUntainted"`. That flag means a *secret value* may be passed as an argument only from untainted (Blizzard) code. An addon that passes ordinary numbers is unaffected. The repo's own linter treats this flag, and `AllowedWhenTainted`, as benign (`tools/apiguard.py:208-216`) [Read]. Any other restriction is called out explicitly below.

---

## Key findings

1. **The quest log API is complete and unrestricted on Forever.**
   - Reading the log needs only `C_QuestLog`: `GetNumQuestLogEntries`, `GetInfo`, `GetQuestObjectives`, `IsComplete`, `ReadyForTurnIn`, `GetQuestTagInfo` and `GetQuestType`.
   - Classification comes from `C_QuestInfoSystem.GetQuestClassification`.
   - None of these has `HasRestrictions`, `Secret*Returns` or `IsProtectedFunction` (DOC/QuestLogDocumentation.lua; DOC/QuestInfoSystemDocumentation.lua:11-25) [Read].
   - **Phase 1 decision:** build the quest-log model directly on `C_QuestLog`, keyed by questID. Never key by log index, because indices shift as headers collapse and quests are added.
2. **Quest log events are documented with payloads.**
   - Available: `QUEST_ACCEPTED(questId)`, `QUEST_REMOVED(questID, wasReplayQuest)`, `QUEST_TURNED_IN(questID, xpReward, moneyReward)`, `QUEST_WATCH_UPDATE(questID)`, `QUEST_LOG_CRITERIA_UPDATE(...)`, `QUEST_AUTOCOMPLETE(questId)`, `UNIT_QUEST_LOG_CHANGED(unitTarget)`, and `QUEST_LOG_UPDATE` (UniqueEvent, no payload).
   - **Phase 1 decision:** use the payload events as triggers that mark state dirty. Rebuild or diff the model on the next `QUEST_LOG_UPDATE`, which the client coalesces.
3. **Forever caps the quest log at 40 accepted quests.**
   - The constant is `MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT = 40` (DOC/QuestConstantsDocumentation.lua:156-161), and Forever's own quest log uses it (UI/Blizzard_UIPanels_Game/Camelot/QuestMapFrameUtils.lua:16-22) [Read].
   - At runtime, read the cap from `C_QuestLog.GetMaxNumQuestsCanAccept()` instead of hard-coding 40.
   - This answers the spec's "verify the cap".
4. **The API covers only part of the spec's categories.**
   - Covered: Dungeon, Raid, PvP, Group and Elite (via `QuestTagInfo.tagID`), and Repeatable/Daily/Weekly (via `QuestInfo.frequency` and `QuestClassification.Recurring`).
   - Not covered for normal quests: Profession, Pet battle, Class and Seasonal. `Enum.QuestTagType.Profession` and `PetBattle` apply only to world quests, through `worldQuestType` (UI/Blizzard_FrameXMLUtil/Mainline/QuestUtils.lua:78-81).
   - The missing categories come from QuestieDB's `zoneOrSort` (negative QuestSort IDs), `requiredClasses` and `requiredSkill`.
   - A small manual list is still needed for what slips through.
5. **Hiding Blizzard's tracker.**
   - **A plain `ObjectiveTrackerFrame:Hide()` does not stick.** The container calls `self:Show()` whenever any module has content (UI/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerContainer.lua:117-127).
   - **Reparenting is undone by Blizzard.** The managed-frame system calls `frame:SetParent(container)` (UI/Blizzard_ManagedFrameSystem/Shared/ManagedFrameSystem.lua:46-49), and Edit Mode calls `SetParent(UIParent)` (UI/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:335-343).
   - **Rolesets are not usable by addons.** `C_Roleset.ApplyRolesetFilters` is `HasRestrictions`, and Blizzard's UI-mode manager overwrites the global filter whenever a mode changes.
   - **Edit Mode has no hide setting**, and no CVar hides the tracker.
   - **Phase 1 decision:** copy Questie's shipped Forever pattern. Call `Hide()`, then add `HookScript("OnShow")` to re-hide. Defer to `PLAYER_REGEN_ENABLED` only if `ObjectiveTrackerFrame:IsProtected()` is true in combat. Never call Blizzard's `Update()` (FA/Questie/Modules/QuestieCompat.lua:365-434) [Read].
   - This needs an explicit, narrow exception to the CLAUDE.md "never hook" rule. A post-hook that only calls `Hide()` on a non-secure frame does not modify Blizzard's logic. See A5 for the hook-free alternative and its gaps.
6. **The settings panel API exists unchanged.**
   - `Settings.RegisterVerticalLayoutCategory`, `RegisterCanvasLayoutCategory`, `RegisterAddOnCategory`, `RegisterAddOnSetting`, `RegisterProxySetting`, `CreateCheckbox`/`CreateSlider`/`CreateDropdown` and `OpenToCategory` are all in `UI/Blizzard_Settings_Shared/Blizzard_Settings.lua:134-180, 388-410` [Read]. That file loads for all game types, including camelot.
   - **Phase 1 decision:** use a vertical-layout category with `RegisterAddOnSetting` bound to the SavedVariables table. Move to a canvas layout only when the per-category Show/Separate/Hide grid needs custom UI.
7. **SavedVariables work the standard way.**
   - `## SavedVariables` and `## SavedVariablesPerCharacter` are used by Forever's own Blizzard addons and by Questie_Forever.toc.
   - Questie also uses `## LoadSavedVariablesFirst: 1`. `## Category:` and `## IconTexture:` are read by the addon list and the addon compartment.
   - `## AllowAddOnTableAccess` and `## SuppressLocalTableRef` appear only on Blizzard addons and are not for us [Inferred].
   - **Phase 1 decision:**
     - `## SavedVariables: QuestmarkDB` holds account-wide profiles and settings, which the spec wants shared across characters.
     - `## SavedVariablesPerCharacter: QuestmarkCharDB` holds pins, the ignore list, collapse state and the selected profile name.
     - Add `## Category: Quests` and `## IconTexture:` for the addon list.
8. **Position and facing APIs exist with no restriction flags.**
   - `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition` (nilable return), `C_Map.GetWorldPosFromMapPos`, `C_Map.GetMapWorldSize`, `UnitPosition` and `GetPlayerFacing` (nilable return).
   - TomTom on Forever uses HereBeDragons: `UnitPosition("player")` plus `GetPlayerFacing()`, with `C_Map.GetPlayerMapPosition` as a fallback. It hides the arrow when facing is nil.
   - **Decision for phase 5:** use the same approach, either by embedding HereBeDragons-2.0 or by calling `UnitPosition` directly. Treat a nil from any of these calls as "no position" (an instance).
9. **The native waypoint API is available for the optional beacon setting.**
   - Functions: `C_Map.SetUserWaypoint(UiMapPoint)`, `C_Map.CanSetUserWaypointOnMap` and `C_SuperTrack.SetSuperTrackedUserWaypoint(bool)`.
   - Quest-native routing comes from `C_QuestLog.GetNextWaypoint(questID)`, which may return nothing.
10. **QuestieDB is a standalone addon and is unusually memory-efficient.**
    - It has its own .toc, no SavedVariables and no dependencies.
    - Its 16.4 MB `.toc` holds the entire database as base64 + zlib + CBOR `## X-` metadata. It decodes lazily through `C_AddOns.GetAddOnMetadata` and `C_EncodingUtil`.
    - It exposes a versioned public API: `_G.LibQuestieDB` with `RequireContract(n)`, plus `_G.QuestDB`, `NpcDB`, `ObjectDB` and `ItemDB` with `Get(id, key)`.
    - It contains 5,682 quests, 15,559 NPCs, 7,258 objects and 23,858 items. Of the quests, 1,222 have IDs of 90000 or above, which are probably Forever-new [Inferred].
11. **Recommendation on the spec's database question: a hybrid.**
    - Phases 1-9 need no quest database at all.
    - For phase 10, read QuestieDB at runtime as an optional dependency, guarded by `LibQuestieDB.RequireContract(4)`.
    - Bake only Questmark's own derived data at build time: hints, classification overrides and background-objective cluster flags computed from QuestieDB spawns.
    - Re-baking all of QuestieDB would duplicate a 16 MB generated store, a correction pipeline and a release cadence that its maintainers already run. See B5.
12. **Hiding the tracker has side effects Questmark must cover itself.**
    - The quest auto-complete popups (`AutoQuestPopUpTracker`) are hidden with it.
    - Blizzard's tracker keeps auto-adding quest watches on `QUEST_ACCEPTED` when the `autoQuestWatch` CVar is set (UI/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTracker.lua:32-38) [Read]. This is harmless, but Questmark should not treat Blizzard's watch list as the user's pins.
    - Questmark must handle `QUEST_AUTOCOMPLETE` itself in a later phase.

---

## A1. Quest log read API

All functions below are in `C_QuestLog` (DOC/QuestLogDocumentation.lua, `Environment = "All"`, line 6) [Read]. "Restrictions" lists every flag present; `SAWU` is short for `SecretArguments = "AllowedWhenUntainted"`.

| Function | Signature (from docs) | Restrictions | Cite |
|---|---|---|---|
| GetNumQuestLogEntries | `() -> numShownEntries: number, numQuests: number` | none | :303-311 |
| GetInfo | `(questLogIndex: luaIndex) -> info: QuestInfo?` | SAWU | :191-204 |
| GetQuestIDForLogIndex | `(questLogIndex: luaIndex) -> questID: number?` ("Only returns a questID for actual quests, not headers") | SAWU | :395-409 |
| GetLogIndexForQuestID | `(questID: number) -> questLogIndex: luaIndex?` | SAWU | :206-220 |
| GetTitleForQuestID | `(questID: number) -> title: cstring?` | SAWU | :667-682 |
| GetQuestObjectives | `(questID: number) -> objectives: QuestObjectiveInfo[]` | MayReturnNothing, SAWU | :476-491 |
| GetNumQuestObjectives | `(questID: number) -> leaderboardCount: number` | SAWU | :312-326 |
| IsComplete | `(questID: number) -> isComplete: bool` | SAWU | :733-747 |
| ReadyForTurnIn | `(questID: number) -> readyForTurnIn: bool?` | SAWU | :1173-1187 |
| IsFailed | `(questID: number) -> isFailed: bool` | SAWU | :763-777 |
| IsOnQuest | `(questID: number) -> isOnQuest: bool` | SAWU | :824-838 |
| IsQuestFlaggedCompleted | `(questID: number) -> isCompleted: bool` | SAWU | :915-929 |
| GetAllCompletedQuestIDs | `() -> quests: number[]` | none | :115-123 |
| GetQuestTagInfo | `(questID: number) -> info: QuestTagInfo?` | SAWU | :524-538 |
| GetQuestType | `(questID: number) -> questType: number?` | SAWU | :548-562 |
| IsRepeatableQuest | `(questID: number) -> isRepeatable: bool` | SAWU | :1035-1049 |
| IsEliteQuest | `(questID: number) -> isEliteQuest: bool` | SAWU | :748-762 |
| IsQuestTask / IsWorldQuest / IsQuestTrivial | `(questID) -> bool` | SAWU | :1005-1034, :1081-1095 |
| GetQuestDifficultyLevel | `(questID: number) -> level: number` | SAWU | :379-393 |
| GetSuggestedGroupSize | `(questID: number) -> suggestedGroupSize: number` | SAWU | :619-633 |
| GetMaxNumQuestsCanAccept | `() -> maxNumQuestsCanAccept: number` | none | :241-249 |
| GetDistanceSqToQuest | `(questID) -> distanceSq: number, onContinent: bool` | MayReturnNothing, SAWU | :158-174 |
| GetQuestsOnMap | `(uiMapID) -> quests: QuestPOIMapInfo[]` | MayReturnNothing, SAWU | :578-593 |
| GetNextWaypoint | `(questID) -> mapID, x, y` | MayReturnNothing, SAWU | :250-267 |
| GetNextWaypointText | `(questID) -> waypointText: string` | MayReturnNothing, SAWU | :286-301 |
| IsPushableQuest | `(questID) -> isPushable: bool` | SAWU | :839-853 |
| CanAbandonQuest / SetAbandonQuest / AbandonQuest | `(questID) -> canAbandon` / `()` / `()` | SAWU / none / none | :45-59, :1228-1231, :10-13 |
| AddQuestWatch / RemoveQuestWatch | `(questID) -> wasWatched / wasRemoved` | SAWU | :14-28, :1188-1202 |

`C_QuestInfoSystem.GetQuestClassification(questID: number?, questInfoID: number?) -> classification: QuestClassification` has the SAWU flag (DOC/QuestInfoSystemDocumentation.lua:11-25) [Read].

`C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID) -> difficulty: RelativeContentDifficulty` drives level coloring (DOC/PlayerInfoDocumentation.lua:79-91). Forever's quest log uses it, together with a `[level+]` title prefix built from `info.difficultyLevel` and `IsEliteQuest` (UI/Blizzard_FrameXMLUtil/Camelot/QuestUtilsOverrides.lua:6-18) [Read].

### Structures

**`QuestInfo`** (DOC/QuestLogDocumentation.lua:1546-1579) [Read]:
- `title`, `questLogIndex`, `questID`, `campaignID?`
- `level`, `difficultyLevel`, `suggestedGroup`
- `frequency: QuestFrequency?`
- `isHeader`, `useMinimalHeader`, `sortAsNormalQuest`, `isCollapsed`, `startEvent`
- `isTask`, `isBounty`, `isStory`, `isScaling`, `isOnMap`, `hasLocalPOI`, `isHidden`
- `isAutoComplete`, `overridesSortOrder`, `readyForTranslation`, `isInternalOnly`, `isAbandonOnDisable`
- `headerSortKey?`
- `questClassification: QuestClassification`

**`QuestObjectiveInfo`** (:1580-1592) [Read]:
- `text`, `type: string`, `finished`
- `numFulfilled`, `numRequired`
- `objectiveType: QuestObjectiveType?`

The `QuestObjectiveType` enum has no documentation table in the Forever docs. Retail-style values of `type` are strings such as "monster", "item", "object", "event", "reputation", "log" and "progressbar" [Inferred; verify in game].

**`QuestTagInfo`** (:1593-1606) [Read]:
- `tagName`, `tagID`
- `worldQuestType?`, `quality?`, `tradeskillLineID?`
- `isElite?`, `displayExpiration?`

### Recommended phase 1 read loop

This is how Blizzard's quest map iterates the log (UI/Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:928-932) [Read]:

1. Loop `i = 1..GetNumQuestLogEntries()` and call `GetInfo(i)`.
2. Remember the last `isHeader` title as the quest's log group. On a classic-data realm this is the zone or category header [Inferred].
3. Skip entries with `isHeader`, `isHidden` or `isInternalOnly`.
4. For each remaining questID, fetch `GetQuestObjectives(questID)`, `IsComplete` and `ReadyForTurnIn`.

Caveat: collapsed headers hide their children from `GetNumQuestLogEntries`' shown count [Assumes; numShownEntries vs numQuests]. To avoid missing quests, check that the number of quests found equals `numQuests`. If it does not, expand headers or fall back to a questID-driven refresh.

---

## A2. Classification

These are the API enums on Forever, with exact values [Read].

**`Enum.QuestTag`** (`tagID`, DOC/QuestLogDocumentation.lua:1499-1520):

| Name | Value |
|---|---|
| Group | 1 |
| PvP | 41 |
| Raid | 62 |
| Dungeon | 81 |
| Legendary | 83 |
| Heroic | 85 |
| Raid10 | 88 |
| Raid25 | 89 |
| Scenario | 98 |
| Account | 102 |
| CombatAlly | 266 |
| Delve | 288 |

Forever's own constants are `QUEST_INFO_ELITE_ID = 1`, `DUNGEON_ID = 81`, `PVP_ID = 41` and `RAID_ID = 62` (DOC/QuestConstantsDocumentation.lua:144-153). Forever's tracker shows only those four tags, as text (UI/Blizzard_FrameXMLUtil/Camelot/QuestUtilsOverrides.lua:20-35; UI/Blizzard_ObjectiveTracker/Camelot/Blizzard_QuestObjectiveTrackerOverride.lua:5-7).

**`Enum.QuestTagType`** (`worldQuestType`, DOC/QuestConstantsDocumentation.lua:86-115):

| Value | Name | Value | Name |
|---|---|---|---|
| 0 | Tag | 10 | RatedReward |
| 1 | Profession | 11 | InvasionWrapper |
| 2 | Normal | 12 | FactionAssault |
| 3 | PvP | 13 | Islands |
| 4 | PetBattle | 14 | Threat |
| 5 | Bounty | 15 | CovenantCalling |
| 6 | Dungeon | 16 | DragonRiderRacing |
| 7 | Invasion | 17 | Capstone |
| 8 | Raid | 18 | WorldBoss |
| 9 | Contribution | 19 | Prey |

Blizzard reads Profession and PetBattle only from `info.worldQuestType` (UI/Blizzard_FrameXMLUtil/Mainline/QuestUtils.lua:78-81; UI/Blizzard_FrameXML/Mainline/AlertFrameSystems.lua:1083-1086). **They do not apply to normal quests.**

**`Enum.QuestClassification`** (DOC/QuestInfoSharedDocumentation.lua:5-25):

| Name | Value | Name | Value |
|---|---|---|---|
| Important | 0 | Questline | 6 |
| Legendary | 1 | Normal | 7 |
| Campaign | 2 | BonusObjective | 8 |
| Calling | 3 | Threat | 9 |
| Meta | 4 | WorldQuest | 10 |
| Recurring | 5 | | |

Blizzard treats `Recurring` as "repeatable" (QuestUtils.lua:220).

**`Enum.QuestFrequency`** (`QuestInfo.frequency`, DOC/QuestLogDocumentation.lua:1485-1498): Default 0, Daily 1, Weekly 2, ResetByScheduler 3. Blizzard's repeatable test is `frequency == Daily or Weekly or ResetByScheduler` (QuestUtils.lua:133).

**`Enum.QuestRepeatability`** (DOC/QuestConstantsDocumentation.lua:58-72): None 0, Daily 1, Weekly 2, Turnin 3, World 4. No quest-log function returns it [Read: no function in QuestLogDocumentation.lua returns this type].

### Mapping the spec's categories

| Spec category | API source | Fallback |
|---|---|---|
| Dungeon | `tagID == 81` (also 62 Raid) [Read] | QuestieDB `zoneOrSort` = dungeon AreaID; dungeons list `FA/QuestieDB/support/Forever/Zones/dungeons.lua` |
| Repeatable | `frequency ~= Default`, `classification == Recurring`, `IsRepeatableQuest` [Read] | QuestieDB `questFlags` DAILY 4096 / WEEKLY 32768, `specialFlags` REPEATABLE 1 (FA/QuestieDB/src/corrections/enum/quests.lua:6-27) |
| Profession | none for normal quests | QuestieDB `zoneOrSort` profession sorts (e.g. HERBALISM -24, ALCHEMY -181, FISHING -101, COOKING -304, FIRST_AID -324; quests.lua:52-65), `requiredSkill` |
| Class | none | QuestieDB `zoneOrSort` class sorts (WARRIOR -81, WARLOCK -61, ...; quests.lua:39-50), `requiredClasses` bitmask |
| Seasonal/Event | none | QuestieDB `zoneOrSort` holiday sorts (SEASONAL -22, HALLOWS_END -21, LUNAR_FESTIVAL -366, ...; quests.lua:67-80) |
| Pet battle | none (`QuestTagType.PetBattle` is world-quest-only) | QuestieDB `PET_BATTLE = -394` (quests.lua:98); probably empty on Forever [Inferred] |
| Forever-specific | none | QuestieDB `NIGHT_ELF -676`, `CAMPING -666`, `THE_HIGH_ORDER -660` (quests.lua:107-110) |

Without QuestieDB, the quest-log header the quest sits under (the `isHeader` title, which for classic-style data is the zone or QuestSort name, such as "Herbalism", "Seasonal" or "Warrior") is a usable phase-4 heuristic. It is not tied to a language-independent ID, though, so it needs a localized lookup [Inferred; verify in game].

**A manual list will still be needed for:**
- quests with a normal zone sort that are really profession or class content, for example class quests filed under a zone;
- Forever-new 9xxxx quests whose `zoneOrSort` QuestieDB has not yet categorized;
- Forever's new sorts (`CAMPING`, `NIGHT_ELF`, `THE_HIGH_ORDER`), which need a decision about which spec category they belong to.

---

## A3. Quest events

All of these are documented on Forever [Read].

| Event | Payload | Flags | Use | Cite |
|---|---|---|---|---|
| QUEST_ACCEPTED | `questId: number` | Synchronous | accepted | DOC/QuestLogDocumentation.lua:1309-1318 |
| QUEST_REMOVED | `questID: number, wasReplayQuest: bool` | Synchronous | abandoned or turned in (removed from log) | :1382-1392 |
| QUEST_TURNED_IN | `questID: number, xpReward: number, moneyReward: number` | Synchronous | completed; distinguishes turn-in from abandon | :1393-1404 |
| QUEST_LOG_UPDATE | none | UniqueEvent | generic refresh (coalesced) | :1370-1375 |
| QUEST_WATCH_UPDATE | `questID: number` | Synchronous | objective progress on a quest | :1417-1426 |
| QUEST_LOG_CRITERIA_UPDATE | `questID, specificTreeID, description: cstring, numFulfilled, numRequired` | Synchronous | criteria progress | :1356-1369 |
| QUEST_AUTOCOMPLETE | `questId: number` | Synchronous | auto-complete popup (tracker-owned) | :1319-1328 |
| QUEST_WATCH_LIST_CHANGED | `questID: number?, added: bool?` | Synchronous, UniqueEvent | Blizzard watch list changed | :1405-1416 |
| QUEST_POI_UPDATE | none | UniqueEvent | POI data refreshed | :1376-1381 |
| QUEST_DATA_LOAD_RESULT | `questID: number, success: bool` | Synchronous | after `RequestLoadQuestByID` | :1335-1345 |
| UNIT_QUEST_LOG_CHANGED | `unitTarget: UnitTokenVariant` | Synchronous | log changed for player/party | DOC/UnitDocumentation.lua:4563-4571 |
| QUEST_COMPLETE / QUEST_PROGRESS / QUEST_DETAIL / QUEST_GREETING / QUEST_FINISHED | (QUEST_DETAIL: `questStartItemID?`) | Synchronous | NPC dialog (later: auto-accept/turn-in) | QuestLogDocumentation.lua:1329-1355; QuestOfferDocumentation.lua:77-99 |
| ZONE_CHANGED / ZONE_CHANGED_INDOORS / ZONE_CHANGED_NEW_AREA | none | Synchronous | zone re-sort | DOC/MapDocumentation.lua:651-667 |
| PLAYER_MAP_CHANGED | `oldMapID, newMapID` | Synchronous | map change | DOC/MapDocumentation.lua:624-633 |
| PLAYER_REGEN_DISABLED / ENABLED | none | Synchronous | combat queue | DOC/UnitDocumentation.lua:3885-3895 |

None of these events has `SecretPayloads` or any other restriction flag. In the whole doc set, only 7 entries carry `SecretPayloads`, and none is a quest event [Read: key count over DOC/].

Blizzard's own quest tracker listens to `QUEST_LOG_UPDATE`, `QUEST_WATCH_LIST_CHANGED`, `QUEST_AUTOCOMPLETE`, `SUPER_TRACKING_CHANGED`, `QUEST_TURNED_IN`, `QUEST_POI_UPDATE` and `SUPER_TRACKING_PATH_UPDATED` (UI/Blizzard_ObjectiveTracker/Blizzard_QuestObjectiveTracker.lua:3) [Read]. In other words, it treats `QUEST_LOG_UPDATE` as the main refresh signal.

**Recommended model:**
1. `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN` and `QUEST_WATCH_UPDATE` record *what* changed (for re-sort rule 4 and for in-game learning).
2. One refresh on the next `QUEST_LOG_UPDATE` reconciles the model.
3. A remove counts as an abandon when `QUEST_REMOVED` arrives without a matching `QUEST_TURNED_IN`. The order of the two events needs verifying in game [Assumes].
4. Turn-in-ready is a state, not an event: check `ReadyForTurnIn(questID)` or `IsComplete` during the refresh.

---

## A4. Positions, maps and waypoints

| API | Signature | Restrictions | Cite |
|---|---|---|---|
| C_Map.GetBestMapForUnit | `(unitToken) -> uiMapID: number?` ("Only works for the player and party members.") | SAWU | DOC/MapDocumentation.lua:48-63 |
| C_Map.GetPlayerMapPosition | `(uiMapID: number, unitToken) -> position: vector2?` (Vector2DMixin) | SAWU; nilable | :436-452 |
| C_Map.GetWorldPosFromMapPos | `(uiMapID, mapPosition: vector2) -> continentID: number, worldPosition: vector2` | MayReturnNothing, SAWU | :505-522 |
| C_Map.GetMapPosFromWorldPos | `(continentID, worldPosition: vector2, overrideUiMapID?) -> uiMapID, mapPosition` | MayReturnNothing, SAWU | :380-398 |
| C_Map.GetMapWorldSize | `(uiMapID) -> width, height` ("size in yards") | SAWU | :419-435 |
| C_Map.GetMapInfo / GetMapChildrenInfo / GetMapRectOnMap | see docs | MayReturnNothing, SAWU | :311-326, :197-214, :399-418 |
| UnitPosition | `(unit) -> positionX, positionY, positionZ, mapID` | SAWU | DOC/UnitDocumentation.lua:2713-2730 |
| GetPlayerFacing | `() -> result: number?` | none | DOC/PlayerScriptDocumentation.lua:827-835 |
| C_Map.SetUserWaypoint | `(point: UiMapPoint) -> wasSet: bool` | SAWU | DOC/MapDocumentation.lua:598-612 |
| C_Map.CanSetUserWaypointOnMap / ClearUserWaypoint / GetUserWaypoint / HasUserWaypoint | | SAWU / none | :10-31, :453-462, :523-531 |
| C_Map.OpenWorldMap | `(uiMapID?)` | **HasRestrictions** | :577-587 |
| C_SuperTrack.SetSuperTrackedUserWaypoint | `(superTracked: bool)` | SAWU | DOC/SuperTrackManagerDocumentation.lua:168-177 |
| C_SuperTrack.SetSuperTrackedQuestID / GetSuperTrackedQuestID | `(questID)` / `() -> questID?` | SAWU / none | :158-167, :64-72 |
| C_QuestLog.GetNextWaypoint / GetNextWaypointForMap / GetQuestsOnMap | see A1 | MayReturnNothing, SAWU | QuestLogDocumentation.lua:250-301, :578-593 |

**Behavior in instances.** The docs do not mark `UnitPosition` or `GetPlayerFacing` as MayReturnNothing, but both have nilable returns (`GetPlayerFacing` is `Nilable = true`; `GetPlayerMapPosition` is `Nilable = true`). In instances they return nil [Inferred from the nilable returns and from TomTom's handling below; verify in game]. Treat nil as "no position" and switch to the descriptive Where line.

**How TomTom does it on Forever** (TomTom's .toc lists interface 16001: FA/TomTom/TomTom.toc:1) [Read]:
- **Position.** The bundled HereBeDragons-2.0 calls `UnitPosition("player")` and applies continent transforms (FA/TomTom/libs/HereBeDragons/HereBeDragons-2.0.lua:661-669). Map data is built from `C_Map.GetWorldPosFromMapPos`, `GetMapWorldSize` and `GetMapRectOnMap` (:171-200).
- **Zone coordinates.** `HereBeDragons:GetPlayerZonePosition` (:681-693). `TomTom:GetCurrentPlayerPosition` cross-checks with `C_Map.GetBestMapForUnit("player")` and falls back to `C_Map.GetPlayerMapPosition` (FA/TomTom/core/position.lua:30-48).
- **Distance.** Computed in world coordinates: `hbd:GetPlayerWorldPosition()` (FA/TomTom/core/distance.lua:96, 133).
- **Facing.** The arrow computes `angle - GetPlayerFacing()` and hides itself when facing is nil (FA/TomTom/modules/crazy_arrow/crazy_arrow.lua:395-405).
- **Super-track and user waypoints.** `C_SuperTrack.GetSuperTrackedQuestID`, `IsSuperTrackingUserWaypoint` and `C_Map.GetUserWaypoint` (FA/TomTom/modules/poi.lua:24-30, 205-235).
- **Gamepad caveat.** TomTom warns that in Forever's gamepad UI mode, Blizzard's secure gamepad code scans every world map pin and every button in WorldMapFrame, so addon frames there taint it. It detects the mode with `C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad` (FA/TomTom/core/position.lua:14-27) [Read]. This matters for phase 10's world-map pins.

---

## A5. Blizzard objective tracker on Forever

### How it is built [Read]

- **The frame.** `ObjectiveTrackerFrame` is defined in UI/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTracker.xml:3. It inherits `RightManagedFrameTemplate, EditModeObjectiveTrackerSystemTemplate, ObjectiveTrackerContainerTemplate`, with `frameStrata="LOW"` and `roleset="objectives"`.
- **Modules.** `ObjectiveTrackerManager:Init` runs after `PLAYER_ENTERING_WORLD` and `VARIABLES_LOADED`. It adds these modules to the frame: Scenario, UIWidget, CampaignQuest, Quest, Adventure, Achievement, MonthlyActivities, InitiativeTasks, ProfessionsRecipe, Bonus and WorldQuest (Blizzard_ObjectiveTrackerManager.lua:190-216, 230).
- **Forever override.** Forever adds `Camelot/Blizzard_QuestObjectiveTrackerOverride.lua`, loaded with `[AllowLoadGameType camelot]` (Blizzard_ObjectiveTracker.toc). It disables timer bars and uses text-only tags (override file :1-7).
- **The frame's own events.** It listens for `ZONE_CHANGED*` to call `C_QuestLog.SortQuestWatches()`, and on `QUEST_ACCEPTED` it auto-adds watches when the `autoQuestWatch` CVar is set (Blizzard_ObjectiveTracker.lua:13-40).
- **Header.** The header hides when `C_GameRules.IsGameRuleActive(Enum.GameRule.ObjectiveTrackerDisabled)` is true (:42-45). That game rule is server-defined, not something an addon can set.
- **No secure templates.** There are no secure templates under `Blizzard_ObjectiveTracker/`: searching for "Secure" or "protected" finds nothing, and `QuestObjectiveItemButtonTemplate` is a plain Button (Blizzard_ObjectiveTrackerShared.xml:4). So the frame is normally not protected [Inferred]. Questie still checks `IsProtected()` at runtime (below), which is the safe choice.

### What rolesets are [Read]

Rolesets are tags that the **UI mode system** uses to hide groups of frames as a set.
- **Setting tags.** `Frame:SetRolesets(str)`, `AddRoleset` and `RemoveRoleset` are `IsProtectedFunction = true` (DOC/SimpleFrameAPIDocumentation.lua:17-28, 1101-1110, 1460-1470). `SetRolesets` is documented as "used by the UI mode system to gate visibility".
- **Applying filters.** `C_Roleset.ApplyRolesetFilters(blocked, allowed)` is `HasRestrictions = true`, documented as "Blocked for tainted callers while in combat lockdown" (DOC/RolesetSystemDocumentation.lua:10-22).
- **Who uses it.** Blizzard's `UIModeUtil` (UI/Blizzard_UIModes/Blizzard_UIModeUtil.lua:6-42) keeps a "hide most" blocklist that includes `objectives`. Modes such as pet battle, commentator and client scenes push it.
- **Why addons can't use it.** `UIModeManagerMixin:ResolveVisibility` rewrites the whole filter on every push or pop, and clears it when the stack is empty (Blizzard_UIModeManager.lua:47-50, 103). An addon-applied filter would be wiped the next time a mode changes. Calling `UIModeUtil.RegisterMode` / `SetModeActive` from addon code would put tainted entries into Blizzard's mode stack, and the call is blocked for tainted callers in combat anyway.

### Why the simple approaches fail [Read]

| Approach | Problem |
|---|---|
| `ObjectiveTrackerFrame:Hide()` once | `ObjectiveTrackerContainerMixin:Update` calls `self:Show()` whenever a module has content (Blizzard_ObjectiveTrackerContainer.lua:117-127). It is re-shown on the next quest update. |
| `SetParent(hiddenFrame)` | `ManagedFrameContainerMixin:UpdateFrame` calls `frame:SetParent(container)` whenever a shown managed frame is (re-)added (ManagedFrameSystem.lua:46-49, 57-77), including on `UI.TopLevelParentShown` (:160). `EditModeSystemMixin:BreakFromFrameManager` calls `SetParent(UIParent)` (EditModeSystemTemplates.lua:335-343). Reparenting does not survive layout passes, and `SetParent` is itself `IsProtectedFunction` (DOC/SimpleScriptRegionAPIDocumentation.lua:653-657). |
| `SetAlpha(0)` | `ManagedFrameContainerMixin:AnimInManagedFrames` resets the alpha of managed frames to 1 (ManagedFrameSystem.lua:130-134). |
| Edit Mode setting | The tracker's only settings are Height, Opacity and TextSize (DOC/EditModeManagerConstantsDocumentation.lua:587-596). There is no hide option. |
| CVar | No CVar hides the tracker. The tracker reads only `autoQuestWatch` and `questPOI` (Blizzard_ObjectiveTracker.lua:35; Blizzard_ObjectiveTrackerManager.lua:151-168). |
| Roleset filter | See above: it is restricted and Blizzard overwrites it. |
| Untracking every quest | The container hides itself when it is empty (Container.lua:121-126). But this changes the player's watch list, and other modules (scenario, bonus, achievements, recipes) would still show. |

Blizzard itself never calls `ObjectiveTrackerFrame:Hide/Show/SetShown` outside the tracker addon. Searching `UI/` for those calls on `ObjectiveTrackerFrame` returns only the game-rule check [Read].

### How Questie does it on Forever [Read]

Source: `FA/Questie/Modules/QuestieCompat.lua:365-434`.
- `HideWatchFrame()` sets a flag and calls `ObjectiveTrackerFrame:HookScript("OnShow", ...)` once. The hook re-runs `ApplyObjectiveTrackerVisibility()`, which calls `ObjectiveTrackerFrame:Hide()`.
- Inside `ApplyObjectiveTrackerVisibility`:
  - In combat, if the frame is protected, it waits for `PLAYER_REGEN_ENABLED` and applies the latest request then (:372-377).
  - When restoring, it calls `Show()` and deliberately avoids `Update()`. The comment at :383 says: "Forever: calling Update() here would run Blizzard's layout (and its secret aura reads) and taint it."
- The comment at :397 says it deliberately does not reparent: "keep later native OnShow calls suppressed, without reparenting protected frames".
- Questie runs this from `OnEnable` when its tracker is enabled, and re-applies it on `UPDATE_ALL_UI_WIDGETS` and on quest auto-complete (Questie.lua:47-61; EventHandler.lua:352-355; QuestEventHandler.lua:527-528, as reported by the sub-research).

### Recommendation for phase 1

1. **Use Questie's pattern; it is proven on this client.**
   - At `PLAYER_ENTERING_WORLD`, call `ObjectiveTrackerFrame:Hide()` and install `HookScript("OnShow", reHide)` once.
   - Do it only out of combat when `ObjectiveTrackerFrame:IsProtected()`. Otherwise queue it until `PLAYER_REGEN_ENABLED`.
   - Never call `ObjectiveTrackerFrame:Update()` or any other Blizzard layout method.
   - Provide an "Show Blizzard tracker" setting that releases the hide by clearing the flag and calling `Show()`.
2. **This is a hook.** CLAUDE.md says "Hide Blizzard UI, never modify or hook it". `HookScript` is a post-hook: Blizzard's own OnShow runs first, unchanged, and the hook only calls `Hide()`. It is the narrowest hook possible, but it still needs the user's explicit sign-off as an exception, plus an `apiguard` acknowledgment if the linter flags it.
3. **A hook-free alternative exists but has gaps.** Questmark's own event frame could call `ObjectiveTrackerFrame:Hide()` after the same events that make Blizzard re-show the tracker (`QUEST_LOG_UPDATE`, `QUEST_WATCH_LIST_CHANGED`, `SUPER_TRACKING_CHANGED`, `ZONE_CHANGED_NEW_AREA`, `EditMode.Exit`, `UPDATE_ALL_UI_WIDGETS`). That avoids hooking Blizzard, but:
   - handler order versus Blizzard's module handlers is not guaranteed, so the tracker could flash;
   - any trigger missing from the list leaves the tracker visible.
4. **Side effects to cover:**
   - The tracker hosts `AutoQuestPopUpTracker`, so auto-complete and auto-accept popups disappear with it. Handle `QUEST_AUTOCOMPLETE` in Questmark (later phase).
   - `ScenarioObjectiveTracker` also lives in this frame, so scenario and dungeon-stage UI is hidden too [Inferred]. Decide whether the tracker should be released inside scenarios.
   - Questie's tracker anchors to `ObjectiveTrackerFrame:GetPoint()` (QuestieCompat.lua:438-441). If both addons run, both will hide the tracker; that is harmless.

---

## A6. Settings panel API

All of these are in UI/Blizzard_Settings_Shared/Blizzard_Settings.lua [Read]:
- `Settings.RegisterAddOnCategory(category)` (:134-138)
- `Settings.OpenToCategory(categoryID, scrollToElementName)` (:144-146)
- `Settings.RegisterVerticalLayoutCategory(name)` and `RegisterVerticalLayoutSubcategory(parentCategory, name)` (:154-160)
- `Settings.RegisterCanvasLayoutCategory(frame, name)` and `RegisterCanvasLayoutSubcategory(parentCategory, frame, name)` (:162-168)
- `Settings.RegisterAddOnSetting(categoryTbl, variable, variableKey, variableTbl, variableType, name, defaultValue)` (:174-176)
- `Settings.RegisterProxySetting(categoryTbl, variable, variableType, name, defaultValue, getValue, setValue)` (:178-180)
- `Settings.CreateCheckbox(category, setting, tooltip)` (:388), `CreateSlider(category, setting, options, tooltip)` (:404), `CreateDropdown(category, setting, options, tooltip)` (:410), `CreateSliderOptions(min, max, rate)` (:309)

The toc for `Blizzard_Settings_Shared` has `## AllowLoad: Both` and no game-type exclusion for these files. Only `Camelot\NewDefinitions.lua` and the `[Game]` overrides are Forever-specific. So the API is present on Forever [Read: UI/Blizzard_Settings_Shared/Blizzard_Settings_Shared.toc].

One caution: `Settings.OpenToCategory` goes through `C_SettingsUtil.OpenSettingsPanel`. If a slash command needs to open the panel in combat, check that function's flags first (not checked here).

---

## A7. SavedVariables and .toc directives

- **Standard SavedVariables directives are used on Forever** [Read]:
  - Blizzard addons: `UI/Blizzard_AuctionHouseUI/Blizzard_AuctionHouseUI.toc:3-5`, `UI/Blizzard_TimeManager/Blizzard_TimeManager.toc:7`, `UI/Blizzard_EventTrace/Blizzard_EventTrace.toc:6`.
  - Questie: `FA/Questie/Questie_Forever.toc` has `## SavedVariables: QuestieConfig, QuestieProfilerEnabled`, `## SavedVariablesPerCharacter: QuestieConfigCharacter` and `## LoadSavedVariablesFirst: 1` (sub-research).
- **`## SavedVariablesMachine`** is Blizzard-only, found on Console, AddOnList and GlueSavedVariables [Inferred: no third-party use seen].
- **Metadata the client UI reads** [Read]:
  - `IconTexture` / `IconAtlas` (UI/Blizzard_AddOnList/AddonList.lua:390-391).
  - `Group` and `Category` (:453-456).
  - `AddonCompartmentFunc` (UI/Blizzard_Minimap/Mainline/AddonCompartment.lua:106-111). Forever loads its own `[Game]\AddonCompartment.lua` under `[AllowLoadGameType camelot]` (UI/Blizzard_Minimap/Blizzard_Minimap.toc:48-51).
- **Blizzard-only directives** seen on Forever's Blizzard addons: `## AllowAddOnTableAccess: 1` (Blizzard_CombatAudioAlerts.toc:6), `## SuppressLocalTableRef: 1` (Blizzard_RecruitAFriend.toc:5), `## UseSecureEnvironment`, `## AllowLoad`, `## AllowLoadGameType`, `## DefaultState` and `## LoadFirst`. They are not for third-party addons [Inferred].
- **How the client picks files on Forever.** Inside Blizzard tocs, files are gated with `[AllowLoadGameType camelot]` / `[ExcludeLoadGameType camelot]`. 209 lines are `camelot`-gated, and Mainline files load unless they exclude camelot [Read: counts over UI/*/*.toc]. Third-party addons instead pick a flavor by file name: QuestieDB and Questie ship `_Forever.toc` and `_Camelot.toc` (sub-research). Questmark's single `Questmark.toc` with `## Interface: 16001` is enough.
- **Recommended Questmark.toc additions for phase 1:**
  - `## SavedVariables: QuestmarkDB`
  - `## SavedVariablesPerCharacter: QuestmarkCharDB`
  - `## Category: Quests`
  - `## IconTexture: Interface\AddOns\Questmark\...`
  - optionally `## AddonCompartmentFunc`
  - Add both globals to `.luarc.json` `diagnostics.globals`, as CLAUDE.md requires.

---

## B1. QuestieDB structure

Source: sub-research, with header and globals spot-checked by me.

- **Separate addon.** `FA/QuestieDB/` contains `QuestieDB_Forever.toc` and `QuestieDB_Camelot.toc`. The two are byte-identical, 16,428,694 bytes and 126,241 lines each.
- **Toc header** (lines 1-33) [Read]: `## Interface: 16001`, `# Baked mode: entity reads resolve from the TOC metadata store below.`, `## Version: 1.0.14`, `## Category: Quests`, `## IconTexture: ...`, `## X-Contract-Version: 4`, `## X-Flavor: Forever`, `## X-Mode: baked`. There is no SavedVariables, no Dependencies and no LoadOnDemand. 52 Lua files follow.
- **Storage format** [Read, FA/QuestieDB/src/read/baked.lua]:
  - Every record is a `## X-<Type>-<id>-<field>: <base64>` toc metadata line, read with `C_AddOns.GetAddOnMetadata` (:21, 27).
  - Values longer than 1000 bytes are split into `~N~` chunks (:32-47).
  - `X-<Type>-IDS` is base64, then zlib (`C_EncodingUtil.DecompressString`), then CBOR (:67-72).
  - Each entity has a scalar row `X-<Type>-<id>-S` (base64 + CBOR), plus one key per table-valued field, gated by a presence bitmask (:80-134).
  - Localization is one compressed CBOR blob per locale and type, decoded only on non-enUS clients.
- **Quest schema** (36 fields, FA/QuestieDB/src/meta/questMeta.lua:19-92):
  - 1-9: 1 name, 2 startedBy, 3 finishedBy, 4 requiredLevel, 5 questLevel, 6 requiredRaces, 7 requiredClasses, 8 objectivesText, 9 triggerEnd
  - 10-18: 10 objectives, 11 sourceItemId, 12 preQuestGroup, 13 preQuestSingle, 14 childQuests, 15 inGroupWith, 16 exclusiveTo, 17 zoneOrSort, 18 requiredSkill
  - 19-27: 19 requiredMinRep, 20 requiredMaxRep, 21 requiredSourceItems, 22 nextQuestInChain, 23 questFlags, 24 specialFlags, 25 parentQuest, 26 reputationReward, 27 breadcrumbForQuestId
  - 28-36: 28 breadcrumbs, 29 extraObjectives, 30 requiredSpell, 31 requiredSpecialization, 32 requiredMaxLevel, 33 availableUntilCompleted, 34 availableStartingWith, 35 requiredRanks, 36 disabledByQuest
- **NPC schema** (15 fields, npcMeta.lua:19-50):
  - 1 name, 2 minLevelHealth, 3 maxLevelHealth (2 and 3 are constants and not stored), 4 minLevel, 5 maxLevel, 6 rank, 7 spawns, 8 waypoints
  - 9 zoneID, 10 questStarts, 11 questEnds, 12 factionID, 13 friendlyToFaction, 14 subName, 15 npcFlags
- **Object schema** (7 fields, objectMeta.lua:19-34): 1 name, 2 questStarts, 3 questEnds, 4 spawns, 5 zoneID, 6 factionID, 7 waypoints.
- **Item schema** (16 fields, itemMeta.lua:19-52):
  - 1 name, 2 npcDrops, 3 objectDrops, 4 itemDrops, 5 startQuest, 6 questRewards, 7 flags, 8 foodType
  - 9 itemLevel, 10 requiredLevel, 11 ammoType, 12 class, 13 subClass, 14 vendors, 15 relatedQuests, 16 teachesSpell
- **How Forever data is organized** [Read: FA/QuestieDB/src/config.lua:66, 165-189]:
  - The Forever flavor uses classic rules, interface 16001 and the alias `_Camelot`.
  - Corrections are layered: legacy classic fixes, then a generated `foreverBase*` delta, then `Forever/traces/*` (generated from player traces), then hand-written `forever*Fixes`. All static corrections are baked in at build time; only dynamic (faction/race/class) fixes run at load.
  - `src/support/eraToForever.lua:8-53` remaps coordinates for 4 zones whose maps changed on Forever (Mulgore, Eastern Plaguelands, Redridge, Stormwind).
  - The shipped data does not mark which quests are Forever-new. Only the ID ranges hint at it (see B4) [Inferred].

## B2. Size and memory

**On disk** [Read, measured]:
- QuestieDB: 34,481,079 bytes in 65 files. About 95% of that is the two identical 16.4 MB tocs, and the client reads only one.
- Questie: 8,444,269 bytes in 531 files.
- Together that is about 43 MB on disk, against the spec's "~57 MB download" figure. The download likely included other bundle parts or compression differences [Inferred].

**Memory:**
- Questie's profiler README reports about 17.7 MB allocated at load across localization groups, allocated even when the client locale doesn't match (FA/Questie/Modules/Profiler/README.md:208-211) [Read].
- QuestieDB decodes only the ID lists eagerly and caches scalar rows per entity on access (baked.lua:65-66; shared.lua:15-20) [Read].
- The metadata strings themselves live in client-side storage, so they are probably not counted in Lua memory [Inferred]. As a result, the Lua heap cost of QuestieDB alone should be small and grows with use.
- Measure in game: call `collectgarbage("count")` / `UpdateAddOnMemoryUsage()` with QuestieDB loaded and Questie disabled [Assumes].

## B3. Runtime API

- **Globals** [Read]:
  - `_G.LibQuestieDB` (FA/QuestieDB/src/api.lua:177).
  - `_G.QuestDB`, `_G.NpcDB`, `_G.ObjectDB` and `_G.ItemDB`, created as `_G[entityType.name .. "DB"]` (api.lua:30).
- **Entity methods** (shared.lua:378-581, sub-research):
  - Reads: `Get(id, key)`, `GetByIndex`, `GetAll(id, keys)`, `GetRaw`, `GetAllIds(hashmap)`, `Exists`.
  - Name lookups: `IdsByName`, `BuildNameIndex[Async]`.
  - Cache control: `InvalidateCache`.
- **Library methods** (api.lua:101-160):
  - Contract: `RequireContract(n)`, plus `contractVersion` 4 and `minSupportedContract` 1.
  - Corrections: `RegisterCorrection`, `RegisterRuntimeCorrection`, `ApplyRegisteredCorrections`, `SetCorrection`, `GetProvenance`, `GetOwners`.
  - Data: `Enum.*` (sortKeys, questFlags, ...) and `Meta.*` (the key schemas).
- **No LibStub.** QuestieDB is a plain global library.
- **How Questie uses it:**
  - Questie lists QuestieDB under `## OptionalDeps`, which only orders loading. There is no `LoadOnDemand` and no `LoadAddOn` call.
  - Questie binds `LibQuestieDB.Quest.Get` and similar at file load (FA/Questie/Database/QuestieDB.lua:209-262).
  - `VersionCheckDB.lua:21-59` aborts Questie's startup if `C_AddOns.IsAddOnLoaded("QuestieDB")` or the contract check fails.
- **Standalone use.** QuestieDB has no dependency on Questie, so another addon can depend on it alone (`## OptionalDeps: QuestieDB` or `## Dependencies: QuestieDB`).
- **Distribution is unknown.** Whether QuestieDB is distributed standalone or only in the Questie bundle was not verified [Assumes]. It decides whether Questmark users who drop Questie can keep QuestieDB.

## B4. Counts and availability fields

Counts come from decoding the `X-<Type>-IDS` headers with a scratch parser. Every ID had a matching `-S` row.

| Type | Count | ID range |
|---|---|---|
| Quests | **5,682** | 2 to 99,411 |
| NPCs | **15,559** | |
| Objects | **7,258** | |
| Items | **23,858** | |

Quest IDs by range:

| Range | Quests |
|---|---|
| below 10,000 | 4,262 |
| 60k | 8 |
| 70k | 84 |
| 80k | 106 |
| 90,000 and above | **1,222** |

The quests under 10k are most likely classic base data and the 90k+ quests are most likely Forever-new [Inferred].

**How the fields are represented** [Read]:
- `startedBy` / `finishedBy`: `{npcIds?, objectIds?, itemIds?}`. Example: quest 2 is `{[3]={16305}}`, started by an item.
- `requiredRaces` / `requiredClasses`: bitmasks.
  - Forever adds Skyborne race bits 2^32 (Alliance) and 2^33 (Horde) (FA/Questie/Database/QuestieDB.lua:158-159).
  - Questie checks races arithmetically, not with `bit.*`, because the bits exceed 32 (QuestiePlayer.lua:86-96). **Questmark must do the same.**
  - Common values: all-Alliance 4294967373 (1,838 quests), unrestricted 0 (1,765), all-Horde 8589934770 (1,577).
- `preQuestSingle` (any one completed) and `preQuestGroup` (all completed): ID lists.
- `exclusiveTo`: ID list. Quest counts per field are in the usage table below.
- `breadcrumbForQuestId` (scalar) and `breadcrumbs` (list).
- `nextQuestInChain` and `parentQuest`: scalars.
- `requiredSkill`, `requiredMinRep`, `requiredMaxRep`: `{id, value}` pairs.
- `questFlags`: cmangos bitmask (DAILY 4096, WEEKLY 32768). `specialFlags`: bit 1 means repeatable (enum/quests.lua:6-27).
- `zoneOrSort`: an AreaID if positive, a QuestSort if negative (enum/quests.lua:29-111).

How many quests use each field:

| Field | Quests | Field | Quests |
|---|---|---|---|
| startedBy | 5,217 | requiredRaces | 3,916 |
| finishedBy | 5,104 | requiredClasses | 1,034 |
| preQuestSingle | 2,506 | nextQuestInChain | 2,070 |
| preQuestGroup | 84 | questFlags | 3,037 |
| exclusiveTo | 459 | specialFlags | 928 |
| breadcrumbs | 162 | breadcrumbForQuestId | 216 |
| requiredSkill | 230 | parentQuest | 41 |
| requiredMinRep | 280 | requiredSpell | 80 |
| requiredMaxRep | 41 | requiredMaxLevel | 42 |

**How Questie decides a quest is available** (FA/Questie/Modules/Quest/AvailableQuests/AvailableQuests.lua:546-637; `QuestieDB.IsDoable` in FA/Questie/Database/QuestieDB.lua:695-960) [Read].

The available-quests pass skips quests that are blacklisted, completed, hidden or marked unavailable after talking to the NPC. Option filters then drop repeatable, PvP, dungeon, raid or AQ quests. A quest must then pass both the level check and `IsDoable`:

- **Level check:** a green-range minimum, `requiredLevel` and `requiredMaxLevel`.
- **`IsDoable`** rejects a quest when any of the following holds:
  - it is completed or hidden;
  - race or class fails (bitmask check);
  - none of its `preQuestSingle` quests is complete;
  - reputation is outside min/max, or the profession skill or rank is too low;
  - **only when `preQuestSingle` is absent:** not every `preQuestGroup` quest is done. An `exclusiveTo` sibling of a prerequisite counts as done, and a negative ID skips that substitution;
  - its `parentQuest` is not active;
  - its `nextQuestInChain` is active or completed;
  - any of its `exclusiveTo` quests is active or completed;
  - spec, spell or achievement requirements fail;
  - the quest it is a breadcrumb for is active or completed, or one of its own `breadcrumbs` is active;
  - `disabledByQuest` is active, or daily-quest hiding applies;
  - the `availableUntilCompleted` / `availableStartingWith` window fails.

This rule set is the reference implementation for the spec's "available-quest filtering". Questmark should reuse it as-is, either by calling Questie-equivalent logic over QuestieDB or by porting it, rather than inventing new rules.

## B5. Recommendation: runtime QuestieDB vs. build-time bake

| Factor | Runtime dependency on QuestieDB | Bake at build time |
|---|---|---|
| Memory | Very low and lazy. Data sits in toc metadata and decodes per entity on access (B2). | Plain Lua tables for about 5.7k quests plus about 15.5k NPCs with spawn coordinates would cost several MB of resident Lua memory [Inferred]. Matching QuestieDB's efficiency means re-implementing its baked-toc codec. |
| Update cadence | Fixes arrive automatically, including the trace-based Forever corrections (config.lua:165-189), whenever the user updates QuestieDB. | Questmark must re-run its pipeline and ship a release for every upstream data fix. Forever is new and its data churns. |
| Coupling | Depends on a versioned contract (`RequireContract`, contract 4) and on the global names. Users must install QuestieDB, and distribution is unknown (B3). A breaking upstream contract disables Questmark features until it is fixed. | No runtime coupling. The build depends on QuestieDB's generator or format instead. |
| Licensing | Both are GPL-3 (`LICENSE.md` and `gpl-3.0.md` are present). Using it at runtime as a separate addon involves no redistribution. | Redistributes derived data, which needs GPL-3 compliance and attribution. The spec already plans GPL-3. A separate agent covers licensing. |
| Extensibility | `LibQuestieDB.RegisterCorrection` / `RegisterRuntimeCorrection` let Questmark patch fields at runtime. Hints and other Questmark-only fields still need Questmark's own table. | Full control over the schema. |

**Recommendation: a hybrid, decided per phase.**

1. **Phases 1-9 need no database.**
   - Quest titles, objectives, completion and turn-in state come from `C_QuestLog`.
   - Classification comes from `tagID`, `frequency` and `QuestClassification`, plus a small manual list.
   - Optionally, read `QuestDB.Get(id, "zoneOrSort")` when QuestieDB happens to be loaded. Make it a soft enhancement guarded by `LibQuestieDB and LibQuestieDB.RequireContract(4)`, never a requirement.
2. **Phase 10 (Questie replacement):**
   - Read QuestieDB at runtime as `## OptionalDeps: QuestieDB` and degrade gracefully when it is absent: no available-quest pins and no unit tooltips.
   - Do not re-bake the whole database. Duplicating a 16 MB generated store and its correction pipeline is the expensive path, with no upside unless QuestieDB turns out not to be installable standalone.
3. **Bake only Questmark's own derived data at build time**, by reading QuestieDB's toc offline:
   - the hint table;
   - category overrides;
   - background-objective flags and dense-cluster centers computed from spawns;
   - the dungeon-quest index for the pre-dungeon reminder.
   These are small, Questmark-specific, and expensive to compute in game.
4. **Re-evaluate if any of these turns out true:**
   - QuestieDB is only distributed inside the Questie bundle;
   - its contract changes more often than about once a quarter;
   - in-game memory measurement shows the lazy decode cache grows large during normal play.

   If so, fall back to baking a pruned subset, such as quest givers, turn-ins and objective spawns for Forever quests only, using the same toc-metadata technique.
