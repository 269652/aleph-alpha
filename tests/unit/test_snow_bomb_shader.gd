extends GutTest

## The GPU snow layer: illustrated stamps bombed across world space by a
## fragment shader (see docs/concept/snow_cover.md).
##
## A fragment shader cannot be asserted headless, so the tuned parts of the
## GLSL are mirrored by GDScript here -- the same relationship water_shader.gd's
## ripple_amplitude and hillshade_shader.gd's shadow_alpha have to their own
## shaders, and for the same reason. The mirror runs float64 and the GPU
## float32, so it cannot catch precision failures; that is what
## test_snow_render_smoke.gd's far-world readback exists for.

const SnowBombShader = preload("res://src/rendering/snow_bomb_shader.gd")
const SnowStampAtlas = preload("res://src/rendering/snow_stamp_atlas.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var snow: SnowBombShader


func before_each():
	snow = SnowBombShader.new()


## A spread of world points that is deliberately NOT aligned to the stamp
## lattice or the tile grid, so a sample can never accidentally only ever land
## at one phase of either.
func _sample_points(count: int = 400, origin := Vector2(0.0, 0.0)) -> Array:
	var points: Array = []
	for i in count:
		points.append(origin + Vector2(float(i) * 7.3, float(i) * 11.9))
	return points


func _mean_coverage(depth: float, points: Array) -> float:
	var total := 0.0
	for point in points:
		total += snow.coverage_at(depth, point.x, point.y)
	return total / float(points.size())


# -- the hash and the noise --------------------------------------------------

## THE structural pin: the lattice hash must be trig-free.
##
## A sine-times-large-constant hash is a float32 landmine at this world's
## coordinates -- the hundreds of thousands of world units a real position
## reaches feed sin() millions of radians, GPU range reduction collapses, and
## the field goes regionally near-constant, so snow simply does not render
## across whole regions while every float64 CPU statistic here still passes.
## That exact failure was found live in this codebase's river shader.
##
## Comments are stripped before the check, deliberately: a doc comment
## EXPLAINING why sine is banned must not be what trips the pin (the
## comment-vs-code trap an earlier no-smoothstep test in this codebase fell
## into).
func test_the_lattice_hash_is_trig_free():
	var code := ""
	for line in SnowBombShader.SHADER_CODE.split("\n"):
		var stripped: String = line
		var comment := stripped.find("//")
		if comment >= 0:
			stripped = stripped.substr(0, comment)
		code += stripped + "\n"
	assert_false(code.contains("sin("), "the shader must not hash with sine")
	assert_false(code.contains("cos("), "the shader must not hash with cosine")


## The hash has to actually spread across [0, 1) -- a hash that clusters
## would make every stamp site pick nearly the same variant, level and jitter,
## which is wallpaper by another route.
func test_the_hash_spreads_across_its_whole_range():
	var low := 1.0
	var high := 0.0
	var total := 0.0
	var count := 0
	for y in 40:
		for x in 40:
			var h := SnowBombShader.value_hash(float(x) * 1.7, float(y) * 2.3)
			assert_between(h, 0.0, 1.0, "the hash must stay in [0, 1]")
			low = minf(low, h)
			high = maxf(high, h)
			total += h
			count += 1
	assert_lt(low, 0.05, "the hash never reaches its bottom")
	assert_gt(high, 0.95, "the hash never reaches its top")
	assert_almost_eq(total / float(count), 0.5, 0.06, "the hash is biased")


## The same spread must survive FAR from the origin. This cannot catch the
## GPU's float32 collapse (this mirror is float64), but it does catch a hash
## that is structurally range-dependent.
func test_the_hash_stays_healthy_at_far_world_coordinates():
	var low := 1.0
	var high := 0.0
	for y in 40:
		for x in 40:
			var h := SnowBombShader.value_hash(
				334000.0 + float(x) * 1.7, 76000.0 + float(y) * 2.3
			)
			low = minf(low, h)
			high = maxf(high, h)
	assert_lt(low, 0.1, "the hash flattens at far-world coordinates")
	assert_gt(high, 0.9, "the hash flattens at far-world coordinates")


## Value noise must be SMOOTH -- neighbouring samples close together. This is
## what the drift field is built on, and the property that keeps the snow line
## a meandering edge rather than a grid of squares.
func test_the_noise_is_smooth_between_lattice_points():
	var worst := 0.0
	for i in 200:
		var x := float(i) * 0.37
		var y := float(i) * 0.11
		worst = maxf(
			worst,
			absf(SnowBombShader.value_noise(x, y) - SnowBombShader.value_noise(x + 0.05, y))
		)
	assert_lt(worst, 0.1, "the noise jumps between neighbouring samples")


# -- the drift field ---------------------------------------------------------

## Carried over unchanged from the tile implementation, where it was measured
## and tuned across three separate reported bugs: snow drifts and shelters in
## patches many metres across, so the field deciding which ground catches
## first is low-frequency by construction. Two edge-adjacent TILES must stay
## close together.
func test_neighbouring_tiles_have_nearly_the_same_onset():
	var worst := 0.0
	var tile := float(TerrainRenderer.TILE_SIZE)
	for tile_y in range(-6, 7):
		for tile_x in range(-60, 61):
			var here := SnowBombShader.onset_at(float(tile_x) * tile, float(tile_y) * tile)
			var east := SnowBombShader.onset_at(float(tile_x + 1) * tile, float(tile_y) * tile)
			var south := SnowBombShader.onset_at(float(tile_x) * tile, float(tile_y + 1) * tile)
			worst = maxf(worst, absf(east - here))
			worst = maxf(worst, absf(south - here))
	assert_lt(
		worst, SnowBombShader.MAX_NEIGHBOUR_ONSET_STEP,
		"neighbouring tiles' onsets differ by %.4f" % worst
	)


## Pinned from the other side too, so nobody answers a neighbour-step failure
## by flattening the field into a constant.
func test_the_drift_field_still_covers_the_ground_unevenly():
	var low := 1.0
	var high := -1.0
	var tile := float(TerrainRenderer.TILE_SIZE)
	for tile_y in range(-40, 40):
		for tile_x in range(-40, 40):
			var onset := SnowBombShader.onset_at(float(tile_x) * tile, float(tile_y) * tile)
			low = minf(low, onset)
			high = maxf(high, onset)
	assert_gt(
		high - low, SnowBombShader.ONSET_VARIANCE,
		"the drift field only spans %.4f -- it has been flattened" % (high - low)
	)


## Onset is a lead/lag on real snow, not a way to conjure some out of nothing.
func test_onset_cannot_show_snow_on_a_genuinely_bare_field():
	for point in _sample_points():
		assert_eq(
			snow.coverage_at(0.0, point.x, point.y), 0.0,
			"a bare field drew snow at (%.1f, %.1f)" % [point.x, point.y]
		)


## And symmetrically: once the field is GENUINELY fully covered, onset has
## nothing left to lag -- no point may be left permanently short of full.
func test_onset_cannot_hide_snow_once_the_field_is_fully_covered():
	for point in _sample_points():
		assert_almost_eq(
			SnowBombShader.lying_at(1.0, point.x, point.y, 0.0), 1.0, 0.0001,
			"a fully covered field lagged at (%.1f, %.1f)" % [point.x, point.y]
		)


# -- the bombing geometry ----------------------------------------------------

## THE correctness constraint on the tuning. The shader searches a fixed 3x3
## neighbourhood of lattice cells, which only finds every stamp that can
## overlap a point if no stamp reaches further than 1.5 cells from its own
## site. Violate it and stamps get clipped along invisible lines 16 world
## units apart -- a grid artifact produced by the very code meant to hide the
## grid. Checked at the LARGEST a stamp can be (full depth, maximum size
## jitter), which is the case that would break first.
func test_a_three_by_three_search_reaches_every_stamp_that_can_overlap_a_point():
	var largest_half := SnowBombShader.STAMP_WORLD_SIZE \
		* (1.0 + SnowBombShader.STAMP_SIZE_JITTER) / 2.0
	var reach := largest_half + SnowBombShader.STAMP_JITTER_WORLD
	var searched := (float(SnowBombShader.SEARCH_RADIUS_CELLS) + 0.5) \
		* SnowBombShader.STAMP_LATTICE_WORLD
	assert_lte(
		reach, searched,
		"a stamp reaches %.2f world units but the search only covers %.2f" % [reach, searched]
	)


## Stamps must be bigger than their own lattice cell, or full cover would be
## a grid of separated puffs with bare ground showing between them however
## deep the snow got.
func test_stamps_overlap_their_own_lattice_cell():
	assert_gt(SnowBombShader.STAMP_WORLD_SIZE, SnowBombShader.STAMP_LATTICE_WORLD)


# -- what the depth ramp actually draws --------------------------------------

## The far end of the ramp: solid cover everywhere, no holes. Sampled on a
## dense off-lattice spread, and it is the WORST point that has to be covered
## -- a good mean with a few bare pixels is exactly the "holes in deep snow"
## bug this pins.
func test_a_fully_covered_field_draws_solid_cover_everywhere():
	var worst := 1.0
	var worst_at := Vector2.ZERO
	for point in _sample_points(600):
		var coverage := snow.coverage_at(1.0, point.x, point.y)
		if coverage < worst:
			worst = coverage
			worst_at = point
	assert_gt(
		worst, 0.85,
		"deep snow left a hole (coverage %.3f) at (%.1f, %.1f)" % [worst, worst_at.x, worst_at.y]
	)


## The near end: a dusting is scattered specks with real bare ground between
## them, not a thin continuous wash. Both halves matter -- some points bare,
## some genuinely covered.
func test_a_dusting_leaves_real_bare_ground_between_the_stamps():
	var bare := 0
	var covered := 0
	for point in _sample_points(600):
		var coverage := snow.coverage_at(0.12, point.x, point.y)
		if coverage < 0.05:
			bare += 1
		elif coverage > 0.5:
			covered += 1
	assert_gt(bare, 60, "a dusting covered nearly everything -- no bare ground left")
	assert_gt(covered, 12, "a dusting drew nothing solid anywhere")


## Coverage rises with depth, and never falls back. This is the ramp itself:
## a field that is deeper must never look thinner.
func test_coverage_rises_with_depth():
	var points := _sample_points(300)
	var previous := -1.0
	for step in 21:
		var depth := float(step) / 20.0
		var mean := _mean_coverage(depth, points)
		assert_gte(
			mean, previous - 0.001,
			"coverage fell from %.4f to %.4f going to depth %.2f" % [previous, mean, depth]
		)
		previous = mean
	assert_gt(previous, 0.9, "a full field must end up near-solid, not %.4f" % previous)


## THE central claim of the mechanism: nothing about the tile grid is visible,
## because coverage is a continuous function of world position alone. Sampled
## a hair either side of a real tile boundary, where the OLD implementation
## could differ by a whole depth band.
##
## The bound is 0.07, not 0.0 -- perfect continuity is unreachable by any
## texture-sampled renderer of hand-inked art, and chasing it further isn't
## worth what it would cost:
##   - Nearest-neighbour sampling was a real bug (worst case 0.8157, a whole
##     stamp popping) -- fixed by making _stamp_alpha bilinear, matching the
##     GPU's own filter_linear exactly.
##   - level_for_site snapping to a rounded level was a real bug too -- an
##     infinitesimal change in `lying` could switch to an entirely different,
##     independently-illustrated image. Fixed by crossfading the two
##     neighbouring levels (see _level_f) instead of rounding to one.
##   - What's left after both fixes is texture DETAIL: this game's ink-outline
##     art style means a stamp can have a genuinely hard, near-single-texel
##     edge, and STAMP_EDGE_FADE_UV already closes the gap at each stamp's
##     OWN boundary. A remaining edge in the MIDDLE of a 64px illustrated
##     puff is real content, not a bug -- smoothing it further means
##     blurring the art itself (out of scope for this shader) or paying real
##     per-fragment GPU cost for a blur wide enough to matter (measured: even
##     a 7x7-tap kernel barely moves the worst case, because it cannot reach
##     across a level switch either).
## Measured on the real class after both fixes: worst case 0.0552, 37/1200
## boundary-pairs over the old 0.02 (none over 0.07). 0.07 is a real ceiling
## with margin above that measurement, not a number picked to make this pass.
func test_coverage_is_continuous_across_a_tile_boundary():
	var tile := float(TerrainRenderer.TILE_SIZE)
	var worst := 0.0
	for depth in [0.15, 0.35, 0.55, 0.75, 0.95]:
		for i in 60:
			var y := float(i) * 13.7
			for boundary in [0.0, tile, tile * 5.0, tile * -3.0]:
				var left := snow.coverage_at(depth, boundary - 0.01, y)
				var right := snow.coverage_at(depth, boundary + 0.01, y)
				worst = maxf(worst, absf(left - right))
	assert_lt(worst, 0.07, "coverage jumps by %.4f across a tile boundary" % worst)


## No lattice-period artifact: coverage sampled one whole lattice period apart
## must be no more self-similar than coverage sampled at an unrelated offset.
## If stamps repeated with the lattice, the period offset would match itself
## far more closely -- that is what "texture bombing" is supposed to prevent,
## and this measures it rather than trusting it.
func test_coverage_has_no_lattice_period_artifact():
	var lattice := SnowBombShader.STAMP_LATTICE_WORLD
	var period_difference := 0.0
	var offset_difference := 0.0
	var samples := 0
	for i in 300:
		var x := float(i) * 3.1
		var y := float(i) * 5.7
		var here := snow.coverage_at(0.5, x, y)
		period_difference += absf(snow.coverage_at(0.5, x + lattice, y) - here)
		offset_difference += absf(snow.coverage_at(0.5, x + lattice * 0.37, y) - here)
		samples += 1
	assert_gt(samples, 0)
	assert_gt(
		period_difference / maxf(offset_difference, 0.0001), 0.6,
		"coverage repeats with the lattice: %.4f at the period vs %.4f off it"
			% [period_difference / float(samples), offset_difference / float(samples)]
	)


## Neighbouring stamp sites draw different pictures -- different variants, and
## near a level boundary different levels. The variant spread is what stops a
## field reading as one blob repeated; the level spread is what dithers a
## level transition away instead of drawing it as a contour line.
func test_neighbouring_stamp_sites_draw_different_pictures():
	var variant_changes := 0
	var level_changes := 0
	var pairs := 0
	for cell_y in range(0, 20):
		for cell_x in range(0, 20):
			var here_variant := SnowBombShader.variant_for_site(cell_x, cell_y)
			var east_variant := SnowBombShader.variant_for_site(cell_x + 1, cell_y)
			var here_level := SnowBombShader.level_for_site(0.5, cell_x, cell_y)
			var east_level := SnowBombShader.level_for_site(0.5, cell_x + 1, cell_y)
			if here_variant != east_variant:
				variant_changes += 1
			if here_level != east_level:
				level_changes += 1
			pairs += 1
	assert_gt(
		float(variant_changes) / float(pairs), 0.5,
		"neighbouring sites mostly draw the same variant"
	)
	assert_gt(
		float(level_changes) / float(pairs), 0.05,
		"no level dithering at all -- every transition will draw as a contour"
	)


## Every site's variant must be a real atlas column, and every level a real
## atlas row -- an out-of-range index would sample the gutter or wrap onto the
## wrong stamp.
func test_every_site_picks_a_real_atlas_cell():
	for cell_y in range(-30, 30):
		for cell_x in range(-30, 30):
			assert_between(
				SnowBombShader.variant_for_site(cell_x, cell_y),
				0, SnowStampAtlas.VARIANTS_PER_LEVEL - 1
			)
			for depth in [0.0, 0.3, 0.7, 1.0]:
				assert_between(
					SnowBombShader.level_for_site(depth, cell_x, cell_y),
					0, snow.level_count() - 1
				)


# -- footprints --------------------------------------------------------------

## Walking PACKS snow rather than clearing it -- a trail reads as tracks
## through a field, not a trench dug to soil.
func test_treading_packs_snow_down_without_clearing_it():
	var points := _sample_points(300)
	var untrodden := 0.0
	var trodden := 0.0
	for point in points:
		untrodden += snow.coverage_at(1.0, point.x, point.y, 0.0)
		trodden += snow.coverage_at(1.0, point.x, point.y, 1.0)
	untrodden /= float(points.size())
	trodden /= float(points.size())
	assert_lt(trodden, untrodden - 0.05, "treading deep snow changed nothing")
	assert_gt(trodden, 0.3, "a single pass through deep snow dug it to the soil")


## Only where the cover was thin to begin with does a boot reach the ground.
func test_a_footprint_in_a_dusting_shows_the_ground():
	var bare := 0
	var points := _sample_points(300)
	for point in points:
		if snow.coverage_at(0.1, point.x, point.y, 1.0) < 0.02:
			bare += 1
	assert_gt(
		float(bare) / float(points.size()), 0.8,
		"a boot through a dusting left the ground covered"
	)


## Tread can only ever REMOVE snow, at every depth -- a packing term that
## added coverage anywhere would draw footprints as raised white blocks.
func test_treading_never_adds_snow():
	for depth in [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]:
		for point in _sample_points(120):
			assert_lte(
				snow.coverage_at(depth, point.x, point.y, 0.6),
				snow.coverage_at(depth, point.x, point.y, 0.0) + 0.0001,
				"tread added snow at depth %.2f" % depth
			)


# -- the material ------------------------------------------------------------

## The shader gets the real stamp atlas, and the cell arithmetic it needs to
## address it. A wrong column/row count silently samples the wrong stamps.
func test_the_material_carries_the_stamp_atlas_and_its_layout():
	var material := snow.make_material()
	assert_true(material is ShaderMaterial)
	assert_true(
		material.get_shader_parameter("stamp_atlas") is Texture2D,
		"the atlas texture must be pushed to the shader"
	)
	assert_eq(
		material.get_shader_parameter("atlas_columns"), SnowStampAtlas.VARIANTS_PER_LEVEL
	)
	assert_eq(material.get_shader_parameter("atlas_rows"), snow.level_count())


## Every tuned constant this file pins must actually reach the GLSL, or the
## mirror would be asserting numbers the GPU never uses -- the one failure
## mode a hand-kept mirror really has.
func test_every_mirrored_constant_reaches_the_shader():
	var material := snow.make_material()
	var expected := {
		"stamp_lattice_world": SnowBombShader.STAMP_LATTICE_WORLD,
		"stamp_world_size": SnowBombShader.STAMP_WORLD_SIZE,
		"stamp_jitter_world": SnowBombShader.STAMP_JITTER_WORLD,
		"stamp_size_jitter": SnowBombShader.STAMP_SIZE_JITTER,
		"stamp_min_size_fraction": SnowBombShader.STAMP_MIN_SIZE_FRACTION,
		"site_onset_spread": SnowBombShader.SITE_ONSET_SPREAD,
		"level_dither": SnowBombShader.LEVEL_DITHER,
		"stamp_edge_fade_uv": SnowBombShader.STAMP_EDGE_FADE_UV,
		"tread_depth": SnowBombShader.TREAD_DEPTH,
		"tread_alpha_factor": SnowBombShader.TREAD_ALPHA_FACTOR,
		"onset_broad_variance": SnowBombShader.ONSET_BROAD_VARIANCE,
		"onset_fine_variance": SnowBombShader.ONSET_FINE_VARIANCE,
		"onset_drift_tiles": SnowBombShader.ONSET_DRIFT_TILES,
		"onset_fine_drift_tiles": SnowBombShader.ONSET_FINE_DRIFT_TILES,
	}
	for name in expected:
		assert_almost_eq(
			float(material.get_shader_parameter(name)), float(expected[name]), 0.0001,
			"the shader's %s does not match the mirrored constant" % name
		)


## Depth is one float pushed per frame -- the whole reason this costs nothing
## per loaded tile. Shared, so one push re-draws every painted cell at once
## rather than needing a repaint.
func test_setting_the_depth_reaches_the_shared_material():
	var material := snow.shared_material()
	snow.set_snow_depth(0.42)
	assert_almost_eq(float(material.get_shader_parameter("snow_depth")), 0.42, 0.0001)
	snow.set_snow_depth(2.0)
	assert_almost_eq(
		float(material.get_shader_parameter("snow_depth")), 1.0, 0.0001,
		"depth must be clamped -- Snowfall's own range is 0..1"
	)


## The shared material really is shared: EarthChunkManager registers it once
## on a TileMapLayer and then only ever pushes uniforms.
func test_the_material_is_shared_across_callers():
	assert_same(snow.shared_material(), snow.shared_material())


# -- hosting on a TileMapLayer -------------------------------------------------
#
# fragment() never reads TEXTURE -- it writes COLOR unconditionally from its
# own stamp_atlas/trail_mask samplers -- so the TileMapLayer this shader is
# assigned to as a material needs no illustrated art of its own, only real
# painted cells to mark "snow may render here" (see docs/concept/
# snow_cover.md: this is the sole remaining reason the layer is a
# TileMapLayer at all rather than one screen-sized quad -- carrying land
# presence, not visuals). build_presence_tile_set is that minimal tileset.

func test_presence_tile_set_has_exactly_one_tile():
	var tile_set := SnowBombShader.build_presence_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	assert_eq(source.get_tiles_count(), 1)
	assert_eq(source.get_tile_id(0), SnowBombShader.PRESENCE_ATLAS_COORD)


## Must match TerrainRenderer.ART_TILE_SIZE, the same convention every other
## painted layer's tileset uses -- a mismatched tile_size would misalign
## presence cells against the terrain they are meant to gate snow over.
func test_presence_tile_set_uses_the_terrain_art_tile_size():
	var tile_set := SnowBombShader.build_presence_tile_set()
	assert_eq(tile_set.tile_size, Vector2i.ONE * TerrainRenderer.ART_TILE_SIZE)
