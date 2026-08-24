extends RefCounted

## NPC Daily Planning (docs/concept/npc.md "Planning architecture"): once per
## in-game day, one call produces a rough {time_block, location_tag,
## activity} schedule for an NPC, informed by their identity/needs -- then a
## cheap local FSM (see NpcMarker) executes it tick-by-tick with zero further
## calls, only re-planning on day rollover or a significant interrupt.
##
## Mirrors WorldBossFitness's PhaseGenerator/FakePhaseGenerator split exactly
## (docs/roadmap.md "stubbed/fake LLM response" testing convention): Planner
## is the contract a real planner (e.g. a local LLM via Ollama, per the
## design brainstorm) implements; FakeNpcPlanner is a deterministic,
## occupation-keyed stand-in used everywhere today so the whole village
## simulation is real and testable before any LLM is wired in.

const NpcIdentity = preload("res://src/world/npc_identity.gd")


## The contract a real (LLM-backed or otherwise) planner implements. Base
## returns an empty schedule -- harmless default, matching PhaseGenerator's.
class Planner:
	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		return []


## Deterministic fake planner: never calls anything, always returns the same
## fixed, occupation-keyed day for a given identity. Every occupation's
## night entry is home/sleep; each occupation works its own location by day.
## Unrecognized occupations fall back to a generic idle-at-home/socialize day
## rather than crashing.
class FakeNpcPlanner extends Planner:
	func plan_day(identity: NpcIdentity, _day_index: int) -> Array:
		var work_location: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(identity.occupation, "")
		if work_location == "":
			return [
				{"time_block": "morning", "location_tag": "home", "activity": "idle"},
				{"time_block": "midday", "location_tag": "well", "activity": "socialize"},
				{"time_block": "evening", "location_tag": "well", "activity": "socialize"},
				{"time_block": "night", "location_tag": "home", "activity": "sleep"},
			]
		# A guard stays on watch through the evening instead of socializing at
		# the well -- everyone else's workday winds down there.
		var evening_location := "gate" if identity.occupation == "guard" else "well"
		var evening_activity := "work" if identity.occupation == "guard" else "socialize"
		return [
			{"time_block": "morning", "location_tag": work_location, "activity": "work"},
			{"time_block": "midday", "location_tag": work_location, "activity": "work"},
			{"time_block": "evening", "location_tag": evening_location, "activity": evening_activity},
			{"time_block": "night", "location_tag": "home", "activity": "sleep"},
		]
