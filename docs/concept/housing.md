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

### Two-story houses

Requested directly ("they should be sophisticated; 2 story high buildings")
once the blueprint system in [workforce.md](workforce.md) had real shapes to
grow beyond single-story small_house/cottage/manor. The player wanted a
REAL walkable upper floor with interior stairs and real windows visible
from outside — not a cosmetic second-story facade painted over a
single-height room.

**A NEW layer, for the exact reason roofs and furniture already needed
one.** The upper floor occupies the IDENTICAL (x, y) footprint as the
ground floor beneath it — this is a flat 2D top-down engine with no real
Z axis, so "upstairs" is drawn as a second tile layer sharing the ground
floor's own cells, exactly the same "own Dictionary because it coexists
with what's already at that cell" reasoning `roof_modifications` and
`furniture_modifications` both already establish. `Chunk.upper_floor_
modifications` (`Vector2i` local cell -> piece id) is the third such
layer, painted on its own `UpperFloor` `TileMapLayer` (registered through
`EarthChunkManager.set_upper_floor_layer`, the same optional fail-open
shape as `set_roof_layer`) — one that sits ABOVE the roof layer
(`EarthChunkManager.UPPER_FLOOR_LAYER_Z_INDEX`), the reverse of what a
naive "floors stack under the roof" order would suggest; see "How it
reads from above" below for why, and for the correction this paragraph's
own first version needed.

**No teleport, no scene change — a real shared-coordinate floor toggle.**
A single new `BuildingPiece`, `wood_stairs` (`CATEGORY_STAIRS`, walkable),
sits at the SAME cell on both the ground and upper layers. Stepping onto
it (`Player._floor_transition_step`, called every physics frame the same
way `_build_step`/`_destroy_step` already are) flips a player-side
`_current_floor` between 0 and 1 via `EarthChunkManager.step_on_stairs` —
the player's world position never changes, only which modification layer
they currently read/build against. Walking back onto the same stairs cell
flips it back. This is deliberately the simplest possible "upstairs"
primitive: one boolean per player, no new scene, no camera cut.

**How it reads from above — windows visible from outside is the real
"sophisticated" signal, not decoration.** This paragraph's first version
had the upper floor's walls and windows "render UNCONDITIONALLY" in
place, hidden only from a player standing upstairs inside it, on the
theory that real geometry drawn on top is what makes a lit window visible
two stories up. Reported directly once it went live: *"there are still no
2 story houses... also now most houses don't even have a door."* In a flat
top-down engine, an upper storey drawn in place over an identical
footprint with identical wall art is *indistinguishable* from a one-story
house — and its own front wall/window sits exactly over the ground
floor's door. The corrected contract follows [building.md](building.md)'s
"How a house reads from above" (its new point 5), decided per house by
where the player is (`EarthChunkManager._update_upper_floor_visibility`,
the upper-storey twin of `_update_roof_visibility` — it reuses that
function's own ground-room result each frame rather than running a second
`RoomDetector` pass, and uses the upper storey's own real room via
`_upper_floor_piece_grid_for` when the player is on floor 1):

- **Exterior** (not inside this house): only the upper storey's FACADE
  band is drawn — the same southernmost-per-column cells `HouseBlueprint.
  _facade_cells` gives the ground floor, read back off the chunk — each
  one row UP, over the roof's own front row. So the house reads as
  roof-above-facade-above-facade: the ground door and windows on the
  bottom band, the upper storey's windows on the band above, roof above
  that. Its interior, side and back cells are under the roof from
  outside exactly as the ground floor's own are, and are not drawn at all.
  That band is why the `UpperFloor` layer sits ABOVE the roof layer.
- **Inside, on the ground floor**: nothing of the upper storey is drawn —
  the band comes off with the roof, and the ground room is the view.
- **Inside, upstairs**: the whole upper storey is drawn in place, its
  furniture with it, and the player is lifted above the layer
  (`Player._floor_transition_step` flips `z_index` to `EarthChunkManager.
  UPPER_FLOOR_OCCUPANT_Z_INDEX` alongside `collision_mask`) so the very
  floor they stand on cannot paint over them — while villagers still
  downstairs are correctly hidden beneath it.

Night lighting follows the drawing: a two-story house's own upper
windows are lit one row up, where its facade band actually is, on their
own draw order above the upper-floor layer (`VillageRenderer.
UPPER_WINDOW_LIGHT_Z_INDEX`), and only the facade's windows — the upper
storey's side/back windows are under the roof from outside like the
ground floor's own. Real GUT coverage: `test_earth_chunk_manager_upper_
floor_exterior.gd` (9 tests: the three views, the door staying uncovered
— the reported regression itself — furniture only upstairs, leaving the
house, a neighbouring house keeping its exterior look, and the layer
z-order pinned as constants rather than eyeballed scene values), 3 new
`test_player.gd` tests for the z flip, and 3 new `test_village_renderer.
gd` tests for the shifted, facade-only upper lights.

**Ten real shapes, kept deliberately separate from the single-story
pool.** `HouseBlueprint.TWO_STORY_BLUEPRINT_IDS` — `townhouse_narrow`,
`merchant_house`, `guild_hall`, `riverside_villa`, `timber_longhouse`,
`artisan_workshop_house`, `tower_keep`, `harborside_manor`,
`grand_estate`, `gambrel_lodge` — is a SEPARATE array from `BLUEPRINT_
IDS`/`BLUEPRINT_POOL_BY_OCCUPATION`, so the procedural village
generator's NPC-owned houses stay single-story only; extending village
generation to build real second floors for NPCs is named, scoped-out
follow-up, not an oversight (see Open Questions). Each shape's upper
floor (`HouseBlueprint.build_upper_floor`) reuses the ground floor's own
wall-ring/window-placement logic with one extra window slot filled where
the ground floor's door would be (an upper floor has no door of its own
— you reach it by the stairs, not a second entrance) and places
`wood_stairs` at the shape's fixed `stairs` cell. All ten reuse the SAME
`carpentry_level` 3.0 ceiling `manor` already established — real variety
at the top tier the skill web can reach, not a fourth, harder gate (see
`workforce.md`'s own "Blueprint tiers"). Wood cost is ground-floor pieces
+ roof pieces (the same convention small_house/cottage/manor already
verify against their own shapes) plus the upper storey's own walls,
windows, floor, and stairs — ranging from `tower_keep`'s 129 wood (a
compact 5x5 keep) to `grand_estate`'s 303 (an 8x8 manor-and-a-half),
priced in `shop.gd` at the same ~2.68x wood-to-gold ratio manor/cottage
already share.

**Deliberate simplifications, named honestly rather than left silent:**

- **No real upper-floor wall collision in v1.** Reusing Godot's existing
  per-cell static-body collision system for a SECOND simultaneous
  collision layer at identical world coordinates (ground walls collide on
  floor 0, upper walls collide only on floor 1, at the same tile) was
  judged too large and too risky a physics-layer rework for this pass.
  The upper floor is real for visibility, room-detection, and
  placement/persistence purposes — a player can walk through its walls
  today. Real dual-floor collision is Open Questions below, not silently
  assumed solved.
- **`hire_builder_for_house`/`BuilderMarker` do not build second floors.**
  A hired builder still only raises the ground floor and roof, matching
  the existing precedent that `BuilderMarker` does not build roofs either
  (`workforce.md`'s own build-or-hire fork). Only the player's own
  `_try_build_house_from_blueprint` calls `build_upper_floor`. Extending
  the hire path to two-story shapes is scoped-out follow-up.
- **Roof geometry needed NO changes at all.** Since the upper floor
  shares the ground floor's exact footprint, `HouseBlueprint.
  build_roofs()`'s existing facade-derived roof stays exactly as it is —
  the roof DATA is unchanged and still covers every non-facade cell. What
  changed at paint time (see "How it reads from above" above) is that the
  upper storey's own facade band is drawn one row up over the roof's front
  row, so the roof appears one row shorter with a second wall band beneath
  it. The original claim that the unchanged roof "already correctly caps
  whichever floor is topmost" was the wrong half of this: it did, but with
  the upper storey then painted in place over it, nothing distinguished
  the two storeys from above. Still zero new roof code, not an accidental
  gap.

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
- ✅ Two-story houses, above: `BuildingPiece.CATEGORY_STAIRS`/`wood_stairs`;
  `HouseBlueprint.TWO_STORY_BLUEPRINT_IDS`/`is_two_story`/`build_upper_
  floor`; `Chunk.upper_floor_modifications` + its own `UpperFloor`
  `TileMapLayer`/paint pass; `EarthChunkManager.set_current_player_floor`/
  `_update_upper_floor_visibility`/`upper_floor_at_global`/
  `step_on_stairs`/`stamp_upper_floor_at_global`; `Player._current_floor`/
  `_floor_transition_step`; ten new blueprints, `ItemCatalog` entries,
  `shop.gd` prices, and `CraftingRecipeBook` recipes (all at the manor's
  own carpentry_level 3.0 ceiling)
- ✅ Real upper-floor wall collision: a SECOND real Godot physics layer
  (`EarthChunkManager.UPPER_FLOOR_COLLISION_LAYER`, bit 2 — ground stays on
  the default bit 1, untouched), so a wall/window solid on one floor never
  falsely blocks (or fails to block) the other at the same cell — the real
  case that matters is the ground floor's own door (walkable) sitting
  under the upper floor's own window (solid) in its place. `Player.
  collision_mask` flips between the two layers the instant `_current_
  floor` changes (`_floor_transition_step`) — a single property flip, not
  an iterate-and-toggle-every-body-in-the-world scheme. `build_upper_
  floor_at_global` is the new per-cell entry point (mirrors `build_at_
  global`), and `stamp_upper_floor_at_global` (renamed from a private
  helper, now public like `stamp_structure_at_global`) syncs collision for
  every cell of a bulk stamp too. Real GUT coverage: `test_earth_chunk_
  manager_upper_floor_collision.gd` (12 tests — spawn/remove/layer-
  identity/ground-vs-upper-at-the-same-cell/chunk unload+reload) and 4 new
  `test_player.gd` tests proving `collision_mask` itself actually flips on
  a real floor transition (the property nothing upstream of it matters
  without), plus the full pre-existing ground-floor collision suite in
  `test_earth_chunk_manager.gd` re-run and still green (10/10) to confirm
  zero regression. Deliberately NOT extended: real structural statics/
  decay/collapse for the upper floor (a materially separate system — see
  workforce.md's own
  BuildingStatics/BuildingDecay sections — left as ground-floor-only, a
  named, narrower gap than "no collision at all").
- ✅ `hire_builder_for_house`/`BuilderMarker` now build the real upper
  floor too, not just the ground floor + roof-less shell: `BuilderMarker.
  target_upper_pieces` (optional, `{}` by default so every pre-existing
  single-story hire is unaffected) is only ever attempted once every real
  ground piece is placed — the same real-world build order a house
  actually goes up in — via its own round-robin seek/withdraw/carry/place
  cycle mirroring the ground one exactly, checked against the UPPER
  floor's own real neighbors (`build_upper_floor_at_global`/`upper_floor_
  at_global`), never the ground floor's. The project's own real completion
  total (`ConstructionLabor.labor_hours_required_for_pieces`) now sums
  BOTH floors, so a two-story hire only reaches COMPLETE once the whole
  house — not just its ground floor — is real. Real GUT coverage: 4 new
  tests in `test_builder_marker.gd` (default-empty backward compatibility,
  upper pieces placed after the ground floor, an upper wall's own
  adjacency judged against the upper floor specifically — isolated by
  leaving the ground floor deliberately EMPTY so a bug reading the wrong
  grid would fail loudly — and full two-floor completion with the correct
  combined labor total). The pre-existing "a hired house gets no roof at
  all" gap this had before two-story houses existed is now closed too —
  see the roof entry below, added in the same follow-up pass.
- ✅ Procedural village NPC houses can be two-story: `HouseBlueprint.
  BLUEPRINT_POOL_BY_OCCUPATION`'s own merchant/blacksmith pools (the only
  two occupations that already reached for the showiest SINGLE-story
  options) now each carry a real two-story entry at both their PLAIN end
  and their SHOWY tail, chosen for thematic fit and for footprints
  comparable to the manor tier already there (25–49 tiles) rather than the
  largest shapes, which risk visibly overlapping a neighbor in
  `SettlementGenerator`'s own fixed ring layout — a named judgment call.
  Farmer/fisher/guard/herbalist stay single-story. `VillageRenderer.
  _stamp_house` stamps the real upper floor once `HouseBlueprint.
  is_two_story` reads true AND the ground floor itself is fully complete
  (the SAME gate the roof already uses), and appends the upper floor's own
  real windows to the SAME night-lighting list the ground floor's windows
  already feed — the original request's own "windows in second level"
  now genuinely lights up for NPC-owned houses too, not just the player's.
  Real GUT coverage: 4 new tests in `test_village_renderer.gd` (a real
  two-story choice stamps a real, non-empty upper floor; its windows
  extend the lighting list; a still-partially-built house gets no upper
  floor yet; a single-story choice never calls the upper-floor stamp at
  all) plus 4 new tests in `test_house_blueprint.gd` (merchant/blacksmith
  pools each contain a two-story id; the generic fallback and the four
  modest occupations still never do) — and the full pre-existing suites of
  both files re-run and still green (43/43, 35/35) to confirm zero
  regression from widening two long-lived pool constants.
  **Follow-up, reported directly as too rare to reliably find by
  exploring**: `BLUEPRINT_POOL_BY_OCCUPATION`'s merchant/blacksmith pools
  were RESHUFFLED to a real MAJORITY two-story weighting (blacksmith
  5/7 ≈ 71%, merchant 6/8 = 75%), each still opening with two real plain
  entries so even a cautious/stoic-dominant roll keeps a real chance.
  `test_a_merchant_or_blacksmith_villager_most_often_gets_a_two_story_
  house` in `test_house_blueprint.gd` measures this directly over 300 real
  seeds per occupation (both now > 50%), rather than trusting an eyeballed
  intent comment — the real, load-bearing lesson from this pass: a pool
  ratio the CODE claims to weight one way must be *measured*, not assumed,
  since `choose_blueprint_id`'s own index math depends on the pool's real
  size and repetition, not just which ids are present.

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

- ✅ `hire_builder_for_house`/`BuilderMarker` build the real roof too, for
  BOTH single- and two-story hires — the pre-existing "a hired house gets
  no roof at all" gap this had since long before two-story houses ever
  existed. New `EarthChunkManager.roof_at_global`/`build_roof_at_global`
  (the roof's own per-cell read/write pair, mirroring `modification_at_
  global`/`build_at_global` exactly — `chunk.roof_modifications` could
  previously only ever be written in BULK, fine for the player's instant
  self-build and the village generator, but nothing for a piece-by-piece
  worker to call). `BuilderMarker` now sequences THREE layers strictly in
  order — ground, then upper (if any), then roof — via a `_current_layer`
  discriminator (`"ground"`/`"upper"`/`"roof"`, replacing the two-story
  pass's own `_current_is_upper` boolean now that there are three states,
  not two) rather than accumulating boolean flags. The roof's own
  adjacency check reuses the GROUND grid snapshot even for a two-story
  hire — correct, not a shortcut, since every real two-story shape shares
  an identical floor/wall footprint between its two layers (no notches).
  `target_roof_pieces` defaults to `{}`, and the project's completion
  total now sums all three layers, so every pre-existing single-story,
  no-roof-tracking hire is unaffected. Real GUT coverage: `test_earth_
  chunk_manager_roof_pieces.gd` (7 tests) + 4 new `test_builder_marker.gd`
  tests (single-story hire gets a roof; two-story hire gets ground→upper→
  roof in order; full three-layer completion with the correct combined
  labor total) + the full pre-existing `test_builder_marker.gd` suite
  re-run green (17/17) to confirm zero regression.

- ✅ Real terrain buildability (`docs/concept/building.md`), reported
  directly: *"houses / buildings cannot be built on river / water; also
  not in the forest... the NPCs / Player must first fell all trees to
  make space for the building."* Before this, `can_build_house_from_
  blueprint` checked only that a cell had no existing MODIFICATION —
  water, forest, and standing trees were never checked at all, and
  `BuilderMarker`'s own `_buildable_ground` was a named, honest permissive
  stand-in. New `EarthChunkManager.tree_at_global` (does a real,
  currently-standing tree occupy this tile — mirrors `_clear_vegetation_
  on_cells`' own tree-to-tile reverse lookup) and `is_buildable_terrain_at`
  (a thin aggregator: not ocean or forest biome, not a river, not a lake,
  no standing tree) are the one real answer all three build paths now
  share: `can_build_house_from_blueprint` (the player's own instant
  self-build), `BuilderMarker._buildable_ground` (the hired path, real
  now instead of `return true`), and `VillageRenderer._find_dry_origin`
  (since replaced by `_fit_house`/`_find_clear_origin`, see the livable-
  houses entry below; renamed in spirit from water-only to real terrain
  avoidance, preferring
  the real check via `has_method` duck-typing when `world` provides it,
  falling back to the original ocean-only `biome_at_global` check for an
  older test double that predates it). `SettlementGenerator.
  _UNINHABITABLE_BIOMES` gained `"forest"` alongside `"ocean"`/`"mountain"`
  — a real village would spend its whole existence fighting standing
  trees rather than ever finishing a house. "Fell trees to make space" is
  real for the PLAYER's own building (a tree refuses placement until
  chopped with the existing axe mechanic) and for a HIRED builder
  (identical refusal); the procedural village generator has no live
  "worker" concept to fell anything, so it achieves the same real outcome
  by SEARCHING for already-clear ground instead (the same mechanism it
  already used for water avoidance, now widened) — a deliberate, named
  difference in mechanism, not a gap in outcome. Real GUT coverage: `test_
  earth_chunk_manager_buildable_terrain.gd` (8 tests, each finding one
  real example of ocean/forest/river/lake/tree/plain-ground against the
  real Berlin fixture — no mocked terrain), a new `test_settlement_
  generator.gd` case (forest joins ocean/mountain), 3 new `test_village_
  renderer.gd` tests (the real check is preferred when available; a
  legacy `biome_at_global`-only double still works via the fallback; the
  real check refuses cells `biome_at_global` alone could never have
  caught), 1 new `test_builder_marker.gd` wiring test (a real standing
  tree refuses a hired placement), and the full pre-existing suites of
  `test_village_renderer.gd` (45/45), `test_settlement_generator.gd`
  (10/10), and `test_builder_marker.gd` (17/17, alongside the roof tests
  above) re-run green — this last one mattering most, since it proves
  Berlin's own real fixture tile (already used by dozens of pre-existing
  tests) is itself real, buildable ground under the new check, not an
  accidental regression waiting in every other test in that file.

- ✅ NPC-generated houses get real interior furniture, on BOTH floors —
  reported directly alongside two-story houses themselves ("no room
  decoration"), then corrected directly to cover the upper floor too ("no
  do both floors") after this pass first scoped it to the ground floor
  alone. **Reconciled with a concurrent session's own independent work**:
  this pass originally built its own flat, non-thematic bulk-furnish pair
  for both floors; while merging into `main`, that turned out to collide
  with a concurrent session that had, in parallel, built a materially
  better ground-floor mechanism — real, occupation-linked furniture via a
  new `HouseDecor.furniture_set_for(occupation)` (see "Occupation-themed
  decor" above) — which this pass's own ground-floor call would otherwise
  have double-furnished on top of. Resolved by retiring this pass's own
  ground-floor mechanism entirely and keeping the other session's, then
  re-shaping this pass's upper-floor half to match its surviving sibling
  exactly: `EarthChunkManager.furnish_upper_floor_at_global(chunk_coord,
  origin_tile, upper_pieces, furniture_ids)` is `furnish_house_at_global`'s
  own list-driven walk/skip/count contract, one layer up — it walks the
  upper floor's own real floor cells in order, tries each `furniture_ids`
  entry against successive cells via the real `FurniturePlacement.
  can_place`, skips on refusal, and repaints once. `VillageRenderer.
  _stamp_house` calls it with the exact SAME `HouseDecor.furniture_set_
  for(npc.occupation)` list the ground floor was just furnished with, so
  a two-story merchant's upstairs bed/rug is just as occupation-themed as
  their couch downstairs, not a separate, cruder list — an improvement
  over this pass's own original flat priority list, not just a dedup. The
  upper floor still needed a genuinely new layer — `Chunk.upper_floor_
  furniture_modifications`, its own `UpperFloorFurniture` `TileMapLayer`
  — rather than reusing `furniture_modifications`, because a table on the
  ground floor and a bed on the upper floor can legitimately share the
  exact same (x, y): one Dictionary can only ever hold one piece per
  cell, the same reasoning every other ground/upper pair in this doc
  already follows. Its visibility rule is deliberately the OPPOSITE of
  ground furniture's: ground furniture is never hidden by anything
  (nothing occludes the ground layer's own room from a bird's-eye view —
  only the ROOF, a separate layer above, conditionally hides), while the
  upper storey's furniture is only ever drawn in place while the player is
  actually standing upstairs in that room — from outside it is under the
  roof, and from the ground floor it is a storey above the room being
  looked at (see "How it reads from above"; this bullet's first version
  had it the other way round, hiding while occupied and showing from
  outside, which the same live report corrected). Both calls are gated on
  the SAME "ground floor fully
  complete" condition the roof/upper-floor already use, and both are
  duck-typed via `has_method` exactly like `stamp_structure_at_global`/
  `stamp_upper_floor_at_global` already are. Real GUT coverage — ground
  floor: the other session's own, already described above under
  "Occupation-themed decor". Upper floor, rewritten to match the
  reconciled interface: 3 `test_village_renderer.gd` tests (a two-story
  house furnishes its upper floor too, with `HouseDecor`'s own real set;
  a single-story house never calls the upper-floor furnish at all; a
  still-partial two-story house gets no upper furniture yet) and a fully
  rewritten `test_earth_chunk_manager_furniture_bulk.gd` (5 tests: a real
  piece placed onto the real upper grid; refusal of a cell with no real
  upper-floor piece backing it; the two floors' furniture proven
  independent at the identical cell; and the drawn-only-while-upstairs
  rule proven both ways — drawn once the player is up there, gone again
  once they leave). **Named honestly, then closed**: this reconciliation —
  retiring this pass's own ground-floor mechanism, reshaping its upper-
  floor half, and rewriting the two test files above — was done by hand
  while merging into `main` under a "skip tests" instruction, with no GUT
  run at the time. The owed run happened in the follow-up pass right
  after ("How it reads from above"), and it found exactly one real
  problem: the rewritten coexistence test furnished the ground floor
  against a bare, wall-less floor cell, which `furnish_house_at_global`
  correctly refuses (the same enclosed-room fixture lesson this pass had
  already learned once, on the upper side). Fixed in the test, not the
  code; the file is green (5/5) since. Still NOT extended: the player's own hand-furnishing
  verb (`HotbarAction.FURNISH`/`/furniture place`) still only reaches the
  ground floor's `furniture_modifications` — a player furnishing their
  OWN upper floor by hand is a real, separate, already-named Open
  Question below, not silently assumed solved by this NPC-generation-only
  pass.

- ✅ **A two-story house now READS as one from outside, and keeps its
  door** — the first live report after the whole batch above merged:
  *"There are still no 2 story houses and the houses are also still not
  furnished... also now most houses don't even have a door."* A real
  probe against four freshly generated villages showed every house had
  its door and its furniture on the ground layer and the two-story
  houses were real (74 upper cells in one village) — but 2 of that
  village's 5 doors were painted over by the upper storey at the same
  cell, and from above a second storey drawn in place with identical art
  is invisible as such. Not a data bug: the rendering contract itself was
  wrong, and is rewritten under "How it reads from above" above (upper
  storey as a second facade band one row up, over the roof; nothing of it
  downstairs; all of it, in place, only while actually upstairs), with
  [building.md](building.md)'s own "How a house reads from above" gaining
  the rule as its point 5. Chunk unload now also erases the furniture and
  upper-floor layers for the chunk (a pre-existing gap: only the roof/
  water/snow overlays were ever erased). All TDD red-first: the new
  exterior tests were run against the pre-fix code first (0/8, the door
  test failing for exactly the reported reason) before the fix landed.

- ✅ **Livable houses: furnished for real, dry, clear of the wood and
  grass, and enterable** — the next live report, with screenshots: *"The
  NPCs buildings still look poor and basic; not like sophisticated
  architecture also they are still not furnished also some are built so
  that you can't enter"* (a stone house with a pond INSIDE it), then
  *"they shouldn't be able to build anything on water tiles and trees /
  grass must be cut before and can't grow back inside a house."* Each was
  measured before it was touched. **"Still not furnished" was true and
  the furniture was there**: every furniture id and `wood_stairs` fell
  through `ProceduralBuildingPieceSprite.generate_image`'s `match` to the
  plain wood-floor tile, so the occupation-themed sets above, and the
  stairs a player needs to find the second storey, drew as bare boards.
  They have real art now (the file's own every-piece-distinct test had
  been red on `main` for exactly this). **The pond**: buildability and the
  painted water surface were two different predicates; one rule now
  (`EarthChunkManager.is_water_at_global`, [building.md](building.md)
  "Placement rules"), and a persisted house piece found standing in water
  on load is washed away and the chunk re-saved, so a world saved before
  this heals itself on the next visit. **Grass/flowers/scrub/lichen** are
  blocked on every built cell (cleared at stamp/build/load, released on
  destroy) and trees keep a one-cell apron around a house. **"Can't
  enter"**: `VillageRenderer._fit_house`/`_find_clear_origin` site a house
  with its footprint AND doorstep inside the chunk, buildable and free of
  anything already built, anywhere in its own chunk, falling back to a
  smaller shape before skipping. **"Poor and basic"**: the facade family,
  [building.md](building.md) "How a house reads from above" point 6 — the
  band a house shows the street is now plaster-and-timber or ashlar with
  an eave shadow, sills, shutters, lintel and doorstep, its upper band a
  variant of its own. The honest measurement of the result (the real
  `spawn_village` re-run on ten real settlements around the reported
  position) lives in building.md's Status entry for this pass, remaining
  gap included. Chunk-boundary and TDD notes: all red-first; the probe that
  found the causes is a throwaway GUT test, deliberately not committed.

**Unlike the batch above (built under an explicit "skip tests" mid-session
instruction), this pass and its follow-ups all followed this project's
own mandatory strict-TDD red-first cycle throughout** — every function
named ✅ in these updates has a real, run, currently-green GUT test
written before its implementation, not just a plausible-looking claim.
Together they closed every gap the batch above named honestly as scoped
OUT (real upper-floor collision, the hire/`BuilderMarker` path, procedural
village generation) plus three more raised directly in review (a hired
roof, real terrain buildability, and NPC house furniture on both floors).
**One exception, named honestly**: the furniture item above was
reconciled by hand during the merge into `main` without a GUT run at the
time — since closed, see that bullet's own note (one test-fixture bug
found, no code bug).

### Open questions

- Appeal-score formula — what actually counts (variety, symmetry, theme
  matching -- now answered by occupation-themed decor above -- rarity of
  decor items) and how legible should the scoring be to the player (fully
  transparent numbers vs. Stardew's opaque quality-heuristic feel)?
- Does a decorated home unlock anything mechanical (better sleep-quality
  bonus feeding [survival.md](survival.md), NPC willingness to be
  [hired](npc.md#hiring--instruction)), or stay a purely social/cosmetic
  system?
- Real upper-floor structural statics/decay/collapse — extending
  `BuildingStatics`/`BuildingDecay` to a second, independent piece grid
  rather than leaving the upper floor structurally inert (named above as a
  deliberate, narrower gap once real collision existed)?
- Now that NPCs can live in two-story houses with real furniture on both
  floors, do they get any real BEHAVIORAL use of the upper floor
  (sleeping upstairs specifically, a merchant's own storeroom), or does
  the NPC's own daily schedule stay indifferent to which floor its
  furniture happens to sit on?
- Should the remaining five two-story shapes (`townhouse_narrow`,
  `riverside_villa`, `timber_longhouse`, `grand_estate`, `gambrel_lodge`)
  ever reach the procedural generator too — widening the merchant/
  blacksmith pools further, extending two-story to a new occupation, or
  improving `SettlementGenerator`'s own ring spacing so the largest
  footprints stop being a real overlap risk?
- The PLAYER's own hand-furnishing verb (`HotbarAction.FURNISH`/`/
  furniture place`) still only ever reaches `EarthChunkManager.
  build_furniture_at_global`, which writes to the ground floor's
  `furniture_modifications` only — NPC generation now furnishes an upper
  floor via its own real `stamp_upper_floor_furniture_at_global`, but a
  PLAYER standing in their own upstairs room still has no verb to place a
  single piece there by hand. Should `build_furniture_at_global` (or a
  new `build_upper_floor_furniture_at_global` sibling) read `Player.
  _current_floor` to decide which real layer a placement targets?
