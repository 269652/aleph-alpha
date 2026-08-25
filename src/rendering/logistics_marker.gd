extends Node2D

## The Logistics worker (see docs/concept/timber_construction.md's "Storage,
## logistics, and the autonomous dependency chain" section): walks to a
## production structure carrying real waiting output, collects it, carries
## it to the nearest Storage, and deposits it -- repeat. Deliberately NOT
## built on NpcMarker/CreatureMarker, mirroring DecomposerMarker's own
## reasoning: a narrow, single-purpose autonomous actor doesn't need the
## full sense/perceive/act stack. Mirrors DecomposerMarker's
## match-on-behavior-phase engine-glue split directly -- this owns WHERE the
## nearest source/storage are (via EarthChunkManager) and WHAT is being
## carried; LogisticsBehavior only decides WHEN each leg completes.
##
## `item_id`/`source_structure_id` are injected rather than hardcoded to one
## producer: no real accumulating-output production building (the doc
## section's own "Sägewerk-equivalent") exists yet in this codebase to name
## a fixed default for (see that section's own honesty note) -- a caller
## assigns a worker to whichever source structure id and item it's meant to
## haul, exactly as it would need to once a real producer exists.

const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const LogisticsBehavior = preload("res://src/gameplay/logistics_behavior.gd")

const GROUP_NAME := "logistics_worker"

const WALK_SPEED := 28.0
const ARRIVE_DISTANCE_PX := 4.0

## How many units of `item_id` a single trip carries -- a real hand-cart-load
## cap, not "however much the source has": the same "a worker's trip is
## bounded" reasoning DecomposerMarker's own single-bite-at-a-time feeding
## already models, scaled up from a bite to a cart load.
const CARRY_CAPACITY := 4

## Which structure id this worker collects FROM, and which item it hauls --
## the caller's job to set before the worker starts (see class doc comment).
var source_structure_id := ""
var item_id := ""
var storage_structure_id := "storage"
var search_radius_tiles := 20

## Late-bound world reference, the same pattern other markers use for their
## EarthChunkManager access (e.g. AmbientFlyerMarker's own worm/flower
## lookups) -- set by whatever spawns this marker.
var earth = null

var carried_item_id := ""
var carried_count := 0

var _behavior := LogisticsBehavior.new()
var _source_target_position := Vector2.ZERO
var _storage_target_position := Vector2.ZERO


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	# A hand-cart has no dedicated art yet -- reusing Storage's own tile art
	# at marker scale is a placeholder (a dedicated worker sprite is a
	# follow-up, not this pass's scope; see this doc section's own status
	# note), not a claim that this IS a storage building.
	sprite.texture = ProceduralStructureSprite.new().generate_texture("storage")
	sprite.scale = Vector2.ONE * 0.5
	add_child(sprite)


func _process(delta: float) -> void:
	match _behavior.phase:
		LogisticsBehavior.Phase.SEEKING:
			_step_seeking(delta)
		LogisticsBehavior.Phase.APPROACHING:
			_step_approaching(delta)
		LogisticsBehavior.Phase.COLLECTING:
			_step_collecting(delta)
		LogisticsBehavior.Phase.CARRYING:
			_step_carrying(delta)
		LogisticsBehavior.Phase.DEPOSITING:
			_step_depositing(delta)


func _step_seeking(delta: float) -> void:
	_behavior.advance(delta)  # no-op outside timed phases, just ticks the coordination-pause clock
	if not _behavior.can_commit():
		return
	if earth == null or source_structure_id == "" or item_id == "":
		return
	var found = earth.nearest_structure_position(
		position, source_structure_id, float(search_radius_tiles) * TerrainRenderer.TILE_SIZE
	)
	if found == null:
		return
	_source_target_position = found
	_behavior.begin_approach()


func _step_approaching(delta: float) -> void:
	var to_target: Vector2 = _source_target_position - position
	if to_target.length() <= ARRIVE_DISTANCE_PX:
		_behavior.arrive_at_source()
		return
	position += to_target.normalized() * WALK_SPEED * delta


func _step_collecting(delta: float) -> void:
	var outcome := _behavior.advance(delta)
	if outcome == LogisticsBehavior.Outcome.COLLECTED:
		_collect_from_source()


## Withdraws up to CARRY_CAPACITY of `item_id` from the source's real stock,
## then locates the nearest Storage to carry it to. If the source turned out
## to have nothing waiting after all (another worker beat this one to it), or
## no Storage can be found, this aborts back to SEEKING -- and, for the
## no-storage case, puts back what it withdrew rather than silently
## destroying real stock.
func _collect_from_source() -> void:
	var source_tile := _tile_for(_source_target_position)
	var available: int = earth.structure_stock_at(source_tile.x, source_tile.y, item_id)
	var amount: int = mini(available, CARRY_CAPACITY)
	if amount <= 0:
		_behavior.abort()
		return
	earth.withdraw_from_structure_at(source_tile.x, source_tile.y, item_id, amount)
	var storage_position = earth.nearest_structure_position(
		position, storage_structure_id, float(search_radius_tiles) * TerrainRenderer.TILE_SIZE
	)
	if storage_position == null:
		earth.deposit_to_structure_at(source_tile.x, source_tile.y, item_id, amount)  # put it back
		_behavior.abort()
		return
	carried_item_id = item_id
	carried_count = amount
	_storage_target_position = storage_position


func _step_carrying(delta: float) -> void:
	if carried_count <= 0:
		_behavior.abort()
		return
	var to_target: Vector2 = _storage_target_position - position
	if to_target.length() <= ARRIVE_DISTANCE_PX:
		_behavior.arrive_at_storage()
		return
	position += to_target.normalized() * WALK_SPEED * delta


func _step_depositing(delta: float) -> void:
	var outcome := _behavior.advance(delta)
	if outcome == LogisticsBehavior.Outcome.DEPOSITED:
		_deposit_into_storage()


func _deposit_into_storage() -> void:
	if earth != null and carried_count > 0:
		var storage_tile := _tile_for(_storage_target_position)
		earth.deposit_to_structure_at(storage_tile.x, storage_tile.y, carried_item_id, carried_count)
	carried_item_id = ""
	carried_count = 0


## Recovers the global tile coordinate a tile-center pixel position
## (nearest_structure_position's own return shape) came from.
func _tile_for(tile_center_pixel: Vector2) -> Vector2i:
	return Vector2i(
		floori(tile_center_pixel.x / TerrainRenderer.TILE_SIZE), floori(tile_center_pixel.y / TerrainRenderer.TILE_SIZE)
	)
