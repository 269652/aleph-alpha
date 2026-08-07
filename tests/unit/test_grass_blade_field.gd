extends GutTest

## GrassBladeField: per-chunk GPU micro-blades (see grass_blade_field.gd) --
## the individually-swaying 1px blades baked tiles can't animate.

const GrassBladeField = preload("res://src/rendering/grass_blade_field.gd")

var field := GrassBladeField.new()


func _biome(cells: Array) -> PackedStringArray:
	return PackedStringArray(cells)


func test_builds_blades_only_on_grassland_cells():
	var node := field.build_field(_biome(["grassland", "ocean", "grassland", "desert"]), 2, 2, 16, 7)
	assert_eq(node.multimesh.instance_count, 2 * GrassBladeField.BLADES_PER_CELL)
	node.free()


func test_returns_null_for_a_chunk_without_grassland():
	assert_null(field.build_field(_biome(["ocean", "desert"]), 2, 1, 16, 7))


func test_blades_carry_per_instance_phase_and_color():
	var node := field.build_field(_biome(["grassland"]), 1, 1, 16, 3)
	assert_true(node.multimesh.use_custom_data, "per-blade sway phase rides in INSTANCE_CUSTOM")
	assert_true(node.multimesh.use_colors)
	assert_true(node.material is ShaderMaterial)
	assert_string_contains(GrassBladeField.SHADER_CODE, "INSTANCE_CUSTOM")
	assert_string_contains(GrassBladeField.SHADER_CODE, "TIME")
	node.free()


func test_field_is_deterministic_per_seed():
	var a := field.build_field(_biome(["grassland"]), 1, 1, 16, 5)
	var b := field.build_field(_biome(["grassland"]), 1, 1, 16, 5)
	assert_eq(a.multimesh.get_instance_transform_2d(0), b.multimesh.get_instance_transform_2d(0))
	a.free()
	b.free()
