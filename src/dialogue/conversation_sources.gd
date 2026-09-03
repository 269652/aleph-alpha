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
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Every key `DialogueContext.build` reads. Stated explicitly, and pinned by
## test_nothing_build_reads_is_simply_absent, for the same reason
## DialogueContext.FRAME_FIELDS is stated: a source that silently stops being
## passed is a topic that silently stops being available, and an always-empty
## topic is exactly the substrate bug pillar 2 exists to surface.
const SOURCE_KEYS: Array[String] = [
	"identity", "economy", "memory_store", "event_store", "settlement_id",
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
	chunk_manager, identity, npc_id: String, player_inventory, player_wallet
) -> Dictionary:
	var settlement_id := _settlement_of(chunk_manager, npc_id)
	var at := _npc_position(identity)
	return {
		"identity": identity,
		"economy": _call(chunk_manager, "npc_economy", []),
		"memory_store": _call(chunk_manager, "memory_store", []),
		"event_store": _call(chunk_manager, "event_store", []),
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
