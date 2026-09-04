extends GutTest

## See docs/concept/fishing.md#aquatic-population-model -- "Water area ->
## carrying capacity".

const WaterAreaSurvey = preload("res://src/world/water_area_survey.gd")
const Chunk = preload("res://src/world/chunk.gd")

var survey: WaterAreaSurvey


func before_each():
	survey = WaterAreaSurvey.new()


func _make_chunk(biome_name: String, temperature: float, size: int = 4) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.biome = PackedStringArray()
	chunk.biome.resize(size * size)
	chunk.biome.fill(biome_name)
	chunk.temperature = PackedFloat32Array()
	chunk.temperature.resize(size * size)
	chunk.temperature.fill(temperature)
	return chunk


func test_interior_water_cell_count_is_zero_for_an_all_land_chunk():
	assert_eq(survey.interior_water_cell_count(_make_chunk("grassland", 0.5)), 0)


## Rivers and lakes are overlay flags on land biome (docs/concept/
## hydrology.md); they count as water for fish exactly as ocean does.
func test_river_and_lake_cells_count_as_interior_water():
	var river := _make_chunk("grassland", 0.5, 4)
	river.is_river = PackedByteArray()
	river.is_river.resize(16)
	river.is_river.fill(1)
	assert_eq(survey.interior_water_cell_count(river), 4, "same as an all-ocean 4x4")
	var lake := _make_chunk("forest", 0.5, 4)
	lake.is_lake = PackedByteArray()
	lake.is_lake.resize(16)
	lake.is_lake.fill(1)
	assert_eq(survey.interior_water_cell_count(lake), 4)
	assert_true(survey.is_water_cell(river, 5))
	assert_false(survey.is_water_cell(_make_chunk("grassland", 0.5, 4), 5))


func test_interior_water_cell_count_excludes_the_chunk_edge():
	# 4x4 all-ocean: only the 2x2 interior (x,y in [1,2]) qualifies -- edge
	# cells' cross-chunk neighbors aren't knowable from this chunk alone.
	assert_eq(survey.interior_water_cell_count(_make_chunk("ocean", 0.5, 4)), 4)


func test_interior_water_cell_count_grows_with_a_larger_all_ocean_chunk():
	var small := survey.interior_water_cell_count(_make_chunk("ocean", 0.5, 4))
	var large := survey.interior_water_cell_count(_make_chunk("ocean", 0.5, 8))
	assert_gt(large, small)


func test_mean_interior_water_temperature_reads_the_water_cells():
	var chunk := _make_chunk("ocean", 0.8, 4)
	assert_almost_eq(survey.mean_interior_water_temperature(chunk), 0.8, 0.001)


func test_mean_interior_water_temperature_defaults_to_neutral_with_no_water():
	var chunk := _make_chunk("grassland", 0.9, 4)
	assert_almost_eq(survey.mean_interior_water_temperature(chunk), 0.5, 0.001)
