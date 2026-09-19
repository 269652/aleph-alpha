extends GutTest

## The live per-NPC trust value hiring_gate.gd has been waiting for.
##
## docs/concept/npc_instructions.md names this exact gap as the reason the
## whole hiring path is unreachable in a live game: "nowhere on a real
## NpcIdentity/NpcMarker actually holds a live trust value for
## hiring_gate.gd to read". This is that value.
##
## Deliberately the "minimal, player-only trust scalar" that doc already
## specifies -- not the full NPC-NPC relationship web, which is a different
## and much larger system.

const NpcTrustStore = preload("res://src/world/npc_trust_store.gd")
const NpcTrust = preload("res://src/world/npc_trust.gd")
const HiringGate = preload("res://src/world/hiring_gate.gd")

var store: NpcTrustStore


func before_each():
	store = NpcTrustStore.new()


## A stranger is not hostile, just unknown -- NpcTrust's own documented
## starting point, not a second opinion about where people begin.
func test_an_npc_you_have_never_met_sits_at_the_baseline():
	assert_eq(store.trust_of(1234), NpcTrust.BASELINE_TRUST)


## The knob the whole hiring economy turns on, so it is pinned here rather
## than eyeballed in a comment: baseline 0.2 to HIRE_THRESHOLD 0.5 is a
## 0.3 gap, and 0.1 a conversation means somebody takes a job from you on
## the THIRD real conversation, never on first meeting.
func test_three_conversations_is_what_it_takes_to_be_hireable():
	var npc := 7
	assert_false(store.is_hireable(npc), "a stranger will not take your job")
	store.record_conversation(npc)
	store.record_conversation(npc)
	assert_false(store.is_hireable(npc), "two is still not enough")
	store.record_conversation(npc)
	assert_true(store.is_hireable(npc), "the third conversation earns it")


func test_the_conversation_step_is_exactly_the_gap_over_three_conversations():
	assert_almost_eq(
		NpcTrust.BASELINE_TRUST + 3.0 * NpcTrustStore.TRUST_PER_CONVERSATION,
		NpcTrust.HIRE_THRESHOLD, 0.0001,
		"the step and the threshold must stay in step, or 'three conversations' becomes a lie"
	)


func test_trust_never_climbs_past_full():
	var npc := 3
	for _i in 100:
		store.record_conversation(npc)
	assert_eq(store.trust_of(npc), NpcTrust.FULL_TRUST)


func test_each_npc_keeps_their_own_opinion_of_you():
	store.record_conversation(1)
	store.record_conversation(1)
	store.record_conversation(1)
	assert_true(store.is_hireable(1))
	assert_false(store.is_hireable(2), "talking to one villager does not vouch for you with another")


## The store answers the same question HiringGate asks, so the two can
## never disagree about who is hireable.
func test_hireability_is_the_gates_own_answer_not_a_second_rule():
	var npc := 9
	store.record_conversation(npc)
	store.record_conversation(npc)
	store.record_conversation(npc)
	assert_eq(
		store.is_hireable(npc),
		HiringGate.can_hire(store.trust_of(npc), 1.0, 1.0),
		"one rule, asked from two places"
	)


func test_setting_trust_directly_is_clamped_to_the_real_range():
	store.set_trust(5, 99.0)
	assert_eq(store.trust_of(5), NpcTrust.FULL_TRUST)
	store.set_trust(5, -99.0)
	assert_eq(store.trust_of(5), 0.0)
