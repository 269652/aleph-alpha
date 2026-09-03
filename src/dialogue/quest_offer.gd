extends RefCounted

## What a villager asks you for, projected out of what is really wrong with
## their life (docs/concept/quests.md, "Offered in conversation: the six
## grounded sources").
##
## ## The pillar this module is built to keep falsifiable
##
## quests.md pillar 1: "Quests are a byproduct of simulation state, never
## authored content" -- and its own sharper phrasing, "delete the query and
## the village is still starving." That is a property of this file: there is
## no errand table here, no default ask, and no branch that produces an offer
## from an absent fact. Every offer below is a restatement of a condition
## some other module measured, and a frame in which nothing is wrong yields
## an empty Array rather than a shorter errand.
##
## ## Why the id is derived
##
## `offer_id` is `"<kind>:<subject>:<count>"` and is never allocated.
## quests.md: "the same real shortage always yields the same id and offers
## dedupe across recomputation without a registry. That is pillar 1 restated
## as an implementation constraint: an offer cannot outlive the condition it
## projects, because it has no identity of its own."
##
## So this whole list is recomputed on every conversation open, and that is
## cheap and correct rather than wasteful: an errand that was resolved while
## you walked back simply is not in the list any more, with nothing to
## expire. The only thing that IS persisted is an ACCEPTANCE, and that is a
## `Contract`, which already exists.
##
## `<subject>` is the item id where there is one, and otherwise the thing the
## errand is about (a food KIND, a place to go and look). For an entity id it
## is a colon-bearing string, so the id has more than three parts -- it stays
## an opaque, derived, stable key either way, which is all the dedupe rule
## asks of it.
##
## ## Urgency is borrowed, never recomputed
##
## Each kind names a DialogueTopic topic (TOPIC_BY_KIND) and takes that
## topic's salience verbatim. This is deliberate: DialogueTopic's second rule
## is that "salience is a measured number already in the simulation, never an
## authored weight," and a second scoring layer here would be exactly the
## authored weight that rule forbids -- with the added failure that a
## villager could ask for something more urgently than they are willing to
## talk about it.
##
## ## Which of the six sources are live
##
## quests.md names six. Four are built here, and the two that are not are
## absent rather than stubbed:
##
## 1. Production shortfall  -- LIVE (KIND_FETCH)
## 2. Village hunger        -- LIVE (KIND_FEED)
## 3. Remembered threat     -- LIVE (KIND_INVESTIGATE)
## 4. Deeper need           -- NOT BUILT. `NeedResolver.resolve` needs live
##    stock, allocated nodes and nearby structures; the frame carries none of
##    the three, and it carries none of them on purpose (DialogueContext's
##    own header: the frame holds no Object, which is what makes it hashable
##    and what makes the AI seam safe). Reaching for a live store from here
##    would break that boundary for one sentence.
## 5. Carried news          -- NOT BUILT. It needs a memory the PLAYER holds,
##    and the player holds none: the rumor-vector loop is dialogue.md's own
##    open item. This is the one source no NPC can satisfy, so it stays
##    listed and unbuilt rather than faked from something else.
## 6. Hardship              -- LIVE (KIND_FIREWOOD)
##
## Pure static module over the frame -- no store, no Node, no engine.

const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const QuestReward = preload("res://src/dialogue/quest_reward.gd")
const Rumor = preload("res://src/emergence/rumor.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Source 1: bring a household the recipe input it is short of.
const KIND_FETCH := "fetch"
## Source 2: bring a hungry villager food their market cannot sell them.
const KIND_FEED := "feed"
## Source 3: go and look at somewhere they remember going wrong.
const KIND_INVESTIGATE := "look"
## Source 6: firewood before the cold.
const KIND_FIREWOOD := "firewood"

const KINDS: Array[String] = [KIND_FETCH, KIND_FEED, KIND_INVESTIGATE, KIND_FIREWOOD]

## The topic each kind borrows its urgency from. Pinned by
## test_every_kind_names_a_real_topic_to_borrow_its_salience_from against
## DialogueTopic.TOPIC_IDS, so a renamed topic breaks here loudly rather than
## silently scoring every offer at zero.
const TOPIC_BY_KIND := {
	KIND_FETCH: DialogueTopic.TOPIC_HOUSEHOLD_ASK,
	KIND_FEED: DialogueTopic.TOPIC_HUNGER,
	KIND_INVESTIGATE: DialogueTopic.TOPIC_RAID,
	KIND_FIREWOOD: DialogueTopic.TOPIC_WEATHER,
}

## The full documented shape (quests.md). Asserted key-by-key rather than
## trusted, so a source that forgets a field is a test failure and not a
## missing label in a window.
const OFFER_KEYS: Array[String] = [
	"offer_id", "kind", "npc_id", "household_id", "settlement_id",
	"item_id", "item_kind", "count", "target_id", "reward", "deadline_seconds",
	"salience",
]

## What a food errand names. VillageMarket.FOOD_KIND is ItemCatalog's own
## `kind`, the same category SettlementFood filters a settlement's stock
## through before it counts as fed -- so "bring me something to eat" is
## satisfied by exactly what would have fed them at the market.
const FOOD_KIND := "food"

## What a hardship errand asks for. Real in two independent places: it is an
## ItemCatalog material, and it is literally what the `campfire` recipe
## burns (CraftingRecipeBook: wood 2 + rock 2), which is the recipe the
## `nurse` occupation's own household attempts.
const FIREWOOD_ITEM_ID := "wood"

## Below this there is snow on the ground but no hardship in it. Anchored to
## the same [0,1] snow depth DialogueTopic.TOPIC_WEATHER already scores on
## (Snowfall.accumulate's own clamped range), at the third of it where a
## villager stops being able to work outside. Pinned by
## test_a_dusting_of_snow_is_not_hardship.
const MIN_SNOW_FOR_HARDSHIP := 1.0 / 3.0

## How much wood a winter's worth of snow is worth asking for -- two full
## campfires' input (CraftingRecipeBook's campfire takes 2 wood), so the ask
## is a real quantity of a real recipe rather than a round number. Scaled by
## actual snow depth, so a hard winter asks for more.
const FIREWOOD_UNITS_AT_FULL_SNOW := 4

## How long an accepted errand runs before it lapses, in real world seconds.
## One simulated day: the same clock SeasonCycle drives everything else on,
## and the granularity a village errand is actually felt at. Carried as a
## DURATION rather than an absolute time because an offer is stateless -- the
## absolute deadline is set on the Contract at acceptance, which is the only
## thing that persists.
const DEADLINE_SECONDS := SeasonCycle.SECONDS_PER_DAY

## The memory event types that name something gone wrong somewhere you could
## go and look at. Read off DialogueTopic's own map rather than restated, so
## the errand and the sentence about it can never name different events.
const THREAT_TOPICS: Array[String] = [DialogueTopic.TOPIC_RAID, DialogueTopic.TOPIC_RUIN]

static var _min_threat_strength_cache := -1.0


## The belief strength below which a remembered threat is too degraded to
## send anyone after.
##
## MEASURED, not chosen: a memory is worth acting on while it is still no
## more than one retelling from someone who was there. The number is obtained
## by actually running Rumor.transmit twice from a firsthand record and
## scoring both with the same DialogueTopic.belief_strength every memory
## topic is scored with -- so if the decay constants are ever retuned, this
## floor moves with them instead of silently becoming a different rule.
## Same shape as DialogueTopic.hop_depths, which measures its ladder rather
## than reading an order off an enum.
static func min_threat_strength() -> float:
	if _min_threat_strength_cache >= 0.0:
		return _min_threat_strength_cache
	var firsthand := MemoryRecord.new()
	firsthand.event_id = "measurement"
	firsthand.holder = "measurement"
	firsthand.remembered_type = "measurement"
	firsthand.source_type = MemoryRecord.FIRSTHAND
	var once = Rumor.transmit(firsthand, "measurement", 0.0)
	var twice = Rumor.transmit(once, "measurement", 0.0)
	var after_one := DialogueTopic.belief_strength(
		{"confidence": once.confidence, "distortion": once.distortion}
	)
	var after_two := DialogueTopic.belief_strength(
		{"confidence": twice.confidence, "distortion": twice.distortion}
	)
	_min_threat_strength_cache = (after_one + after_two) * 0.5
	return _min_threat_strength_cache


## `"<kind>:<subject>:<count>"` -- pure, allocation-free, and identical for
## the same real condition however many times it is recomputed.
static func id_of(kind: String, subject: String, count: int) -> String:
	return "%s:%s:%d" % [kind, subject, count]


## An offer id read back into the errand it names.
##
## The inverse of id_of, and the reason deriving the id was worth doing: an
## accepted errand persists as a `Contract`, whose obligations are free-form
## Strings by that module's own design -- so the id IS the storage, and
## nothing about the errand has to be written down twice.
##
## Splits from the ENDS rather than on every colon: a subject is often an
## entity id ("settlement:9") and carries colons of its own. A string that is
## not an offer id reads back empty rather than raising, the same fail-open
## shape every other read in this layer has.
static func parse_id(offer_id: String) -> Dictionary:
	var empty := {"kind": "", "subject": "", "count": 0}
	var parts := offer_id.split(":")
	if parts.size() < 3:
		return empty
	var kind := parts[0]
	var count_text := parts[parts.size() - 1]
	if not KINDS.has(kind) or not count_text.is_valid_int():
		return empty
	var subject_parts: Array = []
	for i in range(1, parts.size() - 1):
		subject_parts.append(parts[i])
	return {
		"kind": kind,
		"subject": ":".join(subject_parts),
		"count": int(count_text),
	}


## Every errand this villager really has, most urgent first.
##
## Empty is an ordinary and common answer: most villagers, most of the time,
## want nothing from you.
static func offers_for(frame: Dictionary) -> Array:
	var offers: Array = []
	offers.append_array(_fetch_offers(frame))
	offers.append_array(_feed_offers(frame))
	offers.append_array(_investigate_offers(frame))
	offers.append_array(_firewood_offers(frame))
	offers.sort_custom(func(a, b): return float(a["salience"]) > float(b["salience"]))
	return offers


## The one errand this villager would raise if they raised one, or {} if they
## have none.
static func best_for(frame: Dictionary) -> Dictionary:
	var offers := offers_for(frame)
	if offers.is_empty():
		return {}
	return offers[0]


# -- source 1: production shortfall ------------------------------------------


## One offer per missing recipe input. The shortfall was already attributed
## to this villager by DialogueContext._shortfall_for, by string math off the
## household id -- so nothing here has to look anyone up.
static func _fetch_offers(frame: Dictionary) -> Array:
	var offers: Array = []
	var salience := DialogueTopic.salience(DialogueTopic.TOPIC_HOUSEHOLD_ASK, frame)
	for entry in frame.get("shortfall_missing", []):
		var item_id := str(entry.get("item_id", ""))
		var count := int(entry.get("need", 0))
		if item_id == "" or count <= 0:
			continue
		offers.append(_offer(
			frame, KIND_FETCH, item_id, "", count,
			str(frame.get("household_id", "")), salience
		))
	return offers


# -- source 2: village hunger ------------------------------------------------


## A real, transient, recoverable failure to eat: hungry AND the market
## cannot sell them a meal. Either half alone is not an errand -- a hungry
## villager with a stocked market can simply go and buy one, and an empty
## market is nobody's problem until someone is hungry.
static func _feed_offers(frame: Dictionary) -> Array:
	if not bool(frame.get("is_hungry", false)):
		return []
	if bool(frame.get("meal_available", false)):
		return []
	return [_offer(
		frame, KIND_FEED, "", FOOD_KIND, 1,
		str(frame.get("npc_id", "")),
		DialogueTopic.salience(DialogueTopic.TOPIC_HUNGER, frame)
	)]


# -- source 3: remembered threat ---------------------------------------------


## Somewhere they remember going wrong, if they remember it well enough to be
## worth the walk. One offer per distinct place, so two memories of the same
## raid do not become two errands.
static func _investigate_offers(frame: Dictionary) -> Array:
	var offers: Array = []
	var seen: Dictionary = {}
	var floor_strength := min_threat_strength()
	for memory in frame.get("memories", []):
		if not (memory is Dictionary):
			continue
		var topic := DialogueTopic.memory_topic_for(str(memory.get("event_type", "")))
		if not THREAT_TOPICS.has(topic):
			continue
		# Nowhere to send anyone is not an errand, however vivid the memory.
		var place := str(memory.get("place_settlement_id", ""))
		if place == "" or seen.has(place):
			continue
		if DialogueTopic.belief_strength(memory) < floor_strength:
			continue
		seen[place] = true
		offers.append(_offer(
			frame, KIND_INVESTIGATE, "", "", 0, place,
			DialogueTopic.salience(topic, frame)
		))
	return offers


# -- source 6: hardship ------------------------------------------------------


## Real snow above a floor, and someone who cannot go and cut their own.
## quests.md source 6: "Real snow depth above a floor plus a non-producer
## occupation. Firewood before the cold."
static func _firewood_offers(frame: Dictionary) -> Array:
	if bool(frame.get("is_producer", false)):
		return []
	var snow := clampf(float(frame.get("snow_depth", 0.0)), 0.0, 1.0)
	if snow < MIN_SNOW_FOR_HARDSHIP:
		return []
	var count := ceili(snow * float(FIREWOOD_UNITS_AT_FULL_SNOW))
	return [_offer(
		frame, KIND_FIREWOOD, FIREWOOD_ITEM_ID, "", count,
		str(frame.get("household_id", "")),
		DialogueTopic.salience(DialogueTopic.TOPIC_WEATHER, frame)
	)]


# -- the shape ---------------------------------------------------------------


## The one place an offer Dictionary is built, so every source produces the
## identical documented shape and OFFER_KEYS has one thing to check.
##
## The reward is derived HERE from the asker's live wallet and derived AGAIN
## at fulfilment (see QuestReward) -- what is on the offer is what they could
## pay when they asked, which is not a promise.
static func _offer(
	frame: Dictionary, kind: String, item_id: String, item_kind: String,
	count: int, target_id: String, salience: float
) -> Dictionary:
	var subject := item_id if item_id != "" else (item_kind if item_kind != "" else target_id)
	return {
		"offer_id": id_of(kind, subject, count),
		"kind": kind,
		"npc_id": str(frame.get("npc_id", "")),
		"household_id": str(frame.get("household_id", "")),
		"settlement_id": str(frame.get("settlement_id", "")),
		"item_id": item_id,
		"item_kind": item_kind,
		"count": count,
		"target_id": target_id,
		"reward": QuestReward.gold_for(count, int(frame.get("wallet_gold", 0))),
		"deadline_seconds": DEADLINE_SECONDS,
		"salience": salience,
	}
