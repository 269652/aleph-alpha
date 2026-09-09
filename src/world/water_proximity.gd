extends RefCounted

## Pure ring-scan geometry for the ambient river-proximity layer (see
## docs/concept/soundscape.md's "Proximity layers" gap, and docs/concept/
## creature_and_footstep_audio.md for the sibling "individual nearby
## animals" half of the same live request: "fully build the soundscape
## out of individual nearby animals and environment"). No EarthChunkManager/
## Node dependency -- the same "pure model, thin wrapper" split every
## other audio-adjacent module in this codebase already uses.
##
## `is_water` is a plain Callable ((global_x: int, global_y: int) -> bool,
## the same shape `is_river_at_global`/`is_lake_at_global` already use)
## rather than a hard-coded call to either -- keeps this fully testable
## against synthetic, known coordinates instead of unpredictable real
## generated terrain (see test_water_proximity.gd's own doc comment).


## Checks outward ring by ring (Chebyshev square rings, radius 1, 2, 3...)
## rather than a filled disk, so a nearby hit short-circuits after only a
## few small rings instead of always paying for the full scan area -- the
## common case (nothing at all within range) still costs the full
## O(max_radius^2) scan either way, but that only runs on a throttled
## cadence (see NatureSoundscapePlayer's own REFRESH_INTERVAL_SECONDS),
## not every frame.
##
## Returns the real EUCLIDEAN distance in tiles to the nearest tile
## `is_water` accepts, or `INF` if nothing qualifies within
## `max_radius_tiles` -- Euclidean, not a ring index or taxicab count, so
## a diagonal hit doesn't read as artificially further than an
## axis-aligned one at the same true distance.
##
## A known, accepted approximation, not a silently-decided one: stopping
## at the first non-empty RING can occasionally return a hit slightly
## farther (in true Euclidean terms) than one sitting just past that
## ring's own edge -- a far corner of ring R can exceed R*sqrt(2) while
## ring R+1 starts at R+1, and for R>=3 those two ranges overlap. This
## never matters for what this exists to drive (a smooth ambient-volume
## ramp over dozens of tiles, not a precise measurement), so the simpler,
## cheaper single-ring-then-stop scan is used rather than the extra
## complexity of checking one more ring past the first hit to guarantee
## the true global minimum.
static func nearest_distance_tiles(
	global_x: int, global_y: int, max_radius_tiles: int, is_water: Callable
) -> float:
	if is_water.call(global_x, global_y):
		return 0.0
	for radius in range(1, max_radius_tiles + 1):
		var best_at_this_radius := INF
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # interior of the square, already checked at a smaller radius
				if is_water.call(global_x + dx, global_y + dy):
					best_at_this_radius = minf(best_at_this_radius, Vector2(dx, dy).length())
		if best_at_this_radius < INF:
			return best_at_this_radius
	return INF
