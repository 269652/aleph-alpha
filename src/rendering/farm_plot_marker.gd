extends Node2D

## The visible, player-tillable/plantable/harvestable counterpart to
## FarmPlot (docs/concept/farming.md's "farming loop") -- wraps one FarmPlot
## instance (the pure growth/state-machine logic, already real and tested)
## and draws its current state: tilled soil (see ProceduralSoilSprite,
## shared with WildCropMarker's own soil mound -- same dirt regardless of
## what's growing in it) plus the crop's own growth-stage leaves (see
## IllustratedCropSprite, the SAME art wild carrot/potato patches already
## use -- farmed and wild share one art/DNA model per docs/concept/
## farming.md's "Resolved" section).
##
## Unlike WildCropMarker (a dumb view pushed state by an external per-chunk
## sim), this marker OWNS and drives its own FarmPlot directly -- a farm
## plot is already a single, independent, player-placed instance with
## nothing chunk-wide to share, so there's no separate sim class the way
## WildCropPatch exists for many wild cells at once. EarthChunkManager still
## owns WHEN growth actually advances (see advance(), called from
## step_farm_plots on the world's own ecology tick) and WHERE this marker is
## parented/positioned -- this class only owns the plot's rules and its own
## drawing, mirroring the project's "pure logic (FarmPlot) + thin Node glue
## (this)" split everywhere else.

const FarmPlot = preload("res://src/gameplay/farm_plot.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")
const ProceduralSoilSprite = preload("res://src/rendering/procedural_soil_sprite.gd")
const IllustratedWheatPatch = preload("res://src/rendering/illustrated_wheat_patch.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
## The tilled ground a bed stands on -- see docs/concept/village_farms.md's
## "A bed stands on real tilled earth", and _build_soil_ground below.
const IllustratedTerrainSprite = preload("res://src/rendering/illustrated_terrain_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## The crop_id that renders via IllustratedWheatPatch's bending-blade path
## instead of IllustratedCropSprite's flat leaf sprite -- see
## docs/concept/long_grass.md's "A second atlas family: farmed wheat". The
## autonomous Farm/Farmer (docs/concept/npc_farm_production.md) already
## plants and harvests real "wheat" through this exact class; it had no
## real crop art at all until this (IllustratedCropSprite.has_crop("wheat")
## is false, so leaf_texture returned null -- a growing wheat plot showed
## bare tilled soil with nothing visibly growing in it).
const WHEAT_CROP_ID := "wheat"

const GROUP_NAME := "farm_plot"

## The IllustratedTerrainSprite sheet a bed's own ground comes from. Not a
## biome -- nothing ever looks it up by biome name (see that file's own
## "soil" entry); this is the one caller.
const SOIL_SHEET := "soil"

## Draw order within the marker. The ground is the ground: the mound sits on
## it and the crop grows out of it, so both draw above. Explicit rather than
## relying on child order, matching this codebase's "every z-sensitive node
## sets it" convention.
const SOIL_GROUND_Z_INDEX := -2
const MOUND_Z_INDEX := -1
const LEAVES_Z_INDEX := 0

## Wilted tint applied to a withered plot's leaves -- desaturated and
## darkened, a "read as dead/neglected at a glance" signal distinct from a
## healthy plot's identity WHITE, so a player can tell a plot died without
## having to inspect it.
const WITHERED_TINT := Color(0.55, 0.5, 0.38)

var plot := FarmPlot.new()

static var _illustrated := IllustratedCropSprite.new()
static var _wheat := IllustratedWheatPatch.new()
static var _terrain := IllustratedTerrainSprite.new()
## variant index -> the soil texture for it, shared by every bed that rolls
## that variant. Nine variants against however many beds a village works, so
## without this each bed uploaded its own copy of one of nine 32x32 images
## -- the same per-tile texture waste CharacterPreviewDiorama._build_ground
## was fixed for. Static because the frames behind it are (see
## IllustratedTerrainSprite._frame_cache).
static var _soil_textures: Dictionary = {}

## The full-tile tilled earth under everything (see _build_soil_ground).
## Distinct from _soil, which is ProceduralSoilSprite's small MOUND -- a
## root crop's own ground, hidden for wheat. This one is never hidden: a
## bed is tilled earth whatever is (or is not) growing in it.
var _soil_ground: Sprite2D
var _soil: Sprite2D
var _leaves: Sprite2D
## Real Sprite2D children for a wheat crop's own small cluster of bending
## blades -- ordinary sprites, not GPU-instanced MultiMesh, since a single
## farm plot's handful of blades is nowhere near the density that would
## need it (see IllustratedWheatPatch's own doc comment). Pooled/reused
## across redraws (hidden rather than freed when the count needed shrinks)
## so replanting doesn't churn nodes every tick.
var _wheat_blades: Array[Sprite2D] = []
## Last season pushed in via advance() -- persists across till_and_plant/
## water/harvest calls (none of which change the season) so _redraw() has
## something sensible to use even when called from one of those instead of
## advance() itself. Defaults to IllustratedWheatPatch's own DEFAULT_SEASON
## so a freshly-planted, never-yet-advanced wheat plot still renders
## something real on the very first _redraw().
var _season := IllustratedWheatPatch.DEFAULT_SEASON

## What this bed was last SOWN with, which outlives plot.crop_id: harvesting
## clears the crop, and the ground a bed was last worked as is what it still
## looks like afterwards. Without it a cut wheat bed grew its soil mound
## back the moment the wheat came off -- caught by
## test_a_harvested_wheat_bed_still_shows_no_mound.
var _sown_crop_id := ""


func _ready() -> void:
	add_to_group(GROUP_NAME)

	_build_soil_ground()

	_soil = Sprite2D.new()
	_soil.texture = ProceduralSoilSprite.new().generate_texture(false)
	_soil.scale = Vector2.ONE * ProceduralSoilSprite.SOIL_WORLD_SCALE
	_soil.z_index = MOUND_Z_INDEX
	add_child(_soil)

	_leaves = Sprite2D.new()
	_leaves.z_index = LEAVES_Z_INDEX
	add_child(_leaves)

	_redraw()


## Advances this plot's growth by `delta` world-clock seconds (see
## EarthChunkManager.step_farm_plots) and refreshes what's drawn to match --
## the one place growth actually ticks, so a caller never needs to
## separately remember to redraw after advancing. `season` (the world's
## current calendar season, see EarthChunkManager.current_season) only
## affects a WHEAT crop's own art (see _redraw_wheat) -- optional and
## defaulted so every pre-existing call site (including this file's own
## tests) keeps working unchanged.
func advance(delta: float, season: String = IllustratedWheatPatch.DEFAULT_SEASON) -> void:
	plot.advance(delta)
	_season = season
	_redraw()


## Tills and plants `crop_id`, unless a live crop (growing or ready) already
## occupies this plot -- a stray press must never destroy an unharvested
## crop. Safe on an empty OR withered plot (matches FarmPlot.plant's own
## "always resets to growing" contract). Returns whether planting actually
## happened.
func till_and_plant(crop_id: String, seed_value: int) -> bool:
	if plot.state == "growing" or plot.state == "ready":
		return false
	plot.plant(crop_id, seed_value)
	_sown_crop_id = crop_id
	_redraw()
	return true


## Tends the plot, resetting its neglect clock (see FarmPlot.water) -- only
## meaningful while actually growing. Returns whether watering happened.
func water() -> bool:
	if plot.state != "growing":
		return false
	plot.water()
	return true


## Harvests a ready plot (see FarmPlot.harvest) -- returns the
## {"crop_id", "count"} result (a zero-count no-op result if not ready), and
## redraws either way (a successful harvest clears the leaves back to bare
## tilled soil, ready to be planted again without re-tilling).
func harvest() -> Dictionary:
	var result := plot.harvest()
	_redraw()
	return result


## Whether this plot is currently drawing its crop via IllustratedWheatPatch's
## bending-blade path rather than IllustratedCropSprite's flat leaf sprite.
func is_rendering_bending_wheat() -> bool:
	return plot.crop_id == WHEAT_CROP_ID and plot.state != "empty"


## The season last pushed in via advance() -- see EarthChunkManager.
## step_farm_plots, which forwards its own current_season() here every
## tick. Only ever affects a wheat crop's own art (_redraw_wheat).
func current_wheat_season() -> String:
	return _season


## How many real Sprite2D blade children are currently visible -- 0 whenever
## this plot isn't a growing/ready/withered wheat crop.
func wheat_blade_count() -> int:
	var count := 0
	for blade in _wheat_blades:
		if blade.visible:
			count += 1
	return count


## Whether this plot is drawing ProceduralSoilSprite's mound of tilled
## earth under its crop. NOT about the ground the bed stands on -- see
## soil_ground(), which is always shown.
func is_showing_soil() -> bool:
	return _soil != null and _soil.visible


## The full tile of tilled earth this bed stands on.
##
## Before this, the only soil a bed drew was ProceduralSoilSprite's small
## mound, and that mound is a ROOT crop's own ground -- correctly hidden for
## wheat (see _redraw). Which meant a wheat bed was six rectangles of the
## untouched meadow it had been tilled out of, with wheat rising from the
## grass: nothing had ever drawn the ground a bed IS. Reported with the beds
## circled, and answered here rather than by bringing the blob back.
func soil_ground() -> Sprite2D:
	return _soil_ground


## Which of soil.png's nine variants a bed at `tile` stands on. Hashed from
## the tile itself, so neighbouring beds in one 3x2 patch differ while any
## given bed looks the same every time it is drawn -- the same seeded-
## determinism convention every other art pick in this codebase follows.
static func soil_variant_for(tile: Vector2i) -> int:
	var count := _terrain.frame_count_for(SOIL_SHEET)
	if count <= 0:
		return 0
	return absi(hash("%d_%d_farm_soil" % [tile.x, tile.y])) % count


## One full-tile soil sprite, scaled from the art's OWN pixel width so it
## covers exactly TerrainRenderer.TILE_SIZE however the sheet is authored --
## the same derive-from-the-art rule CharacterPreviewDiorama._build_ground
## follows, rather than a hardcoded scale that silently breaks if the art is
## ever re-exported at another size.
##
## Seeded from this marker's own tile, which it reads back off its position:
## EarthChunkManager sets that before add_child (so it is already correct by
## _ready), and a bed never moves afterwards.
func _build_soil_ground() -> void:
	_soil_ground = Sprite2D.new()
	_soil_ground.z_index = SOIL_GROUND_Z_INDEX
	var tile := Vector2i(
		floori(position.x / float(TerrainRenderer.TILE_SIZE)),
		floori(position.y / float(TerrainRenderer.TILE_SIZE))
	)
	var variant := soil_variant_for(tile)
	var image := _terrain.frame_for(SOIL_SHEET, variant)
	if image != null:
		if not _soil_textures.has(variant):
			_soil_textures[variant] = ImageTexture.create_from_image(image)
		_soil_ground.texture = _soil_textures[variant]
		_soil_ground.scale = (
			Vector2.ONE * (float(TerrainRenderer.TILE_SIZE) / float(image.get_width()))
		)
	add_child(_soil_ground)


func _redraw() -> void:
	if _leaves == null:
		return  # not _ready() yet
	# Reported with the beds circled: "what's the round procedural dark
	# blob? Can you remove it and keep just the wheat please". The mound is
	# a ROOT crop's own ground -- its root grows inside it, and pulling one
	# leaves the crater ProceduralSoilSprite's DISTURBED state draws -- but
	# under a field of bending wheat it is just a dark circle, six of them
	# in a 3x2 bed. Keyed on the crop rather than removed outright, so the
	# crops the mound was drawn for keep it.
	#
	# Against what the bed was SOWN with, not plot.crop_id: harvesting
	# clears the crop, and a bare mound appearing the moment the wheat came
	# off is the same blob back again.
	_soil.visible = _sown_crop_id != WHEAT_CROP_ID
	if plot.crop_id == WHEAT_CROP_ID:
		_leaves.visible = false
		_redraw_wheat()
		return
	_hide_wheat_blades()
	_leaves.visible = plot.state != "empty"
	if not _leaves.visible:
		return
	var fraction := 1.0
	if plot.state == "growing":
		fraction = clampf(plot.time_growing / plot.growth_time, 0.0, 1.0)
	_leaves.scale = Vector2.ONE * _illustrated.leaf_world_scale(plot.crop_id)
	_leaves.texture = _illustrated.leaf_texture(
		plot.crop_id, IllustratedCropSprite.growth_stage_index(fraction)
	)
	_leaves.modulate = WITHERED_TINT if plot.state == "withered" else Color.WHITE


## Draws a growing/ready/withered wheat crop as several small bending
## blades (see IllustratedWheatPatch) instead of one flat leaf sprite --
## same growth-fraction-picks-the-row logic _redraw's own carrot/potato
## path already uses, reused verbatim rather than restated.
func _redraw_wheat() -> void:
	if plot.state == "empty":
		_hide_wheat_blades()
		return
	var fraction := 1.0
	if plot.state == "growing":
		fraction = clampf(plot.time_growing / plot.growth_time, 0.0, 1.0)
	var row := IllustratedWheatPatch.row_for_growth(fraction)
	var tint := WITHERED_TINT if plot.state == "withered" else Color.WHITE
	var specs := IllustratedWheatPatch.blade_specs_for_seed(plot.seed_value)
	_ensure_wheat_blade_pool(specs.size())
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var column := posmod(spec.seed as int, IllustratedGrassPatch.ATLAS_COLUMNS)
		var blade := _wheat_blades[i]
		var frame := _wheat.frame_texture(_season, row, column)
		blade.texture = frame
		blade.material = IllustratedWheatPatch.material()
		blade.scale = Vector2.ONE * _wheat.blade_world_scale(_season, row, column)
		# Root pinned at this blade's own deterministic offset, growing
		# upward from it -- mirrors IllustratedGrassPatch's own mesh()
		# center_offset invariant (scaling never drifts a root away from
		# its ground position), via Sprite2D's own offset/centered instead
		# of a QuadMesh, since this is one ordinary sprite, not a shared
		# instanced quad.
		blade.centered = false
		if frame != null:
			blade.offset = Vector2(-frame.get_width() * 0.5, -frame.get_height())
		blade.position = spec.offset as Vector2
		blade.modulate = tint
		blade.visible = true
	for i in range(specs.size(), _wheat_blades.size()):
		_wheat_blades[i].visible = false


func _ensure_wheat_blade_pool(count: int) -> void:
	while _wheat_blades.size() < count:
		var blade := Sprite2D.new()
		add_child(blade)
		_wheat_blades.append(blade)


func _hide_wheat_blades() -> void:
	for blade in _wheat_blades:
		blade.visible = false
