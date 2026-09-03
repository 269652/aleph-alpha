extends GutTest

## Does a REAL village, built the way the game builds one, ever produce an
## errand a player can actually be offered?
##
## This is an instrument, not a unit test. `QuestOffer` is pure and tested
## against hand-built frames; what those tests cannot see is whether the
## substrate below ever produces such a frame -- the exact failure mode
## `DialogueTopic`'s own header names ("a topic that is always empty is a
## SUBSTRATE bug this frame exists to surface"), applied to errands.
##
## The specific way this breaks silently: a household id is derived TWICE, by
## two modules that never speak. `EarthChunkManager` reads its shortfalls
## against `HouseholdStore`'s ids, and `DialogueContext` derives the villager's
## own household id by pure string math off the npc id. If those two shapes
## ever disagree, every query keeps returning correct shortfalls, every
## villager keeps having none, and nothing anywhere fails.

const ConversationSources = preload("res://src/dialogue/conversation_sources.gd")
const DialogueContext = preload("res://src/dialogue/dialogue_context.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const NpcAsk = preload("res://src/dialogue/npc_ask.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const QuestOffer = preload("res://src/dialogue/quest_offer.gd")
const Conversation = preload("res://src/dialogue/conversation.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const NpcRecognition = preload("res://src/dialogue/npc_recognition.gd")

const CHUNK := Vector2i(91, 91)
## Enough villagers to span several occupations, which is what makes "some
## villager has an errand" a claim about the village rather than about one
## lucky seed.
const SEEDS: Array[int] = [2, 5, 8, 11, 14, 17, 20, 23]

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var settlement_id: String


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var identities: Array = []
	for seed_value in SEEDS:
		identities.append(NpcIdentity.new(seed_value))
	manager.record_settlement_founded_if_new(CHUNK, identities)
	settlement_id = EntityRef.for_settlement(CHUNK)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _frame_for(seed_value: int) -> Dictionary:
	var identity := NpcIdentity.new(seed_value)
	var npc_id := "npc:%d" % seed_value
	# Deliberately NOT overridden: `gather` resolves the settlement itself, and
	# every settlement-derived source (the shortfall list included) is looked
	# up against whatever it resolves. If that resolution fails for a villager
	# the game really spawns, the whole errand layer is silently empty in play
	# while every unit test above it passes.
	return DialogueContext.build(
		npc_id, ConversationSources.gather(manager, identity, npc_id, null, null, null)
	)


## The precondition the rest of this file rests on: a fresh village really is
## short of things. An emergence Market only gains stock from its own output
## or an inbound haul, so on day one every mapped occupation's recipe is
## blocked.
func test_a_fresh_village_is_genuinely_short_of_things():
	assert_gt(
		manager.production_shortfall_quests_for_settlement(settlement_id).size(), 0,
		"no household in a fresh village is short of anything -- the shortfall query itself is dead"
	)


## `gather` has to find the settlement on its own -- from the event store, the
## way it does in the running game. A villager whose settlement it cannot name
## reads every settlement-derived source against "" and therefore has no
## shortfall, no village status and nothing to be asked for.
func test_gather_finds_the_settlement_a_villager_actually_lives_in():
	for seed_value in SEEDS:
		var identity := NpcIdentity.new(seed_value)
		var npc_id := "npc:%d" % seed_value
		var sources := ConversationSources.gather(manager, identity, npc_id, null, null, null)
		assert_eq(
			String(sources["settlement_id"]), settlement_id,
			"gather cannot say where %s lives" % npc_id
		)


## The join that has no owner: the shortfall the settlement reports has to
## reach the villager it belongs to.
func test_a_shortfall_reaches_the_villager_it_belongs_to():
	var reached := 0
	for seed_value in SEEDS:
		if not _frame_for(seed_value)["shortfall_missing"].is_empty():
			reached += 1
	assert_gt(
		reached, 0,
		"the village has shortfalls and not one villager knows about their own -- "
		+ "the two household ids have drifted apart"
	)


## And the whole point: it becomes something a player can be offered.
func test_some_villager_in_a_real_village_has_an_errand_to_offer():
	var offered := 0
	for seed_value in SEEDS:
		for offer in QuestOffer.offers_for(_frame_for(seed_value)):
			if NpcAsk.is_promisable(offer):
				offered += 1
	assert_gt(offered, 0, "nobody in a real village can ask the player for anything")


## The errand names a real item at a real count -- not an empty ask that
## would render as a sentence with a hole in it.
func test_the_errand_names_something_real():
	for seed_value in SEEDS:
		for offer in QuestOffer.offers_for(_frame_for(seed_value)):
			if offer["kind"] != QuestOffer.KIND_FETCH:
				continue
			assert_ne(String(offer["item_id"]), "")
			assert_gt(int(offer["count"]), 0)
			assert_string_contains(NpcAsk.accept_label(offer), String(offer["item_id"]))


# -- and the delivery has to end the shortage -------------------------------


## The falsifiable half of quests.md pillar 1, run against a real village:
## a quest projects a real shortage, so completing it must change that
## shortage. Found by playing -- the delivery fulfilled the contract, paid,
## took the item out of the pack, and the villager asked for exactly the same
## thing again, because nothing had put the goods into the settlement's stock.
func test_delivering_what_was_asked_for_ends_the_shortage():
	var short := manager.production_shortfall_quests_for_settlement(settlement_id)
	assert_gt(short.size(), 0, "precondition: the village is short of something")

	var missing: Array = short[0]["missing"]
	assert_gt(missing.size(), 0, "precondition: that shortfall names an item")
	var item_id := String(missing[0]["item_id"])
	var need := int(missing[0]["need"])

	manager.deliver_to_settlement(settlement_id, {item_id: need})

	for shortfall in manager.production_shortfall_quests_for_settlement(settlement_id):
		for entry in shortfall["missing"]:
			assert_ne(
				String(entry["item_id"]), item_id,
				"the goods were handed over and the village is still short of them"
			)


## The goods land in the SAME market the shortfall was computed against --
## not a second store that agrees with nothing.
func test_delivered_goods_land_in_the_settlements_own_market():
	manager.deliver_to_settlement(settlement_id, {"rock": 4})
	assert_eq(manager.market_for_settlement(settlement_id).stock_of("rock"), 4)


## Delivering nowhere, or nothing, changes nothing and raises nothing.
func test_delivering_nothing_anywhere_is_harmless():
	manager.deliver_to_settlement("", {"rock": 4})
	manager.deliver_to_settlement(settlement_id, {})
	assert_eq(manager.market_for_settlement(settlement_id).stock_of("rock"), 0)


# -- the whole exchange, against the real coordinator ------------------------


## Everything above tests the errand layer against a bare ContractStore. The
## game hands it the COORDINATOR instead, and that difference has already
## produced one bug that every test missed (see NpcAsk._contracts_for). So the
## full exchange is run here end to end against a real EarthChunkManager, a
## real Inventory and a real frame -- the same objects the running game uses.
func _talk_to(seed_value: int, inventory):
	var identity := NpcIdentity.new(seed_value)
	var npc_id := "npc:%d" % seed_value
	var sources := ConversationSources.gather(manager, identity, npc_id, inventory, null, null)
	var frame: Dictionary = DialogueContext.build(npc_id, sources)
	return Conversation.open(
		frame, null, Conversation.RECOGNITION_STRANGER,
		ConversationSources.asks_for(sources, frame, ItemCatalog.new())
	)


func _asking_seed() -> int:
	for seed_value in SEEDS:
		for offer in QuestOffer.offers_for(_frame_for(seed_value)):
			if NpcAsk.is_promisable(offer):
				return seed_value
	return -1


func _choice_ids(talk) -> Array:
	var out: Array = []
	for choice in talk.choices():
		out.append(choice["id"])
	return out


func test_the_whole_exchange_works_against_the_real_coordinator():
	var seed_value := _asking_seed()
	assert_gt(seed_value, -1, "precondition: someone in this village has an errand")

	var offer: Dictionary = {}
	for candidate in QuestOffer.offers_for(_frame_for(seed_value)):
		if NpcAsk.is_promisable(candidate):
			offer = candidate
			break

	var inventory = Inventory.new(20)
	inventory.add(ItemCatalog.new().make(String(offer["item_id"])), int(offer["count"]) + 2)

	# 1. offered
	var talk = _talk_to(seed_value, inventory)
	assert_true(_choice_ids(talk).has(NpcAsk.CHOICE_ACCEPT), "no errand was offered")

	# 2. promised -- and immediately deliverable, because the goods are on us
	talk.choose(NpcAsk.CHOICE_ACCEPT)
	assert_true(
		_choice_ids(talk).has(NpcAsk.CHOICE_DELIVER),
		"carrying what was just promised, and no way to hand it over"
	)

	# 3. handed over
	talk.choose(NpcAsk.CHOICE_DELIVER)
	var effect: Dictionary = talk.take_effect()
	assert_eq(int(effect["items"][String(offer["item_id"])]), int(offer["count"]))
	assert_eq(String(effect["settlement_id"]), settlement_id)

	# 4. and the promise is settled in the real store, with the real event
	# recorded -- which is what NpcRecognition reads next time.
	assert_eq(
		manager.event_store().events_of_type(NpcRecognition.OUTCOME_FULFILLED).size(), 1,
		"the promise was kept and nobody witnessed it"
	)


## And a second conversation, after the goods arrive, no longer asks for what
## the village now has.
func test_the_villager_stops_asking_once_the_village_has_it():
	var seed_value := _asking_seed()
	var offer: Dictionary = {}
	for candidate in QuestOffer.offers_for(_frame_for(seed_value)):
		if NpcAsk.is_promisable(candidate):
			offer = candidate
			break

	assert_true(
		_offer_ids_of(seed_value).has(String(offer["offer_id"])),
		"precondition: they are asking for it before it arrives"
	)

	manager.deliver_to_settlement(settlement_id, {String(offer["item_id"]): int(offer["count"])})

	assert_false(
		_offer_ids_of(seed_value).has(String(offer["offer_id"])),
		"the goods arrived and they are still asking for them"
	)


func _offer_ids_of(seed_value: int) -> Array:
	var ids: Array = []
	for offer in QuestOffer.offers_for(_frame_for(seed_value)):
		ids.append(String(offer["offer_id"]))
	return ids
