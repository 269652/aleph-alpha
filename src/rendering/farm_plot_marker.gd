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

const GROUP_NAME := "farm_plot"

## Wilted tint applied to a withered plot's leaves -- desaturated and
## darkened, a "read as dead/neglected at a glance" signal distinct from a
## healthy plot's identity WHITE, so a player can tell a plot died without
## having to inspect it.
const WITHERED_TINT := Color(0.55, 0.5, 0.38)

var plot := FarmPlot.new()

static var _illustrated := IllustratedCropSprite.new()

var _soil: Sprite2D
var _leaves: Sprite2D


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
## separately remember to redraw after advancing.
func advance(delta: float) -> void:
	plot.advance(delta)
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


func _redraw() -> void:
	if _leaves == null:
		return  # not _ready() yet
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
