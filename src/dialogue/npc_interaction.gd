extends RefCounted

## One real talk interaction with a villager -- the next real step past
## `NpcGreeting`'s bare deterministic line (docs/concept/npc.md's "Minimal
## talk interaction" placeholder) and short of the full Live Dialogue System
## (docs/concept/dialogue.md's `DialogueTopic`/`DialogueMove`/`DialogueBeat`/
## `OfflineRenderer`/`ConversationWindow` pipeline, which has no `DialogueBeat`
## or renderer yet). Composes two pieces that are already real and already
## tested rather than inventing a third:
##
##   * `NpcGreeting` -- the personality/need-flavored line itself.
##   * `DialogueContext` -- the ONE place the conversation system reads the
##     world, asked here for exactly one fact: `time_block`, sourced from the
##     shared world clock the same way the NPC's own `NpcSchedule`/
##     `NpcPlanner` daily plan already is (never `NpcMarker`'s private,
##     per-marker clock -- see `DialogueContext`'s own "trap 3" doc comment).
##
## dialogue.md pillar 3, "the player is a node in the graph, not a camera":
## talking is a real act that writes real state. So this module also records
## the interaction the same way every other real event in this codebase is
## recorded -- `Event` -> `EventStore.append` -> `MemoryStore.witness_event`
## (see e.g. `EarthChunkManager.claim_property_with_deed`) -- with BOTH the
## player and the villager as actors, so both hold a firsthand memory of the
## same conversation afterward. That also means `NpcRecognition` (which reads
## exactly this event shape) stops calling the player a stranger after one
## real conversation, with no change of its own required.
##
## No topics, no branching, no quest hooks, no phrasing pools -- one
## greeting in, one real event and up to two real memories out. Pure:
## Dictionaries and stores in, a Dictionary out, no Node of its own.

const DialogueContext = preload("res://src/dialogue/dialogue_context.gd")
const Event = preload("res://src/emergence/event.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const NpcGreeting = preload("res://src/world/npc_greeting.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")

## The event type this interaction is recorded as -- "player_verb_object",
## the same naming shape every other player-caused event in src/ already
## uses (player_claimed_property, player_settled).
const EVENT_TYPE := "player_talked_to_npc"

## One line per NpcSchedule.TIME_BLOCKS (see that module), appended after
## NpcGreeting's own personality/need line -- how the SAME villager's
## greeting changes across their own day without inventing a second voice
## for them. Keyed exactly like NpcGreeting's own _TRAIT_LINES/_NEED_PHRASES
## tables, and empty ("" -- DialogueContext.HOUR_UNKNOWN's own frame value)
## deliberately has no entry, so a caller with no world clock gets the bare
## line back unchanged rather than an invented time of day (dialogue.md
## pillar 2: an empty fact adds nothing, it does not fall back to filler).
const _TIME_BLOCK_ASIDES := {
	"morning": "The morning's still young.",
	"midday": "The sun's high overhead.",
	"evening": "Evening's settling in.",
	"night": "It's late to be out and about.",
}


## One real interaction with `identity`. `sources` is DialogueContext.build's
## own bag (see its doc comment for the full list) plus:
##
##   player_id      String -- defaults to PlayerIdentity.PLAYER_ENTITY_ID
##   event_store    EventStore
##   memory_store   MemoryStore
##
## The interaction is recorded -- a real Event appended to `event_store`,
## witnessed into `memory_store` by both parties -- only when BOTH stores are
## supplied, mirroring the pairing every other emitter in this codebase
## already uses (Event -> EventStore.append -> MemoryStore.witness_event):
## a memory whose `event_id` cannot be resolved back to a real stored event
## is not "referencing the interaction", so this never records one half of
## the pair without the other. Fails open otherwise (same contract as every
## other source in this pipeline) -- the greeting still returns, nothing is
## remembered.
##
## Returns {"greeting": String, "time_block": String, "frame": Dictionary,
## "event": Event, "npc_memory": MemoryRecord (or null),
## "player_memory": MemoryRecord (or null)}.
static func talk(identity: NpcIdentity, sources: Dictionary) -> Dictionary:
	var npc_id := EntityRef.for_npc(identity.seed_value)
	var player_id := str(sources.get("player_id", PlayerIdentity.PLAYER_ENTITY_ID))

	var frame_sources := sources.duplicate()
	frame_sources["identity"] = identity
	var frame := DialogueContext.build(npc_id, frame_sources)
	var time_block := str(frame.get("time_block", ""))

	var world_age := float(sources.get("world_age_seconds", 0.0))
	var event := Event.new(EVENT_TYPE, world_age)
	event.actors = [player_id, npc_id]

	var npc_memory = null
	var player_memory = null
	var event_store = sources.get("event_store")
	var memory_store = sources.get("memory_store")
	if event_store != null and memory_store != null:
		event_store.append(event)
		for memory in memory_store.witness_event(event, world_age):
			if memory.holder == npc_id:
				npc_memory = memory
			elif memory.holder == player_id:
				player_memory = memory

	return {
		"greeting": greeting_for(identity, time_block),
		"time_block": time_block,
		"frame": frame,
		"event": event,
		"npc_memory": npc_memory,
		"player_memory": player_memory,
	}


## The greeting line alone, with no event/memory side effects -- NpcGreeting's
## own personality/need line, with a time-of-day aside appended when
## `time_block` names one (see _TIME_BLOCK_ASIDES). `time_block` defaults to
## "" (no known time of day), which returns NpcGreeting's line completely
## unchanged.
static func greeting_for(identity: NpcIdentity, time_block: String = "") -> String:
	var base := NpcGreeting.new().greeting_for(identity)
	var aside: String = _TIME_BLOCK_ASIDES.get(time_block, "")
	if aside == "":
		return base
	return "%s %s" % [base, aside]
