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


# -- a villager does not walk through a wall ---------------------------------
#
# Reported live: "houses should also block NPCs and animals". An NpcMarker
# is a Sprite2D that moves by one position.move_toward per frame, so the
# StaticBody2D on a wall has never had any effect on it.
#
# It SLIDES rather than stopping dead, which is what the same collision
# would do to the player (move_and_slide) and what this marker needs to
# keep working: there is no pathfinding here, only a straight line to the
# target, so a villager who stopped the instant they touched a wall would
# stand there for good -- and their own front door is reached by walking
# at the house. Blocked straight on, they try the two axes separately and
# take whichever is open, which carries them along the wall to the door.
#
# A DOOR and a FLOOR are walkable pieces, so going indoors is unaffected.

class StubWorldWithWall:
	extends StubWorld
	var blocking_tiles: Dictionary = {}
	func piece_blocks_movement_at_global(x: int, y: int) -> bool:
		return blocking_tiles.has(Vector2i(x, y))


func _wall_marker(world) -> NpcMarker:
	var marker := NpcMarker.new()
	marker.identity = NpcIdentity.new(1)
	add_child_autofree(marker)
	marker.setup(world, 16)
	return marker


func test_open_ground_is_stepped_into_unchanged():
	var world := StubWorldWithWall.new()
	var marker := _wall_marker(world)
	assert_eq(marker._slid_along_walls(Vector2(8, 8), Vector2(24, 8)), Vector2(24, 8))


func test_a_villager_slides_along_a_wall_instead_of_stopping_dead():
	var world := StubWorldWithWall.new()
	# The step's destination is a wall, and so is the cell due east of the
	# start -- but due south is open, so that is the part of the step that
	# survives.
	world.blocking_tiles[Vector2i(1, 1)] = true
	world.blocking_tiles[Vector2i(1, 0)] = true
	var marker := _wall_marker(world)
	var slid: Vector2 = marker._slid_along_walls(Vector2(8, 8), Vector2(24, 24))
	assert_eq(
		slid, Vector2(8, 24),
		"blocked east, open south: the villager keeps the part of the step that is open"
	)


func test_a_villager_boxed_in_on_both_axes_stays_put():
	var world := StubWorldWithWall.new()
	world.blocking_tiles[Vector2i(1, 0)] = true
	world.blocking_tiles[Vector2i(1, 1)] = true
	world.blocking_tiles[Vector2i(0, 1)] = true
	var marker := _wall_marker(world)
	assert_eq(marker._slid_along_walls(Vector2(8, 8), Vector2(24, 24)), Vector2(8, 8))


func test_a_world_that_knows_no_pieces_never_blocks_a_villager():
	var marker := _wall_marker(StubWorld.new())
	assert_eq(marker._slid_along_walls(Vector2(8, 8), Vector2(24, 24)), Vector2(24, 24))


## The rails a farmhouse raises round its beds stop a villager for the same
## reason they stop an animal (CreatureMarker._fence_blocks_movement):
## asked for directly, "fences should have a hitbox blocking player and
## NPCs as well". A rail is a LINE on one edge of its tile, so what the
## world is asked is whether the STEP crosses it -- never whether a tile
## carries a rail, which would make the ring round a field unwalkable
## ground rather than a fence.
class StubWorldWithFence:
	extends StubWorld
	var blocks_step := false
	var asked_step: Array = []
	func fence_blocks_step_global(from_x: int, from_y: int, to_x: int, to_y: int) -> bool:
		asked_step = [Vector2i(from_x, from_y), Vector2i(to_x, to_y)]
		return blocks_step


func test_a_villager_does_not_step_across_a_farm_rail():
	var world := StubWorldWithFence.new()
	world.blocks_step = true
	var marker := _wall_marker(world)
	assert_eq(marker._slid_along_walls(Vector2(8, 8), Vector2(24, 8)), Vector2(8, 8))
	assert_eq(world.asked_step, [Vector2i(0, 0), Vector2i(1, 0)], "it asks about the step it takes")


func test_a_villager_walks_on_when_no_rail_is_crossed():
	var world := StubWorldWithFence.new()
	world.blocks_step = false
	var marker := _wall_marker(world)
	assert_eq(marker._slid_along_walls(Vector2(8, 8), Vector2(24, 8)), Vector2(24, 8))


## Reported live, with the village in shot: *"The farmer doesn't farm
## anymore"*.
##
## A regression from f64a360e ("a villager walks round a wall and a rail,
## not through them"), whose own message named this failure mode: *"there
## is no pathfinding here, only a straight line at the target... boxed in
## on both, they stay put"*. Rails round a field stop a villager now -- and
## a field's rails stand on its INNER edge, so the one villager they shut
## out is the farmer whose beds they enclose.
##
## Measured on a real village (tools/probe_village_farming.gd): of three
## villagers with a field, one worked 58 beds in 600s and the other two
## worked NONE. Both spent 2650 of 2750 on-field ticks in APPROACHING,
## frozen -- the herbalist nine pixels from its own bed, refused the last
## step south into it.
##
## A gate exists for exactly this (docs/concept/village_farms.md, "The
## gate"), but reaching it needs pathfinding a Sprite2D walking one
## move_toward per frame does not have. The farmer is who the field is
## FOR; the rails are there to keep animals out and to read as an
## enclosure, not to shut the worker out of their own beds. So a villager
## may cross into a bed they themselves work, and no other rail moves.
func test_a_farmer_may_step_into_a_bed_they_work():
	var world := StubWorldWithFence.new()
	world.blocks_step = true
	var marker := _wall_marker(world)
	marker.field_cells = [Vector2i(1, 0)]

	assert_eq(
		marker._slid_along_walls(Vector2(8, 8), Vector2(24, 8)), Vector2(24, 8),
		"the rail round a farmer's own field does not shut the farmer out of it"
	)


func test_a_rail_still_stops_a_villager_stepping_anywhere_else():
	var world := StubWorldWithFence.new()
	world.blocks_step = true
	var marker := _wall_marker(world)
	marker.field_cells = [Vector2i(9, 9)]  # their field is somewhere else entirely

	assert_eq(
		marker._slid_along_walls(Vector2(8, 8), Vector2(24, 8)), Vector2(8, 8),
		"every other rail still stops them, including a neighbour's"
	)


func test_a_villager_with_no_field_is_stopped_by_every_rail():
	var world := StubWorldWithFence.new()
	world.blocks_step = true
	var marker := _wall_marker(world)

	assert_eq(marker._slid_along_walls(Vector2(8, 8), Vector2(24, 8)), Vector2(8, 8))


# -- the water errand (docs/concept/village_water.md) -----------------------
#
# Asked for directly: *"when they get water they should carry the empty
# bucket to the well and bring back a full bucket which they can pour into
# their houses water tank"*. This is the half that makes the errand
# LEGIBLE -- the state machine and the tank are already pinned in
# test_water_errand.gd and test_earth_chunk_manager_household_water.gd; what
# is tested here is that a villager actually walks it and is seen doing so.

const WaterErrand = preload("res://src/emergence/water_errand.gd")
const HouseholdWater = preload("res://src/emergence/household_water.gd")


## A world with exactly one house in it, whose tank the test can set.
class WateredWorld:
	extends StubWorld
	var house_level := HouseholdWater.TANK_LITRES
	var poured := 0
	var door_position := Vector2(1000, 1000)

	func building_door_near(pixel_position: Vector2, radius_tiles: float) -> Dictionary:
		if pixel_position.distance_to(door_position) > radius_tiles * 16.0:
			return {}
		return {
			"id": "house_small", "chunk_coord": Vector2i(0, 0),
			"origin_local": Vector2i(4, 4), "seed": 7,
		}

	func water_trip_due_at(_record: Dictionary) -> bool:
		return HouseholdWater.trip_is_due(house_level)

	func pour_bucket_into_house(_chunk_coord: Vector2i, _origin_local: Vector2i) -> bool:
		poured += 1
		house_level = HouseholdWater.poured_into(house_level, HouseholdWater.BUCKET_LITRES)
		return true


func _a_watered_villager(level: float) -> WateredWorld:
	var world := WateredWorld.new()
	world.house_level = level
	world.door_position = marker.home_position
	marker.setup(world, TILE_SIZE)
	marker.set_planner(FixedPlanner.new([
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "idle"},
	]))
	return world


## Walks the errand to completion, standing the villager on each leg's
## target so the test is about the ERRAND rather than about walking speed.
func _walk_the_errand(world: WateredWorld, steps: int = 12) -> void:
	for i in steps:
		marker.position = marker._resolve_location(
			WaterErrand.location_tag_for(marker.water_errand)
		)
		marker._process(0.1)
		if marker.water_errand == WaterErrand.AT_HOME and world.poured > 0:
			return


# -- setting out ------------------------------------------------------------

func test_a_villager_with_a_full_tank_stays_off_the_errand():
	_a_watered_villager(HouseholdWater.TANK_LITRES)
	marker._process(0.1)
	assert_eq(marker.water_errand, WaterErrand.AT_HOME)
	assert_eq(marker.carried_item(), "")


func test_a_villager_whose_house_is_low_sets_out_for_the_well():
	_a_watered_villager(0.0)
	marker._process(0.1)
	assert_eq(marker.water_errand, WaterErrand.TO_WELL)


func test_they_carry_an_empty_bucket_on_the_way_there():
	_a_watered_villager(0.0)
	marker._process(0.1)
	assert_eq(marker.carried_item(), WaterErrand.BUCKET_EMPTY)


func test_the_errand_sends_them_to_the_well_not_wherever_the_plan_said():
	# The plan says home all day; the errand outranks it.
	_a_watered_villager(0.0)
	marker._process(0.1)
	assert_eq(marker.current_location_tag(), "well")


# -- and back again ---------------------------------------------------------

func test_reaching_the_well_fills_the_bucket():
	var world := _a_watered_villager(0.0)
	marker._process(0.1)
	marker.position = marker._resolve_location("well")
	marker._process(0.1)  # arrive -> DRAWING
	marker._process(0.1)  # drawn  -> TO_HOME
	assert_eq(marker.water_errand, WaterErrand.TO_HOME)
	assert_eq(marker.carried_item(), WaterErrand.BUCKET_FULL)
	assert_eq(world.poured, 0, "nothing was poured before they got home")


func test_getting_home_pours_the_bucket_into_the_tank():
	var world := _a_watered_villager(0.0)
	marker._process(0.1)
	_walk_the_errand(world)
	assert_gt(world.poured, 0, "the bucket was never poured")
	assert_gt(world.house_level, 0.0, "the tank is still empty")


func test_the_errand_ends_and_they_are_not_stuck_holding_a_bucket():
	var world := _a_watered_villager(0.0)
	marker._process(0.1)
	_walk_the_errand(world)
	assert_eq(marker.water_errand, WaterErrand.AT_HOME)
	assert_eq(marker.carried_item(), "")


## A villager pouring water into their own tank is standing at their own
## door -- and must not vanish indoors while doing it, or the errand ends
## invisibly and the whole point is lost.
func test_they_stay_visible_while_they_are_on_the_errand():
	var world := _a_watered_villager(0.0)
	marker._process(0.1)
	for i in 10:
		marker.position = marker._resolve_location(
			WaterErrand.location_tag_for(marker.water_errand)
		)
		marker._process(0.1)
		if WaterErrand.is_running(marker.water_errand):
			assert_true(marker.visible, "a villager on the errand went invisible")
		if marker.water_errand == WaterErrand.AT_HOME and world.poured > 0:
			break


# -- nothing to fetch from --------------------------------------------------

func test_a_villager_with_no_world_never_sets_out():
	marker.set_planner(FixedPlanner.new([
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "idle"},
	]))
	marker._process(0.1)
	assert_eq(marker.water_errand, WaterErrand.AT_HOME)


func test_a_villager_with_no_house_of_their_own_never_sets_out():
	var world := _a_watered_villager(0.0)
	world.door_position = Vector2(50000, 50000)  # their house is nowhere near
	marker._process(0.1)
	assert_eq(marker.water_errand, WaterErrand.AT_HOME)


# -- the farmhouse's own tank (docs/concept/village_water.md mechanism 3) ---
#
# Asked for directly: *"they then drink from their houses stock or use it to
# water crops in case of a farmhouse"*. A farmhouse is nobody's home, so
# nothing drinks there -- its tank is emptied by the FIELD. When it runs
# down to the household's drinking reserve the beds stop being watered, and
# that is what sends the farmer to the well for it.

const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")


## A world with a cottage AND the farmhouse its farmer works, each with a
## tank of its own that the test can run dry independently.
class FarmingWorld:
	extends StubWorld
	var house_due := false
	var farmhouse_due := false
	var crop_water := true
	var drawn := 0
	var watered: Array = []
	var poured: Array = []
	var door_position := Vector2(1000, 1000)
	var farmhouse_cell := Vector2i(200, 200)

	const HOUSE_ORIGIN := Vector2i(4, 4)
	const FARMHOUSE_ORIGIN := Vector2i(2, 2)

	func building_door_near(pixel_position: Vector2, radius_tiles: float) -> Dictionary:
		if pixel_position.distance_to(door_position) > radius_tiles * 16.0:
			return {}
		return {
			"id": "house_small", "chunk_coord": Vector2i(0, 0),
			"origin_local": HOUSE_ORIGIN, "seed": 7,
		}

	func building_at_global(global_x: int, global_y: int) -> Dictionary:
		if Vector2i(global_x, global_y) != farmhouse_cell:
			return {}
		return {
			"id": VillageFarm.FARM_BUILDING_ID, "chunk_coord": Vector2i(1, 1),
			"origin_local": FARMHOUSE_ORIGIN, "seed": 9,
		}

	func water_trip_due_at(record: Dictionary) -> bool:
		if String(record.get("id", "")) == VillageFarm.FARM_BUILDING_ID:
			return farmhouse_due
		return house_due

	func pour_bucket_into_house(_chunk_coord: Vector2i, origin_local: Vector2i) -> bool:
		poured.append(origin_local)
		return true

	func draw_crop_water_at_global(_global_x: int, _global_y: int) -> bool:
		if not crop_water:
			return false
		drawn += 1
		return true

	func water_farm_plot_at_global(global_x: int, global_y: int) -> bool:
		watered.append(Vector2i(global_x, global_y))
		return true


func _a_farmer_with_a_farmhouse() -> FarmingWorld:
	var world := FarmingWorld.new()
	world.door_position = marker.home_position
	marker.setup(world, TILE_SIZE)
	marker.set_planner(FixedPlanner.new([
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "idle"},
	]))
	marker.field_cells = [world.farmhouse_cell + Vector2i(1, 1), world.farmhouse_cell + Vector2i(2, 1)]
	marker.stock_building_cell = world.farmhouse_cell
	return world


## Stands the villager on each leg's own target so the test is about the
## ERRAND rather than about walking speed.
func _walk_the_farm_errand(world: FarmingWorld, steps: int = 12) -> void:
	for i in steps:
		marker.position = marker._resolve_location(
			WaterErrand.location_tag_for(marker.water_errand)
		)
		marker._process(0.1)
		if marker.water_errand == WaterErrand.AT_HOME and not world.poured.is_empty():
			return


# -- the field is billed to the farmhouse -----------------------------------

func test_watering_the_beds_is_paid_for_out_of_the_farmhouse_tank():
	var world := _a_farmer_with_a_farmhouse()
	marker._field_index = 0
	marker._work_field_cell()
	assert_eq(world.drawn, 1, "a visit to the beds cost the farmhouse nothing")
	assert_false(world.watered.is_empty(), "the beds never got wet")


func test_a_farmhouse_down_to_its_reserve_stops_the_beds_being_watered():
	var world := _a_farmer_with_a_farmhouse()
	world.crop_water = false
	marker._field_index = 0
	marker._work_field_cell()
	assert_true(
		world.watered.is_empty(),
		"the field drank water the farmhouse did not have"
	)


## A farmer with no farmhouse of their own -- a village that has not raised
## one -- keeps the free drip they always had. There is no tank to bill it
## to, and failing CLOSED here would kill every such field on this commit.
func test_a_farmer_with_no_farmhouse_still_waters_their_beds():
	var world := _a_farmer_with_a_farmhouse()
	world.crop_water = false
	marker.stock_building_cell = NpcMarker.NO_STOCK_BUILDING
	marker._field_index = 0
	marker._work_field_cell()
	assert_false(world.watered.is_empty())


# -- so somebody fetches water for the farmhouse too ------------------------

func test_a_farmer_sets_out_when_the_farmhouse_tank_is_low():
	var world := _a_farmer_with_a_farmhouse()
	world.farmhouse_due = true
	marker._process(0.1)
	assert_eq(marker.water_errand, WaterErrand.TO_WELL)
	assert_eq(marker.carried_item(), WaterErrand.BUCKET_EMPTY)


func test_the_bucket_for_the_field_is_carried_to_the_farmhouse_not_the_cottage():
	var world := _a_farmer_with_a_farmhouse()
	world.farmhouse_due = true
	_walk_the_farm_errand(world)
	assert_eq(world.poured, [FarmingWorld.FARMHOUSE_ORIGIN])


## The farmhouse's DOORSTEP, the one cell a building is reached from
## (BuildingCatalog.doorstep_of, the same rule building_door_near keeps) --
## not its anchor, which is a cell the building itself stands on. A
## villager who walks to the anchor pours the bucket standing inside the
## farmhouse's own art.
func test_the_walk_home_with_a_full_bucket_ends_at_the_farmhouse_doorstep():
	var world := _a_farmer_with_a_farmhouse()
	world.farmhouse_due = true
	for i in 4:
		marker.position = marker._resolve_location(
			WaterErrand.location_tag_for(marker.water_errand)
		)
		marker._process(0.1)
		if marker.carried_item() == WaterErrand.BUCKET_FULL:
			break
	assert_eq(marker.carried_item(), WaterErrand.BUCKET_FULL, "precondition: they filled the bucket")
	assert_eq(
		marker._resolve_location(marker.current_location_tag()),
		marker._cell_centre(
			world.farmhouse_cell + BuildingCatalog.doorstep_of(VillageFarm.FARM_BUILDING_ID)
		),
		"a full bucket for the field was carried somewhere other than the farmhouse door"
	)


## People before plants -- the same order the drinking reserve keeps.
func test_their_own_house_is_served_before_the_field():
	var world := _a_farmer_with_a_farmhouse()
	world.house_due = true
	world.farmhouse_due = true
	_walk_the_farm_errand(world)
	assert_eq(world.poured, [FarmingWorld.HOUSE_ORIGIN])


## An errand is a thing somebody is in the MIDDLE of: whichever building
## sent them is the building the bucket comes back to, however the other
## one's tank changes while they walk.
func test_a_villager_does_not_change_their_mind_halfway_across_the_square():
	var world := _a_farmer_with_a_farmhouse()
	world.farmhouse_due = true
	marker._process(0.1)
	assert_true(WaterErrand.is_running(marker.water_errand), "precondition: they set out")
	world.house_due = true
	_walk_the_farm_errand(world)
	assert_eq(world.poured, [FarmingWorld.FARMHOUSE_ORIGIN])


func test_a_villager_with_no_farmhouse_is_never_sent_for_one():
	var world := _a_farmer_with_a_farmhouse()
	world.farmhouse_due = true
	marker.stock_building_cell = NpcMarker.NO_STOCK_BUILDING
	marker._process(0.1)
	assert_eq(marker.water_errand, WaterErrand.AT_HOME)


# -- the bucket is actually in their hand -----------------------------------
#
# The other half of the report: *"it's not visible what they are doing"*.
# WaterErrand.carried() has always SAID what is in the villager's hand;
# until this it went nowhere, so the errand ran invisibly and the crowd at
# the well was replaced by people walking about for no apparent reason.

func test_a_villager_on_the_errand_is_carrying_something_you_can_see():
	var view := _bind_real_view()
	_a_watered_villager(0.0)
	marker._process(0.1)
	assert_true(WaterErrand.is_running(marker.water_errand), "precondition: they set out")
	assert_true(view.is_slot_equipped("tool"), "the errand is invisible: their hands are empty")
	assert_ne(view.tool_slot_texture(), null)


func test_a_villager_off_the_errand_is_empty_handed():
	var view := _bind_real_view()
	_a_watered_villager(HouseholdWater.TANK_LITRES)
	marker._process(0.1)
	assert_false(view.is_slot_equipped("tool"))


## Pillar 2 at the one point it can actually fail: the two legs must not
## look alike, or nothing has been fixed.
func test_the_bucket_they_carry_back_is_not_the_one_they_carried_out():
	var view := _bind_real_view()
	var world := _a_watered_villager(0.0)
	marker._process(0.1)
	var carried_out := view.tool_slot_texture()
	assert_ne(carried_out, null, "precondition: they set out with something")
	for i in 4:
		marker.position = marker._resolve_location(
			WaterErrand.location_tag_for(marker.water_errand)
		)
		marker._process(0.1)
		if marker.carried_item() == WaterErrand.BUCKET_FULL:
			break
	assert_eq(marker.carried_item(), WaterErrand.BUCKET_FULL, "precondition: they filled it")
	assert_ne(view.tool_slot_texture(), carried_out, "a full bucket looks exactly like an empty one")


func test_they_put_the_bucket_down_once_they_are_home():
	var view := _bind_real_view()
	var world := _a_watered_villager(0.0)
	marker._process(0.1)
	assert_true(view.is_slot_equipped("tool"), "precondition: they set out with it")
	world.house_level = HouseholdWater.TANK_LITRES  # filled while they walked
	_walk_the_errand(world)
	assert_eq(marker.water_errand, WaterErrand.AT_HOME, "precondition: the errand ended")
	assert_false(view.is_slot_equipped("tool"), "they are still holding the bucket indoors")


# -- an errand you cannot finish -------------------------------------------
#
# There is no pathfinding here, only a straight line at the target and a
# slide along whatever it runs into (_slid_along_walls), so a villager with
# a wall, a rail or a building between them and the well walks at it
# forever. Measured on the probe village (tools/probe_farm_water.gd): one
# of three field workers ended a 600s run still `to_well`, 104 px short of
# a well it had had 570 seconds to reach, having worked 156 of 6000 ticks
# against its own baseline of 2750. It never farmed again.

## Walks the errand until they give up, standing them still so they make no
## progress at all -- which is what a wall looks like from in here.
func _walk_into_a_wall(steps: int = 4000) -> void:
	var stuck := marker.position
	for i in steps:
		marker.position = stuck
		marker._process(0.1)
		if not WaterErrand.is_running(marker.water_errand):
			return


func test_a_villager_who_cannot_reach_the_well_puts_the_bucket_down():
	var world := _a_watered_villager(0.0)
	marker._process(0.1)
	assert_true(WaterErrand.is_running(marker.water_errand), "precondition: they set out")
	_walk_into_a_wall()
	assert_eq(marker.water_errand, WaterErrand.AT_HOME, "they walked at the wall for ever")
	assert_eq(marker.carried_item(), "", "still holding a bucket they never filled")
	assert_eq(world.poured, 0, "they poured a bucket they never filled")


func test_they_get_on_with_their_day_before_trying_again():
	_a_watered_villager(0.0)
	marker._process(0.1)
	_walk_into_a_wall()
	assert_eq(marker.water_errand, WaterErrand.AT_HOME, "precondition: they gave up")
	marker._process(0.1)
	assert_eq(
		marker.water_errand, WaterErrand.AT_HOME,
		"they turned round at the door and walked into the same wall again"
	)


func test_they_try_again_the_next_day():
	_a_watered_villager(0.0)
	marker._process(0.1)
	_walk_into_a_wall()
	assert_eq(marker.water_errand, WaterErrand.AT_HOME, "precondition: they gave up")
	marker._process(NpcMarker.ERRAND_RETRY_SECONDS)
	marker._process(0.1)
	assert_true(WaterErrand.is_running(marker.water_errand), "they gave up on water for good")


## The other side of the same constant: patience has to be generous enough
## that a REAL walk never trips it. This villager teleports nowhere -- they
## walk to the well and back at their own speed.
func test_a_villager_who_can_walk_there_still_finishes_the_errand():
	var world := _a_watered_villager(0.0)
	var walked := 0
	for i in 4000:
		marker._process(0.1)
		walked = i
		if world.poured > 0:
			break
	assert_gt(world.poured, 0, "a villager who could simply walk to the well never got there")
	assert_lt(walked, 3999, "they were still walking after %.0f simulated seconds" % 400.0)
