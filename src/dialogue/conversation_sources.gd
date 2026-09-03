extends RefCounted

## Gathers the world into the one Dictionary `DialogueContext.build` reads.
##
## The glue that was missing between the simulation and the dialogue engine.
## `build` is deliberately fail-open on every source -- an absent store and an
## empty one are the same answer -- so this may hand over an incomplete world
## and does so on purpose during load and in test harnesses. But what it DOES
## hand over is the real thing, from the real stores: dialogue.md's first
## pillar is that every sentence is grounded in a fact some other system
## already computed, and this is the only place that could quietly break it by
## substituting a stand-in.

const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const NpcRecognition = preload("res://src/dialogue/npc_recognition.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Every key `DialogueContext.build` reads. Stated explicitly, and pinned by
## test_nothing_build_reads_is_simply_absent, for the same reason
## DialogueContext.FRAME_FIELDS is stated: a source that silently stops being
## passed is a topic that silently stops being available, and an always-empty
## topic is exactly the substrate bug pillar 2 exists to surface.
const SOURCE_KEYS: Array[String] = [
	"identity", "economy", "memory_store", "event_store", "contract_store",
	"settlement_id",
	"market", "village_market", "item_catalog", "household_count",
	"active_institutions", "production_counts", "shortfalls",
	"co_present_identities", "season", "weather", "snow_depth",
	"world_age_seconds", "seconds_per_simulated_day",
	"player_inventory", "player_wallet", "player_id",
]


## The sources for one conversation.
##
## `chunk_manager` may be null -- a conversation in an unwired world must not
## crash, it must just have less to say.
static func gather(
	chunk_manager, identity, npc_id: String, player_inventory, player_wallet, economy = null
) -> Dictionary:
	var settlement_id := _settlement_of(chunk_manager, npc_id)
	var at := _npc_position(identity)
	return {
		"identity": identity,
		# Handed in by the caller, because it lives on the NpcMarker -- not on
		# the manager and not on the identity.
		#
		# This was `_call(chunk_manager, "npc_economy", [])` and
		# EarthChunkManager has no such method, so the fail-open returned null
		# for every villager in the running game. Everything DialogueContext
		# reads off the economy -- `hunger`, `is_hungry`, `wallet_gold` -- was
		# therefore permanently 0/false in play: the hunger and wallet topics
		# could never fire, and an errand reward derived from the asker's own
		# wallet would always have been nothing. Found while wiring errands,
		# pinned by test_the_villagers_own_economy_is_handed_over.
		"economy": economy,
		"memory_store": _call(chunk_manager, "memory_store", []),
		"event_store": _call(chunk_manager, "event_store", []),
		# Recognition's floor comes from the two stores that cannot be argued
		# with -- an append-only event log and a contract's live status --
		# rather than from anyone's MEMORY of them, which the gossip step can
		# talk a villager out of. See NpcRecognition's own header.
		"contract_store": _call(chunk_manager, "contract_store", []),
		# The coordinator itself, for anything that must WRITE a contract
		# rather than read one (see asks_for, and NpcAsk's "driving the store"
		# section). Reading a status is the store's job; changing one is the
		# coordinator's, because only it also records the event.
		"contract_driver": chunk_manager,
		"settlement_id": settlement_id,
		"market": _call(chunk_manager, "market_for_settlement", [settlement_id]),
		"village_market": null,
		"item_catalog": null,
		"household_count": _call(chunk_manager, "household_count_for_settlement", [settlement_id]),
		"active_institutions": _call(
			chunk_manager, "active_institution_count_for_settlement", [settlement_id]
		),
		"production_counts": _call(chunk_manager, "production_counts_for_settlement", [settlement_id]),
		"shortfalls": _call(
			chunk_manager, "production_shortfall_quests_for_settlement", [settlement_id]
		),
		# Who else is standing here, which is what the `contradiction` topic
		# needs: two villagers holding the same event at source types two or
		# more retelling hops apart.
		"co_present_identities": _co_present(chunk_manager, identity),
		"season": _call(chunk_manager, "current_season", []),
		"weather": _call(chunk_manager, "current_weather", [at]),
		"snow_depth": _call(chunk_manager, "snow_depth", []),
		# The SHARED world clock. DialogueContext's own header is explicit that
		# memories are sorted against this rather than any per-marker one.
		"world_age_seconds": _call(chunk_manager, "world_age_seconds", []),
		"seconds_per_simulated_day": SeasonCycle.SECONDS_PER_DAY,
		"player_inventory": player_inventory,
		"player_wallet": player_wallet,
		"player_id": PlayerIdentity.PLAYER_ENTITY_ID,
	}


## Calls `method` on `target` if it has one, otherwise null. Fail-open in the
## same shape DialogueContext itself uses, so a manager that has not grown a
## given accessor yet costs one topic rather than the conversation.
static func _call(target, method: String, args: Array):
	if target == null or not target.has_method(method):
		return null
	return target.callv(method, args)


static func _settlement_of(chunk_manager, npc_id: String) -> String:
	var found = _call(chunk_manager, "settlement_id_for_npc", [npc_id])
	return String(found) if found != null else ""


static func _npc_position(identity) -> Vector2:
	if identity != null and identity.get("position") != null:
		return identity.position
	return Vector2.ZERO


## Other villagers standing close enough to be part of this conversation's
## world. Empty when the manager cannot answer, which costs the contradiction
## topic and nothing else.
static func _co_present(chunk_manager, identity) -> Array:
	var found = _call(chunk_manager, "co_present_identities_near", [_npc_position(identity)])
	return found if found is Array else []


## Where the player stands with this villager (see NpcRecognition, and
## dialogue.md pillar 3: "the player is a node in the graph, not a camera").
##
## Reads STRANGER for an unwired world, which is the honest answer: no history
## recorded is exactly what a stranger is.
static func recognition_of(sources: Dictionary, npc_id: String) -> String:
	return String(NpcRecognition.tier_for({
		"npc_id": npc_id,
		"player_id": String(sources.get("player_id", PlayerIdentity.PLAYER_ENTITY_ID)),
		"event_store": sources.get("event_store"),
		"contract_store": sources.get("contract_store"),
		"memories": sources.get("memories", []),
	})["tier"])


## Everything a conversation needs to know about ERRANDS, assembled from what
## the frame and the stores already hold (see QuestOffer, NpcAsk, and
## docs/concept/quests.md's "Offered in conversation").
##
## Nothing new is read from the world here. The frame already knows who the
## player is, what they are carrying and what this villager holds in their own
## wallet -- so the errand layer needs no second read that could disagree with
## the first, and DialogueContext stays the one place this system reads the
## simulation.
##
## `item_catalog` is optional: it classifies carried ids for errands that name
## a CATEGORY rather than an item ("bring me something to eat"). Without one
## every item-id errand still works and only category errands go unmatched --
## the same fail-open shape every other source here has.
static func asks_for(sources: Dictionary, frame: Dictionary, item_catalog) -> Dictionary:
	var carrying: Dictionary = frame.get("player_carrying", {})
	return {
		# The COORDINATOR where there is one, not its bare ContractStore --
		# see NpcAsk's "driving the store" section: only the coordinator also
		# appends the lifecycle event and lets villagers witness it, and
		# NpcRecognition reads exactly those events to decide how you are
		# greeted next time. A promise settled straight against the store
		# would be one nobody ever noticed you kept.
		"contract_store": sources.get("contract_driver", sources.get("contract_store")),
		"player_id": String(frame.get("player_id", PlayerIdentity.PLAYER_ENTITY_ID)),
		"carrying": carrying,
		"item_kinds": _kinds_of(carrying, item_catalog),
		# The villager's own live balance -- the reward is re-derived against
		# it at delivery, never trusted from the offer (quests.md).
		"payer_gold": int(frame.get("wallet_gold", 0)),
	}


static func _kinds_of(carrying: Dictionary, item_catalog) -> Dictionary:
	var kinds: Dictionary = {}
	if item_catalog == null or not item_catalog.has_method("kind_of"):
		return kinds
	for item_id in carrying:
		kinds[item_id] = String(item_catalog.kind_of(item_id))
	return kinds
