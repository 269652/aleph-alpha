extends Node2D

## The Farm's Farmer -- "an NPC moves in" per LumberjackMarker's own
## framing (see docs/concept/npc_farm_production.md). Deliberately NOT the
## full NpcMarker/CreatureMarker AI stack (daily schedules, roaming-wildlife
## sense/perceive/act), the same reasoning LumberjackMarker/DecomposerMarker
## already give for the same choice. One FarmerMarker per placed Farm (see
## EarthChunkManager's _farm_farmers wiring).
##
## Owns PLOT_COUNT real FarmPlotMarker children (the SAME plant/water/
## harvest logic and art a player's own hand-tilled plot already uses) at
## fixed offsets around `home`. Every owned plot's growth advances every
## frame regardless of the Farmer's own current phase -- the Farm's crops
## keep growing whether or not the Farmer is currently standing there,
## mirroring SagewerkProduction's own "the building's production is
## independent of its worker's phase" pillar.
##
## SEEKING (pick whichever owned plot needs attention most: a ready plot to
## harvest, an empty/withered plot to till-and-plant wheat, or a growing
## plot at real risk of withering to re-water -- see _next_action_plot_index)
## -> APPROACHING (walk to it) -> WORKING (a timed dwell; on completion,
## perform that plot's action) -> back to SEEKING. A harvest credits the
## Farm's own real StructureStock at its home tile directly -- unlike
## LumberjackMarker's felled log, a farm plot never needs a separate
## CARRYING leg back to a distant worksite; the plot already IS part of the
## Farm.

const FarmerBehavior = preload("res://src/gameplay/farmer_behavior.gd")
const FarmPlotMarker = preload("res://src/rendering/farm_plot_marker.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ProceduralLumberjackSprite = preload("res://src/rendering/procedural_lumberjack_sprite.gd")

const GROUP_NAME := "farmer"

## A real, if arbitrary, cap on how much one Farmer can tend before
## something occasionally risks withering -- see docs/concept/
## npc_farm_production.md's own Open Questions.
const PLOT_COUNT := 3

## Real farmhouse kitchen-garden row spacing -- close enough that a
## Farmer's walk between adjacent plots is a few real steps, not a trek.
const PLOT_SPACING_PX := 20.0

const WALK_SPEED := 26.0
const ARRIVE_DISTANCE_PX := 4.0

## What this Farm grows (docs/concept/npc_farm_production.md).
const CROP_ID := "wheat"

## Re-water a growing plot once it's used up this much of its own real
## wither grace window (FarmPlot.WATER_GRACE_FRACTION) -- real margin
## before the actual wither point, grounded in a real farmer checking crops
## on a walking circuit and watering ahead of visible wilting, not only
## once a plant has already started to droop.
const WATER_BEFORE_WITHER_FRACTION := 0.5

## Where this Farmer's Farm stands -- both its plots' anchor and where
## harvested wheat credits the Farm's own StructureStock (see
## _perform_action).
var home := Vector2.ZERO

## Late-bound world reference, the same pattern LumberjackMarker/
## LogisticsMarker already use for their own EarthChunkManager access.
var earth = null

var _behavior := FarmerBehavior.new()
var _plots: Array[FarmPlotMarker] = []
var _target_index := -1
var _next_seed_value := 0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = ProceduralLumberjackSprite.new().generate_texture()
	add_child(sprite)
	for i in PLOT_COUNT:
		var plot_marker := FarmPlotMarker.new()
		plot_marker.position = _plot_offset(i)
		add_child(plot_marker)
		_plots.append(plot_marker)


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	return "Farmer"


## No player-facing interaction -- an autonomous worker, not something you
## click on to command (mirrors LumberjackMarker not offering any either).
func get_hover_actions() -> Array:
	return []


func _plot_offset(index: int) -> Vector2:
	return Vector2((float(index) - float(PLOT_COUNT - 1) / 2.0) * PLOT_SPACING_PX, PLOT_SPACING_PX)


func _process(delta: float) -> void:
	for plot_marker in _plots:
		plot_marker.advance(delta)
	match _behavior.phase:
		FarmerBehavior.Phase.SEEKING:
			_step_seeking(delta)
		FarmerBehavior.Phase.APPROACHING:
			_step_approaching(delta)
		FarmerBehavior.Phase.WORKING:
			_step_working(delta)


func _step_seeking(delta: float) -> void:
	_behavior.advance(delta)  # no-op outside WORKING, just ticks the re-commit clock
	if not _behavior.can_commit():
		return
	var index := _next_action_plot_index()
	if index == -1:
		return
	_target_index = index
	_behavior.begin_approach()


func _step_approaching(delta: float) -> void:
	var target_position: Vector2 = home + _plot_offset(_target_index)
	var to_target: Vector2 = target_position - position
	if to_target.length() <= ARRIVE_DISTANCE_PX:
		_behavior.arrive()
		return
	position += to_target.normalized() * WALK_SPEED * delta


func _step_working(delta: float) -> void:
	if not _behavior.advance(delta):
		return
	_perform_action(_target_index)
	_target_index = -1
	_behavior.finish_work()


func _perform_action(index: int) -> void:
	var plot_marker := _plots[index]
	match _action_kind_for(plot_marker):
		"harvest":
			var result: Dictionary = plot_marker.harvest()
			var count: int = result.get("count", 0)
			if count > 0 and earth != null:
				var home_tile := _tile_for(home)
				earth.deposit_to_structure_at(home_tile.x, home_tile.y, result["crop_id"], count)
		"plant":
			_next_seed_value += 1
			var seed_value := hash("%s_%d" % [str(home), _next_seed_value])
			plot_marker.till_and_plant(CROP_ID, seed_value)
		"water":
			plot_marker.water()


## Priority: a ready plot (harvest -- get real value off the field) beats
## an empty/withered plot (plant -- start the next cycle) beats a growing
## plot at real risk of withering (water it) -- -1 if no owned plot needs
## any action right now.
func _next_action_plot_index() -> int:
	for i in _plots.size():
		if _action_kind_for(_plots[i]) == "harvest":
			return i
	for i in _plots.size():
		if _action_kind_for(_plots[i]) == "plant":
			return i
	for i in _plots.size():
		if _action_kind_for(_plots[i]) == "water":
			return i
	return -1


func _action_kind_for(plot_marker: FarmPlotMarker) -> String:
	var plot: FarmPlot = plot_marker.plot
	if plot.state == "ready":
		return "harvest"
	if plot.state == "empty" or plot.state == "withered":
		return "plant"
	if (
		plot.state == "growing"
		and plot.time_since_watered >= plot.growth_time * FarmPlot.WATER_GRACE_FRACTION * WATER_BEFORE_WITHER_FRACTION
	):
		return "water"
	return ""


func _tile_for(pixel_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(pixel_position.x / TerrainRenderer.TILE_SIZE), floori(pixel_position.y / TerrainRenderer.TILE_SIZE)
	)
