extends GutTest

## A REAL forager (see docs/concept/soil_fauna.md "Real foraging: a round
## trip, not an instant resolve"): walks to a known food position, takes
## the food only on real arrival (re-checked then, not guaranteed), walks
## back to the mound, and only THERE does the cache/consume roll resolve.
## Deliberately no SEEKING phase (see AntForageBehavior's own doc comment)
## -- the colony already found this target before dispatching a forager at
## all; this marker owns the walk-there-and-back and the real world effect
## at each end, not target discovery.

const AntForagerMarker = preload("res://src/rendering/ant_forager_marker.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const AntForageBehavior = preload("res://src/gameplay/ant_forage_behavior.gd")
const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const IllustratedDecomposerSprite = preload("res://src/rendering/illustrated_decomposer_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")

const MOUND_CELL := Vector2i(3, 3)


## A minimal duck-typed world -- enough of EarthChunkManager's own
## take_grass_seed_at/plant_grass_at/take_fruit_at/try_plant_seed_at
## contract for AntForagerMarker's real-arrival-resolves behaviour,
## without needing a real chunk manager.
class StubWorld:
	var seed_present := true
	var fruit_species := "apple"  # "" means nothing there
	var leaf_present := true
	var planted_grass: Array = []
	var planted_seeds: Array = []  # [{"position": Vector2, "species": String}]

	func take_grass_seed_at(_position: Vector2) -> bool:
		var was_present := seed_present
		seed_present = false
		return was_present

	func plant_grass_at(position: Vector2) -> bool:
		planted_grass.append(position)
		return true

	func take_fruit_at(_position: Vector2) -> String:
		var species := fruit_species
		fruit_species = ""
		return species

	func try_plant_seed_at(position: Vector2, species: String) -> bool:
		planted_seeds.append({"position": position, "species": species})
		return true

	func consume_leaf_litter_at(_position: Vector2) -> bool:
		var was_present := leaf_present
		leaf_present = false
		return was_present

	## Scouting-sensing stand-ins for EarthChunkManager's own real
	## leaf_litter_near/grass_seeds_near/fruit_near (see AntForagerMarker.
	## _sense_food_nearby) -- each defaults to "nothing nearby" (empty), a
	## scouting test opts a specific kind IN by setting its own array to a
	## real candidate list. Radius is ignored here on purpose: a stub
	## reporting whatever the test put there IS the "sensed it" signal,
	## the same "trust the caller already scoped this" convention the
	## other stub methods above already use.
	var nearby_leaves: Array = []
	var nearby_seeds: Array = []
	var nearby_fruit: Array = []

	## How many times each real EarthChunkManager query this stub stands in
	## for was actually called -- see the sense-interval-throttle tests
	## below (reported live, real measured cost: ~1000-1300ms of CPU per
	## 3-second window across ~1000 concurrently-scouting foragers, each
	## calling all three of these every single frame with no throttle at
	## all -- the round-3 FPS regression's dominant cause).
	var sense_call_count := 0

	func leaf_litter_near(_position: Vector2, _radius_px: float) -> Array:
		sense_call_count += 1
		return nearby_leaves

	func grass_seeds_near(_position: Vector2, _radius_tiles: int) -> Array:
		return nearby_seeds

	func fruit_near(_position: Vector2, _radius_tiles: int) -> Array:
		return nearby_fruit


func _new_colony() -> AntColony:
	var biome := PackedStringArray()
	for i in 64:
		biome.append("grassland")
	return AntColony.new(42, 8, 8, biome)


func _spawned(target: Vector2, mound: Vector2, world = null, colony: AntColony = null) -> AntForagerMarker:
	var forager := AntForagerMarker.new()
	forager.target_position = target
	forager.mound_position = mound
	forager.position = mound
	if world != null or colony != null:
		forager.setup(world, colony, MOUND_CELL)
	add_child_autofree(forager)
	return forager


## Real dispatch always scouts now (see EarthChunkManager._dispatch_ant_
## scout) -- no known target_position at all, opted in via `scout` instead
## of the direct-construction shape _spawned above uses.
func _spawned_scout(mound: Vector2, world = null, colony: AntColony = null) -> AntForagerMarker:
	var forager := AntForagerMarker.new()
	forager.mound_position = mound
	forager.position = mound
	forager.scout = true
	if world != null or colony != null:
		forager.setup(world, colony, MOUND_CELL)
	add_child_autofree(forager)
	return forager


## Dispatched once a scout has already reported a real cluster (see
## EarthChunkManager's own scout-vs-resolver dispatch choice) -- follows a
## KNOWN trail rather than exploring blind. Otherwise identical to a
## scout: no known target, opts into SCOUTING the same way.
func _spawned_resolver(mound: Vector2, world = null, colony: AntColony = null) -> AntForagerMarker:
	var forager := AntForagerMarker.new()
	forager.mound_position = mound
	forager.position = mound
	forager.resolver = true
	if world != null or colony != null:
		forager.setup(world, colony, MOUND_CELL)
	add_child_autofree(forager)
	return forager


# -- identity: group membership and tooltip (see docs/concept/soil_fauna.md
# "Ants at half their old size, and finally hoverable") --------------------

func test_joins_the_ant_forager_group():
	var f := _spawned(Vector2(50, 0), Vector2.ZERO)
	assert_true(f.is_in_group(AntForagerMarker.GROUP_NAME))


func test_joins_the_hoverable_group():
	var f := _spawned(Vector2(50, 0), Vector2.ZERO)
	assert_true(f.is_in_group(HoverTargetFinder.GROUP_NAME))


func test_get_display_name_names_it_an_ant():
	var f := _spawned(Vector2(50, 0), Vector2.ZERO)
	assert_eq(f.get_display_name(), "Ant")


func test_has_a_real_ant_sprite_texture():
	var f := _spawned(Vector2(50, 0), Vector2.ZERO)
	var sprite := f.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)


func test_sprite_is_scaled_down_like_every_other_decomposer_ant():
	var f := _spawned(Vector2(50, 0), Vector2.ZERO)
	var sprite := f.get_child(0) as Sprite2D
	assert_eq(sprite.scale, Vector2.ONE * IllustratedDecomposerSprite.new().marker_scale("ant", "walk"))


# -- movement: walks toward whichever leg it is currently on ---------------

## Reported directly: "half ants speed" -- halved from its original 24.0
## (see WALK_SPEED's own doc comment for what that used to mean). Pinned,
## not just a bare literal in the constant's own declaration, per this
## project's "tuned values must be tested" rule -- a future change back
## toward 24.0 (or any other drift) now fails a real test rather than only
## an eyeballed comment.
func test_walk_speed_is_pinned_to_half_its_original_value():
	assert_eq(AntForagerMarker.WALK_SPEED, 12.0)


func test_starts_in_the_approaching_phase():
	var f := _spawned(Vector2(50, 0), Vector2.ZERO)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.APPROACHING)


func test_walks_toward_the_target_before_arriving():
	var f := _spawned(Vector2(100, 0), Vector2.ZERO)
	f._process(0.1)
	assert_gt(f.position.x, 0.0)
	assert_lt(f.position.x, 100.0)


func test_does_not_overshoot_a_short_approach():
	var f := _spawned(Vector2(5, 0), Vector2.ZERO)
	f._process(1.0)  # WALK_SPEED*1.0 = 12px, still far more than the 5px leg
	assert_almost_eq(f.position.x, 5.0, 0.01, "should land exactly on a short target, not overshoot past it")


# -- the real effect: taking the seed only happens on real arrival ---------

func test_taking_the_seed_does_not_happen_before_real_arrival():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(200, 0), Vector2.ZERO, world, colony)
	f._process(0.1)  # a small step, nowhere near arrival yet
	assert_true(world.seed_present, "the seed must still be there until the ant has genuinely walked to it")
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.APPROACHING)


func test_arriving_takes_the_seed_for_real_and_switches_to_returning():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f._process(1.0)  # comfortably enough to close a 2px leg
	assert_false(world.seed_present, "arrival should really take the seed")
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_true(f._behavior.found_food)


## Something else may have taken the seed in the time this forager spent
## walking -- a real forager still walks home, just empty-handed.
func test_arriving_to_find_nothing_there_still_returns_home_empty_handed():
	var world := StubWorld.new()
	world.seed_present = false
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f._process(1.0)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_false(f._behavior.found_food)


func test_a_forager_with_no_world_still_returns_home_empty_handed_rather_than_crashing():
	var f := _spawned(Vector2(2, 0), Vector2.ZERO)  # no setup() call at all
	f._process(1.0)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_false(f._behavior.found_food)


# -- finishing the trip at the mound: cache/consume + self-free -------------

func test_a_successful_grass_seed_trip_plants_a_new_patch_near_the_mound_and_frees_itself():
	var world := StubWorld.new()
	var colony := _new_colony()
	var mound := Vector2(1000, 1000)
	var f := _spawned(mound + Vector2(2, 0), mound, world, colony)
	f._process(1.0)  # arrive at the food, take it, start returning
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	f._process(1.0)  # arrive back at the mound
	assert_eq(world.planted_grass.size(), 1, "a successful grass-seed trip should plant one new patch")
	assert_true(f.is_queued_for_deletion(), "a forager should free itself once its whole round trip is walked")


func test_an_empty_handed_trip_plants_nothing():
	var world := StubWorld.new()
	world.seed_present = false
	var colony := _new_colony()
	var mound := Vector2(1000, 1000)
	var f := _spawned(mound + Vector2(2, 0), mound, world, colony)
	f._process(1.0)
	f._process(1.0)
	assert_eq(world.planted_grass.size(), 0, "nothing was found, so nothing should be planted")
	assert_true(f.is_queued_for_deletion())


## Windfall resolves through AntColony.windfall_is_consumed, deterministic
## per (colony, cell, step) -- predicted here from the same real function
## rather than asserted blind, so this test is exercising the marker's own
## wiring, not guessing at a coin flip.
func test_a_windfall_trip_uses_the_fruit_api_and_resolves_deterministically():
	var world := StubWorld.new()
	world.fruit_species = "apple"
	var colony := _new_colony()
	var mound := Vector2(2000, 2000)
	var f := _spawned(mound + Vector2(2, 0), mound, world, colony)
	f.forage_kind = "windfall"
	f._process(1.0)  # take the fruit
	assert_eq(world.fruit_species, "", "the fruit should really be taken")
	var expected_consumed := AntColony.windfall_is_consumed(colony.windfall_carrier_seed_for(MOUND_CELL))
	f._process(1.0)  # return to the mound and resolve
	if expected_consumed:
		assert_eq(world.planted_seeds.size(), 0, "a consumed windfall find should not be cached")
	else:
		assert_eq(world.planted_seeds.size(), 1, "a surviving windfall find should be cached as a new sapling")
		assert_eq(world.planted_seeds[0]["species"], "apple")


## Bug report: "ants... eat leaves at the spot instead of physically
## carrying the leaf to the mound where it should disappear... the ant
## should be seen dragging the leaf to the mound" (see
## docs/concept/soil_fauna.md's "Leaf litter is a separate forage source
## this mound simulation does not see", now closed). A leaf resolves through
## the same real-arrival-takes-it contract as a seed, just against
## consume_leaf_litter_at instead of take_grass_seed_at.
func test_a_leaf_trip_uses_the_leaf_litter_api_and_resolves_on_arrival():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f.forage_kind = "leaf"
	f._process(1.0)  # comfortably enough to close a 2px leg
	assert_false(world.leaf_present, "arrival should really consume the leaf")
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_true(f._behavior.found_food)


## A leaf is real detritus/food the colony consumes on the spot, not a
## propagule like a grass seed (myrmecochory) or a surviving windfall nut --
## it must simply disappear once carried home, never re-cached/re-planted
## anywhere (see soil_fauna.md's own "where it should disappear" framing).
func test_a_successful_leaf_trip_plants_nothing_and_frees_itself():
	var world := StubWorld.new()
	var colony := _new_colony()
	var mound := Vector2(5000, 5000)
	var f := _spawned(mound + Vector2(2, 0), mound, world, colony)
	f.forage_kind = "leaf"
	f._process(1.0)  # arrive at the leaf, take it, start returning
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	f._process(1.0)  # arrive back at the mound
	assert_eq(world.planted_grass.size(), 0, "a leaf must never be re-planted as a grass patch")
	assert_eq(world.planted_seeds.size(), 0, "a leaf must never be cached as a sapling")
	assert_true(f.is_queued_for_deletion(), "a forager should free itself once its whole round trip is walked")


func test_an_empty_handed_leaf_trip_plants_nothing():
	var world := StubWorld.new()
	world.leaf_present = false
	var colony := _new_colony()
	var mound := Vector2(5000, 5000)
	var f := _spawned(mound + Vector2(2, 0), mound, world, colony)
	f.forage_kind = "leaf"
	f._process(1.0)
	f._process(1.0)
	assert_eq(world.planted_grass.size(), 0)
	assert_eq(world.planted_seeds.size(), 0)
	assert_true(f.is_queued_for_deletion())


# -- pheromones: a successful trip marks the food location ------------------

## Only a CLUSTER find lays a trail now (see this file's own "cluster
## recruitment" section below for the full story) -- a plain, direct-
## construction version of that same claim, in this section's own
## simpler style (no full scout-sensing pipeline needed to prove the
## RETURNING-leg trail-laying mechanic itself).
func test_a_successful_cluster_trip_lays_a_trail_on_the_way_home():
	var world := StubWorld.new()
	var colony := _new_colony()
	var target := Vector2(3000, 3000)
	var mound := Vector2(3100, 3000)  # far enough that RETURNING takes a real step
	var f := _spawned(target, mound, world, colony)
	f._is_cluster_find = true
	f._cluster_size = 3
	# Still 2 more left after taking one -- otherwise arrival-time
	# invalidation (see test_taking_the_last_cluster_item_invalidates_the_
	# trail below) fires immediately and this test would never reach the
	# RETURNING-leg trail-laying it means to exercise.
	world.nearby_seeds = [{"position": target}, {"position": target}]
	f._process(200.0)  # close the whole approach distance
	f._process(0.1)  # now within arrive-distance -- takes it, starts RETURNING
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	f._process(1.0)  # a real step on the way home should lay a trail tile
	var field = colony.pheromones_at(MOUND_CELL)
	assert_not_null(field, "a successful CLUSTER find should lay down a real trail on the way home")
	assert_true(field.has_active_trail())


func test_a_successful_solo_trip_deposits_no_pheromone_at_all():
	var world := StubWorld.new()
	var colony := _new_colony()
	var target := Vector2(3000, 3000)
	var mound := Vector2(3100, 3000)
	var f := _spawned(target, mound, world, colony)
	# _is_cluster_find left at its default false -- a solo find.
	f._process(200.0)
	f._process(0.1)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	f._process(1.0)
	var field = colony.pheromones_at(MOUND_CELL)
	assert_true(field == null or not field.has_active_trail(), "a solo find must never lay a recruiting trail")


func test_a_failed_trip_deposits_no_pheromone():
	var world := StubWorld.new()
	world.seed_present = false
	var colony := _new_colony()
	var f := _spawned(Vector2(3000, 3000), Vector2(3002, 3000), world, colony)
	f._process(1.0)
	assert_null(colony.pheromones_at(MOUND_CELL), "nothing was found, so there is nothing to recruit toward")


# -- the queen hears about it: arrival records the real outcome ------------

func test_arriving_home_records_the_forage_result_with_the_colony():
	var world := StubWorld.new()
	var colony := _new_colony()
	var mound := Vector2(4000, 4000)
	var f := _spawned(mound + Vector2(2, 0), mound, world, colony)
	var before := colony.capacity_at(MOUND_CELL)
	f._process(1.0)  # take the seed
	f._process(1.0)  # return home, record the success
	assert_gt(colony.capacity_at(MOUND_CELL), before, "a real success should feed the colony's own recent-success signal")


# -- sprite pose reflects what is ACTUALLY being carried, not just which
# leg of the trip this is (an empty-handed return must not show the carry
# pose just because the ant is walking home) --------------------------------

func test_shows_the_walk_pose_while_approaching():
	var f := _spawned(Vector2(50, 0), Vector2.ZERO)
	var sprite := f.get_child(0) as Sprite2D
	var walk_frames := IllustratedDecomposerSprite.new().generate_textures("ant", "walk")
	assert_true(walk_frames.has(sprite.texture))


func test_shows_the_carry_pose_while_returning_with_real_food():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f._process(1.0)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	var sprite := f.get_child(0) as Sprite2D
	var carry_frames := IllustratedDecomposerSprite.new().generate_textures("ant", "carry")
	assert_true(carry_frames.has(sprite.texture))


func test_shows_the_walk_pose_while_returning_empty_handed():
	var world := StubWorld.new()
	world.seed_present = false
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f._process(1.0)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_false(f._behavior.found_food)
	var sprite := f.get_child(0) as Sprite2D
	var walk_frames := IllustratedDecomposerSprite.new().generate_textures("ant", "walk")
	assert_true(walk_frames.has(sprite.texture), "an empty-handed return should still show the plain walk cycle, not carry")


# -- the carried leaf itself: a REAL, visible ground-litter sprite that rides
# home with the ant, not just its own body's carry pose -----------------------
#
# Bug report: "the ant now uses the carry sprite sheet animation row when
# dragging a leaf into the mound but it still disappears when the ant
# touches it ... it should actually drag the real leaf entity visibly over
# the ground and it should vanish only when it's in the mound." Traced to
# _resolve_arrival_at_food's own consume_leaf_litter_at call: it genuinely
# removes the leaf from LeafLitterField (and so from the ground renderer)
# the moment the ant ARRIVES at it, which is correct for the ground-litter
# side of the world, but nothing ever stood in for it visually for the
# whole walk back -- only the ant's OWN body switched to its "carry" pose
# (see the section above), same as an empty-handed seed/windfall return.
# `carried_leaf_species`/`carried_leaf_season` (set at dispatch time, from
# the same nearest_leaf_litter_near lookup that found the target position
# in the first place -- see test_earth_chunk_manager.gd's own coverage) let
# this second sprite show the exact leaf that was actually picked up,
# cropped from LeafLitterAtlas the same way the ground renderer itself
# draws it, so a carried cherry autumn leaf looks like the SAME cherry
# autumn leaf that just vanished off the ground, not a generic placeholder.

const LeafLitterAtlas = preload("res://src/rendering/leaf_litter_atlas.gd")
const LeafLitterRenderer = preload("res://src/rendering/leaf_litter_renderer.gd")


func test_shows_no_carried_leaf_visual_while_approaching():
	var f := _spawned(Vector2(50, 0), Vector2.ZERO)
	f.forage_kind = "leaf"
	var leaf_sprite := f.get_child(1) as Sprite2D
	assert_false(leaf_sprite.visible, "nothing has been picked up yet -- no carried leaf to show")


func test_shows_a_carried_leaf_visual_while_returning_with_a_real_leaf():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f.forage_kind = "leaf"
	f.carried_leaf_species = "cherry"
	f.carried_leaf_season = "autumn"
	f._process(1.0)  # arrive, pick up the leaf, start returning
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_true(f._behavior.found_food)
	var leaf_sprite := f.get_child(1) as Sprite2D
	assert_true(leaf_sprite.visible, "a real leaf was just picked up -- it should now visibly ride home")
	assert_not_null(leaf_sprite.texture)


func test_shows_no_carried_leaf_visual_on_an_empty_handed_leaf_return():
	var world := StubWorld.new()
	world.leaf_present = false
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f.forage_kind = "leaf"
	f._process(1.0)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_false(f._behavior.found_food)
	var leaf_sprite := f.get_child(1) as Sprite2D
	assert_false(leaf_sprite.visible, "nothing was actually found -- there is no leaf to visibly carry home")


func test_shows_no_carried_leaf_visual_for_a_seed_trip():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f._process(1.0)  # default forage_kind "seed"
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_true(f._behavior.found_food)
	var leaf_sprite := f.get_child(1) as Sprite2D
	assert_false(leaf_sprite.visible, "a grass seed has its own carry pose already -- this visual is leaf-only")


## Pinned, not eyeballed: a carried leaf should read as the SAME SIZE as one
## still sitting on the ground (LeafLitterRenderer.WORLD_SIZE), not the
## atlas stamp's own native pixel size (LeafLitterAtlas.STAMP_SIZE, a fixed
## 64px regardless of how big the art should actually READ in the world).
func test_the_carried_leaf_visual_is_scaled_to_match_ground_litter_size():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f.forage_kind = "leaf"
	f.carried_leaf_species = "cherry"
	f.carried_leaf_season = "autumn"
	f._process(1.0)
	var leaf_sprite := f.get_child(1) as Sprite2D
	var expected_scale := Vector2.ONE * (LeafLitterRenderer.WORLD_SIZE / float(LeafLitterAtlas.STAMP_SIZE))
	assert_eq(leaf_sprite.scale, expected_scale)


## Pinned against the SAME atlas math the ground renderer itself packs (see
## LeafLitterAtlas.cell_index/CELL_SIZE/STAMP_PADDING/STAMP_SIZE) -- the
## carried sprite must crop the identical cell a ground-resting leaf of this
## exact species/season would use, not merely "some texture, non-null".
func test_the_carried_leaf_visual_crops_the_correct_atlas_cell():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(2, 0), Vector2.ZERO, world, colony)
	f.forage_kind = "leaf"
	f.carried_leaf_species = "cherry"
	f.carried_leaf_season = "autumn"
	f._process(1.0)
	var leaf_sprite := f.get_child(1) as Sprite2D
	var atlas := LeafLitterAtlas.new()
	var index := atlas.cell_index("cherry", "autumn")
	var expected_region := Rect2(
		index * LeafLitterAtlas.CELL_SIZE + LeafLitterAtlas.STAMP_PADDING, LeafLitterAtlas.STAMP_PADDING,
		LeafLitterAtlas.STAMP_SIZE, LeafLitterAtlas.STAMP_SIZE
	)
	assert_true(leaf_sprite.texture is AtlasTexture)
	assert_eq((leaf_sprite.texture as AtlasTexture).region, expected_region)


# -- scouting: real search, not omniscient dispatch (see docs/concept/
# soil_fauna.md's section of that name) ------------------------------------
#
# Reported live: "ants go straight to the next leaf when moving out the
# mound ... they should either explore randomly or follow pheromones",
# then, after a pheromone-biased candidate-LIST dispatch answered that:
# "no omniscience please". A scout starts with NO known target at all
# (opt in via `scout`, see _spawned_scout) -- it senses real food only
# within its own small, LOCAL SENSE_RADIUS_TILES as it wanders, never the
# whole mound's forage reach from a stationary point. Food is placed
# right at the mound's own spawn position in these tests so sensing
# commits on the very FIRST _process() call, before any wander movement
# at all -- this is what keeps these tests deterministic despite real
# wandering itself being seeded by an unpredictable randi() roll (see
# wander_seed's own doc comment): the COMMIT logic is being proven here,
# not "wandering eventually stumbles onto a specific far-off point",
# which is a claim about AmbientFlyerMovement/AntScoutWander's own already
#-tested pure math, not about this marker's wiring.

func test_a_scout_starts_in_the_scouting_phase():
	var f := _spawned_scout(Vector2.ZERO)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.SCOUTING)


func test_a_scout_wanders_when_nothing_is_sensed_nearby():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(1.0)
	assert_ne(f.position, Vector2.ZERO, "nothing was sensed -- it should still be wandering, not frozen in place")
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.SCOUTING)


func test_a_scout_commits_to_a_real_leaf_within_sensing_range():
	var world := StubWorld.new()
	world.nearby_leaves = [{"position": Vector2(5, 0), "species": "cherry", "season": "autumn"}]
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.APPROACHING)
	assert_eq(f.target_position, Vector2(5, 0))
	assert_eq(f.forage_kind, "leaf")
	assert_eq(f.carried_leaf_species, "cherry")
	assert_eq(f.carried_leaf_season, "autumn")


func test_a_scout_commits_to_a_real_seed_within_sensing_range():
	var world := StubWorld.new()
	world.nearby_seeds = [{"position": Vector2(5, 0)}]
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.APPROACHING)
	assert_eq(f.target_position, Vector2(5, 0))
	assert_eq(f.forage_kind, "seed")


func test_a_scout_commits_to_a_real_nut_within_sensing_range():
	var world := StubWorld.new()
	world.nearby_fruit = [{"position": Vector2(5, 0), "species": "acorn"}]
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.APPROACHING)
	assert_eq(f.target_position, Vector2(5, 0))
	assert_eq(f.forage_kind, "windfall")


## Mirrors _forage_windfall_near_mound's own original gate exactly (see
## that function's history): a single ant cannot meaningfully interact
## with an intact fleshy fruit the way a bird or squirrel does.
func test_a_scout_ignores_a_fleshy_fruit_only_a_real_nut_counts():
	var world := StubWorld.new()
	world.nearby_fruit = [{"position": Vector2(5, 0), "species": "apple"}]
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.SCOUTING, "a fleshy fruit is not real prey for a lone ant")


## Leaf litter is not biome-gated at all, unlike seed/windfall (see
## _sense_food_nearby's own doc comment) -- checked first, same priority
## DecomposerMarker's own ambient sensing already gives it.
func test_a_scout_prefers_a_leaf_over_a_seed_sensed_at_the_same_time():
	var world := StubWorld.new()
	world.nearby_leaves = [{"position": Vector2(5, 0), "species": "cherry", "season": "autumn"}]
	world.nearby_seeds = [{"position": Vector2(-5, 0)}]
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_eq(f.forage_kind, "leaf")


func test_a_scout_gives_up_after_the_scouting_budget_with_nothing_found():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(AntForagerMarker.MAX_SCOUT_SECONDS + 1.0)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_false(f._behavior.found_food)


func test_a_scout_with_no_world_gives_up_rather_than_crashing():
	var f := _spawned_scout(Vector2.ZERO)  # no setup() call at all
	f._process(AntForagerMarker.MAX_SCOUT_SECONDS + 1.0)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_false(f._behavior.found_food)


## Pinned, not eyeballed (see CLAUDE.md's own "tuned values must be
## tested" rule and MAX_SCOUT_CROSSINGS/MAX_SCOUT_SECONDS' own doc
## comments): a real derivation from FORAGE_RADIUS_TILES/WALK_SPEED/
## SCOUT_SPEED_FRACTION, not an independent literal.
func test_max_scout_seconds_is_derived_not_eyeballed():
	var expected := (
		(2.0 * AntColony.FORAGE_RADIUS_TILES * TerrainRenderer.TILE_SIZE)
		/ (AntForagerMarker.WALK_SPEED * AntForagerMarker.SCOUT_SPEED_FRACTION)
		* AntForagerMarker.MAX_SCOUT_CROSSINGS
	)
	assert_almost_eq(AntForagerMarker.MAX_SCOUT_SECONDS, expected, 0.001)


# -- performance: a scouting forager must not re-sense every single frame,
# -- and must update at SimulationLod's reduced rate far from the player
# -- (reported live, real measured cost via a --solo perf investigation
# -- session: FPS collapsed to 3-5, ~1000-1300ms of CPU per 3-second window
# -- spent inside _sense_food_nearby alone, across roughly 1000
# -- concurrently-scouting foragers -- this class was the one creature
# -- marker in the whole codebase with no SimulationLod throttling at all,
# -- unlike DecomposerMarker/MillipedeMarker/CreatureMarker/FishMarker,
# -- despite this file's own top doc comment claiming it mirrors
# -- DecomposerMarker's wander). See docs/concept/soil_fauna.md's own
# -- "Generalized... FPS regression round 3" section. -----------------------

## A scout senses its surroundings on its very first scouting step
## (immediately -- see SENSE_INTERVAL_SECONDS' own doc comment), but not
## again on every subsequent frame regardless of how close it still is:
## real food lying there does not need re-discovering every 1/60th of a
## second when the ant itself has barely moved between checks.
func test_scouting_does_not_re_sense_every_single_frame():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.01)  # the immediate first-ever sense
	var after_first_call := world.sense_call_count
	assert_eq(after_first_call, 1, "precondition: the very first scouting step should sense immediately")
	for i in 15:
		f._process(0.01)  # 15 * 0.01s = 0.15s, under SENSE_INTERVAL_SECONDS
	assert_eq(
		world.sense_call_count, after_first_call,
		"re-sensing this soon after the first check should be throttled, not run every frame"
	)


## Once SENSE_INTERVAL_SECONDS has genuinely elapsed, sensing DOES run
## again -- this is a real throttle, not a permanent one-shot.
func test_scouting_re_senses_once_the_interval_actually_elapses():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.01)
	assert_eq(world.sense_call_count, 1, "precondition")
	f._process(AntForagerMarker.SENSE_INTERVAL_SECONDS + 0.01)
	assert_eq(world.sense_call_count, 2, "a real elapsed interval should trigger a fresh sense check")


## Mirrors DecomposerMarker's own test_far_from_the_player_does_not_
## rescan_carrion_on_every_process_call exactly -- a scouting forager far
## from the player must advance in fewer, larger LOD-coalesced steps, not
## call _step_scouting (and so _sense_food_nearby) on every tiny _process
## call regardless of distance.
func test_far_from_the_player_updates_at_the_lod_reduced_rate():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	var player := Node2D.new()
	add_child_autofree(player)
	player.add_to_group("player")
	player.position = f.position + Vector2(
		SimulationLod.FULL_RATE_RADIUS_PX + SimulationLod.FALLOFF_PX + 1.0, 0
	)
	for i in 20:
		f._process(0.01)
	assert_eq(
		world.sense_call_count, 0,
		"far from the player, a scouting forager should not have accumulated enough LOD-reduced time to sense yet"
	)


# -- cluster recruitment: only a real cluster ever lays a trail, directional,
# -- invalidated once spent (reported live: "when a scout goes out other
# -- ants follow him in a line even when nothing has been discovered yet
# -- ... these scouts should only lay out pheromones after they discovered
# -- a cluster for which multiple ants are needed ... he encodes direction
# -- and amount in the pheromones so other ants don't follow it back into
# -- the mound ... then when the scouts return the mound dispatches more
# -- ants which follow / resolve the pheromone trails and the last ant
# -- which takes home the last piece or one that encounters it empty
# -- invalidates the pheromone trail") ---------------------------------------

const PheromoneField = preload("res://src/world/pheromone_field.gd")

## Three real items sensed together, matching AntColony.CLUSTER_THRESHOLD
## exactly -- the minimum that counts as a real cluster.
const _CLUSTER_LEAVES: Array = [
	{"position": Vector2(100, 0), "species": "cherry", "season": "autumn"},
	{"position": Vector2(101, 0), "species": "cherry", "season": "autumn"},
	{"position": Vector2(102, 0), "species": "cherry", "season": "autumn"},
]


func test_a_scout_flags_a_cluster_find_when_enough_items_are_sensed_together():
	var world := StubWorld.new()
	world.nearby_leaves = _CLUSTER_LEAVES.duplicate(true)
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_true(f._is_cluster_find)
	assert_eq(f._cluster_size, 3)


func test_a_scout_does_not_flag_a_cluster_for_a_single_item():
	var world := StubWorld.new()
	world.nearby_leaves = [_CLUSTER_LEAVES[0].duplicate(true)]
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_false(f._is_cluster_find)


func test_a_cluster_find_lays_a_trail_on_the_way_home():
	var world := StubWorld.new()
	world.nearby_leaves = _CLUSTER_LEAVES.duplicate(true)
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)  # senses the cluster (stub ignores real distance), commits
	assert_true(f._is_cluster_find, "precondition")
	f._process(100.0)  # walk all the way to the food
	f._process(0.1)  # now within arrive-distance -- takes it, starts RETURNING
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	f._process(1.0)  # a real step on the way home should lay a trail tile
	var field: PheromoneField = colony.pheromones_at(MOUND_CELL)
	assert_not_null(field, "a cluster find should start a real trail on the way home")
	assert_true(field.has_active_trail())


func test_a_solo_find_lays_no_trail_at_all():
	var world := StubWorld.new()
	world.nearby_leaves = [_CLUSTER_LEAVES[0].duplicate(true)]
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_false(f._is_cluster_find, "precondition")
	f._process(100.0)
	f._process(0.1)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.RETURNING)
	f._process(1.0)
	var field: PheromoneField = colony.pheromones_at(MOUND_CELL)
	assert_true(
		field == null or not field.has_active_trail(),
		"a solo find must never lay a recruiting trail"
	)


func test_the_trail_direction_points_toward_the_food_not_the_mound():
	var world := StubWorld.new()
	world.nearby_leaves = _CLUSTER_LEAVES.duplicate(true)
	var colony := _new_colony()
	var f := _spawned_scout(Vector2.ZERO, world, colony)
	f._process(0.1)
	f._process(100.0)
	f._process(0.1)  # arrival, now RETURNING (walking from the food at x=100 back toward x=0)
	f._process(1.0)  # lays a trail tile somewhere between the food and the mound
	var field: PheromoneField = colony.pheromones_at(MOUND_CELL)
	var trail := field.nearest_trail_near(f.position, float(TerrainRenderer.TILE_SIZE))
	assert_gt(
		trail.get("direction").x, 0.5,
		"the trail should point back OUT toward the food (+x), not toward the mound"
	)


func test_taking_the_last_cluster_item_invalidates_the_trail():
	var world := StubWorld.new()
	world.leaf_present = true
	world.nearby_leaves = []  # nothing else left once this last one is taken
	var colony := _new_colony()
	colony.deposit_pheromone_trail(MOUND_CELL, Vector2i(6, 0), Vector2(1, 0), 3.0)
	var f := _spawned(Vector2(100, 0), Vector2.ZERO, world, colony)
	f.forage_kind = "leaf"
	f._is_cluster_find = true  # as if a scout/resolver had already committed to this as a cluster
	f._process(200.0)  # close the whole approach distance
	f._process(0.1)  # arrival -- takes the last real item
	assert_true(f._behavior.found_food, "precondition: the take itself should succeed")
	var field: PheromoneField = colony.pheromones_at(MOUND_CELL)
	assert_false(field.has_active_trail(), "taking the last real item should invalidate the trail immediately")


func test_arriving_to_find_a_cluster_already_empty_invalidates_the_trail():
	var world := StubWorld.new()
	world.leaf_present = false  # already gone by the time this ant arrives
	var colony := _new_colony()
	colony.deposit_pheromone_trail(MOUND_CELL, Vector2i(6, 0), Vector2(1, 0), 3.0)
	var f := _spawned(Vector2(100, 0), Vector2.ZERO, world, colony)
	f.forage_kind = "leaf"
	f._is_cluster_find = true
	f._process(200.0)
	f._process(0.1)  # arrival -- the take fails
	assert_false(f._behavior.found_food, "precondition: nothing was really there any more")
	var field: PheromoneField = colony.pheromones_at(MOUND_CELL)
	assert_false(
		field.has_active_trail(),
		"arriving to find the cluster already empty should invalidate the existing trail too"
	)


# -- resolvers: dispatched once a scout has already reported a real cluster,
# -- they FOLLOW a known trail rather than exploring blind ------------------

func test_a_resolver_follows_a_known_trail_instead_of_wandering_blind():
	var world := StubWorld.new()
	var colony := _new_colony()
	colony.deposit_pheromone_trail(MOUND_CELL, Vector2i(0, 0), Vector2(1, 0), 3.0)
	var f := _spawned_resolver(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_gt(
		f.position.x, 0.0,
		"should have stepped in the trail's own stored direction, not an arbitrary wander heading"
	)


func test_a_resolver_with_no_known_trail_wanders_like_a_plain_scout():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned_resolver(Vector2.ZERO, world, colony)
	f._process(1.0)
	assert_ne(f.position, Vector2.ZERO, "with nothing to follow, a resolver should still be wandering, not frozen")
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.SCOUTING)


func test_a_resolver_that_senses_real_food_directly_commits_just_like_a_scout():
	var world := StubWorld.new()
	world.nearby_leaves = [_CLUSTER_LEAVES[0].duplicate(true)]
	var colony := _new_colony()
	colony.deposit_pheromone_trail(MOUND_CELL, Vector2i(0, 0), Vector2(1, 0), 3.0)
	var f := _spawned_resolver(Vector2.ZERO, world, colony)
	f._process(0.1)
	assert_eq(f._behavior.phase, AntForageBehavior.Phase.APPROACHING, "sensing real food takes priority over trail-following")


# -- scout waves: an assigned spread sector nudges wander, so several ------
# -- scouts dispatched together fan out (reported live: "the mound should
# -- send out multiple scouts in random directs") ---------------------------

func test_a_scouts_assigned_spread_direction_measurably_changes_its_wander():
	var world := StubWorld.new()
	var colony := _new_colony()

	var f1 := _spawned_scout(Vector2.ZERO, world, colony)
	f1._process(0.001)  # runs _ensure_initialized() once
	f1.wander_seed = 777
	f1._elapsed_time = 0.0
	f1.position = Vector2.ZERO
	f1._process(0.1)
	var position_without_bias := f1.position

	var f2 := _spawned_scout(Vector2.ZERO, world, colony)
	f2._process(0.001)
	f2.wander_seed = 777
	f2._elapsed_time = 0.0
	f2.position = Vector2.ZERO
	f2.assigned_heading_bias = Vector2.UP
	f2._process(0.1)
	var position_with_bias := f2.position

	assert_ne(
		position_with_bias, position_without_bias,
		"an assigned spread direction should measurably change this scout's own wander step"
	)
