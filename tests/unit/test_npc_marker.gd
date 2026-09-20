extends GutTest

const NpcSchedule = preload("res://src/world/npc_schedule.gd")

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


## Pinned to a trade whose own work tag is one of this fixture's landmarks:
## the run below spans a day rollover, so whatever the planner says for this
## villager's trade is what actually gets walked, and the tag under test
## would otherwise be replaced by their own.
func test_resolves_a_landmark_tag_to_the_shared_landmark_position():
	marker.identity.occupation = "merchant"
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	assert_lt(_closest_approach(marker, marker.landmarks["stall"]), 1.0)


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
const Ethogram = preload("res://src/gameplay/ethogram.gd")


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
	# A REAL meal on the stall, and the gold for it: the hunger interrupt
	# only fires when there is actually something to buy at the end of the
	# walk (NpcEconomy.can_obtain_a_meal). These tests have always meant
	# "a villager who must buy goes and buys"; the empty market they used to
	# build was incidental, and with it the villager now correctly keeps
	# working rather than queueing at a stall with nothing on it.
	_stock_the_stall(market)
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

	# Long enough to earn REAL GOLD, derived from the real rate rather than
	# written as a round 300 seconds. Half this villager's day is scheduled
	# as work (two of the four blocks above), and a producer's take-home is
	# a share of what they earn (VillageWages), so a single unit's gold
	# rounds away to nothing. The drip is each resource's own renewal now
	# (docs/concept/settlement_food_calibration.md), so a fixed second count
	# silently gathers nothing the moment that is retuned.
	# The PEAK, not the closing balance: a villager who can buy a meal spends
	# what they earn on one (NpcEconomy/VillageMarket.buy_meal), so reading
	# the purse at an arbitrary moment measures whether they had just eaten,
	# not whether they ever earned. Earning and then spending is still
	# earning.
	var peak_gold := 0
	for i in _working_seconds_to_gather("hunter", 20.0, world):
		marker._process(1.0)
		peak_gold = maxi(peak_gold, marker.economy.wallet.balance)

	assert_gt(market.total_stock(), 0.0)
	assert_gt(peak_gold, 0, "a working hunter really earns")


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
## Pinned to a trade whose work tag is a real shared landmark. Seed 1's
## occupation is not this test's subject -- it is about what an instruction
## script does and does not override -- and the day-rollover replan means
## whatever the planner says for that trade is what actually gets walked.
func test_no_instruction_script_walks_the_planner_entry_unchanged():
	marker.identity.occupation = "merchant"
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	assert_lt(_closest_approach(marker, marker.landmarks["stall"]), 1.0)


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
	marker.identity.occupation = "merchant"
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
	assert_lt(_closest_approach(marker, marker.landmarks["stall"]), 1.0)


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


# -- hidden while home (docs/concept/building.md "Buildings are entities;
# interiors are scenes": home_position is now a real house's doorstep, not
# a bare marker -- a villager idling/sleeping in plain view on their own
# doorstep every day/night read as "sleeping outside the front door".
# Mirrors EarthChunkManager's existing conversion-worker "hidden while
# working inside a structure" pattern, one per house instead of a table of
# structures.) ----------------------------------------------------------

func test_an_npc_who_has_arrived_home_on_a_home_tagged_entry_becomes_invisible():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.position = marker.home_position  # already arrived
	marker._process(0.1)
	assert_false(marker.visible)


func test_an_npc_still_walking_toward_home_stays_visible():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.position = Vector2(1000, 1200)  # far from home_position (1000, 1000)
	marker._process(0.1)
	assert_true(marker.visible, "must stay visible mid-stride, not vanish before arriving")


## Standing AT a shared landmark position must never trip the hidden check --
## it is keyed on the "home" tag specifically, not merely "arrived somewhere".
func test_an_npc_at_a_work_landmark_stays_visible():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = marker.landmarks["stall"]
	marker._process(0.1)
	assert_true(marker.visible)


func test_an_npc_reappears_once_the_schedule_moves_off_home():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.position = marker.home_position
	marker._process(0.1)
	assert_false(marker.visible, "precondition: hidden while home")

	marker.schedule = [
		{"time_block": "morning", "location_tag": "field", "activity": "work"},
		{"time_block": "midday", "location_tag": "field", "activity": "work"},
		{"time_block": "evening", "location_tag": "field", "activity": "work"},
		{"time_block": "night", "location_tag": "field", "activity": "work"},
	]
	marker._process(0.1)
	assert_true(marker.visible, "must reappear the same frame the schedule leaves home")


## The urgent-hunger interrupt always redirects to "well" (see the hunger
## section above), so a hungry NPC who happened to be standing at home when
## hunger crossed the threshold must reappear rather than staying hidden
## while walking to eat.
func test_hunger_interrupt_while_home_makes_the_npc_visible_again():
	var market := VillageMarket.new()
	marker.setup_economy(market)
	_stock_the_stall(market)  # see _stock_the_stall -- there must be a meal to walk to
	marker.economy.needs.hunger = 1.0  # unambiguously past HUNGRY_THRESHOLD
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.position = marker.home_position
	marker._process(0.1)
	assert_true(marker.visible, "a hungry NPC redirected to the well must not stay hidden at home")


## is_at_home(): the same "arrived home on a home-tagged entry" state the
## hide rule above reads, exposed so the world can find the villager whose
## house the player just walked into ("Residents inside", docs/concept/
## building.md) and so the doorstep scans can skip a villager who is
## actually inside.
func test_is_at_home_is_true_exactly_when_hidden_at_home():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.position = Vector2(1000, 1200)
	marker._process(0.1)
	assert_false(marker.is_at_home(), "still walking home")
	marker.position = marker.home_position
	marker._process(0.1)
	assert_true(marker.is_at_home())
	assert_false(marker.visible)


func test_is_at_home_is_false_at_a_landmark_even_when_standing_still():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = marker.landmarks["stall"]
	marker._process(0.1)
	assert_false(marker.is_at_home())


# -- a hungry producer works rather than queuing at an empty well ----------
#
# The hunger interrupt above sends any hungry villager to the well. Measured
# live (tools/probe_village_hunting.gd): a real hunter went hungry about
# twelve seconds in, with an empty village market and an empty purse, and
# then never worked again for the remaining 227 simulated seconds -- because
# the interrupt fires every frame, and not working is exactly what stops
# them producing the food they were sent to buy. The well had nothing on it
# and never would.
#
# A producer standing in a region that still yields does not need the
# market: working IS eating for them (see NpcEconomy's free self-feed, which
# this reuses rather than restates). So the interrupt is for villagers who
# have to BUY, which is what npc.md describes it as.


func _producer_marker_at_work(occupation: String, world: StubWorld) -> void:
	marker.identity.occupation = occupation
	marker.setup(world, TILE_SIZE)
	var market := VillageMarket.new()
	marker.setup_economy(market)
	_stock_the_stall(market)
	marker.schedule = [
		{"time_block": "morning", "location_tag": "workspot", "activity": "work"},
		{"time_block": "midday", "location_tag": "workspot", "activity": "work"},
		{"time_block": "evening", "location_tag": "workspot", "activity": "work"},
		{"time_block": "night", "location_tag": "workspot", "activity": "work"},
	]
	marker.economy.needs.hunger = 1.0


func test_a_hungry_producer_keeps_working_instead_of_queuing_at_an_empty_well():
	var world := StubWorld.new()
	_producer_marker_at_work("hunter", world)
	var workspot := marker.workspot_position
	var before := marker.position.distance_to(workspot)

	marker._process(0.5)

	assert_lt(
		marker.position.distance_to(workspot), before,
		"a hungry hunter's food is in the woods, not on an empty stall"
	)


func test_a_hungry_producer_whose_region_has_collapsed_still_goes_to_the_well():
	# The famine chain stays intact: with nothing left to hunt there is
	# nothing to self-feed on, so the market is the only hope again.
	var world := StubWorld.new()
	world.herbivore_population = 0.0
	_producer_marker_at_work("hunter", world)
	var well: Vector2 = marker.landmarks["well"]
	var before := marker.position.distance_to(well)

	marker._process(0.5)

	assert_lt(marker.position.distance_to(well), before)


func test_a_hungry_non_producer_still_goes_to_the_well():
	var world := StubWorld.new()
	_producer_marker_at_work("blacksmith", world)
	var well: Vector2 = marker.landmarks["well"]
	var before := marker.position.distance_to(well)

	marker._process(0.5)

	assert_lt(marker.position.distance_to(well), before, "a blacksmith really does have to buy")


# -- a villager acts on what they need -------------------------------------
#
# Asked for directly: "improve the NPC AI Behaviour by an order of magnitude
# ... cater for their needs; stroll". See docs/concept/npc_social_life.md:
# the schedule says where a villager would BE, drives say what they DO, and
# a drive overrides the schedule's walk target exactly as the hunt and field
# overrides already do.

const VillagerBehavior = preload("res://src/gameplay/villager_behavior.gd")


## Puts one drive of the marker's own real needs past its threshold.
func _make_urgent(drive: String) -> void:
	marker.economy = NpcEconomy.new(1, marker.identity.occupation, null)
	marker.economy.needs.set_level(drive, 1.0)


func _quiet_every_need() -> void:
	marker.economy = NpcEconomy.new(1, marker.identity.occupation, null)
	for drive in marker.economy.needs.gains():
		marker.economy.needs.set_level(drive, 0.0)


func test_a_thirsty_villager_walks_to_the_well_not_their_workspot():
	_quiet_every_need()
	_make_urgent("thirst")
	var before := marker.position
	marker._process(0.5)
	assert_lt(
		marker.position.distance_to(marker.landmarks["well"]),
		before.distance_to(marker.landmarks["well"]),
		"a thirsty villager heads for the well"
	)


func test_a_tired_villager_goes_home():
	_quiet_every_need()
	marker.position = Vector2(900, 900)
	_make_urgent("rest")
	var before := marker.position
	marker._process(0.5)
	assert_lt(
		marker.position.distance_to(marker.home_position),
		before.distance_to(marker.home_position),
		"a tired villager heads home"
	)


## Drinking really answers the need, or a villager stands at the well
## forever: the well is reached, the drive falls, and the schedule gets its
## villager back.
func test_reaching_the_well_really_slakes_the_thirst():
	_quiet_every_need()
	_make_urgent("thirst")
	marker.position = marker.landmarks["well"]
	assert_gt(marker.economy.needs.gains()["thirst"], 0.0, "precondition: really thirsty")
	marker._process(0.5)
	assert_eq(marker.economy.needs.gains()["thirst"], 0.0, "a villager who reached the well drank")


func test_sleeping_at_home_really_answers_the_tiredness():
	_quiet_every_need()
	_make_urgent("rest")
	marker.position = marker.home_position
	marker._process(0.5)
	assert_eq(marker.economy.needs.gains()["rest"], 0.0, "a villager who got home rested")


## Pillar 2: with nothing pressing, the schedule still owns the villager.
func test_a_villager_with_no_urgent_need_still_keeps_their_schedule():
	_quiet_every_need()
	marker.schedule = [
		{"time_block": "morning", "location_tag": "gate", "activity": "work"},
		{"time_block": "midday", "location_tag": "gate", "activity": "work"},
		{"time_block": "evening", "location_tag": "gate", "activity": "work"},
		{"time_block": "night", "location_tag": "gate", "activity": "work"},
	]
	var before := marker.position
	marker._process(0.5)
	assert_lt(
		marker.position.distance_to(marker.landmarks["gate"]),
		before.distance_to(marker.landmarks["gate"]),
		"nothing pressing, so the schedule stands"
	)


# -- villagers meet, and a meeting takes real time -------------------------
#
# Asked for directly: "they should socialize; talk". Design pillar 4 of
# docs/concept/npc_social_life.md: if it happens, you can see it happen --
# two villagers stop walking, stand together and face each other for a real
# number of seconds. Invisible bookkeeping is not behaviour.


## A world that answers the one question a villager asks when looking for
## company, the same duck-typed shape every other _world hook here uses.
class StubNeighbourhood:
	var neighbour: NpcMarker = null
	func nearest_npc_near(_at: Vector2, max_distance: float, excluding = null) -> NpcMarker:
		if neighbour == null or neighbour == excluding:
			return null
		return neighbour if _at.distance_to(neighbour.position) <= max_distance else null


func _neighbour_at(at: Vector2) -> NpcMarker:
	var other := NpcMarker.new()
	other.identity = NpcIdentity.new(7)
	other.home_position = Vector2(2000, 2000)
	other.workspot_position = Vector2(2000, 2000)
	other.position = at
	add_child(other)
	_extra.append(other)
	var world := StubNeighbourhood.new()
	world.neighbour = other
	marker.setup(world, TILE_SIZE)
	return other


func test_a_lonely_villager_walks_toward_a_neighbour():
	_quiet_every_need()
	_make_urgent("company")
	var other := _neighbour_at(Vector2(1120, 1000))  # inside COMPANY_REACH_PX, outside talking range
	var before := marker.position
	marker._process(0.5)
	assert_lt(
		marker.position.distance_to(other.position), before.distance_to(other.position),
		"a lonely villager goes to find somebody"
	)


func test_reaching_a_neighbour_starts_a_real_conversation():
	_quiet_every_need()
	_make_urgent("company")
	var other := _neighbour_at(marker.position + Vector2(2, 0))
	marker._process(0.1)
	assert_true(marker.is_talking(), "they stopped to talk")
	assert_true(other.is_talking(), "and so did the other one -- a conversation has two sides")


func test_a_conversation_stops_them_both_walking():
	_quiet_every_need()
	_make_urgent("company")
	var other := _neighbour_at(marker.position + Vector2(2, 0))
	marker._process(0.1)
	var stood_at := marker.position
	var other_stood_at := other.position
	marker._process(0.25)
	other._process(0.25)
	assert_eq(marker.position, stood_at, "a villager mid-conversation does not wander off")
	assert_eq(other.position, other_stood_at, "and neither does the one they are talking to")


func test_a_conversation_really_ends():
	_quiet_every_need()
	_make_urgent("company")
	_neighbour_at(marker.position + Vector2(2, 0))
	marker._process(0.1)
	assert_true(marker.is_talking(), "precondition: talking")
	marker._process(NpcMarker.CONVERSATION_SECONDS + 0.1)
	assert_false(marker.is_talking(), "a conversation that never ended would freeze a villager forever")


func test_talking_is_what_answers_the_need_for_company():
	_quiet_every_need()
	_make_urgent("company")
	_neighbour_at(marker.position + Vector2(2, 0))
	assert_gt(marker.economy.needs.gains()["company"], 0.0, "precondition: lonely")
	marker._process(0.1)
	assert_eq(
		marker.economy.needs.gains()["company"], 0.0,
		"a villager who has just had a conversation is not lonely"
	)


## Real work against the real world outranks a need: a hunter mid-chase and
## a farmer in their own field are not pulled away to chat, or to drink, or
## to go home. Asserted on the rule itself rather than by staging a live
## hunt, because what the rule says is exactly "not free to answer".
func test_a_villager_busy_with_real_work_answers_no_need_at_all():
	_quiet_every_need()
	_make_urgent("company")
	_neighbour_at(marker.position + Vector2(2, 0))
	# Busy first: once a conversation has started it runs to its end (a
	# villager does not walk off mid-sentence), so asking the other way round
	# would be asking a talking villager whether they are busy.
	assert_null(
		marker._step_needs(0.1, false),
		"mid-chase or mid-field, a villager finishes the work first"
	)
	assert_false(marker.is_talking(), "and never started a conversation at all")
	assert_not_null(marker._step_needs(0.1, true), "but free, that same villager would go and talk")


# -- carrying a load to the store ------------------------------------------
#
# docs/concept/village_warehouse.md mechanism 3, "goods are carried in": the
# visible half of a warehouse. What a producer takes is in their hands until
# they have walked it to the door, so a village's stock arrives somewhere
# rather than appearing as a number.
#
# `warehouse_position` is null for every villager whose settlement has no
# store (a cramped site houses its people and goes without -- see the
# concept doc's own caveat under pillar 1), and such a villager keeps the
# direct deposit they always had.


## A villager with a store to carry to, hands already full. Credited
## through record_real_harvest rather than record_real_catch because that
## one is gated on being a PRODUCER, and this marker's occupation is
## whatever its seed gave it -- a blacksmith would have been handed nothing
## and the test would have passed vacuously on empty hands.
func _loaded_villager_at(store: Vector2) -> void:
	_quiet_every_need()
	marker.economy.market = VillageMarket.new()
	marker.warehouse_position = store
	marker.economy.carry_limit = NpcEconomy.CARRY_LIMIT
	marker.economy.record_real_harvest("wheat", int(NpcEconomy.CARRY_LIMIT))


func test_a_villager_with_full_hands_walks_to_the_store():
	var store := Vector2(700, 700)
	_loaded_villager_at(store)
	assert_almost_eq(marker.economy.burden(), 1.0, 0.0, "precondition: their hands really are full")
	var before := marker.position.distance_to(store)
	marker._process(0.5)
	assert_lt(marker.position.distance_to(store), before, "a loaded villager heads for the store")


## Reaching the door really puts the load down, or a villager stands at the
## warehouse forever holding it -- the same "arriving is what answers it"
## rule the well and the bed already run on.
func test_reaching_the_door_really_puts_the_load_down():
	_loaded_villager_at(Vector2(700, 700))
	var in_hand := marker.economy.carried_total()
	marker.position = marker.warehouse_position
	marker._process(0.1)
	assert_almost_eq(marker.economy.carried_total(), 0.0, 0.0001, "their hands are empty")
	assert_almost_eq(
		marker.economy.market.total_stock(), in_hand, 0.0001,
		"and the village has what they were carrying"
	)


func test_an_empty_handed_villager_is_left_to_their_schedule():
	_quiet_every_need()
	marker.economy.market = VillageMarket.new()
	marker.warehouse_position = Vector2(700, 700)
	marker.economy.carry_limit = NpcEconomy.CARRY_LIMIT
	assert_null(
		marker._step_needs(0.1, true),
		"carrying nothing is not an errand, however near the store is"
	)


## The trap this wiring sits over: BehaviorKernel reads a gate the caller
## never mentioned as WIDE OPEN, and burden is deliberately not on the
## villager drive clock, so NpcNeeds.gains() has never heard of it. A marker
## that forgot to publish what its villager is carrying would send every
## villager in sight of a store off to haul an imaginary load.
func test_the_marker_really_says_what_this_villager_is_carrying():
	_quiet_every_need()
	marker.economy.carry_limit = NpcEconomy.CARRY_LIMIT
	marker.warehouse_position = Vector2(700, 700)
	var context := marker._villager_context()
	assert_true(context.has(Ethogram.WAREHOUSE), "the store is where the load goes")
	assert_true(
		(context["drives"] as Dictionary).has(Ethogram.DRIVE_BURDEN),
		"a burden the marker never reports is a burden the kernel reads as full"
	)
	assert_almost_eq(float(context["drives"][Ethogram.DRIVE_BURDEN]), 0.0, 0.0)


func test_a_village_with_no_store_offers_a_villager_nowhere_to_carry_to():
	_quiet_every_need()
	assert_null(marker.warehouse_position, "precondition: no store by default")
	assert_false(marker._villager_context().has(Ethogram.WAREHOUSE))


## A real meal on the village stall and the gold to pay for it.
##
## The hunger interrupt only fires when there is something to buy at the end
## of the walk (NpcEconomy.can_obtain_a_meal, added after a real village was
## measured: a merchant hungry for 1589 of 1801 ticks with an empty purse
## spent every one of their 825 scheduled work ticks queueing at a well with
## nothing on it, so they never worked, never earned, and stayed hungry for
## ever). A test that means "a villager who must buy goes and buys" has to
## put something there to buy.
func _stock_the_stall(market) -> void:
	market.add_stock("fish", 5.0)
	if marker.economy != null:
		marker.economy.wallet.add(100)


## How many WALL-CLOCK seconds this villager needs to gather `units` whole
## food units, given that only part of their day is scheduled as work.
##
## Doubled because two of the four scheduled blocks are work: a villager who
## gathers for half their day needs twice the wall clock of one who gathers
## all of it.
## `gather_world` is the caller's own stub world, passed in rather than
## reached for: there is no `world` member on this suite, and referring to
## one made the WHOLE FILE fail to parse -- which GUT reports as a script it
## could not load and then runs nothing from, so every test in here was
## silently dropped rather than failing.
func _working_seconds_to_gather(occupation: String, units: float, gather_world) -> int:
	var NpcProduction = load("res://src/world/npc_production.gd")
	var per_second: float = NpcProduction.new().yield_per_second(
		occupation, gather_world, marker.position
	)
	if per_second <= 0.0:
		return 0
	return int(ceil(2.0 * units * NpcProduction.FOOD_UNIT / per_second)) + 1


## How close `target` ever gets to `destination` over a few days of walking.
##
## The closest APPROACH, not where they happen to be standing when the run
## ends: a day is sixty real seconds and the walk across a village is most of
## one, so where a villager is on any particular tick is as much about which
## block just turned as about where their tag resolves to. What these tests
## are actually about is that the tag resolves THERE -- that the villager
## really goes to it.
##
## It matters more now than it did: a village does not turn as one any more
## (NpcSchedule.personal_hour), so a fixed number of ticks leaves different
## villagers in different blocks of their own days.
func _closest_approach(target, destination: Vector2, ticks := 600) -> float:
	var closest := INF
	for i in ticks:
		target._process(1.0)
		closest = minf(closest, target.position.distance_to(destination))
	return closest


# -- walls are solid to a villager too -------------------------------------
#
# Reported live: "NPCs walk straight through houses, ignoring the hitbox".
# The hitbox was never broken -- every building really does get a
# StaticBody2D (EarthChunkManager._spawn_building_node), which is exactly
# what stops the PLAYER. But an NpcMarker is a plain Sprite2D assigning
# `position` directly, so no physics body is ever consulted on its behalf.
# The marker has to ASK, via NpcBuildingGate.


## A world exposing just the two hooks NpcMarker duck-types on: the biome
## read its water check makes, and the building lookup the new wall check
## makes. Blocks one 3x3 house squarely between the villager and its home.
class HouseInTheWayWorld:
	extends RefCounted
	var house_min := Vector2i(63, 60)
	var house_max := Vector2i(65, 62)
	var trespassed := false

	func biome_at_global(_x: int, _y: int) -> String:
		return "grassland"

	func covers(tile: Vector2i) -> bool:
		return (
			tile.x >= house_min.x and tile.x <= house_max.x
			and tile.y >= house_min.y and tile.y <= house_max.y
		)

	func has_building_at_global(x: int, y: int) -> bool:
		return covers(Vector2i(x, y))


func test_a_villager_never_walks_through_a_house():
	var world := HouseInTheWayWorld.new()
	marker.setup(world, TILE_SIZE)
	# Standing west of the house, with home due east of it -- the straight
	# line between the two runs right through the building.
	marker.position = Vector2(61 * TILE_SIZE + 8, 61 * TILE_SIZE + 8)
	marker.home_position = Vector2(68 * TILE_SIZE + 8, 61 * TILE_SIZE + 8)
	marker.workspot_position = marker.home_position
	marker.landmarks = {}
	for i in 600:
		marker._process(0.05)
		var tile := Vector2i(
			floori(marker.position.x / TILE_SIZE), floori(marker.position.y / TILE_SIZE)
		)
		assert_false(
			world.covers(tile),
			"the villager is standing inside the house at %s (step %d)" % [tile, i]
		)
		if world.covers(tile):
			return  # one failure is the point; don't flood the report


func test_a_villager_with_no_world_bound_walks_exactly_as_before():
	# Fail-open, the same contract _is_in_water already keeps: an unbound
	# marker (every pre-existing fixture) must be completely unaffected.
	marker.position = Vector2(1000, 1000)
	marker.home_position = Vector2(1000, 1200)
	marker.workspot_position = marker.home_position
	var before := marker.position
	for i in 20:
		marker._process(0.05)
	assert_gt(
		before.distance_to(marker.position), 0.0,
		"an NPC with no world bound stopped moving"
	)


func test_a_villager_routes_around_a_house_and_actually_gets_home():
	# The bug sliding could never fix (see docs/concept/navigation.md):
	# NpcBuildingGate keeps a villager ALONG a wall it brushes, but a
	# villager whose own doorstep sits directly behind its own house has
	# nowhere to slide to and presses into the wall forever. Avoiding the
	# house was never the hard part -- ARRIVING was.
	var world := HouseInTheWayWorld.new()
	marker.setup(world, TILE_SIZE)
	marker.position = Vector2(61 * TILE_SIZE + 8, 61 * TILE_SIZE + 8)
	marker.home_position = Vector2(68 * TILE_SIZE + 8, 61 * TILE_SIZE + 8)
	marker.workspot_position = marker.home_position
	marker.landmarks = {}
	var closest := INF
	for i in 2000:
		marker._process(0.05)
		closest = minf(closest, marker.position.distance_to(marker.home_position))
		if closest <= TILE_SIZE:
			break
	assert_lte(
		closest, float(TILE_SIZE),
		"the villager never got home -- closest approach was %.1fpx, with a house in the way" % closest
	)


func test_routing_still_never_puts_a_villager_inside_the_house():
	# The gate stays underneath the router: a route can go stale (a house
	# raised across it mid-walk), and this is what guarantees a stale route
	# still cannot end inside a wall.
	var world := HouseInTheWayWorld.new()
	marker.setup(world, TILE_SIZE)
	marker.position = Vector2(61 * TILE_SIZE + 8, 61 * TILE_SIZE + 8)
	marker.home_position = Vector2(68 * TILE_SIZE + 8, 61 * TILE_SIZE + 8)
	marker.workspot_position = marker.home_position
	marker.landmarks = {}
	for i in 2000:
		marker._process(0.05)
		var tile := Vector2i(
			floori(marker.position.x / TILE_SIZE), floori(marker.position.y / TILE_SIZE)
		)
		if world.covers(tile):
			assert_false(true, "routing put the villager inside the house at %s" % tile)
			return
	assert_true(true)
