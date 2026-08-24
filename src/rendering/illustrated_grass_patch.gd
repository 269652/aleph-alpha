extends RefCounted

## A chunk's worth of TallGrass cells, rendered as GPU-instanced cards from
## the illustrated atlas -- one MultiMeshInstance2D draw call per Y-sort
## band, not one Sprite2D per card. See docs/concept/long_grass.md.
const ATLAS_PATH := "res://assets/sprites/grass_blades.png"
## The delivered sheet is 1254×1254 and contains 10×10 blade variants. Its
## source art is roughly 128px per cell; regions derive from its true size.
const ATLAS_COLUMNS := 10
const ATLAS_ROWS := 10
const DEFAULT_ATLAS_SIZE := Vector2i(1254, 1254)
## Individual Sprite2D cards used to be expensive enough that this stayed
## small (4). GPU instancing keeps this to ONE draw call regardless of card
## count -- but each card is still a translucent, alpha-blended, shaded quad the
## GPU must rasterize and blend, so cards are cheap in draw CALLS yet not in
## fill rate/overdraw. On a fill-rate-limited integrated GPU a dense field of
## 12-deep tufts was a measurable cost, so this trades a little volumetric
## density for a lot less overdraw (pinned by test_illustrated_grass_patch).
const CARD_COUNT := 8
const WORLD_SIZE := 16.0

## How many horizontal strips a chunk's grass splits into for Y-sorting.
## One draw call per (chunk, band) instead of one per card is the whole
## performance win; a single draw call can only Y-sort as ONE unit, so true
## per-blade sorting against the player is impossible under batching. Bands
## are the standard middle ground: coarse enough for a real draw-call
## reduction (CHUNK_SIZE=32 tiles / 8 bands = 4 tiles/band), fine enough
## that walking through a field still sorts correctly at the tile-cluster
## level (a blade mis-sorted against its same-band neighbor is
## imperceptible; the whole field flickering in front of/behind the player
## as one block would not be).
const BAND_COUNT := 8

## Bend profile: how far a pixel row is displaced, as a function of
## top_t (0 at the root, 1 at the tip). A straight vertex shear only ever
## produces a linear ramp (a flat parallelogram); an exponent above 1
## instead eases in, so the root barely moves while curvature - and
## displacement - concentrates near the tip, the way a real blade bends
## under wind load.
const BEND_CURVE_EXPONENT := 1.6
## Radians of wind-phase spread across a card's full UV.x width, so blades
## drawn side by side in the same tuft sway with a different timing instead
## of shearing the whole card as one rigid shape.
const PHASE_SPREAD := 2.4
## amplitude_scale(uv_x) = AMPLITUDE_BASE + AMPLITUDE_VARIATION * sin(...):
## kept strictly positive so no column of blades ever goes fully still.
const AMPLITUDE_BASE := 0.8
const AMPLITUDE_VARIATION := 0.2
const AMPLITUDE_FREQUENCY := 6.0
## Peak UV-space displacement (fraction of the card's width) at full bend.
## A rendered-pixel probe showed a small shift reads clearly against a
## sparse single-blade card (its moving silhouette edge is high-contrast)
## but is nearly invisible against a dense, busy bush card (a small shift
## of repetitive texture still looks like the same texture) even though the
## sampled pixels do change - reported live as "bigger bushes don't part".
## Both amplitudes are sized for the busier case.
const WIND_UV_AMPLITUDE := 0.09
const WALKER_PUSH_UV_AMPLITUDE := 1.5

## The shader's own wind_strength default: calibrated to
## WeatherModel.wind_strength_for("clear") == 1.0 (see weather_model.gd), the
## majority weather state (CLEAR_THRESHOLD), so WIND_UV_AMPLITUDE above stays
## exactly today's tuned look until a live value is pushed in via
## set_wind_strength (see EarthChunkManager.set_wind_strength). Deliberately
## does NOT scale WALKER_PUSH_UV_AMPLITUDE -- parting is the walker's own
## reaction, not ambient wind, and must not go weaker on a calm day.
const DEFAULT_WIND_STRENGTH := 1.0

static var SHADER_CODE: String = _build_shader_code()

static func bend_curve(top_t: float) -> float:
	return pow(clampf(top_t, 0.0, 1.0), BEND_CURVE_EXPONENT)

static func blade_phase(uv_x: float) -> float:
	return uv_x * PHASE_SPREAD

static func blade_amplitude_scale(uv_x: float) -> float:
	return AMPLITUDE_BASE + AMPLITUDE_VARIATION * sin(uv_x * AMPLITUDE_FREQUENCY)

## Which Y-band (0..BAND_COUNT-1) a cell at `local_y` (row within its own
## chunk, 0..chunk_size-1) belongs to.
static func band_index_for_local_y(local_y: int, chunk_size: int, band_count: int = BAND_COUNT) -> int:
	if chunk_size <= 0 or band_count <= 0:
		return 0
	var band_height: float = maxf(float(chunk_size) / float(band_count), 0.0001)
	return clampi(int(float(local_y) / band_height), 0, band_count - 1)

## The world Y a band's MultiMeshInstance2D should sit at for Y-sorting --
## the band's own vertical center, so it sorts against the player/creatures
## roughly like the tile clumps within it would individually.
static func band_anchor_world_y(band_index: int, chunk_origin_y: int, chunk_size: int, tile_size: float, band_count: int = BAND_COUNT) -> float:
	var band_height: float = maxf(float(chunk_size) / float(band_count), 0.0001)
	var local_y_center: float = (float(band_index) + 0.5) * band_height
	return (float(chunk_origin_y) + local_y_center) * tile_size

static func _build_shader_code() -> String:
	return """
shader_type canvas_item;
uniform vec2 player_world_position = vec2(-100000.0);
uniform float walker_radius = 22.0;
uniform float wind_speed = 1.6;
// Live wind conditions (see WeatherModel.wind_strength_for, forwarded via
// EarthChunkManager.set_wind_strength) -- WIND_UV_AMPLITUDE is the BASE
// ambient sway at wind_strength == 1.0 ("clear"), scaled up in rougher
// weather and down in none. Deliberately does NOT touch the walker-push
// term below (see `push`): parting is the walker's own reaction, not wind.
uniform float wind_strength = 1.0;

varying vec2 v_root;
// Per-card atlas sub-rect (normalized), packed into MultiMesh's dedicated
// per-instance custom-data channel on the CPU side. NOT `instance uniform`
// (see docs/concept/long_grass.md: that draws from one global, hardware-
// capped buffer shared by the whole scene). Also NOT plain per-instance
// COLOR read directly in fragment(): under this project's gl_compatibility
// renderer, that produced a dithered/checkerboard mix of neighboring
// instances' data instead of a clean per-instance constant - reading
// INSTANCE_CUSTOM in vertex() and carrying it via varying is the path that
// actually renders cleanly (verified with a real render: raw COLOR read in
// fragment gave visible speckle noise even with zero bend math involved;
// INSTANCE_CUSTOM via a varying gave a clean, solid, correct sample).
varying vec4 v_region;

void vertex() {
	// Roots never translate: this is the only geometry touch, and it reads
	// the local origin (this instance's own transform origin - MultiMesh
	// folds per-instance transforms into MODEL_MATRIX per draw), not
	// VERTEX, so it stays fixed regardless of bend.
	v_root = (MODEL_MATRIX * vec4(vec2(0.0), 0.0, 1.0)).xy;
	v_region = INSTANCE_CUSTOM;
}

void fragment() {
	// UV is the shared quad's own local 0..1 (root at UV.y=0, tip at
	// UV.y=1 - verified empirically for QuadMesh + MultiMeshInstance2D's
	// TRANSFORM_2D; this differs from a region-mapped Sprite2D's UV, which
	// is atlas-relative). This card's own atlas sub-rect arrives packed
	// into v_region (region_uv0 in r,g and region_uv1 in b,a).
	vec2 region_uv0 = v_region.rg;
	vec2 region_uv1 = v_region.ba;
	vec2 region_size = max(region_uv1 - region_uv0, vec2(0.0001));

	// Path-trace the blade by displacing the *sample* UV per pixel row
	// instead of shearing the quad's geometry, so the bend follows a
	// smooth curve and each drawn blade in the card can lean differently.
	float bend = pow(clamp(UV.y, 0.0, 1.0), %s);
	float phase = UV.x * %s;
	float amplitude_scale = %s + %s * sin(UV.x * %s);

	vec2 from_walker = v_root - player_world_position;
	float distance_to_walker = length(from_walker);
	vec2 away = from_walker / max(distance_to_walker, 0.001);
	float wake = 1.0 - smoothstep(0.0, walker_radius, distance_to_walker);

	float wind = sin(TIME * wind_speed + v_root.x * 0.071 + v_root.y * 0.043 + phase) * %s * wind_strength * amplitude_scale;
	float push = away.x * wake * %s;
	float bend_offset = (wind + push) * bend;

	// Sample-space Y is flipped relative to mesh-space UV.y (the atlas art
	// is authored root-at-bottom-of-cell/tip-at-top, but mesh UV.y=0 is the
	// root) - see illustrated_grass_patch.gd's band_index_for_local_y-
	// adjacent comment trail for the empirical verification.
	float local_x = clamp(UV.x - bend_offset, 0.0, 1.0);
	vec2 atlas_uv = region_uv0 + vec2(local_x, 1.0 - UV.y) * region_size;
	COLOR = texture(TEXTURE, atlas_uv);
}
""" % [BEND_CURVE_EXPONENT, PHASE_SPREAD, AMPLITUDE_BASE, AMPLITUDE_VARIATION, AMPLITUDE_FREQUENCY, WIND_UV_AMPLITUDE, WALKER_PUSH_UV_AMPLITUDE]

var _material: ShaderMaterial
var _texture: Texture2D
var _mesh: QuadMesh
## Last live wind strength pushed in (see set_wind_strength) -- applied to
## material() at BUILD time too, so a caller that sets the live wind before
## the material has been lazily built yet doesn't lose it.
var _wind_strength := DEFAULT_WIND_STRENGTH

static func atlas_region_for_seed(seed_value: int, atlas_size: Vector2i = DEFAULT_ATLAS_SIZE) -> Rect2i:
	var index := posmod(seed_value, ATLAS_COLUMNS * ATLAS_ROWS)
	var column := index % ATLAS_COLUMNS
	var row := index / ATLAS_COLUMNS
	var from := Vector2i(column * atlas_size.x / ATLAS_COLUMNS, row * atlas_size.y / ATLAS_ROWS)
	var to := Vector2i((column + 1) * atlas_size.x / ATLAS_COLUMNS, (row + 1) * atlas_size.y / ATLAS_ROWS)
	return Rect2i(from, to - from)

## Offsets used to cluster into a small sub-region (±3.3 x ±1.4 world units)
## hugging the tile's own center - visually one clump sitting somewhere on
## the tile rather than grass filling its whole footprint (reported live:
## "make grass blades volumetric... more than one entity spawns on the same
## tile not only at bottom corner"). 21x17 buckets spread the root across
## most of WORLD_SIZE (±6.8, comfortably inside the ±8 tile-bounds half) on
## both axes independently, so cards read as filling the tile rather than
## clumping in one corner of it - see test_card_offsets_spread_across_most_
## of_a_full_tile_not_a_small_corner / ..._stay_within_the_tiles_own_bounds.
static func card_specs_for_seed(seed_value: int) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for index in CARD_COUNT:
		var h := hash("%d_grass_card_%d" % [seed_value, index])
		var offset := Vector2(float(posmod(h, 21) - 10) * 0.68, float(posmod(h / 21, 17) - 8) * 0.85)
		specs.append({"seed": h, "offset": offset, "depth": CARD_COUNT - index})
	return specs

func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("wind_strength", _wind_strength)
	return _material

func mesh() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(WORLD_SIZE, WORLD_SIZE)
		# Shifts the quad so local (0,0) sits at its BOTTOM edge (root at
		# the ground, growing upward) - the MultiMesh analogue of Sprite2D's
		# offset=(0,-h/2) trick, empirically verified: a positive Y here
		# pushes the quad toward larger screen/world Y (down), so this
		# needs to be negative to grow up.
		_mesh.center_offset = Vector3(0.0, -WORLD_SIZE * 0.5, 0.0)
	return _mesh

func set_walker_position(world_position: Vector2) -> void:
	material().set_shader_parameter("player_world_position", world_position)


## Pushes the live wind strength (see WeatherModel.wind_strength_for, via
## EarthChunkManager.set_wind_strength) onto the shared ambient-sway uniform
## -- see the shader's own wind_strength doc comment for why the walker-push
## term is deliberately left untouched.
func set_wind_strength(strength: float) -> void:
	_wind_strength = strength
	material().set_shader_parameter("wind_strength", strength)

## Pure data prep for fill_band, headlessly testable on its own: computes
## every card's instance transform (root pinned at its own ground position,
## regardless of growth scale) and packed atlas-region color, from plain
## data only - no MultiMesh/Texture2D access. `cell_specs` is an array of
## {seed:int, ground_position:Vector2, growth:float}. Sorted back-to-front
## by ground Y so overlapping alpha-blended cards within a band blend in
## roughly the right order.
static func instances_for_cells(cell_specs: Array, band_anchor: Vector2, atlas_size: Vector2i) -> Array[Dictionary]:
	var flat: Array[Dictionary] = []
	for cell_spec in cell_specs:
		for spec in card_specs_for_seed(cell_spec.seed):
			flat.append({
				"region": atlas_region_for_seed(spec.seed, atlas_size),
				"position": cell_spec.ground_position + (spec.offset as Vector2),
				"growth": cell_spec.growth,
			})
	flat.sort_custom(func(a, b): return a.position.y < b.position.y)

	var texture_size := Vector2(atlas_size)
	var instances: Array[Dictionary] = []
	for entry in flat:
		var region: Rect2i = entry.region
		var local_pos: Vector2 = entry.position - band_anchor
		var scale_factor: float = maxf(0.3, entry.growth)
		var region_uv0 := Vector2(region.position) / texture_size
		var region_uv1 := Vector2(region.position + region.size) / texture_size
		instances.append({
			"transform": Transform2D(Vector2(scale_factor, 0.0), Vector2(0.0, scale_factor), local_pos),
			"custom_data": Color(region_uv0.x, region_uv0.y, region_uv1.x, region_uv1.y),
		})
	return instances

## Rebuilds `mmi` (wiring its MultiMesh/texture/material on first use if
## needed) so it renders every cell in `cell_specs` - each a
## {seed:int, ground_position:Vector2, growth:float} - as CARD_COUNT cards.
##
## `band_anchor` must already be `mmi`'s own `position` (it drives this
## band's Y-sort key against the player/creatures); instance transforms are
## stored relative to it. Thin engine glue over instances_for_cells - see
## that function for the actual (headlessly-tested) placement math. This
## wrapper itself needs a real renderer to verify: MultiMesh per-instance
## transform/color storage is backed by the dummy renderer under
## `--headless` and silently doesn't round-trip there.
func fill_band(mmi: MultiMeshInstance2D, band_anchor: Vector2, cell_specs: Array) -> void:
	if _texture == null:
		_texture = load(ATLAS_PATH) as Texture2D
	if _texture == null:
		push_error("Missing long-grass atlas: %s" % ATLAS_PATH)
		return
	if mmi.multimesh == null:
		var new_mm := MultiMesh.new()
		new_mm.mesh = mesh()
		new_mm.transform_format = MultiMesh.TRANSFORM_2D
		new_mm.use_custom_data = true
		mmi.multimesh = new_mm
		mmi.texture = _texture
		mmi.material = material()
	var mm: MultiMesh = mmi.multimesh
	var instances := instances_for_cells(cell_specs, band_anchor, Vector2i(_texture.get_size()))
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform_2d(i, instances[i].transform)
		mm.set_instance_custom_data(i, instances[i].custom_data)
