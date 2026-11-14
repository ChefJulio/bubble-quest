# Questmark

WoW Forever quest addon. Spec: [docs/SPEC.md](docs/SPEC.md). Build order: the spec's "Implementation plan".

## API ground truth

Model knowledge of the WoW API is out of date and retail-flavored. Forever runs the modern client
(build pinned in `tools/toolchain.json`) with Midnight addon restrictions (secret values, protected calls).

- Before using any API, event, widget method or Blizzard frame, verify it in `.tools/wow-ui-source`
  (Forever branch): `Interface/AddOns/Blizzard_APIDocumentationGenerated/` for API signatures and
  restriction flags, the rest of `Interface/` for how Blizzard itself uses it. Never guess.
- `.tools/` is created by `python tools/lint.py`; run it once if missing.

## Lint: mandatory

Run `python tools/lint.py` after every Lua/XML change. It must print `lint: OK`.

- Never silence a finding to get a pass. Fix the call, or for a restricted call that is genuinely
  correct, add `-- apiguard: allow <specific reason>` and tell the user what was acknowledged and why.
- A clean lint does not prove runtime behavior: secret values, taint and combat lockdown only show up
  in-game. Say so when handing changes over for testing.

## Conventions

- Lua: 2-space indent; addon state lives on the private namespace (`local ADDON_NAME, ns = ...`).
  New globals only when the client requires them (SavedVariables, `SLASH_*`); add those to
  `diagnostics.globals` in `.luarc.json`.
- Never create, move or show/hide secure frames in combat; queue until `PLAYER_REGEN_ENABLED`.
- Hide Blizzard UI, never modify it. Never replace Blizzard functions or scripts (`SetScript` on
  their frames, overwriting globals): that taints. Post-hooks (`HookScript`, `hooksecurefunc`)
  are allowed where needed (e.g. re-hiding the objective tracker on `OnShow`); they run after
  Blizzard's code without changing it. Never call Blizzard's update functions from a hook.
- Testing is in-game: `/reload`, BugSack/BugGrabber for errors.
