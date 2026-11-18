# Terrain map: the minimap's real terrain, beyond the minimap

Proposed 2026-11-16, revised 2026-11-17. Not started. Shows the real terrain the minimap draws (its
ground tiles) where Blizzard doesn't: on the world map instead of the painted art, around and beyond
the minimap, and in our own map window. One shared terrain layer, part of the companion addon
[BubbleMap](questmarker-map.md), which owns the views, zoom and build order. The standalone
"radar" frame first proposed here became that addon's padded, zoomable minimap.

## What the client allows

- **No API.** The minimap's ground is drawn by the engine; nothing returns its tiles. The only control
  is `C_Minimap.SetDrawGroundTextures` (on/off). The minimap can't zoom out past
  `Minimap:GetZoomLevels()`, and `C_Minimap.GetViewRadius()` (yards) is read-only.
- **The tiles are loadable by FileDataID.** They are ordinary BLPs in the client's data. On Forever a
  path string (`World\Minimaps\Azeroth\map36_20`) does not load; the numeric FileDataID does.
  `Texture:SetTexture(asset)` returns `success` (`SimpleTextureBaseAPIDocumentation.lua:604-619`,
  `AllowedWhenTainted`). Proven in play by TerrainWorldMap (MIT) and Forever Simple World Map
  (All Rights Reserved: reference only, nothing copied).
- **Grid:** each continent is 64 x 64 tiles of 533.33 yards, 256 x 256 px, tile index
  `32 - worldCoord / 533.33` (world X and Y swapped: column from world Y, row from world X).
- **Cities and dungeons** are WMO minimap textures: separate, smaller tiles placed per WMO group with
  an offset and a yaw, layered by height. No floors in the data; overlapping levels sort by z.

## Data (build time)

Generated per client build from the local Forever install; FileDataIDs change between builds, so the
data is pinned to `tools/toolchain.json`'s `wow_ui_source.build` and regenerated when it changes.

| Table | Content | Size (TWM's, build 1.60.1) |
|---|---|---|
| Continent tiles | `[continent][col * 64 + row] = fileID`, plus which tiles exist | ~92 KB, ~3,460 tiles |
| City WMO tiles | per capital uiMap: groups of `{fileID, cx, cy, w, h, yaw, z}` | ~574 KB, 828 groups |
| Dungeon/raid WMO tiles | per instance map: same shape | ~2 MB, 2,724 groups |

**Pipeline:** `tools/terrain.py`, a Python port of TerrainWorldMap's MIT Node scripts (`parse_wdt`,
`gen_wmo_tiles`, `gen_mapareas`; credit kept in the file header). Inputs:

- CASCConsole (pinned version) extracts WDT, `_obj0.adt`, WMO root/group and BLP headers from the
  install. The only non-Python piece; a Python CASC reader is its own project.
- wago.tools DB2 CSVs for `product=wowf` at the pinned build: `WMOMinimapTexture`, `WMOAreaTable`,
  `Map`, `UiMapAssignment`.
- FileDataIDs come straight from the WDT's MAID chunk, so no 150 MB community listfile.

Porting rather than vendoring Node: one toolchain, and we own the coordinate math (TWM's
`gotchas.md` documents its hard-won pieces: axis swap, 90-degree WMO turn, yaw sign). Estimate 3-6
days; vendoring is half a day but adds Node and .NET to a Python repo. Known data defects to carry
over: WMO placements with pitch/roll are skipped; some `WMOMinimapTexture` rows are stale (Forever's
rebuilt Orgrimmar).

**Shipping:** the continent tile table (~92 KB) is in `BubbleMap`, since the minimap padding
needs it whenever the addon runs. The WMO tables (2.6 MB) live in a load-on-demand addon,
`BubbleMap_Terrain` (`LoadOnDemand: 1`), loaded by `C_AddOns.LoadAddOn` the first time a city or
dungeon is drawn. Packaging: [questmarker-map.md](questmarker-map.md#packaging).

## Terrain core (`BubbleMap/Terrain.lua`)

Shared by both views; knows nothing about frames it draws into.

- **Coordinates:** uiMap position -> world yards (`C_Map.GetWorldPosFromMapPos`, `GetMapWorldSize`)
  -> tile column/row + fraction. All `C_Map` calls used are `AllowedWhenUntainted` and may return nil
  (`MapDocumentation.lua`); a nil skips the frame.
- **Tile pool:** a fixed grid of textures; tile (c, r) always lives in slot (c % w, r % h). Crossing a
  tile edge re-textures only the entering row or column; `SetTexture` is skipped when the slot already
  holds that fileID. Panning is one `SetPoint` on the grid's anchor.
- **Warm ring and parking:** the needed set is the visible tiles plus a ring of 1 (minimap) or the
  neighbouring zones' tiles (world map). Tiles that leave the needed set are parked: hidden, image kept,
  in an LRU of up to 96. A tile coming back is shown instantly with no load. Async load blanks (a tile
  empty for a frame) are suspected but unconfirmed; the warm ring exists to hide them either way.
- **Work only on change:** the needed set is recomputed when the view crosses a tile edge, changes
  zoom or changes map; never per frame.
- **Missing tiles** (open sea) draw over an opaque backdrop. A `SetTexture` that returns false is
  counted and reported by `/qm terrain`.

## World map toggle (`BubbleMap/WorldMap.lua`)

**Layering, touching nothing of Blizzard's.** Our own frame on `WorldMapFrame:GetCanvas()`
(`Blizzard_MapCanvas.lua:758`), mouse-disabled, `SetAllPoints`, with an opaque backdrop and the tiles.
Blizzard's base art draws at the canvas's own level (`Blizzard_MapCanvas.xml:7`); pins get one level
each from 2000 upward (`MapCanvas_PinFrameLevelsManager.lua:3, 65-74`), and explored-area art is a pin
type (`PIN_FRAME_LEVEL_MAP_EXPLORATION`, `Blizzard_WorldMap.lua:261`). So the frame's level is read, not
claimed: `pinFrameLevelsManager:GetFrameLevelStart("PIN_FRAME_LEVEL_MAP_EXPLORATION") + 1` (2003), which
puts it above the art and the explored overlays and below every other pin, and below BubbleQuest's
quest areas at 2004 (`BubbleQuestAPI.FrameLevels()`). No room to spare: re-check if either side moves. Reading the manager's table is safe;
inserting a level into it would write Blizzard data, so we don't. TerrainWorldMap instead hides
Blizzard's detail layers and exploration pins and replaces the map's `OnMouseWheel` with `SetScript`;
none of that is needed here.

- **Zoom and pan** cost nothing: the canvas child scales our frame.
- **Redraw** on post-hooks only: `hooksecurefunc(WorldMapFrame, "OnMapChanged")`, `HookScript("OnShow")`,
  and canvas size change. Same own-frame pattern as `UI/MapAreas.lua`.
- **Which maps:** zone maps and the six capitals (uiMaps 1453-1458, with their WMO city tiles). Continent
  and world maps keep Blizzard's art: a whole continent at tile detail is ~1,700 textures for a view
  where the art is the better picture.
- **Dungeon maps:** phase 2 of this feature. TerrainWorldMap draws dungeons only in its own window, never
  aligned to Blizzard's dungeon uiMaps; aligning them is new work (UiMapAssignment boxes per floor).
- **Toggle:** our own button parented to `WorldMapFrame`, anchored to `GetCanvasContainer()` TOPRIGHT
  below Blizzard's button stack (they stack from -2 in -32 steps, `Blizzard_WorldMap.lua:310-322`;
  count which of `WorldMapTrackingOptionsButton`/`WorldMapTrackingPinButton` exist). No library: Krowi's
  moves Blizzard's buttons with `SetPoint`. Not `AddOverlayFrame`: that puts our frame into Blizzard's
  secure refresh loop. State saved per account; also `/qm terrain`.
- **Gamepad UI mode:** off. Blizzard's secure gamepad code scans every frame in `WorldMapFrame`, so addon
  frames there taint it (`docs/research/forever-api-and-questiedb.md:299`). Detect with
  `C_InputInterfaceStyle.GetCurrentStyle()` as TomTom does; hide the button and the layer.
- **City WMO groups:** textures on one frame with draw sublevels bucketed by z, not a frame per group
  (828 frames in TWM). `SetTexCoord` 8-arg flip + `SetRotation(-yaw)`.

## Minimap padding, zoom and our map window

Designed in [questmarker-map.md](questmarker-map.md): the terrain fills the minimap's frame around
Blizzard's square at its exact scale, takes over past Blizzard's zoom range in both directions, and is
the base of our own deep-zoom map window. Ring of 1 tile warm around the minimap view.

**Rotating minimap: in scope** (decided in review 2026-11-17). With "Rotate Minimap" on, Blizzard
draws a square ground image and rotates it, so at diagonal headings its corners fall short of our
square frame (seen in game). With rotation on, we turn Blizzard's ground off
(`C_Minimap.SetDrawGroundTextures(false)`) and draw it all ourselves: every tile turned with the
player's facing (`Texture:SetRotation` around the view centre, positions rotated the same way),
updated as facing changes. Blizzard still draws the blips. Neither reference addon supports this; it's
our own work, after the north-up padding.

## Out of scope

- **Open-world indoors** (caves, buildings outside cities). Same data system as cities, but needs new
  runtime work with no API support: know the player is indoors, find which WMO group they're in
  (point-in-box), pick the level from `UnitPosition` z, and several MB more data. Revisit after cities.

## Settle in game

1. `SetTexture(fileID)` with a missing BLP: does it return false, or draw a green placeholder?
2. Async blanks: does a newly textured tile show empty for a frame?
3. The exploration-pin level on Forever, and that our frame really sits over the explored overlays.
4. `GetPlayerMapPosition`/`UnitPosition` inside Forever instances and in combat (dungeons, minimap padding).
5. `LoadAddOn` of the data addon while in combat: hitch or refusal? If either, defer to
   `PLAYER_REGEN_ENABLED`.
6. Cost of a capital's WMO groups on the canvas.
