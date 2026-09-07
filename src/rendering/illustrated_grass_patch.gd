extends RefCounted

## A chunk's worth of TallGrass cells, rendered as GPU-instanced cards from
## the illustrated atlas -- one MultiMeshInstance2D draw call per Y-sort
## band, not one Sprite2D per card. See docs/concept/long_grass.md.
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

## One sheet per season (see docs/concept/long_grass.md's "Seasonal art"),
## superseding the single `grass_blades.png`. `grass_blades_summer.png` IS
## that original file's own art, unchanged -- the other three are new,
## real-drawn spring/autumn/winter variants sharing its exact grid.
const SEASON_ATLAS_PATHS := {
	"spring": "res://assets/sprites/grass_blades_spring.png",
	"summer": "res://assets/sprites/grass_blades_summer.png",
	"autumn": "res://assets/sprites/grass_blades_autumn.png",
	"winter": "res://assets/sprites/grass_blades_winter.png",
}
## What an unrecognised season falls back to -- same reasoning and same
## choice as `SeasonalFoliage.FALLBACK_SEASON`: unexpectedly green reads as
## an ordinary lawn, unexpectedly bare/frosted reads as dead ground.
const DEFAULT_SEASON := "summer"
## Each delivered sheet is 1254×1254 and contains 10×10 blade cells. Source
## art is roughly 128px per cell; regions derive from the true sheet size.
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
	float raw_local_x = UV.x - bend_offset;
	float local_x = clamp(raw_local_x, 0.0, 1.0);
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
	// At extreme bend, raw_local_x can run past [0,1] for many consecutive
	// fragments at once -- local_x's own clamp keeps the SAMPLE safely
	// in-bounds, but everything past the true edge would otherwise repeat
	// whatever single edge pixel the clamp landed on, stretching it into a
	// visible smear (reported live: "all seasons except summer produce
	// artifacts when parting" -- three of the four delivered sheets have a
	// real, non-transparent pixel sitting exactly at that edge; see this
	// shader's own history/test for the measurement). A fragment whose true,
	// unclamped position has bent past its own region's edge shows nothing
	// instead of that stretched pixel -- not a proximity-based fade (see the
	// SUPERSEDED note above): it fires identically for ambient wind alone,
	// with no player nearby, and never reduces opacity anywhere the bend
	// actually stays in-bounds.
	if (raw_local_x < 0.0 || raw_local_x > 1.0) {
		COLOR.a = 0.0;
	}
	// Gated on greenness for the same reason GroundTint is, and with the same
	// gain: the illustrated atlas already carries dry/brown blades, and those
	// must not be turned again by a season they are already wearing.
	float greenness = clamp((COLOR.g - max(COLOR.r, COLOR.b)) * %s, 0.0, 1.0);
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * season_tint, greenness);
}
""" % [BEND_CURVE_EXPONENT, PHASE_SPREAD, AMPLITUDE_BASE, AMPLITUDE_VARIATION, AMPLITUDE_FREQUENCY, WIND_UV_AMPLITUDE, WALKER_PUSH_UV_AMPLITUDE, SeasonalFoliage.GREENNESS_GAIN]

var _material: ShaderMaterial
## Lazily-loaded, cached per season (see SEASON_ATLAS_PATHS) -- replaces a
## single shared `_texture` now that there are four sheets to choose between.
var _textures: Dictionary = {}
var _mesh: QuadMesh
## Last live wind strength pushed in (see set_wind_strength) -- applied to
## material() at BUILD time too, so a caller that sets the live wind before
## the material has been lazily built yet doesn't lose it.
var _wind_strength := DEFAULT_WIND_STRENGTH
## Last season tint pushed in (see set_season_tint) -- applied in material()
## at BUILD time too, so a caller that sets the season before the material has
## been lazily built doesn't lose it (same reasoning as _wind_strength above).
var _season_tint := Color(1.0, 1.0, 1.0)

## Some of the delivered sheets' taller "bush"/wheat-ear variants (the
## denser rows) draw their own plant art past their own cell's nominal
## bottom edge, bleeding into the TOP of the next row down -- a real
## property of the sheets themselves, not a rendering bug: a mechanically-
## sliced region with no inset hands a recipient card a fragment of the row
## ABOVE's plant sitting right at its own top edge. Because the shader flips
## root-at-bottom/tip-at-top (a card's local Y=0 is the ground, growing up),
## that fragment renders at the TIP -- the point farthest from the ground --
## genuinely detached from the card's own body by a real transparent gap.
## Reported live: "the grass now has floating artefacts above it" (snow gave
## the white background enough contrast to show it clearly, but the bleed
## itself is independent of snow).
##
## MEASURED, not eyeballed, against each real shipped sheet at its native
## 1254x1254 resolution, using the EXACT integer arithmetic atlas_region_
## for's own from/to computation uses (row * atlas_size.y / ATLAS_ROWS
## truncates, it does not round -- measuring with float rounding instead
## gives a subtly different, wrong nominal_top and was the source of a whole
## false trail of apparent cross-season mismatches before this was caught).
## Summer alone reproduces the table this was originally measured against
## pixel-for-pixel (`grass_blades.png`, now shipped as `grass_blades_summer.
## png`'s own pixels -- see docs/concept/long_grass.md), which is itself a
## real check that this measurement methodology is correct.
##
## PER-SEASON, not one table shared across all four: rows 0-5's own values
## are identical across every season (copied verbatim from the single shared
## table this superseded, not re-measured -- a shared value already covers
## them cleanly, so re-measuring them per season was out of scope for the
## investigation that split this table), but rows 6-9 (the four densest
## rows) measurably do NOT converge on one shared value -- the least-bled
## season's own real minimum sits well under the most-bled season's, so a
## single number either under-crops the worst season (real donor bleed still
## shows) or over-crops the best one (destroying real art that needed little
## or no inset). Splitting this by season lets each sheet use its OWN real
## minimum instead of the worst case across all four.
##
## Verified against all four real sheets by
## test_atlas_region_for_never_includes_the_previous_rows_bled_over_content_
## on_any_season_sheet, with exactly ONE remaining exception: winter's own
## row 9, whose art fills nearly its entire cell height (confirmed with a
## direct visual crop, not just measured) -- no inset, however large, lands
## its region's own top edge in a genuinely transparent zone across every
## column without cropping the row to a sliver. winter[9] below (12px) is
## still the real, measured BEST available value (a substantial improvement
## over the old shared table's 30px -- see
## test_winter_row_9_bleed_is_narrowed_but_not_fully_closed_by_the_per_
## season_table), just genuinely short of the 90% bar the other 35 (season,
## row) combinations in 6-9 all clear. A known, narrowed gap (see
## docs/concept/long_grass.md's Status), not a bug in this function.
const ROW_TOP_BLEED_PX_BY_SEASON := {
	"spring": [0, 3, 6, 11, 16, 19, 20, 26, 27, 12],
	"summer": [0, 3, 6, 11, 16, 19, 15, 20, 23, 7],
	"autumn": [0, 3, 6, 11, 16, 19, 19, 22, 27, 10],
	"winter": [0, 3, 6, 11, 16, 19, 20, 25, 27, 12],
}

## The atlas cell for a card of the given growth stage and variant seed --
## see docs/concept/long_grass.md's "Seasonal art" for why these are two
## independent axes rather than one flat hash across all 100 cells: `growth`
## (0..1, from `TallGrass.get_growth`) selects the ROW, a real drawn growth
## stage from a bare shoot (row 0) to a full flowering clump (last row);
## `seed_value` selects the COLUMN, the same per-card visual-variant hash as
## before. Growth is clamped, not wrapped -- a card never cycles back to a
## shoot once past the last row, it just stays on it.
##
## `season` selects which of `ROW_TOP_BLEED_PX_BY_SEASON`'s own rows to
## inset by -- an unrecognized name falls back to DEFAULT_SEASON, mirroring
## `_texture_for`'s own fallback. Defaulting to DEFAULT_SEASON rather than a
## required argument keeps every existing call site (this file's own
## `instances_for_cards` included, when it isn't told a season either)
## behaving exactly as before.
static func atlas_region_for(seed_value: int, growth: float, atlas_size: Vector2i = DEFAULT_ATLAS_SIZE, season: String = DEFAULT_SEASON) -> Rect2i:
	var column := posmod(seed_value, ATLAS_COLUMNS)
	var row := clampi(int(clampf(growth, 0.0, 1.0) * ATLAS_ROWS), 0, ATLAS_ROWS - 1)
	var bleed_table: Array = ROW_TOP_BLEED_PX_BY_SEASON.get(season, ROW_TOP_BLEED_PX_BY_SEASON[DEFAULT_SEASON])
	# The bleed table above is measured in native pixels of the REAL
	# 1254x1254 sheet; expressed as a fraction of one cell's own height so a
	# caller passing a differently-sized atlas_size (e.g. a smaller test
	# fixture) still gets a proportionally correct inset rather than an
	# oversized or negative-height region.
	var native_cell_height := float(DEFAULT_ATLAS_SIZE.y) / float(ATLAS_ROWS)
	var bleed_fraction := float(bleed_table[row]) / native_cell_height
	var cell_height := float(atlas_size.y) / float(ATLAS_ROWS)
	var top_inset := int(round(bleed_fraction * cell_height))
	var from := Vector2i(column * atlas_size.x / ATLAS_COLUMNS, row * atlas_size.y / ATLAS_ROWS + top_inset)
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


## A stable [0, 1) pseudo-random threshold derived from a card's own atlas
## seed -- a SEPARATE hash from the one that already picks its column/variant
## (atlas_region_for), so the two never correlate: two cards sharing a column
## must still be free to turn at different points in a season transition, or
## every card in that column would turn in lockstep. Compared against
## SeasonTransition's shared, quantised progress (see split_cards_by_turn)
## to decide whether this ONE card has turned to the next season's sheet
## yet -- the same "one shared clock, many independently-timed units" shape
## ProceduralTreeSprite's per-pixel _sweep_rank turns a canopy with, at card
## granularity instead of per-pixel (see docs/concept/long_grass.md's
## "Seasonal art").
static func turn_threshold_for_seed(atlas_seed: int) -> float:
	return float(posmod(hash("%d_grass_turn" % atlas_seed), 10000)) / 10000.0


## Splits `card_specs` (each {atlas_seed:int, position:Vector2, growth:float},
## see cards_for_cell) into {"from": [...], "to": [...]} by comparing each
## card's own turn_threshold_for_seed against `progress` -- a card samples
## the OLD season's sheet while progress is still below its own threshold,
## the NEW season's once progress reaches it. `progress <= 0.0` puts every
## card in "from" and `progress >= 1.0` puts every card in "to" without
## touching turn_threshold_for_seed at all, so a settled (non-transitioning)
## season -- the common case -- collapses to a single, cheap bucket. Cards
## are never dropped or duplicated: every input card lands in exactly one
## of the two returned arrays.
static func split_cards_by_turn(card_specs: Array, progress: float) -> Dictionary:
	var from: Array = []
	var to: Array = []
	if progress <= 0.0:
		from = card_specs.duplicate()
	elif progress >= 1.0:
		to = card_specs.duplicate()
	else:
		for card in card_specs:
			if turn_threshold_for_seed(card.atlas_seed) <= progress:
				to.append(card)
			else:
				from.append(card)
	return {"from": from, "to": to}


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
##
## `season` forwards straight into `atlas_region_for` so its own per-season
## bleed inset (`ROW_TOP_BLEED_PX_BY_SEASON`) actually takes effect -- without
## this, that table could be as correct as it likes and never affect what a
## card actually samples, since this is the only place `atlas_region_for` is
## called from. Defaults to DEFAULT_SEASON so every existing caller/test that
## never mentions a season keeps behaving exactly as before.
static func instances_for_cards(card_specs: Array, band_anchor: Vector2, atlas_size: Vector2i, season: String = DEFAULT_SEASON) -> Array[Dictionary]:
	var flat: Array[Dictionary] = []
	for card_spec in card_specs:
		flat.append({
			"region": atlas_region_for(card_spec.atlas_seed, card_spec.growth, atlas_size, season),
			"position": card_spec.position,
		})
	flat.sort_custom(func(a, b): return a.position.y < b.position.y)

	var texture_size := Vector2(atlas_size)
	var instances: Array[Dictionary] = []
	for entry in flat:
		var region: Rect2i = entry.region
		var local_pos: Vector2 = entry.position - band_anchor
		var region_uv0 := Vector2(region.position) / texture_size
		var region_uv1 := Vector2(region.position + region.size) / texture_size
		instances.append({
			# Full, undamped size regardless of growth -- growth now picks
			# WHICH row's art is sampled (see atlas_region_for), so scaling
			# on top of that would double-damp an already-smaller-drawn
			# shoot. See docs/concept/long_grass.md's "Seasonal art".
			"transform": Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), local_pos),
			"custom_data": Color(region_uv0.x, region_uv0.y, region_uv1.x, region_uv1.y),
		})
	return instances

## Only `grass_blades_summer.png` (the original shipped art) was ever
## authored with a real alpha channel -- the three new seasonal sheets
## (spring/autumn/winter) were delivered as plain opaque RGB, background and
## all (measured: Image.FORMAT_RGB8, corner/gutter pixels reading alpha=1.0
## uniformly). Loaded as-is, every card would render as a solid near-black
## rectangle instead of a cutout blade. BACKGROUND_KEY/BACKGROUND_KEY_
## TOLERANCE key that background out via SpriteSheetSlicer.chroma_keyed,
## which also upgrades the format to RGBA8 -- applied to every season
## uniformly (a no-op on a sheet already keyed to alpha=0, like summer's own
## background, so this never double-processes the one sheet that didn't need
## it). Tolerance measured against real sampled background pixels (up to
## ~0.012 per channel of compression noise around pure black); a visual
## check of the keyed result at this tolerance (spring/autumn/winter, saved
## and inspected directly) showed the background cleanly gone with no
## visible damage to the actual blade art.
const BACKGROUND_KEY := Color(0.0, 0.0, 0.0)
const BACKGROUND_KEY_TOLERANCE := 0.05

## Lazily loads and caches the atlas texture for one season, falling back to
## DEFAULT_SEASON for a name SEASON_ATLAS_PATHS doesn't recognise (mirrors
## SeasonalFoliage.tint_for_season's own fallback).
func _texture_for(season: String) -> Texture2D:
	if not _textures.has(season):
		var path: String = SEASON_ATLAS_PATHS.get(season, SEASON_ATLAS_PATHS[DEFAULT_SEASON])
		var image := SpriteSheetLoader.load_image(path)
		if image != null:
			image = SpriteSheetSlicer.chroma_keyed(image, BACKGROUND_KEY, BACKGROUND_KEY_TOLERANCE)
			_textures[season] = ImageTexture.create_from_image(image)
		else:
			_textures[season] = null
	return _textures[season]


## Rebuilds `mmi` (wiring its MultiMesh/material on first use if needed, and
## re-pointing its texture whenever `season` changes) so it renders every
## CARD in `card_specs` - each a {atlas_seed:int, position:Vector2,
## growth:float} (see `cards_for_cell`) - sampled from `season`'s own sheet,
## using that SAME season's own bleed inset for the region math too
## (forwarded into `instances_for_cards`, see its own doc comment) - not
## just which texture is bound.
##
## `band_anchor` must already be `mmi`'s own `position` (it drives this
## band's Y-sort key against the player/creatures); instance transforms are
## stored relative to it. Thin engine glue over instances_for_cards - see
## that function for the actual (headlessly-tested) placement math. This
## wrapper itself needs a real renderer to verify: MultiMesh per-instance
## transform/color storage is backed by the dummy renderer under
## `--headless` and silently doesn't round-trip there.
func fill_band(mmi: MultiMeshInstance2D, band_anchor: Vector2, card_specs: Array, season: String = DEFAULT_SEASON) -> void:
	var texture := _texture_for(season)
	if texture == null:
		push_error("Missing long-grass atlas for season '%s': %s" % [season, SEASON_ATLAS_PATHS.get(season)])
		return
	if mmi.multimesh == null:
		var new_mm := MultiMesh.new()
		new_mm.mesh = mesh()
		new_mm.transform_format = MultiMesh.TRANSFORM_2D
		new_mm.use_custom_data = true
		mmi.multimesh = new_mm
		mmi.material = material()
	mmi.texture = texture
	var mm: MultiMesh = mmi.multimesh
	var instances := instances_for_cards(card_specs, band_anchor, Vector2i(texture.get_size()), season)
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform_2d(i, instances[i].transform)
		mm.set_instance_custom_data(i, instances[i].custom_data)
