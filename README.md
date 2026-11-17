# BubbleQuest

A quest helper addon for World of Warcraft: Forever, part of the BubbleSuite. Formerly Questmarker.
Licensed under GPL-3.0-or-later (see `LICENSE`).

## Install (dev)

Junction this folder into the Forever AddOns directory as `BubbleQuest`, and each companion folder
(`BubbleMap`, and `Questmarker`: the stub that hands old Questmarker settings over) under its own
name, so the game reads the repo directly and changes only need a `/reload` (PowerShell):

```
$addons = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
New-Item -ItemType Junction -Path "$addons\BubbleQuest" -Target <repo path>
New-Item -ItemType Junction -Path "$addons\BubbleMap" -Target <repo path>\BubbleMap
New-Item -ItemType Junction -Path "$addons\Questmarker" -Target <repo path>\Questmarker
```

New addon folders need a full game restart (not just `/reload`). Then type `/bq` (`/qm` still works).

Forever disables user scripts, so `/dump`, `/run` and `/script` do nothing (silently). Debug through
the addon's own slash commands instead.

## Lint

```
python tools/lint.py            # lint (first run fetches tools into .tools/)
python tools/lint.py --update   # bump to the latest Forever API data, LuaLS and annotations
```

Requires git, curl and Python 3.12+. Run it after every change; it must pass before committing.

Two layers:

1. **LuaLS** with [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api), the Forever
   FrameXML source, and generated declarations for XML-named Blizzard frames. Catches undefined globals
   (nonexistent APIs), wrong argument types, deprecated calls, accidental globals. Same config
   (`.luarc.json`) drives the editor: install the `sumneko.lua` VS Code extension.
2. **Forever API guard** (`tools/apiguard.py`) checks every call against Blizzard's own API docs from
   the `forever` branch of [wow-ui-source](https://github.com/Gethe/wow-ui-source), which carry the
   restriction metadata LuaLS annotations drop:
   - **errors:** protected or SecureOnly functions, `C_` functions missing on Forever (retail-only),
     undocumented event names, method names nothing defines (`frame:SetPointt`)
   - **warnings:** restricted or secret-returning calls and events, Blizzard Lua functions that
     directly call a restricted API (e.g. `Settings.OpenToCategory`), secure templates
     (combat-locked frames)

Every warning fails the lint until reviewed. Once a restricted call is confirmed correct, acknowledge
it on the same line or the line above, with a reason:

```lua
-- apiguard: allow name only used for display, never compared
local name = UnitName("target")
```

Tool versions are pinned in `tools/toolchain.json`, so everyone lints against the same Forever build.
