extends RefCounted

## A chunk's worth of fallen-leaf litter, rendered as GPU-instanced cards from
## LeafLitterAtlas -- one MultiMeshInstance2D draw call per chunk, mirroring
## IllustratedGrassPatch's shape minus Y-sort banding (flat ground litter has
## no vertical extent to misorder -- see EarthChunkManager's own
## _ground_decor_parent doc comment).
##
## Falling and settled-sway motion is computed continuously in the shared
## vertex shader, ported BY HAND from DroppedItem's own already-tested
## _step_fall/_step_ground_sway formulas -- the same "GDScript mirror kept in
## sync with the GLSL by hand" convention SnowBombShader's own static funcs
## already establish in this codebase, and for the same reason: a vertex
## shader cannot be asserted headless. Each static func below names the
## DroppedItem method (and the GLSL vertex() line group) it mirrors.
##
## ## The packed instance data (INSTANCE_CUSTOM), and why it fits
##
## MultiMesh per-instance custom data is exactly 4 float channels (r,g,b,a),
## each only 8 BITS wide in this renderer (a raw value stored there reads
## back quantized to 256 levels -- see rain_overlay.gd's own doc comment,
## "a screen coordinate stored there would snap to a 5px grid"). Grass
## (illustrated_grass_patch.gd) already spends all 4 on an irregular UV pair
## (region_uv0.xy, region_uv1.zw) because its atlas is a pre-baked sheet with
## no fixed grid. LeafLitterAtlas is deliberately a FIXED cell grid instead,
## so addressing a cell costs a single small index -- freeing three whole
## channels for what grass never needed: continuous fall/relocation motion.
## The 4 channels:
##   r -- packed cell index (see pack_cell_index/unpack_cell_index)
##   g -- packed transition-offset X (see pack_offset_axis/unpack_offset_axis)
##   b -- packed transition-offset Y (same)
##   a -- packed, WRAPPED transition-start time (see pack_time_fraction)
##
## ## Why the start time is a WRAPPED fraction, and how that stays safe
##
## Channel a cannot hold a raw, ever-growing world-age timestamp (the same
## "8-bit custom data can't hold a raw growing timer" trap rain_overlay.gd's
## own doc comment already names, which is why THAT file packs a fraction of
## its own fall_span instead of a raw fall distance). So this packs
## fract(transition_start / WRAP_PERIOD) instead, and the shader compares it
## against a live current_time_fraction uniform (pushed once per relevant
## tick, NOT per instance -- see set_current_time) computed the same way.
##
## A wrapped comparison like this can, in principle, ALIAS once real elapsed
## time exceeds a full WRAP_PERIOD: a leaf whose transition finished long ago
## could misread as "just starting" again the instant the wrapped clock laps
## it, and visibly jump back to its old offset for a moment. This is made
## STRUCTURALLY impossible rather than merely unlikely: LeafLitterField.
## advance() snaps a completed leaf's own transition_from to equal its
## position (see that method's own doc comment) the moment TRANSITION_
## DURATION elapses, which packs a REAL, exact ZERO offset from then on --
## and zero times any (even a briefly aliased) eased fraction is still zero.
## Only a leaf ACTIVELY mid-transition depends on the wrapped math being
## correct, and that window is bounded by TRANSITION_DURATION itself (well
## under one second), always comfortably inside WRAP_PERIOD.
##
## WRAP_PERIOD is deliberately exactly GROUND_SWAY_PERIOD (not merely "close
## to it"): the ongoing ground sway (once settled) is driven by the SAME
## current_time_fraction uniform, as sin(current_time_fraction * TAU +
## phase) -- see settled_sway_rotation. That equivalence (current_time_
## fraction * TAU/GROUND_SWAY_PERIOD*WRAP_PERIOD reducing to current_time_
## fraction * TAU exactly) is only seam-free across a wrap if the two
## constants are equal -- changing one without the other reintroduces a
## visible phase jump in the sway once a real session runs long enough to
## wrap.

const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")
const LeafLitterAtlas = preload("res://src/rendering/leaf_litter_atlas.gd")
const WindDispersal = preload("res://src/world/wind_dispersal.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")

## How big a leaf reads on the ground, in world pixels. Originally ported
## unchanged from DroppedItem.LEAF_WORLD_SIZE's own derivation
## (WALNUT_WORLD_WIDTH * 1.5); reported directly as too large once seen
## rendered at real scale ("leaves should be half as big") -- halved to
## 0.75x walnut width. Pinned by test_world_size_is_half_its_previous_
## walnut_relative_size, not eyeballed.
const WORLD_SIZE := ProceduralItemSprite.WALNUT_WORLD_WIDTH * 0.75

## Ported unchanged from DroppedItem's own identically-named/valued
## constants (see that file's "Falling and swaying" section).
const FALL_SWAY_WORLD := 10.0
const FALL_SWAY_CYCLES := 2.2
const FALL_ROTATION_MAX_RADIANS := 0.34906585039886593  # deg_to_rad(20.0)
const GROUND_SWAY_RADIANS := 0.06981317007977318  # deg_to_rad(4.0)
const GROUND_SWAY_PERIOD := 3.2

## See this file's own doc comment above ("Why the start time is a WRAPPED
## fraction") for why this MUST equal GROUND_SWAY_PERIOD exactly.
const WRAP_PERIOD := GROUND_SWAY_PERIOD

## Bounds the packed transition-offset channels. Comfortably covers the
## initial fall (DroppedItem.FALL_HEIGHT was 40.0) and the furthest any
## dispersal trigger can nudge a settled leaf in one hop -- WindDispersal's
## own hard ceiling (MAX_TRAVEL_TILES) is the largest of the three triggers
## by a wide margin (wind can drift a light seed-weight object much further
## than a single footstep/creature-contact nudge), so it is what actually
## sizes this bound.
const MAX_TRANSITION_OFFSET := WindDispersal.MAX_TRAVEL_TILES * TerrainRenderer.TILE_SIZE

## Turns a real tumbling leaf completes over one full transition, at the
## short end (a settle back into place after a footstep/animal nudge, or the
## short canopy-height fall-in -- see LeafLitterField.FALL_HEIGHT) and the
## long end (a leaf actually carried MAX_TRANSITION_OFFSET by real wind --
## see tumble_turns_for_distance). A dry leaf visibly cartwheeling a few
## metres across open pavement in an ordinary gust is a familiar autumn
## sight completing several full rotations, not a fraction of one -- 3.0
## turns over the longest real journey this game models sits centrally in
## that everyday range; 0.5 turns for a journey too short to expose much of
## the leaf to moving air keeps a footstep-settle from spinning wildly in
## place. Pinned by test_tumble_turns_for_distance_is_minimum_at_zero_
## distance/test_tumble_turns_for_distance_is_maximum_at_the_reference_
## distance, not eyeballed.
const MIN_TUMBLE_TURNS := 0.5
const MAX_TUMBLE_TURNS := 3.0

## How many loops a leaf's PATH completes as it swirls toward its settled
## target -- reported directly: "the leaves and blossoms have a lot of
## left/right movements where they end up on the same place where they
## started and it doesn't look natural as it's a straight line ... move
## them a bit with a left right swirl / spiral motion or tumbles or so ...
## varying". The previous shape (transition_flutter_world, now removed)
## swayed along ONE FIXED AXIS -- perpendicular to the straight-line travel
## direction -- with an amplitude that decayed to exactly zero by landing,
## which reads exactly as reported: a straight line with a symmetric
## side-to-side wobble riding on top, always snapping back onto the line.
## instance_swirl_offset instead curls through BOTH the direction-of-travel
## and perpendicular axes together (see that function's own doc comment),
## tracing a real loop around the straight-line path rather than
## oscillating along one fixed line.
##
## The range mirrors MIN_TUMBLE_TURNS/MAX_TUMBLE_TURNS's own real-world
## grounding at a more restrained ceiling: the PATH's own loop is a
## secondary visual read behind the leaf's own body spin (tumble_rotation),
## so a busier loop than the body's own rotation would compete with it
## rather than read as one coherent tumbling-and-curling fall. Varies PER
## LEAF (see swirl_turns_for_seed/swirl_seed_for_position) rather than one
## fixed value for every leaf, which is the concrete "varying" the report
## asks for -- verified by direct render, not assumed from the numbers
## alone (see tools/probe_leaf_swirl_path.gd).
const MIN_SWIRL_TURNS := 0.4
const MAX_SWIRL_TURNS := 1.8

## How wide a leaf's own loop swings, as a fraction of FALL_SWAY_WORLD --
## varies per leaf ALONGSIDE swirl_turns, but independently of it (see
## test_swirl_radius_fraction_is_not_simply_the_turns_fraction_restated),
## so some leaves trace a wide, lazy loop, others a tight, fast one, rather
## than every leaf's spiral being sized the same way its turn count is.
## Never below half of FALL_SWAY_WORLD (the loop should still read as a
## real swirl at its narrowest, not shrink away to an imperceptible wiggle)
## and never above the full amount (the same ceiling the old flutter's own
## amplitude was already tuned against).
const MIN_SWIRL_RADIUS_FRACTION := 0.5
const MAX_SWIRL_RADIUS_FRACTION := 1.0

static var SHADER_CODE: String = _build_shader_code()


# -- packing/unpacking (mirrors the GLSL's own INSTANCE_CUSTOM decode) -------

## Mirrors GLSL: `float cell_index = round(INSTANCE_CUSTOM.r * (cell_count - 1.0));`
static func pack_cell_index(cell_index: int, cell_count: int) -> float:
	return float(cell_index) / float(maxi(cell_count - 1, 1))


static func unpack_cell_index(fraction: float, cell_count: int) -> int:
	return clampi(int(round(fraction * float(maxi(cell_count - 1, 1)))), 0, cell_count - 1)


## Mirrors GLSL: `vec2 raw_offset = (INSTANCE_CUSTOM.gb - 0.5) * 2.0 * max_transition_offset;`
static func pack_offset_axis(value: float) -> float:
	return clampf(value / MAX_TRANSITION_OFFSET * 0.5 + 0.5, 0.0, 1.0)


static func unpack_offset_axis(fraction: float) -> float:
	return (fraction - 0.5) * 2.0 * MAX_TRANSITION_OFFSET


## Mirrors GLSL: `float start_fraction = INSTANCE_CUSTOM.a;` (packed the same
## way current_time_fraction is -- see set_current_time).
static func pack_time_fraction(seconds: float) -> float:
	return fposmod(seconds, WRAP_PERIOD) / WRAP_PERIOD


# -- the ported fall/sway math -------------------------------------------------

## Smoothstep -- mirrors DroppedItem._step_fall's own `eased` line exactly
## ("t * t * (3.0 - 2.0 * t) # smoothstep: ease in, ease out"), and GLSL:
## `float eased = t * t * (3.0 - 2.0 * t);`
static func eased_progress(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## How much of the transition's own starting offset is left to show, 1.0 at
## the very start decaying to 0.0 once complete. Mirrors DroppedItem's
## `position = _fall_origin.lerp(_fall_target, eased)`, re-expressed as an
## offset from the TARGET rather than a lerp between two absolute points
## (see instances_for_leaves/pack_instance_custom_data's own doc comment for
## why: a MultiMesh instance's transform is set to the TARGET once and never
## re-touched, so the shader must add a decaying OFFSET to it instead of
## re-computing a lerp with no CPU help). GLSL: `float remaining = 1.0 - eased;`
static func remaining_offset_fraction(t: float) -> float:
	return 1.0 - eased_progress(t)


## Real elapsed seconds since a transition's own packed start, recovered from
## two WRAPPED fractions on the SAME clock (see this file's own doc comment
## on why wrapping is safe here). Mirrors GLSL:
## `float elapsed = fract(current_time_fraction - start_fraction) * wrap_period;`
static func elapsed_seconds(start_fraction: float, current_fraction: float) -> float:
	return fposmod(current_fraction - start_fraction, 1.0) * WRAP_PERIOD


## 0 at the instant a transition starts, 1 once TRANSITION_DURATION has
## elapsed. GLSL: `float t = clamp(elapsed / transition_duration, 0.0, 1.0);`
static func transition_t(start_fraction: float, current_fraction: float) -> float:
	return clampf(
		elapsed_seconds(start_fraction, current_fraction) / LeafLitterField.TRANSITION_DURATION,
		0.0, 1.0
	)


## A per-leaf phase derived from its own SETTLED position rather than a
## stored per-instance value (there is no channel budget left for one -- see
## this file's own doc comment on the 4 packed channels) -- the same
## position-derived-jitter idiom illustrated_grass_patch's own shader already
## uses for its per-blade wind phase (`v_root.x * 0.071 + v_root.y * 0.043`).
## The classic GLSL fract(sin(x)*43758.5453) hash; `fposmod(v, 1.0)` is GLSL
## `fract` (see SnowBombShader's own doc comment on that exact equivalence).
## Mirrors GLSL:
##   vec2 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
##   float phase = fract(sin(root.x * 0.0973 + root.y * 0.1187) * 43758.5453) * TAU;
static func phase_for_position(position: Vector2) -> float:
	var h := sin(position.x * 0.0973 + position.y * 0.1187) * 43758.5453
	return fposmod(h, 1.0) * TAU


## A second, independent per-leaf hash -- DELIBERATELY different magic
## constants from phase_for_position's own, so a leaf's swirl shape (how
## many loops, how wide) varies independently of its flutter/tumble phase
## rather than the two always moving together because they share one
## number. Same fract(sin(x)*big_constant) idiom this file already
## establishes for position-derived variety with no stored channel needed.
## GLSL:
##   float swirl_seed = fract(sin(root.x * 0.1361 + root.y * 0.0827) * 12945.017);
static func swirl_seed_for_position(position: Vector2) -> float:
	var h := sin(position.x * 0.1361 + position.y * 0.0827) * 12945.017
	return fposmod(h, 1.0)


## How many loops THIS leaf's own swirl completes (see MIN_SWIRL_TURNS's own
## doc comment for the real-world reasoning behind the range). GLSL:
##   float swirl_turns = mix(min_swirl_turns, max_swirl_turns, swirl_seed);
static func swirl_turns_for_seed(seed_value: float) -> float:
	return lerpf(MIN_SWIRL_TURNS, MAX_SWIRL_TURNS, clampf(seed_value, 0.0, 1.0))


## How wide THIS leaf's own loop swings, as a fraction of FALL_SWAY_WORLD.
## Reads a DIFFERENT sub-value than swirl_turns_for_seed's own raw seed
## (see MIN_SWIRL_RADIUS_FRACTION's own doc comment for why), so turn-count
## and loop-width vary independently rather than always moving together.
## GLSL:
##   float swirl_radius_fraction = mix(
##       min_swirl_radius_fraction, max_swirl_radius_fraction, fract(swirl_seed * 7.0));
static func swirl_radius_fraction_for_seed(seed_value: float) -> float:
	return lerpf(
		MIN_SWIRL_RADIUS_FRACTION, MAX_SWIRL_RADIUS_FRACTION, fposmod(seed_value * 7.0, 1.0)
	)


## The swirling offset (world pixels) at progress `t`: a real loop curling
## through BOTH `direction` (the transition's own straight-line travel
## axis) and `perpendicular` together, rather than a wobble confined to
## `perpendicular` alone (see MIN_SWIRL_TURNS's own doc comment for why
## that read as "a straight line with a symmetric side-to-side wobble" --
## the reported bug this replaces). Traced as a rotating radius in the
## (direction, perpendicular) basis -- `angle` sweeps around as `t`
## advances, so the offset genuinely curls rather than sliding back and
## forth along one fixed line -- with `radius` shaped as a BUMP (zero at
## t==0, widest around the middle of the journey, zero again at t==1, via
## sin(t*PI)) rather than a one-sided decay: a leaf's real transition_from
## IS its true starting point, so the swirl should not displace it away
## from there any more than it should leave it stranded off its real
## target. `phase` reuses the SAME position-derived phase flutter/tumble
## already read (so a leaf's spiral begins at the same "moment" its own
## tumble does -- no jarring seam between the two), `swirl_seed` is the
## second, independent per-leaf hash (see swirl_seed_for_position) driving
## how many loops and how wide THIS leaf's own spiral is. GLSL:
##   float swirl_turns = mix(min_swirl_turns, max_swirl_turns, swirl_seed);
##   float swirl_radius_fraction = mix(
##       min_swirl_radius_fraction, max_swirl_radius_fraction, fract(swirl_seed * 7.0));
##   float swirl_angle = t * TAU * swirl_turns + phase;
##   float swirl_radius = fall_sway_world * swirl_radius_fraction * sin(t * PI);
##   vec2 swirl_offset = (direction * cos(swirl_angle) + perpendicular * sin(swirl_angle)) * swirl_radius;
static func instance_swirl_offset(
	t: float, phase: float, swirl_seed: float, direction: Vector2, perpendicular: Vector2
) -> Vector2:
	var turns := swirl_turns_for_seed(swirl_seed)
	var radius_fraction := swirl_radius_fraction_for_seed(swirl_seed)
	var angle := t * TAU * turns + phase
	var radius := FALL_SWAY_WORLD * radius_fraction * sin(t * PI)
	return (direction * cos(angle) + perpendicular * sin(angle)) * radius


## The wobble a leaf carries WHILE actively transitioning, tapering to zero
## by the time the transition completes (the same (1.0 - t) taper shape
## instance_swirl_offset's own radius uses, just as a one-sided decay here
## rather than a bump -- this is the sprite's own body rotation, not the
## ground-plane path, so it has no equivalent "must not displace the real
## t==0 starting point" concern to guard against). Mirrors DroppedItem._step_
## fall's own rotation line exactly:
##   sin(t * TAU * FALL_SWAY_CYCLES + _sway_phase) * deg_to_rad(20.0) * (1.0 - t)
## GLSL: `float transition_rotation = sin(t * TAU * fall_sway_cycles + phase) * fall_rotation_max * (1.0 - t);`
static func transition_rotation(t: float, phase: float) -> float:
	return sin(t * TAU * FALL_SWAY_CYCLES + phase) * FALL_ROTATION_MAX_RADIANS * (1.0 - t)


## How many full turns a transition covering `distance` world pixels
## completes -- linearly scaled between MIN_TUMBLE_TURNS (near-zero
## distance: a footstep settle, or the short canopy fall-in) and
## MAX_TUMBLE_TURNS (at or past MAX_TRANSITION_OFFSET, the longest real
## wind-blown journey this game models), clamped past that reference
## distance rather than spinning ever faster. TRANSITION_DURATION is the
## SAME fixed 0.9s for every transition regardless of distance (see that
## constant's own doc comment), so a longer journey is also a FASTER one --
## scaling turns by distance is equivalently scaling them by how hard the
## wind is actually moving this leaf, which is the real thing that makes a
## tumbling leaf spin harder. GLSL:
##   float tumble_turns = mix(min_tumble_turns, max_tumble_turns,
##       clamp(length(raw_offset) / max_transition_offset, 0.0, 1.0));
static func tumble_turns_for_distance(distance: float) -> float:
	var fraction := clampf(distance / MAX_TRANSITION_OFFSET, 0.0, 1.0)
	return lerpf(MIN_TUMBLE_TURNS, MAX_TUMBLE_TURNS, fraction)


## Which way THIS leaf spins -- a real tumbling leaf's rotation direction is
## effectively arbitrary per event (whichever edge the wind catches first),
## so two leaves tumbling side by side should not all spin the same way any
## more than they should all flutter in lockstep (see phase_for_position's
## own doc comment on that identical banding concern) -- reuses the SAME
## position-derived phase already computed for flutter/wobble rather than
## spending a channel on a dedicated spin-direction bit. GLSL:
##   float spin_direction = mod(phase, TAU) < PI ? 1.0 : -1.0;
static func spin_direction_for_phase(phase: float) -> float:
	return 1.0 if fposmod(phase, TAU) < PI else -1.0


## The accumulating tumble -- UNLIKE transition_rotation's own wobble (which
## oscillates back toward zero, see that function's own "reaches zero once
## complete" test), a real tumbling leaf does not un-spin itself: this grows
## monotonically with progress and reaches its own full turn count exactly
## once the transition completes, continuing in the ONE direction
## spin_direction_for_phase picked for this leaf. Summed with
## transition_rotation (not replacing it) in vertex() below, so a short,
## near-zero-distance settle still keeps transition_rotation's own gentle
## settling wobble riding on top of a small real spin, while a long
## wind-blown journey's spin dominates. GLSL:
##   float tumble_rotation = t * tumble_turns * TAU * spin_direction;
static func tumble_rotation(t: float, distance: float, phase: float) -> float:
	return t * tumble_turns_for_distance(distance) * TAU * spin_direction_for_phase(phase)


## The gentle ongoing rock a SETTLED leaf keeps -- mirrors DroppedItem.
## _step_ground_sway exactly (`sin(_age * TAU / GROUND_SWAY_PERIOD +
## _sway_phase) * GROUND_SWAY_RADIANS`), but driven off the SAME wrapped
## current_time_fraction the transition math reads (see this file's own doc
## comment on why WRAP_PERIOD == GROUND_SWAY_PERIOD makes
## `current_time_fraction * TAU / GROUND_SWAY_PERIOD * WRAP_PERIOD` reduce to
## exactly `current_time_fraction * TAU`, with no separate real-seconds
## value needed). GLSL:
## `float settled_rotation = sin(current_time_fraction * TAU + phase) * ground_sway_radians;`
static func settled_sway_rotation(current_time_fraction: float, phase: float) -> float:
	return sin(current_time_fraction * TAU + phase) * GROUND_SWAY_RADIANS


# -- pure data prep: position / atlas index / packed fall-start --------------

## One leaf's packed INSTANCE_CUSTOM Color -- see this file's own doc comment
## for the 4-channel layout.
static func pack_instance_custom_data(
	cell_index: int, cell_count: int, transition_from: Vector2, position: Vector2, transition_start: float
) -> Color:
	var raw_offset := transition_from - position
	return Color(
		pack_cell_index(cell_index, cell_count),
		pack_offset_axis(raw_offset.x),
		pack_offset_axis(raw_offset.y),
		pack_time_fraction(transition_start),
	)


## Pure data prep, headlessly testable on its own (no MultiMesh/Texture2D
## access) -- computes every leaf's instance transform (pinned at its own
## settled TARGET position; the shader adds the decaying transition offset,
## see this file's own doc comment) and packed custom data, from plain
## LeafLitterField records only. `current_time_fraction` is accepted (rather
## than read from a shared clock) purely so this stays a pure function --
## real callers pass whatever set_current_time was last given.
static func instances_for_leaves(
	leaves: Array[Dictionary], atlas: LeafLitterAtlas, _current_time_fraction: float
) -> Array[Dictionary]:
	var instances: Array[Dictionary] = []
	for leaf in leaves:
		var cell_index := atlas.cell_index(leaf.species, leaf.season)
		instances.append({
			"transform": Transform2D(0.0, leaf.position),
			"custom_data": pack_instance_custom_data(
				cell_index, atlas.cell_count(), leaf.transition_from, leaf.position, leaf.transition_start
			),
		})
	return instances


static func _build_shader_code() -> String:
	return """
shader_type canvas_item;

uniform sampler2D atlas_texture : filter_linear, repeat_disable;
uniform float atlas_cell_count = 12.0;
uniform float atlas_cell_size_px = 68.0;
uniform float atlas_stamp_size_px = 64.0;
uniform float atlas_padding_px = 2.0;
uniform float atlas_width_px = 816.0;

uniform float max_transition_offset = %s;
uniform float wrap_period = %s;
uniform float transition_duration = %s;
uniform float fall_sway_world = %s;
uniform float fall_sway_cycles = %s;
uniform float fall_rotation_max = %s;
uniform float ground_sway_radians = %s;
uniform float min_tumble_turns = %s;
uniform float max_tumble_turns = %s;
uniform float min_swirl_turns = %s;
uniform float max_swirl_turns = %s;
uniform float min_swirl_radius_fraction = %s;
uniform float max_swirl_radius_fraction = %s;

// Pushed once per relevant tick (see set_current_time) -- NOT per instance,
// the same "the CPU's whole per-frame job becomes pushing one float" cost
// SnowBombShader's own snow_depth uniform already established in this
// codebase.
uniform float current_time_fraction = 0.0;

varying vec4 v_region;

void vertex() {
	// r: packed cell index (see pack_cell_index/unpack_cell_index).
	float cell_index = round(INSTANCE_CUSTOM.r * (atlas_cell_count - 1.0));
	float cell_x0 = (cell_index * atlas_cell_size_px + atlas_padding_px) / atlas_width_px;
	float cell_x1 = cell_x0 + atlas_stamp_size_px / atlas_width_px;
	float cell_y0 = atlas_padding_px / atlas_cell_size_px;
	float cell_y1 = cell_y0 + atlas_stamp_size_px / atlas_cell_size_px;
	v_region = vec4(cell_x0, cell_y0, cell_x1, cell_y1);

	// g/b: packed transition-offset x/y (see pack_offset_axis).
	vec2 raw_offset = (INSTANCE_CUSTOM.gb - 0.5) * 2.0 * max_transition_offset;
	// a: packed, wrapped transition-start time (see pack_time_fraction).
	float start_fraction = INSTANCE_CUSTOM.a;
	float elapsed = fract(current_time_fraction - start_fraction) * wrap_period;
	float t = clamp(elapsed / transition_duration, 0.0, 1.0);
	float eased = t * t * (3.0 - 2.0 * t);
	float remaining = 1.0 - eased;

	vec2 direction = length(raw_offset) > 0.001 ? normalize(raw_offset) : vec2(0.0, 1.0);
	vec2 perpendicular = vec2(-direction.y, direction.x);

	// Per-leaf phase derived from its own settled position -- no stored
	// channel needed (see phase_for_position's own doc comment).
	vec2 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	float phase = fract(sin(root.x * 0.0973 + root.y * 0.1187) * 43758.5453) * TAU;

	// A SECOND, independent per-leaf hash driving how this leaf's own
	// swirl is shaped (see swirl_seed_for_position's own doc comment for
	// why this is deliberately NOT the same hash as phase above).
	float swirl_seed = fract(sin(root.x * 0.1361 + root.y * 0.0827) * 12945.017);

	// The swirl: a real loop curling through BOTH direction and
	// perpendicular together (see instance_swirl_offset's own doc comment
	// for why this replaces a wobble confined to perpendicular alone).
	// swirl_radius is a BUMP -- zero at t==0 and t==1, widest around the
	// middle -- so the leaf still starts and lands exactly where its own
	// straight-line offset says it should.
	float swirl_turns = mix(min_swirl_turns, max_swirl_turns, swirl_seed);
	float swirl_radius_fraction = mix(min_swirl_radius_fraction, max_swirl_radius_fraction, fract(swirl_seed * 7.0));
	float swirl_angle = t * TAU * swirl_turns + phase;
	float swirl_radius = fall_sway_world * swirl_radius_fraction * sin(t * PI);
	vec2 swirl_offset = (direction * cos(swirl_angle) + perpendicular * sin(swirl_angle)) * swirl_radius;
	vec2 offset = raw_offset * remaining + swirl_offset;

	// Real litter tumbling in wind visibly spins THROUGH, not merely
	// wobbles (see tumble_rotation's own doc comment) -- scaled by how far
	// this transition actually carries the leaf, so a footstep settle
	// barely turns where a real wind-blown journey cartwheels several
	// times.
	float tumble_turns = mix(
		min_tumble_turns, max_tumble_turns,
		clamp(length(raw_offset) / max_transition_offset, 0.0, 1.0)
	);
	float spin_direction = mod(phase, TAU) < PI ? 1.0 : -1.0;
	float tumble_rot = t * tumble_turns * TAU * spin_direction;

	float transition_rot = sin(t * TAU * fall_sway_cycles + phase) * fall_rotation_max * (1.0 - t);
	float settled_rot = sin(current_time_fraction * TAU + phase) * ground_sway_radians;
	float total_rotation = transition_rot + tumble_rot + settled_rot;

	float cos_r = cos(total_rotation);
	float sin_r = sin(total_rotation);
	vec2 rotated = vec2(
		VERTEX.x * cos_r - VERTEX.y * sin_r,
		VERTEX.x * sin_r + VERTEX.y * cos_r
	);
	VERTEX = rotated + offset;
}

void fragment() {
	vec2 uv = mix(v_region.xy, v_region.zw, UV);
	COLOR = texture(atlas_texture, uv);
}
""" % [
		MAX_TRANSITION_OFFSET, WRAP_PERIOD, LeafLitterField.TRANSITION_DURATION,
		FALL_SWAY_WORLD, FALL_SWAY_CYCLES, FALL_ROTATION_MAX_RADIANS, GROUND_SWAY_RADIANS,
		MIN_TUMBLE_TURNS, MAX_TUMBLE_TURNS,
		MIN_SWIRL_TURNS, MAX_SWIRL_TURNS, MIN_SWIRL_RADIUS_FRACTION, MAX_SWIRL_RADIUS_FRACTION,
	]


var _atlas := LeafLitterAtlas.new()
var _material: ShaderMaterial
var _mesh: QuadMesh


func mesh() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(WORLD_SIZE, WORLD_SIZE)
	return _mesh


## Every uniform the mirror pins is pushed from the GDScript constant of the
## same name -- mirrors SnowBombShader's own material()/refresh_uniforms
## convention (see that file's doc comment on why: so the two can never
## drift out of sync with each other).
func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("atlas_texture", _atlas.atlas_texture())
		_material.set_shader_parameter("atlas_cell_count", float(_atlas.cell_count()))
		_material.set_shader_parameter("atlas_cell_size_px", float(LeafLitterAtlas.CELL_SIZE))
		_material.set_shader_parameter("atlas_stamp_size_px", float(LeafLitterAtlas.STAMP_SIZE))
		_material.set_shader_parameter("atlas_padding_px", float(LeafLitterAtlas.STAMP_PADDING))
		_material.set_shader_parameter(
			"atlas_width_px", float(_atlas.cell_count() * LeafLitterAtlas.CELL_SIZE)
		)
		_material.set_shader_parameter("current_time_fraction", 0.0)
	return _material


## Pushes the live wrapped clock (see pack_time_fraction) the shader's own
## transition/sway math reads -- called once per relevant tick (see
## EarthChunkManager's own renderer wiring), not per instance.
func set_current_time(world_age_seconds: float) -> void:
	material().set_shader_parameter("current_time_fraction", pack_time_fraction(world_age_seconds))


## Rebuilds `mmi` (wiring its MultiMesh/texture/material on first use) so it
## renders every leaf in `leaves` (see LeafLitterField.leaves). Thin engine
## glue over instances_for_leaves -- see that function for the actual
## (headlessly-tested) placement/packing math. This wrapper itself needs a
## real renderer to verify: MultiMesh per-instance transform/custom-data
## storage is backed by the dummy renderer under --headless and silently
## doesn't round-trip there (same caveat illustrated_grass_patch.gd's own
## fill_band already documents).
func fill(mmi: MultiMeshInstance2D, leaves: Array[Dictionary]) -> void:
	if mmi.multimesh == null:
		var new_mm := MultiMesh.new()
		new_mm.mesh = mesh()
		new_mm.transform_format = MultiMesh.TRANSFORM_2D
		new_mm.use_custom_data = true
		mmi.multimesh = new_mm
		mmi.material = material()
	var mm: MultiMesh = mmi.multimesh
	var instances := instances_for_leaves(leaves, _atlas, 0.0)
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform_2d(i, instances[i].transform)
		mm.set_instance_custom_data(i, instances[i].custom_data)
