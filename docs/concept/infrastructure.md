# Infrastructure

Movement leaves a mark, and enough of it becomes the world's own
infrastructure — not placed by a designer, not spawned by a quest, but worn
into existence by whoever actually walked there. This is the emergent half
of [transportation.md](transportation.md): that doc covers the tools a
player carries (boats, mounts, fast travel); this one covers what the
*land itself* accumulates from repeated traffic — paths, trails, roads, and
eventually the crossings and hubs that grow up around them — per
`docs/emergence/04-settlements-cities-infrastructure.md` "Infrastructure":
"Repeated movement upgrades path → trail → road. Repeated crossings can
produce ford → ferry → bridge. Trade can produce rest stop → inn → market
→ settlement."

## Design pillars

1. **Worn, not placed — for paths and trails.** Nothing in the worn tiers
   is authored by hand or spawned by a scripted event. A path exists
   because feet crossed that ground often enough, and it fades the same
   way — through disuse, not a despawn timer. This is the same "real
   mechanism, not scripted spawn" pillar
   [ecosystem_dynamics.md](ecosystem_dynamics.md) states for fruiting and
   population — applied to the ground itself instead of the biology on it.
   The one deliberate exception is the **Road** tier (2026-09-16): a road
   is *laid* — by a settlement, as its streets and plaza
   ([building.md](building.md) pillar 5, `VillageLayout`) — not worn,
   because no amount of walking turns dirt into cobbles; that is work a
   community does. Still not authored by a designer: which village lays
   which street where is decided by the same seeded, algorithmic layout
   that sites its houses.
2. **Real-world grounding: desire paths.** A "desire path" is the actual
   term ecologists and urban planners use for exactly this — a trail worn
   by repeated foot traffic taking the route people actually walk rather
   than the one a planner intended. It forms from use, widens with more
   use, and grows back over with disuse. The tiers below (path → trail →
   road) are that same real process at increasing intensity, not an
   invented game mechanic.
3. **Causally grounded, not just visually rendered.** A worn path is not
   only a texture change — it is a real entity in the emergence substrate
   (`docs/emergence/00-emergence-architecture.md`), inspectable with
   `/history path:<x>_<y>`, so "why does this dirt path exist" has a real,
   traceable answer (repeated real foot traffic) rather than being pure set
   dressing.
4. **Grow from what already exists.** The wearing/recovery mechanism itself
   (`PathScarring`) already exists and already runs live, every session, from
   ordinary player movement — this doc and the substrate work built against
   it extend that real mechanism rather than inventing a parallel one.

## Tiers: path → trail → road

Three tiers of the same underlying wear, increasing with cumulative use and
decreasing with disuse — a real escalation, not three unrelated systems:

- **Path** — the first tier. Grass wears through to bare earth. This is
  what `PathScarring` already models today: per-tile wear accumulates from
  footsteps, decays over time, and crossing a threshold re-textures the
  tile as trampled ground (reusing the build system's earth-tile
  modification, the same rendering a player-dug patch of dirt already
  uses — a worn path and a dug patch are visually "the ground got turned
  to dirt" either way, an accepted overlap).
- **Trail** — sustained, heavier use of an already-worn path, walked all the
  way to `PathScarring`'s own wear ceiling (`TRAIL_THRESHOLD`, deliberately
  the SAME number as `MAX_WEAR` rather than a newly-invented one — the
  ceiling this module already enforced always named exactly this state, it
  just had nothing rendering it). Reported live: "path scarring only is
  computed once and walking back and forth doesn't deepen it" — the wear
  number itself was never the bug (`wear_at` already climbed to `MAX_WEAR`
  on repeated crossings), only legibility was missing: a path re-textured
  once at `WORN_THRESHOLD` and nothing further was ever visible, however
  much more it was walked. Rendered as its own flat, hard-edged, darker
  atlas tile (`TerrainRenderer.TRAIL_TILE_ID`) — deliberately NOT border-
  blended the way the Path tier's earth tile is; "man-made, flat-edged,
  never organically blended into the ground" is this codebase's own
  existing rule for every other modification tile, and ground walked all
  the way to a trail reads as MORE deliberately worn, not less. (One later
  exception, and it is not really one: a building's own footprint cells
  stopped being a modification tile at all in 2026-09-20 — they resolve to
  the GROUND that building stands on, this Road tier included, see
  [building.md](building.md)'s "The ground a building stands on, and the
  kerb round its plot".)
- **Road** — the built tier, and the one that is *laid* rather than worn
  (see pillar 1's exception). A settlement lays its streets and plaza as
  `TerrainRenderer.ROAD_TILE_ID` at founding (`VillageLayout` →
  `VillageRenderer`), and older saves' trail-drawn streets are repaved on
  their next load (`EarthChunkManager._migrate_village_trails_to_roads`).
  A road is a real built surface, exactly like a house's footprint: nothing
  grows on it (grass, flowers, scrub, lichen are blocked; trees and stones
  never spawn or root on it; laying a street fells a tree standing in it),
  it never wears — `World._step_path_scarring` takes no wear on a paved
  cell and never repaints or reclaims one, so the worn tiers can never
  overwrite a street — and it walks a little faster:
  `Player.ROAD_SPEED_MULTIPLIER` (1.15, test-pinned) multiplies into the
  same per-frame speed chain water, weather, slope and condition already
  do. It also **takes no footprints**, and not because anything asks
  whether a road should have them: setts are granite, whose published indentation hardness is some
  140 000x the pressure a foot can put on the ground, so the same real
  comparison that lets soil and snow keep a print refuses one here (see
  `GroundImprint` and [snow_cover.md's "Ground that is too hard to take a
  print"](snow_cover.md#ground-that-is-too-hard-to-take-a-print-2026-09-17)).
  Snow lying on a street is snow underfoot, so a snowed-over street shows
  tracks again. Art: ONE seamless full-bleed tile, `assets/sprites/terrain/road.png`,
  `TerrainRenderer.ART_TILE_SIZE` square (32 px), no dividers, no
  directional variants (a flat cobble surface that tiles in every
  direction — corners and crossings would need paint-time neighbour
  resolution, a later pass); until it exists, `TerrainRenderer.
  road_tile_image` draws a procedural cobble placeholder, and dropping the
  PNG in lights it up on the next atlas rebuild (bump `ATLAS_VERSION`).
  Between-village roads and the worn-route heatmap that would justify
  them are still the open items below.

Each tier crossing (and the reverse — reclaimed by disuse) is a real,
`/why`-inspectable event once emergence-substrate wiring reaches it (see
Status for exactly how far that wiring currently goes).

## Crossings: ford → ferry → bridge

Repeated crossings of water upgrade the same way paths do — a shallow,
frequently-forded river spot becomes worth a ferry, then eventually a real
bridge. This needs a real notion of "a crossing point," which the game does
not track yet (today, crossing water is boats/swimming per
[transportation.md](transportation.md), with no notion of a *place* where
crossings repeatedly happen). Entirely unbuilt; a later slice. Real rivers
now exist to actually ford ([rivers.md](rivers.md)) — this doc's own gap is
unchanged by that: there's real water to cross, still nothing tracking
where a crossing happens.

## Traffic heatmaps, market nodes, and trade impact

The full vision (`docs/emergence/07-implementation-roadmap.md` Phase 8):
"Implement traffic heatmaps, routes, roads, bridges, ferries, market nodes,
condition, and maintenance. Repeated movement creates infrastructure;
broken infrastructure changes trade." A traffic heatmap is the natural
aggregate of the same per-tile wear data already being tracked; routes
between settlements, market nodes at trade hubs, and infrastructure
condition feeding back into Phase 5's real market prices are all real,
intended extensions once there is more than one real settlement's worth of
inter-settlement movement to aggregate over. Unbuilt; later slices. See
[trade.md](trade.md) for the compiled spec of exactly this: real
inter-settlement caravans, driven by real price differentials, wearing
these routes in as a byproduct of trips actually taken — not yet
implemented either, but the two are designed to land together.

## Status

- ✅ **Path wearing/recovery mechanism** (`PathScarring`) — pre-existing,
  player-only, real per-tile wear with decay, rendered as earth tiles.
- ✅ **Path formation/reclamation is a real, causally-grounded event** — see
  `docs/progress.md`'s Emergence Phase 8 entry for exactly what's wired.
- ✅ **The Trail tier** (2026-09-05) — `PathScarring.is_trail`/`trail_tiles`,
  `TerrainRenderer.TRAIL_TILE_ID`, `EarthChunkManager.
  record_trail_formed_if_new`/`record_trail_reclaimed` (the same real
  `path:<x>_<y>` entity deepening, not a new kind of thing — `path_reclaimed`
  now recognizes a decay straight from Trail past Path to bare ground in one
  gap as a real reclaim too). `World._step_path_scarring` paints/tapers it
  right alongside the existing Path loop.
- ✅ **Real individual footprint stamps on grass/forest, not just the tile
  wear/dirt-swap above** (2026-09-07) — reported live: "proper
  pathscarring for grass and forest tiles", asked alongside the same
  request for real snow footprints. `PathScarring`'s own tile-level wear/
  dirt-swap/Trail mechanism above is completely UNCHANGED; a new, purely
  additive visual layer (`FootstepGait`/`FootprintField`/
  `FootprintRenderer`, shared with snow) now also stamps real, individually
  -placed, alternating left/right prints as the player actually walks —
  see [snow_cover.md's "Real left/right footprint
  stamps"](snow_cover.md#real-leftright-footprint-stamps-2026-09-07) for
  the full mechanism, since one field/renderer pair serves grass, forest,
  and snow alike, distinguished only by which surface each print was
  stamped on.
- ✅ **The Road tier, as a LAID surface** (2026-09-16) — `TerrainRenderer.
  ROAD_TILE_ID`/`is_road_tile`/`road_tile_image` (its own atlas slot,
  procedural cobble placeholder until `assets/sprites/terrain/road.png`
  lands), laid by `VillageRenderer` for every `VillageLayout` street cell;
  built-surface semantics shared with house footprints
  (`EarthChunkManager._is_built_surface`, `_can_root_at`, `TreeRenderer`/
  `StoneRenderer` spawn skips); never worn (`World._is_paved` guards every
  tile-writing branch of `_step_path_scarring`); `Player.
  ROAD_SPEED_MULTIPLIER`; older saves' trail streets repaved on load. The
  earlier note here — "needs the wear model's ceiling raised first" —
  was the worn reading of "road"; that reading is retired: a road is not
  a wear tier at all. Tested in `test_terrain_renderer.gd`,
  `test_earth_chunk_manager_buildings.gd`, `test_tree_renderer.gd`,
  `test_stone_renderer.gd`, `test_world_path_scarring_trail_wiring.gd`,
  `test_player.gd`, `test_village_renderer.gd`,
  `test_earth_chunk_manager_village_migration.gd`.
- ✅ **The road spur to a village's outlying works** (2026-09-16, see
  [village_growth.md](village_growth.md)) — the first laid road that is not
  part of the street grid itself. `VillageLayout.industry_plot` routes an L
  from the sawmill's doorstep, along its own row to a column and up that
  column, back to the main street, around the building's own footprint when
  the works stand south of the street; a site whose spur cannot be laid is
  refused outright, so the village never ends up with works it cannot walk
  to. Same `ROAD_TILE_ID` and the same built-surface semantics as the
  streets above — this is a real road, not a worn track. Connectivity is
  verified by a flood fill over really-paved cells, in both
  `test_village_layout.gd` and `test_village_renderer.gd`.
- ✅ **A street keeps no footprints** (2026-09-17) — reported live:
  "walking over cobblestone streets should not leave footprints".
  `GroundImprint` (`src/world/ground_imprint.gd`) decides it by real
  indentation physics rather than a tile-id exemption: a footfall's own
  pressure (real mass over a real plantar area) against the material's own
  published Vickers hardness, read straight off
  `MaterialProperties.HARDNESS_HV`. Granite setts win that by five orders
  of magnitude; built floors fall out of the same rule for free via
  `BuildingPiece`'s own material column; dug earth and a worn trail stay
  the soil they were worn out of. Gated in
  `EarthChunkManager.record_footstep` at the tile the print lands in.
  16/16 in `test_ground_imprint.gd`, 29/29 in
  `test_earth_chunk_manager_footprints.gd`. See [snow_cover.md's "Ground
  that is too hard to take a
  print"](snow_cover.md#ground-that-is-too-hard-to-take-a-print-2026-09-17).
- ✅ **A street sounds like stone, not like the grass beside it**
  (2026-09-17) — the sibling gap the footprint pass above named and
  left open. `record_footstep` resolves `GroundImprint.material_underfoot`
  once per step and carries it out as a `ground_material` fact, which
  `FootstepSound.surface_for` maps (`stone` → `"rock"`, `wood`/`timber`
  → `"wood"`); `"soil"` stays deliberately unmapped so untouched ground
  still takes its sound from the biome. One resolution serving both the
  print and the sound, so the two cannot disagree about what is
  underfoot. Honest limit: no distinct stone recording has been sourced,
  so `"rock"` still resolves to the generic step clip — the win is that
  a street stops sounding like grass, not that it sounds like cobbles.
  See [creature_and_footstep_audio.md's "A laid surface sounds like what
  it is laid with"](creature_and_footstep_audio.md#a-laid-surface-sounds-like-what-it-is-laid-with-2026-09-17).
- ⬜ A real footstep recording for stone and for a wooden floor — both
  currently share `default.ogg`, the same honest gap already standing for
  sand and rock (see that doc's `_CLIP_BY_SURFACE`).
- ⬜ Between-village roads (routing a street on to the next settlement).
  The plaza and side streets a laid-out village frames its road with are
  real — see [building.md](building.md) for the layout side.
- ⬜ Crossings (ford/ferry/bridge) — no "crossing point" concept exists yet.
- ⬜ Traffic heatmaps, inter-settlement routes, market nodes.
- ⬜ Infrastructure condition/maintenance/degradation feeding back into
  trade (Phase 5's real market prices).
- ⬜ Creature-driven wear — `PathScarring` is player-only today, the same
  documented scope limit `PebbleDispersion` has, for the same reason (an
  O(creatures × nearby tiles) scan every frame with nothing yet that needs
  it enough to justify the cost).

## Open questions

- Once trail/road tiers exist, do NPCs preferentially path along worn
  routes (faster/safer travel), the way a real desire path attracts more
  of the traffic that formed it?
- Does a road's existence factor into settlement/city siting
  (`docs/emergence/04`'s formation list already includes "roads" as a
  settlement-candidate factor) once Phase 9 (towns & cities) exists?
