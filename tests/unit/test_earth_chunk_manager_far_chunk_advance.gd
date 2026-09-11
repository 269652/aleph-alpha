extends GutTest

## EarthChunkManager's far-chunk advance gate for leaf litter and footprints
## (FPS regression round 11, docs/concept/soil_fauna.md; docs/concept/
## leaf_litter.md "Cost"). step_leaf_litter and step_footprints used to
## advance EVERY loaded chunk's field every frame -- 30 chunks, of which
## only the 9 inside decoration range can be seen -- measured live at ~8 ms
## (litter) + ~2-4 ms (prints) per frame, fps-independent. A chunk outside
## decoration range now advances its field only once per
## FAR_CHUNK_ADVANCE_SECONDS of accumulated time, handing over everything it
## accumulated (no time is ever lost), and flushes whatever is pending the
## moment it comes back into range, so a returning player never sees litter
## frozen mid-drift.
##
## Fields are injected directly (test_earth_chunk_manager.gd's own "poke
## internal state" convention, see its _field_at helper) -- no real chunk
## load, so this file stays fast. Deltas are 0.25 s throughout because four
## of them sum to exactly 1.0 in binary, so the interval math is exact.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")
const FootprintField = preload("res://src/world/footprint_field.gd")

const STEP := 0.25
const NEAR := Vector2i(10, 10)  # the decoration centre itself
const FAR := Vector2i(20, 10)   # ten chunks out: never inside a radius of 1


class _CountingLitter extends LeafLitterField:
	var advances := 0
	var advanced_by := 0.0
	func advance(delta: float, now: float) -> void:
		advances += 1
		advanced_by += delta
		super.advance(delta, now)


class _CountingPrints extends FootprintField:
	var advances := 0
	func advance(now: float) -> void:
		advances += 1
		super.advance(now)


var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	manager._decoration_center = NEAR
	manager._decoration_radius = 1


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _litter_at(chunk_coord: Vector2i) -> _CountingLitter:
	var field := _CountingLitter.new()
	manager._leaf_litter_fields[chunk_coord] = field
	return field


func _prints_at(chunk_coord: Vector2i) -> _CountingPrints:
	var field := _CountingPrints.new()
	manager._footprint_fields[chunk_coord] = field
	return field


func _step_prints(times: int) -> void:
	for i in times:
		manager.advance_world_age(STEP)
		manager.step_footprints()


func test_the_far_advance_interval_is_pinned():
	assert_eq(EarthChunkManager.FAR_CHUNK_ADVANCE_SECONDS, 1.0)


# -- leaf litter -------------------------------------------------------------


func test_a_decorating_chunks_litter_still_advances_every_frame():
	var near := _litter_at(NEAR)
	for i in 8:
		manager.step_leaf_litter(STEP)
	assert_eq(near.advances, 8, "inside decoration range: every frame, exactly as before")
	assert_almost_eq(near.advanced_by, 2.0, 0.0001)


func test_a_far_chunks_litter_advances_once_per_interval_and_loses_no_time():
	var far := _litter_at(FAR)
	for i in 8:
		manager.step_leaf_litter(STEP)  # two seconds
	assert_eq(far.advances, 2, "once per FAR_CHUNK_ADVANCE_SECONDS, not once per frame")
	assert_almost_eq(far.advanced_by, 2.0, 0.0001, "everything it accumulated was handed over")


func test_a_far_chunk_flushes_its_pending_time_the_moment_it_comes_back_into_range():
	var far := _litter_at(FAR)
	for i in 2:
		manager.step_leaf_litter(STEP)  # half a second pending, nothing advanced yet
	assert_eq(far.advances, 0, "precondition: still waiting out its interval")
	manager._decoration_center = FAR
	manager.step_leaf_litter(STEP)
	assert_eq(far.advances, 1, "back in range: advanced on that very frame")
	assert_almost_eq(far.advanced_by, 0.75, 0.0001, "the pending half second plus this frame -- nothing lost")


# -- footprints --------------------------------------------------------------


func test_a_decorating_chunks_prints_still_advance_every_frame():
	var near := _prints_at(NEAR)
	_step_prints(8)
	assert_eq(near.advances, 8)


func test_a_far_chunks_prints_advance_once_per_interval():
	var far := _prints_at(FAR)
	_step_prints(8)  # two seconds of world age
	assert_eq(far.advances, 2, "once per FAR_CHUNK_ADVANCE_SECONDS of world age -- lossless, advance() takes an absolute clock")


func test_a_far_chunks_prints_advance_the_moment_it_comes_back_into_range():
	var far := _prints_at(FAR)
	_step_prints(1)  # first sight of it: advanced once, then waiting
	assert_eq(far.advances, 1, "precondition")
	_step_prints(1)
	assert_eq(far.advances, 1, "precondition: waiting out its interval")
	manager._decoration_center = FAR
	_step_prints(1)
	assert_eq(far.advances, 2, "back in range: advanced on that very frame")
