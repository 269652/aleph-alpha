extends GutTest

## NpcPlanner (docs/concept/npc.md "Planning architecture"): once per in-game
## day, one (offline/LLM) call produces a rough {time_block, location_tag,
## activity} schedule; a cheap local FSM then executes it with zero further
## calls. Mirrors WorldBossFitness's PhaseGenerator/FakePhaseGenerator split
## (docs/roadmap.md "stubbed/fake LLM response" convention): Planner is the
## contract a real LLM-backed planner will implement later, FakeNpcPlanner is
## the deterministic stand-in used everywhere today.

const NpcPlanner = preload("res://src/world/npc_planner.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")

const _TIME_BLOCKS := ["morning", "midday", "evening", "night"]


func test_planner_base_returns_an_empty_schedule():
	var planner := NpcPlanner.Planner.new()
	assert_eq(planner.plan_day(NpcIdentity.new(1), 0), [])


func test_fake_planner_is_deterministic_for_the_same_identity_and_day():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var identity := NpcIdentity.new(7)
	var first := planner.plan_day(identity, 3)
	var second := planner.plan_day(identity, 3)
	assert_eq(first, second)


func test_fake_planner_covers_every_time_block_exactly_once():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var identity := NpcIdentity.new(7)
	var schedule := planner.plan_day(identity, 0)
	var seen := {}
	for entry in schedule:
		assert_true(_TIME_BLOCKS.has(entry["time_block"]), "unexpected time_block: %s" % entry["time_block"])
		seen[entry["time_block"]] = true
	assert_eq(seen.size(), _TIME_BLOCKS.size())


func test_fake_planner_every_entry_has_a_location_tag_and_activity():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var schedule := planner.plan_day(NpcIdentity.new(2), 0)
	for entry in schedule:
		assert_gt(entry["location_tag"].length(), 0)
		assert_gt(entry["activity"].length(), 0)


func test_fake_planner_night_entry_is_always_sleep_at_home():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	for seed_value in range(20):
		var schedule := planner.plan_day(NpcIdentity.new(seed_value), 0)
		var night := NpcSchedule.entry_for_time_block(schedule, "night")
		assert_eq(night["activity"], "sleep")
		assert_eq(night["location_tag"], "home")


## A merchant's schedule should route them to the stall, not the field --
## the plan is occupation-aware, not a single generic loop for everyone.
func test_fake_planner_merchant_works_at_the_stall():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	# Find a seed that rolls "merchant" (occupation pool is small).
	var identity: NpcIdentity
	for seed_value in range(50):
		var candidate := NpcIdentity.new(seed_value)
		if candidate.occupation == "merchant":
			identity = candidate
			break
	assert_not_null(identity, "precondition: expected a merchant within 50 seeds")
	var schedule := planner.plan_day(identity, 0)
	var midday := NpcSchedule.entry_for_time_block(schedule, "midday")
	assert_eq(midday["location_tag"], "stall")
	assert_eq(midday["activity"], "work")


## -- NpcSchedule: resolving which entry is "current" for the time of day --

func test_time_block_for_hour_covers_the_full_day():
	for hour in range(24):
		assert_true(_TIME_BLOCKS.has(NpcSchedule.time_block_for_hour(hour)), "no time block for hour %d" % hour)


func test_entry_for_time_block_returns_the_matching_entry():
	var schedule := [
		{"time_block": "morning", "location_tag": "field", "activity": "work"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	assert_eq(NpcSchedule.entry_for_time_block(schedule, "night")["location_tag"], "home")


func test_entry_for_time_block_returns_empty_sentinel_when_missing():
	var entry := NpcSchedule.entry_for_time_block([], "morning")
	assert_eq(entry["location_tag"], "")
	assert_eq(entry["activity"], "")


func test_current_entry_resolves_from_an_hour():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var schedule := planner.plan_day(NpcIdentity.new(3), 0)
	var current := NpcSchedule.current_entry(schedule, 2)  # hour 2 -> night
	assert_eq(current["activity"], "sleep")
