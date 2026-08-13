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
## - Ambient wind chop: two octaves of value noise scrolling at different
##   speeds/directions, so the surface shears rather than sliding as one
##   sheet. Its scroll rate is paced by wind_strength (driven by the live
##   weather model via set_wind_strength/WeatherModel.wind_strength_for), so
##   the same shore idles calmly on a clear day and churns faster/choppier
##   during a storm.
## - Shore "bounce": an incident wave (traveling toward the coast) and its
##   reflection (traveling away) are summed near the shore -- real standing-
##   wave interference at a boundary, spanning the first couple of shore
##   rings and fading out toward open water.
## - Raindrops make waves: while it's raining (rain_intensity, driven by the
##   live weather model via set_rain_intensity), a hash-seeded grid of drop
##   points continuously spawns expanding ring ripples, several overlapping
##   at once.
##
## All three sources sum into ONE combined wave field before being mapped to
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
uniform float scroll_speed = 0.55;
uniform float wind_strength = 0.3;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 deep_color : source_color = vec3(0.04, 0.22, 0.5);
uniform vec3 crest_color : source_color = vec3(0.16, 0.42, 0.72);
uniform float wave_low_threshold = 0.55;
uniform float wave_high_threshold = 0.95;

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

// Cellular raindrop ripples: each grid cell spawns one expanding ring per
// cycle at a hash-derived point and time offset. Neighboring cells are
// sampled too, so a ring that originated next door still renders correctly
// as it expands across the cell boundary. Several rings overlap and sum.
float raindrop_ripples(vec2 pos) {
	if (rain_intensity <= 0.001) {
		return 0.0;
	}
	float cell_size = 22.0;
	float interval = 1.7;
	float speed = 15.0;
	float total = 0.0;
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cell = floor(pos / cell_size) + vec2(float(ox), float(oy));
			float seed = value_hash(cell);
			float age = mod(TIME + seed * interval * 7.0, interval);
			vec2 drop_pos = (cell + vec2(value_hash(cell + 7.3), value_hash(cell + 41.7))) * cell_size;
			float dist = distance(pos, drop_pos);
			float radius = age * speed;
			float ring = 1.0 - smoothstep(0.0, 1.4, abs(dist - radius));
			float fade = 1.0 - age / interval;
			total += ring * fade * fade;
		}
	}
	return clamp(total, 0.0, 1.0) * rain_intensity;
}

void fragment() {
	vec2 p = world_pos * noise_scale;
	// wind_strength paces the whole ambient surface: calm and slow-scrolling
	// on a clear day, faster and choppier as weather worsens (see
	// WeatherModel.wind_strength_for / EarthChunkManager.set_wind_strength).
	float wind_rate = scroll_speed * wind_strength;
	float swell = value_noise(p + vec2(TIME * wind_rate, TIME * wind_rate * 0.35));
	float chop = value_noise(p * 2.3 - vec2(TIME * wind_rate * 0.7, TIME * wind_rate * 0.2));
	float ambient_wave = swell * 0.65 + chop * 0.35;

	// Shore distance: baked into this tile's own texture as a DATA channel
	// (see procedural_shore_distance_sprite.gd), spanning multiple tiles via
	// TerrainRenderer.RING_MAX -- 0 at the land edge, ramping outward over
	// several tiles instead of snapping within a single one.
	float shore_dist = sqrt(texture(TEXTURE, UV).r);

	// Incident + reflected wave, summed -- a real standing-wave interference
	// pattern at the coast ("waves bounce off the shore"), spanning the
	// first couple of shore rings and fading toward open water.
	float k = 10.0;
	float omega = 2.3;
	float incident = sin(shore_dist * k + TIME * omega);
	float reflected = sin(shore_dist * k - TIME * omega);
	float shore_band = clamp(1.0 - shore_dist / 0.6, 0.0, 1.0);
	float shore_bounce = (incident + reflected) * 0.5 * shore_band;

	float rain = raindrop_ripples(world_pos);

	// All three wave sources sum before mapping to color -- where they
	// overlap, they genuinely interfere, not just draw over each other.
	float wave = clamp(ambient_wave + shore_bounce * 0.4 + rain * 0.8, 0.0, 1.0);

	// Most of the noise range stays near "deep" -- only genuine peaks reach
	// "crest" -- so the surface reads as a cohesive blue body with modest
	// highlights, not a pale wash (reported: "looks like cloudy sky").
	vec3 water = mix(deep_color, crest_color, smoothstep(wave_low_threshold, wave_high_threshold, wave));

	float glint = smoothstep(0.975, 1.0, value_noise(p * 3.7 + vec2(TIME * 0.9, -TIME * 0.5)));
	water += vec3(glint * 0.4);

	// Fade smoothly into the coastline instead of cutting off at a tile
	// edge.
	float edge_alpha = smoothstep(0.0, 0.5, shore_dist);
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

## smoothstep bounds mapping the combined wave value to deep_color..
## crest_color. Pushed higher than the original (0.3, 0.85) so most of the
## noise range stays near-deep and only genuine peaks reach crest -- the
## other half of the "cloudy sky" fix (a washed-out crest color alone wasn't
## enough; too much of the surface was reaching it).
const WAVE_LOW_THRESHOLD := 0.55
const WAVE_HIGH_THRESHOLD := 0.95

## Baseline pacing -- matches WeatherModel.wind_strength_for("clear") (the
## water's original always-on pace, from before per-weather scaling existed),
## so an unconfigured/default material already looks like a normal clear day
## rather than an artificially calmed one.
const DEFAULT_WIND_STRENGTH := 1.0

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("alpha_strength", WATER_ALPHA)
	material.set_shader_parameter("wind_strength", DEFAULT_WIND_STRENGTH)
	material.set_shader_parameter("rain_intensity", 0.0)
	material.set_shader_parameter("deep_color", DEEP_COLOR)
	material.set_shader_parameter("crest_color", CREST_COLOR)
	material.set_shader_parameter("wave_low_threshold", WAVE_LOW_THRESHOLD)
	material.set_shader_parameter("wave_high_threshold", WAVE_HIGH_THRESHOLD)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Sets how strongly raindrop ripples show on the shared material (0 = none,
## 1 = full rain) -- see EarthChunkManager.set_rain, driven from the live
## weather model. A continuous parameter on an already-continuous shader, so
## even a hard 0/1 flip is just a ripple-strength change, not a visual swap.
func set_rain_intensity(intensity: float) -> void:
	shared_material().set_shader_parameter("rain_intensity", intensity)


## Sets how energetic the ambient wave motion is on the shared material --
## see WeatherModel.wind_strength_for, driven from the live weather model
## (EarthChunkManager.set_wind_strength). Scales the ambient wave's effective
## time-rate, so water idles gently on a clear day and churns faster/choppier
## as weather worsens.
func set_wind_strength(strength: float) -> void:
	shared_material().set_shader_parameter("wind_strength", strength)
