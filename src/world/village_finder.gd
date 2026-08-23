extends RefCounted

## Nearest-settlement search for the /village dev-console command (see
## World._handle_village_command / EarthChunkManager.find_nearest_village).
## Pure: takes the settlement generator and a duck-typed per-chunk biome
## lookup as arguments rather than reaching into EarthChunkManager itself, so
## the search order/termination can be tested without spinning up real
## terrain generation.

## How many candidate chunks a single ring at `radius` away (Chebyshev
## distance) has -- the ring itself, not the filled square.
func _ring_chunks(center: Vector2i, radius: int) -> Array:
	if radius == 0:
		return [center]
	var chunks: Array = []
	for x in range(center.x - radius, center.x + radius + 1):
		chunks.append(Vector2i(x, center.y - radius))
		chunks.append(Vector2i(x, center.y + radius))
	for y in range(center.y - radius + 1, center.y + radius):
		chunks.append(Vector2i(center.x - radius, y))
		chunks.append(Vector2i(center.x + radius, y))
	return chunks


## Searches outward from `start_chunk` in expanding square rings (Chebyshev
## distance, so a settlement 2 chunks away diagonally is no farther than one
## 2 chunks away in a cardinal direction) up to `max_radius_chunks`, and
## returns the first chunk_coord `settlement_generator.has_settlement_at`
## accepts, or null if none is found within range. `dominant_biome_for_chunk`
## is a Callable(Vector2i) -> String, so this stays decoupled from the real
## (expensive) terrain generator.
func find_nearest(
	start_chunk: Vector2i,
	max_radius_chunks: int,
	settlement_generator,
	dominant_biome_for_chunk: Callable
) -> Variant:
	for radius in range(max_radius_chunks + 1):
		for chunk_coord in _ring_chunks(start_chunk, radius):
			var biome: String = dominant_biome_for_chunk.call(chunk_coord)
			if settlement_generator.has_settlement_at(chunk_coord, biome):
				return chunk_coord
	return null
