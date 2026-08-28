extends GutTest

## DialogueContext (see src/dialogue/dialogue_context.gd, docs/concept/
## dialogue.md's pipeline diagram) -- the ONE place the conversation system
## reads the world, producing a flat, hashable frame shaped after
## FieldJournal.entry_for's "gather everything about one entity".
##
## Every test here is written against hand-built stores and small fakes: a
## real EarthChunkManager is the only thing that owns the live versions of
## these numbers, and a single update() of one costs ~60 seconds, so the
## module is deliberately pure enough that none of this needs an engine.
##
## Five of these tests pin traps this codebase has actually hit, and each is
## named for its trap rather than for the field it happens to assert:
##   1. A villager's OWN memory bank is nearly empty -- the news lives in the
##      "household:" and "settlement:" banks alongside it.
##   2. MemoryStore.memories_for reads in FIRST-FORMED order, so `.back()` is
##      the oldest-formed-last entry, not the latest-heard one; only
##      recorded_at descending is "latest".
##   3. NpcMarker._current_hour_of_day counts elapsed real seconds since that
##      marker happened to spawn and is never synced across markers (see
##      EarthChunkManager._current_hour_of_day's own doc comment). Only the
##      world clock is shared.
##   4. All 18 Event.new sites in src/ use the two-argument constructor, so
##      Event.location -- and therefore MemoryRecord.remembered_location --
##      is Vector2.ZERO everywhere. "Where" has to be reconstructed from the
##      entity ids a memory names.
##   5. remembered_outcome, emotional_salience, Event.visibility and
##      Event.evidence are written by NOTHING in src/ except their own
##      from_dict defaults. They are dead, and the frame must not pretend
##      otherwise by carrying them.

const DialogueContext = preload("res://src/dialogue/dialogue_context.gd")
## Read-only, and only by the burst tests below: "can they still answer about
## their arrival" is a question about the TOPIC, so asking the topic module is
## the honest way to ask it rather than re-implementing its lookup here.
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")

const EntityRef = preload("res://src/emergence/entity_ref.gd")
const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const Household = preload("res://src/emergence/household.gd")
const Market = preload("res://src/emergence/market.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const MemoryStore = preload("res://src/emergence/memory_store.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")

const Inventory = preload("res://src/gameplay/inventory.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")

const NpcEconomy = preload("res://src/world/npc_economy.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const VillageWages = preload("res://src/world/village_wages.gd")

## An arbitrary but fixed villager seed -- every derived id below is built
## from it rather than restated, so nothing here depends on which occupation
## this particular seed happens to roll.
const SEED := 4711
const SETTLEMENT := "settlement:3_-7"


func _npc_id() -> String:
	return EntityRef.for_npc(SEED)


## Records one real event into `store`, witnessed by `holder` at `tick`.
## Goes through the real Event/MemoryStore.witness_event path rather than
## hand-building a MemoryRecord, so the memories under test are exactly the
## shape live play produces (see EarthChunkManager's own emitters).
func _remember(store: MemoryStore, holder: String, type: String, tick: float, tags: Array = []) -> Event:
	var event := Event.new(type, tick)
	event.actors.append(holder)
	for tag in tags:
		event.tags.append(str(tag))
	event.id = "evt_%s_%s_%d" % [holder, type, int(tick)]
	store.witness_event(event, tick)
	return event


func _identity() -> NpcIdentity:
	return NpcIdentity.new(SEED)


# -- trap 1: a villager's own bank is nearly empty ---------------------------

func test_memories_are_read_from_all_three_banks_not_just_the_villagers_own():
	var memory_store := MemoryStore.new()
	_remember(memory_store, _npc_id(), "npc_settled", 10.0)
	_remember(memory_store, Household.for_founder(_npc_id()).id, "institution_formed", 20.0)
	_remember(memory_store, SETTLEMENT, "production_failed", 30.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"memory_store": memory_store,
		"settlement_id": SETTLEMENT,
	})

	var banks: Array = []
	for memory in frame["memories"]:
		banks.append(memory["bank"])
	assert_true(banks.has("npc"), "the villager's own bank must be read")
	assert_true(banks.has("household"), "the household bank must be read")
	assert_true(banks.has("settlement"), "the settlement bank must be read")


func test_the_household_bank_id_is_the_one_household_for_founder_actually_builds():
	var memory_store := MemoryStore.new()
	var real_household_id: String = Household.for_founder(_npc_id()).id
	_remember(memory_store, real_household_id, "institution_formed", 20.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {"memory_store": memory_store})

	assert_eq(frame["household_id"], real_household_id)
	assert_eq(frame["memories"].size(), 1, "the derived household bank id must actually hit")


# -- trap 2: .back() is first-formed order, not latest ------------------------

func test_memories_are_sorted_by_recorded_at_descending_not_by_when_they_were_formed():
	var memory_store := MemoryStore.new()
	# Formed newest FIRST, so first-formed order (what memories_for returns,
	# and therefore what .back() picks) is exactly backwards from latest.
	_remember(memory_store, _npc_id(), "newest", 300.0)
	_remember(memory_store, _npc_id(), "middle", 200.0)
	_remember(memory_store, _npc_id(), "oldest", 100.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {"memory_store": memory_store})

	var types: Array = []
	for memory in frame["memories"]:
		types.append(memory["event_type"])
	assert_eq(types, ["newest", "middle", "oldest"])


func test_the_memory_fan_out_is_capped_per_bank_and_it_is_the_oldest_that_falls_off():
	var memory_store := MemoryStore.new()
	var cap: int = DialogueContext.memories_per_bank()
	for i in cap + 3:
		_remember(memory_store, _npc_id(), "e%d" % i, float(i))

	var frame: Dictionary = DialogueContext.build(_npc_id(), {"memory_store": memory_store})

	assert_eq(frame["memories"].size(), cap)
	assert_eq(frame["memories"][0]["event_type"], "e%d" % (cap + 2), "newest survives")
	assert_eq(frame["memories"][cap - 1]["event_type"], "e3", "the three oldest fall off")
	assert_eq(frame["memory_count"], cap + 3, "the uncapped total is still reported")


func test_one_full_bank_cannot_crowd_the_other_two_out_of_the_frame():
	var memory_store := MemoryStore.new()
	# The settlement bank accumulates every status/production/tier event of a
	# whole village and is by far the busiest; a purely global cap would let
	# it evict this villager's own recollections entirely.
	for i in DialogueContext.memories_per_bank() * 3:
		_remember(memory_store, SETTLEMENT, "settlement_e%d" % i, 1000.0 + float(i))
	_remember(memory_store, _npc_id(), "npc_settled", 1.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"memory_store": memory_store,
		"settlement_id": SETTLEMENT,
	})

	var types: Array = []
	for memory in frame["memories"]:
		types.append(memory["event_type"])
	assert_true(types.has("npc_settled"), "the villager's own oldest memory must survive")


# -- one settlement step's news must not bury a villager's own life ----------
#
# The three helpers below reproduce the real burst rather than describing it:
# EarthChunkManager.record_settlement_founded_if_new founds a bank, and one
# EarthChunkManager.step_settlements pass floods it, all on a single tick
# (that pass reads one _world_age_seconds, so every memory it forms shares a
# recorded_at and no recency order exists WITHIN a burst at all).
#
# This is what DialogueContext.memories_per_bank has to clear. It is
# reproduced here rather than driven through a real EarthChunkManager
# because one update() of one costs ~60 seconds; the cost of reproducing it
# is that this and the emitter census in dialogue_context.gd have to be kept
# in step, which is exactly what
# test_the_derived_cap_clears_the_burst_this_file_actually_reproduces fails
# on when they drift.


## Founds a settlement the way EarthChunkManager.record_settlement_founded_
## if_new does: one `settlement_founded` the whole village witnesses, then
## one `npc_settled` per villager -- held FIRSTHAND by that villager (which
## is the `arrival` topic) and witnessed by the settlement (which is what
## puts a neighbour's arrival in the settlement bank, where
## DialogueTopic._neighbour_facts mostly finds one -- villager ids appear
## among an event's actors in very few places, and that module says so).
## Returns the villager ids in order; villagers[0] is the speaker.
func _found_settlement(events: EventStore, memories: MemoryStore, tick: float) -> Array[String]:
	var villagers: Array[String] = []
	for i in SettlementGenerator.POPULATION:
		villagers.append(EntityRef.for_npc(SEED + i))

	var founded := Event.new("settlement_founded", tick)
	founded.actors.append(SETTLEMENT)
	founded.importance = 0.2
	for villager in villagers:
		founded.witnesses.append(villager)
	events.append(founded)
	memories.witness_event(founded, tick)

	for villager in villagers:
		var settled := Event.new("npc_settled", tick)
		settled.actors.append(villager)
		settled.witnesses.append(SETTLEMENT)
		events.append(settled)
		memories.witness_event(settled, tick)
	return villagers


## One event recorded the way EarthChunkManager records one -- through a real
## EventStore (so ids are the real `evt_<ordinal>_<type>`, which is what the
## same-tick tie-break actually resolves on) and a real
## MemoryStore.witness_event.
func _step_event(
	events: EventStore,
	memories: MemoryStore,
	type: String,
	actors: Array,
	witnesses: Array,
	tick: float
) -> void:
	var event := Event.new(type, tick)
	for actor in actors:
		event.actors.append(str(actor))
	for witness in witnesses:
		event.witnesses.append(str(witness))
	events.append(event)
	memories.witness_event(event, tick)


## One full EarthChunkManager.step_settlements pass over this settlement, at
## its widest: production fires once per household, and every remaining
## emitter that pass can reach fires once. Mirrors, entry for entry,
## DialogueContext.STEP_ONCE_PER_SETTLEMENT_EMITTERS.
##
## Witnesses are set exactly as the real emitters set them: the settlement's
## own villagers (_villager_witnesses_of) for everything the village watched,
## and NONE for the three contract bookkeeping transitions, which
## _record_contract_event deliberately leaves unwitnessed -- so those three
## reach the two trading households' banks and no one else's.
func _run_one_settlement_step(
	events: EventStore, memories: MemoryStore, villagers: Array[String], tick: float
) -> void:
	var traders := [Household.for_founder(villagers[0]).id, Household.for_founder(villagers[1]).id]

	# _step_settlement_production: one attempt per household, and there is
	# exactly one household per villager (record_settlement_founded_if_new
	# forms one for each).
	for _household_index in villagers.size():
		_step_event(events, memories, "production_failed", [SETTLEMENT], villagers, tick)

	# _step_settlement_trade's propose -> accept -> activate -> outcome chain.
	for bookkeeping in ["contract_proposed", "contract_accepted", "contract_active"]:
		_step_event(events, memories, bookkeeping, traders, [], tick)
	_step_event(events, memories, "contract_fulfilled", traders, villagers, tick)
	_step_event(events, memories, "institution_formed", traders, villagers, tick)
	# _step_settlement_institution_health, and the ruin that dissolution
	# leaves behind (which inherits its cause's witnesses).
	_step_event(events, memories, "institution_dissolved", traders, villagers, tick)
	_step_event(events, memories, "ruin_formed", ["ruin:institution"], villagers, tick)
	# step_settlements' own status assessment, and the ruin a decline leaves.
	_step_event(events, memories, "settlement_declining", [SETTLEMENT], villagers, tick)
	_step_event(events, memories, "ruin_formed", ["ruin:settlement"], villagers, tick)
	# _step_settlement_classification.
	_step_event(events, memories, "settlement_became_town", [SETTLEMENT], villagers, tick)
	_step_event(events, memories, "settlement_specialized", [SETTLEMENT], villagers, tick)


func test_a_villager_can_still_say_where_they_came_from_after_a_full_settlement_step():
	var events := EventStore.new()
	var memories := MemoryStore.new()
	var villagers := _found_settlement(events, memories, 10.0)
	_run_one_settlement_step(events, memories, villagers, 40.0)

	var frame: Dictionary = DialogueContext.build(villagers[0], {
		"memory_store": memories,
		"event_store": events,
		"settlement_id": SETTLEMENT,
		"world_age_seconds": 40.0,
	})

	var arrival: Dictionary = DialogueTopic.facts_for(DialogueTopic.TOPIC_ARRIVAL, frame)
	assert_false(arrival.is_empty(), "one bad harvest must not cost a villager where they came from")
	assert_eq(str(arrival["top_memory"]["event_type"]), "npc_settled")
	assert_eq(str(arrival["top_memory"]["holder"]), villagers[0], "their OWN arrival, held firsthand")


func test_a_full_settlement_step_does_not_cost_the_settlement_bank_its_neighbours():
	# DialogueTopic._neighbour_facts needs a memory NAMING the neighbour, and
	# npc_settled is essentially the only event type that names a villager at
	# all -- one per villager, all recorded on the founding tick, all in the
	# settlement bank. They are the oldest thing in that bank and they are
	# never re-emitted, so a cap that clears the burst for the speaker's own
	# bank has to clear it here too or the village goes anonymous.
	var events := EventStore.new()
	var memories := MemoryStore.new()
	var villagers := _found_settlement(events, memories, 10.0)
	_run_one_settlement_step(events, memories, villagers, 40.0)

	var frame: Dictionary = DialogueContext.build(villagers[0], {
		"memory_store": memories,
		"event_store": events,
		"settlement_id": SETTLEMENT,
		"world_age_seconds": 40.0,
	})

	var named := {}
	for memory in frame["memories"]:
		if str(memory["event_type"]) != "npc_settled":
			continue
		for actor in memory["actors"]:
			named[str(actor)] = true
	for villager in villagers:
		assert_true(named.has(villager), "%s is no longer anyone this village remembers" % villager)


func test_the_derived_cap_clears_the_burst_this_file_actually_reproduces():
	# The cross-check between dialogue_context.gd's emitter census and the
	# step reproduced above: if either grows without the other, the cap stops
	# clearing the burst and this fails. It asserts the cap is BIG ENOUGH,
	# never that it is exactly right -- the module derives an upper bound over
	# all three banks on purpose (see memories_per_bank).
	var events := EventStore.new()
	var memories := MemoryStore.new()
	var villagers := _found_settlement(events, memories, 10.0)

	assert_eq(
		memories.memories_for(villagers[0]).size(),
		2,
		"a villager's bank is founded with their own arrival and the founding they watched"
	)
	assert_eq(
		memories.memories_for(SETTLEMENT).size(),
		SettlementGenerator.POPULATION + 1,
		"a settlement's own bank is founded with its founding and every villager's arrival"
	)

	_run_one_settlement_step(events, memories, villagers, 40.0)

	var cap: int = DialogueContext.memories_per_bank()
	assert_true(
		cap >= memories.memories_for(villagers[0]).size(),
		"the cap must clear a villager's founding plus one whole step's news"
	)
	assert_true(
		cap >= memories.memories_for(SETTLEMENT).size(),
		"and the settlement bank's, which is founded wider and floods alongside it"
	)
	assert_true(
		cap >= memories.memories_for(Household.for_founder(villagers[0]).id).size(),
		"and the household bank's, which takes the whole contract chain"
	)


func test_the_same_event_held_in_two_banks_is_carried_once_as_the_villagers_own_copy():
	var memory_store := MemoryStore.new()
	var event := Event.new("settlement_growing", 50.0)
	event.actors.append(SETTLEMENT)
	event.witnesses.append(_npc_id())
	event.id = "evt_0_settlement_growing"
	memory_store.witness_event(event, 50.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"memory_store": memory_store,
		"settlement_id": SETTLEMENT,
	})

	assert_eq(frame["memories"].size(), 1)
	assert_eq(frame["memories"][0]["bank"], "npc", "what the villager believes wins")
	assert_eq(frame["memories"][0]["source_type"], MemoryRecord.WITNESSED)


# -- trap 3: the world clock, never NpcMarker's private per-marker one --------

func test_memory_age_is_measured_against_the_world_clock():
	var memory_store := MemoryStore.new()
	_remember(memory_store, _npc_id(), "npc_settled", 120.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"memory_store": memory_store,
		"world_age_seconds": 500.0,
	})

	assert_almost_eq(frame["memories"][0]["age_seconds"], 380.0, 0.001)
	assert_almost_eq(frame["world_age_seconds"], 500.0, 0.001)


func test_hour_of_day_comes_from_the_world_clock_and_its_real_day_length():
	# Three quarters through a simulated day is hour 18 -- evening.
	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"world_age_seconds": 60.0 * 10.0 + 45.0,
		"seconds_per_simulated_day": 60.0,
	})

	assert_eq(frame["hour_of_day"], 18)
	assert_eq(frame["time_block"], NpcSchedule.time_block_for_hour(18))


func test_the_hour_is_unknown_rather_than_invented_when_no_day_length_is_supplied():
	# The day length lives only on two Node scripts (EarthChunkManager and
	# NpcMarker), which a pure module must not preload -- so an unsupplied
	# clock reads as absent, never as a guessed default hour.
	var frame: Dictionary = DialogueContext.build(_npc_id(), {"world_age_seconds": 500.0})

	assert_eq(frame["hour_of_day"], DialogueContext.HOUR_UNKNOWN)
	assert_eq(frame["time_block"], "")


# -- trap 4: remembered_location is Vector2.ZERO everywhere -------------------

func test_where_is_reconstructed_from_entity_ids_not_from_remembered_location():
	var memory_store := MemoryStore.new()
	var event := _remember(memory_store, SETTLEMENT, "production_failed", 10.0)
	assert_eq(event.location, Vector2.ZERO, "every real emitter uses the 2-arg constructor")

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"memory_store": memory_store,
		"settlement_id": SETTLEMENT,
	})

	assert_eq(frame["memories"][0]["place_settlement_id"], SETTLEMENT)


func test_a_memory_naming_another_settlement_is_placed_there_not_here():
	var memory_store := MemoryStore.new()
	var far_away := "settlement:9_9"
	var event := Event.new("regional_trade_raided", 10.0)
	event.actors.append(far_away)
	event.witnesses.append(_npc_id())
	event.id = "evt_0_regional_trade_raided"
	memory_store.witness_event(event, 10.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"memory_store": memory_store,
		"settlement_id": SETTLEMENT,
	})

	assert_eq(frame["memories"][0]["place_settlement_id"], far_away)


# -- trap 5: dead fields are not carried -------------------------------------

func test_the_frame_carries_none_of_the_four_fields_nothing_in_src_ever_writes():
	var memory_store := MemoryStore.new()
	_remember(memory_store, _npc_id(), "npc_settled", 10.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {"memory_store": memory_store})

	for dead_key in ["remembered_outcome", "emotional_salience", "visibility", "evidence"]:
		assert_false(frame.has(dead_key), "%s is dead in src/ -- do not build on it" % dead_key)
		assert_false(
			frame["memories"][0].has(dead_key),
			"%s is dead in src/ -- do not build on it" % dead_key
		)


func test_the_two_event_fields_that_ARE_written_come_off_the_authoritative_event():
	# tags and importance are the counterexamples to the four dead fields
	# above: real emitters really write them (tags carries the recipe id,
	# which is the only place the noun in "he's short three rock" exists).
	# MemoryRecord copies neither, so both come off the ground-truth Event.
	var memory_store := MemoryStore.new()
	var event_store := EventStore.new()
	var event := Event.new("production_failed", 10.0)
	event.actors.append(_npc_id())
	event.tags.append("stone_pickaxe")
	event.importance = 0.3
	event_store.append(event)
	memory_store.witness_event(event, 10.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"memory_store": memory_store,
		"event_store": event_store,
	})

	assert_eq(frame["memories"][0]["tags"], ["stone_pickaxe"])
	assert_almost_eq(frame["memories"][0]["importance"], 0.3, 0.0001)


func test_a_memory_whose_ground_truth_event_is_unreachable_still_carries_the_belief():
	# EventStore and MemoryStore are separately persisted, and a caller may
	# hand over one and not the other -- the belief is still real, it simply
	# has no ground truth attached, so tags read empty rather than crashing.
	var memory_store := MemoryStore.new()
	_remember(memory_store, _npc_id(), "npc_settled", 10.0, ["ignored"])

	var frame: Dictionary = DialogueContext.build(_npc_id(), {"memory_store": memory_store})

	assert_eq(frame["memories"][0]["tags"], [])
	assert_almost_eq(frame["memories"][0]["importance"], 0.0, 0.0001)
	assert_eq(frame["memories"][0]["event_type"], "npc_settled")


# -- the frame contract ------------------------------------------------------

func test_the_frame_is_flat_and_holds_no_object_references():
	var memory_store := MemoryStore.new()
	_remember(memory_store, _npc_id(), "npc_settled", 10.0)
	var village_market := VillageMarket.new()
	village_market.add_stock("fruit", 20.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), _full_sources(memory_store, village_market))

	assert_true(_is_object_free(frame), "a frame must be hashable: no Object may survive into it")


func test_every_documented_field_is_present_even_when_nothing_is_supplied():
	var frame: Dictionary = DialogueContext.build(_npc_id(), {})

	for field in DialogueContext.FRAME_FIELDS:
		assert_true(frame.has(field), "frame is missing documented field '%s'" % field)
	assert_eq(frame.size(), DialogueContext.FRAME_FIELDS.size(), "frame carries an undocumented field")


func test_an_empty_world_yields_empty_topics_rather_than_invented_ones():
	var frame: Dictionary = DialogueContext.build(_npc_id(), {})

	assert_eq(frame["memories"], [])
	assert_eq(frame["shortfall_missing"], [])
	assert_eq(frame["neighbours"], [])
	assert_eq(frame["settlement_status"], "", "no settlement means no status, not 'stable'")
	assert_eq(frame["season"], "")
	assert_eq(frame["weather"], "")


# -- identity and voice inputs -----------------------------------------------

func test_identity_and_all_eight_genes_reach_the_frame():
	var identity := _identity()

	var frame: Dictionary = DialogueContext.build(_npc_id(), {"identity": identity})

	assert_eq(frame["npc_id"], _npc_id())
	assert_eq(frame["seed_value"], SEED)
	assert_eq(frame["npc_name"], identity.npc_name)
	assert_eq(frame["occupation"], identity.occupation)
	assert_eq(frame["personality_trait"], identity.personality_trait)
	assert_eq(frame["need"], identity.need)
	assert_eq(frame["work_location"], NpcIdentity.WORK_LOCATION_BY_OCCUPATION[identity.occupation])
	assert_eq(
		frame["traits"].size(),
		NpcIdentity.PERSONALITY_TRAITS.size(),
		"NpcVoice bands all eight genes, not just the argmax"
	)
	for trait_name in NpcIdentity.PERSONALITY_TRAITS:
		assert_almost_eq(float(frame["traits"][trait_name]), float(identity.genome.traits[trait_name]), 0.0001)


# -- economy -----------------------------------------------------------------

func test_hunger_wallet_and_affordability_come_off_the_real_economy():
	var village_market := VillageMarket.new()
	village_market.add_stock("fruit", 5.0)
	var economy := NpcEconomy.new(SEED, "guard", village_market)
	economy.needs.hunger = 0.9
	economy.wallet.add(VillageWages.subsistence_wage())

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"economy": economy,
		"village_market": village_market,
	})

	assert_almost_eq(frame["hunger"], 0.9, 0.0001)
	assert_true(frame["is_hungry"])
	assert_eq(frame["wallet_gold"], VillageWages.subsistence_wage())
	assert_eq(frame["meal_price"], VillageWages.subsistence_wage())
	assert_true(frame["can_afford_meal"])
	assert_true(frame["meal_available"])


func test_a_broke_villager_in_a_stocked_village_cannot_afford_the_meal_that_is_there():
	var village_market := VillageMarket.new()
	village_market.add_stock("fruit", 5.0)
	var economy := NpcEconomy.new(SEED, "guard", village_market)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"economy": economy,
		"village_market": village_market,
	})

	assert_eq(frame["wallet_gold"], 0)
	assert_false(frame["can_afford_meal"])
	assert_true(frame["meal_available"], "the food is there -- it is the gold that is missing")


func test_the_village_purse_and_whether_it_can_still_pay_a_wage_reach_the_frame():
	var village_market := VillageMarket.new()
	var economy := NpcEconomy.new(SEED, "guard", village_market)
	village_market.set_meta(NpcEconomy.PURSE_META, float(VillageWages.subsistence_wage()))

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"economy": economy,
		"village_market": village_market,
	})

	assert_almost_eq(frame["village_purse_gold"], float(VillageWages.subsistence_wage()), 0.0001)
	assert_true(frame["village_can_pay_wage"])


func test_a_producer_carries_the_real_item_their_occupation_gathers():
	var frame: Dictionary = DialogueContext.build(EntityRef.for_npc(1), {
		"identity": _fake_identity(1, "hunter"),
	})

	assert_true(frame["is_producer"])
	assert_eq(frame["produces_item_id"], "meat")


func test_a_non_producer_names_no_gathered_item_rather_than_a_placeholder():
	var frame: Dictionary = DialogueContext.build(EntityRef.for_npc(1), {
		"identity": _fake_identity(1, "guard"),
	})

	assert_false(frame["is_producer"])
	assert_eq(frame["produces_item_id"], "")


# -- the household's production shortfall ------------------------------------

func test_a_villager_with_no_shortfall_carries_an_empty_list_not_a_filler_ask():
	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"identity": _fake_identity(SEED, "blacksmith"),
		"shortfalls": [],
	})

	assert_eq(frame["shortfall_missing"], [])
	assert_eq(frame["household_recipe_id"], "stone_pickaxe", "the recipe is real even with nothing missing")


func test_only_this_villagers_own_households_shortfall_is_attributed_to_them():
	var mine: String = Household.for_founder(_npc_id()).id
	var someone_else: String = Household.for_founder(EntityRef.for_npc(SEED + 1)).id

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"shortfalls": [
			{"household_id": someone_else, "recipe_id": "map", "missing": [{"item_id": "stick", "need": 9}]},
			{"household_id": mine, "recipe_id": "stone_pickaxe", "missing": [{"item_id": "rock", "need": 3}]},
		],
	})

	assert_eq(frame["shortfall_missing"], [{"item_id": "rock", "need": 3}])


func test_what_the_player_carries_is_matched_against_the_shortfall():
	var catalog := ItemCatalog.new()
	var inventory := Inventory.new(8)
	inventory.add(catalog.make("rock"), 5)
	var mine: String = Household.for_founder(_npc_id()).id

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"player_inventory": inventory,
		"shortfalls": [
			{"household_id": mine, "recipe_id": "stone_pickaxe", "missing": [{"item_id": "rock", "need": 3}]},
		],
	})

	assert_eq(frame["player_carrying"], {"rock": 5})
	assert_eq(frame["shortfall_items_player_has"], ["rock"])
	assert_true(frame["shortfall_covered_by_player"])


func test_carrying_some_but_not_enough_is_not_covered():
	var catalog := ItemCatalog.new()
	var inventory := Inventory.new(8)
	inventory.add(catalog.make("rock"), 1)
	var mine: String = Household.for_founder(_npc_id()).id

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"player_inventory": inventory,
		"shortfalls": [
			{"household_id": mine, "recipe_id": "stone_pickaxe", "missing": [{"item_id": "rock", "need": 3}]},
		],
	})

	assert_eq(frame["shortfall_items_player_has"], ["rock"])
	assert_false(frame["shortfall_covered_by_player"])


# -- the settlement ----------------------------------------------------------

func test_settlement_food_sums_both_of_the_two_things_called_the_market():
	var market := Market.new()
	market.add_stock("meat", 2)
	var village_market := VillageMarket.new()
	village_market.add_stock("fruit", 20.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"settlement_id": SETTLEMENT,
		"market": market,
		"village_market": village_market,
		"household_count": 2,
	})

	assert_eq(frame["settlement_food_stock"], 22)
	assert_eq(frame["settlement_capacity"], int(22 / float(SettlementState.FOOD_PER_HOUSEHOLD)))
	assert_eq(frame["settlement_status"], SettlementState.GROWING, "a fed village can finally grow")
	assert_eq(frame["settlement_household_count"], 2)


func test_settlement_tier_and_specialization_are_derived_from_real_flows():
	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"settlement_id": SETTLEMENT,
		"household_count": SettlementTier.TOWN_HOUSEHOLDS,
		"active_institutions": SettlementTier.TOWN_INSTITUTIONS,
		"production_counts": {"cooked_meat": 4},
	})

	assert_eq(frame["settlement_tier"], SettlementTier.TOWN)
	assert_eq(frame["settlement_specialization"], "hunting center")
	assert_eq(frame["settlement_production_diversity"], 1)


func test_a_villager_with_no_settlement_gets_empty_settlement_facts():
	var frame: Dictionary = DialogueContext.build(_npc_id(), {"household_count": 3})

	assert_eq(frame["settlement_id"], "")
	assert_eq(frame["settlement_status"], "")
	assert_eq(frame["settlement_tier"], "")
	assert_eq(frame["settlement_food_stock"], 0)


func test_the_settlement_is_recovered_from_the_npc_settled_event_when_not_supplied():
	# EarthChunkManager._settlement_of_party reconstructs it exactly this way:
	# an npc's own npc_settled event names its settlement as the witness.
	var event_store := EventStore.new()
	var settled := Event.new("npc_settled", 1.0)
	settled.actors.append(_npc_id())
	settled.witnesses.append(SETTLEMENT)
	event_store.append(settled)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {"event_store": event_store})

	assert_eq(frame["settlement_id"], SETTLEMENT)


# -- who else is standing here -----------------------------------------------

func test_co_present_neighbours_are_flattened_and_never_include_the_speaker():
	var neighbour := NpcIdentity.new(SEED + 1)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"identity": _identity(),
		"co_present_identities": [_identity(), neighbour],
	})

	assert_eq(frame["neighbours"].size(), 1)
	assert_eq(frame["neighbours"][0], {
		"npc_id": EntityRef.for_npc(SEED + 1),
		"name": neighbour.npc_name,
		"occupation": neighbour.occupation,
	})


func test_a_neighbours_belief_is_carried_only_for_an_event_this_villager_also_holds():
	var memory_store := MemoryStore.new()
	var neighbour_id := EntityRef.for_npc(SEED + 1)

	var shared := Event.new("settlement_declining", 10.0)
	shared.actors.append(SETTLEMENT)
	shared.witnesses.append(_npc_id())
	shared.id = "evt_0_settlement_declining"
	memory_store.witness_event(shared, 10.0)
	memory_store.transmit(_npc_id(), neighbour_id, shared.id, 20.0)

	var theirs_alone := Event.new("ruin_formed", 30.0)
	theirs_alone.actors.append(neighbour_id)
	theirs_alone.id = "evt_1_ruin_formed"
	memory_store.witness_event(theirs_alone, 30.0)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"memory_store": memory_store,
		"co_present_identities": [NpcIdentity.new(SEED + 1)],
	})

	assert_eq(frame["neighbour_beliefs"].size(), 1, "only the event they can actually disagree about")
	var belief: Dictionary = frame["neighbour_beliefs"][0]
	assert_eq(belief["npc_id"], neighbour_id)
	assert_eq(belief["event_id"], shared.id)
	assert_eq(
		belief["source_type"],
		MemoryRecord.TRUSTED_TESTIMONY,
		"one hop off a witnessed account -- a real disagreement to surface"
	)


# -- the world right now, and the player -------------------------------------

func test_season_weather_and_snow_reach_the_frame_verbatim():
	var frame: Dictionary = DialogueContext.build(_npc_id(), {
		"season": "winter",
		"weather": "storm",
		"snow_depth": 0.75,
	})

	assert_eq(frame["season"], "winter")
	assert_eq(frame["weather"], "storm")
	assert_almost_eq(frame["snow_depth"], 0.75, 0.0001)


func test_the_players_gold_and_identity_reach_the_frame():
	var wallet := Wallet.new()
	wallet.add(12)

	var frame: Dictionary = DialogueContext.build(_npc_id(), {"player_wallet": wallet})

	assert_eq(frame["player_gold"], 12)
	assert_eq(frame["player_id"], "player:local")


# -- helpers -----------------------------------------------------------------


## An identity double for the cases that need a SPECIFIC occupation -- a real
## NpcIdentity rolls its occupation from its seed, so pinning one would mean
## seed-hunting a test to whichever occupation the generator happens to give.
class FakeIdentity extends RefCounted:
	var seed_value: int
	var npc_name := "Testperson"
	var occupation: String
	var personality_trait := "stoic"
	var need := "wants_news_from_afar"
	var genome

	func _init(a_seed: int, an_occupation: String) -> void:
		seed_value = a_seed
		occupation = an_occupation
		genome = preload("res://src/world/npc_genome.gd").new(
			a_seed, preload("res://src/world/npc_identity.gd").PERSONALITY_TRAITS
		)


func _fake_identity(a_seed: int, an_occupation: String) -> FakeIdentity:
	return FakeIdentity.new(a_seed, an_occupation)


func _full_sources(memory_store: MemoryStore, village_market: VillageMarket) -> Dictionary:
	return {
		"identity": _identity(),
		"economy": NpcEconomy.new(SEED, "guard", village_market),
		"memory_store": memory_store,
		"settlement_id": SETTLEMENT,
		"village_market": village_market,
		"market": Market.new(),
		"household_count": 2,
		"active_institutions": 1,
		"production_counts": {"cooked_meat": 3},
		"co_present_identities": [NpcIdentity.new(SEED + 1)],
		"season": "autumn",
		"weather": "rain",
		"snow_depth": 0.0,
		"world_age_seconds": 900.0,
		"seconds_per_simulated_day": 60.0,
		"player_inventory": Inventory.new(8),
		"player_wallet": Wallet.new(),
		"shortfalls": [],
	}


## Recursively verifies nothing in the frame is an Object -- the property
## that makes it hashable, cacheable and safe to hand to a renderer that must
## not be able to reach back into the simulation.
func _is_object_free(value) -> bool:
	match typeof(value):
		TYPE_OBJECT:
			return false
		TYPE_DICTIONARY:
			for key in value:
				if not _is_object_free(key) or not _is_object_free(value[key]):
					return false
			return true
		TYPE_ARRAY:
			for entry in value:
				if not _is_object_free(entry):
					return false
			return true
		_:
			return true
