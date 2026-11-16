# Questie parity checklist

Made 2026-11-16 from Questie's options panels (Forever, v12.9.0), now that Questmarker is replacing
Questie rather than running beside it. Each Questie feature: what Questmarker has, plans, or skips.

Status: **have** (built), **planned** (designed or agreed), **candidate** (worth considering, not
agreed), **skip** (not worth it, or the client already does it).

## General

| Questie | Status | Questmarker / notes |
| --- | --- | --- |
| Show party members' tracked quest objectives (Questie-to-Questie comms) | have | Party progress from the server (cards, map, minimap tooltips); works without the addon on their side |
| Announce quest updates in party chat (accepted, abandoned, objective done, completed, item starts a quest, incomplete breadcrumb), to yourself, ShutUp | planned | Off by default (review: "I hate them"; some players like them); per-type toggles |
| Instant quest text | planned | Check first whether Forever's client has its own option |
| Custom quest frame icons (gossip/quest window: available, complete, repeatable, trivial) | planned | Small |
| Map button | planned | Part 2's map menu |
| Minimap button, addon compartment | have | Compartment entry (no minimap button, by choice) |
| Map coordinates, minimap coordinates, decimal precision | planned | Small; TomTom also does it |
| Which available quests (XP-granting only, all low level, N levels below, a level range) | planned | Part 2: Questie's default plus a "Trivial quests" toggle; the other modes are a candidate |

## Tooltips

| Questie | Status | Questmarker / notes |
| --- | --- | --- |
| World tooltips: quest progress on mobs and objects | planned | The client adds quest lines to unit tooltips itself (TooltipDataLineType QuestObjective/QuestTitle/QuestPlayer): add only what's missing |
| Quests in NPC tooltips (what a quest giver offers) | planned | With part 2's data |
| Quest level in tooltips | planned | |
| Next quests in chain | planned | QuestieDB nextQuestInChain |
| Breadcrumb quests | planned | |
| Item drop rates | planned | LibForeverData has drop chances |
| "This item starts a quest" | planned | Roadmap 5 |
| Quest XP at max level | skip | |

## Sounds

| Questie | Status | Questmarker / notes |
| --- | --- | --- |
| Sounds for quest completed, objective completed, objective progress; sound choice, channel, delay | planned | Defaults must not annoy (review): quiet, quest completed only on by default |

## Map and minimap icons

| Questie | Status | Questmarker / notes |
| --- | --- | --- |
| Objectives (icons per spawn, themes) | have | Quest areas instead (world map and minimap), per-quest colours, highlights |
| Completed quests (turn-in "?") | have | Blizzard's map "?", icon size setting |
| Available normal / repeatable / from items / event / PvP / dungeon / raid / AQ quests | planned | Part 2; drops as an honest area; event/PvP/dungeon/raid filters from Quest categories |
| Hide icons of untracked quests | have | Areas are drawn for the cards' quests only |
| Townsfolk, profession trainers, vendors | planned | Part 3 |
| Enable map icons / minimap icons | have | Map settings toggles |
| Icon scales (map, minimap, townsfolk, quest, per objective type) | planned | One icon size now; split map and minimap |
| Glow, unique colours | have | Highlight glow; one colour per quest |
| Hide icons on continent map, in unexplored areas | planned | Check how areas look on continent maps first |
| Minimap fade distance, fade icons over the player | planned | Fade what's under the player's arrow |
| Patrol paths (waypoints) for wandering NPCs, line width/opacity/colours | planned | Roadmap 6 |
| Icon limit, filter distances | have, partly | Areas merge close spawns (MERGE_YARDS); a cap if busy zones need it |
| Icon themes and overrides | skip | |

## Automation

| Questie | Status | Questmarker / notes |
| --- | --- | --- |
| Auto accept, auto complete, modifier key | have | Accept regular/daily/weekly, turn in, override key, "only while held" |
| Rules for NPCs (normal, repeatable, dungeon/raid, PvP, event, trivial) | have, partly | Daily/weekly split; type filters are a candidate |
| Rules for quests shared by players | planned | Auto-accept shares, off by default, in the Automation section |
| Reject shares in battlegrounds, from non-friends | planned | Off by default |
| Abandon a quest when its breadcrumb isn't done | skip | Destructive; not without a confirm |

## Nameplates and target frame

| Questie | Status | Questmarker / notes |
| --- | --- | --- |
| Quest objective icon on nameplates (position, scale) | planned | Roadmap 3 |
| Same on the target frame | planned | With the nameplate work |

## Advanced and other

| Questie | Status | Questmarker / notes |
| --- | --- | --- |
| Show item/NPC/object/spell/quest IDs in tooltips | planned | Toggle, off by default |
| Profiles (create, copy, delete) | planned | Profiles exist in saved data; add the UI |
| Locale selection | skip | Follows the client |
| My Journey (quest history), Advanced Search, Quests by Zone/Faction, profiler, debug | skip | Parked by the user (not used) |
| Dungeon quests at instance entrances | skip for now | Dungeon features not started |
