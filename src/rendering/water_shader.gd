extends RefCounted

## GPU water: continuous, physically-inspired waves rendered in world space
## over every ocean cell -- the fluid motion 4-frame tile art (and, before
## that, the hard-edged baked shore/foam tiles) fundamentally can't express.
##
## The WaterFx overlay TileMapLayer (see EarthChunkManager.set_water_layer)
## is painted with a small "shore distance" tile family (see
## procedural_shore_distance_sprite.gd, TerrainRenderer.RING_MAX): each
## tile's red channel encodes distance to the nearest land, spanning several
## tiles (not just one) so the effects below have room to actually be seen.
## This shader reads that channel as DATA, not art, and uses it to do
## everything that used to live in discrete baked tiles -- continuously,
## per-pixel, on the GPU:
##
## - Shore "bounce": an incident wave (traveling toward the coast) and its
##   reflection (traveling away) are summed near the shore -- real standing-
##   wave interference at a boundary, spanning the first couple of shore
##   rings and fading out toward open water.
## - Raindrops make waves: while it's raining (rain_intensity, driven by the
##   live weather model via set_rain_intensity), a hash-seeded grid of drop
##   points continuously spawns expanding ring ripples, several overlapping
##   at once.
## - Movement disturbances: a fish darting past, or a player/animal wading or
##   swimming, records a world-space point (see record_water_disturbance /
##   add_disturbance) that spawns its own expanding, fading ring -- the same
##   technique as raindrops, anchored to a real position instead of a hashed
##   grid.
##
## Deliberately NOT wind-driven: water used to have an always-on ambient
## chop paced by wind_strength, so even an untouched pond had constant
## motion. Ripples now only come from something actually causing them --
## rain, or a fish/player/animal in the water -- so undisturbed water stays
## flat (reported: "ripples should ... not [come from] wind").
##
## All sources sum into ONE combined wave field before being mapped to
## color -- where they overlap, they genuinely interfere (constructive/
## destructive), not just draw over each other. Alpha also fades smoothly
## with shore distance, so the ocean melts into the coastline instead of
## cutting off at a tile edge. Everything runs on TIME/world position: fully
## fluid at any frame rate, zero per-frame script. Contract pinned by
## test_water_shader.gd.
##
## Honest scope note: this is a stylized, GPU-cheap APPROXIMATION of real
## water physics (superposed traveling waves + a boundary reflection term),
## not a shallow-water-equation solve -- the right fidelity for 16px top-down
## pixel art, not a claim of simulating fluid dynamics exactly.

const SHADER_CODE := """
shader_type canvas_item;

uniform float alpha_strength = 0.6;
uniform float noise_scale = 0.045;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
// Wind animates the surface TEXTURE only -- it never feeds the ripple wave
// field below. Ripples are rings from rain and movement; this is the
// living shimmer the surface has between them.
uniform float wind_strength = 1.0;
uniform float scroll_speed = 0.55;
uniform float wind_chop_strength = 0.07;
uniform float rain_strength = 0.55;
uniform vec3 deep_color : source_color = vec3(0.04, 0.22, 0.5);
uniform vec3 crest_color : source_color = vec3(0.16, 0.42, 0.72);
uniform vec3 trough_color : source_color = vec3(0.02, 0.14, 0.34);
uniform float wave_low_threshold = 0.05;
uniform float wave_high_threshold = 0.45;
uniform float edge_alpha_fade_start = 0.0;
uniform float edge_alpha_fade_end = 0.5;

// Ripple shape/decay tuning -- pushed from the GDScript constants of the
// same name (see make_material) rather than written as literals here, so
// ripple_amplitude() can mirror this math on the CPU and actually be tested.
uniform float ripple_speed = 14.0;
uniform float ripple_lifetime = 2.2;
uniform float ripple_wavelength = 6.0;
uniform float ripple_packet_width = 7.0;
uniform float ripple_spread_decay = 0.02;
// Rain gets its OWN, much tighter tuning: a raindrop is a small quick
// splash, not a swimmer's wake. Sharing the wake's packet made every drop a
// multi-tile bullseye.
uniform float rain_ripple_speed = 8.0;
uniform float rain_ripple_lifetime = 0.9;
uniform float rain_ripple_wavelength = 3.0;
uniform float rain_ripple_packet_width = 3.5;

// Ripple-causing disturbances: rain (above), plus discrete world-space
// events -- a fish darting past, a player or animal wading/swimming (see
// EarthChunkManager.record_water_disturbance). Deliberately NOT wind: an
// empty, still pond with nothing moving in or over it should stay flat.
// disturbance_age is each event's elapsed seconds since it happened,
// updated and re-pushed every frame from GDScript (see
// WaterShader.advance_disturbances) -- NOT computed here from TIME minus a
// CPU timestamp. The shader's TIME and CPU wall-clock time (Time.
// get_ticks_msec()) are two independent clocks with no guaranteed epoch
// alignment; comparing them produced a persistently out-of-range age, so
// the ripple was always discarded and never actually appeared (reported:
// "neither the fish nor player or creature movement cause ripples").
uniform vec2 disturbance_pos[16];
uniform float disturbance_age[16];
uniform int disturbance_count = 0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float value_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = value_hash(i);
	float b = value_hash(i + vec2(1.0, 0.0));
	float c = value_hash(i + vec2(0.0, 1.0));
	float d = value_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ONE expanding wave packet -- the shared shape of every ripple in this
// water, whether a raindrop's splash or a fish's wake.
//
// Not a single hard ring: a travelling wave PACKET of several concentric
// crests and troughs behind the front, decaying both with age and with the
// circumference it has to spread its energy around. A lone ring read as an
// expanding hoop, not as water. Mirrored on the CPU by
// WaterShader.ripple_amplitude (which is what pins this tuning under test).
//
// Returns a SIGNED displacement: crests positive, troughs negative, so
// overlapping ripples genuinely interfere instead of only ever adding.
float ripple_packet(
	float dist, float age, float speed, float lifetime, float wavelength, float packet_width
) {
	if (age < 0.0 || age > lifetime) {
		return 0.0;
	}
	float front = age * speed;
	float phase = front - dist;  // > 0 = inside the advancing front
	float packet = exp(-abs(phase) / packet_width);
	float rings = sin(phase * 6.28318530718 / wavelength);
	float age_fade = 1.0 - age / lifetime;
	float spread_fade = 1.0 / (1.0 + front * ripple_spread_decay);
	return rings * packet * age_fade * spread_fade;
}

// Cellular raindrop ripples: each grid cell spawns one splash per cycle at a
// hash-derived point and time offset. Neighboring cells are sampled too, so
// a ripple that originated next door still renders as it expands across the
// cell boundary -- rain_ripple_lifetime is kept short enough that a splash
// stays within that 3x3 reach.
float raindrop_ripples(vec2 pos) {
	if (rain_intensity <= 0.001) {
		return 0.0;
	}
	float cell_size = 14.0;
	float interval = 1.6;
	float total = 0.0;
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cell = floor(pos / cell_size) + vec2(float(ox), float(oy));
			float seed = value_hash(cell);
			float age = mod(TIME + seed * interval * 7.0, interval);
			vec2 drop_pos = (cell + vec2(value_hash(cell + 7.3), value_hash(cell + 41.7))) * cell_size;
			total += ripple_packet(
				distance(pos, drop_pos), age,
				rain_ripple_speed, rain_ripple_lifetime,
				rain_ripple_wavelength, rain_ripple_packet_width
			);
		}
	}
	return total * rain_intensity;
}

// The same wave packet, anchored to explicitly recorded positions and a
// CPU-driven age instead of a hashed grid -- a fish's wake or a swimmer's
// trail (see EarthChunkManager.record_water_disturbance).
float movement_ripples(vec2 pos) {
	float total = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= disturbance_count) {
			continue;
		}
		total += ripple_packet(
			distance(pos, disturbance_pos[i]), disturbance_age[i],
			ripple_speed, ripple_lifetime, ripple_wavelength, ripple_packet_width
		);
	}
	return total;
}

void fragment() {
	vec2 p = world_pos * noise_scale;

	// Shore distance: baked into this tile's own texture as a DATA channel
	// (see procedural_shore_distance_sprite.gd), spanning multiple tiles via
	// TerrainRenderer.RING_MAX -- 0 at the land edge, ramping outward over
	// several tiles instead of snapping within a single one.
	float shore_dist = sqrt(texture(TEXTURE, UV).r);

	// NOTE: a shore standing-wave term used to live here (incident +
	// reflected, pulsed by TIME). It made the ENTIRE body of water rise and
	// fall in lockstep with nothing moving in it, which is both unphysical
	// once ambient waves are gone (nothing arrives at the shore to reflect)
	// and was the loudest thing on screen once the crest thresholds were
	// corrected. Removed -- shore_dist now only drives the alpha fade below.
	float rain = raindrop_ripples(world_pos);
	float movement = movement_ripples(world_pos);

	// Both sources sum before mapping to color -- where they overlap, they
	// genuinely interfere (constructive AND destructive, since both terms
	// are signed), not just draw over each other. Nothing else contributes:
	// water with no rain and nothing moving in it stays flat.
	float wave = rain * rain_strength + movement;

	// Crests brighten and troughs darken away from the same deep baseline,
	// so a ripple reads as relief on the surface rather than as a glowing
	// ring painted on top of it. Both use ascending smoothstep edges (GLSL
	// leaves edge0 > edge1 undefined), the trough side by negating `wave`.
	vec3 water = deep_color;
	water = mix(water, crest_color, smoothstep(wave_low_threshold, wave_high_threshold, wave));
	water = mix(water, trough_color, smoothstep(wave_low_threshold, wave_high_threshold, -wave));

	// Wind-driven surface shimmer: two octaves of value noise scrolling at
	// different speeds/directions, so the surface shears rather than sliding
	// as one sheet. Added as a gentle brightness modulation AFTER the ripple
	// coloring and deliberately NOT summed into `wave` -- wind moves the
	// surface texture, it does not spawn rings.
	float wind_rate = scroll_speed * wind_strength;
	float swell = value_noise(p + vec2(TIME * wind_rate, TIME * wind_rate * 0.35));
	float chop = value_noise(p * 2.3 - vec2(TIME * wind_rate * 0.7, TIME * wind_rate * 0.2));
	float wind_chop = (swell * 0.65 + chop * 0.35) - 0.5;
	water += vec3(wind_chop * wind_chop_strength);

	// Fade smoothly into the coastline instead of cutting off at a tile
	// edge.
	float edge_alpha = smoothstep(edge_alpha_fade_start, edge_alpha_fade_end, shore_dist);
	COLOR = vec4(water, alpha_strength * edge_alpha);
}
"""

## Overlay opacity: high enough to own the water's look, low enough that the
## baked base water tile beneath (and the shore edge-alpha fade) stays part
## of the final look (pinned 0.2..0.75 by
## test_overlay_is_translucent_so_the_base_tile_layer_shows_through).
const WATER_ALPHA := 0.6

## Deep water: a dark, clearly-blue baseline most of the surface should read
## as -- pinned darker and more saturated than CREST_COLOR.
const DEEP_COLOR := Color(0.04, 0.22, 0.5)

## Wave crest: lighter than DEEP_COLOR but deliberately kept blue rather than
## trending toward white/cyan (the previous color read as "cloudy sky" when
## it dominated large areas -- pinned by test_crest_color_stays_clearly_
## blue_not_washed_out_toward_white).
const CREST_COLOR := Color(0.16, 0.42, 0.72)

## Wave trough: darker than DEEP_COLOR, so the far side of a ripple reads as
## a dip in the surface rather than the ripple being a bright ring stuck on
## top of flat water.
const TROUGH_COLOR := Color(0.02, 0.14, 0.34)

## smoothstep bounds mapping the combined (signed) wave value to
## trough_color..deep_color..crest_color.
##
## These were 0.55/0.95, tuned when an ambient wind-noise term held the wave
## field at a constant ~0.5 baseline. With that term gone, open water sits at
## 0.0 and those bounds meant a ripple had to reach 0.61 before it tinted
## anything at all -- so a ripple was visible only in its first fraction of a
## second, at near-zero radius, which is exactly the reported "sometimes a
## mini ripple appears but nothing looks natural". LOW is now just above flat
## water (so undisturbed water still reads deep, the original intent) and
## HIGH is reachable by a real ripple crest. Pinned by
## test_a_ripple_stays_visible_across_its_whole_lifetime.
const WAVE_LOW_THRESHOLD := 0.05
const WAVE_HIGH_THRESHOLD := 0.45

## smoothstep bounds mapping shore_dist (see fragment()'s `shore_dist =
## sqrt(texture(TEXTURE, UV).r)`) to the coastline alpha fade -- named
## constants (pushed as uniforms below) rather than shader-string literals
## for the same reason as the ripple tuning above: edge_alpha_for_shore_
## distance() mirrors this on the CPU so placement code elsewhere (e.g. the
## character preview diorama's fish, see character_preview_layout.gd's
## FISH_SAFE_RADIUS_FRACTION) can derive "is this point clearly, visibly
## water" from the SAME math the GPU actually draws with, instead of
## eyeballing a fraction of the pond's nominal (geometric, not visual)
## radius.
const EDGE_ALPHA_FADE_START := 0.0
const EDGE_ALPHA_FADE_END := 0.5

## Ripple shape/decay tuning, shared by raindrops and movement wakes. These
## are pushed into the shader as uniforms (see make_material) rather than
## duplicated as shader literals, so ripple_amplitude() below mirrors exactly
## what the GPU draws and the tuning can be tested rather than eyeballed.
## How fast a wake's front travels outward, in world units per second.
const RIPPLE_SPEED := 14.0
## How long a movement wake keeps expanding before it dies. Together with
## RIPPLE_SPEED this bounds a wake at ~1.9 tiles of radius: far enough to
## read as a wake, not so far that one fish visibly disturbs a whole pond.
const RIPPLE_LIFETIME := 2.2
## Distance between successive crests -- the packet holds a couple of these.
const RIPPLE_WAVELENGTH := 6.0
## How far behind the front the ring packet extends. Must exceed
## RIPPLE_WAVELENGTH or a ripple is a single lonely circle rather than the
## few concentric rings real water makes -- but only just, or it trails a
## bullseye of half a dozen rings.
const RIPPLE_PACKET_WIDTH := 7.0
## How quickly amplitude drops as the ring's circumference grows (energy
## spreading around a widening circle).
const RIPPLE_SPREAD_DECAY := 0.02

## Rain gets its OWN, much tighter tuning -- a raindrop is a small quick
## splash, not a swimmer's wake. Sharing the wake's packet made every drop a
## multi-tile bullseye (reported: "the ripples don't look as natural as
## before"). Pinned by
## test_a_raindrop_splash_is_much_smaller_than_a_movement_wake.
const RAIN_RIPPLE_SPEED := 12.0
const RAIN_RIPPLE_LIFETIME := 1.2
const RAIN_RIPPLE_WAVELENGTH := 4.0
const RAIN_RIPPLE_PACKET_WIDTH := 4.5

## Rain ripples read a touch too hard at full strength ("rain looked ok just
## a bit too strong ripples"), so the rain field is scaled back before it
## reaches the wave sum -- shape unchanged, just gentler.
const RAIN_STRENGTH := 0.55

## Baseline wind pacing -- matches WeatherModel.wind_strength_for("clear").
const DEFAULT_WIND_STRENGTH := 1.0
## How strongly the wind shimmer modulates surface brightness. Small on
## purpose: this is texture, and must never compete with an actual ripple.
const WIND_CHOP_STRENGTH := 0.07

## Cap on concurrent movement-disturbance ripples (fish, players/animals in
## water) -- matches the shader's fixed-size disturbance_pos/disturbance_age
## arrays, which GLSL can't size dynamically.
##
## Was 8, which every loaded fish (including ones far off-screen) churned
## through so fast that a wake was evicted almost the instant it appeared --
## why rain rendered fine while movement wakes stayed invisible. Raised, and
## paired with distance culling in EarthChunkManager.record_water_disturbance
## so off-screen swimmers can't crowd out the ones actually on screen.
const MAX_DISTURBANCES := 16

## How long a disturbance ring keeps expanding/fading before it's dropped.
## The same number the shader draws with (RIPPLE_LIFETIME, pushed as a
## uniform), so a ripple is never culled while still visible or kept alive
## after it has faded out.
const DISTURBANCE_LIFETIME := RIPPLE_LIFETIME

var _shared_material: ShaderMaterial
var _disturbance_positions: Array[Vector2] = []
var _disturbance_ages: Array[float] = []


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("alpha_strength", WATER_ALPHA)
	material.set_shader_parameter("rain_intensity", 0.0)
	material.set_shader_parameter("deep_color", DEEP_COLOR)
	material.set_shader_parameter("crest_color", CREST_COLOR)
	material.set_shader_parameter("trough_color", TROUGH_COLOR)
	material.set_shader_parameter("wave_low_threshold", WAVE_LOW_THRESHOLD)
	material.set_shader_parameter("wave_high_threshold", WAVE_HIGH_THRESHOLD)
	material.set_shader_parameter("edge_alpha_fade_start", EDGE_ALPHA_FADE_START)
	material.set_shader_parameter("edge_alpha_fade_end", EDGE_ALPHA_FADE_END)
	# One source of truth for the ripple tuning: the shader reads these as
	# uniforms so ripple_amplitude() below mirrors exactly what is drawn.
	material.set_shader_parameter("ripple_speed", RIPPLE_SPEED)
	material.set_shader_parameter("ripple_lifetime", RIPPLE_LIFETIME)
	material.set_shader_parameter("ripple_wavelength", RIPPLE_WAVELENGTH)
	material.set_shader_parameter("ripple_packet_width", RIPPLE_PACKET_WIDTH)
	material.set_shader_parameter("ripple_spread_decay", RIPPLE_SPREAD_DECAY)
	material.set_shader_parameter("rain_ripple_speed", RAIN_RIPPLE_SPEED)
	material.set_shader_parameter("rain_ripple_lifetime", RAIN_RIPPLE_LIFETIME)
	material.set_shader_parameter("rain_ripple_wavelength", RAIN_RIPPLE_WAVELENGTH)
	material.set_shader_parameter("rain_ripple_packet_width", RAIN_RIPPLE_PACKET_WIDTH)
	material.set_shader_parameter("rain_strength", RAIN_STRENGTH)
	material.set_shader_parameter("wind_strength", DEFAULT_WIND_STRENGTH)
	material.set_shader_parameter("wind_chop_strength", WIND_CHOP_STRENGTH)
	material.set_shader_parameter("disturbance_count", 0)
	material.set_shader_parameter("disturbance_pos", _padded_positions())
	material.set_shader_parameter("disturbance_age", _padded_ages())
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## The exact math the shader's ripple_packet runs, mirrored on the CPU so
## the tuning above is a tested function rather than eyeballed shader
## literals (a fragment shader can't be asserted headlessly).
##
## `distance_units` is how far the sampled point is from the disturbance;
## `age_seconds` is how long ago it happened. Returns a SIGNED displacement:
## positive on a crest, negative in a trough, zero once the ripple has died
## or ahead of its still-advancing front.
static func ripple_amplitude(
	distance_units: float, age_seconds: float, lifetime: float = RIPPLE_LIFETIME
) -> float:
	if age_seconds < 0.0 or age_seconds > lifetime:
		return 0.0
	var front := age_seconds * RIPPLE_SPEED
	var phase := front - distance_units
	var packet := exp(-absf(phase) / RIPPLE_PACKET_WIDTH)
	var rings := sin(phase * TAU / RIPPLE_WAVELENGTH)
	var age_fade := 1.0 - age_seconds / lifetime
	var spread_fade := 1.0 / (1.0 + front * RIPPLE_SPREAD_DECAY)
	return rings * packet * age_fade * spread_fade


## The exact math the shader's fragment() runs to fade alpha toward the
## coastline, mirrored on the CPU for the same reason ripple_amplitude()
## mirrors the ripple packet above -- so a placement decision ("is this
## point visibly water") can be a tested function against the real curve
## rather than an eyeballed fraction of the pond's geometric radius.
## `shore_dist` is the tile's own [0, ~0.71] shore-distance value (see
## procedural_shore_distance_sprite.gd -- sqrt of the raw per-pixel
## distance-to-nearest-land-edge channel), not a world-space distance.
static func edge_alpha_for_shore_distance(shore_dist: float) -> float:
	return smoothstep(EDGE_ALPHA_FADE_START, EDGE_ALPHA_FADE_END, shore_dist)


## Sets how strongly raindrop ripples show on the shared material (0 = none,
## 1 = full rain) -- see EarthChunkManager.set_rain, driven from the live
## weather model. A continuous parameter on an already-continuous shader, so
## even a hard 0/1 flip is just a ripple-strength change, not a visual swap.
func set_rain_intensity(intensity: float) -> void:
	shared_material().set_shader_parameter("rain_intensity", intensity)


## Sets how energetic the wind-driven SURFACE SHIMMER is (see
## WeatherModel.wind_strength_for, driven from the live weather model via
## EarthChunkManager.set_wind_strength). Paces the surface texture only --
## wind never spawns ripple rings, which come from rain and movement.
func set_wind_strength(strength: float) -> void:
	shared_material().set_shader_parameter("wind_strength", strength)


## Directly sets the disturbance-ripple uniforms -- `positions`/`ages` are
## padded by the caller to the shader's fixed array size; `count` is how many
## of those slots are actually live. Prefer add_disturbance()/
## advance_disturbances() for the normal record-then-age-every-frame flow;
## this exists for tests and callers that already maintain their own buffer.
func set_disturbances(positions: PackedVector2Array, ages: PackedFloat32Array, count: int) -> void:
	var material := shared_material()
	material.set_shader_parameter("disturbance_pos", positions)
	material.set_shader_parameter("disturbance_age", ages)
	material.set_shader_parameter("disturbance_count", count)


## Records a ripple-causing disturbance (a fish darting past, a player or
## animal wading/swimming) at `world_pos`, age 0 -- rendered as an expanding,
## fading ring by movement_ripples in the shader, exactly like
## raindrop_ripples, so it genuinely interferes with other wave sources
## rather than drawing over them. Oldest disturbance drops once
## MAX_DISTURBANCES is exceeded. Call advance_disturbances(delta) every frame
## afterward to actually age (and expand) the ring -- this alone just adds a
## fresh one at age 0.
func add_disturbance(world_pos: Vector2) -> void:
	_disturbance_positions.append(world_pos)
	_disturbance_ages.append(0.0)
	if _disturbance_positions.size() > MAX_DISTURBANCES:
		_disturbance_positions.pop_front()
		_disturbance_ages.pop_front()
	_push_disturbances()


## Ages every live disturbance by `delta` and drops any past
## DISTURBANCE_LIFETIME, re-pushing the uniforms so the shader's rings
## actually expand/fade over time. Deliberately CPU-driven rather than
## computed in the shader from TIME minus a stored timestamp: the shader's
## TIME and Time.get_ticks_msec() are independent clocks with no guaranteed
## epoch alignment, which silently made every ripple permanently "in the
## past" or "in the future" and so always discarded (reported: "neither the
## fish nor player or creature movement cause ripples").
func advance_disturbances(delta: float) -> void:
	if _disturbance_positions.is_empty():
		return
	var kept_positions: Array[Vector2] = []
	var kept_ages: Array[float] = []
	for i in _disturbance_positions.size():
		var age: float = _disturbance_ages[i] + delta
		if age > DISTURBANCE_LIFETIME:
			continue
		kept_positions.append(_disturbance_positions[i])
		kept_ages.append(age)
	_disturbance_positions = kept_positions
	_disturbance_ages = kept_ages
	_push_disturbances()


func _push_disturbances() -> void:
	set_disturbances(_padded_positions(), _padded_ages(), _disturbance_positions.size())


func _padded_positions() -> PackedVector2Array:
	var positions := PackedVector2Array(_disturbance_positions)
	while positions.size() < MAX_DISTURBANCES:
		positions.append(Vector2.ZERO)
	return positions


func _padded_ages() -> PackedFloat32Array:
	var ages := PackedFloat32Array(_disturbance_ages)
	while ages.size() < MAX_DISTURBANCES:
		ages.append(-999.0)
	return ages
