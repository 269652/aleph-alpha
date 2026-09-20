extends SceneTree

## Reported live: *"All NPCs walk to the well at the same moments... and it's
## not visible what they are doing."*
##
## Counts, for a real village roster, how many villagers each time block
## sends to the same spot -- so "at the same moments" is a number rather
## than an impression, and so the fix has something to be measured against.
##
## Usage: godot --headless -s tools/probe_well_crowding.gd

const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const HouseholdWater = preload("res://src/emergence/household_water.gd")
const WaterErrand = preload("res://src/emergence/water_errand.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const VILLAGERS := 12


func _initialize() -> void:
	var planner := NpcPlanner.FakeNpcPlanner.new()
	var roster: Array = []
	for i in VILLAGERS:
		roster.append(NpcIdentity.new(hash("well_probe_%d" % i)))

	var blocks := ["morning", "midday", "evening", "night"]
	print("-- %d villagers, where each time block sends them --" % VILLAGERS)
	for block in blocks:
		var by_tag := {}
		for identity in roster:
			for entry in planner.plan_day(identity, 0):
				if String(entry["time_block"]) != block:
					continue
				var tag := String(entry["location_tag"])
				by_tag[tag] = int(by_tag.get(tag, 0)) + 1
		var parts: Array[String] = []
		var biggest := 0
		for tag in by_tag:
			parts.append("%s x%d" % [tag, int(by_tag[tag])])
			biggest = maxi(biggest, int(by_tag[tag]))
		parts.sort()
		print("  %-8s %-58s busiest spot holds %d of %d" % [block, ", ".join(parts), biggest, VILLAGERS])

	print("\n-- what they are doing there --")
	var activities := {}
	for identity in roster:
		for entry in planner.plan_day(identity, 0):
			var key := "%s/%s" % [entry["location_tag"], entry["activity"]]
			activities[key] = int(activities.get(key, 0)) + 1
	var keys: Array = activities.keys()
	keys.sort()
	for key in keys:
		print("  %-26s x%d" % [key, int(activities[key])])

	_print_water_rhythm()
	_print_farm_rhythm()
	quit()


## What the water errand actually produces over a season: how often each
## household has to send somebody, and how many of them are out fetching
## on any given day. The second number is the one the report was about --
## if it spikes, the square is a waiting room again.
func _print_water_rhythm() -> void:
	var households := 12
	var levels: Array = []
	for i in households:
		levels.append(HouseholdWater.starting_level(hash("water_house_%d" % i)))
	var trips_by_day: Array = []
	var total_trips := 0
	var days := int(SeasonCycle.DAYS_PER_YEAR / 4.0)
	for day in days:
		var out_today := 0
		for i in households:
			levels[i] = HouseholdWater.level_after(levels[i], 1, 1.0)
			if HouseholdWater.trip_is_due(levels[i]):
				levels[i] = WaterErrand.poured(levels[i])
				out_today += 1
				total_trips += 1
		trips_by_day.append(out_today)
	var busiest := 0
	for n in trips_by_day:
		busiest = maxi(busiest, int(n))
	print("\n-- the water errand over one season (%d days, %d households) --" % [days, households])
	print("  trips in all: %d  (about one per household every %.1f days)" % [
		total_trips, float(days * households) / float(maxi(total_trips, 1))
	])
	print("  busiest day sent %d of %d households to the well" % [busiest, households])
	print("  day by day: %s" % str(trips_by_day))


## What a FARMHOUSE's tank produces (docs/concept/village_water.md
## mechanism 3), against a cottage's on the same span. The claim being
## measured is pillar 5: somebody is at the well for a farm OFTENER than
## for a household, because a farmhouse's tank has a field on it.
##
## The tending rate is HouseholdWater.TENDINGS_PER_SIMULATED_DAY, which is
## itself measured against a real village by tools/probe_farm_water.gd --
## this probe deliberately does NOT invent one. The first cut of this
## feature guessed 1.33 here, was wrong by a factor of four, and starved
## every field in the game until the real thing was measured.
func _print_farm_rhythm() -> void:
	var days := int(SeasonCycle.DAYS_PER_YEAR / 4.0)
	var rate := HouseholdWater.TENDINGS_PER_SIMULATED_DAY
	print("\n-- the farmhouse's own tank over one season (%d days, %.1f tendings/day) --" % [days, rate])
	var level := HouseholdWater.farm_starting_level(hash("probe_farm"))
	var trips := 0
	var dry_days := 0
	var carried := 0.0
	for day in days:
		carried += rate
		while carried >= 1.0:
			if not HouseholdWater.can_water_crops(level):
				dry_days += 1
				break
			level = HouseholdWater.level_after_tending(level)
			carried -= 1.0
		if HouseholdWater.farm_trip_is_due(level):
			level = WaterErrand.poured(level)
			trips += 1
	print("  %2d trips, one every %.1f days, %d day(s) the beds went dry" % [
		trips, float(days) / float(maxi(trips, 1)), dry_days
	])
	print("  the pure rule's own answer: one every %.1f days" % HouseholdWater.days_between_farm_trips())

	# Averaged over a whole village's worth of cottages rather than one, so
	# the comparison is not decided by which level a single seed started at.
	var cottages := 12
	var cottage_trips := 0
	for i in cottages:
		var cottage := HouseholdWater.starting_level(hash("probe_cottage_%d" % i))
		for day in days:
			cottage = HouseholdWater.level_after(cottage, 1, 1.0)
			if HouseholdWater.trip_is_due(cottage):
				cottage = WaterErrand.poured(cottage)
				cottage_trips += 1
	print("  %d one-person cottages, for comparison: one trip every %.1f days each" % [
		cottages, float(days * cottages) / float(maxi(cottage_trips, 1))
	])
