extends RefCounted

## What a villager has to talk about, and how much they want to -- the
## scored-topic stage of docs/concept/dialogue.md's pipeline (`frame ->
## DialogueTopic.available_for -> scored topics -> DialogueMove.select`).
##
## Reads NOTHING but the frame DialogueContext.build produced. That is the
## whole reason the frame is a flat Dictionary of plain values: a topic
## cannot reach back into a live store to find one more fact, so what a
## villager can say is exactly what one module already decided they know.
##
## -- The two rules this module exists to enforce --
##
## 1. A TOPIC IS OMITTED WHEN ITS FACTS ARE EMPTY (dialogue.md pillar 2).
##    Not "falls back to a shorter line" -- omitted. There is no default
##    string anywhere in this file, and a frame with nothing in it produces
##    an empty topic list rather than a remark about the weather. That is
##    enforced structurally rather than by each topic remembering to check:
##    `is_available` is DEFINED as `not facts_for(...).is_empty()`, so a
##    topic can only become available by actually finding facts. It doubles
##    as an instrument -- a topic that is always empty is a SUBSTRATE bug
##    (nobody witnesses that event, nothing ever writes that number), which
##    this module is meant to surface rather than paper over.
## 2. SALIENCE IS A MEASURED NUMBER ALREADY IN THE SIMULATION (pillar 4),
##    never an authored weight. Every salience below is a real quantity some
##    other module computed, and each one is stated where it is used:
##    the villager's own `hunger`; the fraction of a real meal price a real
##    wallet is short; how far a real village purse is from one real
##    subsistence wage; the household/capacity ratio SettlementState.
##    status_for itself classifies on; the share of a village's own food
##    need (households x SettlementState.FOOD_PER_HOUSEHOLD) that is
##    missing; SettlementTier's own top-tier thresholds; the unmet share of
##    a real recipe's own input counts; real snow depth; a memory's real
##    `confidence x (1 - distortion)`; and, for a disagreement, the real
##    number of retelling hops Rumor.transmit puts between two accounts.
##    Every one of them is a fact of the world at the moment of asking, so
##    the stack re-sorts as the world moves without anything being re-tuned.
##
## Salience is therefore computed FROM THE FACTS, not alongside them: each
## `_..._facts` gathers what the topic is about and `_salience_of` reads its
## number back out of that same Dictionary. A topic cannot score on
## something it is not about.
##
## Every salience lands in [0,1] so DialogueMove can rank topics against
## each other at all. That normalisation is itself measured wherever a
## quantity has a natural scale in the substrate (snow depth is already "0
## bare to 1 fully covered"; belief strength is already a probability-shaped
## pair) and against the substrate's OWN anchor everywhere else (a meal
## price, one subsistence wage, a recipe's own input total, the tier
## thresholds a settlement is really judged on) -- never against a number
## chosen here.
##
## -- Memory topics are a table, and the table is a census --
##
## The eleven memory topics are one Dictionary of event types
## (MEMORY_TOPIC_EVENT_TYPES) rather than eleven hand-written predicates,
## and between them they claim EVERY event type src/ actually emits. That is
## deliberate: an event nobody has a topic for is news no villager can ever
## say out loud, so test_every_event_type_the_substrate_really_emits_is_
## claimed_by_some_topic scans the emitters themselves and fails when a new
## one appears. The reverse test fails on a topic claiming an event type
## nothing emits, so the table cannot drift into fiction either.
##
## Three of the eleven are, today, ALWAYS EMPTY, and they are kept rather
## than quietly dropped because rule 1 says an always-empty topic is a
## substrate bug to surface: `boss` (world_boss_promoted/defeated name only
## the creature as actor and set no witnesses, so the two most IMPORTANT
## events in the game -- 0.6 and 0.7, the highest importance anything
## writes -- reach no villager's bank), `path` (path_worn/path_reclaimed
## name only the path), and `player_deed` (player_claimed_property is held
## by the PLAYER's own household). Each lights up for free the day its
## emitter grows witnesses; none of them is a dialogue problem to fix here.
##
## Pure static module -- a Dictionary in, plain values out, no Node, no
## scene, no store, no state of its own beyond one measured constant it
## caches. Same shape as DialogueContext, SettlementFood and NpcVoice.

const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const Rumor = preload("res://src/emergence/rumor.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")

# What their day costs them.
const TOPIC_HUNGER := "hunger"
const TOPIC_WALLET := "wallet"
const TOPIC_WAGE := "wage"
const TOPIC_WORK := "work"
const TOPIC_HOUSEHOLD_ASK := "household_ask"
# What their village is.
const TOPIC_VILLAGE_STATUS := "village_status"
const TOPIC_VILLAGE_TIER := "village_tier"
const TOPIC_VILLAGE_SPECIALIZATION := "village_specialization"
const TOPIC_VILLAGE_FOOD := "village_food"
# The world around the conversation.
const TOPIC_WEATHER := "weather"
# What they remember (see MEMORY_TOPIC_EVENT_TYPES).
const TOPIC_ARRIVAL := "arrival"
const TOPIC_VILLAGE_HISTORY := "village_history"
const TOPIC_PRODUCTION_NEWS := "production_news"
const TOPIC_INSTITUTION := "institution"
const TOPIC_CARAVAN := "caravan"
const TOPIC_RAID := "raid"
const TOPIC_RUIN := "ruin"
const TOPIC_DEAL := "deal"
const TOPIC_BOSS := "boss"
const TOPIC_PATH := "path"
const TOPIC_PLAYER_DEED := "player_deed"
# Who else is standing here.
const TOPIC_NEIGHBOUR := "neighbour"
const TOPIC_CONTRADICTION := "contradiction"

## Every topic, in the order they are declared above rather than any order
## of importance -- `available_for` sorts by real salience, so nothing here
## is a ranking. Exists as an explicit contract for the same reason
## DialogueContext.FRAME_FIELDS does: it is what DialogueMove builds
## against.
const TOPIC_IDS: Array[String] = [
	TOPIC_HUNGER, TOPIC_WALLET, TOPIC_WAGE, TOPIC_WORK, TOPIC_HOUSEHOLD_ASK,
	TOPIC_VILLAGE_STATUS, TOPIC_VILLAGE_TIER, TOPIC_VILLAGE_SPECIALIZATION,
	TOPIC_VILLAGE_FOOD,
	TOPIC_WEATHER,
	TOPIC_ARRIVAL, TOPIC_VILLAGE_HISTORY, TOPIC_PRODUCTION_NEWS, TOPIC_INSTITUTION,
	TOPIC_CARAVAN, TOPIC_RAID, TOPIC_RUIN, TOPIC_DEAL, TOPIC_BOSS, TOPIC_PATH,
	TOPIC_PLAYER_DEED,
	TOPIC_NEIGHBOUR, TOPIC_CONTRADICTION,
]

## Which topic carries which of the substrate's real event types -- the
## whole emitted vocabulary of src/, split by what a villager would actually
## be saying, one topic per kind of news.
##
## Every type here is really constructed by an `Event.new(...)` in
## src/world/earth_chunk_manager.gd; the two families it builds by
## interpolation ("settlement_%s" over SettlementState.STATUSES,
## "settlement_became_%s" over SettlementTier.TIERS) are spelled out and
## pinned against those two lists by test_the_interpolated_event_families_
## are_built_from_the_substrates_own_lists, so a new status or tier cannot
## become news nothing claims.
##
## `arrival` is split off from `village_history` on purpose. Every villager
## holds their own npc_settled firsthand and undistorted forever, so it is
## the one memory that is always present at full strength -- folding it into
## village_history would let it stand in for a village's actual fortunes and
## hide whether those are being witnessed at all.
const MEMORY_TOPIC_EVENT_TYPES := {
	TOPIC_ARRIVAL: ["npc_settled"],
	TOPIC_VILLAGE_HISTORY: [
		"settlement_founded",
		"settlement_growing", "settlement_stable", "settlement_declining",
		"settlement_became_hamlet", "settlement_became_town", "settlement_became_city",
		"settlement_specialized",
	],
	TOPIC_PRODUCTION_NEWS: ["production_succeeded", "production_failed"],
	TOPIC_INSTITUTION: ["institution_formed", "institution_dissolved"],
	TOPIC_CARAVAN: ["regional_trade_departed", "regional_trade_shipped"],
	TOPIC_RAID: ["regional_trade_raided"],
	TOPIC_RUIN: ["ruin_formed"],
	TOPIC_DEAL: [
		"contract_fulfilled", "contract_breached", "contract_defaulted", "contract_cancelled",
	],
	TOPIC_BOSS: ["world_boss_promoted", "world_boss_defeated"],
	TOPIC_PATH: ["path_worn", "path_reclaimed"],
	# Both real deeds a player does that a villager would witness and repeat:
	# claiming a property, and settling in the first place. `player_settled`
	# was emitted by earth_chunk_manager.gd and claimed by no topic at all --
	# so a village could watch someone move in and have nothing to say about
	# it. Caught by test_every_event_type_the_substrate_really_emits_is_
	# claimed_by_some_topic, which exists to make exactly this kind of hole
	# loud rather than silent.
	TOPIC_PLAYER_DEED: ["player_claimed_property", "player_settled"],
}

## How far apart two accounts of the same event have to be before the
## disagreement is worth naming, in real retelling hops (see hop_depths).
## Quoted from dialogue.md rather than chosen here: "available when this
## villager and a co-present neighbour hold the same `event_id` at source
## types two or more steps apart". Two hops is exactly the gap the spec's
## own example describes -- one of them was there, the other heard it from
## someone who heard it.
const CONTRADICTION_MIN_STEPS := 2

## hop_depths()'s answer, measured once per run off the real Rumor chain
## (it cannot change within a run -- Rumor._NEXT_SOURCE is a const).
static var _hop_depths_cache: Dictionary = {}


## The facts `topic_id` is about, read out of `frame`, or an EMPTY
## Dictionary when this villager has nothing to say on it. Empty is the
## whole contract: it is what omits the topic (see is_available), and there
## is deliberately no shape in which it returns a placeholder instead.
## An unknown topic id is simply empty rather than an error, the same
## fail-open shape every read in DialogueContext already has.
static func facts_for(topic_id: String, frame: Dictionary) -> Dictionary:
	if MEMORY_TOPIC_EVENT_TYPES.has(topic_id):
		return _memory_facts(topic_id, frame)
	match topic_id:
		TOPIC_HUNGER:
			return _hunger_facts(frame)
		TOPIC_WALLET:
			return _wallet_facts(frame)
		TOPIC_WAGE:
			return _wage_facts(frame)
		TOPIC_WORK:
			return _work_facts(frame)
		TOPIC_HOUSEHOLD_ASK:
			return _household_ask_facts(frame)
		TOPIC_VILLAGE_STATUS:
			return _village_status_facts(frame)
		TOPIC_VILLAGE_TIER:
			return _village_tier_facts(frame)
		TOPIC_VILLAGE_SPECIALIZATION:
			return _village_specialization_facts(frame)
		TOPIC_VILLAGE_FOOD:
			return _village_food_facts(frame)
		TOPIC_WEATHER:
			return _weather_facts(frame)
		TOPIC_NEIGHBOUR:
			return _neighbour_facts(frame)
		TOPIC_CONTRADICTION:
			return _contradiction_facts(frame)
	return {}


## Whether this villager has anything real to say on `topic_id`. Defined as
## having facts rather than asserted separately, so availability and facts
## can never drift apart -- an available topic with no facts behind it would
## be a filler line by another name (dialogue.md pillar 2).
static func is_available(topic_id: String, frame: Dictionary) -> bool:
	return not facts_for(topic_id, frame).is_empty()


## How much this villager wants to talk about `topic_id`, in [0,1] -- a real
## measured quantity in every case (see the module doc comment for which one
## each topic uses). 0.0 for a topic with nothing behind it, which is not a
## score at all but the absence of one.
static func salience(topic_id: String, frame: Dictionary) -> float:
	var facts := facts_for(topic_id, frame)
	if facts.is_empty():
		return 0.0
	return _salience_of(topic_id, facts)


## Every topic this villager can actually speak to, scored, most salient
## first -- the input DialogueMove multiplies by NpcSeenLedger.decay. Ties
## break on topic id so two equally salient topics never depend on
## Dictionary iteration order, the same determinism SettlementTier.
## specialization_for's own sort buys.
##
## Entries are {"topic_id": String, "salience": float, "facts": Dictionary}.
static func available_for(frame: Dictionary) -> Array:
	var scored: Array = []
	for topic_id in TOPIC_IDS:
		var facts := facts_for(topic_id, frame)
		if facts.is_empty():
			continue
		scored.append({
			"topic_id": topic_id,
			"salience": _salience_of(topic_id, facts),
			"facts": facts,
		})
	scored.sort_custom(func(a, b): return _outranks(a, b))
	return scored


static func _outranks(a: Dictionary, b: Dictionary) -> bool:
	if a["salience"] != b["salience"]:
		return a["salience"] > b["salience"]
	return a["topic_id"] < b["topic_id"]


## Which memory topic carries `event_type`, or "" for a type no topic claims
## -- which, per the module doc comment, is a substrate change nobody has
## given a villager the words for yet.
static func memory_topic_for(event_type: String) -> String:
	for topic_id in MEMORY_TOPIC_EVENT_TYPES:
		if MEMORY_TOPIC_EVENT_TYPES[topic_id].has(event_type):
			return topic_id
	return ""


## How sure this holder is, discounted by how far their account has actually
## drifted: dialogue.md pillar 4's `confidence x (1 - distortion)`, and the
## salience of every memory topic. The two are genuinely different numbers
## (docs/emergence/02: a rumor can be told with total confidence and still
## be wrong), so a memory is worth saying in proportion to both.
##
## Event.importance is deliberately NOT multiplied in. Only 5 of the 18
## emitters in src/ ever set it, so a product would zero out thirteen
## eighteenths of every villager's news; it rides along in the facts instead,
## real where it exists, for whoever ranks beats.
static func belief_strength(memory: Dictionary) -> float:
	var confidence := clampf(float(memory.get("confidence", 0.0)), 0.0, 1.0)
	var distortion := clampf(float(memory.get("distortion", 0.0)), 0.0, 1.0)
	return confidence * (1.0 - distortion)


## How many retellings each MemoryRecord source type is away from having
## been there, MEASURED by actually running Rumor.transmit rather than by
## reading an order off MemoryRecord.SOURCE_TYPES.
##
## The distinction matters and is the reason this is a function at all: the
## real chain is firsthand/witnessed -> trusted_testimony ->
## stranger_testimony -> rumor, so FIRSTHAND to TRUSTED_TESTIMONY is ONE
## retelling although it is two places apart in that enum, and
## STRANGER_TESTIMONY to RUMOR is also one although it is three places
## apart. INFERENCE and WRITTEN_RECORD are absent from the result entirely,
## because the transmission chain never produces them and nothing else in
## src/ writes them -- they are dead in exactly the way remembered_outcome
## and Event.visibility are, and a ladder that included them would be
## measuring a distance no two villagers can ever really be apart.
##
## {source_type: int depth}. Measured once and cached: the chain it walks is
## a const in Rumor, so the answer cannot change within a run.
static func hop_depths() -> Dictionary:
	if _hop_depths_cache.is_empty():
		_hop_depths_cache = _measure_hop_depths()
	return _hop_depths_cache.duplicate()


## The two source types a memory can be FORMED at (MemoryRecord.from_event:
## an actor remembers firsthand, a witness from the sidelines) are both zero
## retellings deep -- seeing it from the sidelines is still seeing it -- and
## every other reachable type is however many Rumor.transmit calls it takes
## to get there.
static func _measure_hop_depths() -> Dictionary:
	var depths := {}
	for start in [MemoryRecord.FIRSTHAND, MemoryRecord.WITNESSED]:
		var source: String = start
		var depth := 0
		# Bounded by the enumeration itself: a chain longer than there are
		# source types would mean Rumor had grown a cycle.
		for _hop in range(MemoryRecord.SOURCE_TYPES.size() + 1):
			if not depths.has(source) or int(depths[source]) > depth:
				depths[source] = depth
			var probe := MemoryRecord.new()
			probe.event_id = "hop_probe"
			probe.holder = "npc:0"
			probe.source_type = source
			var told = Rumor.transmit(probe, "npc:1", 0.0)
			if told.source_type == source:
				break
			source = told.source_type
			depth += 1
	return depths


## How many retellings apart two accounts of the same event are, or -1 when
## one of them is at a source type the real transmission chain never
## produces and the distance is therefore not measurable at all.
static func source_steps_between(a_source_type: String, b_source_type: String) -> int:
	var depths := hop_depths()
	if not depths.has(a_source_type) or not depths.has(b_source_type):
		return -1
	return absi(int(depths[a_source_type]) - int(depths[b_source_type]))


## The deepest anything gets from having been there -- the denominator that
## puts a disagreement on the same [0,1] scale as every other salience.
static func _deepest_hop() -> int:
	var deepest := 0
	var depths := hop_depths()
	for source_type in depths:
		deepest = maxi(deepest, int(depths[source_type]))
	return deepest


# -- what their day costs them -----------------------------------------------


## Hunger, on NpcNeeds' OWN threshold rather than "hunger > 0": a villager
## who is a little peckish has nothing to say about it, and is_hungry is the
## same answer NpcEconomy._try_eat acts on, so a villager talks about being
## hungry exactly when the simulation has them trying to eat.
static func _hunger_facts(frame: Dictionary) -> Dictionary:
	if not bool(frame.get("is_hungry", false)):
		return {}
	return {
		"hunger": clampf(float(frame.get("hunger", 0.0)), 0.0, 1.0),
		"meal_price": int(frame.get("meal_price", 0)),
		"wallet_gold": int(frame.get("wallet_gold", 0)),
		"can_afford_meal": bool(frame.get("can_afford_meal", false)),
		"meal_available": bool(frame.get("meal_available", false)),
	}


## Money, but only ever as a MEAL ON THE SHELF THIS WALLET CANNOT REACH --
## never as being poor. dialogue.md's own substrate table states the reason:
## a permanent state is not news, and before the village purse landed, five
## of eight occupations were permanently broke, so "I have no gold" was true
## of most of the village forever. What is real, transient and resolvable is
## that the market really has food and this wallet is really short of its
## price.
static func _wallet_facts(frame: Dictionary) -> Dictionary:
	var price := int(frame.get("meal_price", 0))
	if price <= 0 or not bool(frame.get("meal_available", false)):
		return {}
	if bool(frame.get("can_afford_meal", false)):
		return {}
	var gold := int(frame.get("wallet_gold", 0))
	return {
		"wallet_gold": gold,
		"meal_price": price,
		"short_by": maxi(price - gold, 0),
	}


## The village purse that cannot pay this villager's wage. Only for a
## non-producer, because the purse is precisely what stands in for the food
## source they do not have (VillageWages: a producing household's income is
## levied so a blacksmith can eat) -- a producer's own gathering is not
## funded by it, so an empty purse is not their news. An unknown occupation
## is left alone rather than assumed to be a non-producer: absence is empty.
static func _wage_facts(frame: Dictionary) -> Dictionary:
	if str(frame.get("settlement_id", "")) == "":
		return {}
	if str(frame.get("occupation", "")) == "" or bool(frame.get("is_producer", false)):
		return {}
	if bool(frame.get("village_can_pay_wage", false)):
		return {}
	# One subsistence wage IS one meal at the village market's live price
	# (VillageWages.subsistence_wage), which is the same number the frame
	# already carries as meal_price -- not a second copy of it.
	var wage := int(frame.get("meal_price", 0))
	if wage <= 0:
		return {}
	var purse := maxf(float(frame.get("village_purse_gold", 0.0)), 0.0)
	return {
		"occupation": str(frame.get("occupation", "")),
		"village_purse_gold": purse,
		"wage": wage,
		"short_by": maxf(float(wage) - purse, 0.0),
	}


## Their own work, for the three occupations that really gather food. What
## measures how much it is worth talking about is the village's own food
## deficit (see _food_pressure) -- deliberately the SAME number the
## village_food topic scores on, because it is one real pressure being said
## two different ways: the empty shelf, and the hunter whose catch is what
## fills it. A producer in a village with food to spare stays available and
## scores nothing, which is the honest answer -- there is nothing pressing
## about your work when the larder is full.
static func _work_facts(frame: Dictionary) -> Dictionary:
	if not bool(frame.get("is_producer", false)):
		return {}
	var item_id := str(frame.get("produces_item_id", ""))
	if item_id == "":
		return {}
	return {
		"occupation": str(frame.get("occupation", "")),
		"produces_item_id": item_id,
		"work_location": str(frame.get("work_location", "")),
		"food_stock": int(frame.get("settlement_food_stock", 0)),
		"food_needed": _food_needed(frame),
		"household_count": int(frame.get("settlement_household_count", 0)),
	}


## The ask: what this household's own recipe is short of, which
## DialogueContext already attributed to this villager by string math off
## the household id. Empty is the point -- a household short of nothing
## invents no errand.
static func _household_ask_facts(frame: Dictionary) -> Dictionary:
	var missing: Array = frame.get("shortfall_missing", [])
	if missing.is_empty():
		return {}
	var units_short := 0
	for entry in missing:
		units_short += maxi(int(entry.get("need", 0)), 0)
	return {
		"recipe_id": str(frame.get("household_recipe_id", "")),
		"missing": missing,
		"units_short": units_short,
		"recipe_units": _recipe_units(str(frame.get("household_recipe_id", ""))),
		"items_player_has": frame.get("shortfall_items_player_has", []),
		"covered_by_player": bool(frame.get("shortfall_covered_by_player", false)),
	}


## How many input units the household's recipe really wants, off the same
## CraftingRecipeBook Quest._missing_inputs built the shortfall from -- so
## "short three rock" can be scored as three of the five units a stone
## pickaxe actually takes rather than as a bare count of three. 0 for a
## recipe the book does not know, which _salience_of reads as wholly unmet:
## a shortfall we cannot measure against its recipe is, as far as anything
## here can tell, the whole of it.
static func _recipe_units(recipe_id: String) -> int:
	if recipe_id == "":
		return 0
	var units := 0
	for input in CraftingRecipeBook.new().recipe_inputs(recipe_id):
		units += int(input.get("count", 0))
	return units


# -- what their village is ---------------------------------------------------


## Whether the village is growing or failing. Scored on the household /
## capacity ratio itself -- the one number SettlementState.status_for
## thresholds on -- so the score and the label can never disagree: a
## salience above SettlementState.STABLE_BAND is exactly a status that is
## not STABLE (pinned by test_village_status_salience_crosses_settlement_
## states_own_band_exactly_when_the_label_does).
static func _village_status_facts(frame: Dictionary) -> Dictionary:
	var status := str(frame.get("settlement_status", ""))
	if status == "":
		return {}
	return {
		"status": status,
		"household_count": int(frame.get("settlement_household_count", 0)),
		"capacity": int(frame.get("settlement_capacity", 0)),
		"food_stock": int(frame.get("settlement_food_stock", 0)),
	}


## What kind of place this is. Scored on how far along SettlementTier's own
## top-tier thresholds the village has actually come, taking the SMALLEST of
## the dimensions the frame carries because that is SettlementTier's own
## rule -- all dimensions must cross together, population alone is never
## sufficient.
##
## Two of its three dimensions, honestly: the frame carries household count
## and production diversity but not the active institution count, so a
## village rich in institutions and thin on people scores as thin. Naming
## that here rather than pretending the measure is complete.
static func _village_tier_facts(frame: Dictionary) -> Dictionary:
	var tier := str(frame.get("settlement_tier", ""))
	if tier == "":
		return {}
	return {
		"tier": tier,
		"household_count": int(frame.get("settlement_household_count", 0)),
		"production_diversity": int(frame.get("settlement_production_diversity", 0)),
	}


## What the village is known for. Scored on the concentration of its real
## production -- one over the number of distinct recipes it actually
## succeeds at, so a village that does one thing is entirely that thing and
## a village doing four is a quarter of the way to being known for any of
## them. The number this SHOULD be is the dominant recipe's share of
## production_counts (SettlementTier.specialization_for already computes the
## winner from those counts), but the frame carries only their size; see
## this module's notes.
static func _village_specialization_facts(frame: Dictionary) -> Dictionary:
	var specialization := str(frame.get("settlement_specialization", ""))
	if specialization == "":
		return {}
	return {
		"specialization": specialization,
		"production_diversity": int(frame.get("settlement_production_diversity", 0)),
	}


## The larder. Available only when the village really is short: a village
## that can feed its households has nothing to say about food, which is rule
## 1 rather than an oversight.
static func _village_food_facts(frame: Dictionary) -> Dictionary:
	if str(frame.get("settlement_id", "")) == "":
		return {}
	var needed := _food_needed(frame)
	if needed <= 0:
		return {}
	var stock := int(frame.get("settlement_food_stock", 0))
	if stock >= needed:
		return {}
	return {
		"food_stock": stock,
		"food_needed": needed,
		"capacity": int(frame.get("settlement_capacity", 0)),
		"household_count": int(frame.get("settlement_household_count", 0)),
		"meal_available": bool(frame.get("meal_available", false)),
	}


## What this village has to find to keep its households fed: the same
## per-household draw SettlementState.carrying_capacity divides food stock
## by, read the other way round. Never a second "how much food is enough"
## number of this module's own.
static func _food_needed(frame: Dictionary) -> int:
	return maxi(int(frame.get("settlement_household_count", 0)), 0) * SettlementState.FOOD_PER_HOUSEHOLD


## The share of what this village needs to eat that it does not have.
static func _food_pressure(stock: int, needed: int) -> float:
	if needed <= 0:
		return 0.0
	return clampf(1.0 - float(stock) / float(needed), 0.0, 1.0)


# -- the world around the conversation ---------------------------------------


## The season and the weather, scored on snow depth -- which is the ONLY
## measured quantity either of them has. `season` and `weather` reach the
## frame as bare strings with no intensity behind them, while snow depth is
## a real accumulating number already scaled 0 bare to 1 fully covered
## (Snowfall.accumulate, EarthChunkManager.set_snow_depth's own clamp), and
## it is what dialogue.md's own hardship quest source reads. So a villager
## in deep snow has something pressing to say about the weather and one in a
## dry summer has the topic available and nothing urgent in it. See this
## module's notes: an intensity for rain and heat is a substrate gap, not a
## dialogue one.
static func _weather_facts(frame: Dictionary) -> Dictionary:
	var season := str(frame.get("season", ""))
	var weather := str(frame.get("weather", ""))
	if season == "" and weather == "":
		return {}
	return {
		"season": season,
		"weather": weather,
		"snow_depth": clampf(float(frame.get("snow_depth", 0.0)), 0.0, 1.0),
	}


# -- what they remember ------------------------------------------------------


## Every memory in the frame belonging to `topic_id`'s event types, with the
## one this villager holds most strongly singled out for the sentence to be
## built from. The frame's memories are already newest-first, and the strict
## `>` below keeps the FIRST of equally-held memories, so the most recent of
## two equally believed accounts wins -- deterministic without a second
## sort.
static func _memory_facts(topic_id: String, frame: Dictionary) -> Dictionary:
	var event_types: Array = MEMORY_TOPIC_EVENT_TYPES[topic_id]
	var matched: Array = []
	var present: Array = []
	var top := {}
	var strongest := -1.0
	for memory in frame.get("memories", []):
		var event_type := str(memory.get("event_type", ""))
		if not event_types.has(event_type):
			continue
		matched.append(memory)
		if not present.has(event_type):
			present.append(event_type)
		var strength := belief_strength(memory)
		if strength > strongest:
			strongest = strength
			top = memory
	if matched.is_empty():
		return {}
	return {
		"event_types": present,
		"memories": matched,
		"top_memory": top,
		"strength": maxf(strongest, 0.0),
	}


# -- who else is standing here -----------------------------------------------


## A neighbour standing here whom this villager holds a memory ABOUT -- the
## person is named among the remembered actors, not merely nearby. The
## neighbour with the most strongly held memory wins, ties breaking on npc
## id so it never depends on iteration order.
##
## Note what this really requires: villager ids appear among an event's
## actors in very few places (npc_settled is the main one), so this fires
## mostly off the SETTLEMENT bank's copy of a neighbour's own arrival. See
## this module's notes.
static func _neighbour_facts(frame: Dictionary) -> Dictionary:
	var neighbours: Array = frame.get("neighbours", [])
	if neighbours.is_empty():
		return {}
	var best := {}
	var best_strength := -1.0
	for neighbour in neighbours:
		var neighbour_id := str(neighbour.get("npc_id", ""))
		if neighbour_id == "":
			continue
		var about: Array = []
		var top := {}
		var strongest := -1.0
		for memory in frame.get("memories", []):
			if not memory.get("actors", []).has(neighbour_id):
				continue
			about.append(memory)
			var strength := belief_strength(memory)
			if strength > strongest:
				strongest = strength
				top = memory
		if about.is_empty():
			continue
		if strongest > best_strength or (strongest == best_strength and neighbour_id < str(best.get("npc_id", ""))):
			best_strength = strongest
			best = {
				"npc_id": neighbour_id,
				"name": str(neighbour.get("name", "")),
				"occupation": str(neighbour.get("occupation", "")),
				"memories": about,
				"top_memory": top,
				"strength": maxf(strongest, 0.0),
			}
	return best


## dialogue.md's `contradiction`: this villager and a co-present neighbour
## hold the SAME event at accounts two or more retellings apart -- "Bren saw
## it himself; Lira heard it thirdhand". A pure function over two flat
## lists, with no new state anywhere: DialogueContext already restricted
## neighbour_beliefs to event ids this villager also holds, so a
## disagreement is the only thing that can be found in it.
##
## The widest gap wins (the sharpest disagreement is the one worth naming),
## ties breaking on event id then neighbour id.
static func _contradiction_facts(frame: Dictionary) -> Dictionary:
	var beliefs: Array = frame.get("neighbour_beliefs", [])
	if beliefs.is_empty():
		return {}

	var own := {}
	for memory in frame.get("memories", []):
		var event_id := str(memory.get("event_id", ""))
		if not own.has(event_id):
			own[event_id] = memory

	var names := {}
	for neighbour in frame.get("neighbours", []):
		names[str(neighbour.get("npc_id", ""))] = str(neighbour.get("name", ""))

	var best := {}
	for belief in beliefs:
		var event_id := str(belief.get("event_id", ""))
		if not own.has(event_id):
			continue
		var mine: Dictionary = own[event_id]
		var steps := source_steps_between(
			str(mine.get("source_type", "")), str(belief.get("source_type", ""))
		)
		if steps < CONTRADICTION_MIN_STEPS:
			continue
		var neighbour_id := str(belief.get("npc_id", ""))
		if not best.is_empty() and not _sharper_disagreement(steps, event_id, neighbour_id, best):
			continue
		best = {
			"event_id": event_id,
			"event_type": str(mine.get("event_type", "")),
			"steps": steps,
			"own_source_type": str(mine.get("source_type", "")),
			"own_confidence": float(mine.get("confidence", 0.0)),
			"own_distortion": float(mine.get("distortion", 0.0)),
			"neighbour_npc_id": neighbour_id,
			"neighbour_name": str(names.get(neighbour_id, "")),
			"neighbour_source_type": str(belief.get("source_type", "")),
			"neighbour_confidence": float(belief.get("confidence", 0.0)),
			"neighbour_distortion": float(belief.get("distortion", 0.0)),
		}
	return best


static func _sharper_disagreement(
	steps: int, event_id: String, neighbour_id: String, best: Dictionary
) -> bool:
	if steps != int(best["steps"]):
		return steps > int(best["steps"])
	if event_id != str(best["event_id"]):
		return event_id < str(best["event_id"])
	return neighbour_id < str(best["neighbour_npc_id"])


# -- the measured number, read back out of the facts -------------------------


## Every topic's salience, computed from the facts the topic is about and
## nothing else. See the module doc comment for what each quantity is and
## why it is the real one.
static func _salience_of(topic_id: String, facts: Dictionary) -> float:
	if MEMORY_TOPIC_EVENT_TYPES.has(topic_id):
		return clampf(float(facts["strength"]), 0.0, 1.0)
	match topic_id:
		TOPIC_HUNGER:
			return float(facts["hunger"])
		TOPIC_WALLET:
			return clampf(float(facts["short_by"]) / float(facts["meal_price"]), 0.0, 1.0)
		TOPIC_WAGE:
			return clampf(float(facts["short_by"]) / float(facts["wage"]), 0.0, 1.0)
		TOPIC_WORK:
			return _food_pressure(int(facts["food_stock"]), int(facts["food_needed"]))
		TOPIC_HOUSEHOLD_ASK:
			# A recipe the book cannot measure the ask against reads as
			# wholly unmet rather than as unimportant (see _recipe_units).
			if int(facts["recipe_units"]) <= 0:
				return 1.0
			return clampf(float(facts["units_short"]) / float(facts["recipe_units"]), 0.0, 1.0)
		TOPIC_VILLAGE_STATUS:
			return _imbalance(int(facts["household_count"]), int(facts["capacity"]))
		TOPIC_VILLAGE_TIER:
			return minf(
				clampf(float(facts["household_count"]) / float(SettlementTier.CITY_HOUSEHOLDS), 0.0, 1.0),
				clampf(
					float(facts["production_diversity"]) / float(SettlementTier.CITY_PRODUCTION_DIVERSITY),
					0.0,
					1.0
				)
			)
		TOPIC_VILLAGE_SPECIALIZATION:
			return 1.0 / float(maxi(int(facts["production_diversity"]), 1))
		TOPIC_VILLAGE_FOOD:
			return _food_pressure(int(facts["food_stock"]), int(facts["food_needed"]))
		TOPIC_WEATHER:
			return float(facts["snow_depth"])
		TOPIC_NEIGHBOUR:
			return clampf(float(facts["strength"]), 0.0, 1.0)
		TOPIC_CONTRADICTION:
			var deepest := _deepest_hop()
			if deepest <= 0:
				return 0.0
			return clampf(float(facts["steps"]) / float(deepest), 0.0, 1.0)
	return 0.0


## How far a village sits from feeding exactly the households it has -- the
## household/capacity ratio SettlementState.status_for classifies on,
## expressed as a distance from balance so that both directions of pressure
## (too many mouths, or room to grow into) read as something to talk about
## and sitting level reads as nothing.
##
## A village with no capacity at all is at maximum pressure if anyone lives
## there and at none if nobody does -- exactly the two answers status_for
## itself gives when it cannot divide.
static func _imbalance(household_count: int, capacity: int) -> float:
	if capacity <= 0:
		return 1.0 if household_count > 0 else 0.0
	return clampf(absf(float(household_count) / float(capacity) - 1.0), 0.0, 1.0)
