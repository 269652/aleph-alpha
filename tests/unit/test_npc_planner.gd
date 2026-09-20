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


## A hunter's schedule should route them to a hunting ground, not the
## farmer's field -- gathering wild game is a distinct role (see
## docs/concept/npc.md "Needs and the local production economy").
func test_fake_planner_hunter_works_at_the_hunting_ground():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var identity: NpcIdentity
	for seed_value in range(50):
		var candidate := NpcIdentity.new(seed_value)
		if candidate.occupation == "hunter":
			identity = candidate
			break
	assert_not_null(identity, "precondition: expected a hunter within 50 seeds")
	var schedule := planner.plan_day(identity, 0)
	var midday := NpcSchedule.entry_for_time_block(schedule, "midday")
	assert_eq(midday["location_tag"], "hunting_ground")
	assert_eq(midday["activity"], "work")


## A nurse (new non-producer village-care role) works the shared well/square
## rather than a dedicated building that doesn't exist yet -- documented
## judgment call, see docs/concept/npc.md.
func test_fake_planner_nurse_works_at_the_well():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var identity: NpcIdentity
	for seed_value in range(50):
		var candidate := NpcIdentity.new(seed_value)
		if candidate.occupation == "nurse":
			identity = candidate
			break
	assert_not_null(identity, "precondition: expected a nurse within 50 seeds")
	var schedule := planner.plan_day(identity, 0)
	var midday := NpcSchedule.entry_for_time_block(schedule, "midday")
	assert_eq(midday["location_tag"], "well")
	assert_eq(midday["activity"], "work")


## A guard stays on watch at the gate through the evening instead of
## socializing at the well like every other occupation -- the one
## occupation-specific exception in FakeNpcPlanner's own evening branch.
## Previously asserted only indirectly (through NpcMarker's resolved
## position in test_npc_daily_schedule_walk.gd) and never at the planner's
## own schedule-shape level the way every other occupation branch above
## already is.
func test_fake_planner_guard_stays_on_watch_at_the_gate_through_the_evening():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var identity: NpcIdentity
	for seed_value in range(50):
		var candidate := NpcIdentity.new(seed_value)
		if candidate.occupation == "guard":
			identity = candidate
			break
	assert_not_null(identity, "precondition: expected a guard within 50 seeds")
	var schedule := planner.plan_day(identity, 0)
	var evening := NpcSchedule.entry_for_time_block(schedule, "evening")
	assert_eq(evening["location_tag"], "gate")
	assert_eq(evening["activity"], "work")


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


# -- the square is not a waiting room (2026-09-20) --------------------------
#
# Reported live: *"All NPCs walk to the well at the same moments... and it's
# not visible what they are doing."* Measured before changing anything
# (tools/probe_well_crowding.gd), on a real twelve-villager roster: the
# evening block sent **ten of twelve** to the well, all performing
# `socialize`.
#
# NpcSchedule.personal_hour already staggers when each villager's day
# turns, and it works -- but it cannot help when the DESTINATION is the same
# for almost everyone across a five-hour block. They arrive a couple of
# hours apart and then stand together until night. The crowd is a fact about
# where the plan sends people, not about when.
#
# So the evening is each villager's own: some at the well, some at the
# market stall, some simply home. The well is reached by ERRAND
# (docs/concept/village_water.md) or not at all.

const _EVENING_ROSTER := 24


func _evening_spread() -> Dictionary:
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var counts := {}
	for i in _EVENING_ROSTER:
		var identity := NpcIdentity.new(hash("evening_%d" % i))
		for entry in planner.plan_day(identity, 0):
			if String(entry["time_block"]) != "evening":
				continue
			var tag := String(entry["location_tag"])
			counts[tag] = int(counts.get(tag, 0)) + 1
	return counts


func test_no_single_spot_swallows_the_village_in_the_evening():
	var counts := _evening_spread()
	var biggest := 0
	var busiest := ""
	for tag in counts:
		if int(counts[tag]) > biggest:
			biggest = int(counts[tag])
			busiest = tag
	assert_lt(
		float(biggest) / float(_EVENING_ROSTER), 0.5,
		"%d of %d villagers spend the evening at the %s" % [biggest, _EVENING_ROSTER, busiest]
	)


func test_the_evening_really_is_spread_over_several_places():
	assert_gte(_evening_spread().size(), 3, "the whole village has one evening between them")


## Each villager's own evening, the same way their own day-shift is theirs:
## stable across days, so somebody who drinks at the well is a regular
## rather than somebody who wanders differently every night.
func test_a_villagers_evening_is_their_own_and_does_not_wander():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var identity := NpcIdentity.new(4242)
	var first := ""
	for day in 5:
		for entry in planner.plan_day(identity, day):
			if String(entry["time_block"]) == "evening":
				if first == "":
					first = String(entry["location_tag"])
				assert_eq(String(entry["location_tag"]), first, "day %d" % day)


## A guard still holds the gate -- that was already true and must stay so.
func test_a_guard_still_works_the_gate_in_the_evening():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var guard := NpcIdentity.new(7, "guard")
	for entry in planner.plan_day(guard, 0):
		if String(entry["time_block"]) == "evening":
			assert_eq(String(entry["location_tag"]), "gate")
			assert_eq(String(entry["activity"]), "work")


## Nobody is SCHEDULED to fetch water. The well appears in an evening plan
## only as somewhere to be, never as an errand -- the errand is decided by
## the household's own tank (village_water.md pillar 1).
func test_the_plan_never_schedules_the_water_errand():
	var planner := NpcPlanner.FakeNpcPlanner.new()
	for i in _EVENING_ROSTER:
		var identity := NpcIdentity.new(hash("errand_%d" % i))
		for entry in planner.plan_day(identity, 0):
			assert_ne(String(entry["activity"]), "fetch_water",
				"a villager was put on the water errand by a timetable")
