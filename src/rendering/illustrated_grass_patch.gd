extends RefCounted

## A chunk's worth of TallGrass cells, rendered as GPU-instanced cards from
## the illustrated atlas -- one MultiMeshInstance2D draw call per Y-sort
## band, not one Sprite2D per card. See docs/concept/long_grass.md.
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")

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
## per-blade sorting against the player needs each band to be thin enough
## that native Y-sort alone (no per-pixel alpha hack -- see the shader's own
## fragment() history below) never lets a band's own worst-case blade
## visually reach the player's real body.
##
## PREVIOUSLY 8 (CHUNK_SIZE=32 tiles / 8 bands = 4 tiles/band = 64 world
## units). That was too coarse: a band's own worst-case blade (its root at
## the far/top edge of an in-front band, its card then reaching another
## WORLD_SIZE past that) could visually reach 64+16=80 world units above
## the player's own root -- comfortably past the player's own real max
## reach (42 world units, `character_view.tscn`'s HeadSlot offset) -- so it
## painted straight over the player's upper body/head. Reported live, with
## a real screenshot.
##
## THEN 32 (1 tile/band = 16 world units) -- fixed the "painted over the
## head" symptom, but left a real, honest residual: a band still draws in
## front of the player for as long as the player is anywhere within its own
## full tile (band_anchor_world_y's own bottom-edge anchoring, "normal,
## expected concealment" by design). At a whole tile per band, that grace
## window is barely perceptible on sparse, mostly-transparent blade art but
## reads as glaringly broken on the atlas's own dense, near-opaque "bush"
## cards -- reported live again, the same day: "y ordering is correct only
## for some [tufts]... should work like the lower one for all."
##
## Now 64 (half a tile/band = 8 world units): halves that grace window
## again, AND (a second real effect this specific change unlocks) is now
## fine enough that a card's own real per-card offset (up to 6.8 world
## units, see `cards_for_cell`) CAN cross a band boundary -- so the
## per-card banding fix landed just before this one actually starts doing
## something at today's real production ratio, not just at a synthetic
## test-only band_count. Worst-case reach: 8 (band_height) + 6.8 (max card
## offset) + 16 (WORLD_SIZE) = 30.8, an 11.2-world-unit margin under the
## player's real 42 -- a real, tested (see
## test_band_height_leaves_a_real_safety_margin_under_the_players_own_max_reach)
## and comfortable margin again. Another deliberate, honest draw-call cost
## for grass specifically (32 -> 64 per chunk, 8x the original pre-fix
## count of 8) -- correctness over raw draw-call count, the same reasoning
## every prior pass on this exact bug already used.
const BAND_COUNT := 64

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

## Which Y-band (0..BAND_COUNT-1) a row at `local_y` (within its own chunk,
## 0..chunk_size-1) belongs to. `local_y` is `float`, not `int`: a CELL's
## own raw row is always a whole number, but a CARD's real, offset-adjusted
## position (see `cards_for_cell`/`local_row_for_world_y`) is not -- one
## fractional function serves both cell-level and card-level callers (a
## plain `int` widens to `float` automatically at any existing call site).
static func band_index_for_local_y(local_y: float, chunk_size: int, band_count: int = BAND_COUNT) -> int:
	if chunk_size <= 0 or band_count <= 0:
		return 0
	var band_height: float = maxf(float(chunk_size) / float(band_count), 0.0001)
	return clampi(int(local_y / band_height), 0, band_count - 1)


## The chunk-local row-equivalent (the same fractional units `cell.y`
## already lives in) of a real world Y -- the inverse of how a cell's own
## `ground_position` is built (`(tile.y + 0.5) * tile_size`, where
## `tile.y = chunk_origin_y + local_y`). Lets a CARD's real world Y (its
## cell's ground position plus its own random offset -- see
## `cards_for_cell`) be converted back into that same coordinate space and
## handed to `band_index_for_local_y`, for genuine per-card banding instead
## of the cell's own un-offset raw row.
static func local_row_for_world_y(world_y: float, chunk_origin_y: int, tile_size: float) -> float:
	return world_y / tile_size - float(chunk_origin_y)

## The world Y a band's MultiMeshInstance2D should sit at for Y-sorting --
## the band's own BOTTOM edge (its largest row's world Y), not its vertical
## center. A single draw call can only Y-sort as ONE unit (see BAND_COUNT's
## own doc comment), and a center anchor left every row in a band's lower
## half sitting BELOW (a larger world Y than) the anchor -- so a player
## standing on one of those rows, having already walked past every blade in
## the band's upper half, still Y-sorted BEHIND the whole band. Since a
## blade card renders upward from its own root and is a full tile tall (see
## `mesh()`'s WORLD_SIZE), that read as exactly the reported bug: "the
## player's head is behind the long grass blades when the feet already are
## past it." Anchoring at the bottom edge instead means any entity standing
## anywhere within or above the band always sorts behind the whole band
## (grass draws in front while you're walking through it -- normal,
## expected concealment, see docs/concept/combat.md), and the band only
## pops behind the entity once genuinely past its very last row. Trades
## "occasionally covered a beat longer than a single blade's own root would
## justify" for "never shows a body part behind grass it has unambiguously
## already passed" -- pinned by
## test_band_anchor_world_y_is_never_smaller_than_any_row_actually_in_that_band.
static func band_anchor_world_y(band_index: int, chunk_origin_y: int, chunk_size: int, tile_size: float, band_count: int = BAND_COUNT) -> float:
	var band_height: float = maxf(float(chunk_size) / float(band_count), 0.0001)
	var local_y_bottom: float = (float(band_index) + 1.0) * band_height
	return (float(chunk_origin_y) + local_y_bottom) * tile_size

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
// The season's multiplier on living green (see SeasonalFoliage, forwarded via
// EarthChunkManager.set_season_tint) -- the same value the terrain layer
// under these blades wears, so a field and the ground it stands in turn
// together instead of a green lawn showing through straw-coloured grass.
// Identity by default, so a caller that never pushes a season renders exactly
// today's high-summer picture.
uniform vec3 season_tint = vec3(1.0);

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

	// SUPERSEDED (2026-08-26): a blade whose own root the player has already
	// walked past used to fade to transparent here instead of being
	// properly occluded (a per-pixel alpha hack standing in for real
	// Y-sort, reusing walker_radius from the unrelated push effect above).
	// That both under-corrected (a blade more than walker_radius behind the
	// player never faded, so it kept drawing solid on top of the player's
	// upper body/head) and over-corrected (any blade within walker_radius
	// faded to fully invisible just from the player standing near it,
	// reported separately as "grass becomes transparent when walking over
	// it") -- two symptoms of the same wrong mechanism. BAND_COUNT is now
	// fine-grained enough (see its own doc comment) that native Y-sort
	// alone -- the same mechanism every ordinary Sprite2D already uses --
	// places each band in the correct draw order without any alpha
	// modulation: grass is either genuinely behind the player (drawn
	// first, correctly covered) or genuinely in front (drawn after,
	// correctly covering), always fully opaque either way.
	COLOR = texture(TEXTURE, atlas_uv);
	// Gated on greenness for the same reason GroundTint is, and with the same
	// gain: the illustrated atlas already carries dry/brown blades, and those
	// must not be turned again by a season they are already wearing.
	float greenness = clamp((COLOR.g - max(COLOR.r, COLOR.b)) * %s, 0.0, 1.0);
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * season_tint, greenness);
}
""" % [BEND_CURVE_EXPONENT, PHASE_SPREAD, AMPLITUDE_BASE, AMPLITUDE_VARIATION, AMPLITUDE_FREQUENCY, WIND_UV_AMPLITUDE, WALKER_PUSH_UV_AMPLITUDE, SeasonalFoliage.GREENNESS_GAIN]

var _material: ShaderMaterial
var _texture: Texture2D
var _mesh: QuadMesh
## Last live wind strength pushed in (see set_wind_strength) -- applied to
## material() at BUILD time too, so a caller that sets the live wind before
## the material has been lazily built yet doesn't lose it.
var _wind_strength := DEFAULT_WIND_STRENGTH
## Last season tint pushed in (see set_season_tint) -- applied in material()
## at BUILD time too, so a caller that sets the season before the material has
## been lazily built doesn't lose it (same reasoning as _wind_strength above).
var _season_tint := Color(1.0, 1.0, 1.0)

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
		_material.set_shader_parameter("season_tint", _season_tint_vector())
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


## Pushes the season's tint on living green (see SeasonalFoliage, via
## EarthChunkManager.set_season_tint) onto the shared blade material.
## Deliberately does NOT touch growth or spread: this is what a field LOOKS
## like in November, not how fast it grows then (see docs/concept/seasons.md's
## still-open "seasonal scaling of vegetation growth rate" -- a rendering fix
## must not smuggle a sim change in with it).
func set_season_tint(tint: Color) -> void:
	_season_tint = tint
	material().set_shader_parameter("season_tint", _season_tint_vector())


func _season_tint_vector() -> Vector3:
	return Vector3(_season_tint.r, _season_tint.g, _season_tint.b)

## Expands ONE cell spec ({seed:int, ground_position:Vector2, growth:float})
## into its CARD_COUNT real per-card specs: {atlas_seed:int, position:
## Vector2, growth:float} -- each card's own real, offset-adjusted ground
## position (`ground_position + this card's own random offset`, see
## `card_specs_for_seed`). THE single seam for turning a cell into its
## cards -- both `EarthChunkManager`'s own Y-sort banding (which needs each
## card's own real position to bucket it correctly, via
## `local_row_for_world_y` -- see docs/concept/long_grass.md) and
## `instances_for_cards`' own final placement math read from here, so the
## two can never drift apart from each other.
static func cards_for_cell(cell_spec: Dictionary) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	var ground_position: Vector2 = cell_spec.ground_position
	for spec in card_specs_for_seed(cell_spec.seed):
		cards.append({
			"atlas_seed": spec.seed,
			"position": ground_position + (spec.offset as Vector2),
			"growth": cell_spec.growth,
		})
	return cards

## Pure data prep for fill_band, headlessly testable on its own: computes
## every given CARD's instance transform (root pinned exactly at its own
## real position, regardless of growth scale) and packed atlas-region
## color, from plain per-card data only - no MultiMesh/Texture2D access.
## `card_specs` is an array of {atlas_seed:int, position:Vector2,
## growth:float}, one entry per CARD (see `cards_for_cell` -- the caller
## expands cells into cards and buckets them by real Y-sort band BEFORE
## calling this, so a cell whose own cards land in different bands can be
## split across separate calls without any card drawn twice or dropped).
## Sorted back-to-front by ground Y so overlapping alpha-blended cards
## within a band blend in roughly the right order.
static func instances_for_cards(card_specs: Array, band_anchor: Vector2, atlas_size: Vector2i) -> Array[Dictionary]:
	var flat: Array[Dictionary] = []
	for card_spec in card_specs:
		flat.append({
			"region": atlas_region_for_seed(card_spec.atlas_seed, atlas_size),
			"position": card_spec.position,
			"growth": card_spec.growth,
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
## needed) so it renders every CARD in `card_specs` - each a
## {atlas_seed:int, position:Vector2, growth:float} (see `cards_for_cell`).
##
## `band_anchor` must already be `mmi`'s own `position` (it drives this
## band's Y-sort key against the player/creatures); instance transforms are
## stored relative to it. Thin engine glue over instances_for_cards - see
## that function for the actual (headlessly-tested) placement math. This
## wrapper itself needs a real renderer to verify: MultiMesh per-instance
## transform/color storage is backed by the dummy renderer under
## `--headless` and silently doesn't round-trip there.
func fill_band(mmi: MultiMeshInstance2D, band_anchor: Vector2, card_specs: Array) -> void:
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
	var instances := instances_for_cards(card_specs, band_anchor, Vector2i(_texture.get_size()))
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform_2d(i, instances[i].transform)
		mm.set_instance_custom_data(i, instances[i].custom_data)
