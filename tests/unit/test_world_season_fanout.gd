extends GutTest

## The season fan-out, as the RUNNING GAME actually gets it.
##
## SeasonalFoliage, GroundTint's `season_tint` uniform and
## IllustratedGrassPatch's blade tint were all built and are all green in
## their own unit tests -- and nothing in a real session ever pushed a value
## into any of them. The reported bug is exactly that: forcing winter gave
## bare trees standing on a bright summer lawn, in lush green grass, over
## green crop tops. The season was something that happened to
## IllustratedTree's four canopy frames and to nothing else.
##
## So the WIRING is what this file pins, not the tints themselves (those have
## test_seasonal_foliage.gd / test_ground_tint.gd). Same reasoning, and the
## same shape, as test_world_streaming_budget.gd: a feature that is green in
## its own unit test and invisible while playing is not done.
##
## Kept as its own tiny file (bare nodes, no chunk streaming) so it runs in
## seconds rather than living in test_earth_chunk_manager.gd, which takes
## ten-plus minutes.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D

## A tint no season could produce by accident, so a passing assertion cannot
## be the default Color.WHITE sitting there untouched.
const PROBE_TINT := Color(0.25, 0.5, 0.75)


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## The body of World._client_process, read straight from source -- the
## authority on what the running game actually does every frame. Same
## technique as test_world_streaming_budget.gd's _ready_body().
func _client_process_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _client_process(")
	assert_gt(start, -1, "World._client_process should still exist")
	var body_end := source.find("\nfunc ", start + 1)
	if body_end == -1:
		body_end = source.length()
	return source.substr(start, body_end - start)


## The manager owns every green thing that is not the terrain layer itself,
## so it needs a fan-out of its own -- the same "live value pushed into a
## shared uniform every tick" shape set_wind_strength/set_sun_position
## already have.
func test_the_manager_pushes_the_season_onto_the_tall_grass_blades():
	manager.set_season_tint(PROBE_TINT)

	assert_eq(
		manager._illustrated_grass.material().get_shader_parameter("season_tint"),
		Vector3(PROBE_TINT.r, PROBE_TINT.g, PROBE_TINT.b),
		"tall grass kept rendering high summer in deep winter"
	)


## Held as well as forwarded: wild-crop markers are refreshed on their own
## cadences (the next step_wild_crops tick, and chunk load), so the last
## pushed season has to still be there when they ask for it.
func test_the_manager_remembers_the_season_for_the_things_refreshed_later():
	manager.set_season_tint(PROBE_TINT)

	assert_eq(manager._season_tint, PROBE_TINT)


## The default is identity, so a manager nobody has pushed a season into
## renders exactly today's picture rather than a black one.
func test_an_unpushed_manager_tints_nothing():
	assert_eq(manager._season_tint, Color.WHITE)


## The line that makes the whole chain visible. Without it every setter above
## is dead code and the ground still renders high summer in deep winter.
func test_the_client_frame_pushes_the_season_to_the_ground_and_the_chunk_manager():
	var body := _client_process_body()

	assert_string_contains(
		body,
		"_ground_tint.set_season_tint(",
		"the terrain layer's own material never learns the season"
	)
	assert_string_contains(
		body,
		"_chunk_manager.set_season_tint(",
		"grass and crops never learn the season"
	)


## ...off the same world clock every other season reader uses, so the lawn
## and the canopy above it can never disagree about the month. A frame-local
## clock of its own here is exactly how the snow ended up lying in summer
## sunshine (see step_snow's comment).
func test_the_frame_reads_the_season_off_the_shared_world_clock():
	assert_string_contains(
		_client_process_body(),
		"SeasonalFoliage.tint_for_world_age(_chunk_manager.world_age_seconds())"
	)


## The premise the two source assertions above rest on: that really is a
## function of the world clock, and it really does say something different in
## January than in July. If this ever stopped being true the wiring tests
## would be pinning a no-op.
func test_the_shared_clock_actually_says_something_different_in_winter():
	var cycle := preload("res://src/world/season_cycle.gd").new()
	var summer: float = cycle.seconds_until_season(0.0, "summer")
	var winter: float = cycle.seconds_until_season(0.0, "winter")

	assert_ne(
		SeasonalFoliage.tint_for_world_age(summer),
		SeasonalFoliage.tint_for_world_age(winter)
	)


## ## The canopy half of the same fan-out
##
## The ground learned the season off the world clock (above) while the canopy
## learned it off the SIMULATION: `TreeRenderer.season` was an empty string
## written from exactly one place, `EarthChunkManager._sync_tree_season`,
## reachable only from `step_fruiting`, reachable only from `World._process`
## behind `_owns_ecosystem_simulation()` and a ~1s accumulator.
##
## So the first awaited chunk load built its trees before that ever fired
## (no season at all -> IllustratedTree._FALLBACK_SEASON -> summer leaf: a
## fresh world flashed green trees in the snow), and a JOINED CLIENT, which
## owns no simulation, never ran it at all and kept a summer-green forest in
## every season for the whole session.
##
## See docs/concept/seasons.md, "The canopy is on the clock, not on the
## simulation".

const SeasonCycle = preload("res://src/world/season_cycle.gd")


func _clock_at(season: String) -> float:
	return SeasonCycle.new().seconds_until_season(0.0, season)


func _canopy_season() -> String:
	return manager._tree_renderer.canopy_state()["season"]


## Both randomize_world_age (New Game) and load_world_clock (Load Game) go
## through set_world_age_seconds, and both run BEFORE the first
## update()/update_with_progress call -- so dressing the trees here is what
## makes a chunk that loads in winter load bare trees, rather than summer
## ones that correct themselves a moment later.
func test_establishing_the_world_clock_dresses_the_trees_at_once():
	manager.set_world_age_seconds(_clock_at("winter"))

	assert_eq(
		_canopy_season(),
		"winter",
		"the trees were still waiting on a fruiting tick to learn the season"
	)


## No fruiting tick, no ecology step, nothing simulated at all -- just time
## passing, which is the only thing a canopy actually depends on.
func test_advancing_the_clock_alone_dresses_the_trees():
	manager.set_world_age_seconds(0.0)
	manager.advance_world_age(_clock_at("winter"))

	assert_eq(_canopy_season(), "winter")


## /season skips the clock forward without going through
## set_world_age_seconds (see jump_to_season), so it needs the push of its
## own -- forcing winter and watching the wood stay green for a second is the
## exact report this whole section exists for.
func test_a_season_jump_dresses_the_trees_too():
	manager.set_world_age_seconds(0.0)
	assert_true(manager.jump_to_season("winter"), "/season winter should have moved")

	assert_eq(_canopy_season(), "winter")


## The line that makes it true while playing, on EVERY peer: _client_process
## runs for host and joined client alike, unlike the ecology block in
## _process. Same shape as the ground-tint assertion above -- the canopy and
## the lawn are pushed from the same frame, off the same clock.
func test_the_client_frame_dresses_the_canopy_as_well_as_the_ground():
	assert_string_contains(
		_client_process_body(),
		"_chunk_manager.sync_tree_season(",
		"the canopy season still depends on owning the simulation"
	)


## The premise the assertion above rests on: a joined client really does own
## no simulation, so anything pushed only from the owns-gated block in
## _process never happens there at all.
func test_a_joined_client_owns_no_simulation_and_so_cannot_be_pushed_from_one():
	assert_false(
		World.owns_ecosystem_simulation_for(false, true, false),
		"a joined client is not the simulation authority"
	)


## Cheap enough to sit in a per-frame push: the quantised season/turn
## signature guard means a canopy rebuild happens a handful of times per
## in-game year, not once a frame.
func test_syncing_the_same_moment_twice_is_a_no_op():
	manager.set_world_age_seconds(_clock_at("winter"))
	var before: String = manager._last_tree_season

	manager.sync_tree_season()

	assert_eq(manager._last_tree_season, before)
	assert_ne(before, "", "the guard never recorded the season it dressed")


## ## One schedule, not two
##
## step_fruiting redraws the canopies of the trees near the player (it has to
## -- the crop hanging on them is part of the same texture), and it used to
## derive the season for that redraw ITSELF: the calendar name plus its own
## SeasonTransition call, per tree. That is a second answer to "which canopy
## is this tree wearing", and once the canopy moved onto TreePhenology's
## schedule (see docs/concept/seasons.md, "Winter stays bare") the two answers
## stop agreeing -- the trees within the fruiting radius would wear a
## different year from the wood around them.
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")


func _tree_the_player_is_standing_next_to() -> ChoppableTree:
	var tree := ChoppableTree.new()
	var sprite := Sprite2D.new()
	tree.add_child(sprite)
	tree.bind_canopy(sprite)
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i.ZERO] = [tree]
	return tree


func test_the_fruiting_tick_draws_the_canopy_on_the_same_schedule_as_the_wood():
	var tree := _tree_the_player_is_standing_next_to()
	# The first instant of spring: the calendar says spring, the canopy is
	# still bare wood, and those two disagreeing is the whole point.
	manager.set_world_age_seconds(_clock_at("spring"))

	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, Vector2.ZERO)

	assert_eq(
		tree.current_season(),
		_canopy_season(),
		"the tree beside the player wore a different year from the wood behind it"
	)
	assert_eq(tree.current_season(), "winter", "blossom on the first day of spring")
