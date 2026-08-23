extends GutTest

## SubmersionShader (see submersion_shader.gd) -- world-space partial-body
## tinting shared by the player and (eventually) other swimmers. Contract
## tests only; the drawn result can't be asserted headless, same limitation
## test_water_shader.gd and test_wind_sway.gd already work around.

const SubmersionShader = preload("res://src/rendering/submersion_shader.gd")

var submersion: SubmersionShader


func before_each():
	submersion = SubmersionShader.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := submersion.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


## Uses world position, not texture UV -- see the class doc for why: one
## material has to agree across several differently-sized/offset sprite
## parts (a player's body, head, arms), which only a shared coordinate space
## makes possible.
func test_shader_uses_world_space_not_texture_uv():
	var code: String = SubmersionShader.SHADER_CODE
	assert_string_contains(code, "MODEL_MATRIX")
	assert_string_contains(code, "world_pos")


func test_nothing_is_submerged_by_default():
	var material := submersion.make_material()
	# An enormous default Y means "below" is never reached at any sane world
	# scale -- the sprite renders exactly as it does on dry land.
	assert_gt(material.get_shader_parameter("water_world_y"), 100000.0)


func test_set_waterline_updates_the_shared_materials_uniform():
	var material := submersion.shared_material()
	submersion.set_waterline(42.0)
	assert_eq(material.get_shader_parameter("water_world_y"), 42.0)


func test_clear_waterline_resets_to_nothing_submerged():
	var material := submersion.shared_material()
	submersion.set_waterline(42.0)
	submersion.clear_waterline()
	assert_gt(material.get_shader_parameter("water_world_y"), 100000.0)


func test_shared_material_is_reused():
	assert_eq(submersion.shared_material(), submersion.shared_material())


## Matches ProceduralAnimalAnimation's swim tint exactly, so a submerged
## player and a submerged animal read as the same phenomenon.
func test_tint_color_matches_the_animal_swim_tint():
	const AnimScript = preload("res://src/rendering/procedural_animal_animation.gd")
	assert_eq(SubmersionShader.WATER_COLOR, AnimScript.WATER_COLOR)


## Partial, not a full replace or a hard cut -- the point of this whole
## module is that a submerged part still reads as the character's own body,
## tinted, not erased or recoloured solid.
func test_tint_and_fade_are_partial_not_total():
	assert_between(SubmersionShader.TINT_STRENGTH, 0.05, 0.95)
	assert_between(SubmersionShader.ALPHA_FADE, 0.0, 0.95)
