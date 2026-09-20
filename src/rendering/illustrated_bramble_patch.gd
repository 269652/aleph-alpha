extends RefCounted

## A chunk's worth of BlackberryBramble cells, drawn the way ferns are
## (docs/concept/brambles.md, "A bramble gives, and it fights back").
##
## This REPLACES a Sprite2D-per-thicket draw, and reverses the reasoning
## that chose it: *"brambles are sparse and woody — they do not sway"*.
## They sway now, slightly, because it was asked for — *"they should bend
## slightly when walked over from the side"* — and a plain Sprite2D
## cannot carry the bend at all: the shared shader reads INSTANCE_CUSTOM
## for its atlas sub-rect and the instance origin for its root, and neither
## exists outside a MultiMesh.
##
## Like IllustratedFernPatch, it REACHES INTO IllustratedGrassPatch for
## everything about the motion rather than restating it — the shader, the
## mesh subdivision that gives a bent card somewhere to go, and the band
## maths that decides what Y-sorts in front of what. A second bend would be
## two wind systems in one world, visible the moment a thicket swayed out
## of time with the bracken beside it.
##
## What is genuinely this file's own is the SHEET, the geometry it implies,
## and HOW FAR IT GIVES — a cane is woody where a blade is not, which is
## the whole of "bend slightly".

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

## The delivered sheet — real alpha already, so unlike the fern sheet
## nothing is keyed out of it.
const ATLAS_PATH := "res://assets/sprites/plants/blackberry.png"

## How much of the bend a thicket takes (see
## IllustratedGrassPatch.DEFAULT_BEND_SCALE, which is 1.0 — a grass blade
## laying flat).
##
## A quarter, because a cane is woody: it gives a little under a leg going
## past and springs back, where a blade lays over. Asked for as *"bend
## slightly when walked over from the side"*, and the ORDERING against the
## plants that lay over is what a test pins, not this literal.
const BEND_SCALE := 0.25

## 5x5 clumps, the same grid the fern sheet uses.
const ATLAS_COLUMNS := 5
const ATLAS_ROWS := 5
const DEFAULT_ATLAS_SIZE := Vector2i(1254, 1254)

## One tile in world units (TerrainRenderer.TILE_SIZE), restated rather
## than imported so this file stays pure geometry a headless test can reach
## without dragging a tilemap in. It is what a card's ROOT offset is
## bounded by — which is NOT the same thing as the card's own size below,
## and separating the two is the point: a fern is drawn larger than the
## tile it stands on, the way a real clump arches over its own patch of
## ground, while its root still has to be on that tile and not the
## neighbour's.
const TILE_SPAN := 16.0

## How many cards one fern cell draws, and how big each is drawn.
##
## Fewer and larger than grass, and the two are one decision. A grass cell
## draws 8 cards because a cell of meadow IS many blades; each delivered
## FERN cell is already a whole clump with its own rocks, logs and
## mushrooms drawn into it, so stacking eight per tile would read as a
## hedge. The budget that keeps this honest is fill rate rather than card
## count — every card is a translucent, alpha-blended, shaded quad the GPU
## must rasterize and blend regardless of batching (see
## IllustratedGrassPatch.CARD_COUNT's own history, and the integrated GPU
## that measured it) — so what a test pins is AREA: a fern tile must blend
## no more pixels than a grass tile does. 3 x 22^2 = 1452 against grass's
## 8 x 16^2 = 2048.
## ONE card, not three. A thicket is a single woody clump with its own
## berries and leaf litter drawn into it, where a fern cell is a stand of
## fronds worth stacking — and brambles are the sparser plant besides, so
## a second card per cell would be pure overdraw for no read. Drawn at a
## fern's own size.
const CARD_COUNT := 1
const WORLD_SIZE := 22.0


# -- the bend, which is the long grass's own -------------------------------
#
# Forwarders, deliberately: each of these is ONE implementation reached
# through two names, so a change to how a blade bends is a change to how a
# frond bends and cannot be anything else. The tests assert the equality
# directly, which is trivially true by construction — that is what they
# are for.

## The identical bend shader. A static var rather than a const because
## IllustratedGrassPatch builds its own source at load.
static var SHADER_CODE: String = IllustratedGrassPatch.SHADER_CODE


static func bend_curve(top_t: float) -> float:
	return IllustratedGrassPatch.bend_curve(top_t)


static func local_row_for_world_y(world_y: float, chunk_origin_y: int, tile_size: float) -> float:
	return IllustratedGrassPatch.local_row_for_world_y(world_y, chunk_origin_y, tile_size)


static func band_index_for_local_y(
	local_y: float, chunk_size: int, band_count: int = IllustratedGrassPatch.BAND_COUNT
) -> int:
	return IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size, band_count)


static func band_anchor_world_y(
	band_index: int, chunk_origin_y: int, chunk_size: int, tile_size: float,
	band_count: int = IllustratedGrassPatch.BAND_COUNT
) -> float:
	return IllustratedGrassPatch.band_anchor_world_y(
		band_index, chunk_origin_y, chunk_size, tile_size, band_count
	)


# -- the sheet, which is this file's own ------------------------------------

## The atlas cell for a card of the given growth stage and variant seed.
##
## The same two INDEPENDENT axes long grass uses, and for the same reason:
## `growth` (0..1, from ForestFern.get_growth) selects the ROW, a young
## clump through a full one; `seed_value` selects the COLUMN, the per-card
## visual variant. Clamped, not wrapped — a mature fern stays mature
## rather than cycling back to a shoot.
##
## No per-row bleed table, unlike grass: that table exists because the
## grass sheet's own rows bleed into each other, and this sheet's cells sit
## clear of their own boundaries. If a measurement ever shows otherwise,
## the fix belongs here in the same shape.
static func atlas_region_for(
	seed_value: int, growth: float, atlas_size: Vector2i = DEFAULT_ATLAS_SIZE
) -> Rect2i:
	var column := posmod(seed_value, ATLAS_COLUMNS)
	var row := clampi(int(clampf(growth, 0.0, 1.0) * ATLAS_ROWS), 0, ATLAS_ROWS - 1)
	var from := Vector2i(
		column * atlas_size.x / ATLAS_COLUMNS, row * atlas_size.y / ATLAS_ROWS
	)
	var to := Vector2i(
		(column + 1) * atlas_size.x / ATLAS_COLUMNS, (row + 1) * atlas_size.y / ATLAS_ROWS
	)
	return Rect2i(from, to - from)


## Each card's own variant seed, root offset within the tile, and depth.
##
## The offsets spread a clump across most of its own TILE rather than
## huddling at its centre — the same thing grass's own offsets do, bounded
## by the tile instead of by the card, since a fern card is bigger than a
## tile. 11 x 9 buckets at these steps reach about +/-3.4 and +/-3.4 of the
## +/-8 a tile allows, so three cards read as one clump filling its ground
## rather than three ferns in a row.
static func card_specs_for_seed(seed_value: int) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for index in CARD_COUNT:
		var h := absi(hash("%d_bramble_card_%d" % [seed_value, index]))
		var offset := Vector2(
			float(posmod(h, 11) - 5) * 0.68,
			float(posmod(h / 11, 9) - 4) * 0.85
		)
		specs.append({"seed": h, "offset": offset, "depth": CARD_COUNT - index})
	return specs


## Expands ONE cell spec ({seed:int, ground_position:Vector2, growth:float})
## into its CARD_COUNT per-card specs — the single seam for turning a cell
## into its cards, so the chunk manager's Y-sort banding and this file's own
## placement maths can never drift apart. Exactly
## IllustratedGrassPatch.cards_for_cell's contract, over this file's cards.
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


## Every given card's instance transform and packed atlas region, from
## plain per-card data only — no MultiMesh or Texture2D access, so it is
## headlessly testable on its own. Sorted back to front by ground Y so
## overlapping alpha-blended clumps blend in roughly the right order.
##
## Never scaled by growth: growth picks WHICH row is sampled (see
## atlas_region_for), so scaling on top of that would double-damp an
## already-smaller-drawn young clump.
static func instances_for_cards(
	card_specs: Array, band_anchor: Vector2, atlas_size: Vector2i
) -> Array[Dictionary]:
	var flat: Array[Dictionary] = []
	for card_spec in card_specs:
		flat.append({
			"region": atlas_region_for(card_spec.atlas_seed, card_spec.growth, atlas_size),
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
			"transform": Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), local_pos),
			"custom_data": Color(region_uv0.x, region_uv0.y, region_uv1.x, region_uv1.y),
		})
	return instances


# -- the live bits ----------------------------------------------------------

## ONE keyed sheet for every patch in the world, not one per chunk: a 1254
## square texture held per loaded chunk is the kind of cost that only shows
## up once a player has walked a while. Static, and pinned by
## test_every_patch_shares_one_sheet.
static var _texture: Texture2D = null
static var _texture_loaded := false

var _material: ShaderMaterial
var _mesh: QuadMesh
var _wind_strength := IllustratedGrassPatch.DEFAULT_WIND_STRENGTH
var _season_tint := Color(1.0, 1.0, 1.0)


## The sheet, loaded once and shared by every patch in the world.
func texture() -> Texture2D:
	if not _texture_loaded:
		_texture_loaded = true
		var image := SpriteSheetLoader.load_image(ATLAS_PATH)
		if image != null:
			# NOT keyed: this sheet was delivered with real alpha, unlike
			# the fern sheet's painted checkerboard. Keying it anyway would
			# punch holes through every pale berry highlight.
			_texture = ImageTexture.create_from_image(image)
	return _texture


func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("wind_strength", _wind_strength)
		_material.set_shader_parameter("season_tint", _season_tint_vector())
		# The one thing that makes a cane read as woody rather than as a
		# tall blade. Set once, here, rather than per frame: it is a fact
		# about the plant, not a live condition like the wind.
		_material.set_shader_parameter("bend_scale", BEND_SCALE)
	return _material


func mesh() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(WORLD_SIZE, WORLD_SIZE)
		# Local (0,0) at the quad's BOTTOM edge: the root is on the ground
		# and the plant grows up from it, so neither growth nor bend can
		# drift a fern off the tile it stands on.
		_mesh.center_offset = Vector3(0.0, -WORLD_SIZE * 0.5, 0.0)
		# The bend moves this mesh's own vertices (see the shader's
		# vertex()), so it needs vertices to move — the grass's own
		# subdivision, because it is the grass's own bend.
		_mesh.subdivide_width = IllustratedGrassPatch.BEND_MESH_SUBDIVIDE_WIDTH
		_mesh.subdivide_depth = IllustratedGrassPatch.BEND_MESH_SUBDIVIDE_DEPTH
	return _mesh


func set_walker_position(world_position: Vector2) -> void:
	material().set_shader_parameter("player_world_position", world_position)


## The live wind strength (WeatherModel.wind_strength_for, via
## EarthChunkManager.set_wind_strength) — the same uniform the grass's own
## material carries, so a wood and the meadow beside it sway in one wind.
func set_wind_strength(strength: float) -> void:
	_wind_strength = strength
	material().set_shader_parameter("wind_strength", strength)


## The season's tint on living green (SeasonalFoliage, via
## EarthChunkManager.set_season_tint). The fern sheet has no seasonal
## variants of its own, so this is the whole of how a November wood differs
## from an August one.
func set_season_tint(tint: Color) -> void:
	_season_tint = tint
	material().set_shader_parameter("season_tint", _season_tint_vector())


func _season_tint_vector() -> Vector3:
	return Vector3(_season_tint.r, _season_tint.g, _season_tint.b)


## Rebuilds `mmi` so it renders every card in `card_specs`. `band_anchor`
## must already be `mmi`'s own position (it drives this band's Y-sort key);
## instance transforms are stored relative to it. Thin engine glue over
## instances_for_cards — MultiMesh per-instance storage is backed by the
## dummy renderer under --headless and silently does not round-trip there,
## which is why the maths lives in a function a headless test can reach.
func fill_band(mmi: MultiMeshInstance2D, band_anchor: Vector2, card_specs: Array) -> void:
	var sheet := texture()
	if sheet == null:
		push_error("Missing bramble atlas: %s" % ATLAS_PATH)
		return
	if mmi.multimesh == null:
		var new_mm := MultiMesh.new()
		new_mm.mesh = mesh()
		new_mm.transform_format = MultiMesh.TRANSFORM_2D
		new_mm.use_custom_data = true
		mmi.multimesh = new_mm
		mmi.material = material()
	mmi.texture = sheet
	var mm: MultiMesh = mmi.multimesh
	var instances := instances_for_cards(card_specs, band_anchor, Vector2i(sheet.get_size()))
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform_2d(i, instances[i].transform)
		mm.set_instance_custom_data(i, instances[i].custom_data)
