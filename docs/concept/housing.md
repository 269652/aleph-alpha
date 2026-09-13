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
layer, painted on its own `UpperFloor` `TileMapLayer` (mirroring
`EarthChunkManager.set_roof_layer`/`_paint_roof` exactly), placed BEFORE
`Roof` in `world.tscn`'s node order so the roof still draws on top of the
upper floor precisely the way it already draws on top of the ground floor.

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

**Windows visible from outside is the real "sophisticated" signal, not
decoration.** `_update_upper_floor_visibility` is an exact mirror of the
existing `_update_roof_visibility`/room-hiding logic, one layer up: it
hides the upper floor's OWN room only when the player is standing on
floor 1 AND physically inside that specific room (`RoomDetector.room_
containing` against a new `_upper_floor_piece_grid_for` grid, the same
enclosure check furniture placement above already reuses). Everywhere
else — including every other player looking at the house from the ground,
or the owner standing outside their own house — the upper floor's walls
and windows render UNCONDITIONALLY. That is what makes a lit window
visible two stories up from the street: the upper floor is not a secret
room that pops into existence, it is real geometry that only hides itself
from the one vantage point (standing inside it) where showing it would
occlude the player's own view of themselves.

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
  build_roofs()`'s existing facade-derived roof already correctly caps
  whichever floor is topmost — this is a case where reusing the existing
  system required literally zero new code, not an accidental gap.

### Status

- ✅ Night lighting (ambient), above.
- ✅ `BuildingPiece.CATEGORY_FURNITURE` + five real pieces (wood_chair/
  table/bookshelf/bed/rug) and their matching `ItemCatalog` entries
- ✅ `FurniturePlacement.can_place`/`refusal_reason` (interior-floor rule,
  its own layer, tested against a real enclosed-room fixture)
- ✅ `Chunk.furniture_modifications` + its own `TileMapLayer`/paint pass
  (`EarthChunkManager.set_furniture_layer`/`_paint_furniture`, a new
  `Furniture` node in `world.tscn` mirroring `Roof`'s own shape) --
  persisted the same generic way `roof_modifications` already is, and
  rendered via the ALREADY-real shared atlas (`TerrainRenderer.
  atlas_coords_for_modification` already resolves any `BuildingPiece`,
  furniture included, since furniture pieces are real `PIECE_IDS` entries)
- ✅ Placing/removing furniture in the world: `EarthChunkManager.
  build_furniture_at_global`/`destroy_furniture_at_global`/
  `furniture_at_global`, gated by `FurniturePlacement` (real interior-floor
  rule). A real hotbar-armed in-world verb now exists too: a new
  `HotbarAction.FURNISH` (`"furniture"` kind → its own `_selected_
  furniture_item`, mirroring `"placeable"`'s own `_selected_placeable_item`
  exactly, mutually exclusive with it) makes `_build_step` furnish instead
  of placing/terraforming, and `_destroy_step` checks the furniture layer
  BEFORE the general modification layer (a table sitting on a floor
  destroys the table, not the floor under it). The `/furniture place|
  remove` dev-console command (the same interim-call-site choice
  `player_citizenship.md`'s own item commands made) stays too, as a second,
  still-real way to reach the same world model.
- ⬜ `appeal_score` (the honest placeholder above)
- ⬜ NPC visits / opinions from a home's appeal
- ⬜ Multiplayer visiting/rating
- ✅ Two-story houses, above: `BuildingPiece.CATEGORY_STAIRS`/`wood_stairs`;
  `HouseBlueprint.TWO_STORY_BLUEPRINT_IDS`/`is_two_story`/`build_upper_
  floor`; `Chunk.upper_floor_modifications` + its own `UpperFloor`
  `TileMapLayer`/paint pass; `EarthChunkManager.set_current_player_floor`/
  `_update_upper_floor_visibility`/`upper_floor_at_global`/
  `step_on_stairs`/`_stamp_upper_floor_at_global`; `Player._current_floor`/
  `_floor_transition_step`; ten new blueprints, `ItemCatalog` entries,
  `shop.gd` prices, and `CraftingRecipeBook` recipes (all at the manor's
  own carpentry_level 3.0 ceiling)
- ⬜ Real upper-floor wall collision (visual/room-detection only for now —
  named above)
- ⬜ Hire/`BuilderMarker` path building second floors (player-only for now
  — named above)
- ⬜ Procedural village NPC houses ever being two-story (deliberately
  single-story only for now — named above)

**The same explicit caveat as `workforce.md`'s own Status list**: the
✅/🚧 items above (the layer/paint pass and the place/remove verb, and
now the entire two-story house system) were written directly per an
explicit, direct mid-session user instruction ("skip tests"), without
this project's own mandatory strict-TDD red-first cycle and without
running the test suite at all. Grounded in real, independently-verified
existing APIs (`TerrainRenderer.atlas_coords_for_modification`,
`ChunkSerializer.save_modifications`/`load_modifications`,
`FurniturePlacement`'s own already-tested rule, and — for two-story
specifically — `_update_roof_visibility`'s own already-tested room-hiding
logic, mirrored rather than reinvented) -- but genuinely unverified until
a real GUT pass confirms it. Do not merge to `main` on the strength of
this Status list alone.

### Open questions

- Appeal-score formula — what actually counts (variety, symmetry, theme
  matching, rarity of decor items) and how legible should the scoring be to
  the player (fully transparent numbers vs. Stardew's opaque
  quality-heuristic feel)?
- Does a decorated home unlock anything mechanical (better sleep-quality
  bonus feeding [survival.md](survival.md), NPC willingness to be
  [hired](npc.md#hiring--instruction)), or stay a purely social/cosmetic
  system?
- Real upper-floor wall collision — a second simultaneous per-cell static
  body layer, gated on `_current_player_floor`, so a player can no longer
  walk through upstairs walls from either floor?
- Should `hire_builder_for_house`/`BuilderMarker` ever build second floors,
  or should two-story houses stay a player-only, hands-on build (mirroring
  how only the player currently builds roofs by hand too)?
- Should procedural village generation ever place NPC-owned two-story
  houses, and if so, do NPCs get any use of the upper floor (sleeping
  upstairs, a merchant's storeroom) or is it purely a bigger, emptier shell
  than what a player would furnish?
- Furniture placement (above) only checks `modifications`' ground floor —
  should `FurniturePlacement.can_place` also accept `upper_floor_
  modifications` floor cells, so a player can furnish the upstairs room
  they just built stairs to?
