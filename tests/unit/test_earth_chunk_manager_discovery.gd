extends GutTest

## docs/concept/discovery.md: the footfall performed for real -- the chunk
## under the player marked on the SAME ExploredTiles `/map` and
## MapProjection read, the distance measured from the manager's OWN spawn
## chunk, and the report Discovery decided handed back for World to pay.
##
## Uses the manager's own stores directly rather than loading a real chunk:
## a footfall touches the explored record and the spawn coordinate, neither
## of which needs terrain to exist.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const Discovery = preload("res://src/gameplay/discovery.gd")
const JourneyRing = preload("res://src/gameplay/journey_ring.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D

const SPAWN_TILE := Vector2i(0, 0)


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager.set_spawn_tile(SPAWN_TILE)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## A tile in the chunk `chunks` east of spawn.
func _tile_chunks_out(chunks: int) -> Vector2i:
	return SPAWN_TILE + Vector2i(chunks * EarthChunkManager.CHUNK_SIZE, 0)


# -- walking records ground ---------------------------------------------

## The measurement this whole slice exists for: before it, the ONLY caller
## of mark_chunk_explored in the game was the `reveal` spell atom, so a
## player who walked across a continent had an empty map.
func test_a_footfall_marks_the_chunk_under_the_player_explored():
	var chunk := Discovery.chunk_of(_tile_chunks_out(3))
	assert_false(manager.is_chunk_explored(chunk), "precondition: unwalked ground")
	manager.record_footfall(_tile_chunks_out(3))
	assert_true(manager.is_chunk_explored(chunk), "the ground the player stood on is on the map")


## One chunk per footfall: the one under the player. The streamer loads a
## 5x5 neighbourhood and the camera shows a fraction of one chunk, so
## marking all 25 would be the map claiming knowledge the player never had
## (docs/concept/discovery.md, pillar 1).
func test_a_footfall_marks_only_the_chunk_under_the_player():
	manager.record_footfall(_tile_chunks_out(3))
	assert_eq(manager.explored_chunks().size(), 1, "exactly the ground underfoot")


func test_the_map_fills_up_as_the_player_walks():
	for chunks_out in range(6):
		manager.record_footfall(_tile_chunks_out(chunks_out))
	assert_eq(manager.explored_chunks().size(), 6, "six chunks walked, six chunks known")


# -- and pays, once ------------------------------------------------------

func test_new_ground_pays_what_the_ring_asks_for_it():
	var report: Dictionary = manager.record_footfall(_tile_chunks_out(3))
	assert_eq(int(report["xp"]), Discovery.xp_for_distance(3))


## Pillar 3: unfarmable. Pacing back over a boundary cannot pay twice.
func test_walking_back_over_ground_already_walked_pays_nothing():
	manager.record_footfall(_tile_chunks_out(1))
	manager.record_footfall(_tile_chunks_out(2))
	var back: Dictionary = manager.record_footfall(_tile_chunks_out(1))
	assert_eq(int(back["xp"]), 0, "this ground already paid, once")


## The common case, and the one that must cost nothing: the player is
## somewhere in a chunk they are already in, on every frame but a handful.
func test_a_footfall_in_the_chunk_already_underfoot_reports_nothing_at_all():
	manager.record_footfall(_tile_chunks_out(2))
	var same: Dictionary = manager.record_footfall(_tile_chunks_out(2) + Vector2i(1, 1))
	assert_true(same.is_empty(), "staying put is not an event")


# -- the distance is the world's own -------------------------------------

## Measured from the spawn the world really set (set_spawn_tile, the same
## coordinate RegionDifficulty tiers from), never from the origin.
func test_the_distance_is_measured_from_the_worlds_own_spawn_chunk():
	var far_spawn := Vector2i(1000 * EarthChunkManager.CHUNK_SIZE, 0)
	manager.set_spawn_tile(far_spawn)
	var report: Dictionary = manager.record_footfall(far_spawn + Vector2i(EarthChunkManager.CHUNK_SIZE, 0))
	assert_eq(
		int(report["xp"]), Discovery.xp_for_distance(1),
		"one chunk from home is one chunk from home, wherever home is"
	)


## A world that has not decided where home is cannot say how far out you
## are, and must not guess that home is the origin -- that would pay far
## country rates for the ground under a fresh character's feet.
func test_a_world_with_no_spawn_yet_reports_nothing():
	var fresh := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	assert_true(fresh.record_footfall(_tile_chunks_out(5)).is_empty())


# -- and says so ---------------------------------------------------------

func test_crossing_out_of_the_hearth_raises_the_card_for_the_ring_entered():
	var hearth_edge := int(JourneyRing.RINGS[0]["outer_chunks"])
	manager.record_footfall(_tile_chunks_out(hearth_edge))
	var crossed: Dictionary = manager.record_footfall(_tile_chunks_out(hearth_edge + 1))
	assert_false(crossed["crossing"].is_empty(), "a real boundary was crossed")
	assert_eq(String(crossed["crossing"]["id"]), String(JourneyRing.RINGS[1]["id"]))
	assert_true(String(crossed["message"]).contains(Discovery.packing_line(JourneyRing.RINGS[1])))


func test_the_first_footfall_of_a_session_is_not_a_crossing():
	var report: Dictionary = manager.record_footfall(_tile_chunks_out(40))
	assert_true(
		report["crossing"].is_empty(),
		"opening your eyes in the wilds is the briefing's moment, not a crossing card"
	)
	assert_gt(int(report["xp"]), 0, "but the ground is still new")


func test_walking_inside_one_ring_never_raises_a_card():
	for chunks_out in range(1, int(JourneyRing.RINGS[0]["outer_chunks"]) + 1):
		var report: Dictionary = manager.record_footfall(_tile_chunks_out(chunks_out))
		assert_eq(String(report["message"]), "", "%d chunks out is still the hearth" % chunks_out)
