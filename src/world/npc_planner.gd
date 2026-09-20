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
	## hunter -> "hunting_ground": a wild/edge-of-village spot, deliberately
	## not one of the settlement's 3 shared landmarks (well/stall/gate) --
	## like farmer's "field"/fisher's "dock", it resolves to this villager's
	## own personal workspot (see NpcMarker._resolve_location).
	##
	## nurse -> "well": a judgment call (docs/concept/npc.md leaves it open)
	## -- rather than invent a dedicated clinic building/landmark this pass,
	## a village-care role works the shared square, the same real prop every
	## settlement already has, instead of a work tag with nowhere real to
	## resolve to.
	##
	## Reads NpcIdentity.WORK_LOCATION_BY_OCCUPATION rather than keeping its
	## own copy of this mapping -- the single shared source both this planner
	## (which tag a villager's schedule sends them to) and VillageRenderer
	## (which landmark prop, if any, actually stands there) read from, so the
	## two can never drift apart.
	func plan_day(identity: NpcIdentity, _day_index: int) -> Array:
		var work_location: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(identity.occupation, "")
		if work_location == "":
			return [
				{"time_block": "morning", "location_tag": "home", "activity": "idle"},
				{"time_block": "midday", "location_tag": "well", "activity": "socialize"},
				{"time_block": "evening", "location_tag": "well", "activity": "socialize"},
				{"time_block": "night", "location_tag": "home", "activity": "sleep"},
			]
		# A guard stays on watch through the evening; everyone else's
		# evening is their OWN.
		#
		# It used to be the well, for everybody, and that is the whole of
		# the report: *"All NPCs walk to the well at the same moments... and
		# it's not visible what they are doing."* Measured, twenty-one
		# villagers of twenty-four spent every evening at one prop,
		# performing `socialize` -- a word with no verb behind it.
		#
		# NpcSchedule.personal_hour already staggers WHEN each villager's
		# day turns, and it works. It cannot help here: a four-hour spread
		# across a five-hour block still has almost everyone standing at the
		# same spot for most of it. The crowd was never about timing, it was
		# about the destination, so the destination is what changes.
		#
		# The well is reached by ERRAND now (docs/concept/village_water.md)
		# or not at all -- nobody is ever scheduled to fetch water, they go
		# when their own house runs dry.
		var evening_location := "gate" if identity.occupation == "guard" else _evening_haunt(identity)
		var evening_activity := "work" if identity.occupation == "guard" else "socialize"
		return [
			{"time_block": "morning", "location_tag": work_location, "activity": "work"},
			{"time_block": "midday", "location_tag": work_location, "activity": "work"},
			{"time_block": "evening", "location_tag": evening_location, "activity": evening_activity},
			{"time_block": "night", "location_tag": "home", "activity": "sleep"},
		]


	## Where this villager spends their own evening.
	##
	## Stable for a given villager, the same way NpcSchedule.shift_hours_for
	## makes their day-shift theirs: somebody who drinks at the well is a
	## regular rather than somebody who wanders somewhere different every
	## night. Drawn from the settlement's three shared landmarks plus simply
	## staying in -- every one of them is a real prop every village has
	## (see SettlementGenerator), so no villager is sent somewhere that does
	## not resolve.
	const EVENING_HAUNTS: Array[String] = ["well", "stall", "gate", "home"]

	static func _evening_haunt(identity: NpcIdentity) -> String:
		var index := absi(hash("%d_evening" % identity.seed_value)) % 10000
		return EVENING_HAUNTS[index % EVENING_HAUNTS.size()]
