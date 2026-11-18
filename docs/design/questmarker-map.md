# BubbleMap: a minimap made for the suite

Proposed 2026-11-17 as Questmarker_Map; renamed and made standalone the same day (suite rules:
[bubble-suite.md](bubble-suite.md)). Steps 1-4 of the build order are built (in game review); 5-8
are not started. (This file keeps its old name so links to it keep working.)

A SexyMap replacement that fits the Bubble suite: a clean square minimap, everything around it redone
and toggleable, one condensed list instead of addon minimap buttons, and terrain (design:
[terrain-map.md](terrain-map.md)) for padding, extended zoom and the world map. Standalone: with
BubbleQuest loaded too, the map rests on BubbleQuest's tracker as one designed column.

## Packaging

- **Its own addon, its own release.** `BubbleMap/` (TOC `BubbleMap.toc`, `## OptionalDeps:
  BubbleQuest`, SavedVariables `BubbleMapDB`, `/bmap`). For now it lives in BubbleQuest's repo and is
  left out of BubbleQuest's zip (`.pkgmeta` ignore); it moves to its own repo and CurseForge project
  per the suite doc.
- **The big data is a second, load-on-demand addon,** `BubbleMap_Terrain/` (`## LoadOnDemand: 1`,
  `## Dependencies: BubbleMap`): the city and dungeon WMO tables (~2.6 MB), loaded by
  `C_AddOns.LoadAddOn` the first time a city or dungeon is drawn. The continent tile table (~92 KB) is
  needed whenever the minimap draws padding, so it lives in BubbleMap itself.
- **Local testing:** a junction `_forever_\Interface\AddOns\BubbleMap` to the repo folder.
- **Settings:** its own page in Options > AddOns (`Settings.lua`). STOPGAP until the suite's shared
  library (LibBubble) brings the one settings window every Bubble addon uses.

## BubbleQuest, when it's there

BubbleMap never reaches into BubbleQuest's private namespace. BubbleQuest has one read-only, versioned
global, `BubbleQuestAPI` (`Core/API.lua`). BubbleMap finds it with `rawget` at load and checks `API`;
every quest feature is gated on it.

| Member | What | Built |
|---|---|---|
| `API` | Version number (1) | yes |
| `RegisterCallback(event, fn)` | `ProfileChanged`, `TrackerResized` (width), `ThemeChanged`, `AreasChanged`, `TrackerAttachMoved` | yes |
| `GetTracker()` | The tracker's root frame (nil before PLAYER_LOGIN) | yes |
| `SetTrackerAttach(frame)` / `nil` | Hang the tracker's top under `frame`; while attached its header drags `frame` (if movable) and fires `TrackerAttachMoved`. Queued after combat | yes |
| `Theme()` | Font object names, panel colours, padding | yes |
| `SetMinimapView(view)` / `nil` | Point the minimap quest renderer at a larger frame (below) | step 5 |
| `FrameLevels()` | World map canvas levels BubbleQuest uses (quest areas 2004, town services 2006, "!" 2007, "?" 2008, fan row 2010+), so the terrain layer sits under them | step 7 |

**Reuse, not reimplementation.** BubbleQuest's `UI/MinimapAreas.lua` draws quest areas, the guide
line, the "!" givers and the "?" turn-ins from a centre (the player) and a pixels-per-yard scale,
clipped by a mask. The padding around the square is the same picture over a bigger frame, so it stays
one renderer: `SetMinimapView({ frame = outer, scale = fn })` makes it draw into `outer`, mask fitted
to it, asking `scale()` for pixels per yard (BubbleMap owns zoom). Without a view, it draws on
`Minimap` as today. Its hover requires the minimap itself under the cursor (`GetMouseFoci`), so
nothing flashes through frames on top of it, BubbleMap's bar included.

## The minimap: Blizzard's frame, restyled in place

Blizzard's `Minimap` stays in its Edit Mode container: Edit Mode scales it, we never move or reparent
the container. SexyMap reparents the minimap to `UIParent` (Edit Mode then moves an empty box), uses
`SetScript` on Blizzard frames and overwrites their methods; we do none of that, and we don't hook Edit
Mode's apply path (`SetEditModeScale`), where BubbleQuest's tracker taint once came from.

- **Square:** `Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")` and our own 1 px border.
  Re-applied from a post-hook on `MinimapCluster:UpdateMinimapConfig`: Forever resets the mask on every
  rotate toggle (`Blizzard_Minimap/Camelot/Minimap.lua:42, 96-98`). The hook sets widget state only.
- **Blizzard's round ring:** `MinimapCompassTexture` and its underlay at alpha 0.
- **Blob rings:** arch, quest and task blob ring scalar and alpha to 0.
- **`GetMinimapShape`:** defined, returning `"SQUARE"` (LibDBIcon and MinimapAreas read it).
- **After resizing, a redraw:** the engine kept drawing the ground at the old size until the player
  moved (seen in game); a zoom step and back the next frame redraws it.

### The column

- **`outer`** (ours, `BubbleMapFrame`): the column's top, holding the border. Width: BubbleQuest's
  tracker width when it's loaded (the tracker attaches under it), else the "Width" setting. Height:
  a percentage of the width (setting). Blizzard's minimap is anchored to `outer`'s centre inside its
  own container (Blizzard positions only the container, never `Minimap`) and sized to the largest
  square that fits.
- **Tracker attached** is a setting (on by default): off, BubbleQuest's tracker goes back to its own
  place and the map takes BubbleMap's own width.
- **Position:** whatever moved last wins. Until dragged, `outer` hangs from the top corner of Edit
  Mode's minimap box nearest the screen edge, so it grows inward (centred on the box it ran off the screen: Edit Mode clamps only its
  own box; seen in game). Dragged, by BubbleQuest's tracker header or BubbleMap's own bar (when "Lock
  the map" is off), `outer` keeps its own saved position; `/bmap reset` goes back to Edit Mode's.
  Never in combat (the tracker's secure quest item buttons hang under it).
- **Watched cheaply:** a throttled check on `outer` notices Edit Mode scale and box changes.
- **Rectangular map:** if the engine renders a rectangular minimap (`SetSize(w, h)`, `w ~= h`), it
  fills the frame; else the rest is **terrain padding** at the minimap's scale (step 5), ideally with
  Blizzard's ground off (`C_Minimap.SetDrawGroundTextures(false)`) and all ground ours, no seam.
  Blizzard's blips (herbs, ore, party) draw only inside its square; our quest content covers all.
- **Rotation:** with "Rotate Minimap" on, Blizzard's square ground clips at diagonal headings; with
  terrain, our rotated ground fills it ([terrain-map.md](terrain-map.md)).

### Our map, gather mode, and zoom (step 6, built)

Blizzard's blips (herbs, ore, tracking, party, the game's own quest "?" and "!") are only right at
Blizzard's own zoom levels and size, and addons can't read or redraw them. Tried and rejected,
2026-11-17: scaling Blizzard's minimap frame behind a mask (*mask magnify*) or inside a clipping parent
(blips spilled outside the map, the arrow sat off-centre); its alpha at 0 (the engine still drew the
blips); the QuestPOIs tracking filter (the game's "?"/"!" still drew). So the map is either ours or
Blizzard's, never a mix:

- **Our map (the default):** Blizzard's minimap hidden (`Hide`), its zoom fixed at its farthest level;
  BubbleMap draws everything: terrain, our player arrow, BubbleQuest's quest layer
  (`SetMinimapZoom(k, true)`: the game draws no markers, ours draw everywhere).
- **One zoom scale everywhere:** 13 steps, x1.5 each, six in and six out of Blizzard's farthest view
  (the slider's gold middle notch). A vertical notched slider shows at the map's right edge while
  zooming, then fades.
- **Gather mode** (setting: off by default, automatic while a tracking spell is on, or on; the bar's
  gather button toggles it): at the steps where a Blizzard level matches ours within 10% (the middle and
  three in: 1, 0.67, 0.44, 0.30 against Blizzard's 1, 0.71, 0.43, 0.29), Blizzard's minimap shows at
  that level for its live blips, our terrain under it at its exact scale (green dots on the slider).
  Every other step is our map.
- **Ctrl peek** (in our map): Blizzard's minimap at its farthest level while Ctrl is held; no zooming
  while held; released, our map at exactly the zoom it had.
- **Indoors / no terrain** (instances, maps not in the table): Blizzard's minimap with its own zoom.
- **Quest markers in gather mode:** the game draws its "?" and "!" within 0.8 of its view radius
  (measured: 186.5 of 233.3 yd and 159.5 of 200 yd); BubbleQuest skips its own "?" where the game's
  marker is inside that circle, and all its "!" inside it (the game draws a giver's "!" when the client
  has loaded that NPC, which no addon API can tell).
- **One ground:** our terrain in both modes outdoors (Blizzard's ground off), so the colour never
  changes with the mode.
- **Drawn ourselves in our map** (Blizzard's minimap is hidden, its blips with it): group members
  (Group.lua) and BubbleQuest's town services (its QuestView draws them while SetMinimapZoom says the
  game's minimap is hidden; docs/design/town-services.md).
- **Later:** the rest of what Blizzard's minimap showed (corpse and graveyards, rares and treasures,
  flight masters, pings), and a gathering database (GatherMate2 and the like) for possible node spots.

## Around the minimap (built, step 3)

Our own frames (`Around.lua`), each a setting. Blizzard's versions are always faded out while
BubbleMap styles the map, since they're laid out for the round map: alpha 0 and mouse off, never
`Hide()`. `Show()` doesn't reset alpha, so Blizzard re-showing one (zoom buttons on every mouse-over,
the clock's alarm) changes nothing and needs no hook; and `MinimapCluster` is a `ResizeLayoutFrame`
measuring its shown children, so `Hide()` would shrink Edit Mode's box.

Our frames over the map sit one **strata** above the minimap's: `MinimapCluster` is toplevel, so a
click on the map raised it over anything at its strata and the bar vanished (seen in game).

| Element | Ours | Default |
|---|---|---|
| Top bar | along the map's top, the tracker header's band; drags the column when unlocked | on |
| Zone name | coloured by PvP status; tooltip zone/subzone; click: world map | on |
| Tracking | our `MenuUtil` menu, Blizzard's listing rule (optional filters or a spell); predicted state until `MINIMAP_UPDATE_TRACKING`, as Blizzard's menu does | on |
| Calendar | invite count; click: calendar (out of combat: a UI panel) | on |
| Mail | envelope when there's mail; tooltip lists senders | on |
| Clock | `GameTime_GetTime` (the game's local/realm and 24 h settings); click: clock settings, or stops a ringing alarm | on |
| Coordinates | bottom left; Blizzard's frame faded, not its CVar (that's the player's own setting) | off |
| Zoom +/- | bottom right; the wheel zooms either way | off |

Not on Forever, so not replaced: crafting orders, instance difficulty, the landing page button.
Left alone: the queue eye (`QueueStatusButton`, its own Edit Mode system; move it in Edit Mode if it
lands on the map). Also faded: the day/night frame, `MinimapBackdrop` (its event-URL button too).

## The addon list (built, step 4)

One condensed list (`Launchers.lua`) from the bar's Addons button (a drawn 2x2 grid); addons' minimap
buttons are put away.

- **Sources:** LibDataBroker launchers (and LibDBIcon's buttons' data objects); Blizzard's addon
  compartment (`AddonCompartmentFrame.registeredAddons`, read only); stray `Button`s on `Minimap` that
  are named, unprotected and neither Blizzard's nor LibDBIcon's.
- **Each row** runs exactly what the original ran: `obj.OnClick(row, button)`;
  `data.func(data, { buttonName = button }, row)` as Blizzard's menu calls it; `button:Click()` for
  strays. Tooltips from `OnTooltipShow`, `OnEnter` or the compartment's `funcOnEnter`.
- **One row per addon, both actions kept.** LibDBIcon's own compartment entries are dropped (same
  `OnClick`). Any other compartment entry matching a launcher (name, shown name or the addon's folder,
  compared on letters only; or the same icon) becomes that row's **gear**: an addon's button and
  compartment entry often differ (Bagnon: bags and bank on the button, options on the entry; dropping
  one lost it, seen in game).
- **Putting buttons away** never touches another addon's saved settings: LibDBIcon buttons `Hide()`
  plus an `OnShow` re-hide (the library re-shows on `Refresh`/`Show`), and the
  `LibDBIcon_IconCreated` callback for late ones; the compartment button and strays faded.
- **Another button collector** (MinimapButtonButton, MBB, MinimapButtonBag) and the list stays off,
  with a prompt offering to turn that one off. ForeverCleanButtons is not one (it skins action
  buttons); a wrong guess here once switched the list off silently.
- **Later:** hide individual entries, a search box.

## The world map (steps 7-8)

- **Terrain toggle** on Blizzard's world map, as in [terrain-map.md](terrain-map.md): the layer at
  level 2003, above explored-area art (2002) and below BubbleQuest's quest areas (2004), read from
  `GetFrameLevelStart` each time. No room to spare: re-check if either side moves.
- **Deep zoom isn't possible on Blizzard's world map** without tainting it: its zoom levels are rebuilt
  from map art data on every canvas resize (`MapCanvas_ScrollContainerMixin.lua:485-516`); appending a
  level puts our table before many Blizzard readers, and pin acquisition reaches a protected call. So
  deep zoom lives in **our own map window** (MapWindow.lua; built as plain frames over TileView, not
  a `MapCanvasFrameTemplate`). BubbleQuest's phase 11 quest log window may share it.
- **In the window**, bottom up: the sea's colour where there's no tile (`ns.SEA`, sampled from the
  tiles' own sea, so the coast's tile grid doesn't show), terrain, the hovered zone's highlight
  (Blizzard's continent-map glow, `C_Map.GetMapHighlightInfoAtPosition`, its rectangle turned into
  world yards), BubbleQuest's QuestView (quests and town services less flight masters), Blizzard's map
  points (MapPoints.lua: flight masters with their discovered state, dungeon entrances, area points,
  gathered from the continent's UI map and every zone under it), group members, the player's arrow.
  The hovered zone is named in the title.

## Other minimap addons

SexyMap (or another known minimap addon, or anyone defining `GetMinimapShape` first) loaded:
BubbleMap leaves the minimap alone and prompts once per login ("Turn SexyMap off" reloads; "Don't ask
again"). Two addons setting the mask and defining the shape would fight.

## Build order

1. ~~Packaging and API~~ (built).
2. ~~Square map and the column~~ (built).
3. ~~Around the minimap~~ (built).
4. ~~Addon list~~ (built).
5. ~~Terrain core and padding~~ (built): pipeline and continent tiles, `SetMinimapView`, padding at the
   minimap's scale, rotated ground, one ground outdoors.
6. ~~Our map, gather mode, zoom~~ (built; see the section).
7. **World map terrain toggle** with cities (`BubbleMap_Terrain`).
8. **Our map window:** deep zoom, then dungeons.

## Settle in game

Settled: `Minimap:SetSize` square works and survives Edit Mode with no taint seen; alpha plus mouse
off keeps Blizzard's elements away; `LibDBIcon:Hide` plus the re-hide holds (the list in review).

Settled too: mask magnify doesn't mask the blips (rejected, see Zoom); our padding lines up with the
minimap, and one ground (Blizzard's off outdoors) removed the seam.

Open:
1. Does `Minimap:SetSize(w, h)` with `w ~= h` render a rectangle, or stretch? (Not needed now.)
2. Everything in [terrain-map.md](terrain-map.md)'s list.
