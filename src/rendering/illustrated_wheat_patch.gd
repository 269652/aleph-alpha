extends RefCounted

## Wheat's own real illustrated art -- a second atlas FAMILY reusing long
## grass's exact grid convention (10x10 cells, 1254x1254, chroma-keyed
## black background) and its exact per-pixel-row bend/wind/walker-push
## shader math, but NOT its GPU-instanced MultiMesh/banding machinery: a
## single farm plot is one tile, nowhere near the "several thousand
## simultaneous cards" scale that made MultiMesh worth its own complexity
## for the open-field grass system (see docs/concept/long_grass.md's own
## pillar 4). A plot's own handful of blades render as ordinary Sprite2D
## children instead (see FarmPlotMarker) -- cheap at this density, and
## fully unit-testable, unlike MultiMesh under --headless (see
## IllustratedGrassPatch.fill_band's own doc comment on that).
##
## See docs/concept/long_grass.md's "A second atlas family: farmed wheat".

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")
const ProceduralSoilSprite = preload("res://src/rendering/procedural_soil_sprite.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const SHEET_PATHS := {
	"spring": "res://assets/sprites/plants/wheat_spring.png",
	"summer": "res://assets/sprites/plants/wheat_summer.png",
	"autumn": "res://assets/sprites/plants/wheat_autumn.png",
}

## No wheat_winter.png has been delivered -- an unrecognised/missing season
## falls back here, mirroring IllustratedGrassPatch.DEFAULT_SEASON's own
## "unexpectedly wrong look reads better than no art at all" reasoning.
## Real-world grounding for THIS specific choice: wheat is realistically
## harvested well before winter, so a standing plot still reading "golden
## and ripe" through an early frost is the honest choice over inventing a
## fourth look with no real art behind it.
const DEFAULT_SEASON := "summer"

## Measured directly (tools/probe_wheat_sheet_bleed.gd) against all three
## real delivered sheets: every row's real (post-chroma-key) content stays
## flush inside its own nominal cell boundary on every row of every sheet --
## a genuine "measured, found none" result, unlike long grass's own art
## (see IllustratedGrassPatch.ROW_TOP_BLEED_PX_BY_SEASON). Kept as a real,
## explicit table (all zero) rather than simply omitting bleed handling, so
## a future remeasurement against a regenerated sheet has an obvious place
## to record a nonzero finding instead of silently reintroducing the bug
## grass's own art already had.
const BLEED_PX_BY_ROW := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

## How big a single blade should read on the ground, in world pixels -- the
## SAME target IllustratedCropSprite's carrot/potato leaves use (comparable
## to a piece of dropped fruit, never tile-sized), for the identical reason:
## a farm plot's crop must not tower over its own soil mound. Deliberately
## NOT IllustratedGrassPatch.WORLD_SIZE (16.0, a full open-field tile) --
## that scale exists for grass drawn directly on bare ground across a whole
## chunk, not for a crop sitting on one small tilled mound.
const BLADE_WORLD_SIZE := IllustratedCropSprite.LEAF_WORLD_SIZE

## Farm-plot blades spread within the SAME soil mound FarmPlotMarker already
## draws (ProceduralSoilSprite.SOIL_WORLD_WIDTH), not a full open-field
## tile -- IllustratedGrassPatch.card_specs_for_seed's own offsets (sized
## for its WORLD_SIZE=16.0 tile) are scaled down by exactly the mound's own
## width ratio to that tile size, so blades spread proportionally within the
## mound's real footprint instead of spilling past its visible edge.
const _SOIL_TO_TILE_RATIO := ProceduralSoilSprite.SOIL_WORLD_WIDTH / IllustratedGrassPatch.WORLD_SIZE

static var SHADER_CODE: String = _build_shader_code()
static var _material: ShaderMaterial

var _keyed_images: Dictionary = {}  # season String -> Image (chroma-keyed) or null
var _frame_cache: Dictionary = {}  # "season_row_column" String -> ImageTexture
var _scale_cache: Dictionary = {}  # same key -> float


func has_sheet(season: String) -> bool:
	return SHEET_PATHS.has(season)


## Which of the real delivered sheets a given world-calendar season name
## should sample from -- an undelivered/unrecognised name (today: "winter",
## or anything not a real season string at all) falls back to DEFAULT_SEASON.
func sheet_for_season(season: String) -> String:
	return season if has_sheet(season) else DEFAULT_SEASON


## The atlas cell rect for a plain (row, column) index pair -- the same
## column/row division IllustratedGrassPatch.atlas_region_for uses (reusing
## its own ATLAS_COLUMNS/ATLAS_ROWS constants directly rather than
## restating "10"/"10"), but with NO bleed inset: wheat's own measured
## table (BLEED_PX_BY_ROW) is all zero, so there is nothing to crop away.
static func region_for(row: int, column: int, atlas_size: Vector2i = IllustratedGrassPatch.DEFAULT_ATLAS_SIZE) -> Rect2i:
	var from := Vector2i(
		column * atlas_size.x / IllustratedGrassPatch.ATLAS_COLUMNS,
		row * atlas_size.y / IllustratedGrassPatch.ATLAS_ROWS
	)
	var to := Vector2i(
		(column + 1) * atlas_size.x / IllustratedGrassPatch.ATLAS_COLUMNS,
		(row + 1) * atlas_size.y / IllustratedGrassPatch.ATLAS_ROWS
	)
	return Rect2i(from, to - from)


## Maps a FarmPlot's own continuous 0..1 growth fraction onto a discrete
## atlas row -- the same shoot-to-full-bush mapping IllustratedGrassPatch.
## atlas_region_for uses for TallGrass's own growth (0 at the top of the
## sheet, ATLAS_ROWS-1 at the bottom), reusing its ATLAS_ROWS constant
## directly. Clamped, not wrapped: a plot never cycles back to a shoot once
## fully grown, it just stays on the last row.
static func row_for_growth(growth: float) -> int:
	return clampi(int(clampf(growth, 0.0, 1.0) * IllustratedGrassPatch.ATLAS_ROWS), 0, IllustratedGrassPatch.ATLAS_ROWS - 1)


## One of CARD_COUNT deterministic per-blade specs ({seed:int, offset:
## Vector2}), scaled to fit within the farm plot's own soil-mound footprint
## rather than IllustratedGrassPatch.card_specs_for_seed's own full-tile
## spread -- see _SOIL_TO_TILE_RATIO's own doc comment. Reuses that
## function's exact hash-derived offsets (same relative distribution shape,
## same per-blade seed), just rescaled, so a farm plot's blades still spread
## deterministically across most of its own mound rather than clumping.
static func blade_specs_for_seed(seed_value: int) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for spec in IllustratedGrassPatch.card_specs_for_seed(seed_value):
		specs.append({"seed": spec.seed, "offset": (spec.offset as Vector2) * _SOIL_TO_TILE_RATIO})
	return specs


## The real, already-cropped texture for one (season, row, column) frame --
## null only if `season`'s own sheet (after sheet_for_season's fallback)
## fails to load. Cached: the underlying art never changes per session, so
## re-slicing per caller would be pure waste (mirrors IllustratedCropSprite's
## own _leaf_frame_cache).
func frame_texture(season: String, row: int, column: int) -> Texture2D:
	var real_season := sheet_for_season(season)
	var key := "%s_%d_%d" % [real_season, row, column]
	if not _frame_cache.has(key):
		_frame_cache[key] = _slice(real_season, row, column)
	return _frame_cache[key]


## The scale factor a marker applies to a (season, row, column) blade so its
## REAL drawn content extent (not the nominal cell size, which can carry
## padding) reads at BLADE_WORLD_SIZE on screen -- the same "measure the
## real pixels" discipline IllustratedCropSprite.leaf_world_scale already
## uses, avoiding the exact "gigantic sprite" bug that discipline was
## introduced to fix.
func blade_world_scale(season: String, row: int, column: int) -> float:
	var real_season := sheet_for_season(season)
	var key := "%s_%d_%d" % [real_season, row, column]
	if not _scale_cache.has(key):
		var extent := IllustratedCropSprite.max_content_extent(frame_texture(season, row, column))
		_scale_cache[key] = BLADE_WORLD_SIZE / maxf(extent, 1.0)
	return _scale_cache[key]


func _keyed_image(season: String) -> Image:
	if not _keyed_images.has(season):
		if not SHEET_PATHS.has(season):
			_keyed_images[season] = null
		else:
			var raw := SpriteSheetLoader.load_image(SHEET_PATHS[season])
			_keyed_images[season] = (
				null if raw == null
				else SpriteSheetSlicer.chroma_keyed(raw, IllustratedGrassPatch.BACKGROUND_KEY, IllustratedGrassPatch.BACKGROUND_KEY_TOLERANCE)
			)
	return _keyed_images[season]


func _slice(season: String, row: int, column: int) -> ImageTexture:
	var image := _keyed_image(season)
	if image == null:
		return null
	var region := region_for(row, column, image.get_size())
	return ImageTexture.create_from_image(image.get_region(region))


## Every constant this shader needs is READ FROM IllustratedGrassPatch, not
## restated -- "essentially the same" bending enforced by construction: the
## two shaders cannot silently drift apart on a re-tune of one without the
## other, because there is only one set of numbers.
static func _build_shader_code() -> String:
	return """
shader_type canvas_item;
uniform vec2 player_world_position = vec2(-100000.0);
uniform float walker_radius = 22.0;
uniform float wind_speed = 1.6;
uniform float wind_strength = 1.0;

varying vec2 v_root;

void vertex() {
	// Roots never translate -- the only geometry touch, reading the local
	// origin (this Sprite2D's own transform origin) rather than VERTEX, so
	// it stays fixed regardless of bend. Mirrors IllustratedGrassPatch's
	// own vertex() exactly.
	v_root = (MODEL_MATRIX * vec4(vec2(0.0), 0.0, 1.0)).xy;
}

void fragment() {
	// A Sprite2D's own UV.y=0 is the TOP of its bound texture and UV.y=1 is
	// the BOTTOM (standard canvas-item texture-space convention) -- the
	// OPPOSITE of IllustratedGrassPatch's MultiMesh quad, whose own local
	// UV.y=0 is the ROOT/bottom (verified empirically there -- see that
	// file's own comment). Every wheat frame is cropped root-at-the-
	// image's-own-bottom / tip-at-top (the same upright-plant convention
	// every illustrated sheet in this codebase already draws), so "distance
	// from root toward tip" for THIS node is 1.0 - UV.y, not UV.y directly.
	float top_t = 1.0 - UV.y;
	float bend = pow(clamp(top_t, 0.0, 1.0), %s);
	float phase = UV.x * %s;
	float amplitude_scale = %s + %s * sin(UV.x * %s);

	vec2 from_walker = v_root - player_world_position;
	float distance_to_walker = length(from_walker);
	vec2 away = from_walker / max(distance_to_walker, 0.001);
	float wake = 1.0 - smoothstep(0.0, walker_radius, distance_to_walker);

	float wind = sin(TIME * wind_speed + v_root.x * 0.071 + v_root.y * 0.043 + phase) * %s * wind_strength * amplitude_scale;
	float push = away.x * wake * %s;
	float bend_offset = (wind + push) * bend;

	// Displaces the *sampled* UV per pixel row instead of shearing the
	// sprite's own quad geometry -- identical path-tracing shape to
	// IllustratedGrassPatch's own fragment(). No atlas-region remapping is
	// needed here (unlike grass's shared-atlas-per-band shader): each
	// Sprite2D is already bound to its own single, pre-cropped frame
	// texture, so its own local UV already covers exactly that frame.
	float raw_local_x = UV.x - bend_offset;
	float local_x = clamp(raw_local_x, 0.0, 1.0);
	COLOR = texture(TEXTURE, vec2(local_x, UV.y));
	// Same edge-smear guard grass's own shader uses: a fragment whose true,
	// unclamped position bent past its own frame's edge shows nothing
	// instead of a stretched repeat of the clamped edge pixel.
	if (raw_local_x < 0.0 || raw_local_x > 1.0) {
		COLOR.a = 0.0;
	}
}
""" % [
		IllustratedGrassPatch.BEND_CURVE_EXPONENT, IllustratedGrassPatch.PHASE_SPREAD,
		IllustratedGrassPatch.AMPLITUDE_BASE, IllustratedGrassPatch.AMPLITUDE_VARIATION,
		IllustratedGrassPatch.AMPLITUDE_FREQUENCY, IllustratedGrassPatch.WIND_UV_AMPLITUDE,
		IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE,
	]


## ONE shared ShaderMaterial across every wheat blade in the whole running
## game (mirrors IllustratedGrassPatch.material()'s own "every card in a
## band shares one material" precedent, taken one step further into "every
## blade on every farm shares one material" since there is no per-band
## atlas-region data to pack per instance here) -- so a single
## set_wind_strength/set_walker_position call updates every wheat plot
## everywhere in one write, exactly like grass's own single shared uniform.
static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("wind_strength", IllustratedGrassPatch.DEFAULT_WIND_STRENGTH)
	return _material


static func set_wind_strength(strength: float) -> void:
	material().set_shader_parameter("wind_strength", strength)


static func set_walker_position(world_position: Vector2) -> void:
	material().set_shader_parameter("player_world_position", world_position)
