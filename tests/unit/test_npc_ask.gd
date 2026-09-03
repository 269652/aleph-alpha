extends GutTest

## Turning a villager's real shortage into a promise, and back again.
##
## docs/concept/quests.md is precise about what the existing substrate does
## and does not give for free: "Nothing is persisted but the ACCEPTANCE, and
## that is a `Contract`, which already exists." What it does NOT give is any
## interpretation of what a contract holds -- `obligations` is
## `Array[String]` and `consideration` is a `String`, free-form by
## Contract's own design note. So this module is the interpretation, and the
## test that matters most is the round trip: an errand accepted today has to
## be readable back out of a saved contract tomorrow with nothing else
## written down.

const NpcAsk = preload("res://src/dialogue/npc_ask.gd")
const QuestOffer = preload("res://src/dialogue/quest_offer.gd")
const QuestReward = preload("res://src/dialogue/quest_reward.gd")
const Contract = preload("res://src/emergence/contract.gd")
const ContractStore = preload("res://src/emergence/contract_store.gd")

const PLAYER := "player:local"


func _offer(kind := QuestOffer.KIND_FETCH, item := "rock", count := 3, gold := 200) -> Dictionary:
	return {
		"offer_id": QuestOffer.id_of(kind, item, count),
		"kind": kind,
		"npc_id": "npc:41",
		"household_id": "household:41",
		"settlement_id": "settlement:7",
		"item_id": item,
		"item_kind": "",
		"count": count,
		"target_id": "household:41",
		"reward": QuestReward.gold_for(count, gold),
		"deadline_seconds": QuestOffer.DEADLINE_SECONDS,
		"salience": 0.5,
	}


func _feed_offer() -> Dictionary:
	var offer := _offer(QuestOffer.KIND_FEED, "", 1)
	offer["item_kind"] = QuestOffer.FOOD_KIND
	offer["offer_id"] = QuestOffer.id_of(QuestOffer.KIND_FEED, QuestOffer.FOOD_KIND, 1)
	return offer


# -- accepting ---------------------------------------------------------------


## The type is one Contract already documents (docs/emergence/03), not a new
## one invented for quests.
func test_accepting_an_ask_proposes_a_real_supply_contract():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	assert_not_null(contract)
	assert_eq(contract.type, NpcAsk.CONTRACT_TYPE)
	assert_true(Contract.TYPES.has(contract.type))


## Both sides are named, so the store's own party index finds the promise
## from either end -- which is how a conversation knows you already owe this
## villager something.
func test_both_parties_are_bound():
	var store = ContractStore.new()
	NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	assert_eq(store.contracts_for(PLAYER).size(), 1)
	assert_eq(store.contracts_for("npc:41").size(), 1)


## A promise you made is in force immediately -- there is no third party to
## counter-sign, and a conversation is where the agreement happened.
func test_an_accepted_ask_is_active_at_once():
	var store = ContractStore.new()
	assert_eq(NpcAsk.accept(store, _offer(), PLAYER, 100.0).status, Contract.ACTIVE)


## quests.md: the deadline is real and absolute, set at acceptance, because
## acceptance is the only thing that persists.
func test_the_deadline_is_set_from_when_it_was_accepted():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	assert_almost_eq(contract.deadline, 100.0 + QuestOffer.DEADLINE_SECONDS, 0.001)


# -- the round trip ----------------------------------------------------------


## The whole persistence argument in one test: the errand goes in as an
## offer and comes back out of a saved-and-restored contract unchanged, with
## no schema, no registry and no second copy of the ask.
func test_an_errand_survives_being_saved_and_restored_as_a_contract():
	var store = ContractStore.new()
	NpcAsk.accept(store, _offer(QuestOffer.KIND_FETCH, "rock", 3), PLAYER, 100.0)
	var restored = ContractStore.from_dicts(store.to_dicts())

	var errand := NpcAsk.errand_of(restored.contracts_for(PLAYER)[0])
	assert_eq(errand["kind"], QuestOffer.KIND_FETCH)
	assert_eq(errand["subject"], "rock")
	assert_eq(errand["count"], 3)


func test_a_contract_that_is_not_an_ask_reads_back_as_no_errand():
	var store = ContractStore.new()
	var contract = store.propose("trade", [PLAYER], ["something"], "prose", -1.0, 0.0)
	assert_eq(NpcAsk.errand_of(contract)["kind"], "")


# -- what is owed ------------------------------------------------------------


func test_an_open_promise_is_found_from_the_villagers_side():
	var store = ContractStore.new()
	NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	assert_eq(NpcAsk.open_asks(store, "npc:41", PLAYER, 100.0).size(), 1)


func test_a_promise_to_someone_else_is_not_owed_to_this_villager():
	var store = ContractStore.new()
	NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	assert_eq(NpcAsk.open_asks(store, "npc:99", PLAYER, 100.0).size(), 0)


func test_a_settled_promise_is_no_longer_open():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	store.fulfill(contract.id, 200.0)
	assert_eq(NpcAsk.open_asks(store, "npc:41", PLAYER, 200.0).size(), 0)


## The same ask must not become two promises. The offer id is derived from
## the shortage, so the check needs no registry.
func test_the_same_ask_is_not_promised_twice():
	var store = ContractStore.new()
	NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	assert_true(NpcAsk.already_promised(store, _offer(), PLAYER, 100.0))
	assert_false(NpcAsk.already_promised(store, _offer(
		QuestOffer.KIND_FETCH, "wood", 1
	), PLAYER, 100.0))


# -- lapsing -----------------------------------------------------------------


## quests.md: "Deadline is checked LAZILY at conversation open, not by a
## background sweep. The only observer that matters is the conversation
## itself, so a sweep would be pure cost."
func test_a_promise_kept_past_its_deadline_has_lapsed():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	assert_false(NpcAsk.has_lapsed(contract, 100.0 + QuestOffer.DEADLINE_SECONDS - 1.0))
	assert_true(NpcAsk.has_lapsed(contract, 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0))


func test_lapsing_defaults_the_contract():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	var lapsed := NpcAsk.lapse_overdue(store, "npc:41", PLAYER, 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0)
	assert_eq(lapsed.size(), 1)
	assert_eq(contract.status, Contract.DEFAULTED)


func test_a_lapsed_promise_is_not_open_any_more():
	var store = ContractStore.new()
	NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	var late := 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0
	NpcAsk.lapse_overdue(store, "npc:41", PLAYER, late)
	assert_eq(NpcAsk.open_asks(store, "npc:41", PLAYER, late).size(), 0)


## Nothing lapses on time, and lapsing is idempotent -- opening the same
## conversation twice must not record two broken promises.
func test_lapsing_twice_records_one_broken_promise():
	var store = ContractStore.new()
	NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	var late := 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0
	assert_eq(NpcAsk.lapse_overdue(store, "npc:41", PLAYER, late).size(), 1)
	assert_eq(NpcAsk.lapse_overdue(store, "npc:41", PLAYER, late).size(), 0)


# -- delivering --------------------------------------------------------------


func test_carrying_what_was_asked_for_completes_the_errand():
	var errand := NpcAsk.errand_of_offer(_offer(QuestOffer.KIND_FETCH, "rock", 3))
	var delivery := NpcAsk.delivery_for(errand, {"rock": 5}, {})
	assert_true(delivery["complete"])
	assert_eq(delivery["items"], {"rock": 3})


func test_carrying_some_of_it_is_not_a_delivery():
	var errand := NpcAsk.errand_of_offer(_offer(QuestOffer.KIND_FETCH, "rock", 3))
	var delivery := NpcAsk.delivery_for(errand, {"rock": 2}, {})
	assert_false(delivery["complete"])


## A delivery takes exactly what was asked for and never the whole stack.
func test_a_delivery_takes_only_what_was_asked_for():
	var errand := NpcAsk.errand_of_offer(_offer(QuestOffer.KIND_FETCH, "rock", 3))
	assert_eq(NpcAsk.delivery_for(errand, {"rock": 40}, {})["items"], {"rock": 3})


## A food errand names a KIND, so anything of that kind settles it -- which
## is why the caller hands in what each carried id actually IS.
func test_a_food_errand_is_settled_by_anything_of_that_kind():
	var errand := NpcAsk.errand_of_offer(_feed_offer())
	var delivery := NpcAsk.delivery_for(
		errand, {"berry": 4, "iron_sword": 1}, {"berry": "food", "iron_sword": "weapon"}
	)
	assert_true(delivery["complete"])
	assert_eq(delivery["items"], {"berry": 1})


func test_a_food_errand_is_not_settled_by_a_sword():
	var errand := NpcAsk.errand_of_offer(_feed_offer())
	var delivery := NpcAsk.delivery_for(errand, {"iron_sword": 1}, {"iron_sword": "weapon"})
	assert_false(delivery["complete"])
	assert_eq(delivery["items"], {})


# -- what a promise can be made of ------------------------------------------


## An errand with no completion check must never become a promise. Going to
## look at a remembered raid is real, and is offered as DIRECTIONS -- the
## raid site holds real dropped goods -- but nothing in this simulation can
## yet observe the player standing there, so accepting it would be a promise
## with no way to keep it.
func test_only_errands_that_can_actually_be_finished_can_be_promised():
	assert_true(NpcAsk.is_promisable(_offer(QuestOffer.KIND_FETCH, "rock", 3)))
	assert_true(NpcAsk.is_promisable(_feed_offer()))
	assert_true(NpcAsk.is_promisable(_offer(QuestOffer.KIND_FIREWOOD, "wood", 4)))
	assert_false(NpcAsk.is_promisable(_offer(QuestOffer.KIND_INVESTIGATE, "settlement:9", 0)))


func test_an_unpromisable_ask_is_refused_rather_than_half_recorded():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(
		store, _offer(QuestOffer.KIND_INVESTIGATE, "settlement:9", 0), PLAYER, 100.0
	)
	assert_null(contract)
	assert_eq(store.contracts_for(PLAYER).size(), 0)


# -- the words ---------------------------------------------------------------


## The labels name the actual quantity, from the offer's own slots -- never a
## generic "Accept quest".
func test_the_choice_names_what_is_actually_being_asked_for():
	assert_string_contains(NpcAsk.accept_label(_offer(QuestOffer.KIND_FETCH, "rock", 3)), "3")
	assert_string_contains(NpcAsk.accept_label(_offer(QuestOffer.KIND_FETCH, "rock", 3)), "rock")


func test_the_delivery_choice_names_what_is_being_handed_over():
	var errand := NpcAsk.errand_of_offer(_offer(QuestOffer.KIND_FETCH, "rock", 3))
	assert_string_contains(NpcAsk.deliver_label(errand), "rock")


## quests.md: "Tracking is the world, not a log. The floating interaction
## prompt becomes `Talk (G) - owed 3 rock`."
func test_what_is_owed_reads_back_as_a_short_phrase_for_the_world_prompt():
	var store = ContractStore.new()
	NpcAsk.accept(store, _offer(QuestOffer.KIND_FETCH, "rock", 3), PLAYER, 100.0)
	var owed := NpcAsk.owed_summary(NpcAsk.open_asks(store, "npc:41", PLAYER, 100.0))
	assert_string_contains(owed, "3")
	assert_string_contains(owed, "rock")


func test_owing_nothing_reads_back_as_nothing():
	assert_eq(NpcAsk.owed_summary([]), "")


# -- settling ----------------------------------------------------------------


func test_settling_fulfils_the_contract():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	NpcAsk.settle(store, contract, 200, 200.0)
	assert_eq(contract.status, Contract.FULFILLED)


## The claim quests.md rests the whole derived-reward design on: "A villager
## who went broke while you were away pays less, and says so. That is the
## honest behaviour and it costs nothing to implement, because the reward was
## never stored."
func test_a_villager_who_went_broke_pays_what_they_have_now():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(QuestOffer.KIND_FETCH, "rock", 3, 200), PLAYER, 100.0)
	var settled := NpcAsk.settle(store, contract, 2, 200.0)
	assert_eq(settled["paid"], 2)
	assert_true(settled["is_short"])
	assert_eq(settled["full"], QuestReward.full_gold_for(3))


func test_a_villager_who_still_has_it_pays_in_full():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	var settled := NpcAsk.settle(store, contract, 500, 200.0)
	assert_eq(settled["paid"], QuestReward.full_gold_for(3))
	assert_false(settled["is_short"])


## Nothing is paid twice: a contract that is no longer active cannot be
## settled again, however many times a caller tries.
func test_a_settled_promise_cannot_be_settled_again():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	NpcAsk.settle(store, contract, 500, 200.0)
	assert_eq(NpcAsk.settle(store, contract, 500, 201.0)["paid"], 0)


## An overdue promise is not settled by turning up with the goods -- it has
## already lapsed, and lapsing is what the gossip network witnesses.
func test_an_overdue_promise_cannot_be_settled():
	var store = ContractStore.new()
	var contract = NpcAsk.accept(store, _offer(), PLAYER, 100.0)
	var late := 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0
	var settled := NpcAsk.settle(store, contract, 500, late)
	assert_eq(settled["paid"], 0)
	assert_ne(contract.status, Contract.FULFILLED)


# -- the coordinator drives the store, when there is one --------------------


## EarthChunkManager keeps the contract store and the event store in sync:
## every lifecycle transition it drives also appends the matching event, and
## `NpcRecognition` reads those events to decide how a villager greets you.
## So an errand that transitioned the store DIRECTLY would settle correctly
## and change nothing about how anyone treats you afterwards.
##
## Duck-typed on the coordinator's own method names, the same shape
## NpcProduction.yield_per_second duck-types `world`: a bare ContractStore is
## still a perfectly good argument, which is what keeps every test above
## engine-free.
class RecordingCoordinator:
	extends RefCounted
	const Store = preload("res://src/emergence/contract_store.gd")
	var store = Store.new()
	var calls: Array = []

	func propose_contract(type, parties, obligations, consideration, deadline):
		calls.append("propose_contract")
		return store.propose(type, parties, obligations, consideration, deadline, 0.0)

	func accept_contract(contract_id: String) -> bool:
		calls.append("accept_contract")
		return store.accept(contract_id, 0.0)

	func activate_contract(contract_id: String) -> bool:
		calls.append("activate_contract")
		return store.activate(contract_id, 0.0)

	func fulfill_contract(contract_id: String) -> bool:
		calls.append("fulfill_contract")
		return store.fulfill(contract_id, 0.0)

	func default_on_contract(contract_id: String) -> bool:
		calls.append("default_on_contract")
		return store.default_on(contract_id, 0.0)

	## Exactly what EarthChunkManager exposes for READING contracts -- the
	## store itself, and no per-entity query of its own. An earlier version of
	## this stub answered `contracts_for` directly, which the real coordinator
	## does not: every test here passed while nothing worked in the game,
	## because the stub was more capable than the thing it stood for.
	func contract_store():
		return store


func test_accepting_goes_through_the_coordinator_when_there_is_one():
	var coordinator = RecordingCoordinator.new()
	var contract = NpcAsk.accept(coordinator, _offer(), PLAYER, 100.0)
	assert_eq(contract.status, Contract.ACTIVE)
	assert_eq(coordinator.calls, ["propose_contract", "accept_contract", "activate_contract"])


func test_settling_goes_through_the_coordinator_so_the_event_is_recorded():
	var coordinator = RecordingCoordinator.new()
	var contract = NpcAsk.accept(coordinator, _offer(), PLAYER, 100.0)
	coordinator.calls.clear()
	NpcAsk.settle(coordinator, contract, 500, 200.0)
	assert_eq(coordinator.calls, ["fulfill_contract"])
	assert_eq(contract.status, Contract.FULFILLED)


func test_lapsing_goes_through_the_coordinator_so_the_break_is_witnessed():
	var coordinator = RecordingCoordinator.new()
	NpcAsk.accept(coordinator, _offer(), PLAYER, 100.0)
	coordinator.calls.clear()
	var late := 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0
	assert_eq(NpcAsk.lapse_overdue(coordinator, "npc:41", PLAYER, late).size(), 1)
	assert_eq(coordinator.calls, ["default_on_contract"])


# -- what the world shows ----------------------------------------------------


## quests.md: "Tracking is the world, not a log. The floating interaction
## prompt becomes `Talk (G) - owed 3 rock`, fed from the throttle that
## already exists." No quest log, no marker over anyone's head.
func test_the_talk_prompt_carries_what_is_owed():
	var prompt := NpcAsk.talk_prompt("G", "owed 3 rock")
	assert_string_contains(prompt, "Talk (G)")
	assert_string_contains(prompt, "owed 3 rock")


## Owing nothing leaves the prompt exactly as it has always been -- which is
## the case for the overwhelming majority of villagers.
func test_owing_nothing_leaves_the_prompt_alone():
	assert_eq(NpcAsk.talk_prompt("G", ""), "Talk (G)")
