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
	## Real EarthChunkManager.current_season() -- read by the scent-gradient
	## wander bias (see ScentField) to score flower entries the same way the
	## real field does. Defaults to spring so a stub blossom entry (spring-
	## only in the real world, see blossoms_near) is usable out of the box
	## without every test having to set this explicitly.
	var season := "spring"
	func current_season() -> String:
		return season
	## Real honeybee/solitary-bee fruit-tree pollination (see bees.md's
	## own doc comment on this being the LIVE replacement for the retired
	## decorative bee's own TREE_POLLINATING_SPECIES path) -- shares the
	## identical {"position", "nectar"} dict shape flowers_near already
	## uses (see EarthChunkManager.blossoms_near's own real return
	## shape), so the same StubFlowerWorld covers both without a second
	## stub class.
	var blossoms: Array = []
	var pollinated: Array = []
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
	func blossoms_near(position: Vector2, radius_tiles: int) -> Array:
		var out: Array = []
		for b in blossoms:
			if position.distance_to(b["position"]) / float(TerrainRenderer.TILE_SIZE) <= float(radius_tiles):
				out.append(b)
		return out
	func record_pollination_visit_at(position: Vector2, _visit_weight: float = 1.0) -> bool:
		pollinated.append(position)
		for b in blossoms:
			if b["position"].distance_to(position) < 0.01:
				return true
		return false


## A world implementing only the flower half of the contract -- no
## blossoms_near/record_pollination_visit_at/current_season at all,
## mirroring AmbientFlyerMarker's own has_method("blossoms_near") defensive
## gate (a world that predates/doesn't offer tree pollination, or season
## reporting, must never crash a scout reaching for either).
class MinimalFlowerWorld:
	var flowers: Array = []
	func flowers_near(position: Vector2, radius_tiles: int) -> Array:
		var out: Array = []
		for f in flowers:
			if position.distance_to(f["position"]) / float(TerrainRenderer.TILE_SIZE) <= float(radius_tiles):
				out.append(f)
		return out
	func drink_nectar_at(_position: Vector2) -> bool:
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


## Reported live: "I saw a hive where streams of bees are flying in that
## appear out of nowhere." A bee is a plain Y-sorted sibling of trees
## under the same Entities node (see EarthChunkManager._dispatch_bee_
## forager/_entities_parent) -- and every hive is required to sit within
## a couple of tiles of a real tree (see _has_real_hive_anchor). A tree's
## OWN sort position is where it is rooted, not how tall its canopy
## draws; a bee flying at a screen position the Y-sort places "behind"
## that anchor gets hidden under the canopy sprite entirely, then pops
## into view the instant it crosses the sort boundary -- reading exactly
## as "materializing mid-air," not the continuous flight it actually is.
## Y-sorting cannot resolve that on its own: the tree answers "where is
## it rooted", the bee answers "where is it flying", and those are
## different questions (mirrors AmbientFlyerMarker.AIRBORNE_Z_INDEX's own
## doc comment almost verbatim -- butterflies hovering at a flower had
## the identical bug, fixed the identical way; bees never got it).
func test_draws_above_ground_scenery_like_a_flying_thing_should():
	add_child_autofree(marker)
	assert_eq(marker.z_index, BeeForagerMarker.AIRBORNE_Z_INDEX)


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


# -- fruit-tree pollination: the LIVE replacement for the retired -----------
# -- decorative bee's own TREE_POLLINATING_SPECIES path (see -----------
# -- docs/concept/bees.md and AmbientFlyerRenderer's own retirement) --------
#
# Real honeybees (and real solitary bees) are genuine pollinators of
# blossoming fruit trees, not just flower-nectar feeders -- retiring the
# old decorative "bee" without giving this real forager the identical
# capability would have silently dropped fruit-tree pollination from the
# game entirely, a real regression this closes instead.

func test_a_scout_commits_to_a_real_blossoming_tree_when_no_flower_is_nearer():
	var world := StubFlowerWorld.new()
	world.blossoms = [{"position": Vector2(5, 0), "species": "cherry", "nectar": 1.0}]
	_make_scout(world)
	var committed := false
	for i in 200:
		marker._process(0.05)
		if marker._behavior.phase != BeeForageBehavior.Phase.SCOUTING:
			committed = true
			break
	assert_true(committed, "a real blossoming tree well within sensing range should be committed to")


func test_a_successful_blossom_trip_pollinates_the_tree_not_drinks_nectar():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var world := StubFlowerWorld.new()
	world.blossoms = [{"position": Vector2(4, 0), "species": "cherry", "nectar": 1.0}]
	marker.setup(world, colony, cell)
	marker.target_position = Vector2(4, 0)
	marker._target_kind = "blossom"
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	assert_true(_run_until_freed())
	assert_eq(world.pollinated.size(), 1, "a blossom trip should pollinate the tree")
	assert_eq(world.taken.size(), 0, "a blossom trip should never call drink_nectar_at")


func test_a_flower_is_preferred_over_a_blossom_at_equal_distance():
	var world := StubFlowerWorld.new()
	world.flowers = [{"position": Vector2(5, 0), "species": "daisy", "nectar": 1.0}]
	world.blossoms = [{"position": Vector2(5, 0), "species": "cherry", "nectar": 1.0}]
	_make_scout(world)
	var found := marker._sense_food_nearby()
	assert_eq(found.get("kind"), "flower")


func test_scouting_never_crashes_when_the_world_has_no_blossoms_near_method():
	# Mirrors AmbientFlyerMarker's own has_method("blossoms_near") gate --
	# a world that only implements the flower half (e.g. an isolated test
	# double, or in principle a future non-EarthChunkManager world) must
	# never crash reaching for a method it doesn't have.
	_make_scout(MinimalFlowerWorld.new())
	for i in 20:
		marker._process(0.05)
	assert_ne(marker.position, Vector2.ZERO)


# -- distant detection: attraction from beyond close sensing range ---------
#
# Real bees are drawn to blossom/flower scent from well outside the range
# at which they could already commit to landing on one -- see docs/concept/
# flora.md#tree-blossoms-emit-real-scent-too / bees.md's own "A scout also
# detects scent at range" addition. Local sensing (_sense_food_nearby,
# BeeColony.SENSE_RADIUS_TILES) is UNCHANGED and still preferred whenever it
# finds something; _sense_distant_food is a wider (DISTANT_SENSE_RADIUS_
# TILES), lower-priority fallback consulted only when it finds nothing.
#
# NOT a gradient-steering blend (contrast AmbientFlyerMarker's own
# SCENT_STEER_WEIGHT for butterflies): ScentField.RADIUS_TILES (6 tiles,
# how far a real scent plume physically carries) is SMALLER than
# BeeColony.SENSE_RADIUS_TILES (9) already, so a gradient sampled from the
# scout's own position could never contribute anything by the time this
# fallback is even reached -- anything within gradient range would already
# have been within guaranteed-commit range. See DISTANT_SENSE_RADIUS_TILES's
## own doc comment for the full reasoning.

## Beyond SENSE_RADIUS_TILES (so _sense_food_nearby finds nothing and the
## scout cannot simply commit) but within DISTANT_SENSE_RADIUS_TILES (so
## the wider detection query can still reach it).
const _BEYOND_CLOSE_SENSE_TILES := BeeColony.SENSE_RADIUS_TILES + 3.0


func test_a_scout_commits_to_a_distant_blossom_beyond_close_sensing_range():
	var world := StubFlowerWorld.new()
	var far_position := Vector2(_BEYOND_CLOSE_SENSE_TILES * float(TerrainRenderer.TILE_SIZE), 0)
	world.blossoms = [{"position": far_position, "species": "cherry", "nectar": 1.0}]
	_make_scout(world)

	var found := marker._sense_distant_food()
	assert_eq(found.get("position"), far_position)
	assert_eq(found.get("kind"), "blossom")


func test_a_scout_commits_to_a_distant_flower_beyond_close_sensing_range():
	var world := StubFlowerWorld.new()
	var far_position := Vector2(_BEYOND_CLOSE_SENSE_TILES * float(TerrainRenderer.TILE_SIZE), 0)
	world.flowers = [{"position": far_position, "species": "rose", "nectar": 1.0}]
	_make_scout(world)

	var found := marker._sense_distant_food()
	assert_eq(found.get("position"), far_position)
	assert_eq(found.get("kind"), "flower")


func test_distant_food_finds_nothing_beyond_the_wider_home_range():
	var world := StubFlowerWorld.new()
	var too_far := Vector2((BeeColony.FORAGE_RADIUS_TILES + 3.0) * float(TerrainRenderer.TILE_SIZE), 0)
	world.flowers = [{"position": too_far, "species": "rose", "nectar": 1.0}]
	_make_scout(world)

	assert_true(marker._sense_distant_food().is_empty())


func test_distant_food_finds_nothing_when_the_world_has_nothing_at_all():
	_make_scout(StubFlowerWorld.new())
	assert_true(marker._sense_distant_food().is_empty())


## Real superposition (see ScentField's own docstring: "a dense clump is a
## genuinely stronger signal... which gives butterflies and bees a reason to
## gather at meadows") -- an isolated bloom, however close, loses to a
## cluster whose COMBINED concentration outscores it, even when the cluster
## is individually farther away and each single bloom in it is weaker.
func test_a_scout_prefers_a_real_cluster_over_a_closer_lone_bloom():
	var world := StubFlowerWorld.new()
	var lone_but_closer := Vector2(_BEYOND_CLOSE_SENSE_TILES * float(TerrainRenderer.TILE_SIZE), 0)
	var cluster_center := Vector2(0, (_BEYOND_CLOSE_SENSE_TILES + 1.0) * float(TerrainRenderer.TILE_SIZE))
	var tile := float(TerrainRenderer.TILE_SIZE)
	# Same species (daisy, in bloom every growing season -- see
	# FlowerSpecies) for both, so clustering is the ONLY variable: a
	# species-strength mismatch (e.g. a summer-only rose scoring zero
	# against spring's default season) would "win" the assertion for the
	# wrong reason.
	world.flowers = [{"position": lone_but_closer, "species": "daisy", "nectar": 1.0}]
	for i in 5:
		world.flowers.append({
			"position": cluster_center + Vector2(float(i) * tile * 0.5, 0), "species": "daisy", "nectar": 1.0
		})
	_make_scout(world)

	var found := marker._sense_distant_food()
	# Whichever cluster member actually scores highest (not necessarily
	# cluster_center itself -- a more central member can out-score an edge
	# one), it must not be the closer, but lone and fainter, tulip.
	assert_ne(
		found.get("position"), lone_but_closer,
		"the real cluster should out-pull the closer lone bloom"
	)
	assert_almost_eq(
		found.get("position", Vector2.ZERO).distance_to(cluster_center), 0.0, tile * 2.5,
		"the winner should be one of the clustered blooms"
	)


## has_method("current_season") is defensive (mirrors has_method(
## "blossoms_near")): a world that predates/doesn't offer season reporting
## must never crash reaching for distant detection, and should still find a
## real flower (falling back to a default season for scoring) rather than
## refusing to look at all.
func test_distant_food_still_finds_a_flower_when_the_world_has_no_current_season_method():
	var world := MinimalFlowerWorld.new()
	var far_position := Vector2(_BEYOND_CLOSE_SENSE_TILES * float(TerrainRenderer.TILE_SIZE), 0)
	world.flowers = [{"position": far_position, "species": "rose", "nectar": 1.0}]
	_make_scout(world)

	var found := marker._sense_distant_food()
	assert_eq(found.get("position"), far_position)
	assert_eq(found.get("kind"), "flower")


func test_scouting_never_crashes_when_the_world_has_no_current_season_method():
	_make_scout(MinimalFlowerWorld.new())
	for i in 20:
		marker._process(0.05)
	assert_ne(marker.position, Vector2.ZERO)


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


# -- one marker serves both a honeybee hive AND a solitary wild nest ------
#
# See BeeForagerMarker._colony's own doc comment: WildBeePatch.
# record_forage_result shares BeeColony's own exact signature, so the
# identical round-trip mechanism serves a lone WildBeePatch resident
# too, not just a honeybee hive's own worker.

func test_a_successful_trip_also_feeds_a_wild_bee_patchs_resident_count():
	const WildBeePatch = preload("res://src/world/wild_bee_patch.gd")
	var biome := _all_grassland()
	var patch: WildBeePatch = null
	for seed_value in range(1, 200):
		patch = WildBeePatch.new(seed_value, WIDTH, HEIGHT, biome)
		if patch.nest_cells().size() > 0:
			break
	var cell: Vector2i = patch.nest_cells()[0]
	var world := _world_with_one_flower(Vector2(4, 0))
	marker.setup(world, patch, cell)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	assert_true(_run_until_freed())
	assert_gt(patch.forage_success_at(cell), 0.5, "the real trip should have fed the patch's own record")


func test_returning_with_no_colony_wired_up_still_frees_itself_without_crashing():
	var world := _world_with_one_flower(Vector2(4, 0))
	marker.setup(world, null, Vector2i.ZERO)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	assert_true(_run_until_freed())


# -- a retired hive/nest: the outcome of an in-flight trip is honestly -----
# -- lost, never silently deposited into an orphaned colony/patch ----------
#
# A forager holds a direct reference to its own BeeColony/WildBeePatch,
# set once at dispatch (see _colony's own doc comment) -- unlike this
# marker itself, EarthChunkManager._unload_chunk cannot free that object
# just by erasing its own dictionary entry; a forager already in flight
# keeps it alive and keeps flying regardless (this marker is parented on
# the persistent _entities_parent node, not chunk-scoped -- correct, see
# EarthChunkManager._unload_chunk's own doc comment). Without this guard,
# a successful trip would resolve against that exact same, now-orphaned
# object once the forager gets home -- see docs/concept/bees.md's
# "In-flight foragers survive an unload; their trip's outcome does not".

func test_a_retired_colonys_returning_forager_deposits_nothing_and_frees_itself():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var world := _world_with_one_flower(Vector2(4, 0))
	marker.setup(world, colony, cell)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	colony.mark_retired()  # its own hive's chunk unloaded mid-flight
	var before := colony.honey_stored_at(cell)
	assert_true(_run_until_freed())
	assert_almost_eq(
		colony.honey_stored_at(cell), before, 0.001,
		"a retired colony must never receive a deposit from an orphaned forager"
	)


func test_a_retired_wild_bee_patchs_returning_forager_touches_nothing():
	const WildBeePatch = preload("res://src/world/wild_bee_patch.gd")
	var biome := _all_grassland()
	var patch: WildBeePatch = null
	for seed_value in range(1, 200):
		patch = WildBeePatch.new(seed_value, WIDTH, HEIGHT, biome)
		if patch.nest_cells().size() > 0:
			break
	var cell: Vector2i = patch.nest_cells()[0]
	var world := _world_with_one_flower(Vector2(4, 0))
	marker.setup(world, patch, cell)
	marker.target_position = Vector2(4, 0)
	marker.hive_position = Vector2.ZERO
	marker.position = Vector2(3, 0)
	add_child_autofree(marker)
	patch.mark_retired()  # its own nest's chunk unloaded mid-flight
	var before := patch.forage_success_at(cell)
	assert_true(_run_until_freed())
	assert_almost_eq(
		patch.forage_success_at(cell), before, 0.001,
		"a retired patch's forage-success record must never be touched by an orphaned forager"
	)
