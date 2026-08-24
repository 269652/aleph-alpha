extends GutTest

## NpcMarker: the cheap local FSM half of docs/concept/npc.md's "Planning
## architecture" -- walks toward wherever its current schedule entry's
## location_tag resolves to (home / a shared village landmark / a personal
## workspot for occupations without a dedicated building yet), zero planner
## calls mid-day. Deliberately much lighter than CreatureMarker/FishMarker's
## AI -- just "walk toward today's plan".

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const CharacterView = preload("res://scenes/character_view.gd")

const TILE_SIZE := 16


## Duck-typed world: every tile is the same biome unless overridden, same
## shape as CreatureMarker's test stub. Also exposes NpcProduction's real
## weather-tied accessors (settable canned values) so an economy-wiring test
## can simulate a producer actually gathering real food.
class StubWorld:
	var biome := "grassland"
	var vegetation_density := 0.6
	var herbivore_population := 10.0
	var fish_population := 8.0
	func biome_at_global(_x: int, _y: int) -> String:
		return biome
	func vegetation_density_near(_pos: Vector2) -> float:
		return vegetation_density
	func herbivore_population_near(_pos: Vector2) -> float:
		return herbivore_population
	func fish_population_near(_pos: Vector2) -> float:
		return fish_population


var marker: NpcMarker
var _extra: Array = []


func before_each():
	marker = NpcMarker.new()
	marker.identity = NpcIdentity.new(1)
	marker.home_position = Vector2(1000, 1000)
	marker.workspot_position = Vector2(1000, 1050)
	marker.landmarks = {"well": Vector2(900, 900), "stall": Vector2(950, 900), "gate": Vector2(850, 900)}
	marker.position = Vector2(1000, 1000)
	add_child(marker)


func after_each():
	remove_child(marker)
	marker.free()
	for node in _extra:
		if is_instance_valid(node):
			node.free()
	_extra = []


func _bind_real_view() -> CharacterView:
	var view: CharacterView = CharacterViewScene.instantiate()
	add_child(view)
	_extra.append(view)
	marker.bind_character_view(view)
	return view


func test_lazily_generates_a_schedule_on_first_process():
	assert_eq(marker.schedule.size(), 0)
	marker._process(0.1)
	assert_gt(marker.schedule.size(), 0)


func test_position_moves_toward_the_resolved_target():
	# Force a schedule where "night" (a reachable hour) sends the NPC home,
	# and start away from home so movement is observable.
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.position = Vector2(1000, 1200)  # far from home_position (1000, 1000)
	var before_distance: float = marker.position.distance_to(marker.home_position)

	marker._process(0.5)

	assert_lt(marker.position.distance_to(marker.home_position), before_distance)


func test_resolves_a_landmark_tag_to_the_shared_landmark_position():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	for i in 200:
		marker._process(1.0)
	assert_lt(marker.position.distance_to(marker.landmarks["stall"]), 1.0)


## An occupation whose work tag isn't one of the 3 shared landmarks (e.g.
## "field") falls back to the NPC's own personal workspot rather than
## crashing on a missing landmark.
func test_resolves_a_non_landmark_work_tag_to_the_personal_workspot():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "field", "activity": "work"},
		{"time_block": "midday", "location_tag": "field", "activity": "work"},
		{"time_block": "evening", "location_tag": "field", "activity": "work"},
		{"time_block": "night", "location_tag": "field", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	for i in 200:
		marker._process(1.0)
	assert_lt(marker.position.distance_to(marker.workspot_position), 1.0)


# -- walk/swim animation (bound CharacterView, see bind_character_view) -----
#
# The view was bound (VillageRenderer._build_npc) but nothing ever actually
# drove it after that -- _process moved the marker every frame without ever
# calling set_facing/is_moving/set_movement_state on the view, so every
# villager's walk-cycle sat frozen in IDLE despite visibly moving (reported:
# "NPCs don't have walk or swim animation").

func test_moving_toward_a_target_sets_is_moving_and_faces_the_travel_direction():
	var view := _bind_real_view()
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "idle"},
	]
	marker.position = Vector2(1000, 1200)  # far from home_position (1000, 1000) -- straight up

	marker._process(0.1)

	assert_true(view.is_moving)
	assert_eq(view.movement_state, CharacterView.MovementState.WALKING)
	assert_eq(view.facing, CharacterView.Facing.UP)


func test_standing_still_at_the_target_leaves_the_view_idle():
	var view := _bind_real_view()
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "idle"},
	]
	marker.position = marker.home_position  # already there -- nothing to walk toward

	marker._process(0.1)

	assert_false(view.is_moving)
	assert_eq(view.movement_state, CharacterView.MovementState.IDLE)


func test_standing_on_water_sets_the_view_to_swimming():
	var view := _bind_real_view()
	var world := StubWorld.new()
	world.biome = "ocean"
	marker.setup(world, TILE_SIZE)
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "idle"},
	]
	marker.position = marker.home_position

	marker._process(0.1)

	assert_eq(view.movement_state, CharacterView.MovementState.SWIMMING)


## Without setup() (no world), an NPC has no way to check the tile it's
## standing on -- must default to land behavior, not crash.
func test_without_setup_never_crashes_and_defaults_to_land_behavior():
	var view := _bind_real_view()
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "idle"},
	]
	marker.position = marker.home_position
	marker._process(0.1)
	assert_ne(view.movement_state, CharacterView.MovementState.SWIMMING)


func test_no_bound_view_never_crashes():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
	]
	marker.position = Vector2(1000, 1200)
	marker._process(0.1)  # no bound CharacterView -- must not error
	assert_ne(marker.position, Vector2(1000, 1200), "should still walk normally with no view bound")


# -- needs/local production economy (docs/concept/npc.md "Needs and the
# local production economy") -- NpcMarker carries zero needs/economy state
# by default (no setup_economy call); _process must still never crash. --

const NpcEconomy = preload("res://src/world/npc_economy.gd")
const VillageMarket = preload("res://src/world/village_market.gd")


func test_process_without_economy_never_crashes():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
	]
	marker._process(0.1)  # no setup_economy call -- must not error
	assert_null(marker.economy)


func test_setup_economy_builds_an_economy_from_this_villagers_identity():
	var market := VillageMarket.new()
	marker.setup_economy(market)
	assert_not_null(marker.economy)
	assert_eq(marker.economy.occupation, marker.identity.occupation)
	assert_same(marker.economy.market, market)


func test_process_advances_hunger_through_the_bound_economy():
	var market := VillageMarket.new()
	marker.setup_economy(market)
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	var before: float = marker.economy.needs.hunger
	marker._process(1.0)
	assert_gt(marker.economy.needs.hunger, before)


## The full real production loop through NpcMarker's own _process: a hunter
## whose "work" schedule entry is active gathers real food (via the world's
## herbivore_population_near) into the shared market and earns real gold.
func test_a_working_hunter_gathers_real_food_through_process():
	var hunter_identity: NpcIdentity
	for seed_value in range(50):
		var candidate := NpcIdentity.new(seed_value)
		if candidate.occupation == "hunter":
			hunter_identity = candidate
			break
	assert_not_null(hunter_identity, "precondition: expected a hunter within 50 seeds")
	marker.identity = hunter_identity

	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	var market := VillageMarket.new()
	marker.setup_economy(market)
	marker.schedule = [
		{"time_block": "morning", "location_tag": "hunting_ground", "activity": "work"},
		{"time_block": "midday", "location_tag": "hunting_ground", "activity": "work"},
		{"time_block": "evening", "location_tag": "well", "activity": "socialize"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.position = marker.workspot_position  # already at the work tag's resolved spot

	for i in 300:
		marker._process(1.0)

	assert_gt(market.total_stock(), 0.0)
	assert_gt(marker.economy.wallet.balance, 0)
