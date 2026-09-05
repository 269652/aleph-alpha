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

1. **Worn, not placed.** Nothing here is authored by hand or spawned by a
   scripted event. A path exists because feet crossed that ground often
   enough, and it fades the same way — through disuse, not a despawn timer.
   This is the same "real mechanism, not scripted spawn" pillar
   [ecosystem_dynamics.md](ecosystem_dynamics.md) states for fruiting and
   population — applied to the ground itself instead of the biology on it.
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
  the way to a trail reads as MORE deliberately worn, not less.
- **Road** — the heaviest, most sustained tier — likely tied to settlement
  proximity and repeated inter-settlement travel once that exists. Not yet
  built.

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
- ⬜ Road tier (a higher wear threshold above Trail, its own rendering) —
  the Trail tier's own ceiling IS `PathScarring.MAX_WEAR`, so a Road tier
  needs the wear model's own ceiling raised first, not just a new threshold
  picked below an unreachable one.
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
