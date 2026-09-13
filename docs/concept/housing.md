## Housing & decoration

[building.md](building.md) covers functional tile placement/destruction;
this layers an Animal Crossing-style expressive/social dimension on top.

### Interior furniture — a real mechanism, not just a bullet point

Requested directly ("houses need interior möbel") once
[workforce.md](workforce.md) gave the player a real way to build a house at
all — an empty shell was never going to be the whole feature.

**A NEW layer, for the exact reason roofs already needed one.**
`Chunk.roof_modifications`'s own doc comment already states the rule this
inherits verbatim: *"a roof sits ABOVE the room it covers, sharing its cell
with the floor piece below... `modifications` can only ever hold one tile
id per cell, so [it] needs a separate Dictionary to coexist with the floor
underneath it."* A table sits on top of a floor exactly the same way a roof
sits on top of a room — so furniture gets its own `Chunk.furniture_
modifications` (`Vector2i` local cell -> furniture piece id), painted on
its own `TileMapLayer` (mirroring `TerrainRenderer.paint_roofs`), never
merged into `modifications` or `roof_modifications`. This is real,
precedented plumbing, not a new pattern invented for furniture's sake.

**A furniture piece is a NEW `ItemCatalog` kind, `"furniture"`** — a
sibling to `"placeable"` (campfire, sagewerk, ...), not the same kind,
because placement rules genuinely differ (see below): a placeable can go
almost anywhere buildable; furniture can only go on real interior floor.
First real items: `wooden_table`, `wooden_chair`, `wooden_bed`, `rug`,
`bookshelf` — plain, single-cell, wood-costed like every other wood-tier
piece (`BuildingPiece.cost_of`'s own convention), no new material tier
invented for them.

**Placement rule: real interior floor, nothing invented.** A furniture
piece may only be placed on a cell that is (1) `RoomDetector.is_indoors`
true against the structure's real ground `modifications` grid — the SAME
enclosure check a house's own shelter effects already use, not a second
"is this a house" heuristic — and (2) a real `BuildingPiece.CATEGORY_FLOOR`
piece at that cell in `modifications` (you furnish a floor, not a wall or
a bare exterior cell), and (3) unoccupied in `furniture_modifications`
itself (one furniture piece per cell, the same "one thing per layer"
rule every other modification dict already enforces). Pure logic over the
two grids, the same `FurniturePlacement.can_place(cell, ground_grid,
furniture_grid)` shape `BuildingPlacement.can_place` already establishes
for the ground layer — so a village-generated house and a player-built one
share the identical furnishing rule, the same way they already share
`BuildingPlacement`.

**Appeal score: honestly minimal for now, not a fabricated formula.**
`housing.md`'s own Open Questions below already admit the real formula
(variety, symmetry, theme matching) is unresolved — inventing one now
would be exactly the kind of number-with-nothing-behind-it this project's
own conventions refuse elsewhere. The real, tested starting point is
`appeal_score(furniture_ids) := furniture_ids.size()` — a real count of
real placed pieces, monotonic and honest about being a placeholder, not a
weighted formula dressed up to look more finished than it is. Widening it
to variety/arrangement/theme is this doc's own named follow-up (Open
Questions), not silently pre-empted here.

- **NPCs react to and visit homes.** A high-appeal home draws visits from
  nearby NPCs (per [npc.md](npc.md)'s daily-planner architecture — a visit
  can simply be a plan entry an NPC's schedule includes) and NPCs form real
  opinions about it that feed their relationship/memory state, the same
  log-and-recall system that already lets them remember quests or combat.
  This gives base-building a second payoff beyond utility: your home is
  something the world's actual inhabitants notice and respond to, not just
  a private storage box.
- Once [multiplayer](../roadmap.md) lands, this extends naturally to other
  players visiting/rating each other's homes.

### Night lighting (ambient)

A small atmosphere layer, independent of the appeal/decor system above:
settlement houses (`village_renderer.gd`) light their real stamped
[window](building.md#pieces) pieces at night, driven by the same real sun
elevation the rest of the world's day/night lighting already reads (see
`solar_position.gd`'s `elevation_degrees`, and `scenes/world.gd`'s own
day/night tint) — not a second, one-off clock. A house with no windows in
its blueprint stays dark; a house mid-construction only lights the windows
it has actually built so far, never ones still unbuilt. Chunk-scoped like
every other renderer here: a village's lit/unlit state is decided once, at
the moment its chunk streams in, and holds until the chunk unloads and
reloads — the same "regenerates on revisit, no mid-visit re-evaluation"
simplification trees/creatures already accept.

### Status

- ✅ Night lighting (ambient), above.
- ⬜ `Chunk.furniture_modifications` + its own `TileMapLayer`/paint pass
- ⬜ `ItemCatalog` furniture-kind items (wooden_table, wooden_chair,
  wooden_bed, rug, bookshelf)
- ⬜ `FurniturePlacement.can_place` (interior-floor rule)
- ⬜ Placing/removing furniture in the world (the player-facing verb,
  mirroring `build_at_global`/`destroy_at_global`)
- ⬜ `appeal_score` (the honest placeholder above)
- ⬜ NPC visits / opinions from a home's appeal
- ⬜ Multiplayer visiting/rating

### Open questions

- Appeal-score formula — what actually counts (variety, symmetry, theme
  matching, rarity of decor items) and how legible should the scoring be to
  the player (fully transparent numbers vs. Stardew's opaque
  quality-heuristic feel)?
- Does a decorated home unlock anything mechanical (better sleep-quality
  bonus feeding [survival.md](survival.md), NPC willingness to be
  [hired](npc.md#hiring--instruction)), or stay a purely social/cosmetic
  system?
