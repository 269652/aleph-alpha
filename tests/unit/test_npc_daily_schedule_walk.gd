extends GutTest

## Capstone proof for docs/roadmap.md Phase 2's "Local executor: FSM +
## pathfinding that walks the schedule with zero LLM calls during normal
## execution" -- this slice's own stated minimum bar: a REAL NpcMarker,
## given a REAL NpcIdentity and its default NpcPlanner.FakeNpcPlanner (never
## a hand-set schedule -- see NpcMarker._process's own lazy
## `if schedule.is_empty(): schedule = _planner.plan_day(...)` path), walking
## forward through REAL simulated time (NpcMarker._elapsed_time /
## SECONDS_PER_SIMULATED_DAY, the exact clock every live villager runs on)
## and landing in genuinely different real-world positions at dawn, midday,
## and dusk.
##
## Every existing NpcMarker movement test (test_npc_marker.gd) hand-sets a
## schedule pinning ALL FOUR time blocks to the SAME location_tag, which
## proves "moves toward a target" but never proves a real schedule actually
## relocates an NPC across the day the way the roadmap's own minimum bar
## names. This file is deliberately not redundant with that one -- it is the
## one place that chains NpcIdentity -> NpcPlanner.FakeNpcPlanner ->
## NpcSchedule -> NpcMarker end to end, through the real per-frame API the
## live game itself drives, and asserts on the specific day-shaped
## observable roadmap.md and npc.md both call for.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

## Real distances between home/work/well/gate/stall -- large enough that
## "the NPC moved" is unambiguous, small enough WALK_SPEED (20 u/s) comfortably
## covers every leg within the real in-game hours available between
## checkpoints (verified, not assumed -- see
## test_the_sampled_checkpoints_leave_enough_time_to_actually_arrive below).
const _HOME := Vector2(1000.0, 1000.0)
const _WORKSPOT := Vector2(1000.0, 1100.0)  # e.g. a farmer's field -- not a shared landmark
const _WELL := Vector2(1100.0, 1000.0)
const _GATE := Vector2(900.0, 1000.0)
const _STALL := Vector2(1000.0, 900.0)

## Small, repeated steps -- matches how the live game actually drives
## NpcMarker._process every frame, not one artificial jump.
const _STEP_DELTA := 0.25

## Real seconds per one in-game hour, derived from the exact constant
## NpcMarker itself runs its day-cycle on rather than an independently
## eyeballed number -- tracks that clock even if its pacing ever changes.
const _REAL_SECONDS_PER_GAME_HOUR := NpcMarker.SECONDS_PER_SIMULATED_DAY / 24.0

## Checkpoint hours, chosen well inside the 3 time blocks that resolve to
## distinct locations for a plain (non-guard) occupation: night (home),
## midday (own work location), evening (well) -- see NpcSchedule.
## time_block_for_hour and NpcPlanner.FakeNpcPlanner.plan_day. "Dawn" is
## sampled from the tail of the night block (hour 3): the schedule's own
## night entry already covers hours 22-23 and 0-5 as one continuous
## sleep-at-home block, so this is genuinely "still before the day's work
## begins", not a contrived reading of the word.
const _DAWN_HOUR := 3
const _MIDDAY_HOUR := 13
const _DUSK_HOUR := 21

var _npcs: Array = []
var _elapsed := 0.0


func before_each():
	_elapsed = 0.0


func after_each():
	for npc in _npcs:
		if is_instance_valid(npc):
			remove_child(npc)
			npc.free()
	_npcs = []


func _spawn() -> NpcMarker:
	var marker := NpcMarker.new()
	marker.home_position = _HOME
	marker.workspot_position = _WORKSPOT
	marker.landmarks = {"well": _WELL, "gate": _GATE, "stall": _STALL}
	marker.position = _HOME
	add_child(marker)
	_npcs.append(marker)
	return marker


## Same "scan seeds for the occupation we need" convention already used by
## test_npc_planner.gd/test_npc_marker.gd (the occupation pool is small, 50
## seeds reliably covers all 8) -- not a new pattern invented here.
func _identity_for_occupation(occupation: String) -> NpcIdentity:
	for seed_value in range(50):
		var candidate := NpcIdentity.new(seed_value)
		if candidate.occupation == occupation:
			return candidate
	return null


func _hour_elapsed(hour: int) -> float:
	return float(hour) * _REAL_SECONDS_PER_GAME_HOUR


## Advances real elapsed process time (tracked in `_elapsed`, mirroring
## NpcMarker's own private `_elapsed_time` 1:1 since every tick anywhere in
## this file goes through this one helper) up to `target_elapsed`.
func _advance_to(marker: NpcMarker, target_elapsed: float) -> void:
	while _elapsed < target_elapsed:
		marker._process(_STEP_DELTA)
		_elapsed += _STEP_DELTA


## Guards the fixture's own timing budget against WALK_SPEED before trusting
## any position assertion below -- a tuned-value check per this project's
## "never an eyeballed comment" rule, not a claim taken on faith.
func test_the_sampled_checkpoints_leave_enough_time_to_actually_arrive():
	var longest_leg: float = _WORKSPOT.distance_to(_WELL)  # this fixture's longest single leg
	var seconds_needed := longest_leg / NpcMarker.WALK_SPEED

	# Morning (work) starts at hour 6; the midday checkpoint must leave at
	# least that much real-second budget to walk home -> workspot.
	var morning_to_midday_budget := _hour_elapsed(_MIDDAY_HOUR) - _hour_elapsed(6)
	# Evening starts at hour 17; the dusk checkpoint must leave at least
	# that much budget to walk workspot -> well.
	var evening_to_dusk_budget := _hour_elapsed(_DUSK_HOUR) - _hour_elapsed(17)

	assert_gt(morning_to_midday_budget, seconds_needed)
	assert_gt(evening_to_dusk_budget, seconds_needed)


## The roadmap's own minimum bar: a real NPC, driven purely by real elapsed
## time through its own (lazily planner-generated) schedule, is observably
## in a different place at dawn, midday, and dusk.
func test_a_farmer_is_in_a_different_place_at_dawn_midday_and_dusk():
	var identity := _identity_for_occupation("farmer")
	assert_not_null(identity, "precondition: expected a farmer within 50 seeds")
	var marker := _spawn()
	marker.identity = identity

	_advance_to(marker, _hour_elapsed(_DAWN_HOUR))
	var dawn_position := marker.position

	_advance_to(marker, _hour_elapsed(_MIDDAY_HOUR))
	var midday_position := marker.position

	_advance_to(marker, _hour_elapsed(_DUSK_HOUR))
	var dusk_position := marker.position

	assert_gt(dawn_position.distance_to(midday_position), 10.0, "dawn (home) and midday (field) should be different places")
	assert_gt(midday_position.distance_to(dusk_position), 10.0, "midday (field) and dusk (well) should be different places")
	assert_gt(dawn_position.distance_to(dusk_position), 10.0, "dawn (home) and dusk (well) should be different places")

	# Not merely "different", but genuinely AT the schedule's own resolved
	# location -- the fixture's timing budget (see the guard test above)
	# gives the walk ample real time to fully arrive, not just start moving.
	assert_almost_eq(dawn_position.distance_to(_HOME), 0.0, 1.0, "at dawn the farmer should be home")
	assert_almost_eq(midday_position.distance_to(_WORKSPOT), 0.0, 1.0, "at midday the farmer should be at the field")
	assert_almost_eq(dusk_position.distance_to(_WELL), 0.0, 1.0, "at dusk the farmer should be at the well")


## Proves the schedule genuinely depends on the NPC's OWN identity, not one
## hardcoded walk every villager repeats: a merchant's midday spot is the
## shared stall, not the farmer's field above -- driven entirely by
## FakeNpcPlanner reading this villager's own occupation.
func test_a_different_occupation_walks_to_a_different_midday_location():
	var identity := _identity_for_occupation("merchant")
	assert_not_null(identity, "precondition: expected a merchant within 50 seeds")
	var marker := _spawn()
	marker.identity = identity

	_advance_to(marker, _hour_elapsed(_MIDDAY_HOUR))

	assert_almost_eq(marker.position.distance_to(_STALL), 0.0, 1.0, "a merchant should be at the stall by midday")


## A guard is the one documented exception (FakeNpcPlanner's own comment:
## "stays on watch through the evening instead of socializing at the well")
## -- dusk should NOT differ from midday for a guard. Included alongside the
## farmer/merchant cases above so the day-shaped claim reads as "a real
## schedule genuinely drives this, and it genuinely varies by occupation",
## not a coincidence of only ever testing occupations that go home to
## socialize in the evening.
func test_a_guard_stays_at_the_gate_through_dusk_instead_of_socializing():
	var identity := _identity_for_occupation("guard")
	assert_not_null(identity, "precondition: expected a guard within 50 seeds")
	var marker := _spawn()
	marker.identity = identity

	_advance_to(marker, _hour_elapsed(_MIDDAY_HOUR))
	var midday_position := marker.position

	_advance_to(marker, _hour_elapsed(_DUSK_HOUR))
	var dusk_position := marker.position

	assert_almost_eq(midday_position.distance_to(_GATE), 0.0, 1.0, "a guard should be on watch at the gate by midday")
	assert_almost_eq(dusk_position.distance_to(_GATE), 0.0, 1.0, "a guard should still be on watch at the gate at dusk")
