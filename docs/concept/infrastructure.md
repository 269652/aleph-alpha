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
- **Trail** — sustained, heavier use of an already-worn path over a longer
  window. Not yet built: needs its own wear threshold and its own visual
  tier, deliberately deferred rather than guessed at now (see Status).
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
crossings repeatedly happen). Entirely unbuilt; a later slice.

## Traffic heatmaps, market nodes, and trade impact

The full vision (`docs/emergence/07-implementation-roadmap.md` Phase 8):
"Implement traffic heatmaps, routes, roads, bridges, ferries, market nodes,
condition, and maintenance. Repeated movement creates infrastructure;
broken infrastructure changes trade." A traffic heatmap is the natural
aggregate of the same per-tile wear data already being tracked; routes
between settlements, market nodes at trade hubs, and infrastructure
condition feeding back into Phase 5's real market prices are all real,
intended extensions once there is more than one real settlement's worth of
inter-settlement movement to aggregate over. Unbuilt; later slices.

## Status

- ✅ **Path wearing/recovery mechanism** (`PathScarring`) — pre-existing,
  player-only, real per-tile wear with decay, rendered as earth tiles.
- ✅ **Path formation/reclamation is a real, causally-grounded event** — see
  `docs/progress.md`'s Emergence Phase 8 entry for exactly what's wired.
- ⬜ Trail/road tiers (higher wear thresholds, their own rendering).
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
