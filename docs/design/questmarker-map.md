# Questmarker_Map: a minimap made for the tracker

Proposed 2026-11-17. Not started. A companion addon that replaces SexyMap for Questmarker players: a
clean square minimap resting on top of the tracker as one designed column, everything around the
minimap redone and toggleable, one deduplicated launcher list instead of minimap buttons, and terrain
(design: [terrain-map.md](terrain-map.md)) for padding, overview zoom and the world map.

Players who want standalone minimap styling have SexyMap; this addon exists to integrate with
Questmarker and requires it.

## Packaging

- **Same repo, same release, two addons side by side** (the BigWigs/DBM model). `Questmarker_Map/`
  is a folder in the repo with its own TOC: `## Dependencies: Questmarker`, version
  `@project-version@`. One tag releases both, so versions can't drift; no second CurseForge project.
- **The big data is a third, load-on-demand addon,** `Questmarker_Terrain/` (`## LoadOnDemand: 1`,
  `## Dependencies: Questmarker_Map`): the city and dungeon WMO tables (~2.6 MB). Loaded by
  `C_AddOns.LoadAddOn` the first time a city or dungeon is drawn. The continent tile table (~92 KB) is
  needed whenever the minimap draws padding, so it lives in `Questmarker_Map` itself.
- **Changes:**
  - `.pkgmeta`: `move-folders` for both subfolders; the ignore list stays.
  - `tools/package.py`: from one `ADDON` to a list of addon folders, each with its TOC, listed files and
    version substitution. `--check` keeps working on the union.
  - `tools/lint.py` / `apiguard.py` scan by directory; confirm they cover the subfolders and that each
    addon's globals are declared in `.luarc.json`.
  - Local testing: a second junction, `_forever_\Interface\AddOns\Questmarker_Map` to the repo subfolder
    (same for `Questmarker_Terrain`).
- **Switching it off** is the AddOns list. Players who already run a minimap addon leave it unticked.

## Interface between the two addons

`Questmarker_Map` can't see Questmarker's private namespace and must not copy its code. Questmarker
gets one read-only global, `QuestmarkerAPI` (added to `.luarc.json` `diagnostics.globals`):

| Member | What |
|---|---|
| `API` | Version number, starting at 1. The map addon checks it at load and stays off (with one chat line) if it's older than it needs |
| `RegisterCallback(event, fn)` | `"AreasChanged"` (from `MapAreas:MarkDirty`/`version`), `"ProfileChanged"`, `"TrackerResized"` |
| `GetTracker()` | The tracker's root frame, for docking and width |
| `SetTrackerDock(frame)` / `nil` | Dock the tracker's top edge under `frame` (and take its width from the tracker setting); `nil` restores normal positioning |
| `SetMinimapView(view)` / `nil` | Point the minimap quest renderer at a larger frame (below) |
| `Theme()` | Fonts, colours, border and spacing, so both addons look like one |
| `FrameLevels()` | The world map canvas levels Questmarker uses (quest areas 2004, town services 2006, "!" 2007, "?" 2008, fan row 2010+) so the terrain layer can sit under them |

**Reuse, not reimplementation.** `UI/MinimapAreas.lua` already draws quest areas, the guide line,
the "!" givers and the "?" turn-ins from a centre (the player) and a pixels-per-yard scale
(`Minimap:GetWidth() / 2 / C_Minimap.GetViewRadius()`), clipped by a mask. The padding around the
square is the same picture over a bigger frame, so it stays one renderer:

- `SetMinimapView({ frame = outer, scale = fn })`: the renderer draws into `outer` instead of on
  `Minimap`, with its mask fitted to `outer`'s shape, and asks `scale()` for pixels per yard (the map
  addon owns zoom). Hover tests `outer:IsMouseOver()`.
- With no view set (map addon off), it draws on `Minimap` exactly as today.
- Its tooltip stays `QuestmarkerMinimapTooltip`. We keep Blizzard's `Minimap` frame, so
  `Minimap_OnUpdate` still takes over `GameTooltip` every frame.

The world map terrain layer needs nothing from the API except `FrameLevels()`.

## The minimap: Blizzard's frame, restyled in place

We keep Blizzard's `Minimap` inside its Edit Mode container. Edit Mode places it, and everything we
add is our own frames. SexyMap reparents the minimap to `UIParent`, which leaves Edit Mode moving an
empty box. It also uses `SetScript` on Blizzard frames and overwrites their methods. We do none of
that, and we don't hook Edit Mode's apply path (`SetEditModeScale`), which is where our tracker taint
came from.

- **Square:** `Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")`, and our own border frame in
  the tracker's style. Re-applied from a post-hook on `MinimapCluster:UpdateMinimapConfig`, because
  Forever resets the mask on every rotate toggle (`Blizzard_Minimap/Camelot/Minimap.lua:42, 96-98`). The
  hook sets widget state; it calls no Blizzard update function.
- **Blizzard's round art:** `MinimapBackdrop` (ring, compass, expansion and event buttons) and
  `MinimapCompassTexture` hidden.
- **Blob rings:** `SetArchBlobRingScalar/Alpha`, `SetQuestBlobRingScalar/Alpha`,
  `SetTaskBlobRingScalar/Alpha` to 0 (SexyMap misses the task blob).
- **`GetMinimapShape`:** defined, returning `"SQUARE"`: LibDBIcon and `MinimapAreas.isSquare()` read it.
- **Mouse wheel zoom:** Blizzard's own `OnMouseWheel` (`Minimap.xml:280`) is kept, extended through our
  zoom (below) via `HookScript`.

### The column: map on the tracker

- **Width comes from the tracker.** The tracker's width setting (and its resize grip) sets the map's
  width; the map's height is its own setting. The map's outer frame is anchored on `Minimap`, and the
  tracker docks under it (`SetTrackerDock`), so moving the minimap in Edit Mode moves the whole column.
- **The outer frame is as big as the column.** Blizzard's minimap sits in it at the largest size that
  fits, sized with `Minimap:SetSize` and re-applied from the same post-hook.
  - If the engine renders a rectangular minimap (`SetSize(w, h)` with `w ~= h`), it fills the whole
    frame.
  - If not, it's the largest square, centred, and the rest is **terrain padding** at exactly the
    minimap's scale. The cleaner form: `C_Minimap.SetDrawGroundTextures(false)` and draw all ground
    ourselves (no seam), Blizzard's blips still drawn in the square. Blizzard's HybridMinimap does the
    same (`Blizzard_HybridMinimap.lua:44`).
- **The limit:** Blizzard's blips (herbs, ore, party, tracking) and other addons' minimap pins draw
  only inside Blizzard's minimap. Our quest content covers the whole frame.

### Zoom: one range, Blizzard's in the middle

Pixels per yard is the one zoom value. Blizzard's levels (`Minimap:GetZoomLevels()`, discrete) are
the middle of the range.

- **Zoom out past level 0: overview.** The minimap fades out (alpha), ground drawing is off, and our
  terrain plus quest content fill the frame, zooming smoothly. Blips vanish at this zoom: the honest
  limit.
- **Zoom in past the last level:** the minimap can't be clipped by a parent without reparenting it out
  of Edit Mode, so two options, tested in that order:
  1. *Mask magnify:* `Minimap:SetSize(k * side)` with a generated mask whose opaque centre is `1/k`
     of the texture (`tools/make_*.py` style), so the visible part stays the same size and shows `k`
     times the detail, blips included. Unknown whether the engine masks blips and the ground the same
     way; in-game test.
  2. *Fallback:* our terrain, as in overview. Upscaled tiles go soft past about Blizzard's closest
     level (256 px per 533 yd); our quest content stays sharp.

### Hiding Blizzard's elements

Alpha 0 with the mouse disabled first. If that leaves visible problems, parent to a hidden frame of
ours. None of these is an Edit Mode system, so the tracker's taint doesn't apply [Inferred; in-game
check]. Blizzard re-shows the zoom buttons on `Minimap` `OnEnter` (`Minimap.lua:257`), so their
hiding is re-applied from a post-hook. The addon compartment button re-shows on every registration
(`AddonCompartment.lua:172`): `HookScript("OnShow")` re-hide.

## Around the minimap: all ours, each a setting

Our own frames, never restyled Blizzard ones. Each has its own on/off setting; Blizzard's original is
hidden only while ours is on.

| Element | Ours | Source |
|---|---|---|
| Zone text | name, coloured by PvP status; click opens the world map | `GetMinimapZoneText`, `GetZonePVPInfo` |
| Clock | local or realm time, 12/24 h; click opens the stopwatch/time manager | `GameTime_GetTime`-style; verify |
| Coordinates | x, y to one decimal | `C_Map.GetPlayerMapPosition`; Blizzard's off via `SetCVar("minimapShowPlayerCoords", 0)` (`Minimap.lua:486-488`) |
| Zoom +/- | small buttons, or none (wheel only) | our zoom |
| Tracking | button opening our menu of tracking types | `C_Minimap` tracking functions; verify which are restricted |
| Mail | icon when there's mail; tooltip lists senders | `HasNewMail`, `GetLatestThreeSenders` |
| Calendar | date button; pending invites shown | opens the calendar |
| Queue status | Blizzard's eye is a protected, menu-bearing button outside the minimap: we don't rebuild it. Setting chooses where ours shows a status line; the eye stays Blizzard's | research |
| Difficulty | instance difficulty tag | `GetInstanceInfo` |
| Expansion / landing page | button, if the client has one | research |
| Crafting orders and other indicators | each found on Forever's minimap gets a row here | research |

The research rows are settled before building them: what Forever actually puts around its minimap.

## The launcher list (replaces every minimap button)

One condensed, deduplicated list (a drawer button on the map's border opens it). No addon keeps a
minimap button.

- **Sources:**
  - LibDataBroker launchers via LibDBIcon (`GetButtonList`, `GetMinimapButton`, callback
    `LibDBIcon_IconCreated`), plus LDB's `DataObjectIterator` for launchers without an icon button.
  - Blizzard's addon compartment: `AddonCompartmentFrame.registeredAddons` (read only, never sorted or
    changed), and TOC `AddonCompartmentFunc` entries rebuilt from `C_AddOns` metadata so we know the
    folder name (Blizzard keeps it only in a closure, `AddonCompartment.lua:127-129`).
  - Stray buttons: unprotected `Button`s parented to `Minimap` that are neither Blizzard's nor
    LibDBIcon's.
- **Dedup:** key LDB launchers by LDB name, compartment entries by folder name. Drop a compartment row
  whose data is LibDBIcon's own (`lib.objects[name].compartmentData`, the same table). Otherwise match
  an LDB name to a folder name case-insensitively, colour codes stripped. With both, show the LDB
  launcher (richer tooltip).
- **Each row:** icon, name; left/right click run exactly what the button ran (`obj.OnClick(row, button)`;
  compartment: `_G[funcName](addonName, button)`); tooltip from `OnTooltipShow` or `OnEnter`/`OnLeave`.
- **Hiding their buttons:** `LibDBIcon:Hide(name)` after `PLAYER_LOGIN` (it doesn't write the owner's
  saved `db.hide`) plus an `OnShow` re-hide, since the library re-shows on `Refresh`/`Show`. Never
  `Lock`/`Unlock`/`AddButtonToCompartment`, which write the owner's settings. Stray buttons: alpha 0,
  mouse off.
- **List options:** sort by name, a search box once it's long, hide individual entries.

## The world map

- **Terrain toggle** on Blizzard's world map, as in [terrain-map.md](terrain-map.md). The layer sits
  above explored-area art (2002) and below our quest areas (2004): level 2003, read from
  `GetFrameLevelStart` each time, with no room to spare. If Blizzard or the peer layers change, this
  is the first thing to re-check.
- **Deep zoom: not on Blizzard's world map.** Its zoom levels are rebuilt from map art data on every
  canvas resize (`MapCanvas_ScrollContainerMixin.lua:485-516`). There's no supported knob; appending a
  level from a hook puts our table in front of many Blizzard readers, and pin acquisition reaches a
  protected call (`SetPassThroughButtons`), so it would break in combat. Leatrix_Maps doesn't do it
  either (its zoom is its own dungeon-map frame).
- **So deep zoom lives in our own map window:** a `MapCanvasFrameTemplate` instance we own, where we can
  override `CreateZoomLevels` freely. Terrain, our quest layers, the turn-in and giver icons, any
  Blizzard data providers we choose. Our pins override `CheckMouseButtonPassthrough` (protected in
  combat). This is the "quest map". Phase 11's quest log window may want to share it (log on the left,
  map on the right); decide when phase 11 starts.

## Coexisting with SexyMap and other minimap addons

If SexyMap (or another known minimap addon) is loaded, `Questmarker_Map` tells the player once (the
Questie prompt's pattern, with "don't ask again") and leaves the minimap untouched. The world map
terrain toggle and our own map window still work. Two addons both setting the mask and defining
`GetMinimapShape` would fight.

## Build order

Each step usable on its own.

1. **Packaging and API:** the folders, `.pkgmeta`, `package.py`, lint coverage, junctions;
   `QuestmarkerAPI` with `API`, callbacks, `GetTracker`, `SetTrackerDock`, `Theme`.
2. **Square map and the column:** mask, border, hidden art and blob rings, `GetMinimapShape`,
   `SetSize` to the column, tracker docked under it, SexyMap stand-down.
3. **Around the minimap:** the table above, each with its setting.
4. **Launcher list.**
5. **Terrain core and padding:** pipeline and continent tiles ([terrain-map.md](terrain-map.md)),
   `SetMinimapView`, padding at the minimap's scale.
6. **Zoom:** overview past level 0; the mask-magnify test, else terrain past the last level.
7. **World map terrain toggle** with cities (`Questmarker_Terrain`).
8. **Our map window:** deep zoom, then dungeons.

## Settle in game

1. Does `Minimap:SetSize(w, h)` with `w ~= h` render a rectangle, or stretch?
2. Does `Minimap:SetSize` survive Edit Mode (enter, change scale, leave), and does it taint Edit Mode?
3. Does the mask-magnify trick mask the blips and ground alike?
4. Does alpha 0 plus mouse off keep each hidden Blizzard element out of the way, and do the zoom buttons
   stay hidden through `OnEnter`?
5. Seam: does our padding line up with Blizzard's ground at every Blizzard zoom level and indoors?
6. Does `LibDBIcon:Hide` plus the `OnShow` re-hide hold through other addons' `Refresh` calls?
7. Everything in [terrain-map.md](terrain-map.md)'s list.
