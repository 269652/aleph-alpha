extends GutTest

const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## The two placeable structure ids TerrainRenderer needs distinct art for
## today (see item_catalog.gd's "placeable" kind items).
const STRUCTURE_IDS := ["campfire", "furnace"]

var generator: ProceduralStructureSprite


func before_each():
	generator = ProceduralStructureSprite.new()


func _pixel_diff_count(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count


func _average_color(image: Image) -> Color:
	var total := Color(0, 0, 0, 0)
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y)
			count += 1
	return total / count if count > 0 else Color()


func test_generated_image_has_the_expected_size():
	for structure_id in STRUCTURE_IDS:
		var image: Image = generator.generate_image(structure_id)
		assert_eq(image.get_width(), TerrainRenderer.TILE_SIZE, structure_id)
		assert_eq(image.get_height(), TerrainRenderer.TILE_SIZE, structure_id)


## Mirrors test_terrain_renderer.gd's
## test_build_tile_set_uses_real_procedural_art_not_a_flat_color_fill --
## proves this generator produces real shaded/detailed art, not a single
## solid color like the plain earth tile.
func test_generated_image_is_not_a_flat_color_fill():
	for structure_id in STRUCTURE_IDS:
		var image: Image = generator.generate_image(structure_id, 1)
		var first_pixel := image.get_pixel(0, 0)
		var all_same := true
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y) != first_pixel:
					all_same = false
		assert_false(all_same, "%s tile should use real procedural texture, not a flat color fill" % structure_id)


func test_generated_image_is_deterministic_per_id_and_seed():
	for structure_id in STRUCTURE_IDS:
		var first: Image = generator.generate_image(structure_id, 42)
		var second: Image = generator.generate_image(structure_id, 42)
		assert_eq(_pixel_diff_count(first, second), 0, structure_id)


func test_different_seeds_produce_a_visible_variation():
	for structure_id in STRUCTURE_IDS:
		var first: Image = generator.generate_image(structure_id, 1)
		var second: Image = generator.generate_image(structure_id, 2)
		assert_gt(_pixel_diff_count(first, second), 0, "%s seed should jitter shading" % structure_id)


func test_campfire_and_furnace_are_visually_distinct_from_each_other():
	var campfire: Image = generator.generate_image("campfire", 3)
	var furnace: Image = generator.generate_image("furnace", 3)
	assert_gt(
		_pixel_diff_count(campfire, furnace),
		TerrainRenderer.TILE_SIZE,
		"campfire and furnace should look clearly different"
	)


func test_campfire_and_furnace_average_color_is_distinct_from_plain_earth():
	var earth_color := TerrainRenderer.EARTH_COLOR
	for structure_id in STRUCTURE_IDS:
		var avg := _average_color(generator.generate_image(structure_id, 0))
		var distance := Vector3(avg.r, avg.g, avg.b).distance_to(
			Vector3(earth_color.r, earth_color.g, earth_color.b)
		)
		assert_gt(distance, 0.1, "%s should read as visually distinct from plain earth" % structure_id)


## Art-direction pass: campfire should read warm/fire-colored (red channel
## dominant), furnace should read as a cool/neutral stone grey rather than
## fire-colored -- see the task's brief ("warm/fire-colored ... cool
## stone/brick-grey").
func test_campfire_reads_warm_and_furnace_reads_cool():
	var campfire_avg := _average_color(generator.generate_image("campfire", 0))
	var furnace_avg := _average_color(generator.generate_image("furnace", 0))
	assert_gt(campfire_avg.r, campfire_avg.b, "campfire should read warm (red over blue)")
	assert_almost_eq(
		furnace_avg.r, furnace_avg.b, 0.15, "furnace should read as a neutral stone grey, not fire-colored"
	)


func test_generate_texture_returns_an_image_texture_of_matching_size():
	var texture: ImageTexture = generator.generate_texture("campfire", 1)
	assert_eq(texture.get_width(), TerrainRenderer.TILE_SIZE)
	assert_eq(texture.get_height(), TerrainRenderer.TILE_SIZE)


## Fail-safe default -- an id this generator doesn't recognize still returns
## a well-formed tile instead of crashing (same philosophy as
## TerrainRenderer.atlas_coords_for_modification's fallback to plain earth).
func test_unknown_structure_id_falls_back_without_crashing():
	var image: Image = generator.generate_image("mystery_structure", 1)
	assert_eq(image.get_width(), TerrainRenderer.TILE_SIZE)
	assert_eq(image.get_height(), TerrainRenderer.TILE_SIZE)


func test_structure_ids_constant_contains_campfire_and_furnace():
	assert_true(ProceduralStructureSprite.STRUCTURE_IDS.has("campfire"))
	assert_true(ProceduralStructureSprite.STRUCTURE_IDS.has("furnace"))
