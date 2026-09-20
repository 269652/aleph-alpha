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
	quit()
