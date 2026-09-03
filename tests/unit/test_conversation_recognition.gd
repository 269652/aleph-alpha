extends GutTest

## Talking makes you someone (docs/concept/dialogue.md pillar 3: "the player
## is a node in the graph, not a camera").
##
## `NpcRecognition` was built with 318 lines and 29 tests and had no caller at
## all: every beat rendered at `stranger`, and nothing was written when you
## talked, so recognition could never advance. A villager you had spoken to
## nine times greeted you exactly as one you had never met.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const NpcRecognition = preload("res://src/dialogue/npc_recognition.gd")
const ConversationSources = preload("res://src/dialogue/conversation_sources.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager

const NPC_ID := "npc:4242"


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


func _tier() -> String:
	return String(NpcRecognition.tier_for({
		"npc_id": NPC_ID,
		"player_id": PlayerIdentity.PLAYER_ENTITY_ID,
		"event_store": manager.event_store(),
		"contract_store": manager.contract_store(),
		"memories": [],
	})["tier"])


# -- the write half ----------------------------------------------------------


func test_someone_you_have_never_met_is_a_stranger():
	assert_eq(_tier(), NpcRecognition.STRANGER)


## The whole pillar: talking is a real act that writes real state.
func test_talking_to_someone_makes_them_know_you():
	manager.record_conversation_with(NPC_ID)
	assert_eq(_tier(), NpcRecognition.KNOWS_YOU)


## ...and it is recorded ONCE per conversation, not once per sentence. A
## villager you asked three questions of has met you once.
func test_a_conversation_is_one_event_not_one_per_sentence():
	var before := manager.event_store().events_for_entity(NPC_ID).size()
	manager.record_conversation_with(NPC_ID)
	var after_first := manager.event_store().events_for_entity(NPC_ID).size()
	assert_eq(after_first, before + 1)


## Talking to one villager does not make their neighbour know you. Recognition
## is per-person, which is the point of it.
func test_talking_to_one_villager_leaves_another_a_stranger():
	manager.record_conversation_with(NPC_ID)
	assert_eq(
		String(NpcRecognition.tier_for({
			"npc_id": "npc:9999",
			"player_id": PlayerIdentity.PLAYER_ENTITY_ID,
			"event_store": manager.event_store(),
			"contract_store": manager.contract_store(),
			"memories": [],
		})["tier"]),
		NpcRecognition.STRANGER
	)


## The villager WITNESSES it, so it can be gossiped -- which is what makes a
## stranger two settlements away eventually greet you as someone they have
## heard of.
func test_the_villager_witnesses_having_met_you():
	manager.record_conversation_with(NPC_ID)
	assert_gt(manager.memory_store().memories_for(NPC_ID).size(), 0)


# -- the read half -----------------------------------------------------------


## The sources handed to a conversation carry the contract store too, or
## recognition can never see past hearsay: an obligation is something you took
## on, and it lives in contracts rather than in anyone's memory of it.
func test_the_contract_store_is_handed_over():
	var sources := ConversationSources.gather(manager, NpcIdentity.new(1), NPC_ID, null, null)
	assert_eq(sources["contract_store"], manager.contract_store())


func test_the_gathered_sources_can_answer_recognition():
	manager.record_conversation_with(NPC_ID)
	var sources := ConversationSources.gather(manager, NpcIdentity.new(1), NPC_ID, null, null)
	assert_eq(String(ConversationSources.recognition_of(sources, NPC_ID)), NpcRecognition.KNOWS_YOU)


func test_recognition_of_an_unwired_world_is_stranger():
	assert_eq(
		String(ConversationSources.recognition_of(ConversationSources.gather(null, null, NPC_ID, null, null), NPC_ID)),
		NpcRecognition.STRANGER
	)
