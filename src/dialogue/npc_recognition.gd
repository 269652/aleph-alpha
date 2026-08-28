extends RefCounted

## Where the player stands with ONE villager (see docs/concept/dialogue.md's
## "You are in the graph": recognition goes `stranger -> knows you -> owed ->
## trusted -> disappointed`). One read, no state of its own.
##
## -- Why this reads EventStore and ContractStore, and not MemoryStore --
##
## A villager's beliefs are the wrong place to keep your relationship with
## them. MemoryStore._store writes `_memories[key] = memory` unconditionally
## on (holder, event_id), so a later, weaker account simply REPLACES an
## earlier stronger one for that holder -- and the gossip step runs on its
## own schedule, retelling things at Rumor.CONFIDENCE_DECAY_PER_HOP a hop. A
## relationship you actually earned must not be lose-able to a rumour about
## it. So the floor here comes from the two stores that cannot be argued
## with: EventStore is append-only (nothing in it is ever rewritten or
## removed), and a Contract's status is live ground truth rather than
## anyone's opinion of it.
##
## Hearsay is still read, for exactly ONE thing: lifting a STRANGER to
## KNOWS_YOU -- dialogue.md's "a stranger two settlements away eventually
## greets you as someone they have heard of". It can only ever raise, never
## lower, and it can never reach past KNOWS_YOU, because an obligation is
## something you took on and trust is an agreement you kept. Neither is
## conjurable out of talk.
##
## -- Both sides answer to two names --
##
## Contracts and the events that record them name HOUSEHOLDS: EarthChunkManager.
## player_propose_contract names `household:local`, and player_claimed_property's
## only actor is that same household id -- while a conversation event names the
## person, `player:local`. Reading only one of the two names finds none of the
## other's history, so every lookup here runs over both (see parties_of). The
## household id is not a convention invented here; it is derived exactly the
## way Household.for_founder derives it, from the founder's own key.
##
## -- Ordering outcomes --
##
## Two contract outcomes are ordered by APPEND order, not by tick. A whole
## propose -> accept -> activate -> fulfil chain runs inside a single
## settlement step at one `world_age_seconds`, so ticks genuinely tie and
## cannot say which came last; the event id carries the store's own append
## ordinal, and EventStore calls its insertion order "the deterministic read
## order". EarthChunkManager._recorded_contract_outcome walks the same entity
## index backwards for the same reason.
##
## Pure: Dictionaries and stores in, one Dictionary out. No Node, no clock, no
## writes -- reading where you stand changes nothing.

const Contract = preload("res://src/emergence/contract.gd")
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")

const STRANGER := "stranger"
const KNOWS_YOU := "knows_you"
const OWED := "owed"
const TRUSTED := "trusted"
const DISAPPOINTED := "disappointed"

## In dialogue.md's own narrative order. Deliberately NOT exposed as a rank:
## the tiers are not a magnitude (DISAPPOINTED is not "more" than TRUSTED),
## they are the branches of the precedence chain _floor_tier walks.
const TIERS: Array[String] = [STRANGER, KNOWS_YOU, OWED, TRUSTED, DISAPPOINTED]

## The event types EarthChunkManager._record_contract_event appends for a
## contract that ENDED -- its own _CONTRACT_OUTCOME_EVENTS minus
## contract_cancelled, which is not an outcome anyone was on the hook for
## (see FAILED_STATUSES).
const OUTCOME_FULFILLED := "contract_fulfilled"
const OUTCOME_BREACHED := "contract_breached"
const OUTCOME_DEFAULTED := "contract_defaulted"
const OUTCOME_EVENTS: Array[String] = [OUTCOME_FULFILLED, OUTCOME_BREACHED, OUTCOME_DEFAULTED]
const FAILURE_EVENTS: Array[String] = [OUTCOME_BREACHED, OUTCOME_DEFAULTED]

## A promise currently outstanding. PROPOSED is absent on purpose: an offer
## nobody accepted binds nobody, so it is a meeting, not a debt.
const OPEN_STATUSES: Array[String] = [Contract.ACCEPTED, Contract.ACTIVE]

## A promise broken. CANCELLED is absent for the reason Contract's own
## lifecycle doc gives: cancellation is the PRE-activation exit, taken before
## anyone was on the hook, while breach and default are the failures.
const FAILED_STATUSES: Array[String] = [Contract.BREACHED, Contract.DEFAULTED]


## Every id one entity is named by across the emergence stores: itself, plus
## the household it founds. Pinned against Household.for_founder by
## test_npc_recognition.gd, so the two cannot drift apart.
##
## Empty for anything that is not an entity reference at all, which makes a
## caller with no npc or no player resolve to STRANGER rather than matching
## everything.
static func parties_of(entity_id: String) -> Array[String]:
	var out: Array[String] = []
	if not EntityRef.is_valid(entity_id):
		return out
	out.append(entity_id)
	var household := EntityRef.for_kind("household", EntityRef.key_of(entity_id))
	if household != entity_id:
		out.append(household)
	return out


## Where the player stands with this villager, plus the real state it was
## read from. Recognised keys of `sources`, all optional:
##
##   npc_id          String  -- the villager, "npc:<seed>"
##   player_id       String  -- defaults to PlayerIdentity.PLAYER_ENTITY_ID
##   event_store     EventStore
##   contract_store  ContractStore
##   memories        Array   -- THIS villager's memory entries, in
##                              DialogueContext's frame shape
##
## The key names are the frame's own, so a caller can hand this the frame
## with the two stores added rather than repacking it.
##
## Fails open: an absent or wrong-shaped store contributes nothing instead of
## erroring, because a missing store means "no history recorded", and that is
## exactly a stranger.
static func tier_for(sources: Dictionary) -> Dictionary:
	var npc_parties := parties_of(str(sources.get("npc_id", "")))
	var player_parties := parties_of(
		str(sources.get("player_id", PlayerIdentity.PLAYER_ENTITY_ID))
	)

	var history := _shared_history(sources.get("event_store"), player_parties, npc_parties)
	var agreements := _shared_contracts(sources.get("contract_store"), player_parties, npc_parties)
	var hearsay := _hearsay_strength(sources.get("memories", []), player_parties)

	var floor_tier := _floor_tier(history, agreements)
	var tier := floor_tier
	if floor_tier == STRANGER and hearsay > 0.0:
		tier = KNOWS_YOU

	return {
		"tier": tier,
		"floor_tier": floor_tier,
		"shared_event_count": history["count"],
		"last_outcome": history["last_outcome"],
		"last_outcome_event_id": history["last_outcome_event_id"],
		"open_contract_ids": agreements["open"],
		"fulfilled_contract_ids": agreements["fulfilled"],
		"failed_contract_ids": agreements["failed"],
		"heard_of_you": hearsay > 0.0,
		"hearsay_strength": hearsay,
	}


## The precedence chain, strongest first. Not a score: each branch names the
## one real thing that puts you there.
##
##   1. A settled promise outranks a live one. Whether it settled well or
##      badly is decided by the LAST outcome between you, so delivering
##      redeems an earlier failure and failing spends an earlier success --
##      and taking on a new errand does neither.
##   2. An accepted or active contract is OWED.
##   3. Any shared history at all -- an act of yours they were there for, or
##      any contract between you, even one merely proposed or cancelled --
##      means they KNOW you.
static func _floor_tier(history: Dictionary, agreements: Dictionary) -> String:
	var failed: Array = agreements["failed"]
	var fulfilled: Array = agreements["fulfilled"]
	if not failed.is_empty() or not fulfilled.is_empty():
		return TRUSTED if _settled_well(str(history["last_outcome"]), failed) else DISAPPOINTED
	if not agreements["open"].is_empty():
		return OWED
	if int(history["count"]) > 0 or int(agreements["count"]) > 0:
		return KNOWS_YOU
	return STRANGER


## Whether the last thing to settle between you settled well.
##
## The event log is asked first, because it is the only one of the two stores
## that can ORDER two outcomes -- ContractStore.accept/fulfill/breach all
## discard the tick they are handed, so a contract's status records that it
## ended but not when. With no outcome event to order by, a failure stands
## rather than being cancelled out by an unordered success: what is known is
## that a promise was broken, and nothing says it was made good afterwards.
static func _settled_well(last_outcome: String, failed: Array) -> bool:
	if last_outcome == "":
		return failed.is_empty()
	return not FAILURE_EVENTS.has(last_outcome)


## What the two of you have actually been through, read through EventStore's
## entity index (`events_for_entity`, which indexes every event by each of its
## actors AND witnesses).
##
## An event counts when the PLAYER is one of its actors and the villager is an
## actor or a witness. Both halves matter:
##
##   * The player must have ACTED. Standing in the same crowd is not history
##     with someone -- without this, the whole village knows you the moment
##     you happen to be present for one settlement event.
##   * The villager may merely have WATCHED. MemoryRecord grades witnessing
##     as being there (WITNESSED, not testimony), so someone who saw you do
##     something is not a stranger to you.
##
## Only outcomes the villager was an ACTOR in are eligible to be
## `last_outcome`: a contract names its parties and has no witnesses, so an
## outcome they merely watched was not theirs, and cannot settle anything
## between you.
static func _shared_history(
	store, player_parties: Array[String], npc_parties: Array[String]
) -> Dictionary:
	var result := {"count": 0, "last_outcome": "", "last_outcome_event_id": ""}
	if store == null or not store.has_method("events_for_entity"):
		return result
	if player_parties.is_empty() or npc_parties.is_empty():
		return result

	var seen := {}
	var latest_ordinal := -1
	for party in player_parties:
		for event in store.events_for_entity(party):
			var event_id := str(event.id)
			if seen.has(event_id):
				continue
			if not _names_any(event.actors, player_parties):
				continue
			var npc_acted := _names_any(event.actors, npc_parties)
			if not npc_acted and not _names_any(event.witnesses, npc_parties):
				continue
			seen[event_id] = true
			result["count"] = int(result["count"]) + 1

			if not npc_acted or not OUTCOME_EVENTS.has(str(event.type)):
				continue
			var ordinal := _append_ordinal(event_id)
			if ordinal >= latest_ordinal:
				latest_ordinal = ordinal
				result["last_outcome"] = str(event.type)
				result["last_outcome_event_id"] = event_id
	return result


## "evt_<ordinal>_<type>" -> ordinal: the position EventStore.append gave this
## event, parsed the same way EventStore._ordinal_of parses it to resume the
## sequence after a load.
##
## -1 for an id that is not one, which sorts it before every real event
## instead of aborting the read -- a malformed id costs a villager one
## correctly ordered outcome, not the whole conversation.
static func _append_ordinal(event_id: String) -> int:
	var parts := event_id.split("_", true, 2)
	if parts.size() < 2 or not parts[1].is_valid_int():
		return -1
	return int(parts[1])


## The contracts the two of you are BOTH parties to, split by what they are
## now. Party-only, deliberately: a contract has no witnesses, and someone who
## watched you shake hands with their neighbour is owed nothing by you.
static func _shared_contracts(
	store, player_parties: Array[String], npc_parties: Array[String]
) -> Dictionary:
	var open_ids: Array[String] = []
	var fulfilled_ids: Array[String] = []
	var failed_ids: Array[String] = []
	var result := {
		"open": open_ids, "fulfilled": fulfilled_ids, "failed": failed_ids, "count": 0,
	}
	if store == null or not store.has_method("contracts_for"):
		return result
	if player_parties.is_empty() or npc_parties.is_empty():
		return result

	var seen := {}
	for party in player_parties:
		for contract in store.contracts_for(party):
			var contract_id := str(contract.id)
			if seen.has(contract_id):
				continue
			if not _names_any(contract.parties, npc_parties):
				continue
			seen[contract_id] = true
			result["count"] = int(result["count"]) + 1

			var status := str(contract.status)
			if OPEN_STATUSES.has(status):
				open_ids.append(contract_id)
			elif status == Contract.FULFILLED:
				fulfilled_ids.append(contract_id)
			elif FAILED_STATUSES.has(status):
				failed_ids.append(contract_id)
	return result


## How strongly this villager holds anything at all about the player, as
## dialogue.md pillar 4's own `confidence x (1 - distortion)` -- reused from
## DialogueTopic.belief_strength rather than restated, so the two cannot
## disagree about what a belief is worth.
##
## Zero is the honest floor, and it is a MEASURED boundary rather than a
## chosen one: Rumor.DISTORTION_PER_HOP (0.35) clamps distortion to 1.0 on the
## third retelling, so an account that far from the event carries nothing, and
## nothing is not having heard of you.
static func _hearsay_strength(memories, player_parties: Array[String]) -> float:
	var strongest := 0.0
	if typeof(memories) != TYPE_ARRAY or player_parties.is_empty():
		return strongest
	for memory in memories:
		if typeof(memory) != TYPE_DICTIONARY:
			continue
		if not _names_any(memory.get("actors", []), player_parties):
			continue
		strongest = maxf(strongest, DialogueTopic.belief_strength(memory))
	return strongest


static func _names_any(ids, wanted: Array[String]) -> bool:
	if typeof(ids) != TYPE_ARRAY:
		return false
	for id in ids:
		if wanted.has(str(id)):
			return true
	return false
