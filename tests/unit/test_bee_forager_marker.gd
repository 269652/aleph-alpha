extends GutTest

## A REAL forager for a BeeColony hive -- see docs/concept/bees.md
## "Foraging". Mirrors AntForagerMarker's own real round-trip shape
## (SCOUTS for real nectar -- wandering, no known target -- commits and
## flies to it once local sensing finds one, drinks it only on real
## arrival, flies back to the hive, deposits there) trimmed down per
## bees.md's own "What's reused verbatim, what's a deliberate new
## duplicate, and why": no pheromone trail/resolver role (out of scope
## this pass), no carried-item visual, no crush/corpse lifecycle (never
## reported/asked for bees).

const BeeForagerMarker = preload("res://src/rendering/bee_forager_marker.gd")
const BeeForageBehavior = preload("res://src/gameplay/bee_forage_behavior.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const WIDTH := 16
const HEIGHT := 16


func _all_grassland() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for i in biome.size():
		biome[i] = "grassland"
	return biome


func _colony_with_one_hive() -> BeeColony:
	for seed_value in range(1, 200):
		var colony := BeeColony.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		if colony.hive_cells().size() > 0:
			return colony
	fail_test("no seed in [1, 200) placed a single hive")
	return null


## Duck-typed nectar world: the two methods a bee forager calls on its
## `_world` (see EarthChunkManager's real flowers_near/drink_nectar_at) --
## mirrors this whole session's own StubWormWorld/StubCaterpillarWorld
## pattern.
class StubFlowerWorld:
	var flowers: Array = []
	var taken: Array = []
	func flowers_near(position: Vector2, radius_tiles: int) -> Array:
		var out: Array = []
		for f in flowers:
			if position.distance_to(f["position"]) / float(TerrainRenderer.TILE_SIZE) <= float(radius_tiles):
				out.append(f)
		return out
	func drink_nectar_at(position: Vector2) -> bool:
		taken.append(position)
		for i in flowers.size():
			if flowers[i]["position"].distance_to(position) < 0.01 and float(flowers[i].get("nectar", 0.0)) > 0.0:
				flowers[i]["nectar"] = 0.0
				return true
		return false


func _world_with_one_flower(at: Vector2 = Vector2(80, 0)) -> StubFlowerWorld:
	var world := StubFlowerWorld.new()
	world.flowers = [{"position": at, "species": "daisy", "nectar": 1.0}]
	return world


var marker: BeeForagerMarker


func before_each():
	marker = BeeForagerMarker.new()


func _run_until_freed(steps: int = 4000) -> bool:
	for i in steps:
		if not is_instance_valid(marker) or marker.is_queued_for_deletion():
			return true
		marker._process(0.05)
	return false


func test_joins_the_bee_forager_group():
	add_child_autofree(marker)
	assert_true(marker.is_in_group(BeeForagerMarker.GROUP_NAME))


func test_get_display_name_names_it_a_bee():
	add_child_autofree(marker)
	assert_eq(marker.get_display_name(), "Bee")


func test_has_a_real_sprite_texture():
	add_child_autofree(marker)
	var sprite := marker.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)


# -- APPROACHING/RETURNING in isolation (direct construction, matching --
# -- test_ant_forager_marker.gd's own "phase defaults to APPROACHING" ---
# -- backward-compatible contract) ------------------------------------------

func test_approaching_walks_toward_the_target_without_overshooting():
	var world := _world_with_one_flower(Vector2(40, 0))
	marker.setup(world, null, Vector2i.ZERO)
	marker.target_position = Vector2(40, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2.ZERO
	add_child_autofree(marker)
	marker._process(0.05)
	assert_lte(marker.position.distance_to(Vector2(40, 0)), 40.0)
	assert_gt(marker.position.x, 0.0)


func test_takes_the_target_only_on_real_arrival_not_before():
	var world := _world_with_one_flower(Vector2(400, 0))
	marker.setup(world, null, Vector2i.ZERO)
	marker.target_position = Vector2(400, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2.ZERO
	add_child_autofree(marker)
	marker._process(0.05)
	assert_eq(world.taken.size(), 0, "still far away -- must not have taken anything yet")


func test_an_empty_handed_return_deposits_nothing_and_frees_itself():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var world := StubFlowerWorld.new()  # nothing there at all
	marker.setup(world, colony, cell)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	var before := colony.honey_stored_at(cell)
	assert_true(_run_until_freed())
	assert_almost_eq(colony.honey_stored_at(cell), before, 0.001)


func test_a_successful_trip_feeds_the_hives_real_honey_reserve():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var world := _world_with_one_flower(Vector2(4, 0))
	marker.setup(world, colony, cell)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	var before := colony.honey_stored_at(cell)
	assert_true(_run_until_freed())
	assert_gt(colony.honey_stored_at(cell), before)
	assert_eq(world.taken.size(), 1)


func test_a_successful_trip_frees_itself_once_home():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var world := _world_with_one_flower(Vector2(4, 0))
	marker.setup(world, colony, cell)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	assert_true(_run_until_freed())


func test_something_else_may_have_taken_the_nectar_first_still_returns_empty_handed():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var world := _world_with_one_flower(Vector2(4, 0))
	world.flowers[0]["nectar"] = 0.0  # drained by something else before arrival
	marker.setup(world, colony, cell)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	var before := colony.honey_stored_at(cell)
	assert_true(_run_until_freed())
	assert_almost_eq(colony.honey_stored_at(cell), before, 0.001)


# -- scouting: real search, not omniscient dispatch --------------------------

func _make_scout(world) -> void:
	marker.scout = true
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.setup(world, null, Vector2i.ZERO)
	add_child_autofree(marker)


func test_a_scout_starts_in_scouting():
	_make_scout(StubFlowerWorld.new())
	assert_eq(marker._behavior.phase, BeeForageBehavior.Phase.SCOUTING)


func test_a_scout_wanders_when_nothing_is_sensed_nearby():
	_make_scout(StubFlowerWorld.new())
	for i in 20:
		marker._process(0.05)
	assert_ne(marker.position, Vector2.ZERO, "a scout with nothing nearby should still be moving")
	assert_eq(marker._behavior.phase, BeeForageBehavior.Phase.SCOUTING)


func test_a_scout_commits_to_a_real_flower_within_sensing_range():
	var world := _world_with_one_flower(Vector2(5, 0))
	_make_scout(world)
	var committed := false
	for i in 200:
		marker._process(0.05)
		if marker._behavior.phase != BeeForageBehavior.Phase.SCOUTING:
			committed = true
			break
	assert_true(committed, "a real flower well within sensing range should be committed to")


func test_a_scout_never_commits_to_a_flower_that_isnt_there():
	_make_scout(StubFlowerWorld.new())
	for i in 100:
		marker._process(0.05)
		assert_eq(
			marker._behavior.phase, BeeForageBehavior.Phase.SCOUTING,
			"nothing to forage -- must never commit to a flower that isn't there"
		)


func test_a_scout_gives_up_after_max_scout_seconds_and_heads_home_empty_handed():
	_make_scout(StubFlowerWorld.new())
	assert_true(_run_until_freed())


func test_max_scout_seconds_is_derived_not_eyeballed():
	add_child_autofree(marker)
	var expected := (
		(2.0 * BeeColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE))
		/ (BeeForagerMarker.FLY_SPEED * BeeForagerMarker.SCOUT_SPEED_FRACTION)
		* BeeForagerMarker.MAX_SCOUT_CROSSINGS
	)
	assert_almost_eq(BeeForagerMarker.MAX_SCOUT_SECONDS, expected, 0.01)


# -- no world / no colony: graceful, never a crash ---------------------------

func test_scouting_with_no_world_never_crashes_and_still_wanders():
	marker.scout = true
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2.ZERO
	add_child_autofree(marker)
	for i in 20:
		marker._process(0.05)
	assert_ne(marker.position, Vector2.ZERO)


func test_returning_with_no_colony_wired_up_still_frees_itself_without_crashing():
	var world := _world_with_one_flower(Vector2(4, 0))
	marker.setup(world, null, Vector2i.ZERO)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	assert_true(_run_until_freed())
