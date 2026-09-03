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
