# Phase 7 design: hints

Spec, Hint system and sourcing: a Hint line "shown only when the quest has a known confusing step";
data "keyed by quest ID -> objective -> {do, where, hint, source}", shipped with the addon,
regenerated per release; pipeline: forever-db tips triaged first (generic ones become tags, real
tricks become hints), LLM rewrite, keep attribution, human review queue.

Evidence tags: [Read] counted or read in the bundled LibForeverData 2026.11.1.

## The data

forever-db's `step` table, all of it in the bundled library (`LibForeverData.Steps(questID)`):
2,409 rows over 1,683 quests, written as facts in Polestar's own words, CC BY 4.0 [Read].

| action | rows | example |
| --- | --- | --- |
| gotcha | 1,059 | "Eliza has no fixed spawn. She only shows up after you click her grave." |
| craft | 361 | "Smelt Thorium Ore into 20 Thorium Bars with Mining, or buy them." |
| accept | 317 | (mostly "accept from X") |
| loot | 279 | "Get 60 Silk Cloth. It drops from humanoids around level 20-35, or you can buy it." |
| kill | 125 | |
| other | 84 | "Get three Cenarion Plant Salves. They come as rewards from quests 4103-4108." |
| turn-in | 65 | |
| collect-object | 63 | "Click a dirt mound of loose soil to get Neru." |
| use-item | 18 | "Use the E.C.A.C. on the giant Polly to shrink it. Stealth first so it does not attack you." |
| combine | 15 | "Use a gem to combine the five gems and the Amulet of Spirits into the Amulet of Union." |
| buy, summon | 23 | |

Gotchas by keyword [Read]: 387 "needs a group/raid/dungeon", 186 "event/holiday only", 43 PvP, 106
keep/use/combine an item, 25 timers/despawns, 9 hidden spawns, 302 other (mixed: real tricks next to
trivia like "on Forever any class can do it"). Some mix a generic and a real point ("needs a group.
The boss has no static spawn"); some name raw item IDs ("container item (22568)"). Keyword rules
can't sort these, so the triage is a reading pass, as the spec planned.

## Pipeline (build time, `tools/hints/`, not shipped)

1. `extract.py`: every step row from the vendored library, with its stable step id
   (`<quest>:s:<hash>`, kept across forever-db releases), quest title, and the quest's objective names.
   -> `tools/hints/candidates.jsonl`.
2. **Triage** (the LLM pass): each row gets one decision:
   - `hint`: a non-obvious trick (timers, despawns, hidden spawns, item use, combine, talk-twice,
     escort quirks, "keep this item, you hand it in", where an item really comes from). Rewritten:
     one sentence, imperative, at most ~100 characters, no IDs, names kept.
   - `do`: a clearer action for one objective than the game's text ("Click dirt mounds of loose soil
     for Neru"). Tied to that objective's name. Replaces the Do line.
   - `skip`: generic (group/raid/event/PvP: tags and categories already show it), trivia, or a
     restatement of the objective.
   Done by Claude in batches against a fixed brief (`tools/hints/TRIAGE.md`), so a later run makes the
   same kind of decisions. Results with a reason per row: `tools/hints/triage/*.jsonl`, committed.
3. `build.py`: triage -> `Data/Hints.lua` (sorted, stable diff), and `docs/hints-review.md`: every
   hint and Do line with its source text side by side, the human review queue.
4. **Incremental:** a new forever-db release only sends new step ids to triage; decisions already made
   (and corrected in review) stay.

Attribution: the source text is CC BY 4.0; our reworded versions are adaptations, which
THIRD-PARTY-NOTICES already covers ("Questmark may shorten or reword them"). Each entry keeps
its `source` step id.

## Data format (`Data/Hints.lua`)

```lua
ns.HintData = {
  [2381] = {
    hints = { { text = "Stealth first: Polly attacks before you can use the E.C.A.C.", source = "2381:s:8260ae9a" } },
  },
  [299] = {
    objectives = { ["Neru"] = { action = "Click dirt mounds of loose soil for Neru", source = "299:s:87d9074b" } },
  },
}
```

Objectives are keyed by name (the objective text without its counter), like the rest of Questmark.
Phase 8's player notes merge into the same shape.

## On the card

```
 [18] The Polly Problem            ^ 120 yd  -
      Use the E.C.A.C. on Polly             0/1
      Tip: Stealth first, Polly attacks before you can use it.
```

- **Do line:** a triaged `do` replaces the game's wording (and the phase 4 "Loot X from Y" line).
- **Hint line:** after the objective rows, "Tip:" in a soft blue, wrapping. Several hints: each on its
  own line. Shown on ready cards too ("keep the item, you hand it in" matters at turn-in). Not on
  collapsed cards.
- **Tooltip:** hints in full as well.
- **Setting:** "Show hints", default on.

## Running the triage

About 2,400 short rows, in batches of ~300: 8 Claude subagents, run once now, then only new rows per
forever-db release. Output is reviewed by reading `docs/hints-review.md`; corrections are edits to the
triage files, which `build.py` respects.

## In-game test (after build)

1. A quest with a known trick shows a Tip line; quests without one show none.
2. `/qm quest <id>` lists the quest's hints and their sources.
3. Settings: "Show hints" off hides them.
