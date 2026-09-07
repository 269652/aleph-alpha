extends GutTest

## SnowSparkleShader: the shared specular-glint pattern both ground
## (SnowBombShader) and tree canopy (WindSway's shared tree material) splice
## into their own fragment() -- see docs/concept/snow_cover.md, "Sparkle:
## specular glints on lying snow".
##
## This module knows only WHERE/WHEN a glint fires (world position + time) and
## the canopy colour gate; it knows nothing about coverage -- each host
## applies its own gate on top (see test_snow_bomb_shader.gd/test_wind_sway.gd
## for the "no snow -> no sparkle" integration tests, which belong to the
## host that actually knows what counts as snow on its own surface).

const SnowSparkleShader = preload("res://src/rendering/snow_sparkle_shader.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const SnowStampAtlas = preload("res://src/rendering/snow_stamp_atlas.gd")


# -- the hash (mirrors SnowBombShader's own trig-free pin) -------------------

## Same reason as SnowBombShader.value_hash: world coordinates here reach the
## hundreds of thousands of units, and a sine-based hash collapses at float32
## range reduction there. This file hashes its own lattice, so it needs its
## own pin -- scoped to `sparkle_hash` ITSELF, not the whole snippet: unlike
## SnowBombShader, this file also legitimately uses sin() to OSCILLATE over
## TIME (see sparkle_intensity's own doc comment for why that is the
## unrelated, already-safe, already-shipped WindSway pattern) -- a whole-
## snippet ban would flag the very thing that makes sparkle twinkle at all.
func test_the_position_hash_is_trig_free():
	var code: String = SnowSparkleShader.GLSL_SNIPPET
	var start := code.find("float sparkle_hash(")
	var end := code.find("\n}", start)
	assert_true(start >= 0 and end > start, "could not locate sparkle_hash in the snippet")
	var body := code.substr(start, end - start)
	assert_false(body.contains("sin("), "the position hash must not use sine")
	assert_false(body.contains("cos("), "the position hash must not use cosine")


## The animation, by contrast, MUST use TIME -- confirms the oscillation is
## actually wired to the engine clock rather than a constant.
func test_the_twinkle_animates_over_time():
	var site := _find_eligible_site()
	assert_ne(site, Vector2.INF, "no eligible site found to test animation against")
	var a := SnowSparkleShader.sparkle_intensity(site.x, site.y, 0.0)
	var changed := false
	for i in 40:
		if not is_equal_approx(SnowSparkleShader.sparkle_intensity(site.x, site.y, float(i) * 0.1), a):
			changed = true
			break
	assert_true(changed, "sparkle_intensity never changes as time advances")


func test_the_hash_spreads_across_its_whole_range():
	var low := 1.0
	var high := 0.0
	for y in 40:
		for x in 40:
			var h := SnowSparkleShader.value_hash(float(x) * 1.7, float(y) * 2.3)
			assert_between(h, 0.0, 1.0)
			low = minf(low, h)
			high = maxf(high, h)
	assert_lt(low, 0.05)
	assert_gt(high, 0.95)


# -- the shared twinkle: pure function of position + time only ---------------

## The public contract: a pure function of (x, y, time), nothing else -- no
## world/tree/tile collection can be passed in because the signature has no
## slot for one. This IS the structural half of "cost independent of world
## population": there is no population-shaped input to this function at all,
## so nothing about calling it can scale with how many trees or tiles exist.
func test_sparkle_intensity_is_a_pure_function_of_position_and_time_only():
	var a := SnowSparkleShader.sparkle_intensity(123.4, 567.8, 12.0)
	var b := SnowSparkleShader.sparkle_intensity(123.4, 567.8, 12.0)
	assert_eq(a, b, "identical inputs must give an identical result")
	assert_between(a, 0.0, 1.0)


## THE geometric constraint on the tuning, the same shape SnowBombShader's own
## test_a_three_by_three_search_reaches_every_stamp_that_can_overlap_a_point
## pins: a sparkle point must never be able to wander into a neighbouring
## cell, because nothing here searches neighbours (unlike the stamp bombing,
## a single small point does not need to).
func test_sparkle_point_never_reaches_a_neighbouring_cell():
	var reach: float = SnowSparkleShader.SPARKLE_JITTER_WORLD + SnowSparkleShader.SPARKLE_POINT_RADIUS_WORLD
	assert_lt(
		reach, SnowSparkleShader.SPARKLE_CELL_WORLD * 0.5,
		"a sparkle site's point can reach %.2f world units, past half its own %.2f-unit cell"
			% [reach, SnowSparkleShader.SPARKLE_CELL_WORLD]
	)


## Finds a world position within SPARKLE_POINT_RADIUS_WORLD of a real
## eligible site's own (jittered) point, searching cells from (cx0, cy0)
## outward on a step-0.5 grid inside each candidate cell -- step 0.5 is small
## enough relative to SPARKLE_POINT_RADIUS_WORLD (0.55) that a full sweep of
## one cell is guaranteed to land inside a site's point circle wherever the
## jitter put it (worst-case grid-to-circle distance 0.5*sqrt(2)/2 =~ 0.354,
## comfortably under the 0.55 radius). Sampled at several times per point
## since a site between flashes reads as 0.0 regardless of position.
## Returns Vector2.INF if none found in range -- callers must check.
func _find_eligible_site(cell_count: int = 60) -> Vector2:
	var cell: float = SnowSparkleShader.SPARKLE_CELL_WORLD
	for cy in range(-cell_count, cell_count):
		for cx in range(-cell_count, cell_count):
			var base_x := float(cx) * cell
			var base_y := float(cy) * cell
			var ox := 0.0
			while ox < cell:
				var oy := 0.0
				while oy < cell:
					for i in 4:
						if SnowSparkleShader.sparkle_intensity(
							base_x + ox, base_y + oy, float(i) * 0.37
						) > 0.0:
							return Vector2(base_x + ox, base_y + oy)
					oy += 0.5
				ox += 0.5
	return Vector2.INF


## Spatial sparsity: what fraction of lattice CELLS are ever capable of
## sparkling at all, regardless of exactly where within the cell -- the
## eligibility hash's own real pass rate, a direct, meaningful measurement of
## SPARKLE_DENSITY rather than an assumption that the constant equals the
## outcome (the geometry could in principle have made it something else).
## Distinct from test_sparkle_is_sparse_across_space_and_time_together below,
## which measures what a player actually sees on screen at one instant
## (eligibility AND currently-in-range AND currently-flashing all at once).
func test_sparkle_lattice_is_spatially_sparse():
	var eligible := 0
	var total := 0
	for cy in range(-40, 40):
		for cx in range(-40, 40):
			var cell_h := SnowSparkleShader.value_hash(float(cx) + 5.1, float(cy) + 9.7)
			if cell_h <= SnowSparkleShader.SPARKLE_DENSITY:
				eligible += 1
			total += 1
	var fraction := float(eligible) / float(total)
	assert_almost_eq(
		fraction, SnowSparkleShader.SPARKLE_DENSITY, 0.03,
		"measured eligibility fraction %.3f strays far from the tuned SPARKLE_DENSITY %.3f"
			% [fraction, SnowSparkleShader.SPARKLE_DENSITY]
	)
	assert_lt(fraction, 0.35, "too many cells can ever sparkle: %.3f" % fraction)


## Temporal sparsity: AT a single eligible site, sampled across many moments,
## it must mostly read dark with only occasional bright peaks -- "occasional
## twinkle, not a constant heavy shimmer" (the user's own words), measured.
func test_a_single_eligible_site_mostly_reads_dark_between_flashes():
	# Find a genuinely eligible site first (scan until one is found -- most
	# cells are not, by the sparsity test above).
	var site := Vector2.ZERO
	var found := false
	var cell := SnowSparkleShader.SPARKLE_CELL_WORLD
	for cy in range(-40, 40):
		for cx in range(-40, 40):
			var wx := (float(cx) + 0.5) * cell
			var wy := (float(cy) + 0.5) * cell
			if SnowSparkleShader.sparkle_intensity(wx, wy, 0.0) > 0.0:
				site = Vector2(wx, wy)
				found = true
				break
		if found:
			break
	assert_true(found, "no eligible site found in an 80x80-cell sweep -- density is broken")
	var bright := 0
	var samples := 400
	for i in samples:
		var t := float(i) * 0.05
		if SnowSparkleShader.sparkle_intensity(site.x, site.y, t) > 0.5:
			bright += 1
	var duty := float(bright) / float(samples)
	assert_lt(duty, 0.25, "an eligible site is brightly lit %.3f of the time -- reads as a shimmer, not a twinkle" % duty)
	assert_gt(duty, 0.0, "an eligible site never actually flashes brightly across a 20s sweep")


## Combined spatiotemporal sparsity, the number that actually predicts what a
## player sees on screen at any one instant: across a dense grid of positions
## at one fixed moment, only a small fraction should read as a visible glint.
func test_sparkle_is_sparse_across_space_and_time_together():
	var visible := 0
	var total := 0
	for i in 3000:
		var x := float(i) * 3.7
		var y := float(i) * 5.3
		var t := float(i) * 0.011
		if SnowSparkleShader.sparkle_intensity(x, y, t) > 0.5:
			visible += 1
		total += 1
	var fraction := float(visible) / float(total)
	assert_lt(fraction, 0.08, "%.4f of sampled snow pixels sparkle at once -- too heavy" % fraction)


## Neighbouring eligible sites must not flash in lockstep -- a synchronized
## field reads as one field-wide pulse, not scattered independent glints
## (the same "hash the site, not the world" idea SnowBombShader's own
## variant/level hashing already leans on). Finds two INDEPENDENTLY eligible
## sites (not necessarily adjacent cells, since most cells are not eligible
## at all per the sparsity test above) and compares their phase.
func test_neighbouring_sites_twinkle_out_of_phase():
	var site_a := _find_eligible_site()
	assert_ne(site_a, Vector2.INF, "no first eligible site found")
	var cell: float = SnowSparkleShader.SPARKLE_CELL_WORLD
	var site_b := Vector2.INF
	# Search starting well past site_a's own cell so the second search cannot
	# just re-find the same site.
	var start_cx := int(floor(site_a.x / cell)) + 3
	for cy in range(-60, 60):
		for cx in range(start_cx, start_cx + 120):
			var base_x := float(cx) * cell
			var base_y := float(cy) * cell
			var ox := 0.0
			while ox < cell:
				var oy := 0.0
				while oy < cell:
					for i in 4:
						if SnowSparkleShader.sparkle_intensity(
							base_x + ox, base_y + oy, float(i) * 0.37
						) > 0.0:
							site_b = Vector2(base_x + ox, base_y + oy)
					oy += 0.5
				ox += 0.5
			if site_b != Vector2.INF:
				break
		if site_b != Vector2.INF:
			break
	assert_ne(site_b, Vector2.INF, "no second eligible site found")
	var curve_a: Array = []
	var curve_b: Array = []
	for i in 50:
		var t := float(i) * 0.1
		curve_a.append(SnowSparkleShader.sparkle_intensity(site_a.x, site_a.y, t))
		curve_b.append(SnowSparkleShader.sparkle_intensity(site_b.x, site_b.y, t))
	assert_ne(curve_a, curve_b, "two independent sites twinkle in exact lockstep")


# -- the canopy colour gate, measured against the real art -------------------

func test_value_and_saturation_match_the_hsv_definition():
	assert_almost_eq(SnowSparkleShader.value_of(Color(1, 1, 1)), 1.0, 0.001)
	assert_almost_eq(SnowSparkleShader.saturation_of(Color(1, 1, 1)), 0.0, 0.001)
	assert_almost_eq(SnowSparkleShader.value_of(Color(0.5, 0.5, 0.5)), 0.5, 0.001)
	assert_almost_eq(SnowSparkleShader.saturation_of(Color(0.5, 0.5, 0.5)), 0.0, 0.001)
	assert_almost_eq(SnowSparkleShader.value_of(Color(1, 0, 0)), 1.0, 0.001)
	assert_almost_eq(SnowSparkleShader.saturation_of(Color(1, 0, 0)), 1.0, 0.001)


func test_near_white_passes_the_colour_gate_and_saturated_pink_does_not():
	assert_true(SnowSparkleShader.passes_colour_gate(Color(0.95, 0.95, 0.97)))
	assert_false(SnowSparkleShader.passes_colour_gate(Color(0.95, 0.55, 0.70)), "saturated pink must not pass")
	assert_false(SnowSparkleShader.passes_colour_gate(Color(0.2, 0.6, 0.2)), "mid-bright green must not pass")


## THE real-data pin for the canopy colour gate, per CLAUDE.md ("tuned
## thresholds must be tested functions... never eyeballed"): measured with
## tools/probe_snow_sparkle_colors.gd over the REAL composited art. Cherry's
## own illustrated blossom is real, pink, and the one colour this gate exists
## to reject -- see docs/concept/flora.md's own "reads as neutral grey-white
## against every season frame's own hue" measurement, which this pins as a
## real number rather than restating the same claim in prose twice.
func test_the_colour_gate_separates_real_snow_from_real_blossom():
	var tree := IllustratedTree.new()
	var snow_pass := _gate_pass_fraction(tree.snow_canopy_for("cherry"))
	var blossom_pass := _gate_pass_fraction(tree.canopy_for("cherry", "spring"))
	var apple_blossom_pass := _gate_pass_fraction(tree.canopy_for("apple", "spring"))
	assert_gt(snow_pass, 0.20, "the real cherry snow frame barely passes its own colour gate (%.4f)" % snow_pass)
	assert_lt(blossom_pass, 0.03, "cherry blossom passes the snow colour gate too often (%.4f)" % blossom_pass)
	assert_lt(apple_blossom_pass, 0.03, "apple blossom passes the snow colour gate too often (%.4f)" % apple_blossom_pass)
	assert_gt(
		snow_pass / maxf(blossom_pass, 0.0001), 8.0,
		"snow passes the gate only %.1fx as often as blossom -- not enough separation"
			% (snow_pass / maxf(blossom_pass, 0.0001))
	)


## The ground's own real snow art independently passes the SAME gate
## generously, even though ground never actually runs the colour gate at
## runtime (it is gated by `lying` instead, which is unambiguous) -- a
## cross-check that "what counts as snow-coloured" agrees between the two
## surfaces' art, not two independently eyeballed ideas of white.
func test_ground_snow_atlas_passes_the_same_colour_gate_generously():
	var atlas := SnowStampAtlas.new()
	var fraction := _gate_pass_fraction_image(atlas.build_atlas_image())
	assert_gt(fraction, 0.20, "the real ground snow atlas barely passes the shared colour gate (%.4f)" % fraction)


func _gate_pass_fraction(texture: Texture2D) -> float:
	if texture == null:
		return 0.0
	return _gate_pass_fraction_image(texture.get_image())


func _gate_pass_fraction_image(img: Image) -> float:
	img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var pass_count := 0
	var count := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			count += 1
			if SnowSparkleShader.passes_colour_gate(c):
				pass_count += 1
	if count == 0:
		return 0.0
	return float(pass_count) / float(count)


# -- cost shape: linear in call count, not quadratic -------------------------

## Not a hard performance gate (this machine runs many concurrent sessions,
## see docs/progress.md's own FPS-regression writeups on why a literal
## millisecond number is not trustworthy here) -- a loose smoke bound that
## catches an accidental O(n^2)/unbounded-allocation regression, mirroring
## this codebase's own "growth-rate, not timing" testing convention.
func test_evaluation_cost_scales_linearly_with_call_count_not_worse():
	var small_n := 2000
	var large_n := 20000
	var start_small := Time.get_ticks_usec()
	for i in small_n:
		SnowSparkleShader.sparkle_intensity(float(i) * 1.3, float(i) * 2.1, float(i) * 0.01)
	var small_us := Time.get_ticks_usec() - start_small
	var start_large := Time.get_ticks_usec()
	for i in large_n:
		SnowSparkleShader.sparkle_intensity(float(i) * 1.3, float(i) * 2.1, float(i) * 0.01)
	var large_us := Time.get_ticks_usec() - start_large
	# 10x the calls should cost at most ~20x as long, not ~100x (quadratic) --
	# generous slack for scheduling noise on a shared machine.
	assert_lt(
		float(large_us), float(maxi(small_us, 1)) * 20.0,
		"10x the calls cost %.1fx as long -- looks superlinear" % (float(large_us) / float(maxi(small_us, 1)))
	)


# -- the material-sharing shape (see docs/concept/snow_cover.md's own "one
# push, every sharer sees it" paragraph) -------------------------------------

## Every constant this file pins must actually be readable as such -- guards
## against a future edit renaming a const without updating its own doc
## comment cross-references (cheap, but real: SnowBombShader's own
## test_every_mirrored_constant_reaches_the_shader exists for the identical
## reason at the uniform-push layer, which test_snow_bomb_shader.gd and
## test_wind_sway.gd pin on their own hosts).
func test_tuned_constants_are_positive_and_sane():
	assert_gt(SnowSparkleShader.SPARKLE_CELL_WORLD, 0.0)
	assert_between(SnowSparkleShader.SPARKLE_DENSITY, 0.0, 1.0)
	assert_gt(SnowSparkleShader.SPARKLE_HZ, 0.0)
	assert_gt(SnowSparkleShader.SPARKLE_DUTY_EXPONENT, 1.0, "must be > 1 to actually peak rather than staying half-lit")
	assert_between(SnowSparkleShader.SPARKLE_BRIGHTNESS, 0.0, 1.0)
	assert_between(SnowSparkleShader.SPARKLE_MIN_VALUE, 0.0, 1.0)
	assert_between(SnowSparkleShader.SPARKLE_MAX_SATURATION, 0.0, 1.0)
