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

### Occupation-themed decor

Resolves this doc's own "theme matching" Open Question, for the one real
per-NPC signal this codebase already models: occupation identity.
`HouseDecor.furniture_set_for(occupation)` gives each of `NpcIdentity`'s 8
real occupations (farmer/blacksmith/merchant/guard/fisher/herbalist/hunter/
nurse) a distinct set drawn from the same shared furniture pool — every
occupation, not a couple of signature pieces, per an explicit scope
decision. Two more pieces (`couch`, `photo_frame`) joined the original
five so there was enough real variety to make 8 sets genuinely distinct.

Deliberately NOT wealth-tiered: `village_wages.gd`'s own file doc comment
establishes this game's economy as deliberately neutral between producer
and non-producer occupations, so a richer/poorer furniture tier per
occupation would contradict a design decision already made elsewhere.
Each set is instead reasoned from two real signals this codebase already
tracks — `NpcIdentity.WORK_LOCATION_BY_OCCUPATION` (where they work) and
`OccupationProduction`'s own recipe table (what they make) — not invented
lore: a merchant (stall, customers) and a nurse (well, patients) are the
two occupations whose real work routinely brings other people to them, so
they get the couch, the one piece meant for a visitor to sit on; a
herbalist's own recipe (`butterfly_net`, a specimen-collecting trade) gets
it the bookshelf; a guard (gate, sleeps between shifts) gets the smallest,
barracks-plain set.

`EarthChunkManager.furnish_house_at_global` is the new world-write this
needed: called by `VillageRenderer._stamp_house` right after
`stamp_structure_at_global` writes a house's own floor/wall pieces (its
own real ordering requirement — `FurniturePlacement`'s `is_indoors` check
needs those pieces already on the chunk), furnished against the SAME
`stamped_pieces` dict just given to `stamp_structure_at_global`, never a
second floor-detection pass. Tries each id in the NPC's own set against
that house's real floor cells in order, skipping (not aborting on) any
cell `FurniturePlacement` itself refuses, so an odd-shaped or too-small
floor still gets partially furnished rather than emptied.

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
- ✅ `BuildingPiece.CATEGORY_FURNITURE` + seven real pieces (wood_chair/
  table/bookshelf/bed/rug, plus `couch`/`photo_frame` added for occupation
  theming below) and their matching `ItemCatalog` entries
- ✅ `FurniturePlacement.can_place`/`refusal_reason` (interior-floor rule,
  its own layer, tested against a real enclosed-room fixture)
- ✅ `Chunk.furniture_modifications` + its own `TileMapLayer`/paint pass
  (`EarthChunkManager.set_furniture_layer`/`_paint_furniture`, a new
  `Furniture` node in `world.tscn` mirroring `Roof`'s own shape) --
  persisted the same generic way `roof_modifications` already is, and
  rendered via the ALREADY-real shared atlas (`TerrainRenderer.
  atlas_coords_for_modification` already resolves any `BuildingPiece`,
  furniture included, since furniture pieces are real `PIECE_IDS` entries).
  **Now real GUT-tested** (`test_earth_chunk_manager.gd`'s furniture group,
  9 tests) — see the caveat below on what this does and does not close.
- ✅ Placing/removing furniture in the world: `EarthChunkManager.
  build_furniture_at_global`/`destroy_furniture_at_global`/
  `furniture_at_global`, gated by `FurniturePlacement` (real interior-floor
  rule). A real hotbar-armed in-world verb also exists: `HotbarAction.
  FURNISH` (`"furniture"` kind → its own `_selected_furniture_item` on
  `scenes/player.gd`, mirroring `"placeable"`'s own `_selected_placeable_
  item` exactly, mutually exclusive with it) makes `_build_step` furnish
  instead of placing/terraforming, and `_destroy_step` checks the
  furniture layer BEFORE the general modification layer (a table sitting
  on a floor destroys the table, not the floor under it). The `/furniture
  place|remove` dev-console command (`scenes/world.gd`) stays too, as a
  second, still-real way to reach the same world model.
- ✅ **Occupation-themed decor** (own section above): `HouseDecor.
  furniture_set_for(occupation)` + `EarthChunkManager.furnish_house_at_
  global`, wired into `VillageRenderer._stamp_house` — every generated
  settlement house now carries a real, occupation-linked furniture set,
  TDD red-first throughout (`test_house_decor.gd` 6/6, the new
  `furnish_house_at_global` group in `test_earth_chunk_manager.gd` 5/5,
  `test_village_renderer.gd`'s two new furnishing tests, full file 41/41).
- ⬜ `appeal_score` (the honest placeholder above) -- occupation-themed
  decor answers this doc's own "theme matching" question but not "variety/
  symmetry/rarity"; the formula itself is still unbuilt.
- ⬜ NPC visits / opinions from a home's appeal
- ⬜ Multiplayer visiting/rating

**Partial resolution of the previous caveat below**: the furniture layer/
paint pass and the place/remove verb were originally shipped directly per
a mid-session "skip tests" instruction, with no GUT pass at all. This
session added real coverage for the core world-model surface (build/
destroy/query verbs + `_paint_furniture` against a real chunk and
`TileMapLayer`, 9 tests) and for the new generation-time `furnish_house_
at_global` this pass itself introduces. **Still not covered**: `scenes/
player.gd`'s own `_selected_furniture_item` arm/build/destroy-ordering
behavior (`test_player.gd` has zero furniture references), and a real
save/unload/reload round trip through `FURNITURE_MODIFICATIONS_DIR` (the
generic `ChunkSerializer` mechanism it reuses is tested, but not exercised
end-to-end through a furniture-specific unload/reload). Both are real,
named gaps, not a silent claim of full coverage.

### Open questions

- Appeal-score formula — what actually counts (variety, symmetry, theme
  matching -- now answered by occupation-themed decor above -- rarity of
  decor items) and how legible should the scoring be to the player (fully
  transparent numbers vs. Stardew's opaque quality-heuristic feel)?
- Does a decorated home unlock anything mechanical (better sleep-quality
  bonus feeding [survival.md](survival.md), NPC willingness to be
  [hired](npc.md#hiring--instruction)), or stay a purely social/cosmetic
  system?
