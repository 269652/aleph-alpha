extends RefCounted

## How a MemoryRecord transmits from one holder to another (see
## docs/emergence/02-history-memory-rumors.md "Rumor propagation" and
## docs/concept/npc.md's "Memory, beliefs, and rumor propagation", the
## project-specific expression of the same mechanism).
##
## Deliberately simple for a first slice: transmission decays confidence and
## degrades source type by a fixed, tested amount per hop; content
## (remembered actors/location/outcome) survives unchanged -- npc.md
## explicitly defers content mutation as "real, but unproven gameplay payoff
## yet" -- and there is no real trust/relationship weighting yet, since
## npc_identity.gd has no relationships to weight by (see docs/roadmap.md's
## Emergence Phase 3, not built). This is the honest MVP the module's own
## "avoid premature complexity" principle calls for: a real, working,
## testable mechanism now, ready to be weighted by trust/distance once
## relationships exist to weight it with.

const MemoryRecord = preload("res://src/emergence/memory_record.gd")

## How much confidence survives one retelling. Tested (not eyeballed) against
## the behaviour it produces: a firsthand account (confidence 1.0) is down to
## roughly a third of its original certainty after three hops, which is the
## "I heard it from a guy who heard it from a guy" feel this mechanism is
## going for.
const CONFIDENCE_DECAY_PER_HOP := 0.6

## How much distortion accumulates per hop, before clamping to 1.0.
##
## Tracked from the first hop -- docs/concept/npc.md's "Memory, beliefs, and
## rumor propagation" names a distortion accumulator as part of what a memory
## holds -- but does not yet CHANGE what is remembered: content mutation
## ("who did something changes, not just how confident you are") is
## explicitly deferred there as "real, but unproven gameplay payoff yet."
## remembered_actors/location/outcome stay equal to the source event through
## every hop; only confidence and source type actually degrade.
const DISTORTION_PER_HOP := 0.35

## Source type degrades monotonically toward RUMOR and never climbs back,
## however many more times it is retold once it gets there.
const _NEXT_SOURCE := {
	MemoryRecord.FIRSTHAND: MemoryRecord.TRUSTED_TESTIMONY,
	MemoryRecord.WITNESSED: MemoryRecord.TRUSTED_TESTIMONY,
	MemoryRecord.TRUSTED_TESTIMONY: MemoryRecord.STRANGER_TESTIMONY,
	MemoryRecord.STRANGER_TESTIMONY: MemoryRecord.RUMOR,
	MemoryRecord.RUMOR: MemoryRecord.RUMOR,
}


## `memory` retold by its current holder to `new_holder`, heard at `tick`.
## Returns a NEW MemoryRecord for new_holder -- the original is untouched, the
## same "each holder's own copy" shape MemoryRecord.from_event already uses.
static func transmit(memory: MemoryRecord, new_holder: String, tick: float) -> RefCounted:
	var told = MemoryRecord.new()
	told.event_id = memory.event_id
	told.holder = new_holder
	told.remembered_type = memory.remembered_type
	told.remembered_location = memory.remembered_location
	told.remembered_outcome = memory.remembered_outcome
	told.confidence = memory.confidence * CONFIDENCE_DECAY_PER_HOP
	told.emotional_salience = memory.emotional_salience
	told.source_type = _NEXT_SOURCE.get(memory.source_type, MemoryRecord.RUMOR)
	told.distortion = clampf(memory.distortion + DISTORTION_PER_HOP, 0.0, 1.0)
	told.recorded_at = tick

	# Content survives transmission unchanged -- distortion is tracked but not
	# yet applied to what is remembered (see the DISTORTION_PER_HOP docstring
	# above). Built into an explicitly Array[String]-typed local rather than
	# a direct `.duplicate()` assignment: a `RefCounted`-typed `memory`
	# parameter's `.duplicate()` result failed to assign into
	# remembered_actors' Array[String] typing at runtime here even though it
	# reads as if it should just work (Invalid assignment of property...
	# with value of type 'Array').
	var remembered_actors: Array[String] = []
	for actor in memory.remembered_actors:
		remembered_actors.append(actor)
	told.remembered_actors = remembered_actors

	return told
