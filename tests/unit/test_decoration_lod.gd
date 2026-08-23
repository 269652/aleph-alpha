extends GutTest

## Decoration is drawn where it can be SEEN, not everywhere the simulation
## runs. The camera frames about 20x11 tiles; a chunk is 32 tiles square; and
## the world keeps 25-36 chunks loaded. Every grass tuft, bloom, shed seed and
## surfaced worm in all of them was instantiated and drawn -- measured live at
## ~2,900 decorative sprites for a view that can hold a few dozen, with frame
## rate visibly decaying as they accumulated (55.7 fps down to 49.1 across one
## run).

const DecorationLod = preload("res://src/rendering/decoration_lod.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const Player = preload("res://scenes/player.gd")


## The whole point: what the camera can actually show, derived from the real
## framing rather than guessed, so a zoom change can't silently leave the
## radius too small and start showing bare ground.
func test_the_visible_span_matches_what_the_camera_actually_frames():
	var span := DecorationLod.visible_half_span_tiles(Vector2(1280, 720), Player.TARGET_TILE_SCREEN_PX)
	assert_almost_eq(span.x, 10.0, 0.01, "half the screen in tiles across")
	assert_almost_eq(span.y, 5.625, 0.01, "and down")


## A radius has to cover the view from ANYWHERE inside the player's own
## chunk, including standing on its very edge looking outward.
func test_the_radius_covers_the_view_from_the_edge_of_a_chunk():
	var span := DecorationLod.visible_half_span_tiles(Vector2(1280, 720), Player.TARGET_TILE_SCREEN_PX)
	var radius := DecorationLod.radius_chunks(span, EarthChunkManager.CHUNK_SIZE)
	assert_gte(
		float(radius * EarthChunkManager.CHUNK_SIZE), maxf(span.x, span.y),
		"a player at their chunk's edge must still see decorated ground"
	)


func test_the_radius_is_smaller_than_what_the_world_keeps_loaded():
	var span := DecorationLod.visible_half_span_tiles(Vector2(1280, 720), Player.TARGET_TILE_SCREEN_PX)
	assert_lt(
		DecorationLod.radius_chunks(span, EarthChunkManager.CHUNK_SIZE),
		EarthChunkManager.LOAD_RADIUS,
		"otherwise this saves nothing at all"
	)


func test_the_chunk_underfoot_is_always_decorated():
	assert_true(DecorationLod.keeps_decoration(Vector2i(4, -2), Vector2i(4, -2), 1))


func test_the_ring_around_the_player_is_decorated():
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			assert_true(
				DecorationLod.keeps_decoration(Vector2i(dx, dy), Vector2i.ZERO, 1),
				"chunk %d,%d is next to the player" % [dx, dy]
			)


func test_chunks_the_player_cannot_possibly_see_are_not_decorated():
	assert_false(DecorationLod.keeps_decoration(Vector2i(2, 0), Vector2i.ZERO, 1))
	assert_false(DecorationLod.keeps_decoration(Vector2i(0, -3), Vector2i.ZERO, 1))


## Chebyshev, not Euclidean: chunks are squares and the view is a rectangle,
## so a diagonal neighbour is exactly as close as a side one.
func test_a_diagonal_neighbour_counts_as_near_as_a_side_one():
	assert_eq(
		DecorationLod.keeps_decoration(Vector2i(1, 1), Vector2i.ZERO, 1),
		DecorationLod.keeps_decoration(Vector2i(1, 0), Vector2i.ZERO, 1)
	)
