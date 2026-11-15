# Hint triage brief

You are deciding, for each forever-db step row, whether it becomes a **hint**, a **do** line, or is
**skipped**, for Questmarker, a World of Warcraft: Forever quest tracker. Each quest card shows the
quest's objectives ("Kill Kobold Vermin 3/10"), a source line for items ("Loot Red Burlap Bandana from
Defias Thug"), a tag for elite/dungeon/group quests, and its category (dungeon, profession, seasonal,
class, repeatable get their own groups). A **hint** is a one-line tip under the objectives, shown only
when a quest has a step that confuses players. Most quests need none: be selective.

## Input

One JSON object per line: `id`, `quest`, `title`, `level`, `action` (gotcha, craft, accept, loot,
kill, other, turn-in, collect-object, use-item, combine, buy, summon), `text` (the source fact), and
`objectives` (the names the quest's objectives are about: creatures, items, objects).

## Decisions

**hint**: the text describes something a player would not figure out from the objective and would
get stuck on. For example:
- timers and despawns ("the bauble disappears 5 minutes after you loot it");
- hidden or conditional spawns ("only shows up after you click her grave", "summon it at a wind stone");
- using, combining or keeping an item ("keep the barrel, you hand it in", "combine the pages with the
  cover", "use the whistle to call your orphan");
- where something really comes from when it is not obvious ("the salves come from the Cenarion salve
  quests", "the sacks are objects you click, not mob drops");
- how to approach a mob or object in a non-obvious way ("stealth first or it attacks", "talk to him,
  the credit comes from his dialogue, not from fighting").

**do**: the text states, more clearly than "Collect X" / "Kill X", what to *do* for **one** objective,
and that action is not a trick but simply the clear instruction ("Click mounds of loose soil to get
Neru", "Smelt Thorium Ore into bars with Mining, or buy them"). It replaces that objective's line.

**skip**: everything else, in particular:
- needs a group / raid / dungeon / elite (the card's tag and categories already say so);
- only during an event or holiday; PvP or battleground;
- trivia: reward changes, "on Forever any class can do it", quest chain bookkeeping;
- restating the objective or the obvious ("kill 10 kobolds", "accept from X", "turn in to Y",
  "loot it from the mobs that drop it" when the drop source is the obvious quest mob);
- `accept` rows (a hint only shows once the quest is accepted, so how to start it is useless here),
  unless it also says something that matters while doing the quest;
- `turn-in` rows, unless the turn-in is genuinely surprising (not the giver, a different place).

**Rules settled after the first run** (batches disagreed; these are now fixed):
- **Reputation needed to turn in** ("You must be Honored with X to turn this in"): **hint**, worded
  "You must be <standing> with <faction> to turn this in." It blocks the turn-in, which the card
  can't show. (Reputation that only matters to accept a quest: skip.)
- **"Keep item X"** where X is one of the row's `objectives`: **skip**, the card already lists it.
  Hint only if a later quest in the chain also needs it, or it is a tool you use ("the catapult
  needs the Dwarven Tinder to be lit"). "Keep" items that are *not* objectives (from an earlier
  quest, handed in at the end) stay hints.

**Mixed rows**: if a row has a generic part and a real trick ("needs a group. The boss has no static
spawn, it appears after an event"), keep only the trick, as a hint.

## Writing hints and do lines

- English, plain words, ASCII only (straight quotes, no dashes like en/em dash, no ellipsis character).
- Hint: one sentence, two at most, **at most 110 characters**. Lead with the action or the warning.
- Do line: imperative, **at most 70 characters**, no trailing period.
- No IDs: never quest numbers, item numbers, spell numbers ("container item (22568)" -> "a container
  item", "quests 4103-4108" -> "the Cenarion salve quests" if the text says what they are, else "other
  quests").
- Keep proper names (creatures, items, places) exactly as written.
- Do not invent facts. If the text is unclear or seems wrong, skip it and say why.

## Output

Write one JSON object per line, **one line per input row, in input order**, nothing else:

- hint: `{"id": "...", "decision": "hint", "text": "...", "reason": "..."}`
- do: `{"id": "...", "decision": "do", "objective": "...", "text": "...", "reason": "..."}`
  where `objective` is exactly one of the row's `objectives` strings.
- skip: `{"id": "...", "decision": "skip", "reason": "..."}`

`reason`: a few words ("timer", "hidden spawn", "group only", "restates objective", "trivia").
Valid JSON per line (escape quotes inside strings). Copy `id` exactly.
