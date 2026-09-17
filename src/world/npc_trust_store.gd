extends RefCounted

## The live per-NPC trust value `hiring_gate.gd` has been waiting for.
##
## docs/concept/npc_instructions.md names this exact absence as the reason
## the whole hiring path is unreachable in a live game: *"nowhere on a real
## NpcIdentity/NpcMarker actually holds a live trust value for
## hiring_gate.gd to read"*. This is that value, and nothing more -- the
## "minimal, deliberately player-only trust scalar" that doc already
## specifies, not the full NPC-NPC relationship web, which is a separate
## and far larger system.
##
## Keyed by `NpcIdentity.seed_value`: the stable per-NPC key this codebase
## already derives everything else about a villager from, so trust survives
## a marker being despawned and respawned with the chunk.

const NpcTrust = preload("res://src/world/npc_trust.gd")
const HiringGate = preload("res://src/world/hiring_gate.gd")

## How much one real conversation earns.
##
## A tuned value, so it is pinned by a test rather than asserted here
## (CLAUDE.md): NpcTrust's own BASELINE_TRUST (0.2) to its HIRE_THRESHOLD
## (0.5) is a 0.3 gap, and 0.1 a conversation makes that exactly THREE
## conversations. That is the real design statement -- somebody takes a job
## from you on the third real conversation, never on first meeting -- and
## test_the_conversation_step_is_exactly_the_gap_over_three_conversations
## keeps the step and the threshold from drifting apart and quietly making
## "three conversations" a lie.
const TRUST_PER_CONVERSATION := 0.1

var _trust: Dictionary = {}


## What this villager thinks of you. A stranger sits at NpcTrust's own
## documented baseline rather than at zero: unknown is not hostile.
func trust_of(npc_seed: int) -> float:
	return float(_trust.get(npc_seed, NpcTrust.BASELINE_TRUST))


## One real conversation's worth of getting to know you. Returns the new
## value so a caller can react to crossing a threshold without asking again.
func record_conversation(npc_seed: int) -> float:
	set_trust(npc_seed, trust_of(npc_seed) + TRUST_PER_CONVERSATION)
	return trust_of(npc_seed)


func set_trust(npc_seed: int, value: float) -> void:
	_trust[npc_seed] = clampf(value, 0.0, NpcTrust.FULL_TRUST)


## Whether this villager would enter a wage relationship with you at all.
##
## Asks HiringGate rather than comparing against HIRE_THRESHOLD here, so
## the store and the gate can never disagree about who is hireable -- one
## rule, asked from two places, which is the same reasoning HiringGate's
## own doc comment gives for splitting hiring from script complexity.
func is_hireable(npc_seed: int) -> bool:
	return HiringGate.can_hire(trust_of(npc_seed), 1.0, 1.0)
