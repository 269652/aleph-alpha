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
	f._process(1.0)  # WALK_SPEED*1.0 = 24px, far more than the 5px leg
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
