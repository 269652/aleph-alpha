extends GutTest

## NpcRecognition (docs/concept/dialogue.md's "You are in the graph"):
## where the player stands with ONE villager -- stranger, knows_you, owed,
## trusted, disappointed.
##
## The traps this file exists to pin, in the order they would bite:
##
##   1. The floor is read from the APPEND-ONLY EventStore and the live
##      ContractStore, never from MemoryStore. MemoryStore._store overwrites
##      unconditionally on (holder, event_id), so a retelling can replace a
##      villager's own firsthand record of what you did; a relationship you
##      actually earned must not be lose-able that way. Hearsay is read for
##      exactly one thing -- lifting a STRANGER to KNOWS_YOU -- and can never
##      lower a tier or manufacture an obligation.
##   2. Both sides answer to TWO names. Contracts and the events that record
##      them name HOUSEHOLDS ("household:local"), while a conversation event
##      names the person ("player:local"), so reading only one of the two
##      finds none of the other's history.
##   3. Outcomes are ordered by APPEND order, not by tick. A whole
##      propose -> accept -> activate -> fulfil chain runs inside one
##      settlement step at one world_age_seconds, so ticks tie and cannot say
##      which of two outcomes came last.

const NpcRecognition = preload("res://src/dialogue/npc_recognition.gd")
const Contract = preload("res://src/emergence/contract.gd")
const ContractStore = preload("res://src/emergence/contract_store.gd")
const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const Household = preload("res://src/emergence/household.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const Rumor = preload("res://src/emergence/rumor.gd")

const NPC_ID := "npc:4711"
const NPC_HOUSEHOLD := "household:4711"
const OTHER_NPC_ID := "npc:99"
const PLAYER_ID := "player:local"
const PLAYER_HOUSEHOLD := "household:local"

var events: EventStore
var contracts: ContractStore


func before_each():
	events = EventStore.new()
	contracts = ContractStore.new()


# -- helpers -----------------------------------------------------------------


func _append(type: String, actors: Array, witnesses: Array = [], tick: float = 0.0) -> String:
	var event := Event.new(type, tick)
	for actor in actors:
		event.actors.append(str(actor))
	for witness in witnesses:
		event.witnesses.append(str(witness))
	return events.append(event)


## A contract driven to `status` through the real ContractStore lifecycle,
## and (unless `record_events` is false) the same outcome event
## EarthChunkManager._record_contract_event would have appended alongside it.
func _contract(status: String, parties: Array = [], record_events := true, tick := 0.0) -> String:
	var actual_parties: Array = parties
	if actual_parties.is_empty():
		actual_parties = [PLAYER_HOUSEHOLD, NPC_ID]
	var contract = contracts.propose(
		"supply", actual_parties, ["3 rock"], "6 gold", -1.0, tick
	)
	if status == Contract.PROPOSED:
		return contract.id
	contracts.accept(contract.id, tick)
	if status == Contract.ACCEPTED:
		return contract.id
	if status == Contract.CANCELLED:
		contracts.cancel(contract.id, tick)
		if record_events:
			_append("contract_cancelled", actual_parties, [], tick)
		return contract.id
	contracts.activate(contract.id, tick)
	if status == Contract.ACTIVE:
		return contract.id
	if status == Contract.FULFILLED:
		contracts.fulfill(contract.id, tick)
		if record_events:
			_append("contract_fulfilled", actual_parties, [], tick)
	elif status == Contract.BREACHED:
		contracts.breach(contract.id, tick)
		if record_events:
			_append("contract_breached", actual_parties, [], tick)
	elif status == Contract.DEFAULTED:
		contracts.default_on(contract.id, tick)
		if record_events:
			_append("contract_defaulted", actual_parties, [], tick)
	return contract.id


func _sources(extra: Dictionary = {}) -> Dictionary:
	var sources := {
		"npc_id": NPC_ID,
		"player_id": PLAYER_ID,
		"event_store": events,
		"contract_store": contracts,
	}
	for key in extra:
		sources[key] = extra[key]
	return sources


func _memory(actors: Array, confidence := 1.0, distortion := 0.0) -> Dictionary:
	return {
		"event_type": "player_helped",
		"actors": actors,
		"confidence": confidence,
		"distortion": distortion,
	}


# -- the tier list itself ----------------------------------------------------


func test_the_five_tiers_are_the_ones_the_spec_names():
	assert_eq(
		NpcRecognition.TIERS,
		["stranger", "knows_you", "owed", "trusted", "disappointed"]
	)


# -- trap 2: both sides answer to two names ----------------------------------


## The derivation is not a convention invented here: it is exactly the id
## Household.for_founder builds, which is what HouseholdStore.form_household
## actually put in the contract.
func test_parties_of_is_the_entity_and_the_household_it_founds():
	assert_eq(NpcRecognition.parties_of(NPC_ID), [NPC_ID, Household.for_founder(NPC_ID).id])
	assert_eq(NpcRecognition.parties_of(NPC_ID), [NPC_ID, NPC_HOUSEHOLD])
	assert_eq(
		NpcRecognition.parties_of(PlayerIdentity.PLAYER_ENTITY_ID),
		[PLAYER_ID, PLAYER_HOUSEHOLD]
	)


func test_parties_of_a_household_does_not_repeat_it():
	assert_eq(NpcRecognition.parties_of(PLAYER_HOUSEHOLD), [PLAYER_HOUSEHOLD])


func test_parties_of_a_non_entity_is_empty():
	assert_eq(NpcRecognition.parties_of(""), [])
	assert_eq(NpcRecognition.parties_of("nonsense"), [])


## Trap 2 proper: the only actor of player_claimed_property is
## "household:local", so a reader that only knows "player:local" sees none of
## the player's own recorded history.
func test_an_event_naming_only_your_household_is_still_your_history():
	_append("player_claimed_property", [PLAYER_HOUSEHOLD], [NPC_ID])
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.KNOWS_YOU)
	assert_eq(result["shared_event_count"], 1)


# -- stranger ----------------------------------------------------------------


func test_a_villager_you_have_never_met_is_a_stranger():
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.STRANGER)
	assert_eq(result["shared_event_count"], 0)
	assert_false(result["heard_of_you"])


func test_missing_stores_fail_open_to_stranger():
	var result := NpcRecognition.tier_for({"npc_id": NPC_ID, "player_id": PLAYER_ID})
	assert_eq(result["tier"], NpcRecognition.STRANGER)


func test_an_event_shared_with_someone_else_leaves_this_villager_a_stranger():
	_append("conversation", [PLAYER_ID], [OTHER_NPC_ID])
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.STRANGER)


## Standing in the same crowd is not history WITH someone: the player has to
## have done something. Without this the whole village knows you the moment
## you watch one settlement event.
func test_an_event_you_only_witnessed_does_not_make_them_know_you():
	_append("settlement_founded", [NPC_ID], [PLAYER_ID])
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.STRANGER)
	assert_eq(result["shared_event_count"], 0)


# -- knows_you ---------------------------------------------------------------


func test_an_act_of_yours_they_witnessed_makes_them_know_you():
	_append("conversation", [PLAYER_ID], [NPC_ID])
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.KNOWS_YOU)
	assert_eq(result["floor_tier"], NpcRecognition.KNOWS_YOU)
	assert_eq(result["shared_event_count"], 1)


## A proposal is not yet an agreement -- nobody has promised anything, so
## nothing is owed. It is still a meeting.
func test_a_merely_proposed_contract_is_not_owed():
	_contract(Contract.PROPOSED)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.KNOWS_YOU)
	assert_eq(result["open_contract_ids"], [])


## Contract's own lifecycle doc calls cancellation the PRE-ACTIVATION exit;
## breach and default are the failures. Backing out before anyone was on the
## hook is not a broken promise.
func test_a_cancelled_contract_is_not_a_broken_promise():
	_contract(Contract.CANCELLED)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.KNOWS_YOU)
	assert_eq(result["failed_contract_ids"], [])


# -- owed --------------------------------------------------------------------


func test_an_accepted_contract_between_you_is_owed():
	var contract_id := _contract(Contract.ACCEPTED)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.OWED)
	assert_eq(result["open_contract_ids"], [contract_id])


func test_an_active_contract_between_you_is_owed():
	var contract_id := _contract(Contract.ACTIVE)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.OWED)
	assert_eq(result["open_contract_ids"], [contract_id])


## A contract names its parties and has no witnesses. Someone who merely
## watched you shake hands with their neighbour is not owed anything by you,
## however firsthand their knowledge of it is.
func test_a_bystander_to_your_contract_is_not_owed():
	_contract(Contract.ACTIVE, [PLAYER_HOUSEHOLD, OTHER_NPC_ID])
	_append("contract_accepted", [PLAYER_HOUSEHOLD, OTHER_NPC_ID], [NPC_ID])
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.KNOWS_YOU)
	assert_eq(result["open_contract_ids"], [])


# -- trusted and disappointed ------------------------------------------------


func test_a_fulfilled_contract_makes_you_trusted():
	var contract_id := _contract(Contract.FULFILLED)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.TRUSTED)
	assert_eq(result["fulfilled_contract_ids"], [contract_id])
	assert_eq(result["last_outcome"], "contract_fulfilled")


func test_a_breached_contract_disappoints_them():
	var contract_id := _contract(Contract.BREACHED)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.DISAPPOINTED)
	assert_eq(result["failed_contract_ids"], [contract_id])
	assert_eq(result["last_outcome"], "contract_breached")


func test_a_defaulted_contract_disappoints_them():
	_contract(Contract.DEFAULTED)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.DISAPPOINTED)


## A live errand does not erase a broken promise -- you are redeemed by
## delivering, not by taking on more.
func test_an_open_contract_does_not_erase_an_earlier_breach():
	_contract(Contract.BREACHED)
	_contract(Contract.ACTIVE)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.DISAPPOINTED)
	assert_eq(result["open_contract_ids"].size(), 1)


func test_a_later_fulfilment_redeems_an_earlier_breach():
	_contract(Contract.BREACHED)
	_contract(Contract.FULFILLED)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.TRUSTED)
	assert_eq(result["last_outcome"], "contract_fulfilled")


func test_an_earlier_fulfilment_does_not_survive_a_later_breach():
	_contract(Contract.FULFILLED)
	_contract(Contract.BREACHED)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.DISAPPOINTED)


## Trap 3. Both outcomes happen at the same world_age_seconds, exactly as a
## settlement step produces them, so the tick cannot order them and the
## append ordinal must.
func test_outcomes_at_the_same_tick_are_ordered_by_append_order():
	_contract(Contract.FULFILLED, [], true, 5.0)
	_contract(Contract.BREACHED, [], true, 5.0)
	assert_eq(NpcRecognition.tier_for(_sources())["tier"], NpcRecognition.DISAPPOINTED)

	before_each()
	_contract(Contract.BREACHED, [], true, 5.0)
	_contract(Contract.FULFILLED, [], true, 5.0)
	assert_eq(NpcRecognition.tier_for(_sources())["tier"], NpcRecognition.TRUSTED)


## ContractStore records no tick for a transition (its accept/fulfill/breach
## all ignore the tick they are handed), so with no event to order by, a
## failure stands. Live contract state alone still answers.
func test_contract_state_alone_still_answers_with_no_outcome_events():
	_contract(Contract.FULFILLED, [], false)
	_contract(Contract.BREACHED, [], false)
	var result := NpcRecognition.tier_for(_sources())
	assert_eq(result["tier"], NpcRecognition.DISAPPOINTED)
	assert_eq(result["last_outcome"], "")


# -- trap 1: hearsay may lift, never lower, never invent ---------------------


func test_hearsay_lifts_a_stranger_to_someone_who_has_heard_of_you():
	var result := NpcRecognition.tier_for(_sources({
		"memories": [_memory([PLAYER_ID], 0.5, 0.0)],
	}))
	assert_eq(result["floor_tier"], NpcRecognition.STRANGER)
	assert_eq(result["tier"], NpcRecognition.KNOWS_YOU)
	assert_true(result["heard_of_you"])
	assert_almost_eq(result["hearsay_strength"], 0.5, 0.0001)


func test_hearsay_about_your_household_is_hearsay_about_you():
	var result := NpcRecognition.tier_for(_sources({
		"memories": [_memory([PLAYER_HOUSEHOLD])],
	}))
	assert_eq(result["tier"], NpcRecognition.KNOWS_YOU)


func test_hearsay_about_someone_else_is_not_about_you():
	var result := NpcRecognition.tier_for(_sources({
		"memories": [_memory([OTHER_NPC_ID])],
	}))
	assert_eq(result["tier"], NpcRecognition.STRANGER)
	assert_false(result["heard_of_you"])


## However certain the village is that you are wonderful, trust is an
## agreement you kept, and an obligation is one you took on. Neither can be
## conjured out of talk.
func test_hearsay_cannot_manufacture_trust_or_an_obligation():
	var result := NpcRecognition.tier_for(_sources({
		"memories": [
			{
				"event_type": "contract_fulfilled",
				"actors": [PLAYER_HOUSEHOLD, NPC_ID],
				"confidence": 1.0,
				"distortion": 0.0,
			},
		],
	}))
	assert_eq(result["tier"], NpcRecognition.KNOWS_YOU)
	assert_eq(result["fulfilled_contract_ids"], [])
	assert_eq(result["open_contract_ids"], [])


## The whole reason this module reads EventStore: MemoryStore._store
## overwrites unconditionally on (holder, event_id), so a villager can be
## talked out of their own record. Nothing they hold -- or stop holding --
## touches the floor.
func test_an_empty_memory_bank_cannot_lower_what_really_happened():
	_contract(Contract.FULFILLED)
	var result := NpcRecognition.tier_for(_sources({"memories": []}))
	assert_eq(result["tier"], NpcRecognition.TRUSTED)
	assert_false(result["heard_of_you"])


## Where "has heard of you" stops is measured, not picked: Rumor's own
## DISTORTION_PER_HOP (0.35) clamps distortion to 1.0 on the third retelling,
## and a belief with no surviving strength is not knowledge of anything.
func test_a_belief_retold_until_nothing_survives_is_not_having_heard_of_you():
	var event := Event.new("conversation", 0.0)
	event.actors.append(PLAYER_ID)
	event.witnesses.append(OTHER_NPC_ID)
	events.append(event)
	var memory = MemoryRecord.from_event(event, OTHER_NPC_ID, 0.0)

	var hops: Array = []
	for hop in range(3):
		memory = Rumor.transmit(memory, "npc:%d" % hop, float(hop))
		hops.append({
			"actors": memory.remembered_actors,
			"confidence": memory.confidence,
			"distortion": memory.distortion,
		})

	assert_true(
		NpcRecognition.tier_for(_sources({"memories": [hops[1]]}))["heard_of_you"],
		"two retellings still leave something of the account"
	)
	assert_false(
		NpcRecognition.tier_for(_sources({"memories": [hops[2]]}))["heard_of_you"],
		"the third retelling clamps distortion to 1.0 and nothing survives"
	)
