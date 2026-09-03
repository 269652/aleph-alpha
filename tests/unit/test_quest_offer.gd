extends GutTest

## A villager asking you for something they are actually short of.
##
## docs/concept/quests.md's first design pillar is a falsifiable claim, not a
## slogan: "delete the query and the village is still starving." So every
## test here builds a frame that describes a REAL condition and asserts an
## offer falls out of it -- and, just as load-bearing, that a frame with no
## such condition produces no offer at all. There is no default errand
## anywhere in this module, the same way DialogueTopic has no default line.
##
## The offer shape is fixed by quests.md ("Offered in conversation: the six
## grounded sources") and the derived-id rule is the pillar restated as an
## implementation constraint: an offer has no identity of its own, so it
## cannot outlive the condition it projects.

const QuestOffer = preload("res://src/dialogue/quest_offer.gd")
const QuestReward = preload("res://src/dialogue/quest_reward.gd")
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const Rumor = preload("res://src/emergence/rumor.gd")


func _frame(overrides: Dictionary = {}) -> Dictionary:
	var frame := {
		"npc_id": "npc:41",
		"npc_name": "Bren",
		"occupation": "blacksmith",
		"household_id": "household:41",
		"settlement_id": "settlement:7",
		"is_producer": true,
		"wallet_gold": 200,
		"hunger": 0.0,
		"is_hungry": false,
		"meal_available": true,
		"can_afford_meal": true,
		"snow_depth": 0.0,
		"world_age_seconds": 1000.0,
		"household_recipe_id": "stone_pickaxe",
		"shortfall_missing": [],
		"shortfall_items_player_has": [],
		"shortfall_covered_by_player": false,
		"memories": [],
	}
	for key in overrides:
		frame[key] = overrides[key]
	return frame


func _shortfall_frame(item_id := "rock", need := 3) -> Dictionary:
	return _frame({"shortfall_missing": [{"item_id": item_id, "need": need}]})


func _memory(event_type: String, confidence: float, distortion := 0.0) -> Dictionary:
	return {
		"event_id": "evt_%s" % event_type,
		"event_type": event_type,
		"bank": "npc",
		"holder": "npc:41",
		"source_type": MemoryRecord.FIRSTHAND,
		"confidence": confidence,
		"distortion": distortion,
		"recorded_at": 500.0,
		"age_seconds": 500.0,
		"actors": ["settlement:9"],
		"subject_id": "settlement:9",
		"place_settlement_id": "settlement:9",
		"tags": [],
		"importance": 0.0,
	}


func _kinds_in(offers: Array) -> Array:
	var out: Array = []
	for offer in offers:
		out.append(offer["kind"])
	return out


func _of_kind(offers: Array, kind: String) -> Dictionary:
	for offer in offers:
		if offer["kind"] == kind:
			return offer
	return {}


# -- nothing is invented -----------------------------------------------------


## The whole of pillar 2, applied to errands: a villager with nothing wrong
## asks for nothing. Not a shorter errand -- none.
func test_a_villager_in_no_trouble_asks_for_nothing():
	assert_eq(QuestOffer.offers_for(_frame()), [])


func test_an_empty_frame_asks_for_nothing():
	assert_eq(QuestOffer.offers_for({}), [])


# -- source 1: production shortfall, attributed to a face --------------------


func test_a_household_short_of_a_recipe_input_asks_for_exactly_that():
	var offers := QuestOffer.offers_for(_shortfall_frame("rock", 3))
	assert_eq(offers.size(), 1)
	var offer: Dictionary = offers[0]
	assert_eq(offer["kind"], QuestOffer.KIND_FETCH)
	assert_eq(offer["item_id"], "rock")
	assert_eq(offer["count"], 3)


## quests.md source 1: the household id IS the founder's id, so an anonymous
## `household:483920 needs 3 rock` is already this person's own ask. The
## offer has to carry the face, or the whole attribution argument is unused.
func test_the_ask_carries_the_villager_who_is_making_it():
	var offer: Dictionary = QuestOffer.offers_for(_shortfall_frame())[0]
	assert_eq(offer["npc_id"], "npc:41")
	assert_eq(offer["household_id"], "household:41")
	assert_eq(offer["settlement_id"], "settlement:7")


func test_two_missing_inputs_are_two_separate_asks():
	var frame := _frame({"shortfall_missing": [
		{"item_id": "rock", "need": 2}, {"item_id": "wood", "need": 1},
	]})
	assert_eq(QuestOffer.offers_for(frame).size(), 2)


func test_a_shortfall_of_zero_is_not_a_shortfall():
	assert_eq(QuestOffer.offers_for(_shortfall_frame("rock", 0)), [])


# -- the derived id ----------------------------------------------------------


## quests.md: "`offer_id` is DERIVED, never allocated -- `<kind>:<item>:
## <count>` -- so the same real shortage always yields the same id and offers
## dedupe across recomputation without a registry."
func test_the_offer_id_is_derived_from_the_shortage_itself():
	var first: Dictionary = QuestOffer.offers_for(_shortfall_frame("rock", 3))[0]
	var again: Dictionary = QuestOffer.offers_for(_shortfall_frame("rock", 3))[0]
	assert_eq(first["offer_id"], again["offer_id"])
	assert_eq(first["offer_id"], QuestOffer.id_of(QuestOffer.KIND_FETCH, "rock", 3))


func test_a_different_shortage_is_a_different_offer():
	var three: Dictionary = QuestOffer.offers_for(_shortfall_frame("rock", 3))[0]
	var two: Dictionary = QuestOffer.offers_for(_shortfall_frame("rock", 2))[0]
	var wood: Dictionary = QuestOffer.offers_for(_shortfall_frame("wood", 3))[0]
	assert_ne(three["offer_id"], two["offer_id"])
	assert_ne(three["offer_id"], wood["offer_id"])


## No registry, no counter, no allocation: the id is a pure function of what
## it names, which is what makes it safe to recompute the whole offer list on
## every conversation open.
func test_the_id_never_allocates():
	assert_eq(
		QuestOffer.id_of(QuestOffer.KIND_FETCH, "rock", 3),
		QuestOffer.id_of(QuestOffer.KIND_FETCH, "rock", 3)
	)


# -- source 2: village hunger ------------------------------------------------


func test_a_hungry_villager_whose_market_has_no_meal_asks_for_food():
	var frame := _frame({"is_hungry": true, "hunger": 0.8, "meal_available": false})
	var offer := _of_kind(QuestOffer.offers_for(frame), QuestOffer.KIND_FEED)
	assert_false(offer.is_empty())
	assert_eq(offer["item_kind"], QuestOffer.FOOD_KIND)
	assert_eq(offer["count"], 1)


## The offer is a projection of a REAL failure to eat. A villager who can
## simply go and buy a meal has no errand for you, however hungry they are.
func test_a_hungry_villager_who_can_buy_a_meal_asks_for_nothing():
	var frame := _frame({"is_hungry": true, "hunger": 0.8, "meal_available": true})
	assert_false(_kinds_in(QuestOffer.offers_for(frame)).has(QuestOffer.KIND_FEED))


func test_a_fed_villager_at_an_empty_market_asks_for_nothing():
	var frame := _frame({"is_hungry": false, "meal_available": false})
	assert_false(_kinds_in(QuestOffer.offers_for(frame)).has(QuestOffer.KIND_FEED))


## A food errand names a KIND, not an id: nothing in this simulation decides
## which specific food a hungry villager wants, and inventing one would be
## authored content.
func test_a_food_errand_names_no_specific_item():
	var frame := _frame({"is_hungry": true, "meal_available": false})
	assert_eq(_of_kind(QuestOffer.offers_for(frame), QuestOffer.KIND_FEED)["item_id"], "")


# -- source 3: remembered threat ---------------------------------------------


func test_a_firsthand_memory_of_a_raid_becomes_somewhere_to_go_and_look():
	var frame := _frame({"memories": [_memory("regional_trade_raided", 1.0)]})
	var offer := _of_kind(QuestOffer.offers_for(frame), QuestOffer.KIND_INVESTIGATE)
	assert_false(offer.is_empty())
	assert_eq(offer["target_id"], "settlement:9")


func test_a_remembered_ruin_is_also_somewhere_to_look():
	var frame := _frame({"memories": [_memory("ruin_formed", 1.0)]})
	assert_true(_kinds_in(QuestOffer.offers_for(frame)).has(QuestOffer.KIND_INVESTIGATE))


## The floor is MEASURED against the real decay chain, not guessed: what
## survives two retellings is too degraded to send anyone after.
func test_the_threat_floor_is_measured_against_the_real_rumor_decay():
	var firsthand := MemoryRecord.new()
	firsthand.event_id = "evt"
	firsthand.holder = "npc:1"
	firsthand.remembered_type = "regional_trade_raided"
	firsthand.source_type = MemoryRecord.FIRSTHAND
	var once = Rumor.transmit(firsthand, "npc:2", 1.0)
	var twice = Rumor.transmit(once, "npc:3", 2.0)

	var after_one := DialogueTopic.belief_strength(
		{"confidence": once.confidence, "distortion": once.distortion}
	)
	var after_two := DialogueTopic.belief_strength(
		{"confidence": twice.confidence, "distortion": twice.distortion}
	)
	assert_gt(QuestOffer.min_threat_strength(), after_two)
	assert_lt(QuestOffer.min_threat_strength(), after_one)


func test_a_third_hand_rumour_is_not_worth_sending_anyone_after():
	var frame := _frame({"memories": [_memory("regional_trade_raided", 0.36, 0.7)]})
	assert_false(_kinds_in(QuestOffer.offers_for(frame)).has(QuestOffer.KIND_INVESTIGATE))


## An ordinary memory is news, not an errand -- only a memory of something
## that went WRONG has anywhere to send you.
func test_a_memory_of_something_harmless_is_not_an_errand():
	var frame := _frame({"memories": [_memory("settlement_founded", 1.0)]})
	assert_eq(QuestOffer.offers_for(frame), [])


func test_a_threat_remembered_nowhere_in_particular_is_not_an_errand():
	var memory := _memory("regional_trade_raided", 1.0)
	memory["place_settlement_id"] = ""
	assert_eq(QuestOffer.offers_for(_frame({"memories": [memory]})), [])


# -- source 6: hardship ------------------------------------------------------


func test_deep_snow_makes_someone_who_cannot_cut_wood_ask_for_firewood():
	var frame := _frame({"is_producer": false, "snow_depth": 1.0})
	var offer := _of_kind(QuestOffer.offers_for(frame), QuestOffer.KIND_FIREWOOD)
	assert_false(offer.is_empty())
	assert_eq(offer["item_id"], QuestOffer.FIREWOOD_ITEM_ID)
	assert_gt(offer["count"], 0)


## Someone who produces for a living can go and get their own wood; the
## hardship source is about people who cannot.
func test_a_producer_in_deep_snow_asks_for_no_firewood():
	var frame := _frame({"is_producer": true, "snow_depth": 1.0})
	assert_false(_kinds_in(QuestOffer.offers_for(frame)).has(QuestOffer.KIND_FIREWOOD))


func test_a_dusting_of_snow_is_not_hardship():
	var frame := _frame({"is_producer": false, "snow_depth": QuestOffer.MIN_SNOW_FOR_HARDSHIP * 0.5})
	assert_false(_kinds_in(QuestOffer.offers_for(frame)).has(QuestOffer.KIND_FIREWOOD))


func test_deeper_snow_asks_for_more_wood():
	var shallow := _of_kind(
		QuestOffer.offers_for(_frame({"is_producer": false, "snow_depth": 0.5})),
		QuestOffer.KIND_FIREWOOD
	)
	var deep := _of_kind(
		QuestOffer.offers_for(_frame({"is_producer": false, "snow_depth": 1.0})),
		QuestOffer.KIND_FIREWOOD
	)
	assert_gt(deep["count"], shallow["count"])


# -- the shape quests.md fixes ----------------------------------------------


func test_every_offer_carries_the_documented_shape():
	var frame := _frame({
		"shortfall_missing": [{"item_id": "rock", "need": 3}],
		"is_hungry": true, "meal_available": false,
		"is_producer": false, "snow_depth": 1.0,
		"memories": [_memory("regional_trade_raided", 1.0)],
	})
	var offers := QuestOffer.offers_for(frame)
	assert_eq(offers.size(), 4, "all four live sources fire at once")
	for offer in offers:
		for key in QuestOffer.OFFER_KEYS:
			assert_true(offer.has(key), "%s is missing %s" % [offer["kind"], key])


func test_every_kind_is_reachable():
	var frame := _frame({
		"shortfall_missing": [{"item_id": "rock", "need": 3}],
		"is_hungry": true, "meal_available": false,
		"is_producer": false, "snow_depth": 1.0,
		"memories": [_memory("regional_trade_raided", 1.0)],
	})
	var kinds := _kinds_in(QuestOffer.offers_for(frame))
	for kind in QuestOffer.KINDS:
		assert_true(kinds.has(kind), "no offer of kind %s" % kind)


# -- urgency is not a second opinion ----------------------------------------


## The offer layer does not compute its own weights. Every kind's urgency IS
## the salience DialogueTopic already measured for the topic it comes from,
## so a villager can never ask harder than they talk about it.
func test_urgency_is_the_salience_the_topic_layer_already_measured():
	var frame := _shortfall_frame("rock", 3)
	var offer: Dictionary = QuestOffer.offers_for(frame)[0]
	assert_almost_eq(
		float(offer["salience"]),
		DialogueTopic.salience(DialogueTopic.TOPIC_HOUSEHOLD_ASK, frame),
		0.0001
	)


func test_every_kind_names_a_real_topic_to_borrow_its_salience_from():
	for kind in QuestOffer.KINDS:
		assert_true(
			DialogueTopic.TOPIC_IDS.has(QuestOffer.TOPIC_BY_KIND[kind]),
			"%s borrows a topic that does not exist" % kind
		)


func test_the_most_urgent_offer_comes_first():
	var frame := _frame({
		"shortfall_missing": [{"item_id": "rock", "need": 5}],
		"is_hungry": true, "hunger": 1.0, "meal_available": false,
	})
	var offers := QuestOffer.offers_for(frame)
	assert_gt(offers.size(), 1)
	for i in range(1, offers.size()):
		assert_true(float(offers[i - 1]["salience"]) >= float(offers[i]["salience"]))


func test_the_best_offer_is_the_first_one():
	var frame := _frame({
		"shortfall_missing": [{"item_id": "rock", "need": 5}],
		"is_hungry": true, "hunger": 1.0, "meal_available": false,
	})
	assert_eq(QuestOffer.best_for(frame), QuestOffer.offers_for(frame)[0])


func test_a_villager_with_no_errand_has_no_best_offer():
	assert_eq(QuestOffer.best_for(_frame()), {})


# -- the reward rides along, derived ----------------------------------------


func test_the_reward_is_derived_from_the_askers_own_wallet():
	var offer: Dictionary = QuestOffer.offers_for(
		_frame({"shortfall_missing": [{"item_id": "rock", "need": 3}], "wallet_gold": 2})
	)[0]
	assert_eq(offer["reward"]["amount"], 2)
	assert_true(offer["reward"]["is_short"])


## A villager with nothing still asks -- the need is real whether or not they
## can pay for it. Refusing to voice it would be the offer layer deciding a
## real shortage does not exist.
func test_a_penniless_villager_still_asks():
	var offers := QuestOffer.offers_for(
		_frame({"shortfall_missing": [{"item_id": "rock", "need": 3}], "wallet_gold": 0})
	)
	assert_eq(offers.size(), 1)
	assert_eq(offers[0]["reward"]["amount"], 0)


func test_the_reward_is_the_same_number_quest_reward_computes():
	var offer: Dictionary = QuestOffer.offers_for(_shortfall_frame("rock", 3))[0]
	assert_eq(offer["reward"], QuestReward.gold_for(3, 200))


# -- the id reads back -------------------------------------------------------


## The derived id is the whole persistence story: an accepted errand is a
## Contract, and a Contract holds free-form strings. Because the id already
## names the kind, the subject and the count, the errand can be rebuilt from
## it with nothing else stored -- which is why deriving it was worth doing at
## all rather than allocating one.
func test_every_kind_of_offer_survives_a_round_trip_through_its_id():
	var frame := _frame({
		"shortfall_missing": [{"item_id": "rock", "need": 3}],
		"is_hungry": true, "meal_available": false,
		"is_producer": false, "snow_depth": 1.0,
		"memories": [_memory("regional_trade_raided", 1.0)],
	})
	for offer in QuestOffer.offers_for(frame):
		var parsed := QuestOffer.parse_id(offer["offer_id"])
		assert_eq(parsed["kind"], offer["kind"])
		assert_eq(parsed["count"], offer["count"])


## The one case a naive split gets wrong: an errand whose subject is an
## entity id, which has a colon of its own.
func test_a_subject_with_colons_in_it_still_reads_back_whole():
	var parsed := QuestOffer.parse_id(
		QuestOffer.id_of(QuestOffer.KIND_INVESTIGATE, "settlement:9", 0)
	)
	assert_eq(parsed["kind"], QuestOffer.KIND_INVESTIGATE)
	assert_eq(parsed["subject"], "settlement:9")
	assert_eq(parsed["count"], 0)


func test_something_that_is_not_an_offer_id_reads_back_as_nothing():
	assert_eq(QuestOffer.parse_id("")["kind"], "")
	assert_eq(QuestOffer.parse_id("rock")["kind"], "")
	assert_eq(QuestOffer.parse_id("fetch:rock:not_a_number")["kind"], "")
