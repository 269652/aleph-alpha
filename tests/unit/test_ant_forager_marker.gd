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

func test_a_successful_trip_deposits_pheromone_at_the_food_location():
	var world := StubWorld.new()
	var colony := _new_colony()
	var target := Vector2(3000, 3000)
	var f := _spawned(target, Vector2(3002, 3000), world, colony)
	f._process(1.0)  # arrive and take the seed
	var field = colony.pheromones_at(MOUND_CELL)
	assert_not_null(field, "a successful find should lay down a real trail")
	assert_gt(field.concentration_at(target, TerrainRenderer.TILE_SIZE), 0.0)


func test_a_failed_trip_deposits_no_pheromone():
	var world := StubWorld.new()
	world.seed_present = false
	var colony := _new_colony()
	var f := _spawned(Vector2(3000, 3000), Vector2(3002, 3000), world, colony)
	f._process(1.0)
	assert_null(colony.pheromones_at(MOUND_CELL), "nothing was found, so there is nothing to recruit toward")


# -- scouting: a successful scout trip also marks the cluster (see
# docs/concept/soil_fauna.md "Scouts mark leaf clusters, workers collect
# from marks") --------------------------------------------------------

func test_a_successful_scout_trip_marks_the_cluster():
	var world := StubWorld.new()
	var colony := _new_colony()
	var target := Vector2(3000, 3000)
	var f := _spawned(target, Vector2(3002, 3000), world, colony)
	f.forage_kind = "leaf"
	f.is_scout = true
	f._process(1.0)  # arrive and take the leaf
	assert_eq(colony.cluster_marks_at(MOUND_CELL), [target])


func test_a_non_scout_leaf_trip_never_marks_a_cluster():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(3000, 3000), Vector2(3002, 3000), world, colony)
	f.forage_kind = "leaf"
	f.is_scout = false
	f._process(1.0)
	assert_true(colony.cluster_marks_at(MOUND_CELL).is_empty(), "an ordinary leaf trip must not mark a cluster")


func test_a_failed_scout_trip_marks_no_cluster():
	var world := StubWorld.new()
	world.leaf_present = false
	var colony := _new_colony()
	var f := _spawned(Vector2(3000, 3000), Vector2(3002, 3000), world, colony)
	f.forage_kind = "leaf"
	f.is_scout = true
	f._process(1.0)
	assert_true(colony.cluster_marks_at(MOUND_CELL).is_empty(), "nothing was found, so there is no cluster to mark")


## A scout dispatched for seed/windfall (not attempted by the current
## dispatcher, but not this marker's own job to forbid) still never marks
## a cluster -- marking is scoped to real leaf trips only (see docs/
## concept/soil_fauna.md's own "leaf-only" scope note).
func test_a_successful_scout_trip_for_a_non_leaf_kind_marks_no_cluster():
	var world := StubWorld.new()
	var colony := _new_colony()
	var f := _spawned(Vector2(3000, 3000), Vector2(3002, 3000), world, colony)
	f.forage_kind = "seed"
	f.is_scout = true
	f._process(1.0)
	assert_true(colony.cluster_marks_at(MOUND_CELL).is_empty())


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
