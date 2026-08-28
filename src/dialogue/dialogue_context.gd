extends RefCounted

## The ONE place the conversation system reads the world (see
## docs/concept/dialogue.md's pipeline: `world state -> DialogueContext.build
## -> frame`). Everything downstream -- NpcVoice, DialogueTopic,
## DialogueMove, DialogueBeat, OfflineRenderer -- reads the frame and nothing
## else, so exactly one module has to know how this simulation stores its
## facts, and a topic can never accidentally reach back into a live store.
##
## Shaped after FieldJournal.entry_for(entity_id, stores): one entity id in,
## one bag of explicit dependencies in, everything known about that entity
## out. Where FieldJournal renders prose for a player to read, this renders a
## FRAME -- a flat Dictionary of plain values, no Object anywhere in it.
## Flatness is not tidiness: a frame with no object references is hashable
## and cacheable (dialogue.md's cache key is `(voice_key, topic_id, kind,
## fact_band)`, deliberately not the NPC), and it is the boundary that makes
## the documented AI seam safe -- there is no path from anything holding a
## frame back to a wallet, a contract or a store.
##
## Every source is optional and every absence is an ordinary state rather
## than an error, the same fail-open shape SettlementFood.village_market_for
## and NpcProduction.yield_per_second already use: a settlement whose chunk
## is unloaded has no live VillageMarket, a villager standing alone has no
## neighbours, a fresh world has no memories. An absent fact reaches the
## frame EMPTY, and dialogue.md's second design pillar is that an empty fact
## means the topic is omitted -- never a fallback line. Nothing here
## substitutes a plausible-looking default for a fact it could not read,
## because a topic that is always empty is a substrate bug this frame exists
## to surface.
##
## -- Five things that are deliberately NOT done here, each a real trap --
##
## 1. Memories are read from ALL THREE banks, not just `npc:<seed>`. A
##    villager's own bank holds barely anything: of the emitters in
##    EarthChunkManager, most name a SETTLEMENT or a HOUSEHOLD as the actor
##    and reach a villager only as a witness. The household bank id needs no
##    store to find -- Household.for_founder builds it as
##    `household:<key of the founder's own ref>`, so it is pure string math
##    off the npc id (see household_bank_for).
## 2. Memories are sorted by `recorded_at` DESCENDING. MemoryStore.
##    memories_for returns FIRST-FORMED order, so `.back()` -- which is what
##    EarthChunkManager._exchange_recent_memories uses to mean "the latest"
##    -- is only the latest when nothing has ever been retold; a memory heard
##    second-hand today was formed long after one witnessed yesterday.
## 3. Time comes from the WORLD clock. NpcMarker keeps a private
##    `_current_hour_of_day` counting elapsed real seconds since that marker
##    happened to spawn, never synced across markers (see EarthChunkManager.
##    _current_hour_of_day's own doc comment for why grouping needs the
##    shared one). Two villagers standing next to each other disagree about
##    the hour under the private clock.
## 4. `remembered_location` is never read. All 18 `Event.new` sites in src/
##    call the two-argument constructor, so every event's `location` -- and
##    therefore every memory's `remembered_location` -- is Vector2.ZERO. A
##    "where" built from it would say the origin of the world about
##    everything. "Where" is reconstructed from the entity ids a memory
##    actually names instead (see _place_of), at settlement granularity,
##    which is the granularity a sentence wants anyway.
## 5. `remembered_outcome`, `emotional_salience`, `Event.visibility` and
##    `Event.evidence` are not carried. Nothing in src/ writes any of the
##    four -- they exist only as their own `from_dict` defaults -- so a
##    topic scored on them would be scored on a constant. `Event.tags` and
##    `Event.importance`, by contrast, ARE really written (tags carry the
##    recipe/species/item id, which is the only place the specific noun in
##    "he's short three rock" exists at all), so tags are carried and the
##    dead four are not. `importance` is only partly written -- 5 of the 18
##    emitters set it -- which is stated where it is read rather than
##    smoothed over (see _memory_entry).
##
## -- What is derived here, and what is passed in --
##
## The split is not arbitrary. A number the substrate has already DECIDED is
## passed in, because re-deriving it here would produce a second, disagreeing
## answer to a question already answered. A number nothing exposes is derived
## here from the real modules that define it, never re-tuned or re-copied:
## `settlement_food_stock`/`settlement_capacity` through SettlementFood (the
## only thing that sums BOTH markets), `settlement_status` through
## SettlementState.status_for, `settlement_tier`/`settlement_specialization`
## through SettlementTier, `meal_price` through VillageWages.subsistence_wage
## (which is anchored to VillageMarket's own live price, so the two can never
## drift), `household_recipe_id` through OccupationProduction.
##
## One honest divergence: `settlement_status` here is the LIVE
## classification, with none of EarthChunkManager's dwell hysteresis. That
## hysteresis exists to stop the event LOG flickering, not to stop a villager
## noticing what is in front of them -- and the announced, dwelled label is
## already in the frame anyway, as whatever `settlement_growing`/
## `settlement_declining` memories the banks hold.
##
## Pure static module -- arguments in, values out, no Node, no scene, no
## store of its own. Same shape as SettlementFood, VillageWages and
## OccupationProduction.

const EntityRef = preload("res://src/emergence/entity_ref.gd")
const OccupationProduction = preload("res://src/emergence/occupation_production.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const SettlementFood = preload("res://src/emergence/settlement_food.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")
## Preloaded for ONE constant, POPULATION -- the villager count every
## settlement in this world is actually built with, and therefore the number
## the memory burst below scales with. A RefCounted like every other preload
## here; nothing about a Node is reached.
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const VillageWages = preload("res://src/world/village_wages.gd")

## The three memory banks a villager's news actually lives in, in the order
## a duplicate is resolved: their OWN recollection of an event wins over the
## household's and the village's record of the same one, because the frame
## describes what this person believes, not what is true (see
## docs/emergence/02-history-memory-rumors.md's fact-versus-belief split).
const NPC_BANK := "npc"
const HOUSEHOLD_BANK := "household"
const SETTLEMENT_BANK := "settlement"
const BANK_KINDS: Array[String] = [NPC_BANK, HOUSEHOLD_BANK, SETTLEMENT_BANK]

## Every emitter one EarthChunkManager.step_settlements pass can reach that
## records AT MOST ONE memory per settlement per step. A census of that
## pass, one entry per emitter, so the count below is read off the substrate
## rather than guessed at -- the same shape (and the same reason)
## DialogueTopic's MEMORY_TOPIC_EVENT_TYPES uses: a number that is a list's
## length cannot quietly drift away from the list.
##
## Production is deliberately NOT in here. It is the one part of the pass
## that scales, and widest_step_burst adds it separately.
const STEP_ONCE_PER_SETTLEMENT_EMITTERS: Array[String] = [
	# _step_settlement_trade drives the whole propose -> accept -> activate
	# -> fulfil/breach chain inside a SINGLE step. Only the outcome is
	# witnessed by the village (_record_contract_event's own bound), but all
	# four are held firsthand by the two trading households, so all four
	# really do land in a bank.
	"contract_proposed",
	"contract_accepted",
	"contract_active",
	"contract_fulfilled | contract_breached",
	# _step_settlement_trade again (attempt_institution_formation), then
	# _step_settlement_institution_health, and the ruin a dissolution leaves
	# behind (record_ruin_from_dissolved_institution).
	"institution_formed",
	"institution_dissolved",
	"ruin_formed (from the dissolved institution)",
	# step_settlements' own status assessment, and the ruin a decline leaves
	# behind (record_ruin_from_settlement_decline).
	"settlement_growing | settlement_stable | settlement_declining",
	"ruin_formed (from the settlement's decline)",
	# _step_settlement_classification, both halves.
	"settlement_became_hamlet | settlement_became_town | settlement_became_city",
	"settlement_specialized",
]


## The most memories one EarthChunkManager.step_settlements pass can add to
## a single bank.
##
## PRODUCTION is the only part of that pass that scales, and it scales with
## HOUSEHOLDS: _step_settlement_production runs one attempt_production per
## household, record_settlement_founded_if_new forms exactly one household
## per villager, and SettlementGenerator builds POPULATION villagers per
## settlement. The settlement|recipe news guard cannot fold two of those
## attempts into one event either, because OccupationProduction's eight
## recipes are distinct by that module's own systemic constraint -- so it
## really is one event per household, and a village's first step therefore
## emits five production_failed records at once.
##
## An upper bound over all three banks rather than a per-bank table: no
## single bank takes every entry of the census (a household bank never sees
## production, the settlement bank never sees the contract chain), so this
## over-provisions on purpose. The costs are not symmetric -- a cap one slot
## too small silently deletes a villager's biography, a cap a few slots too
## large costs a handful of Dictionary entries in a frame built once per
## conversation.
##
## Two honest limits. This is the burst of ONE step over ONE settlement:
## step_regional_trade runs on the same 30-second beat and stamps its
## caravan events with the same _world_age_seconds, so its memories join the
## same indistinguishable instant -- they are not counted here because no
## caravan can currently depart at all (nothing ever stocks an emergence
## Market, so no supplier ever has surplus), which is a substrate gap rather
## than a licence. And POPULATION is what the world GENERATOR builds; a
## settlement assembled by hand with more households than that takes a
## proportionally wider production burst than this clears.
static func widest_step_burst() -> int:
	return SettlementGenerator.POPULATION + STEP_ONCE_PER_SETTLEMENT_EMITTERS.size()


## The most memories a bank is FOUNDED with, before any step has run.
##
## record_settlement_founded_if_new emits one `settlement_founded` the whole
## village witnesses and one `npc_settled` per villager, so the SETTLEMENT's
## own bank -- the widest of the three -- holds the founding it acted in
## plus every villager's arrival it witnessed. A villager's own bank is
## founded with two (their arrival firsthand, the founding they watched); a
## household bank with none.
##
## These are the memories the cap exists to protect, and they are protected
## by SIZE rather than by any rule of their own because of what they are:
## emitted once per village ever, never re-emitted, so they only get older.
## Recency can never carry them back up once a burst has pushed them out.
static func widest_founding() -> int:
	return SettlementGenerator.POPULATION + 1


## How many of each bank's most recent memories reach the frame: one whole
## step's news, with everything that bank was founded with still underneath
## it.
##
## PER BANK rather than one global number, and that part has a real reason
## behind it: the settlement bank takes every production, status, tier and
## trade event of a whole village, while a villager's own bank holds a
## handful, so a single global cap would let the settlement's backlog evict
## this person's own recollections entirely and every villager in the
## village would then have the same news. Per-bank, no bank can crowd out
## another.
##
## -- Why this is derived and no longer a round number --
##
## It used to be a flat 4, and this module's own comment admitted "which
## small number delivers that is not a question the simulation can answer."
## The simulation answered it. One step_settlements pass forms 13 memories
## in a villager's own bank and 8 in the settlement's, every one of them
## newer than anything the village was FOUNDED with, so the founding
## memories -- this villager's own `npc_settled`, the `settlement_founded`
## they watched, and every neighbour's arrival in the settlement bank --
## were pushed out thirty seconds into every village's life and never came
## back, because none of the three is ever emitted a second time.
##
## What that cost, measured against one reproduced pass (see
## test_the_derived_cap_clears_the_burst_this_file_actually_reproduces):
## the `arrival` topic went empty, and not one of the village's five
## villagers was named by any memory still in the frame, which takes
## `neighbour` with it. A villager could not tell you where they came from
## and could not name the person standing next to them.
##
## Note what a too-small cap actually kept, which is not "the latest news".
## One pass reads a single _world_age_seconds, so every memory it forms
## shares one recorded_at and there is no recency order WITHIN a burst at
## all -- _record_is_newer falls through to its event-id tie-break and the
## survivors are an alphabetical slice of one instant. That is the second
## reason the cap has to clear the WHOLE burst rather than merely be bigger
## than it was.
##
## -- Why it is still a flat newest-N, and what was rejected --
##
## 1. NEWEST-PER-EVENT-TYPE (one slot per kind of news) is the tempting one:
##    it would collapse a step's five identical production_failed records
##    into a single slot and cost little downstream, since
##    DialogueTopic._memory_facts already reduces each topic to a single
##    `top_memory`. It would also silently kill the `neighbour` topic.
##    _neighbour_facts needs a memory NAMING the neighbour, and `npc_settled`
##    is essentially the only event type that names a villager at all -- the
##    settlement bank holds one per villager, all the same type, all on the
##    same founding tick, so a one-slot-per-type rule keeps exactly one of
##    them and the other four villagers become people this village has never
##    heard of.
## 2. A HIGHEST-CONFIDENCE RESERVE would have to tell a villager's biography
##    apart from the day's news on that axis, and it cannot: every actor's
##    memory is formed at the confidence ceiling, so in the settlement bank
##    the step's production events (the settlement is their actor) sit at
##    exactly the strength of the founding it also acted in. That reserve
##    would reserve the flood.
## 3. RESERVING THE OLDEST would work -- a bank's founding is by
##    construction its oldest content -- and it is the honest fallback if
##    this shape ever stops holding. It is not needed yet, and the reason is
##    worth stating because it is exactly what a future change could break:
##    every settlement-level emitter in the pass is change-guarded (a
##    repeated production failure, an unchanged status, tier, specialization
##    or trade outcome all record nothing), so a village in steady state
##    adds nothing to any bank and the founding is never pushed again. An
##    UNGUARDED emitter would make the burst recur and this flat shape would
##    be the thing that fails.
##
## What a cap has to buy in the first place is unchanged: frame-building
## stays O(1) in world age instead of O(events ever recorded).
static func memories_per_bank() -> int:
	return widest_step_burst() + widest_founding()

## `hour_of_day` when the caller supplied no day length to read the world
## clock against -- an unknown hour, never a guessed one. The 60-second
## simulated day lives only on two Node scripts (EarthChunkManager and
## NpcMarker share the constant deliberately), and a pure module must not
## preload a Node script to reach it, so the caller passes it in. An unknown
## hour leaves `time_block` empty, and pillar 2 then omits any topic that
## needed to know the time rather than greeting you with an invented morning.
const HOUR_UNKNOWN := -1

## Every field of the frame, in build order. Exists as an explicit contract
## for the same reason dialogue.md writes the Beat out as one: it is what the
## next module in the pipeline builds against, so a field silently appearing
## or vanishing is a test failure rather than a surprise downstream.
const FRAME_FIELDS: Array[String] = [
	# who this is, and what NpcVoice bands them by
	"npc_id", "seed_value", "npc_name", "occupation", "personality_trait",
	"need", "work_location", "traits", "household_id", "settlement_id",
	# what their day costs them
	"hunger", "is_hungry", "wallet_gold", "meal_price", "can_afford_meal",
	"meal_available", "village_purse_gold", "village_can_pay_wage",
	"is_producer", "produces_item_id",
	# what their household cannot make
	"household_recipe_id", "shortfall_missing", "shortfall_items_player_has",
	"shortfall_covered_by_player",
	# what their village is
	"settlement_food_stock", "settlement_capacity", "settlement_household_count",
	"settlement_status", "settlement_tier", "settlement_specialization",
	"settlement_production_diversity",
	# what they know, and who else is standing here
	"memories", "memory_count", "memory_banks", "neighbours", "neighbour_beliefs",
	# the world around the conversation
	"season", "weather", "snow_depth", "world_age_seconds", "hour_of_day", "time_block",
	# and the person they are talking to
	"player_id", "player_carrying", "player_gold",
]


## Everything the conversation system may know about `npc_id`, as one flat
## frame. `sources` is the explicit dependency bag -- see the module doc
## comment for the derived/passed-in split, and FRAME_FIELDS for the output
## contract. Recognised keys, all optional:
##
##   identity                    NpcIdentity (duck-typed: seed_value,
##                               npc_name, occupation, personality_trait,
##                               need, genome.traits)
##   economy                     NpcEconomy (needs, wallet, market)
##   memory_store                MemoryStore -- all three banks are read
##   event_store                 EventStore -- ground truth for Event.tags,
##                               and the fallback settlement lookup
##   settlement_id               String; recovered from event_store if absent
##   market / village_market     the two unrelated things called "the market"
##                               (see SettlementFood); village_market falls
##                               back to economy.market
##   item_catalog                ItemCatalog; one is made if absent
##   household_count             int, EarthChunkManager.
##                               household_count_for_settlement
##   active_institutions         int, active_institution_count_for_settlement
##   production_counts           Dictionary, production_counts_for_settlement
##   shortfalls                  Array, production_shortfall_quests_for_
##                               settlement's own shape, unfiltered
##   co_present_identities       Array of NpcIdentity standing here now
##   season / weather            String, snow_depth float
##   world_age_seconds           float, the SHARED world clock
##   seconds_per_simulated_day   float; without it the hour is HOUR_UNKNOWN
##   player_inventory            Inventory (duck-typed: stacks())
##   player_wallet               Wallet (duck-typed: balance)
##   player_id                   String, defaults to PlayerIdentity's
static func build(npc_id: String, sources: Dictionary) -> Dictionary:
	var identity = sources.get("identity")
	var economy = sources.get("economy")
	var memory_store = sources.get("memory_store")
	var event_store = sources.get("event_store")

	var occupation := _string_property(identity, "occupation")
	var household_id := household_bank_for(npc_id)
	var settlement_id := _settlement_id(npc_id, sources)

	var village_market = sources.get("village_market")
	if village_market == null:
		village_market = _property(economy, "market")
	var catalog = sources.get("item_catalog")
	if catalog == null:
		catalog = ItemCatalog.new()

	var world_age := float(sources.get("world_age_seconds", 0.0))
	var hour := hour_of_day(world_age, float(sources.get("seconds_per_simulated_day", 0.0)))

	var gathered := _gather_memories(
		memory_store, npc_id, household_id, settlement_id, world_age, event_store
	)
	var neighbours := _neighbours(npc_id, sources.get("co_present_identities", []))

	var missing := _shortfall_for(household_id, sources.get("shortfalls", []))
	var carrying := _player_carrying(sources.get("player_inventory"))

	var wallet_gold := int(_number_property(_property(economy, "wallet"), "balance"))
	var meal_price := VillageWages.subsistence_wage()
	var purse := NpcEconomy.purse_of(village_market)

	var production_counts: Dictionary = sources.get("production_counts", {})
	var settlement := _settlement_facts(
		settlement_id,
		sources.get("market"),
		village_market,
		catalog,
		int(sources.get("household_count", 0)),
		int(sources.get("active_institutions", 0)),
		production_counts
	)

	return {
		"npc_id": npc_id,
		"seed_value": int(EntityRef.key_of(npc_id).to_int()),
		"npc_name": _string_property(identity, "npc_name"),
		"occupation": occupation,
		"personality_trait": _string_property(identity, "personality_trait"),
		"need": _string_property(identity, "need"),
		"work_location": str(NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(occupation, "")),
		"traits": _traits_of(identity),
		"household_id": household_id,
		"settlement_id": settlement_id,

		"hunger": _number_property(_property(economy, "needs"), "hunger"),
		"is_hungry": _is_hungry(economy),
		"wallet_gold": wallet_gold,
		"meal_price": meal_price,
		"can_afford_meal": wallet_gold >= meal_price,
		"meal_available": _can_buy_meal(village_market),
		"village_purse_gold": purse,
		"village_can_pay_wage": VillageWages.can_pay_subsistence(purse),
		"is_producer": NpcProduction.PRODUCER_ITEM_BY_OCCUPATION.has(occupation),
		"produces_item_id": str(NpcProduction.PRODUCER_ITEM_BY_OCCUPATION.get(occupation, "")),

		"household_recipe_id": OccupationProduction.recipe_for(occupation),
		"shortfall_missing": missing,
		"shortfall_items_player_has": _shortfall_items_carried(missing, carrying),
		"shortfall_covered_by_player": _shortfall_is_covered(missing, carrying),

		"settlement_food_stock": settlement["food_stock"],
		"settlement_capacity": settlement["capacity"],
		"settlement_household_count": settlement["household_count"],
		"settlement_status": settlement["status"],
		"settlement_tier": settlement["tier"],
		"settlement_specialization": settlement["specialization"],
		"settlement_production_diversity": settlement["production_diversity"],

		"memories": gathered["memories"],
		"memory_count": gathered["memory_count"],
		"memory_banks": gathered["memory_banks"],
		"neighbours": neighbours,
		"neighbour_beliefs": _neighbour_beliefs(memory_store, neighbours, gathered["event_ids"]),

		"season": str(sources.get("season", "")),
		"weather": str(sources.get("weather", "")),
		"snow_depth": float(sources.get("snow_depth", 0.0)),
		"world_age_seconds": world_age,
		"hour_of_day": hour,
		"time_block": "" if hour == HOUR_UNKNOWN else NpcSchedule.time_block_for_hour(hour),

		"player_id": str(sources.get("player_id", PlayerIdentity.PLAYER_ENTITY_ID)),
		"player_carrying": carrying,
		"player_gold": int(_number_property(sources.get("player_wallet"), "balance")),
	}


## The household memory bank belonging to `npc_id`, by the same string math
## Household.for_founder itself uses -- a household is keyed by its founder's
## own ref, and every household in this codebase is single-member with its
## founder as members[0] (see household.gd), so no HouseholdStore lookup is
## needed to find the bank and none is needed for an UNLOADED settlement's
## villagers either. "" for an id that is not an npc ref at all.
static func household_bank_for(npc_id: String) -> String:
	if EntityRef.kind_of(npc_id) != NPC_BANK:
		return ""
	return EntityRef.for_kind(HOUSEHOLD_BANK, EntityRef.key_of(npc_id))


## The settlement `npc_id` lives in, read back out of its own `npc_settled`
## event, which names that settlement as the witness -- the same
## reconstruction EarthChunkManager._settlement_of_party does, so no
## npc -> settlement index has to be built or persisted for conversation
## either. "" when nothing is on record.
static func settlement_of(npc_id: String, event_store) -> String:
	if event_store == null:
		return ""
	for event in event_store.events_for_entity(npc_id):
		if event.type == "npc_settled" and not event.witnesses.is_empty():
			return event.witnesses[0]
	return ""


## Hour of day (0..23) off the SHARED world clock, or HOUR_UNKNOWN when the
## caller supplied no day length to divide it by (see HOUR_UNKNOWN). Mirrors
## EarthChunkManager._current_hour_of_day exactly, with the day length passed
## in rather than read off a Node constant this module must not depend on.
static func hour_of_day(world_age_seconds: float, seconds_per_simulated_day: float) -> int:
	if seconds_per_simulated_day <= 0.0:
		return HOUR_UNKNOWN
	var day_fraction := fmod(world_age_seconds, seconds_per_simulated_day) / seconds_per_simulated_day
	return int(day_fraction * 24.0)


## The most a single frame can ever carry, across all three banks.
static func max_memories() -> int:
	return memories_per_bank() * BANK_KINDS.size()


# -- memory ------------------------------------------------------------------


## Each bank's most recent memories_per_bank() memories, merged newest-first
## and carried once each. Returns
## {"memories": Array, "memory_count": int, "memory_banks": Dictionary,
## "event_ids": Dictionary} -- `memory_count` is the UNCAPPED total actually
## held, and `memory_banks` the per-bank holding, so a bank that is silently
## always empty (which pillar 2 says is a substrate bug, not a dialogue one)
## is visible in the frame instead of merely producing no topics.
static func _gather_memories(
	memory_store,
	npc_id: String,
	household_id: String,
	settlement_id: String,
	world_age: float,
	event_store
) -> Dictionary:
	var holders := {
		NPC_BANK: npc_id,
		HOUSEHOLD_BANK: household_id,
		SETTLEMENT_BANK: settlement_id,
	}
	var entries: Array = []
	var seen_event_ids := {}
	var per_bank := {}
	var total := 0
	var cap := memories_per_bank()

	for bank in BANK_KINDS:
		var holder: String = holders[bank]
		per_bank[bank] = 0
		if memory_store == null or holder == "":
			continue
		var records: Array = memory_store.memories_for(holder)
		per_bank[bank] = records.size()
		total += records.size()

		var newest: Array = records.duplicate()
		newest.sort_custom(func(a, b): return _record_is_newer(a, b))
		for i in mini(newest.size(), cap):
			var record = newest[i]
			if seen_event_ids.has(record.event_id):
				continue
			seen_event_ids[record.event_id] = true
			entries.append(_memory_entry(record, bank, world_age, settlement_id, event_store))

	entries.sort_custom(func(a, b): return _entry_is_newer(a, b))
	return {
		"memories": entries,
		"memory_count": total,
		"memory_banks": per_bank,
		"event_ids": seen_event_ids,
	}


## Newest first, with a deterministic tie-break on event id so two memories
## recorded on the same tick never depend on Dictionary iteration order --
## the same determinism SettlementTier.specialization_for's own sort buys.
static func _record_is_newer(a, b) -> bool:
	if a.recorded_at != b.recorded_at:
		return a.recorded_at > b.recorded_at
	return a.event_id < b.event_id


static func _entry_is_newer(a: Dictionary, b: Dictionary) -> bool:
	if a["recorded_at"] != b["recorded_at"]:
		return a["recorded_at"] > b["recorded_at"]
	return a["event_id"] < b["event_id"]


## One memory, flattened. `source_type`, `confidence` and `distortion` cross
## intact because they are what the renderer's HEDGE slot is chosen from
## (dialogue.md: firsthand -> "I saw it myself"; stranger_testimony at 0.36
## -> "Someone at the well said --"), and because applying distortion here
## rather than in the renderer would corrupt the fact before anything could
## decide how to say it.
##
## `tags` and `importance` are read off the AUTHORITATIVE Event rather than
## the memory, because MemoryRecord copies neither and `tags` is the only
## place the specific noun lives (a recipe id, a species, a traded item).
## That is consistent with the current rumor model rather than a leak of
## ground truth into belief: Rumor.transmit explicitly leaves remembered
## content unchanged through every hop and degrades only confidence and
## source type, so there is no drifted version of a tag for this to be
## overriding. If content mutation is ever built (npc.md defers it), this is
## the line that has to move.
##
## `importance` is honestly PARTIAL: only 5 of the 18 emitters in src/ set it
## (institution formed/ruin formed/boss promoted/boss defeated/settlement
## founded), so most memories carry Event's own documented 0.0 default, "an
## event is unimportant until something says otherwise". It is carried
## because it is real where it exists, but a topic that scored on it alone
## would be scoring on a constant across most of the world -- salience wants
## `confidence x (1 - distortion)` first (dialogue.md pillar 4), with this
## as a genuine bonus on the handful of events that claim one.
##
## Both read empty when no EventStore was handed in: the two stores are
## separately persisted, and a belief with no reachable ground truth is still
## a real belief.
static func _memory_entry(
	memory, bank: String, world_age: float, own_settlement_id: String, event_store
) -> Dictionary:
	var actors: Array[String] = []
	for actor in memory.remembered_actors:
		actors.append(str(actor))

	var tags: Array[String] = []
	var importance := 0.0
	if event_store != null:
		var event = event_store.get_event(memory.event_id)
		if event != null:
			importance = event.importance
			for tag in event.tags:
				tags.append(str(tag))

	return {
		"event_id": memory.event_id,
		"event_type": memory.remembered_type,
		"bank": bank,
		"holder": memory.holder,
		"source_type": memory.source_type,
		"confidence": memory.confidence,
		"distortion": memory.distortion,
		"recorded_at": memory.recorded_at,
		"age_seconds": maxf(world_age - memory.recorded_at, 0.0),
		"actors": actors,
		"subject_id": actors[0] if not actors.is_empty() else "",
		"place_settlement_id": _place_of(memory, own_settlement_id),
		"tags": tags,
		"importance": importance,
	}


## Where this memory happened, reconstructed from the entity ids it names --
## never from `remembered_location`, which is Vector2.ZERO for every memory
## in the game (see the module doc comment, trap 4).
##
## A settlement named among the remembered actors wins, because that is the
## village the event was ABOUT and the one worth naming in a sentence ("they
## were raided over at ..."); failing that, a memory held BY a settlement
## happened at that settlement; failing both, it happened here, where the
## holder lives. "" only when there is no settlement anywhere in reach, which
## is honest: an event with no village attached has no place to name.
static func _place_of(memory, own_settlement_id: String) -> String:
	for actor in memory.remembered_actors:
		if EntityRef.kind_of(actor) == SETTLEMENT_BANK:
			return str(actor)
	if EntityRef.kind_of(memory.holder) == SETTLEMENT_BANK:
		return memory.holder
	return own_settlement_id


# -- who else is standing here -----------------------------------------------


## The co-present villagers, flattened to ids and the two things a sentence
## can use. The speaker is dropped if the caller included them (a caller
## listing "everyone at this landmark" naturally does), and duplicates with
## them, so `neighbours` is always people OTHER than the speaker.
static func _neighbours(npc_id: String, identities) -> Array:
	var out: Array = []
	if not (identities is Array):
		return out
	var seen := {npc_id: true}
	for identity in identities:
		if identity == null:
			continue
		var neighbour_id := EntityRef.for_npc(int(_number_property(identity, "seed_value")))
		if seen.has(neighbour_id):
			continue
		seen[neighbour_id] = true
		out.append({
			"npc_id": neighbour_id,
			"name": _string_property(identity, "npc_name"),
			"occupation": _string_property(identity, "occupation"),
		})
	return out


## What each co-present neighbour believes about the events THIS villager
## also holds -- the raw material for dialogue.md's `contradiction` topic
## ("available when this villager and a co-present neighbour hold the same
## event_id at source types two or more steps apart"), which is then a pure
## comparison over two flat lists with no new state anywhere.
##
## Restricted to shared event ids on purpose, and not only for size: a
## neighbour's news that this villager has never heard is not a
## disagreement, it is just their news, and it is not this villager's to
## report.
static func _neighbour_beliefs(memory_store, neighbours: Array, event_ids: Dictionary) -> Array:
	var out: Array = []
	if memory_store == null or event_ids.is_empty():
		return out
	for neighbour in neighbours:
		for memory in memory_store.memories_for(neighbour["npc_id"]):
			if not event_ids.has(memory.event_id):
				continue
			out.append({
				"npc_id": neighbour["npc_id"],
				"event_id": memory.event_id,
				"source_type": memory.source_type,
				"confidence": memory.confidence,
				"distortion": memory.distortion,
			})
	return out


# -- the household's production shortfall ------------------------------------


## Just THIS villager's household's missing recipe inputs, pulled out of the
## settlement-wide shortfall list. The attribution needs no lookup: a
## household id is built from its founder, and the founder is the villager
## (Household.for_founder), so a whole village's anonymous
## `household:483920 needs 3 rock` becomes this person's own ask by string
## comparison alone -- dialogue.md's "one line turns an anonymous shortfall
## into Bren asking you for three rock".
##
## Empty when this household is short of nothing, and that emptiness is the
## point: pillar 2 omits the ask topic rather than inventing an errand.
static func _shortfall_for(household_id: String, shortfalls) -> Array:
	var missing: Array = []
	if household_id == "" or not (shortfalls is Array):
		return missing
	for shortfall in shortfalls:
		if not (shortfall is Dictionary):
			continue
		if str(shortfall.get("household_id", "")) != household_id:
			continue
		for entry in shortfall.get("missing", []):
			missing.append({
				"item_id": str(entry.get("item_id", "")),
				"need": int(entry.get("need", 0)),
			})
	return missing


## Which of the missing items the player is carrying any of at all, in the
## order the shortfall names them -- enough for "you've some of that on you"
## without claiming the errand is finished.
static func _shortfall_items_carried(missing: Array, carrying: Dictionary) -> Array:
	var out: Array = []
	for entry in missing:
		var item_id: String = entry["item_id"]
		if int(carrying.get(item_id, 0)) > 0 and not out.has(item_id):
			out.append(item_id)
	return out


## Whether the player could settle the whole shortfall right now, out of what
## they are carrying. False for an empty shortfall on purpose: "there is
## nothing to bring" must not read the same as "you already have what I
## need", or the ask topic would fire for every villager in the world.
static func _shortfall_is_covered(missing: Array, carrying: Dictionary) -> bool:
	if missing.is_empty():
		return false
	for entry in missing:
		if int(carrying.get(entry["item_id"], 0)) < int(entry["need"]):
			return false
	return true


# -- the settlement ----------------------------------------------------------


## The village's real numbers, derived through the modules that define them
## (see the module doc comment's derived/passed-in split). Every field is
## empty for a villager with no settlement on record -- notably `status`,
## which must stay "" rather than becoming SettlementState's STABLE: "there
## is no village here" and "the village is holding steady" are different
## facts and only one of them is worth a sentence.
static func _settlement_facts(
	settlement_id: String,
	market,
	village_market,
	catalog,
	household_count: int,
	active_institutions: int,
	production_counts: Dictionary
) -> Dictionary:
	if settlement_id == "":
		return {
			"food_stock": 0, "capacity": 0, "household_count": household_count,
			"status": "", "tier": "", "specialization": "", "production_diversity": 0,
		}

	var food_stock := SettlementFood.food_stock(market, village_market, catalog)
	var capacity := SettlementFood.carrying_capacity(market, village_market, catalog)
	var production_diversity := production_counts.size()
	return {
		"food_stock": food_stock,
		"capacity": capacity,
		"household_count": household_count,
		"status": SettlementState.status_for(household_count, capacity),
		"tier": SettlementTier.tier_for(household_count, active_institutions, production_diversity),
		"specialization": SettlementTier.specialization_for(production_counts),
		"production_diversity": production_diversity,
	}


static func _settlement_id(npc_id: String, sources: Dictionary) -> String:
	# An explicit id wins: the caller spawned this marker and knows which
	# village it stands in, whereas the event-store lookup is the fallback
	# that still works for a villager whose caller does not.
	var explicit := str(sources.get("settlement_id", ""))
	if explicit != "":
		return explicit
	return settlement_of(npc_id, sources.get("event_store"))


# -- the player --------------------------------------------------------------


## What the player is carrying, as item_id -> count. Stacks of the same item
## are summed, because an Inventory holds one item across several slots and
## "have you three rock" is a question about the total, not about a slot.
static func _player_carrying(inventory) -> Dictionary:
	var carrying := {}
	if inventory == null or not inventory.has_method("stacks"):
		return carrying
	for stack in inventory.stacks():
		if stack == null or stack.item == null:
			continue
		var item_id := str(stack.item.id)
		carrying[item_id] = int(carrying.get(item_id, 0)) + int(stack.count)
	return carrying


# -- duck-typed reads --------------------------------------------------------
#
# Every source is read through these rather than accessed directly, for the
# same reason NpcProduction.yield_per_second duck-types `world`: a caller
# that has not wired a dependency yet, or a test double that only models the
# part it cares about, must produce an empty fact rather than a crash.


static func _property(source, property_name: String):
	if source == null or not (property_name in source):
		return null
	return source.get(property_name)


static func _string_property(source, property_name: String) -> String:
	var value = _property(source, property_name)
	return "" if value == null else str(value)


static func _number_property(source, property_name: String) -> float:
	var value = _property(source, property_name)
	return 0.0 if value == null else float(value)


static func _is_hungry(economy) -> bool:
	var needs = _property(economy, "needs")
	if needs == null or not needs.has_method("is_hungry"):
		return false
	return bool(needs.is_hungry())


static func _can_buy_meal(village_market) -> bool:
	if village_market == null or not village_market.has_method("can_buy_meal"):
		return false
	return bool(village_market.can_buy_meal())


## The eight continuous genes NpcVoice bands, copied out flat. Only the
## argmax (`personality_trait`) is read anywhere else in the game today --
## dialogue.md's whole NpcVoice section is about the seven eighths of this
## signal the game already generates and throws away.
static func _traits_of(identity) -> Dictionary:
	var out := {}
	var genome = _property(identity, "genome")
	var traits = _property(genome, "traits")
	if not (traits is Dictionary):
		return out
	for trait_name in traits:
		out[str(trait_name)] = float(traits[trait_name])
	return out
