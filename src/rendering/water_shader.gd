extends RefCounted

## GPU water: continuous, physically-inspired waves rendered in world space
## over every ocean cell -- the fluid motion 4-frame tile art (and, before
## that, the hard-edged baked shore/foam tiles) fundamentally can't express.
##
## The WaterFx overlay TileMapLayer (see EarthChunkManager.set_water_layer)
## is painted with a small "shore distance" tile family (see
## procedural_shore_distance_sprite.gd): each tile's red channel encodes
## per-pixel distance to the nearest land edge, 0..1. This shader reads that
## channel as DATA, not art, and uses it to do everything that used to live
## in discrete baked tiles -- continuously, per-pixel, on the GPU:
##
## - Ambient wind chop: two octaves of value noise scrolling at different
##   speeds/directions, so the surface shears rather than sliding as one sheet.
## - Shore "bounce": an incident wave (traveling toward the coast) and its
##   reflection (traveling away) are summed near the shore -- real standing-
##   wave interference at a boundary, confined to a band near shore_dist=0
##   and fading out in open water.
## - Raindrops make waves: while it's raining (rain_intensity, driven by the
##   live weather model via set_rain_intensity), a hash-seeded grid of drop
##   points continuously spawns expanding ring ripples, several overlapping
##   at once.
##
## All three sources sum into ONE combined wave field before being mapped to
## color -- where they overlap, they genuinely interfere (constructive/
## destructive), not just draw over each other. Alpha also fades smoothly
## with shore distance, so the ocean melts into the coastline instead of
## cutting off at a tile edge (the previous baked-tile system's jagged
## border). Everything runs on TIME/world position: fully fluid at any frame
## rate, zero per-frame script. Contract pinned by test_water_shader.gd.
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
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;

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
	float swell = value_noise(p + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.35));
	float chop = value_noise(p * 2.3 - vec2(TIME * scroll_speed * 0.7, TIME * scroll_speed * 0.2));
	float ambient_wave = swell * 0.65 + chop * 0.35;

	// Shore distance: baked into this tile's own texture as a DATA channel
	// (see procedural_shore_distance_sprite.gd), 0 at the land edge, 1 far
	// from shore. Softened with sqrt() so the transition reads across more
	// of the tile instead of snapping right at the edge.
	float shore_dist = sqrt(texture(TEXTURE, UV).r);

	// Incident + reflected wave, summed -- a real standing-wave interference
	// pattern at the coast ("waves bounce off the shore"), confined near
	// shore_dist=0 and fading into open water.
	float k = 16.0;
	float omega = 2.3;
	float incident = sin(shore_dist * k + TIME * omega);
	float reflected = sin(shore_dist * k - TIME * omega);
	float shore_band = clamp(1.0 - shore_dist / 0.4, 0.0, 1.0);
	float shore_bounce = (incident + reflected) * 0.5 * shore_band;

	float rain = raindrop_ripples(world_pos);

	// All three wave sources sum before mapping to color -- where they
	// overlap, they genuinely interfere, not just draw over each other.
	float wave = clamp(ambient_wave + shore_bounce * 0.4 + rain * 0.8, 0.0, 1.0);

	vec3 deep = vec3(0.05, 0.24, 0.58);
	vec3 crest = vec3(0.4, 0.72, 0.98);
	vec3 water = mix(deep, crest, smoothstep(0.3, 0.85, wave));

	float glint = smoothstep(0.965, 1.0, value_noise(p * 3.7 + vec2(TIME * 0.9, -TIME * 0.5)));
	water += vec3(glint * 0.55);

	// Fade smoothly into the coastline instead of cutting off at a tile
	// edge -- the fix for the reported jagged shore border.
	float edge_alpha = smoothstep(0.0, 0.5, shore_dist);
	COLOR = vec4(water, alpha_strength * edge_alpha);
}
"""

## Overlay opacity: high enough to own the water's look, low enough that the
## baked base water tile beneath (and the shore edge-alpha fade) stays part
## of the final look (pinned 0.2..0.75 by
## test_overlay_is_translucent_so_the_base_tile_layer_shows_through).
const WATER_ALPHA := 0.6

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("alpha_strength", WATER_ALPHA)
	material.set_shader_parameter("rain_intensity", 0.0)
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
