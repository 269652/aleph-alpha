extends GutTest

## Does a real villager's field really grow and get harvested, against the
## REAL EarthChunkManager?
##
## Reported in play, with the beds in shot: *"The Farmhouse NPC seems to be
## planting things but it's not wheat and nothing grows and nothing gets
## harvested. There are some purple flowers which disappear again after a few
## seconds"*.
##
## Every existing test of this loop drives a STUB world
## (test_npc_marker_farming.gd's StubFarmWorld), and all of them pass. This
## drives the real till/water/harvest hooks and the real step_farm_plots
## cadence instead, with a chunk injected directly rather than generated --
## the same cheap shape test_earth_chunk_manager_clear_vegetation.gd uses.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const Chunk = preload("res://src/world/chunk.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const StepCadence = preload("res://src/gameplay/step_cadence.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const CHUNK := Vector2i(0, 0)
const TILE_SIZE := TerrainRenderer.TILE_SIZE
const FARMHOUSE := Vector2i(10, 10)

## A real 3x2 bed set, the shape a farmstead really encloses.
const BEDS: Array[Vector2i] = [
	Vector2i(9, 12), Vector2i(10, 12), Vector2i(11, 12),
	Vector2i(9, 13), Vector2i(10, 13), Vector2i(11, 13),
]


class AllWorkPlanner:
	extends NpcPlanner.Planner
	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		var out: Array = []
		for block in ["morning", "midday", "evening", "night"]:
			out.append({"time_block": block, "location_tag": "field", "activity": "work"})
		return out


var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var farmer: NpcMarker
var market: VillageMarket


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager._loaded_chunks[CHUNK] = Chunk.new()

	market = VillageMarket.new()
	farmer = NpcMarker.new()
	farmer.identity = NpcIdentity.new(11, "farmer")
	farmer.home_position = _centre(FARMHOUSE)
	farmer.workspot_position = _centre(BEDS[0])
	farmer.landmarks = {"field": _centre(BEDS[0]), "well": _centre(FARMHOUSE)}
	farmer.position = _centre(BEDS[0])
	farmer.set_planner(AllWorkPlanner.new())
	farmer.setup(manager, TILE_SIZE)
	farmer.setup_economy(market)
	farmer.field_cells = BEDS.duplicate()
	farmer.stock_building_cell = FARMHOUSE
	add_child(farmer)


func after_each():
	remove_child(farmer)
	farmer.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


static func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(TILE_SIZE)


## Ticks the villager every frame and the farm plots on the REAL cadence the
## world runs them at (StepCadence.INTERVAL_SECONDS), rather than in lockstep
## with the villager the way a stub does.
func _run(seconds: float, slice := 0.1) -> void:
	var elapsed := 0.0
	var since_plots := 0.0
	while elapsed < seconds:
		farmer._process(slice)
		since_plots += slice
		if since_plots >= StepCadence.INTERVAL_SECONDS:
			manager.step_farm_plots(since_plots)
			since_plots = 0.0
		elapsed += slice


func _shelf(item_id: String) -> int:
	return manager.structure_stock_at(FARMHOUSE.x, FARMHOUSE.y, item_id)


func _states() -> Dictionary:
	var counts: Dictionary = {}
	for cell in BEDS:
		var plot = manager.farm_plot_at_global(cell.x, cell.y)
		var state: String = "none" if plot == null else plot.state
		counts[state] = int(counts.get(state, 0)) + 1
	return counts


# -- it really plants ------------------------------------------------------

func test_a_farmer_really_tills_and_plants_the_real_beds():
	_run(120.0)
	var planted := 0
	for cell in BEDS:
		if manager.farm_plot_at_global(cell.x, cell.y) != null:
			planted += 1
	assert_gt(planted, 0, "the beds were never worked at all")


## And plants WHEAT -- the crop their trade grows, not whatever was lying
## around. Reported: *"it's not wheat"*.
func test_what_a_farmer_plants_in_a_real_bed_is_wheat():
	_run(120.0)
	for cell in BEDS:
		var plot = manager.farm_plot_at_global(cell.x, cell.y)
		if plot != null and plot.crop_id != "":
			assert_eq(plot.crop_id, VillageFarm.crop_for("farmer"), "at %s" % str(cell))


# -- and it really ripens and comes in --------------------------------------

## The whole report in one assertion: *"nothing grows and nothing gets
## harvested"*. A farmhouse whose shelf never sees a grain is decoration.
func test_a_real_field_really_puts_wheat_on_the_farmhouse_shelf():
	farmer.warehouse_position = _centre(Vector2i(20, 20))  # this village has a store
	var peak := 0
	for i in 9000:  # fifteen real minutes, the work block the yield is measured over
		farmer._process(0.1)
		if i % 3 == 0:
			manager.step_farm_plots(0.3)
		peak = maxi(peak, _shelf(VillageFarm.crop_for("farmer")))
	assert_gt(peak, 0, "the field never yielded a single grain: %s" % str(_states()))


## And the beds are not simply dying: a field that withers faster than its
## farmer can walk it is a field that never ripens.
func test_a_real_field_does_not_just_wither():
	_run(300.0)
	var counts := _states()
	assert_lt(
		int(counts.get("withered", 0)), BEDS.size(),
		"every bed in the field is dead: %s" % str(counts)
	)
