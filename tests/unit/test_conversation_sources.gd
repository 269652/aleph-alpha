extends GutTest

## Gathering the world into the one Dictionary DialogueContext.build reads.
##
## `build` is deliberately fail-open on every source, so this is allowed to
## hand it an incomplete world -- but what it DOES hand over has to be the
## real thing, from the real stores, or the whole "a conversation is a read of
## the simulation" pillar is a claim rather than a fact.

const ConversationSources = preload("res://src/dialogue/conversation_sources.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	manager.update(Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	))


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _sources() -> Dictionary:
	return ConversationSources.gather(manager, NpcIdentity.new(1), "npc:1", null, null)


## The two stores the whole belief layer lives in. Without these a villager
## has no memories, so every memory topic is empty and the conversation is
## reduced to their own hunger.
func test_the_real_memory_and_event_stores_are_handed_over():
	var sources := _sources()
	assert_eq(sources["memory_store"], manager.memory_store())
	assert_eq(sources["event_store"], manager.event_store())


## The world clock, not a per-marker one -- DialogueContext's own header is
## explicit that the shared clock is what memories are sorted against.
func test_the_shared_world_clock_is_handed_over():
	assert_true(_sources().has("world_age_seconds"))


## Weather and season are real reads, so "the snow's deep enough to matter" is
## true when it is said.
func test_the_real_weather_is_handed_over():
	var sources := _sources()
	assert_eq(String(sources["season"]), manager.current_season())
	assert_true(sources.has("snow_depth"))


func test_the_speaker_is_handed_over():
	assert_ne(_sources()["identity"], null)


## Every key DialogueContext.build actually reads is present, even where the
## value is empty -- a missing key and an empty one are the same to a
## fail-open reader, but the difference matters to anyone auditing what a
## conversation is allowed to know.
func test_nothing_build_reads_is_simply_absent():
	var sources := _sources()
	for key in ConversationSources.SOURCE_KEYS:
		assert_true(sources.has(key), "sources is missing '%s'" % key)


## And it survives a world that is not wired: a conversation in a test harness
## or during load must not crash, it must just have less to say.
func test_an_unwired_world_still_gathers():
	var sources := ConversationSources.gather(null, null, "npc:1", null, null)
	assert_eq(sources["identity"], null)
	for key in ConversationSources.SOURCE_KEYS:
		assert_true(sources.has(key), "sources is missing '%s'" % key)


# -- what a conversation needs to know about errands -------------------------


func _ask_frame() -> Dictionary:
	return {
		"npc_id": "npc:1",
		"player_id": "player:local",
		"player_carrying": {"rock": 4, "iron_sword": 1},
		"wallet_gold": 17,
	}


## The errand layer needs nothing the frame does not already hold: who is
## asking, what the player is carrying, and what the villager can actually
## pay. Assembling it here rather than in the scene keeps the one place that
## reads the world the one place that reads the world.
func test_the_ask_context_is_assembled_from_what_is_already_known():
	var asks := ConversationSources.asks_for(_sources(), _ask_frame(), null)
	assert_eq(String(asks["player_id"]), "player:local")
	assert_eq(asks["carrying"], {"rock": 4, "iron_sword": 1})


## The COORDINATOR is handed over, not its bare ContractStore. Only the
## coordinator keeps the contract store and the event store in sync, and
## NpcRecognition reads those events to decide how a villager greets you next
## time -- so a promise settled straight against the store would be a promise
## nobody, including the person you kept it for, ever noticed.
func test_the_coordinator_drives_the_contracts_so_promises_are_witnessed():
	var asks := ConversationSources.asks_for(_sources(), _ask_frame(), null)
	assert_eq(asks["contract_store"], manager)
	assert_true(manager.has_method("fulfill_contract"))
	assert_true(manager.has_method("default_on_contract"))


## The reward is re-derived against the villager's LIVE balance at delivery,
## so the balance has to come along -- and it is the same number the frame
## already reports them holding, not a second read that could disagree.
func test_the_villagers_own_balance_comes_along_to_be_paid_from():
	assert_eq(int(ConversationSources.asks_for(_sources(), _ask_frame(), null)["payer_gold"]), 17)


## An errand that names a CATEGORY (a hungry villager wants food, not a
## specific dish) needs to know what each carried id actually is.
func test_what_the_player_carries_is_classified_for_category_errands():
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var kinds: Dictionary = ConversationSources.asks_for(
		_sources(), _ask_frame(), ItemCatalog.new()
	)["item_kinds"]
	assert_eq(String(kinds["iron_sword"]), "weapon")
	assert_eq(String(kinds["rock"]), "material")


## No catalog is an ordinary state, not an error -- the same fail-open shape
## every other source here has. Item-id errands still work; only category
## errands go unmatched.
func test_no_catalog_classifies_nothing_and_raises_nothing():
	assert_eq(ConversationSources.asks_for(_sources(), _ask_frame(), null)["item_kinds"], {})


# -- the villager's own economy ---------------------------------------------


## Found while wiring errands: this key was gathered by calling
## `chunk_manager.npc_economy()`, and no such method exists on
## EarthChunkManager -- so `_call`'s fail-open returned null for every
## villager in the running game. Everything DialogueContext reads off the
## economy (`hunger`, `is_hungry`, `wallet_gold`) was therefore permanently
## 0/false in play: the hunger and wallet topics could never fire, and a
## quest reward derived from the asker's wallet would always have been zero.
##
## The economy lives on the NpcMarker, not on the manager and not on the
## identity, so it has to be handed in by the caller that has the marker.
class StubEconomy:
	extends RefCounted
	var wallet = null
	var needs := {"hunger": 0.75}


func test_the_villagers_own_economy_is_handed_over():
	var economy = StubEconomy.new()
	var sources := ConversationSources.gather(
		manager, NpcIdentity.new(1), "npc:1", null, null, economy
	)
	assert_eq(sources["economy"], economy)


## No economy is still an ordinary state -- a marker whose economy was never
## set up (an isolated rendering test, a villager with no market) reads as
## absent rather than as an error.
func test_a_villager_with_no_economy_is_an_ordinary_state():
	assert_null(_sources()["economy"])


# -- no phantom method names -------------------------------------------------


## `gather` reads the world by NAME, through `_call`'s fail-open. That
## fail-open is deliberate and correct -- an unloaded chunk really has no
## market -- but it makes a MISSPELLED or non-existent method
## indistinguishable from an absent one, and silently so.
##
## Three such names were live at once, all found while wiring errands, each
## having been wrong since the day it was written:
##   `npc_economy`            -> hunger, is_hungry and wallet_gold were 0/false
##                               for every villager in the game
##   `settlement_id_for_npc`  -> no villager had a settlement, so the
##                               shortfall list, village status, tier,
##                               specialization and food stock were all read
##                               against ""
##   `market_for_settlement`  -> no settlement had a market, so SettlementFood
##                               reported zero for everything
##
## Every unit test passed throughout. This is the instrument that makes the
## next one a test failure instead of a silent hole: every method `gather`
## names must exist on the real manager.
const GATHERED_METHOD_NAMES: Array[String] = [
	"memory_store", "event_store", "contract_store", "settlement_id_for_npc",
	"market_for_settlement", "household_count_for_settlement",
	"active_institution_count_for_settlement", "production_counts_for_settlement",
	"production_shortfall_quests_for_settlement", "co_present_identities_near",
	"current_season", "current_weather", "snow_depth", "world_age_seconds",
]


func test_gather_asks_for_nothing_the_manager_cannot_answer():
	for method_name in GATHERED_METHOD_NAMES:
		assert_true(
			manager.has_method(method_name),
			"gather calls %s and EarthChunkManager has no such method" % method_name
		)


## And the names above have to be the ones gather really uses -- a list that
## drifted from the call sites would pin nothing.
func test_the_pinned_names_are_the_ones_gather_really_calls():
	var source := FileAccess.get_file_as_string("res://src/dialogue/conversation_sources.gd")
	for method_name in GATHERED_METHOD_NAMES:
		assert_true(
			source.contains('"%s"' % method_name),
			"%s is pinned here but gather no longer calls it" % method_name
		)


## The neighbour radius is derived from the one conversational distance this
## game already has, not chosen: twice how close you must stand to talk to
## someone at all is "near enough that you can see them both from here".
func test_the_neighbour_radius_is_twice_talk_range():
	var Player = load("res://scenes/player.gd")
	assert_almost_eq(EarthChunkManager.NEIGHBOUR_RADIUS_PX, Player.TALK_RADIUS * 2.0, 0.001)


## The seam between a real Inventory and the errand layer, end to end: what
## the player is really carrying has to arrive in the ask context under the
## ids an errand names. Everything in between is duck-typed reads, so nothing
## else in the suite would notice if it stopped arriving.
func test_what_the_player_really_carries_reaches_the_ask_context():
	var Inventory = load("res://src/gameplay/inventory.gd")
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var catalog = ItemCatalog.new()
	var inventory = Inventory.new(20)
	inventory.add(catalog.make("meat"), 3)

	var sources := ConversationSources.gather(
		manager, NpcIdentity.new(1), "npc:1", inventory, null, null
	)
	var DialogueContext = load("res://src/dialogue/dialogue_context.gd")
	var frame: Dictionary = DialogueContext.build("npc:1", sources)

	assert_eq(int(frame["player_carrying"].get("meat", 0)), 3, "the frame lost the meat")
	assert_eq(
		int(ConversationSources.asks_for(sources, frame, catalog)["carrying"].get("meat", 0)), 3,
		"the ask context lost the meat"
	)
