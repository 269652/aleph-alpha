extends GutTest

## NpcMarker: the cheap local FSM half of docs/concept/npc.md's "Planning
## architecture" -- walks toward wherever its current schedule entry's
## location_tag resolves to (home / a shared village landmark / a personal
## workspot for occupations without a dedicated building yet), zero planner
## calls mid-day. Deliberately much lighter than CreatureMarker/FishMarker's
## AI -- just "walk toward today's plan".

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const CharacterView = preload("res://scenes/character_view.gd")

const TILE_SIZE := 16


## Counts real plan_day calls -- the FakeNpcPlanner in production returns the
## SAME schedule regardless of day_index, so a test can't tell "replanned
## and got the same answer" from "never replanned at all" by inspecting the
## resulting schedule alone. Records every day_index it was asked for.
class CountingPlanner:
	extends NpcPlanner.Planner
	var call_count := 0
	var days_asked_for: Array = []

	func plan_day(_identity: NpcIdentity, day_index: int) -> Array:
		call_count += 1
		days_asked_for.append(day_index)
		return [
			{"time_block": "morning", "location_tag": "home", "activity": "idle"},
			{"time_block": "midday", "location_tag": "home", "activity": "idle"},
			{"time_block": "evening", "location_tag": "home", "activity": "idle"},
			{"time_block": "night", "location_tag": "home", "activity": "sleep"},
		]


## Always returns the same caller-supplied schedule, regardless of day_index
## -- for a test whose own real travel time (see WALK_SPEED vs. the distance
## being crossed) unavoidably spans a real day rollover, but whose actual
## intent has nothing to do with day-rollover replanning at all (e.g.
## resolving a location tag). The default FakeNpcPlanner would otherwise
## silently replace the test's own injected schedule the moment a rollover
## fires, now that day-rollover replanning is real (see this file's own
## "day-rollover replanning" section).
class FixedPlanner:
	extends NpcPlanner.Planner
	var _schedule: Array

	func _init(fixed_schedule: Array) -> void:
		_schedule = fixed_schedule

	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		return _schedule


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


# -- day-rollover replanning (docs/progress.md's Interrupt/Replan Handling
# row: "today's schedule always runs to completion and only re-plans on day
# rollover") -- that claim was actually FALSE: _day_index was declared but
# never incremented anywhere, and `schedule` was only ever computed once,
# the first time it was empty, and never cleared again -- so a real NPC's
# plan_day() was called exactly ONCE per NPC for their entire existence,
# not once per in-game day as every doc comment in this file claims. -----

func test_plan_day_is_called_again_after_a_full_simulated_day_elapses():
	var planner := CountingPlanner.new()
	marker.set_planner(planner)

	marker._process(1.0)  # first-ever plan (schedule starts empty)
	assert_eq(planner.call_count, 1, "the premise: the very first process() call must plan once")

	# Advance past one full simulated day (NpcMarker.SECONDS_PER_SIMULATED_DAY)
	# without crossing a second one.
	marker._process(NpcMarker.SECONDS_PER_SIMULATED_DAY + 1.0)

	assert_eq(planner.call_count, 2, "a full simulated day passing must trigger exactly one real re-plan")
	assert_eq(planner.days_asked_for, [0, 1], "the second plan must ask for day 1, not repeat day 0")


func test_plan_day_is_not_called_again_within_the_same_simulated_day():
	var planner := CountingPlanner.new()
	marker.set_planner(planner)

	marker._process(1.0)
	assert_eq(planner.call_count, 1)

	# Several more process() calls, still comfortably inside day 0.
	for _i in 10:
		marker._process(1.0)

	assert_eq(planner.call_count, 1, "must not re-plan every frame -- only on an actual day rollover")


func test_multiple_day_rollovers_each_trigger_exactly_one_replan():
	var planner := CountingPlanner.new()
	marker.set_planner(planner)
	marker._process(1.0)

	marker._process(NpcMarker.SECONDS_PER_SIMULATED_DAY)  # -> day 1
	marker._process(NpcMarker.SECONDS_PER_SIMULATED_DAY)  # -> day 2

	assert_eq(planner.call_count, 3)
	assert_eq(planner.days_asked_for, [0, 1, 2])


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
	var fixed_schedule := [
		{"time_block": "morning", "location_tag": "field", "activity": "work"},
		{"time_block": "midday", "location_tag": "field", "activity": "work"},
		{"time_block": "evening", "location_tag": "field", "activity": "work"},
		{"time_block": "night", "location_tag": "field", "activity": "work"},
	]
	marker.schedule = fixed_schedule
	# The 200s loop below unavoidably spans a real day rollover (WALK_SPEED
	# vs. the distance from (0,0) to workspot_position alone takes ~72s --
	# already past SECONDS_PER_SIMULATED_DAY) -- pin the planner so that
	# real, now-correctly-firing rollover replan keeps returning this exact
	# schedule instead of the default FakeNpcPlanner's occupation-based one
	# (see FixedPlanner's own doc comment).
	marker.set_planner(FixedPlanner.new(fixed_schedule))
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


# -- urgent hunger interrupts the schedule (docs/progress.md's Interrupt/
# Replan Handling row: "a need crossing a threshold") -- NpcEconomy.step
# already reacts to is_hungry() by transacting food through the market
# (see test_process_advances_hunger_through_the_bound_economy's own
# neighbors), but that is a pure background abstraction: `pixel_position`
# isn't checked against anywhere specific, so a starving NPC still just
# visibly walks wherever their ORDINARY schedule says (e.g. standing at a
# workspot all day) while their hunger silently resolves off-screen. This
# makes the VISIBLE behavior react too -- an NPC reads as ignoring their
# own urgent need otherwise.

func test_urgent_hunger_redirects_the_npc_toward_the_well_regardless_of_schedule():
	var market := VillageMarket.new()
	marker.setup_economy(market)
	# Scheduled to be at the (distant) workspot all day -- with no interrupt,
	# the NPC would walk there and stay, ignoring hunger entirely.
	marker.schedule = [
		{"time_block": "morning", "location_tag": "workspot", "activity": "work"},
		{"time_block": "midday", "location_tag": "workspot", "activity": "work"},
		{"time_block": "evening", "location_tag": "workspot", "activity": "work"},
		{"time_block": "night", "location_tag": "workspot", "activity": "work"},
	]
	marker.economy.needs.hunger = 1.0  # unambiguously past HUNGRY_THRESHOLD
	assert_true(marker.economy.needs.is_hungry(), "the premise: hunger must actually read as urgent")
	var well: Vector2 = marker.landmarks["well"]
	var before_distance := marker.position.distance_to(well)

	marker._process(0.5)

	assert_lt(
		marker.position.distance_to(well), before_distance,
		"an urgently hungry NPC must move toward the well, not their scheduled workspot"
	)


func test_hunger_below_the_urgent_threshold_does_not_interrupt_the_schedule():
	var market := VillageMarket.new()
	marker.setup_economy(market)
	marker.schedule = [
		{"time_block": "morning", "location_tag": "workspot", "activity": "work"},
		{"time_block": "midday", "location_tag": "workspot", "activity": "work"},
		{"time_block": "evening", "location_tag": "workspot", "activity": "work"},
		{"time_block": "night", "location_tag": "workspot", "activity": "work"},
	]
	marker.economy.needs.hunger = 0.0  # freshly fed, not urgent
	var workspot: Vector2 = marker.workspot_position
	var before_distance := marker.position.distance_to(workspot)

	marker._process(0.5)

	assert_lt(
		marker.position.distance_to(workspot), before_distance,
		"an NPC who isn't urgently hungry must still follow their ordinary schedule"
	)


func test_an_npc_with_no_economy_is_unaffected_by_the_hunger_interrupt():
	# economy is null until setup_economy is called (see NpcMarker's own doc
	# comment) -- must not crash, and must fall back to the ordinary schedule.
	assert_null(marker.economy)
	marker.schedule = [
		{"time_block": "morning", "location_tag": "workspot", "activity": "work"},
		{"time_block": "midday", "location_tag": "workspot", "activity": "work"},
		{"time_block": "evening", "location_tag": "workspot", "activity": "work"},
		{"time_block": "night", "location_tag": "workspot", "activity": "work"},
	]
	var workspot: Vector2 = marker.workspot_position
	var before_distance := marker.position.distance_to(workspot)

	marker._process(0.5)

	assert_lt(marker.position.distance_to(workspot), before_distance)


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


# -- instruction scripts (docs/concept/npc_instructions.md "Execution /
# wiring"): NpcMarker.instruction_script, when assigned, overrides the
# planner-produced schedule entry for this tick -- via
# NpcInstructionEvaluator.evaluate -- falling back to the ordinary
# NpcSchedule.current_entry path when unset, or when the evaluator finds no
# matching rule that tick. --

const NpcInstructionParser = preload("res://src/world/npc_instruction_parser.gd")


func _instruction_ast(source: String) -> Dictionary:
	var parser := NpcInstructionParser.new()
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


func test_default_instruction_script_is_null():
	assert_null(marker.instruction_script)


## Regression: an NPC with no instruction_script assigned must walk the
## planner-produced entry exactly as before this change -- the same
## landmark-resolution behavior test_resolves_a_landmark_tag_to_the_shared_
## landmark_position already pins, just re-asserted here alongside the new
## instruction-script tests as the explicit "untouched" proof.
func test_no_instruction_script_walks_the_planner_entry_unchanged():
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


func test_instruction_script_overrides_the_planner_entry_when_a_rule_matches():
	marker.instruction_script = _instruction_ast(
		"instruct \"X\" {\n"
		+ "    otherwise: haul(wood, well)\n"
		+ "}"
	)
	# The planner would send this NPC to "stall"; the instruction script's
	# unconditional otherwise rule must win instead, sending it to "well".
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	for i in 200:
		marker._process(1.0)
	assert_lt(marker.position.distance_to(marker.landmarks["well"]), 1.0)
	assert_gt(marker.position.distance_to(marker.landmarks["stall"]), 1.0)


func test_instruction_script_falls_back_to_the_planner_entry_when_no_rule_matches():
	marker.instruction_script = _instruction_ast(
		"instruct \"X\" {\n"
		+ "    if inventory_at_least(wood, 999): haul(wood, well)\n"
		+ "}"
	)
	# No otherwise, and the lone condition never holds (this test never sets
	# marker.inventory, so the built frame reads its default empty {}) --
	# the evaluator returns null every tick, so the planner's own "stall"
	# entry must still win.
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


# -- per-NPC inventory (docs/concept/npc_instructions.md, closing the
# "inventory_at_least cannot yet be truthfully exercised" gap): NpcMarker
# carries a real `inventory` Dictionary (item_id -> int count), read
# honestly by _instruction_frame() instead of always reporting {}. --

func test_default_inventory_is_an_empty_dictionary():
	assert_eq(marker.inventory, {})


## Proves instruction_at_least now reads a real, non-empty NpcMarker.inventory
## -- a rule gated on real held wood fires because the NPC genuinely holds
## enough, not because the frame was stubbed.
func test_instruction_at_least_reads_a_real_non_empty_inventory():
	marker.inventory = {"wood": 25}
	marker.instruction_script = _instruction_ast(
		"instruct \"X\" {\n"
		+ "    if inventory_at_least(wood, 20): haul(wood, well)\n"
		+ "    otherwise: haul(wood, gate)\n"
		+ "}"
	)
	# The planner would send this NPC to "stall"; with 25 real held wood
	# (>= 20), the first rule must win and send it to "well" instead of
	# falling through to "gate".
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	for i in 200:
		marker._process(1.0)
	assert_lt(marker.position.distance_to(marker.landmarks["well"]), 1.0)
	assert_gt(marker.position.distance_to(marker.landmarks["gate"]), 1.0)


## The same script, with too little real held wood, must fall through to
## the "otherwise" rule instead -- proves the frame's inventory count is the
## real number, not just "non-empty".
func test_instruction_at_least_fails_when_real_inventory_is_below_the_threshold():
	marker.inventory = {"wood": 5}
	marker.instruction_script = _instruction_ast(
		"instruct \"X\" {\n"
		+ "    if inventory_at_least(wood, 20): haul(wood, well)\n"
		+ "    otherwise: haul(wood, gate)\n"
		+ "}"
	)
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	for i in 200:
		marker._process(1.0)
	assert_lt(marker.position.distance_to(marker.landmarks["gate"]), 1.0)
