extends GutTest

## The behavior DSL's atom catalog (docs/concept/behavior_dsl.md §2): the
## registry of reusable named behaviors a tree can reference. Exactly
## npc_instruction_primitives.gd's own split -- a CONDITION registry (used
## only inside `gate`, returns a bool) and an ACTION registry (used only as
## a leaf, returns a decision Dictionary or null) -- so a name used in the
## wrong slot is a category error, not a silent coercion.
##
## Every action atom here is a thin wrapper: flee/seek reuse Affinity/
## BehaviorKernel verbatim (no genome, no species record -- the "not based
## on genetics" half made concrete), schedule wraps NpcSchedule.
## current_entry unmodified, round_trip reads an AntForageBehavior
## instance's own phase. None of these reimplement anything that already
## exists and is already tested.

const BehaviorAtomCatalog = preload("res://src/gameplay/behavior_atom_catalog.gd")
const AntForageBehavior = preload("res://src/gameplay/ant_forage_behavior.gd")


func _stimulus(at: Vector2, channel: String) -> Dictionary:
	return {"position": at, "features": {channel: 1.0}}


# --- the registries themselves are the contract --------------------------------

func test_condition_and_action_names_do_not_overlap():
	for name in BehaviorAtomCatalog.CONDITION_ATOMS:
		assert_false(BehaviorAtomCatalog.ACTION_ATOMS.has(name), "%s is both a condition and an action" % name)


func test_an_unknown_condition_name_fails_closed_to_false():
	assert_false(BehaviorAtomCatalog.evaluate_condition("nonesuch", {}, {}))


func test_an_action_name_used_as_a_condition_fails_closed_to_false():
	assert_false(BehaviorAtomCatalog.evaluate_condition("wander", {}, {}))


func test_an_unknown_action_name_fails_closed_to_null():
	assert_null(BehaviorAtomCatalog.resolve_action("nonesuch", {}, {}))


func test_a_condition_name_used_as_an_action_fails_closed_to_null():
	assert_null(BehaviorAtomCatalog.resolve_action("above", {"need": "hunger", "threshold": 0.5}, {}))


# --- as_list: the scalar/list normalisation every multi-channel atom needs -----

func test_as_list_wraps_a_scalar():
	assert_eq(BehaviorAtomCatalog.as_list("predator"), ["predator"])


func test_as_list_passes_an_existing_list_through():
	assert_eq(BehaviorAtomCatalog.as_list(["predator", "player"]), ["predator", "player"])


func test_as_list_of_nothing_is_empty():
	assert_eq(BehaviorAtomCatalog.as_list(null), [])


# --- above: a need crossing a threshold, reused by any species with a needs dict --

func test_above_is_true_once_the_need_exceeds_the_threshold():
	var context := {"needs": {"hunger": 0.6}}
	assert_true(BehaviorAtomCatalog.evaluate_condition("above", {"need": "hunger", "threshold": 0.5}, context))


func test_above_is_false_at_or_below_the_threshold():
	var context := {"needs": {"hunger": 0.5}}
	assert_false(BehaviorAtomCatalog.evaluate_condition("above", {"need": "hunger", "threshold": 0.5}, context))


func test_above_fails_open_to_zero_for_a_need_not_present():
	assert_false(BehaviorAtomCatalog.evaluate_condition("above", {"need": "hunger", "threshold": 0.1}, {"needs": {}}))
	assert_false(BehaviorAtomCatalog.evaluate_condition("above", {"need": "hunger", "threshold": 0.1}, {}))


## The exact reuse claim: the SAME condition atom, unmodified, gates a
## mammal's needs dict and a villager's -- both are CreatureNeeds.gains()/
## NpcNeeds.gains() shaped {name: level}, and above() does not know or
## care which species built it (docs/concept/behavior_dsl.md §2).
func test_above_reads_any_needs_dict_shaped_the_same_way_regardless_of_species():
	var mammal_needs := {"needs": {"hunger": 0.9, "thirst": 0.1}}
	var villager_needs := {"needs": {"hunger": 0.9}}
	assert_true(BehaviorAtomCatalog.evaluate_condition("above", {"need": "hunger", "threshold": 0.5}, mammal_needs))
	assert_true(BehaviorAtomCatalog.evaluate_condition("above", {"need": "hunger", "threshold": 0.5}, villager_needs))


# --- sensed: is anything on these channels present at all ----------------------

func test_sensed_is_true_when_a_stimulus_carries_the_channel():
	var context := {"stimuli": [_stimulus(Vector2(10, 0), "predator")]}
	assert_true(BehaviorAtomCatalog.evaluate_condition("sensed", {"on": "predator"}, context))


func test_sensed_is_false_when_nothing_carries_the_channel():
	var context := {"stimuli": [_stimulus(Vector2(10, 0), "forage")]}
	assert_false(BehaviorAtomCatalog.evaluate_condition("sensed", {"on": "predator"}, context))


func test_sensed_checks_every_channel_in_a_repeated_on_list():
	var context := {"stimuli": [_stimulus(Vector2(10, 0), "player")]}
	assert_true(BehaviorAtomCatalog.evaluate_condition("sensed", {"on": ["predator", "player"]}, context))


func test_sensed_with_no_stimuli_at_all_is_false():
	assert_false(BehaviorAtomCatalog.evaluate_condition("sensed", {"on": "predator"}, {}))


# --- wander: the universal fallback, always fires -------------------------------

func test_wander_always_fires_regardless_of_context():
	assert_eq(BehaviorAtomCatalog.resolve_action("wander", {}, {}), {"intent": "wander"})


# --- flee / seek: Affinity/BehaviorKernel, no genome anywhere -------------------

func test_flee_heads_away_from_the_nearest_matching_stimulus():
	var context := {
		"position": Vector2.ZERO,
		"stimuli": [_stimulus(Vector2(10, 0), "predator")],
	}
	var decision: Variant = BehaviorAtomCatalog.resolve_action("flee", {"on": "predator"}, context)
	assert_eq(decision["intent"], "flee")
	assert_lt(decision["direction"].x, 0.0)
	assert_eq(decision["target"], Vector2(10, 0))


func test_flee_finds_nothing_and_returns_null_when_no_stimulus_matches():
	var context := {"position": Vector2.ZERO, "stimuli": [_stimulus(Vector2(10, 0), "forage")]}
	assert_null(BehaviorAtomCatalog.resolve_action("flee", {"on": "predator"}, context))


func test_seek_heads_toward_the_nearest_matching_stimulus():
	var context := {"position": Vector2.ZERO, "stimuli": [_stimulus(Vector2(0, 10), "forage")]}
	var decision: Variant = BehaviorAtomCatalog.resolve_action("seek", {"on": "forage"}, context)
	assert_eq(decision["intent"], "seek")
	assert_gt(decision["direction"].y, 0.0)


func test_seek_with_no_stimuli_returns_null():
	assert_null(BehaviorAtomCatalog.resolve_action("seek", {"on": "forage"}, {"position": Vector2.ZERO}))


## Same channel-list normalisation the parser produces: on: predator, on:
## player parses to a list, and flee must check every channel in it.
func test_flee_checks_every_channel_in_a_repeated_on_list():
	var context := {"position": Vector2.ZERO, "stimuli": [_stimulus(Vector2(-5, 0), "player")]}
	var decision: Variant = BehaviorAtomCatalog.resolve_action(
		"flee", {"on": ["predator", "player"]}, context
	)
	assert_eq(decision["intent"], "flee")
	assert_gt(decision["direction"].x, 0.0, "away from the player, at x=-5, is +x")


func test_flee_picks_the_nearer_of_two_matching_stimuli():
	var context := {
		"position": Vector2.ZERO,
		"stimuli": [_stimulus(Vector2(100, 0), "predator"), _stimulus(Vector2(0, 5), "predator")],
	}
	var decision: Variant = BehaviorAtomCatalog.resolve_action("flee", {"on": "predator"}, context)
	assert_eq(decision["target"], Vector2(0, 5))


## No genome, no species record, no receptor expression -- this is the "not
## based on genetics" half of docs/concept/behavior_dsl.md made concrete:
## the same two atoms serve any context that provides position + stimuli.
func test_flee_and_seek_never_read_a_genome_or_species():
	var context := {"position": Vector2.ZERO, "stimuli": [_stimulus(Vector2(1, 0), "predator")]}
	assert_false(context.has("genome"))
	assert_false(context.has("species"))
	assert_not_null(BehaviorAtomCatalog.resolve_action("flee", {"on": "predator"}, context))


# --- schedule: NpcSchedule.current_entry, wrapped unmodified --------------------

func test_schedule_wraps_the_current_entry_for_the_given_hour():
	var context := {
		"schedule": [
			{"time_block": "morning", "location_tag": "field", "activity": "work"},
			{"time_block": "night", "location_tag": "home", "activity": "sleep"},
		],
		"hour": 10,
	}
	var decision: Variant = BehaviorAtomCatalog.resolve_action("schedule", {}, context)
	assert_eq(decision["intent"], "schedule")
	assert_eq(decision["location_tag"], "field")
	assert_eq(decision["activity"], "work")


func test_schedule_with_no_schedule_at_all_returns_null():
	assert_null(BehaviorAtomCatalog.resolve_action("schedule", {}, {}))


# --- round_trip: an AntForageBehavior instance's own phase, read not driven ----

func test_round_trip_reports_approaching_while_the_behavior_is_approaching():
	var behavior := AntForageBehavior.new()
	var decision: Variant = BehaviorAtomCatalog.resolve_action("round_trip", {}, {"round_trip": behavior})
	assert_eq(decision, {"intent": "approaching"})


func test_round_trip_reports_returning_once_the_behavior_has_arrived():
	var behavior := AntForageBehavior.new()
	behavior.arrive_at_food(true)
	var decision: Variant = BehaviorAtomCatalog.resolve_action("round_trip", {}, {"round_trip": behavior})
	assert_eq(decision, {"intent": "returning"})


func test_round_trip_with_no_behavior_instance_in_context_returns_null():
	assert_null(BehaviorAtomCatalog.resolve_action("round_trip", {}, {}))
