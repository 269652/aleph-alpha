extends Node2D

## The builder you see on a construction site (docs/concept/building.md,
## "Somebody is working on it"). Asked for directly, watching a village
## raise a cottage: *"the construction site should show a builder working
## on it"*.
##
## Deliberately NOT the NpcMarker schedule stack -- the same choice, for
## the same reason, FarmerMarker and LumberjackMarker make: a small,
## purpose-built walker whose whole job is one plot. He paces the site,
## stops to work a spell, and moves on, and he never steps off the
## footprint, because the site IS the job. EarthChunkManager spawns exactly
## one per site that is really being worked and frees him with it (see
## _sync_construction_worker), so a worker can never outlive the thing he
## is working on.
##
## He is a face on a number, not decoration: a settlement spends real spare
## hands on its projects (SettlementSpareCapacity scaled by settlement_
## productivity, charged against the project's required hours by
## ConstructionCatchup), and a site accruing no labour has no worker
## standing over it.

const ProceduralBuilderSprite = preload("res://src/rendering/procedural_builder_sprite.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const GROUP_NAME := "construction_worker"

## How long he works one spot before moving to the next. Long enough to
## read as working rather than pacing: a builder crossing a 2x2 plot at
## WALK_SPEED takes about two seconds, so a dwell of the same order means
## roughly half his time is spent with the mallet down.
const WORK_SECONDS := 2.0

## World units per second. A working pace on a building site, well under
## the villagers' own walking speed -- he is carrying something heavy and
## has nowhere to be.
const WALK_SPEED := 9.0

## The plot he works, in world space -- the site's own footprint rect. An
## empty one means no site was given to him, and he simply stands.
var plot: Rect2 = Rect2()

## Which spots on that plot he picks, and in which order -- the site's own
## seed, so one builder works one site the same way on every reload.
var seed_value: int = 0

var _target := Vector2.ZERO
var _working := 0.0
var _picks := 0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = ProceduralBuilderSprite.new().generate_texture()
	add_child(sprite)
	_target = _pick_spot()


func _process(delta: float) -> void:
	if plot.size == Vector2.ZERO:
		return
	if _working > 0.0:
		_working -= delta
		return
	var toward := _target - position
	var step := WALK_SPEED * delta
	if toward.length() <= step:
		position = _target
		_working = WORK_SECONDS
		_target = _pick_spot()
		return
	position += toward.normalized() * step


## The next spot on the plot he works, drawn from the site's own seed
## through two independent salts -- one index split across both axes walks
## a diagonal of the plot instead of covering it, the same trap
## BuildingCatalog.variant_cell_for names.
func _pick_spot() -> Vector2:
	if plot.size == Vector2.ZERO:
		return position
	_picks += 1
	var across := float(PixelNoise.range_index(seed_value, _picks, 11, 1000)) / 999.0
	var down := float(PixelNoise.range_index(seed_value, _picks, 29, 1000)) / 999.0
	return plot.position + Vector2(plot.size.x * across, plot.size.y * down)
