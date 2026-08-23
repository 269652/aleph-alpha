extends RefCounted

## Which chunks are close enough to the player to be worth DECORATING --
## drawing their grass tufts, blooms, shed seeds and surfaced worms.
##
## The simulation and the decoration had the same footprint: every chunk the
## world kept loaded (EarthChunkManager.LOAD_RADIUS / UNLOAD_RADIUS, 25-36
## chunks in practice) also got a Sprite2D per tuft, bloom, seed and worm.
## The camera frames about 20x11 tiles and a chunk is 32 tiles square, so the
## player can never see even one whole chunk, and the other two dozen were
## drawn for nobody. Measured live: ~2,900 decorative sprites, with the frame
## rate visibly decaying as they accumulated over a run (55.7 fps to 49.1).
##
## The simulation still runs everywhere -- grass keeps growing and worms keep
## surfacing in chunks the player has walked away from, which is the whole
## point of simulating a living world. Only the *drawing* is scoped to what
## can be seen, so walking back finds the meadow the sim actually grew.
##
## Pure and engine-free so the radius is a derived, tested property rather
## than an eyeballed number that quietly stops covering the screen the next
## time the camera framing changes.


## Half of what the camera frames, in world tiles: how far the view reaches
## from the player in each direction.
##
## Derived from the real framing (Player.TARGET_TILE_SCREEN_PX states how big
## one tile reads on screen, and CAMERA_ZOOM is itself derived from that)
## rather than from a zoom number, so this stays correct on its own terms.
static func visible_half_span_tiles(viewport_size: Vector2, tile_screen_px: float) -> Vector2:
	if tile_screen_px <= 0.0:
		return Vector2.ZERO
	return viewport_size * 0.5 / tile_screen_px


## How many chunks out from the player's own chunk must stay decorated.
##
## Measured from the player's CHUNK, not from the player: they can stand
## anywhere in it, including hard against an edge looking outward, so the
## radius has to cover the view from the worst case. One chunk out covers a
## view reaching up to CHUNK_SIZE tiles past the chunk boundary, which is
## three times what the camera can actually show.
static func radius_chunks(half_span_tiles: Vector2, chunk_size: int) -> int:
	if chunk_size <= 0:
		return 0
	var reach: float = maxf(half_span_tiles.x, half_span_tiles.y)
	return maxi(1, int(ceil(reach / float(chunk_size))))


## Whether `chunk_coord` is close enough to the player's chunk to be drawn.
##
## Chebyshev distance, matching how the world loads and unloads chunks:
## chunks are squares and the view is a rectangle, so a diagonal neighbour is
## exactly as close as a side one.
static func keeps_decoration(
	chunk_coord: Vector2i, center_chunk: Vector2i, radius: int
) -> bool:
	return maxi(absi(chunk_coord.x - center_chunk.x), absi(chunk_coord.y - center_chunk.y)) <= radius
