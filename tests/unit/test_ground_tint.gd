extends GutTest

## GroundTint: the world-space low-frequency noise shader on the terrain
## TileMapLayer. Every tile of a biome shares the same average color, so
## however good the per-tile art is, a field reads as a uniform printed
## carpet -- the "patterned and artificial" complaint. This shader drifts the
## ground's brightness in soft, tile-spanning patches (wavelength ~10 tiles),
## the way real meadows shift between lusher and drier grass. Contract tests
## only -- the visual result can't be asserted headless.

const GroundTint = preload("res://src/rendering/ground_tint.gd")
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const TerrainAtlasCache = preload("res://src/rendering/terrain_atlas_cache.gd")

const SEASON_CACHE_PATH := "user://test_ground_tint_season_atlas.png"
const SEASON_CACHE_VERSION_PATH := "user://test_ground_tint_season_atlas_version.txt"

var tint := GroundTint.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := tint.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


func test_shader_samples_noise_in_world_space():
	# World-space (via MODEL_MATRIX), not screen-space: the pattern must stay
	# glued to the ground as the camera moves, not swim across it.
	var code: String = GroundTint.SHADER_CODE
	assert_string_contains(code, "shader_type canvas_item")
	assert_string_contains(code, "MODEL_MATRIX")
	assert_string_contains(code, "void fragment()")


func test_tint_strength_is_subtle_and_pinned():
	# A gentle drift, not camo blotches: strength stays well under 20%.
	assert_lte(GroundTint.TINT_STRENGTH, 0.2)
	assert_gt(GroundTint.TINT_STRENGTH, 0.0)
	var material := tint.make_material()
	assert_eq(material.get_shader_parameter("tint_strength"), GroundTint.TINT_STRENGTH)


func test_noise_wavelength_spans_multiple_tiles():
	# The whole point is variation BIGGER than one tile: wavelength (1/scale)
	# must span at least 4 tiles' worth of pixels, else it's just more speckle.
	assert_lte(GroundTint.NOISE_SCALE, 1.0 / (4.0 * 16.0))


func test_shared_material_is_reused():
	assert_eq(tint.shared_material(), tint.shared_material())


## The tint is a broad wash, not a per-pixel effect: evaluating its two noise
## octaves per FRAGMENT cost eight sin-based hashes on every pixel of ground
## on screen (~16M sin ops per frame at 1080p, measured as one of the three
## biggest costs in the frame). A world tile spans about a tenth of a noise
## cell, so per-vertex sampling is very nearly the same field for a fraction
## of the work.
func test_the_tint_noise_is_computed_per_vertex_not_per_pixel():
	var code: String = GroundTint.SHADER_CODE
	var vertex_body := code.substr(code.find("void vertex()"), code.find("void fragment()") - code.find("void vertex()"))
	var fragment_body := code.substr(code.find("void fragment()"))
	assert_string_contains(vertex_body, "value_noise", "the noise belongs in the vertex stage")
	assert_false(
		fragment_body.contains("value_noise"),
		"no per-pixel noise: the fragment stage should only apply the interpolated tint"
	)


# -- the ground carries the season ------------------------------------------

## The terrain layer wore high summer all year while the canopies above it
## turned (see SeasonalFoliage / docs/concept/seasons.md): bare winter trees
## standing on a bright green lawn. The season arrives as one live uniform on
## the material the whole layer already wears.
func test_the_terrain_shader_takes_a_season_tint_uniform():
	var code: String = GroundTint.SHADER_CODE
	assert_string_contains(code, "uniform vec3 season_tint")


## One material covers the WHOLE terrain layer, water included -- an
## unweighted multiply would turn the ocean and the sand brown in autumn.
func test_the_terrain_shader_gates_the_season_tint_on_greenness_so_water_never_browns():
	var code: String = GroundTint.SHADER_CODE
	var fragment_body := code.substr(code.find("void fragment()"))
	assert_string_contains(fragment_body, "season_tint", "the season is applied per pixel")
	assert_string_contains(
		fragment_body, "COLOR.g - max(COLOR.r, COLOR.b)",
		"the same greenness expression SeasonalFoliage.greenness_of computes"
	)
	assert_string_contains(fragment_body, "mix(", "gated, not multiplied outright")


## One constant, two languages: the GDScript the tests exercise and the GLSL
## the GPU runs must not be able to drift apart.
func test_the_shaders_greenness_gain_is_the_one_in_seasonal_foliage():
	assert_string_contains(
		GroundTint.SHADER_CODE, "* %s" % SeasonalFoliage.GREENNESS_GAIN
	)


## Mirrors IllustratedGrassPatch's own wind_strength convention: the value is
## remembered and re-applied when the material is lazily built, so a caller
## that sets the season first does not silently lose it.
func test_set_season_tint_survives_being_called_before_the_material_is_built():
	var fresh := GroundTint.new()
	var winter := SeasonalFoliage.tint_for_season("winter")
	fresh.set_season_tint(winter)
	var parameter = fresh.make_material().get_shader_parameter("season_tint")
	assert_almost_eq(parameter.x, winter.r, 0.0001)
	assert_almost_eq(parameter.y, winter.g, 0.0001)
	assert_almost_eq(parameter.z, winter.b, 0.0001)


## The terrain layer is assigned `shared_material()` once, from an instance
## the assigning code does not keep. If the shared material were per-instance,
## pushing the season from any other holder would set a uniform on a material
## nothing renders -- a silent no-op with no way to see it in a test.
func test_the_shared_material_is_the_same_one_for_every_instance():
	assert_eq(GroundTint.new().shared_material(), GroundTint.new().shared_material())
	var pusher := GroundTint.new()
	var autumn := SeasonalFoliage.tint_for_season("autumn")
	pusher.set_season_tint(autumn)
	var landed = GroundTint.new().shared_material().get_shader_parameter("season_tint")
	assert_almost_eq(landed.x, autumn.r, 0.0001)


## THE reason this is a shader uniform and not baked art. The terrain atlas is
## a single ~5MB image cached on disk under ONE version string with no
## per-tile invalidation, and build_tile_set hands the live TileMapLayer the
## TileSet built from it. A season baked into those pixels would mean four
## atlases, four full bakes, and a whole TileSet rebuild landing mid-session
## at the moment the season turned. Pushing a uniform invalidates nothing --
## pinned here so a future "just bake it" never silently makes the cache
## season-dependent without also making it season-KEYED.
func test_the_season_never_enters_the_atlas_cache_key_so_a_cached_atlas_cannot_go_stale():
	var cache := TerrainAtlasCache.new()
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.36, 0.74, 0.22, 1.0))
	cache.save(image, TerrainRenderer.ATLAS_VERSION, SEASON_CACHE_PATH, SEASON_CACHE_VERSION_PATH)

	for season in SeasonCycle.SEASONS:
		assert_false(
			TerrainRenderer.ATLAS_VERSION.contains(season),
			"the atlas version must not name a season -- the season is not baked"
		)
		GroundTint.new().set_season_tint(SeasonalFoliage.tint_for_season(season))
		assert_true(
			cache.has_valid_cache(
				TerrainRenderer.ATLAS_VERSION, SEASON_CACHE_PATH, SEASON_CACHE_VERSION_PATH
			),
			"a cached atlas must stay valid in %s -- the season never touches it" % season
		)

	DirAccess.remove_absolute(SEASON_CACHE_PATH)
	DirAccess.remove_absolute(SEASON_CACHE_VERSION_PATH)
