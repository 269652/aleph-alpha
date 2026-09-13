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

## Wilted tint applied to a withered plot's leaves -- desaturated and
## darkened, a "read as dead/neglected at a glance" signal distinct from a
## healthy plot's identity WHITE, so a player can tell a plot died without
## having to inspect it.
const WITHERED_TINT := Color(0.55, 0.5, 0.38)

var plot := FarmPlot.new()

static var _illustrated := IllustratedCropSprite.new()
static var _wheat := IllustratedWheatPatch.new()

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


func _ready() -> void:
	add_to_group(GROUP_NAME)

	_soil = Sprite2D.new()
	_soil.texture = ProceduralSoilSprite.new().generate_texture(false)
	_soil.scale = Vector2.ONE * ProceduralSoilSprite.SOIL_WORLD_SCALE
	add_child(_soil)

	_leaves = Sprite2D.new()
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


func _redraw() -> void:
	if _leaves == null:
		return  # not _ready() yet
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
