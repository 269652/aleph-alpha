extends GutTest

## WaterShader: the GPU water overlay (see water_shader.gd) -- continuous,
## physically-inspired waves rendered in world space over ocean cells: a
## shore reflection band, raindrop ripples, and movement-disturbance ripples
## (fish/players/animals in water -- see EarthChunkManager.
## record_water_disturbance), all summed into one interfering wave field.
## Deliberately NOT wind-driven: undisturbed water with nothing moving in or
## over it stays flat. Contract tests only; the visual result can't be
## asserted headless.

const WaterShader = preload("res://src/rendering/water_shader.gd")

var water := WaterShader.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := water.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


func test_shader_renders_continuous_world_space_waves():
	var code: String = WaterShader.SHADER_CODE
	assert_string_contains(code, "shader_type canvas_item")
	assert_string_contains(code, "MODEL_MATRIX")
	assert_string_contains(code, "TIME")
	assert_string_contains(code, "void fragment()")


func test_overlay_is_translucent_so_the_base_tile_layer_shows_through():
	# The overlay must NOT be opaque: the baked base water tile (and its
	# calmer tint near shore, once faded) stays part of the final look.
	assert_lt(WaterShader.WATER_ALPHA, 0.75)
	assert_gt(WaterShader.WATER_ALPHA, 0.2)
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("alpha_strength"), WaterShader.WATER_ALPHA)


func test_shared_material_is_reused():
	assert_eq(water.shared_material(), water.shared_material())


# -- shore-distance-driven edge blending + reflection --------------------------

## The shader must read the WaterFx tile's own texture as shore-distance
## DATA (see procedural_shore_distance_sprite.gd), not ignore it as before --
## this is what lets the ocean edge fade smoothly into the coast on the GPU
## instead of cutting off at a baked tile boundary.
func test_shader_samples_the_tile_texture_as_shore_distance():
	var code: String = WaterShader.SHADER_CODE
	assert_string_contains(code, "texture(TEXTURE, UV)")
	assert_string_contains(code, "shore_dist")


## The shore-reflection standing wave is GONE, and must stay gone.
##
## It was `sin(shore_dist * k) * cos(TIME * omega)` -- a standing wave whose
## amplitude pulsed the ENTIRE body of water in lockstep, every pixel rising
## and falling together. Invisible while an ambient wind term dominated the
## field; once ambient was removed and the crest thresholds corrected, it
## became the loudest thing on screen (reported: "it cascades over the whole
## body of water causing chain reactions and not only a ripple at the point
## where moving is"). It is also unphysical here: with no ambient waves,
## there is nothing arriving at the shore to reflect.
## Checks the identifiers the standing wave was actually built from, rather
## than prose words like "reflected" that legitimately appear in the comment
## explaining why it was removed.
func test_shader_has_no_pond_wide_standing_wave():
	var code: String = WaterShader.SHADER_CODE
	for identifier in ["shore_bounce", "shore_band"]:
		assert_false(code.contains(identifier), "%s would pulse the whole pond in sync" % identifier)


## Shore distance is still read -- it drives the alpha fade into the
## coastline, which is a static edge blend, not a moving wave.
func test_shore_distance_still_drives_the_coastline_alpha_fade():
	assert_string_contains(WaterShader.SHADER_CODE, "edge_alpha")


# -- raindrop ripples --------------------------------------------------------

func test_shader_has_a_continuous_rain_intensity_uniform_defaulting_to_zero():
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("rain_intensity"), 0.0)
	assert_string_contains(WaterShader.SHADER_CODE, "uniform float rain_intensity")


## Raindrops spawn expanding ring ripples from a hash-seeded grid of drop
## points, sampling neighboring cells too so a ring crossing a cell boundary
## still renders -- and the result feeds into the same combined wave field as
## the ambient chop and shore reflection, so overlapping ripples genuinely
## interfere rather than drawing over each other.
func test_shader_generates_raindrop_ripples_that_feed_the_combined_wave_field():
	var code: String = WaterShader.SHADER_CODE
	assert_string_contains(code, "raindrop_ripples")
	assert_string_contains(code, "float wave = ")


## Most cells are between splashes at any instant (rain_ripple_lifetime <
## the spawn interval, i.e. a cell's drop is only "live" a fraction of the
## time), so computing that cell's drop position (2 more hashes) and running
## the full packet math (exp + sin) for a cell that's out of its splash
## window right now wastes real GPU work on every fragment, every one of the
## 9 sampled cells, every frame while it's raining -- reported live: with
## rain or snow active, fps dropped from ~30 to ~6. The age bounds check
## must happen BEFORE the expensive part, not after it, so an inactive
## cell's iteration is actually cheap rather than merely reordered on paper.
func test_raindrop_ripples_skips_the_expensive_part_for_a_cell_out_of_its_splash_window():
	var code: String = WaterShader.SHADER_CODE
	var fn_start := code.find("float raindrop_ripples")
	var fn_end := code.find("\nfloat movement_ripples", fn_start)
	var fn_body := code.substr(fn_start, fn_end - fn_start)
	assert_string_contains(fn_body, "continue", "an out-of-window cell must skip the rest of its own iteration")
	var continue_pos := fn_body.find("continue")
	var drop_pos_pos := fn_body.find("drop_pos")
	assert_gt(continue_pos, 0, "continue must actually appear in raindrop_ripples")
	assert_lt(
		continue_pos, drop_pos_pos,
		"the early-out must come before drop_pos is computed, or its hashes are wasted anyway"
	)


func test_set_rain_intensity_updates_the_shared_materials_uniform():
	var material := water.shared_material()
	water.set_rain_intensity(1.0)
	assert_eq(material.get_shader_parameter("rain_intensity"), 1.0)
	water.set_rain_intensity(0.0)
	assert_eq(material.get_shader_parameter("rain_intensity"), 0.0)


# -- color balance (reported: "looks like a patch of cloudy sky") -------------
#
# The previous crest color was nearly white-cyan and the blend threshold let
# most of the noise range trend toward it, so large areas of "water" read as
# a pale wash instead of a cohesive body of water. Both are now real,
# test-pinned uniforms.

func test_crest_color_stays_clearly_blue_not_washed_out_toward_white():
	assert_lt(
		WaterShader.CREST_COLOR.r, WaterShader.CREST_COLOR.b,
		"crest should read as light blue, not a neutral/cyan-white highlight"
	)
	var brightness_sum := WaterShader.CREST_COLOR.r + WaterShader.CREST_COLOR.g + WaterShader.CREST_COLOR.b
	assert_lt(brightness_sum, 2.2, "crest shouldn't be close to white (sum 3.0)")


func test_deep_color_is_darker_and_more_saturated_than_crest():
	var deep_sum := WaterShader.DEEP_COLOR.r + WaterShader.DEEP_COLOR.g + WaterShader.DEEP_COLOR.b
	var crest_sum := WaterShader.CREST_COLOR.r + WaterShader.CREST_COLOR.g + WaterShader.CREST_COLOR.b
	assert_lt(deep_sum, crest_sum, "deep water should read darker than a wave crest")
	assert_lt(WaterShader.DEEP_COLOR.r, WaterShader.DEEP_COLOR.b, "deep should read blue too")


## Undisturbed water must stay deep-colored, so the surface reads as a
## dominant blue body rather than a wide pale wash.
##
## This used to assert WAVE_LOW_THRESHOLD > 0.45, which made sense only while
## an ambient wind-noise term held the wave field at a constant ~0.5
## baseline. Once that ambient term was removed (ripples come from rain and
## movement now, not wind), open water sits at 0.0 and a 0.55 floor meant a
## ripple had to reach 0.61 before it tinted ANYTHING -- which no ripple did
## except in its first fraction of a second at near-zero radius. That is the
## "sometimes a mini ripple appears but nothing looks natural" report. The
## intent is preserved; the ambient-era magic number is not.
func test_wave_blend_thresholds_keep_undisturbed_water_deep():
	assert_gt(WaterShader.WAVE_LOW_THRESHOLD, 0.0, "flat water must not already be tinted toward crest")
	assert_gt(WaterShader.WAVE_HIGH_THRESHOLD, WaterShader.WAVE_LOW_THRESHOLD)


# -- ripple shape + visibility over a full lifetime ---------------------------
#
# ripple_amplitude mirrors the shader's ripple_packet math on the CPU (the
# shader itself can't be asserted headlessly), so the tuning that decides
# whether a ripple is actually VISIBLE is a tested function rather than
# eyeballed shader literals.

## The peak of the first ring sits a quarter-wavelength behind the wave
## front -- the distance at which a ripple is brightest for a given age.
func _first_crest_distance(age: float) -> float:
	return age * WaterShader.RIPPLE_SPEED - WaterShader.RIPPLE_WAVELENGTH * 0.25


## The regression that made ripples effectively invisible: amplitude decayed
## so fast (and the crest threshold sat so high) that only the first instant
## cleared it. A ripple must stay above the crest threshold across its life,
## not just at birth.
func test_a_ripple_stays_visible_across_its_whole_lifetime():
	for fraction in [0.25, 0.5, 0.75]:
		var age: float = WaterShader.RIPPLE_LIFETIME * fraction
		var amplitude := WaterShader.ripple_amplitude(_first_crest_distance(age), age)
		assert_gt(
			amplitude, WaterShader.WAVE_LOW_THRESHOLD,
			"a ripple at %d%% of its life should still be visible" % int(fraction * 100.0)
		)


## A ripple fades as it goes -- a dying ring must not be as bright as a fresh
## one, or it reads as a hard-edged expanding disc rather than water.
func test_a_ripple_fades_as_it_ages():
	var young: float = WaterShader.RIPPLE_LIFETIME * 0.25
	var old: float = WaterShader.RIPPLE_LIFETIME * 0.75
	assert_gt(
		WaterShader.ripple_amplitude(_first_crest_distance(young), young),
		WaterShader.ripple_amplitude(_first_crest_distance(old), old)
	)


## Real ripples are several concentric rings, not one lone circle -- the
## packet has to be wide enough to hold more than one wavelength, and the
## amplitude must actually change sign across it (crest, trough, crest).
func test_a_ripple_is_several_concentric_rings_not_a_single_circle():
	assert_gt(
		WaterShader.RIPPLE_PACKET_WIDTH, WaterShader.RIPPLE_WAVELENGTH,
		"the packet must span more than one wavelength to show multiple rings"
	)
	var age: float = WaterShader.RIPPLE_LIFETIME * 0.5
	var front: float = age * WaterShader.RIPPLE_SPEED
	var saw_crest := false
	var saw_trough := false
	for step in 40:
		var dist: float = front - float(step) * WaterShader.RIPPLE_WAVELENGTH * 0.1
		var amplitude := WaterShader.ripple_amplitude(dist, age)
		if amplitude > 0.05:
			saw_crest = true
		if amplitude < -0.05:
			saw_trough = true
	assert_true(saw_crest and saw_trough, "a ripple should show both crests and troughs")


## Nothing should appear ahead of the wave front -- water further out hasn't
## been reached yet.
func test_no_ripple_appears_ahead_of_the_wave_front():
	var age: float = WaterShader.RIPPLE_LIFETIME * 0.5
	var far_ahead: float = age * WaterShader.RIPPLE_SPEED + WaterShader.RIPPLE_PACKET_WIDTH * 6.0
	assert_almost_eq(WaterShader.ripple_amplitude(far_ahead, age), 0.0, 0.01)


func test_a_ripple_is_gone_once_past_its_lifetime():
	var past: float = WaterShader.RIPPLE_LIFETIME + 0.1
	assert_eq(WaterShader.ripple_amplitude(past * WaterShader.RIPPLE_SPEED, past), 0.0)


## A wake has to cover enough water to read as a wake (a ripple dying inside
## its own tile is the "mini ripple" symptom) -- but NOT so much that one
## fish swamps a whole pond, which is what a 3+ tile radius did (reported:
## "it cascades over the whole body of water"). Bounded on both sides.
func test_a_wake_spreads_beyond_its_own_tile_but_does_not_swamp_a_pond():
	var max_radius: float = WaterShader.RIPPLE_LIFETIME * WaterShader.RIPPLE_SPEED
	assert_gt(max_radius, 1.5 * 16.0, "a wake should reach past the tile it started in")
	assert_lt(max_radius, 2.5 * 16.0, "a single wake should not span a whole pond")


## A raindrop is a small splash, not a swimmer's wake -- rain gets its own,
## much tighter tuning. Sharing the wake's packet made every drop a
## multi-tile bullseye (reported: "the ripples don't look as natural").
func test_a_raindrop_splash_is_much_smaller_than_a_movement_wake():
	var rain_radius: float = WaterShader.RAIN_RIPPLE_LIFETIME * WaterShader.RAIN_RIPPLE_SPEED
	var wake_radius: float = WaterShader.RIPPLE_LIFETIME * WaterShader.RIPPLE_SPEED
	assert_lt(rain_radius, wake_radius * 0.5, "a raindrop splash should be far smaller than a wake")
	assert_lt(rain_radius, 16.0, "a raindrop splash should stay within about a tile")


## The shader must actually be fed the same tuning the CPU mirror tests --
## duplicated literals in the shader source would let the two drift apart.
func test_make_material_pushes_the_ripple_tuning_uniforms():
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("ripple_speed"), WaterShader.RIPPLE_SPEED)
	assert_eq(material.get_shader_parameter("ripple_wavelength"), WaterShader.RIPPLE_WAVELENGTH)
	assert_eq(material.get_shader_parameter("ripple_packet_width"), WaterShader.RIPPLE_PACKET_WIDTH)
	assert_eq(material.get_shader_parameter("ripple_spread_decay"), WaterShader.RIPPLE_SPREAD_DECAY)


func test_make_material_sets_the_color_and_threshold_uniforms():
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("deep_color"), WaterShader.DEEP_COLOR)
	assert_eq(material.get_shader_parameter("crest_color"), WaterShader.CREST_COLOR)
	assert_eq(material.get_shader_parameter("wave_low_threshold"), WaterShader.WAVE_LOW_THRESHOLD)
	assert_eq(material.get_shader_parameter("wave_high_threshold"), WaterShader.WAVE_HIGH_THRESHOLD)


func test_make_material_pushes_the_edge_alpha_fade_uniforms():
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("edge_alpha_fade_start"), WaterShader.EDGE_ALPHA_FADE_START)
	assert_eq(material.get_shader_parameter("edge_alpha_fade_end"), WaterShader.EDGE_ALPHA_FADE_END)


# -- edge_alpha_for_shore_distance mirrors the shader's coastline fade on the
# -- CPU (the shader itself can't be asserted headlessly), so a placement
# -- decision like "will this point clearly read as water" can be a tested
# -- function against the real curve rather than an eyeballed fraction of a
# -- pond's geometric radius (reported live, for the character preview
# -- diorama: "fish are still spawned on land" -- they were inside the
# -- pond's nominal radius, but well into the visual fade toward the shore).

func test_edge_alpha_is_fully_opaque_at_and_past_the_fade_end():
	assert_eq(WaterShader.edge_alpha_for_shore_distance(WaterShader.EDGE_ALPHA_FADE_END), 1.0)
	assert_eq(WaterShader.edge_alpha_for_shore_distance(WaterShader.EDGE_ALPHA_FADE_END + 0.2), 1.0)


func test_edge_alpha_is_fully_transparent_at_and_before_the_fade_start():
	assert_eq(WaterShader.edge_alpha_for_shore_distance(WaterShader.EDGE_ALPHA_FADE_START), 0.0)


func test_edge_alpha_increases_monotonically_across_the_fade_band():
	var previous := 0.0
	for step in 10:
		var shore_dist: float = WaterShader.EDGE_ALPHA_FADE_START + (WaterShader.EDGE_ALPHA_FADE_END - WaterShader.EDGE_ALPHA_FADE_START) * (float(step) / 9.0)
		var alpha := WaterShader.edge_alpha_for_shore_distance(shore_dist)
		assert_gte(alpha, previous, "the fade must not darken as shore_dist grows")
		previous = alpha


# -- wind animates the SURFACE, but never creates ripples --------------------
#
# Two different things got conflated. "Ripples" -- discrete expanding rings --
# must come only from rain and from things moving through the water. But the
# ambient wind-paced chop that gives the surface its living shimmer is
# surface TEXTURE, not a ripple, and removing it outright left the water
# looking dead (reported: "the wind animation on water is gone from the
# shader"). Wind is back, as its own subtle term that never feeds the ripple
# wave field.

func test_wind_still_animates_the_water_surface():
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("wind_strength"), WaterShader.DEFAULT_WIND_STRENGTH)
	assert_string_contains(WaterShader.SHADER_CODE, "wind_chop")


## The ripple wave field must be built from rain and movement ONLY -- if
## wind fed into it, undisturbed water would ring by itself again.
func test_the_ripple_wave_field_is_only_rain_and_movement():
	var code: String = WaterShader.SHADER_CODE
	var line_start := code.find("float wave = ")
	var wave_line := code.substr(line_start, code.find(";", line_start) - line_start)
	assert_string_contains(wave_line, "rain")
	assert_string_contains(wave_line, "movement")
	assert_false(wave_line.contains("wind"), "wind must not feed the ripple field: %s" % wave_line)
	assert_false(wave_line.contains("chop"), "chop must not feed the ripple field: %s" % wave_line)


func test_set_wind_strength_updates_the_shared_materials_uniform():
	var material := water.shared_material()
	water.set_wind_strength(1.4)
	assert_eq(material.get_shader_parameter("wind_strength"), 1.4)
	water.set_wind_strength(WaterShader.DEFAULT_WIND_STRENGTH)
	assert_eq(material.get_shader_parameter("wind_strength"), WaterShader.DEFAULT_WIND_STRENGTH)


## Every loaded fish emits a wake on a timer, including ones far off-screen.
## With only 8 slots the buffer churned so fast that a ripple was evicted
## almost the instant it appeared -- which is why rain (an independent hashed
## grid) rendered fine while movement wakes stayed invisible.
func test_there_are_enough_disturbance_slots_for_several_concurrent_wakes():
	assert_gte(WaterShader.MAX_DISTURBANCES, 16)


# -- movement-disturbance ripples (fish, players/animals in water) -----------
#
# The same expanding-ring technique as raindrop_ripples, anchored to
# explicit recorded positions and a CPU-driven age instead of a hashed grid
# (see EarthChunkManager.record_water_disturbance/step_water_disturbances).
#
# Age is pushed from GDScript every frame (advance_disturbances), NOT
# computed in the shader from TIME minus a stored CPU timestamp: the
# shader's TIME and Time.get_ticks_msec() are independent clocks with no
# guaranteed epoch alignment, which silently made every ripple's age always
# out of range and so always discarded -- ripples that updated their
# uniforms correctly but never actually appeared (reported: "neither the
# fish nor player or creature movement cause ripples").

func test_shader_has_disturbance_uniforms_defaulting_to_none():
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("disturbance_count"), 0)
	# Sized from MAX_DISTURBANCES so the shader arrays and the GDScript
	# buffer can never silently disagree about capacity.
	var size := WaterShader.MAX_DISTURBANCES
	assert_string_contains(WaterShader.SHADER_CODE, "uniform vec2 disturbance_pos[%d]" % size)
	assert_string_contains(WaterShader.SHADER_CODE, "uniform float disturbance_age[%d]" % size)


func test_shader_generates_movement_ripples_that_feed_the_combined_wave_field():
	var code: String = WaterShader.SHADER_CODE
	assert_string_contains(code, "movement_ripples")
	assert_string_contains(code, "float wave = ")


## The shader must NOT derive a disturbance's age from its own TIME uniform
## minus a stored value -- see the section comment above.
func test_movement_ripples_does_not_derive_age_from_shader_time():
	var code: String = WaterShader.SHADER_CODE
	var fn_start := code.find("float movement_ripples")
	var fn_end := code.find("\n}", fn_start)
	var fn_body := code.substr(fn_start, fn_end - fn_start)
	assert_false(fn_body.contains("TIME"), "movement_ripples must use the pushed disturbance_age, not TIME")


func test_set_disturbances_updates_the_shared_materials_uniforms():
	var material := water.shared_material()
	var positions := PackedVector2Array([Vector2(10, 20), Vector2(30, 40)])
	var ages := PackedFloat32Array([0.3, 0.9])
	water.set_disturbances(positions, ages, 2)
	assert_eq(material.get_shader_parameter("disturbance_count"), 2)
	assert_eq(material.get_shader_parameter("disturbance_pos"), positions)
	assert_eq(material.get_shader_parameter("disturbance_age"), ages)


## Positions/ages must always be padded to the fixed shader array size
## (MAX_DISTURBANCES), or Godot has nothing to assign for the unused slots.
func test_add_disturbance_pads_arrays_to_the_fixed_shader_size():
	var material := water.shared_material()
	water.add_disturbance(Vector2(5, 5))
	var positions: PackedVector2Array = material.get_shader_parameter("disturbance_pos")
	var ages: PackedFloat32Array = material.get_shader_parameter("disturbance_age")
	assert_eq(positions.size(), WaterShader.MAX_DISTURBANCES)
	assert_eq(ages.size(), WaterShader.MAX_DISTURBANCES)
	assert_eq(material.get_shader_parameter("disturbance_count"), 1)


func test_a_freshly_added_disturbance_starts_at_age_zero():
	var material := water.shared_material()
	water.add_disturbance(Vector2(5, 5))
	var ages: PackedFloat32Array = material.get_shader_parameter("disturbance_age")
	assert_eq(ages[0], 0.0)


## The whole point: a ripple must actually expand/fade over real frames, not
## sit frozen at age 0 forever.
func test_advance_disturbances_ages_a_live_disturbance():
	var material := water.shared_material()
	water.add_disturbance(Vector2(5, 5))
	water.advance_disturbances(0.5)
	var ages: PackedFloat32Array = material.get_shader_parameter("disturbance_age")
	assert_almost_eq(ages[0], 0.5, 0.001)


func test_advance_disturbances_drops_a_disturbance_past_its_lifetime():
	var material := water.shared_material()
	water.add_disturbance(Vector2(5, 5))
	water.advance_disturbances(WaterShader.DISTURBANCE_LIFETIME + 0.1)
	assert_eq(material.get_shader_parameter("disturbance_count"), 0)


## Oldest disturbance drops once the cap is exceeded, so the array never
## silently grows unbounded.
func test_add_disturbance_drops_the_oldest_once_past_the_cap():
	var material := water.shared_material()
	for i in WaterShader.MAX_DISTURBANCES + 3:
		water.add_disturbance(Vector2(float(i), 0.0))
	assert_eq(material.get_shader_parameter("disturbance_count"), WaterShader.MAX_DISTURBANCES)


# -- a softer, slower, broader wake -------------------------------------------
#
# "Can you make the ripples a little less pronounced so they appear smoother
# a bit slower and more natural." The wake's SHAPE is shared by the sea and
# the river (RiverFlowShader imports these constants), so the shape tuning
# lives here and both surfaces follow. Slower: the front travels under 12
# world px/s instead of 14. Smoother: crests half a tile apart instead of
# six pixels, so a wake is two or three broad rings rather than a tight
# bullseye of narrow ones. The packet still spans more than one wavelength
# (several rings, not a lone circle) but stays under one and a half, so
# broadening the crests does not trail more of them.


func test_a_wake_is_a_bit_slower_and_its_crests_are_broader():
	assert_lte(WaterShader.RIPPLE_SPEED, 12.0, "a bit slower: the front should amble, not race")
	assert_gte(
		WaterShader.RIPPLE_WAVELENGTH, 8.0,
		"smoother: crests at least half a tile apart read as broad swells, not fine rings"
	)
	var rings_in_packet: float = WaterShader.RIPPLE_PACKET_WIDTH / WaterShader.RIPPLE_WAVELENGTH
	assert_between(
		rings_in_packet, 1.1, 1.4,
		"a couple of rings behind the front -- never one lonely circle, never a bullseye"
	)


## "A more relaxed and calm picture": a wake that is gone in two seconds
## reads as a flicker. It lingers three seconds or more, still expanding
## slowly, and the reach it grows to over that life stays inside the pond
## bound the test above already holds.
func test_a_wake_lingers():
	assert_gte(WaterShader.RIPPLE_LIFETIME, 3.0)
