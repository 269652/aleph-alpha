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


# -- tile-precise cutoff (grass) ----------------------------------------------
#
# keeps_decoration's own chunk-level check is coarser than it looks: a chunk
# is CHUNK_SIZE tiles square while the camera only ever shows a much smaller
# window (its own doc comment: "three times what the camera can actually
# show"). Reported live: "optimize the grass blade rendering so it only draws
# what the player currently sees +2 tiles of buffer in every direction...
# to improve framerate" -- keeps_decoration_tile is the tighter, rectangular,
# sub-chunk cutoff EarthChunkManager applies to grass specifically, layered
# ON TOP of (never instead of) the existing chunk-level gate.

func test_keeps_decoration_tile_is_true_at_the_players_own_tile():
	assert_true(DecorationLod.keeps_decoration_tile(Vector2i(5, -3), Vector2i(5, -3), Vector2(10.0, 5.0), 2))


func test_keeps_decoration_tile_is_true_exactly_at_the_span_plus_buffer_edge():
	# half_span (10, 5) + buffer 2 -> kept up to (12, 7) away on each axis.
	assert_true(DecorationLod.keeps_decoration_tile(Vector2i(12, 0), Vector2i.ZERO, Vector2(10.0, 5.0), 2))
	assert_true(DecorationLod.keeps_decoration_tile(Vector2i(0, 7), Vector2i.ZERO, Vector2(10.0, 5.0), 2))


func test_keeps_decoration_tile_is_false_just_beyond_the_span_plus_buffer_edge():
	assert_false(DecorationLod.keeps_decoration_tile(Vector2i(13, 0), Vector2i.ZERO, Vector2(10.0, 5.0), 2))
	assert_false(DecorationLod.keeps_decoration_tile(Vector2i(0, 8), Vector2i.ZERO, Vector2(10.0, 5.0), 2))


## Rectangular, not circular: a tile can be far away on BOTH axes at once and
## still count as kept, as long as each axis alone stays within its own
## bound -- matching the camera's own rectangular view, the same philosophy
## keeps_decoration's own Chebyshev (not Euclidean) chunk check already uses.
func test_keeps_decoration_tile_is_rectangular_not_circular():
	assert_true(DecorationLod.keeps_decoration_tile(Vector2i(12, 7), Vector2i.ZERO, Vector2(10.0, 5.0), 2))


func test_keeps_decoration_tile_buffer_widens_the_kept_area():
	var tile := Vector2i(11, 0)
	assert_false(DecorationLod.keeps_decoration_tile(tile, Vector2i.ZERO, Vector2(10.0, 5.0), 0))
	assert_true(DecorationLod.keeps_decoration_tile(tile, Vector2i.ZERO, Vector2(10.0, 5.0), 2))


func test_keeps_decoration_tile_half_span_is_rounded_up_not_truncated():
	# A fractional span (matches real camera framing, e.g. 5.625 tiles down)
	# must round UP before the buffer is added, or a tile the camera can
	# genuinely still see gets dropped a fraction of a tile early.
	assert_true(DecorationLod.keeps_decoration_tile(Vector2i(0, 6), Vector2i.ZERO, Vector2(10.0, 5.625), 0))
