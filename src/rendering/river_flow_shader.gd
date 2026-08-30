extends RefCounted

const RiverPhaseField = preload("res://src/world/river_phase_field.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

## GPU river flow: a directional streak pattern advecting downstream over
## river cells, with whitewater where the flow is fast. Layered over the
## base water overlay the same way hillshade layers over land, so
## water_shader.gd (ocean waves, rain ripples, shore blending) is untouched.
## See docs/concept/rivers.md's "Flow rendering" section.
##
## THIS IS A REWRITE of the original streak shader, which read as
## "a tilemap with a filter on it". Three quantified defects, all fixed
## here by construction rather than by tuning:
##
## 1. PHASE RESET AT EVERY TILE BOUNDARY -- the dominant one. The phase was
##    `dot(world_pos, flow_dir)`, with world_pos absolute (up to ~639,000
##    units) and flow_dir quantised to 16 bins. One bin of direction change
##    between adjacent cells shifted the phase by ~30,000 cycles, i.e. an
##    arbitrary reset, on a 16 px lattice -- and that lattice IS the
##    tilemap, made visible. Now the phase comes from a continuous
##    per-course potential baked per tile (see RiverPhaseField), so
##    neighbouring cells differ by exactly the wavelengths between them.
##
## 2. TEMPORAL ALIASING -- the old phase advanced at flow_speed *
##    streak_frequency = 3.84 Hz at top speed, which at this game's measured
##    ~7 fps floor is 0.549 cycles/frame: past the 0.5 Nyquist limit, so the
##    fastest rivers visibly flowed BACKWARDS. The pattern now advances at
##    ONE global rate everywhere (RiverPhaseField.STREAK_RATE_HZ = 0.75 Hz,
##    0.107 cycles/frame at 7 fps), which makes aliasing impossible at any
##    speed rather than merely unlikely.
##
## 3. TURBULENCE PAST THE FOLD THRESHOLD -- the old field displaced the
##    phase by +/-15 world units against an 8.33-unit wavelength: +/-1.8
##    WAVELENGTHS. That does not waver a band, it decorrelates it; the
##    iso-phase map folded back on itself and the bands were being
##    scrambled. (The old code's own comment claimed the displacement was
##    "small enough that streaks still read as flowing roughly downstream";
##    the arithmetic said otherwise.) Turbulence is now expressed as a
##    fraction of a wavelength and capped below the fold threshold.
##
## Speed no longer drives the streak GEOMETRY at all -- one global
## wavelength and rate is what buys defects 1 and 2 -- so it is expressed
## through whitewater and contrast instead, which is also the more
## legible cue at 16 px.

const SHADER_CODE := """
shader_type canvas_item;

uniform float wavelength_px = 8.8;
uniform float streak_rate_hz = 0.75;
uniform float streak_sharpness = 2.0;
uniform float streak_alpha = 0.5;
uniform vec3 streak_color : source_color = vec3(0.85, 0.94, 1.0);
uniform float turbulence_wavelengths = 0.22;
uniform float turbulence_scale = 0.02;
uniform float turbulence_speed = 0.35;
uniform float foam_speed_floor = 0.45;
uniform float foam_speed_ceiling = 0.95;
uniform float foam_coverage = 0.55;
uniform vec3 foam_color : source_color = vec3(0.97, 0.99, 1.0);
uniform float foam_alpha = 0.85;
uniform float art_pixel_size = 8.0;

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

void fragment() {
	// R = wrapped course phase, G/B = flow direction as a unit vector
	// mapped from [-1,1], A = speed fraction. Direction as a vector rather
	// than a bearing saves a radians/sin/cos here and removes the 0/360
	// wrap hazard entirely.
	vec4 data = texture(TEXTURE, UV);
	float baked_phase = data.r;
	vec2 flow_dir = normalize(data.gb * 2.0 - 1.0 + vec2(1e-6, 0.0));
	float speed = data.a;

	// Position WITHIN this tile, along the flow. The baked phase is the
	// course phase at the tile; this carries it continuously across the
	// tile's own span so the pattern is a ribbon, not a per-tile constant.
	vec2 tile_local = fract(world_pos / art_pixel_size) * art_pixel_size;
	float along = dot(tile_local, flow_dir);

	// Turbulence, expressed as a FRACTION OF A WAVELENGTH so it can never
	// again be set past the fold threshold where bands stop wavering and
	// start scrambling. One octave, not two: the old second octave sat at
	// ~1.5x the streak's own frequency, which shreds the pattern it is
	// meant to perturb.
	float turb = value_noise(world_pos * turbulence_scale + vec2(TIME * turbulence_speed, 0.0)) - 0.5;
	float turbulence_cycles = turb * turbulence_wavelengths;

	// ONE global temporal rate -- this is what makes aliasing impossible.
	float phase = baked_phase + along / wavelength_px + turbulence_cycles - TIME * streak_rate_hz;

	float wave = sin(phase * 6.28318530718);
	float streak = pow(max(wave, 0.0), streak_sharpness);

	// Contrast carries speed now that geometry does not: a slow reach shows
	// soft, low-contrast lines, a fast one hard bright ones.
	float contrast = mix(0.55, 1.0, speed);
	vec3 color = streak_color;
	float alpha = streak * streak_alpha * contrast;

	// Whitewater. Real foam tracks flow DECELERATION rather than speed --
	// a uniformly fast chute is glassy, and it is the hydraulic jump where
	// fast meets slow that goes white -- but deceleration needs an upstream
	// sample this pass does not carry, so this is the honest cheap proxy:
	// broken speckle on the fastest reaches only. Hash is quantised to the
	// ART PIXEL grid, so the speckle sits still against nearest-filtered
	// ground instead of crawling.
	float foam_drive = smoothstep(foam_speed_floor, foam_speed_ceiling, speed);
	if (foam_drive > 0.0) {
		vec2 art_cell = floor(world_pos / art_pixel_size);
		float h = value_hash(art_cell);
		// Threshold, not multiply: foam is broken flecks, not a wash.
		float foam = step(1.0 - foam_drive * foam_coverage * streak, h);
		color = mix(color, foam_color, foam);
		alpha = max(alpha, foam * foam_alpha * foam_drive);
	}

	COLOR = vec4(color, alpha);
}
"""

## Streak wavelength in WORLD PIXELS, derived from the course-space
## wavelength the phase field is built on rather than picked independently
## -- the two must agree or the pattern would advance at one scale and
## repeat at another. RiverPhaseField works in tiles; TerrainRenderer's
## TILE_SIZE is 16 world px.
const TILE_SIZE_PX := 16.0
const WAVELENGTH_PX := RiverPhaseField.STREAK_WAVELENGTH_TILES * TILE_SIZE_PX

## Raising a clamped sine to this power narrows each band into a streak.
##
## 2.0 comes from a SEPARATE, concurrent fix for a "make the flow effect
## more visible" report, kept intact through this rewrite rather than
## overwritten by it: at the prior 4.0 the bright (>0.5 intensity) part of
## each cycle covered only ~18.2% of the period -- a thin, sparse glint
## rather than a current that visibly covers the water. 2.0 broadens that
## to ~25%, clear of the 22% floor its regression test pins while staying
## well short of a flat, motionless-looking tint. (Duty fraction is
## (pi - 2*asin(0.5^(1/n))) / (2*pi), and depends only on n -- so it is
## unaffected by this rewrite's change of wavelength and phase source.)
const STREAK_SHARPNESS := 2.0

## Overlay opacity ceiling -- translucent enough that the base water colour
## and its ripples always show through, the same "never opaque" bound
## WaterShader.WATER_ALPHA and HillshadeShader.MAX_SHADOW_ALPHA keep.
##
## 0.5 and the brightened colour below both come from the same concurrent
## "make the flow effect more visible" fix as STREAK_SHARPNESS above, and
## are preserved here for the same reason. The prior 0.35/(0.75,0.88,1.0)
## read as an easy-to-miss glint, particularly layered UNDER
## HillshadeShader's own overlay (up to MAX_SHADOW_ALPHA = 0.55 of
## near-black on the same tile): the streak has to punch through that
## darkening, not merely be visible in isolation. Colour is the second,
## alpha-independent lever -- COLOR blends toward whatever sits underneath,
## so a brighter source lands lighter at the same alpha. Both stay inside
## this codebase's own overlay precedents: alpha under
## HillshadeShader.MAX_SHADOW_ALPHA (0.55) and WaterShader.WATER_ALPHA
## (0.6), every colour channel within [0.7, 1.0] with blue still dominant.
const STREAK_ALPHA := 0.5
const STREAK_COLOR := Color(0.85, 0.94, 1.0)

## Turbulence displacement as a FRACTION OF ONE WAVELENGTH. The fold
## threshold -- where the iso-phase map starts folding back on itself and
## bands scramble instead of wavering -- is at 1/(2*pi) ~= 0.159 per unit of
## noise gradient; well under a quarter wavelength is safely inside it while
## still visibly bending the bands. The old shader ran at the equivalent of
## 1.8 wavelengths.
const TURBULENCE_WAVELENGTHS := 0.22
const TURBULENCE_SCALE := 0.02
const TURBULENCE_SPEED := 0.35

## Whitewater appears only on the fastest reaches (see the shader's own note
## on why real foam tracks deceleration, and why this is the honest proxy).
const FOAM_SPEED_FLOOR := 0.45
const FOAM_SPEED_CEILING := 0.95
const FOAM_COVERAGE := 0.55
const FOAM_COLOR := Color(0.97, 0.99, 1.0)
const FOAM_ALPHA := 0.85

## One art pixel in world units -- the grid the foam speckle is quantised to
## so it sits still against nearest-filtered ground rather than crawling.
## TILE_SIZE 16 / ArtResolution.DETAIL_MULTIPLIER 2.
const ART_PIXEL_SIZE := 8.0

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wavelength_px", WAVELENGTH_PX)
	material.set_shader_parameter("streak_rate_hz", RiverPhaseField.STREAK_RATE_HZ)
	material.set_shader_parameter("streak_sharpness", STREAK_SHARPNESS)
	material.set_shader_parameter("streak_alpha", STREAK_ALPHA)
	material.set_shader_parameter("streak_color", STREAK_COLOR)
	material.set_shader_parameter("turbulence_wavelengths", TURBULENCE_WAVELENGTHS)
	material.set_shader_parameter("turbulence_scale", TURBULENCE_SCALE)
	material.set_shader_parameter("turbulence_speed", TURBULENCE_SPEED)
	material.set_shader_parameter("foam_speed_floor", FOAM_SPEED_FLOOR)
	material.set_shader_parameter("foam_speed_ceiling", FOAM_SPEED_CEILING)
	material.set_shader_parameter("foam_coverage", FOAM_COVERAGE)
	material.set_shader_parameter("foam_color", FOAM_COLOR)
	material.set_shader_parameter("foam_alpha", FOAM_ALPHA)
	material.set_shader_parameter("art_pixel_size", ART_PIXEL_SIZE)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Maps a real local slope magnitude to a [0,1] speed fraction, anchored at
## TerrainPassability.HARD_THRESHOLD_DEG -- the same real
## "scrambling/technical-climbing" steepness BiomeClassifier already reuses,
## rather than a second independently-eyeballed cap.
##
## Kept for callers that have only terrain. The painter prefers
## speed_fraction_for_velocity below, which reads the REAL solved current
## speed now that the hydraulics exist.
static func speed_fraction_for_slope_deg(slope_deg: float) -> float:
	return clampf(slope_deg / TerrainPassability.HARD_THRESHOLD_DEG, 0.0, 1.0)


## The fastest real current the visual scale tops out at, in m/s. Real
## rivers: NIWA/Jowett call 0.3-0.5 m/s "good" habitat flow; USGS-gauged
## FLOOD peaks on real reaches reach ~3 m/s. 2.5 puts a genuinely fast
## river at the top of the scale without every ordinary reach saturating.
const MAX_DISPLAYED_VELOCITY_M_S := 2.5


## The [0,1] speed fraction for a REAL solved current velocity (see
## EarthChunkGenerator.river_hydraulics_at_global) -- what the flow visual
## should read now that current speed is real physics rather than a
## slope proxy.
static func speed_fraction_for_velocity(velocity_m_s: float) -> float:
	return clampf(velocity_m_s / MAX_DISPLAYED_VELOCITY_M_S, 0.0, 1.0)


## The CPU mirror of the shader's periodic-streak math, for headless
## testing. `along_px` is distance along the flow within a tile;
## `baked_phase` is the course phase there. Turbulence and foam are
## deliberately NOT mirrored -- like water_shader.gd's own wind shimmer,
## they are cosmetic, and only the physics another caller might reason
## about gets a CPU twin.
static func streak_intensity(baked_phase: float, along_px: float, time_seconds: float) -> float:
	var phase := (
		baked_phase + along_px / WAVELENGTH_PX - time_seconds * RiverPhaseField.STREAK_RATE_HZ
	)
	return pow(maxf(sin(phase * TAU), 0.0), STREAK_SHARPNESS)
