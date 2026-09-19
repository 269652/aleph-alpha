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
	dominant_biome_for_chunk: Callable,
	would_settle := Callable()
) -> Variant:
	for radius in range(max_radius_chunks + 1):
		for chunk_coord in _ring_chunks(start_chunk, radius):
			var biome: String = dominant_biome_for_chunk.call(chunk_coord)
			if not settlement_generator.has_settlement_at(chunk_coord, biome):
				continue
			# has_settlement_at is the procedural ROLL -- whether a
			# settlement is meant to be here -- and knows nothing about
			# whether the ground can house one. A village only settles
			# where there is room for all of it (VillageRenderer,
			# docs/concept/building.md), so the two genuinely disagree, and
			# sending the player to a chunk where they do is exactly the
			# reported "It teleports me to where no village is".
			if would_settle.is_valid() and not would_settle.call(chunk_coord):
				continue
			return chunk_coord
	return null


## What /village says it did -- the chunk it landed you in and what is really
## standing there (docs/concept/village_growth.md, Mechanism 6).
##
## Reported three times, the third with the verification already in: *"It
## teleports me to where no village is"*, *"/village teleports me to an empty
## field..."*, *"It still teleports me to the same empty spot"*. A command
## that says "Teleported to the nearest village" and nothing else leaves a
## player no way to tell WHICH thing is wrong -- the wrong chunk, no
## buildings recorded, or buildings recorded and never drawn. Naming the
## chunk and the count makes the next report evidence rather than another
## round of guessing.
##
## Zero is spelled out rather than counted, because a village with nothing
## standing in it is the bug being hunted, not a detail.
static func teleport_report(chunk_coord: Vector2i, building_count: int) -> String:
	if building_count <= 0:
		return "Landed in chunk (%d, %d) -- no buildings standing there." % [
			chunk_coord.x, chunk_coord.y
		]
	return "Teleported to the village in chunk (%d, %d): %d building%s standing." % [
		chunk_coord.x, chunk_coord.y, building_count, "" if building_count == 1 else "s"
	]
