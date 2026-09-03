extends RefCounted

## A villager's ask, promised, kept or broken (docs/concept/quests.md,
## "Rewards are derived, and re-derived" and "Tracking is the world, not a
## log"; docs/concept/dialogue.md, "Emergent quests, no LLM").
##
## ## What this module is, precisely
##
## QuestOffer projects a real shortage into an ask. This is the only place
## anything about that ask is WRITTEN DOWN -- and the only thing written down
## is the acceptance, which is a `Contract`, which already existed. There is
## no quest log, no quest registry, no quest id allocator and no quest
## status enum; the contract's own documented lifecycle
## (proposed -> accepted -> active -> fulfilled, or defaulted) is the whole
## state machine.
##
## ## Why the offer id is the storage
##
## `Contract.obligations` is `Array[String]` and `Contract.consideration` is
## a `String` -- free-form by that module's own design note, and nothing in
## the codebase interprets either. Rather than bolt a structured payload onto
## Contract, this module puts the DERIVED offer id
## ("<kind>:<subject>:<count>", see QuestOffer.id_of) in the first
## obligation, which is exactly the player's own obligation, and reads it
## back with QuestOffer.parse_id. So an errand round-trips through save and
## load with nothing stored twice and no schema to migrate -- which is what
## deriving the id bought, and it is pinned by
## test_an_errand_survives_being_saved_and_restored_as_a_contract.
##
## Contract's design note says structured amounts were left out because "this
## project has no real currency/resource-flow simulation wired to NPCs yet."
## That premise has since changed in one narrow place -- NpcEconomy gives
## every villager a real Wallet and QuestReward computes a real number
## against it -- but the reward is still deliberately NOT stored on the
## contract: quests.md requires it be re-derived at fulfilment from live
## state, so storing it would be storing something that is allowed to be
## wrong.
##
## ## Deadlines are lazy on purpose
##
## quests.md: "Deadline is checked lazily at conversation open, not by a
## background sweep. The only observer that matters is the conversation
## itself, so a sweep would be pure cost." `lapse_overdue` is that check, and
## it is idempotent: opening the same conversation twice must not record two
## broken promises.
##
## ## What cannot be promised
##
## An errand with no completion check must never become a promise. Going to
## look at a remembered raid is a real projection and worth SAYING -- the
## raid site holds real dropped goods -- but nothing in this simulation can
## yet observe the player standing there, so `is_promisable` refuses it and
## it stays directions rather than a debt. A promise the game cannot let you
## keep is worse than no promise.
##
## Pure static module over plain values and the two stores handed to it -- no
## Node, no scene, no engine.

const Contract = preload("res://src/emergence/contract.gd")
const QuestOffer = preload("res://src/dialogue/quest_offer.gd")
const QuestReward = preload("res://src/dialogue/quest_reward.gd")

## One of Contract.TYPES (docs/emergence/03's own documented initial set),
## not a type invented for quests: a villager short of a recipe input who
## agrees to pay you for bringing it is exactly a supply agreement.
const CONTRACT_TYPE := "supply"

## The player's moves on an ask. Named here rather than in Conversation
## because they only exist when there is an ask on the table.
const CHOICE_ACCEPT := "ask_accept"
const CHOICE_DELIVER := "ask_deliver"

## The errand kinds that have a real completion check today. See the module
## header: QuestOffer.KIND_INVESTIGATE is deliberately absent.
const PROMISABLE_KINDS: Array[String] = [
	QuestOffer.KIND_FETCH, QuestOffer.KIND_FEED, QuestOffer.KIND_FIREWOOD,
]

## The errand a contract holds, in QuestOffer.parse_id's shape, or an empty
## errand for a contract that is not an ask at all. `{}` is not returned:
## every caller reads `kind`, and an absent kind is "" by the same fail-open
## convention the rest of this layer uses.
const NO_ERRAND := {"kind": "", "subject": "", "count": 0}


## The errand an offer names, without going through a contract -- the same
## shape `errand_of` returns, so the delivery and label functions take one
## kind of argument whether the ask is on the table or already promised.
static func errand_of_offer(offer: Dictionary) -> Dictionary:
	return QuestOffer.parse_id(str(offer.get("offer_id", "")))


## The errand a contract was accepted for, read back out of the obligation it
## was written into.
static func errand_of(contract) -> Dictionary:
	if contract == null:
		return NO_ERRAND.duplicate()
	if contract.type != CONTRACT_TYPE or contract.obligations.is_empty():
		return NO_ERRAND.duplicate()
	return QuestOffer.parse_id(contract.obligations[0])


## Whether this ask has a completion path at all (see the module header).
static func is_promisable(offer: Dictionary) -> bool:
	return PROMISABLE_KINDS.has(str(offer.get("kind", "")))


## The player agrees. Proposes, accepts and activates in one step -- a
## conversation IS the agreement, and there is no third party to
## counter-sign. Returns the live Contract, or null for an ask that cannot be
## promised, which is refused outright rather than half-recorded.
static func accept(contract_store, offer: Dictionary, player_id: String, now: float):
	if contract_store == null or not is_promisable(offer):
		return null
	var deadline := now + float(offer.get("deadline_seconds", 0.0))
	var contract = _propose(
		contract_store,
		[player_id, str(offer.get("npc_id", ""))],
		obligations_for(offer, player_id),
		consideration_for(offer),
		deadline,
		now
	)
	if contract == null:
		return null
	_drive(contract_store, "accept_contract", "accept", contract.id, now)
	_drive(contract_store, "activate_contract", "activate", contract.id, now)
	return contract


## The first obligation is the player's, and IS the derived offer id -- see
## the module header for why that is the whole persistence story. The second
## is the villager's, in the free-form prose Contract asks for, quoting what
## the errand was worth WHEN AGREED. That figure is prose and is never read
## back as a promise: what is actually paid is re-derived at delivery.
static func obligations_for(offer: Dictionary, player_id: String) -> Array:
	var reward: Dictionary = offer.get("reward", {})
	return [
		str(offer.get("offer_id", "")),
		"%s pays %d gold on delivery to %s" % [
			str(offer.get("npc_id", "")), int(reward.get("full", 0)), player_id
		],
	]


static func consideration_for(offer: Dictionary) -> String:
	var reward: Dictionary = offer.get("reward", {})
	return "%s for %d gold" % [_subject_phrase(errand_of_offer(offer)), int(reward.get("full", 0))]


## Every promise still standing between this villager and this player.
##
## Overdue promises are excluded WITHOUT being defaulted here: reading what
## is owed must not change the world (the floating world prompt calls this
## every frame it is visible). `lapse_overdue` is the one place a lapse is
## recorded, and a conversation opening is the one place it is called.
static func open_asks(contract_store, npc_id: String, player_id: String, now: float) -> Array:
	var out: Array = []
	if contract_store == null:
		return out
	for contract in _contracts_for(contract_store, npc_id):
		if contract.status != Contract.ACTIVE:
			continue
		if not contract.parties.has(player_id):
			continue
		if errand_of(contract)["kind"] == "":
			continue
		if has_lapsed(contract, now):
			continue
		out.append(contract)
	return out


## Whether this exact ask is already promised. The offer id is derived from
## the shortage itself, so this needs no registry -- and it is what stops a
## villager offering you the same three rock every time you speak.
static func already_promised(
	contract_store, offer: Dictionary, player_id: String, now: float
) -> bool:
	var offer_id := str(offer.get("offer_id", ""))
	for contract in open_asks(contract_store, str(offer.get("npc_id", "")), player_id, now):
		if contract.obligations[0] == offer_id:
			return true
	return false


## A deadline of -1.0 means no deadline (Contract's own convention), and such
## a promise never lapses however long it is left.
static func has_lapsed(contract, now: float) -> bool:
	if contract == null or contract.deadline < 0.0:
		return false
	return now > contract.deadline


## Records every overdue promise between this villager and this player as a
## real default, and returns the contracts that just lapsed -- so the caller
## can witness each as an event without re-deriving which ones were new.
##
## Idempotent by construction: `default_on` only transitions from ACTIVE, so
## a contract that lapsed on the last conversation open is skipped on this
## one and the returned Array is empty.
static func lapse_overdue(contract_store, npc_id: String, player_id: String, now: float) -> Array:
	var lapsed: Array = []
	if contract_store == null:
		return lapsed
	for contract in _contracts_for(contract_store, npc_id):
		if contract.status != Contract.ACTIVE or not contract.parties.has(player_id):
			continue
		if errand_of(contract)["kind"] == "" or not has_lapsed(contract, now):
			continue
		if _drive(contract_store, "default_on_contract", "default_on", contract.id, now):
			lapsed.append(contract)
	return lapsed


## What handing this errand over would actually take out of the player's
## pack, and whether it settles the errand at all.
##
## `carrying` is item_id -> count; `kinds` is item_id -> ItemCatalog kind,
## needed only by errands that name a KIND rather than an id (a hungry
## villager wants food, and nothing in this simulation decides WHICH food).
## Returns {"complete": bool, "items": {item_id: count}} and never takes more
## than was asked for.
static func delivery_for(errand: Dictionary, carrying: Dictionary, kinds: Dictionary) -> Dictionary:
	var kind := str(errand.get("kind", ""))
	var count := int(errand.get("count", 0))
	var subject := str(errand.get("subject", ""))
	if not PROMISABLE_KINDS.has(kind) or count <= 0:
		return {"complete": false, "items": {}}

	if kind == QuestOffer.KIND_FEED:
		return _delivery_of_kind(subject, count, carrying, kinds)
	var have := int(carrying.get(subject, 0))
	if have < count:
		return {"complete": false, "items": {}}
	return {"complete": true, "items": {subject: count}}


## An errand that names a category takes from the carried ids of that
## category, in sorted order so two identical packs always hand over the same
## thing.
static func _delivery_of_kind(
	wanted_kind: String, count: int, carrying: Dictionary, kinds: Dictionary
) -> Dictionary:
	var items: Dictionary = {}
	var remaining := count
	var item_ids: Array = carrying.keys()
	item_ids.sort()
	for item_id in item_ids:
		if remaining <= 0:
			break
		if str(kinds.get(item_id, "")) != wanted_kind:
			continue
		var take := mini(int(carrying[item_id]), remaining)
		if take <= 0:
			continue
		items[item_id] = take
		remaining -= take
	if remaining > 0:
		return {"complete": false, "items": {}}
	return {"complete": true, "items": items}


## The player hands the goods over. Fulfils the contract and returns what
## the villager actually pays.
##
## The reward is computed HERE, from `payer_gold` read live off the
## villager's own Wallet at this moment -- never from the offer, and never
## from the contract, which deliberately stores no amount. quests.md: "A
## villager who went broke while you were away pays less, and says so."
##
## Returns QuestReward.gold_for's shape plus `paid`, which is 0 (and nothing
## changes) for a promise that is not settleable: already fulfilled, already
## defaulted, or overdue -- an overdue promise is a broken one, and turning
## up late with the goods does not un-break it.
static func settle(contract_store, contract, payer_gold: int, now: float) -> Dictionary:
	var errand := errand_of(contract)
	var reward := QuestReward.gold_for(int(errand.get("count", 0)), payer_gold)
	reward["paid"] = 0
	if contract_store == null or contract == null:
		return reward
	if contract.status != Contract.ACTIVE or has_lapsed(contract, now):
		return reward
	if not _drive(contract_store, "fulfill_contract", "fulfill", contract.id, now):
		return reward
	reward["paid"] = reward["amount"]
	return reward


# -- driving the store, or the coordinator that owns it ----------------------
#
# Every function above takes `contract_store`, and it may be either a bare
# ContractStore or the coordinator that owns one (EarthChunkManager).
#
# The distinction is load-bearing rather than tidy. EarthChunkManager keeps
# the contract store and the EVENT store in sync -- each lifecycle transition
# it drives also appends the matching event and lets nearby villagers witness
# it -- and NpcRecognition reads exactly those events to decide how a villager
# greets you next time. An errand that transitioned the store directly would
# settle perfectly and change nothing about how anyone treats you afterwards:
# the promise you kept would be invisible to everyone including the person you
# kept it for.
#
# So the coordinator's method is preferred wherever it exists, and the raw
# store's is the fallback -- duck-typed on method names, the same shape
# NpcProduction.yield_per_second duck-types `world`, which is what keeps every
# pure test above engine-free.


## Every contract naming `entity_id`, through whichever of the two shapes was
## handed in.
##
## READING is the store's job even when a coordinator was handed in, because
## EarthChunkManager exposes no per-entity contract query of its own -- it
## hands out the store for that and keeps only the WRITES, which are the ones
## that must also record an event. An earlier version called
## `contracts_for` on whatever it was given; the test stub answered it and the
## real coordinator did not, so every test passed and nothing worked in the
## game: a villager kept offering an errand you had already promised, because
## `already_promised` could never see the promise.
static func _contracts_for(contract_store, entity_id: String) -> Array:
	var store = contract_store
	if store != null and store.has_method("contract_store"):
		store = store.contract_store()
	if store == null or not store.has_method("contracts_for"):
		return []
	var out: Array = []
	for contract in store.contracts_for(entity_id):
		out.append(contract)
	return out


static func _propose(
	contract_store, parties: Array, obligations: Array, consideration: String,
	deadline: float, now: float
):
	if contract_store.has_method("propose_contract"):
		return contract_store.propose_contract(
			CONTRACT_TYPE, parties, obligations, consideration, deadline
		)
	if contract_store.has_method("propose"):
		return contract_store.propose(
			CONTRACT_TYPE, parties, obligations, consideration, deadline, now
		)
	return null


## `driven_name` is the coordinator's (which also records the event);
## `raw_name` the store's own. False when neither exists, which is the same
## answer as a transition the store refused.
static func _drive(
	contract_store, driven_name: String, raw_name: String, contract_id: String, now: float
) -> bool:
	if contract_store.has_method(driven_name):
		return bool(contract_store.call(driven_name, contract_id))
	if contract_store.has_method(raw_name):
		return bool(contract_store.call(raw_name, contract_id, now))
	return false


# -- the words ---------------------------------------------------------------


## "I'll bring you the 3 rock." -- built from the offer's own slots, so no two
## villagers offer the player the same sentence about different things.
static func accept_label(offer: Dictionary) -> String:
	return "I'll bring you %s." % _subject_phrase(errand_of_offer(offer))


static func deliver_label(errand: Dictionary) -> String:
	return "Here's %s." % _subject_phrase(errand)


## quests.md: "Tracking is the world, not a log. The floating interaction
## prompt becomes `Talk (G) - owed 3 rock`." Empty for nothing owed, so the
## prompt is unchanged for the overwhelming majority of villagers.
static func owed_summary(contracts: Array) -> String:
	var phrases: Array = []
	for contract in contracts:
		var phrase := _subject_phrase(errand_of(contract))
		if phrase != "":
			phrases.append(phrase)
	if phrases.is_empty():
		return ""
	return "owed %s" % ", ".join(phrases)


## The floating prompt above a villager's head. quests.md: "Tracking is the
## world, not a log. The floating interaction prompt becomes `Talk (G) - owed
## 3 rock`, fed from the throttle that already exists." There is no quest log
## and no marker: what you owe is visible exactly where the person you owe it
## to is standing, and nowhere else.
static func talk_prompt(key_label: String, owed: String) -> String:
	if owed.is_empty():
		return "Talk (%s)" % key_label
	return "Talk (%s) \u00b7 %s" % [key_label, owed]


## "3 rock", or "food" for an errand that names a category. The count is
## omitted when there is only one of a category, because "1 food" is not
## something anyone says.
static func _subject_phrase(errand: Dictionary) -> String:
	var subject := str(errand.get("subject", ""))
	if subject == "" or errand.get("kind", "") == "":
		return ""
	var count := int(errand.get("count", 0))
	if count <= 1:
		return subject
	return "%d %s" % [count, subject]
