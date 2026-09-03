extends RefCounted

## Shared water-area math for the aquatic population model
## (docs/concept/fishing.md#aquatic-population-model) and fish rendering
## (FishRenderer) -- one definition of "open water" used by both the
## simulation and the spawn layer, so a cell that counts toward capacity is
## exactly a cell fish can visually occupy.

const Chunk = preload("res://src/world/chunk.gd")

const _NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


## True when (x, y) is an ocean cell whose 4 cardinal neighbors are all
## ocean too, and not on the chunk's edge (cross-chunk neighbors aren't
## knowable from a single chunk) -- interior water, never beach-adjacent.
func is_interior_water(chunk: Chunk, x: int, y: int) -> bool:
	if x <= 0 or y <= 0 or x >= chunk.width - 1 or y >= chunk.height - 1:
		return false
	if not is_water_cell(chunk, y * chunk.width + x):
		return false
	for offset in _NEIGHBOR_OFFSETS:
		if not is_water_cell(chunk, (y + offset.y) * chunk.width + (x + offset.x)):
			return false
	return true


## Ocean by biome, or a river or lake cell (docs/concept/hydrology.md:
## overlay flags on land biome) -- fish live in all three ("fish should
## also swim in rivers").
func is_water_cell(chunk: Chunk, index: int) -> bool:
	return chunk.biome[index] == "ocean" or chunk.blocks_ground_cover(index)


## Count of interior-water cells in this chunk -- the aquatic model's "water
## area" capacity input (see fishing.md).
func interior_water_cell_count(chunk: Chunk) -> int:
	var count := 0
	for y in chunk.height:
		for x in chunk.width:
			if is_interior_water(chunk, x, y):
				count += 1
	return count


## Average temperature across this chunk's interior-water cells -- the
## aquatic model's water-temperature capacity input (see fishing.md). 0.5
## (neutral) for a chunk with no interior water at all, so an all-land
## chunk's fish capacity is driven to zero by water_area_cells (0), not by
## an arbitrary temperature fallback.
func mean_interior_water_temperature(chunk: Chunk) -> float:
	var total := 0.0
	var count := 0
	for y in chunk.height:
		for x in chunk.width:
			if is_interior_water(chunk, x, y):
				total += chunk.temperature[y * chunk.width + x]
				count += 1
	if count == 0:
		return 0.5
	return total / count
