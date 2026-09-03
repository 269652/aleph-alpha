extends GutTest

## DialogueTopic (see src/dialogue/dialogue_topic.gd, docs/concept/
## dialogue.md's pipeline diagram) -- the scored-topic stage between the
## frame and DialogueMove.
##
## Two rules are what these tests exist for, and nearly every test below
## pins one of them:
##
## 1. A TOPIC IS OMITTED WHEN ITS FACTS ARE EMPTY (dialogue.md pillar 2).
##    There is no fallback line anywhere, so a frame with nothing in it
##    produces NO topics rather than a greeting about the weather. That
##    doubles as an instrument: a topic that is always empty is a SUBSTRATE
##    bug, and this file is where it surfaces.
## 2. SALIENCE IS A MEASURED NUMBER ALREADY IN THE SIMULATION (pillar 4),
##    never an authored weight. Every salience test below asserts against a
##    number some other module computed -- the villager's real hunger, the
##    real household/capacity ratio SettlementState classifies on,
##    SettlementTier's own thresholds, a real recipe's own input counts, a
##    memory's real confidence x (1 - distortion), and the real number of
##    retelling hops Rumor.transmit actually puts between two accounts.
##
## Frames are built through the REAL DialogueContext.build wherever the test
## is about what a topic reads, and a built frame's plain fields are
## overridden directly only where the test is a numeric sweep over one
## quantity (a frame is a flat Dictionary of plain values by construction --
## that is the whole point of it). A real EarthChunkManager is never
## constructed: one update() of one costs ~60 seconds.

const DialogueContext = preload("res://src/dialogue/dialogue_context.gd")
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")

const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const Household = preload("res://src/emergence/household.gd")
const Market = preload("res://src/emergence/market.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const MemoryStore = preload("res://src/emergence/memory_store.gd")
const Rumor = preload("res://src/emergence/rumor.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")

const NpcEconomy = preload("res://src/world/npc_economy.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const VillageWages = preload("res://src/world/village_wages.gd")

## The same fixed villager seed test_dialogue_context.gd uses, so a frame
## built here is the frame built there.
const SEED := 4711
const SETTLEMENT := "settlement:3_-7"


func _npc_id() -> String:
	return EntityRef.for_npc(SEED)


func _frame(sources: Dictionary) -> Dictionary:
	return DialogueContext.build(_npc_id(), sources)


## Records one real event into `store`, witnessed by `holder`, through the
## real Event/MemoryStore.witness_event path -- so every memory under test is
## exactly the shape live play produces.
func _remember(store: MemoryStore, holder: String, type: String, tick: float, tags: Array = []) -> Event:
	var event := Event.new(type, tick)
	event.actors.append(holder)
	for tag in tags:
		event.tags.append(str(tag))
	event.id = "evt_%s_%s_%d" % [holder, type, int(tick)]
	store.witness_event(event, tick)
	return event


## A real VillageMarket holding enough food that can_buy_meal() is true --
## the market's own live answer, never a flag this test invents.
func _stocked_village_market() -> VillageMarket:
	var market := VillageMarket.new()
	market.add_stock("fruit", 10.0)
	return market


# -- rule 1: an empty fact means no topic ------------------------------------


func test_a_frame_built_from_nothing_at_all_produces_no_topics_whatsoever():
	# The whole anti-filler guarantee in one assertion: a villager the caller
	# wired nothing for has nothing to say, and the system says nothing
	# rather than reaching for a line about the weather.
	var frame := _frame({})

	assert_eq(DialogueTopic.available_for(frame), [], "no facts must mean no topics")


func test_every_declared_topic_is_omitted_when_its_own_facts_are_empty():
	var frame := _frame({})

	for topic_id in DialogueTopic.TOPIC_IDS:
		assert_eq(
			DialogueTopic.facts_for(topic_id, frame), {},
			"%s must have no facts in an empty frame" % topic_id
		)
		assert_false(
			DialogueTopic.is_available(topic_id, frame),
			"%s must be omitted when its facts are empty" % topic_id
		)


func test_availability_is_defined_as_having_facts_not_asserted_separately():
	# is_available must not be able to drift from facts_for: an available
	# topic with no facts would be a filler line by another name.
	var memory_store := MemoryStore.new()
	_remember(memory_store, SETTLEMENT, "production_failed", 30.0, ["stone_pickaxe"])
	var frame := _frame({
		"memory_store": memory_store,
		"settlement_id": SETTLEMENT,
		"season": "winter",
		"snow_depth": 0.4,
	})

	for topic_id in DialogueTopic.TOPIC_IDS:
		assert_eq(
			DialogueTopic.is_available(topic_id, frame),
			not DialogueTopic.facts_for(topic_id, frame).is_empty(),
			"%s: availability must be exactly non-empty facts" % topic_id
		)


func test_an_unavailable_topic_scores_zero_rather_than_a_default():
	var frame := _frame({})

	for topic_id in DialogueTopic.TOPIC_IDS:
		assert_eq(
			DialogueTopic.salience(topic_id, frame), 0.0,
			"%s must score nothing when it has nothing to say" % topic_id
		)


func test_an_unknown_topic_id_is_simply_unavailable_rather_than_an_error():
	var frame := _frame({"season": "winter"})

	assert_eq(DialogueTopic.facts_for("not_a_topic", frame), {})
	assert_false(DialogueTopic.is_available("not_a_topic", frame))
	assert_eq(DialogueTopic.salience("not_a_topic", frame), 0.0)


func test_topic_ids_are_unique():
	var seen := {}
	for topic_id in DialogueTopic.TOPIC_IDS:
		assert_false(seen.has(topic_id), "duplicate topic id %s" % topic_id)
		seen[topic_id] = true


# -- rule 2: salience is a measured number -----------------------------------


func test_hunger_salience_is_the_villagers_own_real_hunger_number():
	var economy := NpcEconomy.new(SEED, "blacksmith", null)
	economy.needs.hunger = 0.8

	var frame := _frame({"economy": economy})

	assert_true(DialogueTopic.is_available("hunger", frame))
	assert_almost_eq(DialogueTopic.salience("hunger", frame), 0.8, 0.0001)


func test_a_villager_who_is_not_hungry_by_npc_needs_own_threshold_has_no_hunger_topic():
	var economy := NpcEconomy.new(SEED, "blacksmith", null)
	economy.needs.hunger = 0.1

	var frame := _frame({"economy": economy})

	assert_false(
		DialogueTopic.is_available("hunger", frame),
		"hunger is a topic when NpcNeeds says they are hungry, not whenever hunger > 0"
	)


func test_the_wallet_topic_is_a_meal_they_cannot_pay_for_never_merely_being_poor():
	# "A permanent state is not news" is the substrate lesson dialogue.md's
	# own gap table states. Being broke forever is not a topic; a meal really
	# sitting on the village market's shelf that this wallet cannot reach is.
	var economy := NpcEconomy.new(SEED, "blacksmith", null)
	economy.wallet.balance = 0

	var no_market := _frame({"economy": economy})
	assert_false(
		DialogueTopic.is_available("wallet", no_market),
		"no meal to buy means no topic about not affording one"
	)

	var with_market := _frame({"economy": economy, "village_market": _stocked_village_market()})
	assert_true(DialogueTopic.is_available("wallet", with_market))
	assert_almost_eq(
		DialogueTopic.salience("wallet", with_market),
		1.0,
		0.0001,
		"a villager with nothing is a whole meal price short"
	)


func test_wallet_salience_is_the_fraction_of_the_real_meal_price_they_are_short():
	var economy := NpcEconomy.new(SEED, "blacksmith", null)
	economy.wallet.balance = VillageWages.subsistence_wage() - 1

	var frame := _frame({"economy": economy, "village_market": _stocked_village_market()})

	var price := float(VillageWages.subsistence_wage())
	assert_almost_eq(DialogueTopic.salience("wallet", frame), 1.0 / price, 0.0001)


func test_a_villager_who_can_afford_the_meal_in_front_of_them_has_no_wallet_topic():
	var economy := NpcEconomy.new(SEED, "blacksmith", null)
	economy.wallet.balance = VillageWages.subsistence_wage()

	var frame := _frame({"economy": economy, "village_market": _stocked_village_market()})

	assert_false(DialogueTopic.is_available("wallet", frame))


func test_wage_salience_is_how_far_the_real_village_purse_is_from_one_real_wage():
	# The purse is the substrate slice's own number (VillageWages), and the
	# wage it cannot pay is one meal at the market's own live price.
	var market := VillageMarket.new()
	NpcEconomy._set_purse(market, 0.5)
	var economy := NpcEconomy.new(SEED, "blacksmith", market)
	# The occupation the topic reads is the IDENTITY's -- an occupation the
	# frame does not know is not a non-producer, it is an absent fact.
	var identity := NpcIdentity.new(SEED)
	identity.occupation = "blacksmith"

	var frame := _frame({
		"identity": identity, "economy": economy,
		"village_market": market, "settlement_id": SETTLEMENT,
	})

	var wage := float(VillageWages.subsistence_wage())
	assert_true(DialogueTopic.is_available("wage", frame))
	assert_almost_eq(DialogueTopic.salience("wage", frame), (wage - 0.5) / wage, 0.0001)


func test_a_producer_has_no_wage_topic_because_the_purse_is_not_what_feeds_them():
	var market := VillageMarket.new()
	NpcEconomy._set_purse(market, 0.0)
	var economy := NpcEconomy.new(SEED, "hunter", market)
	var identity := NpcIdentity.new(SEED)
	identity.occupation = "hunter"

	var frame := _frame({
		"identity": identity, "economy": economy,
		"village_market": market, "settlement_id": SETTLEMENT,
	})

	assert_false(DialogueTopic.is_available("wage", frame))


func test_village_status_salience_crosses_settlement_states_own_band_exactly_when_the_label_does():
	# The measured quantity behind "we're growing" IS household_count /
	# capacity -- the one number SettlementState.status_for thresholds on --
	# so the topic's salience must agree with the label at every point of a
	# real sweep, not merely correlate with it.
	var frame := _frame({"settlement_id": SETTLEMENT})

	for households in range(0, 12):
		for capacity in range(0, 12):
			frame["settlement_household_count"] = households
			frame["settlement_capacity"] = capacity
			frame["settlement_status"] = SettlementState.status_for(households, capacity)
			var score: float = DialogueTopic.salience("village_status", frame)
			var is_pressured: bool = frame["settlement_status"] != SettlementState.STABLE
			assert_eq(
				score > SettlementState.STABLE_BAND, is_pressured,
				"%d households / %d capacity: %s scored %f" % [
					households, capacity, frame["settlement_status"], score
				]
			)


func test_a_villager_with_no_settlement_has_no_village_topics_at_all():
	var frame := _frame({"household_count": 4})

	for topic_id in ["village_status", "village_tier", "village_specialization", "village_food"]:
		assert_false(
			DialogueTopic.is_available(topic_id, frame),
			"%s must be omitted when there is no village on record" % topic_id
		)


func test_village_food_salience_is_the_share_of_the_villages_own_food_need_it_lacks():
	# The need is households x SettlementState.FOOD_PER_HOUSEHOLD -- the same
	# per-household draw carrying_capacity itself divides by, never a second
	# number invented here.
	var market := Market.new()
	market.add_stock("fruit", 4)
	var frame := _frame({
		"settlement_id": SETTLEMENT, "market": market, "household_count": 4,
	})

	var needed := 4 * SettlementState.FOOD_PER_HOUSEHOLD
	var expected := 1.0 - 4.0 / float(needed)
	assert_true(DialogueTopic.is_available("village_food", frame))
	assert_almost_eq(DialogueTopic.salience("village_food", frame), expected, 0.0001)


func test_a_village_that_can_feed_itself_has_no_food_topic():
	var market := Market.new()
	market.add_stock("fruit", 4 * SettlementState.FOOD_PER_HOUSEHOLD)
	var frame := _frame({
		"settlement_id": SETTLEMENT, "market": market, "household_count": 4,
	})

	assert_false(DialogueTopic.is_available("village_food", frame))


func test_village_tier_salience_is_measured_against_settlement_tiers_own_city_thresholds():
	var frame := _frame({"settlement_id": SETTLEMENT})
	frame["settlement_tier"] = SettlementTier.HAMLET
	frame["settlement_household_count"] = SettlementTier.CITY_HOUSEHOLDS
	frame["settlement_production_diversity"] = SettlementTier.CITY_PRODUCTION_DIVERSITY

	assert_almost_eq(
		DialogueTopic.salience("village_tier", frame), 1.0, 0.0001,
		"a village at the top-tier thresholds is as much of a place as the tier scale measures"
	)

	frame["settlement_household_count"] = 0
	assert_eq(
		DialogueTopic.salience("village_tier", frame), 0.0,
		"all three dimensions must cross together -- the smallest one governs"
	)


func test_specialization_salience_is_how_concentrated_the_villages_real_production_is():
	var frame := _frame({"settlement_id": SETTLEMENT})
	frame["settlement_specialization"] = "hunting center"

	frame["settlement_production_diversity"] = 1
	assert_almost_eq(DialogueTopic.salience("village_specialization", frame), 1.0, 0.0001)

	frame["settlement_production_diversity"] = 4
	assert_almost_eq(DialogueTopic.salience("village_specialization", frame), 0.25, 0.0001)


func test_weather_salience_is_the_real_snow_depth_the_world_is_carrying():
	var frame := _frame({"season": "winter", "weather": "snow", "snow_depth": 0.62})

	assert_true(DialogueTopic.is_available("weather", frame))
	assert_almost_eq(DialogueTopic.salience("weather", frame), 0.62, 0.0001)


func test_household_ask_salience_is_the_unmet_share_of_the_recipes_own_inputs():
	# stone_pickaxe wants 2 stick + 3 rock. Short 3 rock is 3 of the 5 units
	# the real recipe needs -- read off CraftingRecipeBook, the same book
	# Quest._missing_inputs built the shortfall from.
	var identity := NpcIdentity.new(SEED)
	identity.occupation = "blacksmith"
	var household_id: String = Household.for_founder(_npc_id()).id
	var frame := _frame({
		"identity": identity,
		"settlement_id": SETTLEMENT,
		"shortfalls": [{
			"settlement_id": SETTLEMENT,
			"household_id": household_id,
			"recipe_id": "stone_pickaxe",
			"missing": [{"item_id": "rock", "need": 3}],
		}],
	})

	var inputs: Array = CraftingRecipeBook.new().recipe_inputs("stone_pickaxe")
	var recipe_units := 0
	for input in inputs:
		recipe_units += int(input["count"])

	assert_true(DialogueTopic.is_available("household_ask", frame))
	assert_almost_eq(
		DialogueTopic.salience("household_ask", frame), 3.0 / float(recipe_units), 0.0001
	)


func test_a_household_short_of_nothing_asks_for_nothing():
	var identity := NpcIdentity.new(SEED)
	identity.occupation = "blacksmith"

	var frame := _frame({"identity": identity, "settlement_id": SETTLEMENT, "shortfalls": []})

	assert_false(DialogueTopic.is_available("household_ask", frame))


# -- memory topics -----------------------------------------------------------


func test_a_memory_topics_salience_is_confidence_times_one_minus_distortion():
	var memory_store := MemoryStore.new()
	var event := _remember(memory_store, SETTLEMENT, "regional_trade_raided", 30.0, ["rock"])
	var memory: MemoryRecord = memory_store.memories_for(SETTLEMENT)[0]
	memory.confidence = 0.8
	memory.distortion = 0.25

	var frame := _frame({"memory_store": memory_store, "settlement_id": SETTLEMENT})

	assert_true(DialogueTopic.is_available("raid", frame))
	assert_almost_eq(DialogueTopic.salience("raid", frame), 0.8 * 0.75, 0.0001)
	assert_eq(DialogueTopic.facts_for("raid", frame)["top_memory"]["event_id"], event.id)


func test_the_strongest_belief_sets_a_memory_topics_salience():
	var memory_store := MemoryStore.new()
	_remember(memory_store, SETTLEMENT, "institution_formed", 10.0)
	_remember(memory_store, SETTLEMENT, "institution_dissolved", 20.0)
	var records: Array = memory_store.memories_for(SETTLEMENT)
	records[0].confidence = 0.9
	records[1].confidence = 0.3

	var frame := _frame({"memory_store": memory_store, "settlement_id": SETTLEMENT})

	assert_almost_eq(DialogueTopic.salience("institution", frame), 0.9, 0.0001)


func test_importance_is_carried_as_a_fact_but_never_multiplied_into_salience():
	# Only 5 of the 18 emitters in src/ ever set Event.importance, so a
	# salience that multiplied it in would zero out thirteen eighteenths of
	# every villager's news. It is real where it exists and is carried as a
	# fact for whoever ranks beats -- it is not the measured quantity
	# dialogue.md pillar 4 names.
	var memory_store := MemoryStore.new()
	var event_store := EventStore.new()
	var event := Event.new("ruin_formed", 30.0)
	event.actors.append(SETTLEMENT)
	event.importance = 0.4
	event_store.append(event)
	memory_store.witness_event(event, 30.0)

	var frame := _frame({
		"memory_store": memory_store, "event_store": event_store, "settlement_id": SETTLEMENT,
	})

	assert_almost_eq(
		DialogueTopic.salience("ruin", frame), 1.0, 0.0001,
		"a firsthand, undistorted memory is worth its full belief strength"
	)
	assert_almost_eq(DialogueTopic.facts_for("ruin", frame)["top_memory"]["importance"], 0.4, 0.0001)


func test_every_memory_topic_claims_its_event_types_exclusively():
	var claimed := {}
	for topic_id in DialogueTopic.MEMORY_TOPIC_EVENT_TYPES:
		for event_type in DialogueTopic.MEMORY_TOPIC_EVENT_TYPES[topic_id]:
			assert_false(
				claimed.has(event_type),
				"%s is claimed by both %s and %s" % [event_type, claimed.get(event_type, ""), topic_id]
			)
			claimed[event_type] = topic_id
			assert_eq(DialogueTopic.memory_topic_for(event_type), topic_id)


func test_the_interpolated_event_families_are_built_from_the_substrates_own_lists():
	# EarthChunkManager emits "settlement_%s" % status and
	# "settlement_became_%s" % tier, so the topic table has to agree with
	# SettlementState.STATUSES and SettlementTier.TIERS rather than restate
	# them -- a new status or tier must not silently become unclaimed news.
	for status in SettlementState.STATUSES:
		assert_eq(
			DialogueTopic.memory_topic_for("settlement_%s" % status), "village_history",
			"settlement_%s is real news nothing claims" % status
		)
	for tier in SettlementTier.TIERS:
		assert_eq(
			DialogueTopic.memory_topic_for("settlement_became_%s" % tier), "village_history",
			"settlement_became_%s is real news nothing claims" % tier
		)


func test_every_event_type_the_substrate_really_emits_is_claimed_by_some_topic():
	# The instrument dialogue.md pillar 2 asks for, pointed at the emitters
	# themselves: a new Event.new(...) in the world coordinator with no topic
	# to carry it is news no villager can ever say out loud. Scans the real
	# file rather than trusting a list restated here.
	var emitted := _emitted_event_types()
	assert_gt(emitted.size(), 10, "the scan must actually be finding emitters")

	for event_type in emitted:
		assert_ne(
			DialogueTopic.memory_topic_for(event_type), "",
			(
				"%s is emitted by src/world/earth_chunk_manager.gd but no dialogue topic "
				+ "claims it -- add it to DialogueTopic.MEMORY_TOPIC_EVENT_TYPES"
			) % event_type
		)


func test_no_topic_claims_an_event_type_nothing_in_the_substrate_emits():
	var emitted := _emitted_event_types()
	for topic_id in DialogueTopic.MEMORY_TOPIC_EVENT_TYPES:
		for event_type in DialogueTopic.MEMORY_TOPIC_EVENT_TYPES[topic_id]:
			assert_true(
				emitted.has(event_type),
				"%s claims %s, which nothing in src/ emits" % [topic_id, event_type]
			)


## Every event type src/world/earth_chunk_manager.gd really constructs, as a
## Dictionary used as a set. Reads the file itself: the alternative is a list
## restated here, which is exactly the drift this test exists to catch.
##
## Two emitters do not spell their type as one literal and are expanded the
## same way the file does: "settlement_%s" over SettlementState.STATUSES and
## "settlement_became_%s" over SettlementTier.TIERS. One more passes a
## variable (_record_contract_event's `event_type`); its four real values are
## recovered by looking for them as literals in the same file.
func _emitted_event_types() -> Dictionary:
	var path := "res://src/world/earth_chunk_manager.gd"
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "cannot read %s" % path)
	var text := file.get_as_text()

	var types := {}
	var call_re := RegEx.create_from_string("Event\\.new\\(([^,]*),")
	var literal_re := RegEx.create_from_string("\"([a-z_%]+)\"")
	for call in call_re.search_all(text):
		for literal in literal_re.search_all(call.get_string(1)):
			var raw := literal.get_string(1)
			if not raw.contains("%"):
				types[raw] = true
				continue
			var expansions: Array = []
			if raw == "settlement_%s":
				expansions = SettlementState.STATUSES
			elif raw == "settlement_became_%s":
				expansions = SettlementTier.TIERS
			else:
				fail_test("unexpected interpolated event type %s -- teach the scan about it" % raw)
			for expansion in expansions:
				types[raw % expansion] = true

	for outcome in ["contract_fulfilled", "contract_breached", "contract_defaulted", "contract_cancelled"]:
		if text.contains("\"%s\"" % outcome):
			types[outcome] = true
	return types


## The concrete gap the census test above catches in the abstract:
## record_player_settled_if_new (EarthChunkManager) emits `player_settled`
## with the player as actor and the settlement as witness -- structurally
## identical to npc_settled (see _settled_event below), so it belongs where
## npc_settled already lives, not in village_history. Folding it into
## village_history instead would let the player's own arrival stand in for
## whether the village's actual fortunes are being witnessed at all --
## exactly the hazard MEMORY_TOPIC_EVENT_TYPES's own doc comment already
## names as the reason npc_settled was split off in the first place.
func test_player_settled_joins_arrival_alongside_npc_settled_not_village_history():
	var memory_store := MemoryStore.new()
	var event := _remember(memory_store, SETTLEMENT, "player_settled", 15.0)

	var frame := _frame({"memory_store": memory_store, "settlement_id": SETTLEMENT})

	assert_eq(DialogueTopic.memory_topic_for("player_settled"), DialogueTopic.TOPIC_ARRIVAL)
	assert_true(DialogueTopic.is_available(DialogueTopic.TOPIC_ARRIVAL, frame))
	assert_eq(DialogueTopic.facts_for(DialogueTopic.TOPIC_ARRIVAL, frame)["top_memory"]["event_id"], event.id)
	assert_false(
		DialogueTopic.is_available(DialogueTopic.TOPIC_VILLAGE_HISTORY, frame),
		"the player's own arrival must not read as village-fortune news"
	)


# -- who else is standing here -----------------------------------------------


func test_the_neighbour_topic_needs_a_memory_that_names_the_person_standing_here():
	var neighbour_seed := 991
	var neighbour_id := EntityRef.for_npc(neighbour_seed)
	var neighbour := NpcIdentity.new(neighbour_seed)

	var memory_store := MemoryStore.new()
	# The settlement's own bank holds every villager's npc_settled -- the one
	# place a co-present neighbour is named by id in something this villager
	# can read.
	_remember(memory_store, neighbour_id, "npc_settled", 10.0)
	memory_store.witness_event(_settled_event(neighbour_id, 10.0), 10.0)

	var alone := _frame({"memory_store": memory_store, "settlement_id": SETTLEMENT})
	assert_false(
		DialogueTopic.is_available("neighbour", alone),
		"nobody standing here means nobody to talk about"
	)

	var together := _frame({
		"memory_store": memory_store,
		"settlement_id": SETTLEMENT,
		"co_present_identities": [neighbour],
	})
	assert_true(DialogueTopic.is_available("neighbour", together))
	assert_eq(DialogueTopic.facts_for("neighbour", together)["npc_id"], neighbour_id)


## An npc_settled event shaped exactly as EarthChunkManager emits it: the
## villager is the actor, the settlement the witness, so the settlement's
## bank is where anybody else can read it.
func _settled_event(npc_id: String, tick: float) -> Event:
	var event := Event.new("npc_settled", tick)
	event.id = "evt_settled_%s" % npc_id
	event.actors.append(npc_id)
	event.witnesses.append(SETTLEMENT)
	return event


# -- contradiction -----------------------------------------------------------


func test_contradiction_needs_the_same_event_told_two_or_more_retellings_apart():
	var neighbour_seed := 991
	var neighbour := NpcIdentity.new(neighbour_seed)
	var neighbour_id := EntityRef.for_npc(neighbour_seed)
	var middle_id := EntityRef.for_npc(555)

	var memory_store := MemoryStore.new()
	var event := _remember(memory_store, _npc_id(), "regional_trade_raided", 30.0)

	# One hop: our villager saw it, the neighbour was told by them.
	memory_store.transmit(_npc_id(), neighbour_id, event.id, 31.0)
	var one_hop := _frame({
		"memory_store": memory_store, "co_present_identities": [neighbour],
	})
	assert_false(
		DialogueTopic.is_available("contradiction", one_hop),
		"one retelling apart is not a disagreement worth naming"
	)

	# Two hops: it reached the neighbour through somebody else first.
	var far_store := MemoryStore.new()
	var far_event := _remember(far_store, _npc_id(), "regional_trade_raided", 30.0)
	far_store.transmit(_npc_id(), middle_id, far_event.id, 31.0)
	far_store.transmit(middle_id, neighbour_id, far_event.id, 32.0)
	var two_hops := _frame({
		"memory_store": far_store, "co_present_identities": [neighbour],
	})
	assert_true(
		DialogueTopic.is_available("contradiction", two_hops),
		"Bren saw it himself; Lira heard it thirdhand"
	)


func test_contradiction_salience_is_the_distance_on_the_real_retelling_ladder():
	var neighbour_seed := 991
	var neighbour := NpcIdentity.new(neighbour_seed)
	var neighbour_id := EntityRef.for_npc(neighbour_seed)
	var middle_id := EntityRef.for_npc(555)

	var memory_store := MemoryStore.new()
	var event := _remember(memory_store, _npc_id(), "regional_trade_raided", 30.0)
	memory_store.transmit(_npc_id(), middle_id, event.id, 31.0)
	memory_store.transmit(middle_id, neighbour_id, event.id, 32.0)

	var frame := _frame({"memory_store": memory_store, "co_present_identities": [neighbour]})

	var depths := DialogueTopic.hop_depths()
	var deepest := 0
	for source_type in depths:
		deepest = maxi(deepest, int(depths[source_type]))
	assert_almost_eq(
		DialogueTopic.salience("contradiction", frame), 2.0 / float(deepest), 0.0001
	)
	assert_eq(DialogueTopic.facts_for("contradiction", frame)["steps"], 2)


func test_the_retelling_ladder_is_measured_by_running_the_real_rumor_transmission():
	# The steps are hops through Rumor.transmit, NOT indices into
	# MemoryRecord.SOURCE_TYPES: the transmission chain skips WITNESSED,
	# INFERENCE and WRITTEN_RECORD entirely, so firsthand -> trusted_testimony
	# is ONE retelling even though it is two places apart in that enum.
	var depths := DialogueTopic.hop_depths()

	assert_eq(depths.get(MemoryRecord.FIRSTHAND), 0)
	assert_eq(depths.get(MemoryRecord.WITNESSED), 0, "seeing it from the sidelines is still seeing it")
	assert_eq(depths.get(MemoryRecord.TRUSTED_TESTIMONY), 1)
	assert_eq(depths.get(MemoryRecord.STRANGER_TESTIMONY), 2)
	assert_eq(depths.get(MemoryRecord.RUMOR), 3)
	for unreachable in [MemoryRecord.INFERENCE, MemoryRecord.WRITTEN_RECORD]:
		assert_false(
			depths.has(unreachable),
			"%s is written by nothing in src/ -- it must not be on a measured ladder" % unreachable
		)

	# And the ladder really is what Rumor does, not a copy of it.
	var memory := MemoryRecord.new()
	memory.event_id = "evt"
	memory.holder = _npc_id()
	memory.source_type = MemoryRecord.FIRSTHAND
	var told = Rumor.transmit(memory, "npc:2", 1.0)
	assert_eq(
		int(depths[told.source_type]), 1,
		"one real transmission must be exactly one step on the ladder"
	)


func test_a_neighbour_who_heard_it_the_same_way_contradicts_nothing():
	var neighbour_seed := 991
	var neighbour := NpcIdentity.new(neighbour_seed)
	var neighbour_id := EntityRef.for_npc(neighbour_seed)

	var memory_store := MemoryStore.new()
	var event := Event.new("regional_trade_raided", 30.0)
	event.id = "evt_shared"
	event.actors.append(SETTLEMENT)
	event.witnesses.append(_npc_id())
	event.witnesses.append(neighbour_id)
	memory_store.witness_event(event, 30.0)

	var frame := _frame({"memory_store": memory_store, "co_present_identities": [neighbour]})

	assert_false(
		DialogueTopic.is_available("contradiction", frame),
		"two people who both watched it happen are not in disagreement"
	)


# -- what available_for hands to DialogueMove --------------------------------


func test_available_for_returns_every_available_topic_scored_and_nothing_else():
	var economy := NpcEconomy.new(SEED, "blacksmith", null)
	economy.needs.hunger = 0.9
	var frame := _frame({"economy": economy, "season": "winter", "snow_depth": 0.2})

	var ids: Array = []
	for scored in DialogueTopic.available_for(frame):
		ids.append(scored["topic_id"])
		assert_eq(scored["salience"], DialogueTopic.salience(scored["topic_id"], frame))
		assert_eq(scored["facts"], DialogueTopic.facts_for(scored["topic_id"], frame))

	assert_eq(ids.size(), 2, "exactly the two topics with real facts: %s" % [ids])
	assert_true(ids.has("hunger"))
	assert_true(ids.has("weather"))


func test_every_salience_lands_in_zero_to_one_so_topics_can_be_ranked_against_each_other():
	# DialogueMove multiplies these by NpcSeenLedger.decay and takes top-k,
	# which is only meaningful if a hunger of 0.9 and a snow depth of 0.9
	# really are the same amount of wanting to talk. Each quantity is
	# normalised against the substrate's own anchor, never a chosen one.
	var economy := NpcEconomy.new(SEED, "hunter", null)
	economy.needs.hunger = 1.0
	economy.wallet.balance = 0
	var identity := NpcIdentity.new(SEED)
	identity.occupation = "hunter"
	var memory_store := MemoryStore.new()
	_remember(memory_store, SETTLEMENT, "settlement_declining", 30.0)
	_remember(memory_store, SETTLEMENT, "regional_trade_raided", 40.0)

	var frame := _frame({
		"identity": identity,
		"economy": economy,
		"memory_store": memory_store,
		"village_market": _stocked_village_market(),
		"settlement_id": SETTLEMENT,
		"household_count": 9,
		"season": "winter",
		"weather": "snow",
		"snow_depth": 1.0,
		"shortfalls": [{
			"household_id": Household.for_founder(_npc_id()).id,
			"recipe_id": "cooked_meat",
			"missing": [{"item_id": "meat", "need": 99}],
		}],
	})

	var scored := DialogueTopic.available_for(frame)
	assert_gt(scored.size(), 5, "this frame is meant to light up most of the board")
	for entry in scored:
		assert_between(
			entry["salience"], 0.0, 1.0,
			"%s scored outside the shared scale" % entry["topic_id"]
		)


func test_available_for_is_sorted_by_salience_descending_with_a_deterministic_tie_break():
	var economy := NpcEconomy.new(SEED, "blacksmith", null)
	economy.needs.hunger = 0.9
	var frame := _frame({"economy": economy, "season": "winter", "snow_depth": 0.2})

	var scored := DialogueTopic.available_for(frame)
	assert_eq(scored[0]["topic_id"], "hunger", "0.9 hunger outranks 0.2 of snow")

	# A tie must break on topic id, never on Dictionary iteration order.
	frame["snow_depth"] = 0.9
	var tied := DialogueTopic.available_for(frame)
	assert_eq(tied[0]["topic_id"], "hunger")
	assert_eq(tied[1]["topic_id"], "weather")
