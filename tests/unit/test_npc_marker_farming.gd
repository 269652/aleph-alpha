extends GutTest

## A villager who actually farms (docs/concept/village_farms.md).
##
## Reported in play: "The village needs a farmer which grows wheat like in
## Anno ... similar to a farmer the herbalist should build a farm house and
## plant herbs ... the farmer / herbalist goes to work regularly". Before
## this, the village farmer walked to a decorative "field" prop, stood on
## it, and fruit appeared in the market -- no ground was tilled and nothing
## grew. The same three-part split the hunter already uses applies here:
## FarmerBehavior decides WHEN, VillageFarm decides WHAT, and NpcMarker owns
## the world effect against the SAME FarmPlot lifecycle a player's own
## hand-tilled plot uses.
##
## The regional-aggregate drip stays underneath as the fallback for a
## villager with no farmhouse -- so these tests check both: that a farmer
## with a real field works it and is paid for what it yields, and that one
## without a field earns from the region exactly as before.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")

const TILE_SIZE := 16

## Home is the origin and the decorative workspot sits at +x, so "walked out
## to the field" is unambiguous: the field lies at -x, and only a villager
## who genuinely left their prop behind ends up there.
const HOME := Vector2.ZERO
const WORKSPOT := Vector2(160.0, 0.0)
const FIELD_TILES: Array[Vector2i] = [Vector2i(-10, 0), Vector2i(-10, 1), Vector2i(-9, 0)]


class AllWorkPlanner:
	extends NpcPlanner.Planner
	var activity := "work"

	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		return [
			{"time_block": "morning", "location_tag": "field", "activity": activity},
			{"time_block": "midday", "location_tag": "field", "activity": activity},
			{"time_block": "evening", "location_tag": "field", "activity": activity},
			{"time_block": "night", "location_tag": "field", "activity": activity},
		]


## Exactly the farm contract EarthChunkManager exposes, backed by real
## FarmPlot objects so the tests exercise the real plant/water/harvest
## lifecycle rather than a mock of it.
class StubFarmWorld:
	var biome := "grassland"
	var plots: Dictionary = {}  # Vector2i -> FarmPlot
	var refuse_planting := false
	var plant_calls := 0
	var water_calls := 0
	var harvest_calls := 0

	func biome_at_global(_x: int, _y: int) -> String:
		return biome

	func vegetation_density_near(_pos: Vector2) -> float:
		return 0.6

	func herbivore_population_near(_pos: Vector2) -> float:
		return 0.0

	func fish_population_near(_pos: Vector2) -> float:
		return 0.0

	func farm_plot_at_global(x: int, y: int):
		return plots.get(Vector2i(x, y))

	func till_and_plant_farm_plot_at_global(x: int, y: int, crop_id: String) -> bool:
		if refuse_planting:
			return false
		var tile := Vector2i(x, y)
		var plot: FarmPlot = plots.get(tile)
		if plot == null:
			plot = FarmPlot.new()
			plots[tile] = plot
		if plot.state == "growing" or plot.state == "ready":
			return false
		plot.plant(crop_id, hash(tile))
		plant_calls += 1
		return true

	func water_farm_plot_at_global(x: int, y: int) -> bool:
		var plot: FarmPlot = plots.get(Vector2i(x, y))
		if plot == null or plot.state != "growing":
			return false
		plot.water()
		water_calls += 1
		return true

	func harvest_farm_plot_at_global(x: int, y: int) -> Dictionary:
		var plot: FarmPlot = plots.get(Vector2i(x, y))
		if plot == null:
			return {"crop_id": "", "count": 0}
		var result := plot.harvest()
		if int(result.get("count", 0)) > 0:
			harvest_calls += 1
		return result

	func advance_plots(delta: float) -> void:
		for plot in plots.values():
			plot.advance(delta)


var marker: NpcMarker
var market: VillageMarket
var world: StubFarmWorld
var planner: AllWorkPlanner


func before_each():
	market = VillageMarket.new()
	world = StubFarmWorld.new()
	planner = AllWorkPlanner.new()
	marker = _build_marker("farmer")


func after_each():
	remove_child(marker)
	marker.free()


func _build_marker(occupation: String) -> NpcMarker:
	var built := NpcMarker.new()
	built.identity = NpcIdentity.new(1)
	built.identity.occupation = occupation
	built.home_position = HOME
	built.workspot_position = WORKSPOT
	built.landmarks = {"well": WORKSPOT, "stall": WORKSPOT, "gate": WORKSPOT}
	built.position = HOME
	built.set_planner(planner)
	built.setup(world, TILE_SIZE)
	built.setup_economy(market)
	add_child(built)
	return built


func _give_a_field() -> void:
	marker.field_cells = FIELD_TILES.duplicate()


func _centre_of(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * TILE_SIZE, (tile.y + 0.5) * TILE_SIZE)


## Real seconds of simulation in frame-sized slices, advancing the crops the
## same way the world clock does.
func _run(seconds: float, slice := 0.1) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		marker._process(slice)
		world.advance_plots(slice)
		elapsed += slice


## Runs until every field tile holds a real plot, then stops.
func _run_until_planted(limit := 120.0, slice := 0.1) -> bool:
	var elapsed := 0.0
	while elapsed < limit:
		marker._process(slice)
		world.advance_plots(slice)
		elapsed += slice
		if world.plots.size() >= FIELD_TILES.size():
			return true
	return false


# -- the villager goes out to the field ------------------------------------

func test_a_farmer_with_a_field_walks_out_to_it_not_to_their_prop():
	_give_a_field()
	_run(6.0)
	assert_lt(marker.position.x, 0.0, "the field lies west; the decorative workspot lies east")


func test_a_farmer_with_no_field_keeps_walking_to_their_workspot():
	_run(6.0)
	assert_gt(marker.position.x, 0.0, "with no farmhouse there is nothing to walk out to")


func test_a_villager_who_does_not_farm_ignores_a_field_entirely():
	remove_child(marker)
	marker.free()
	marker = _build_marker("guard")
	_give_a_field()
	_run(6.0)
	assert_eq(world.plots.size(), 0, "a guard handed a field still does not farm it")
	assert_gt(marker.position.x, 0.0)


# -- and really works it ---------------------------------------------------

func test_a_farmer_tills_and_plants_every_tile_of_their_own_field():
	_give_a_field()
	assert_true(_run_until_planted(), "the farmer never planted the whole field")
	for tile in FIELD_TILES:
		var plot: FarmPlot = world.plots.get(tile)
		assert_not_null(plot, "%s was never tilled" % str(tile))
		assert_eq(plot.crop_id, "wheat", "a farmer grows wheat")


func test_a_herbalist_plants_herbs_on_theirs():
	remove_child(marker)
	marker.free()
	marker = _build_marker("herbalist")
	_give_a_field()
	assert_true(_run_until_planted(), "the herbalist never planted the whole field")
	for tile in FIELD_TILES:
		assert_eq((world.plots[tile] as FarmPlot).crop_id, "herb")


func test_a_ready_crop_is_harvested_into_the_village_market():
	_give_a_field()
	assert_true(_run_until_planted())
	var before: float = market.stock.get("wheat", 0.0)
	# Every plot ripe at once: the field is now pure harvest work.
	for plot in world.plots.values():
		plot.state = "ready"
	_run(30.0)
	assert_gt(
		market.stock.get("wheat", 0.0), before,
		"a real harvest must reach the village's own market, not vanish"
	)


func test_a_real_harvest_pays_the_villager_who_made_it():
	_give_a_field()
	assert_true(_run_until_planted())
	var before: int = marker.economy.wallet.balance
	for plot in world.plots.values():
		plot.state = "ready"
	_run(30.0)
	assert_gt(marker.economy.wallet.balance, before, "work that produced something real is paid")


func test_a_growing_crop_is_watered_before_it_withers():
	_give_a_field()
	assert_true(_run_until_planted())
	# Long enough that an untended plot would be well past its own grace
	# window (FarmPlot.WATER_GRACE_FRACTION of a 20-60s growth time).
	_run(90.0)
	var withered := 0
	for plot in world.plots.values():
		if plot.state == "withered":
			withered += 1
	assert_lt(
		withered, FIELD_TILES.size(),
		"a farmer standing in the field must keep at least some of it alive"
	)


func test_off_the_clock_the_field_is_left_alone():
	planner.activity = "sleep"
	_give_a_field()
	_run(20.0)
	assert_eq(world.plots.size(), 0, "a villager asleep is not out tilling")


# -- and stops being paid twice for the same day ---------------------------

func test_a_farmer_on_a_real_field_stops_drawing_the_regional_drip():
	_give_a_field()
	# Long enough that the drip would really have credited whole units by
	# now -- NpcProduction.PRODUCTION_RATE_PER_SECOND against this stub's
	# own vegetation density needs tens of seconds to reach one FOOD_UNIT,
	# so a short run would pass this vacuously.
	_run(120.0)
	assert_eq(
		market.stock.get("fruit", 0.0), 0.0,
		"real field work replaces the ambient number, exactly as a real hunt does"
	)


func test_a_farmer_with_no_field_still_earns_from_the_region():
	_run(120.0)
	assert_gt(
		market.stock.get("fruit", 0.0), 0.0,
		"the regional fallback is what a village with no farmhouse still lives on"
	)


# -- one trip waters the beds around it -------------------------------------
#
# A field capped at ten tiles (asked for directly) is more ground than a
# villager can walk in one wither grace: a circuit of ten costs about ten
# times FarmerBehavior.WORK_SECONDS plus the walking, against a grace of
# half a 20-60s growth time. Measured at zero wheat per work block before
# this rule existed.
#
# The rule is not a bigger number, it is what a farmer actually does: you
# water a BED, and the water runs to the beds beside it. One trip with a
# can, or along a furrow, wets the ground around where you are standing --
# it does not wet one plant.

func test_tending_a_bed_waters_the_beds_beside_it():
	_give_a_field()
	assert_true(_run_until_planted())
	# Everything thirsty but still alive, so the next real action is a
	# watering trip rather than a replant.
	for plot in world.plots.values():
		# Past the watering margin, but with real headroom before the
		# wither point -- a withered bed cannot be watered at all, which
		# would measure the wrong thing.
		plot.time_since_watered = plot.growth_time * FarmPlot.WATER_GRACE_FRACTION * 0.6
	var before: Array = []
	for tile in FIELD_TILES:
		before.append((world.plots[tile] as FarmPlot).time_since_watered)
	_run(8.0)
	var refreshed := 0
	for i in FIELD_TILES.size():
		if (world.plots[FIELD_TILES[i]] as FarmPlot).time_since_watered < float(before[i]):
			refreshed += 1
	assert_gt(
		refreshed, 1,
		"one trip must refresh more than the single bed the farmer is kneeling on"
	)


func test_the_water_does_not_run_across_the_whole_field():
	marker.field_cells = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 0)]
	for cell in marker.field_cells:
		world.till_and_plant_farm_plot_at_global(cell.x, cell.y, "wheat")
	for plot in world.plots.values():
		plot.time_since_watered = 5.0
	marker._water_the_beds_around(Vector2i(0, 0))
	assert_eq(
		(world.plots[Vector2i(1, 0)] as FarmPlot).time_since_watered, 0.0,
		"the bed beside the one being worked gets wet"
	)
	assert_eq(
		(world.plots[Vector2i(5, 0)] as FarmPlot).time_since_watered, 5.0,
		"the bed across the field does not -- a farmer waters where they stand"
	)


# -- how much ground one villager can actually keep -------------------------
#
# MEASURED, not asserted (CLAUDE.md: tuned values are tested functions or
# test-pinned constants). Over one real work block
# (ChunkEcologyCatchup.SECONDS_PER_DAY / NpcSchedule.TIME_BLOCKS.size() =
# 900s), wheat harvested against field size:
#
#     3 cells -> 170     8 cells -> 215
#     4 cells -> 208    10 cells -> 215
#     6 cells -> 225    14 cells -> 215
#
# Two things that curve shows. A ten-tile field -- the size asked for --
# really does produce, at about eight times the ambient drip it replaces.
# And the yield SATURATES around six to eight: past that the farmer cannot
# walk further in the time the crop gives them, so the extra tiles are
# ground they never reach. The cap is the limit that was asked for; the
# saturation is the reason a village grows its output by raising a second
# farmhouse rather than a bigger field.
#
# It took two real fixes to get here, both found by measuring rather than
# reading. Watering used to come LAST in the priority, so a farmer with any
# bare bed planted instead of saving a dying one; and with nothing past its
# threshold the farmer stood still. A three-tile field ran 108 replants, 72
# waterings and ZERO harvests that way.

const WORK_BLOCK_SECONDS := 900.0


## `size` tiles in a row -- the worst real case for a walking circuit, and
## deliberately so: the ring around a 3x2 farmhouse is more compact than a
## line, so a cap measured on a line is conservative for a real field.
func _field_of(size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in size:
		cells.append(Vector2i(-10 + i, 0))
	return cells


func _wheat_off_a_field(size: int) -> float:
	remove_child(marker)
	marker.free()
	market = VillageMarket.new()
	world = StubFarmWorld.new()
	marker = _build_marker("farmer")
	marker.field_cells = _field_of(size)
	_run(WORK_BLOCK_SECONDS, 0.1)
	return market.stock.get("wheat", 0.0)


func test_a_field_of_the_capped_size_really_produces_over_a_work_block():
	assert_gt(
		_wheat_off_a_field(VillageFarm.MAX_WORKED_CELLS), 0.0,
		"the cap has to be a size that actually yields, or a farmhouse is decoration"
	)


## The cap is a design limit that was asked for (first "capped to 10
## tiles", then the shape inside it: "a 2x3 or 3x2 area"), not a measured
## cliff any more -- watering the beds around the one being
## worked is what removed the cliff. What still has to be measured is that
## a field of that size is worth having: a farmhouse must beat the ambient
## regional drip its villager would otherwise have lived on, or it is
## decoration.
func test_a_capped_field_is_worth_more_than_the_drip_it_replaces():
	var NpcProduction = load("res://src/world/npc_production.gd")
	var harvested := _wheat_off_a_field(VillageFarm.MAX_WORKED_CELLS)
	var dripped: float = (
		float(NpcProduction.PRODUCTION_RATE_PER_SECOND) * 0.6 * WORK_BLOCK_SECONDS
	)
	assert_gt(
		harvested, dripped,
		"a real field must out-earn the number it replaces, or nobody should build one"
	)


func test_the_cap_is_exactly_the_field_a_farmhouse_is_sited_for():
	for shape in VillageFarm.FIELD_SHAPES:
		assert_eq(
			(shape as Vector2i).x * (shape as Vector2i).y, VillageFarm.MAX_WORKED_CELLS,
			"a farmhouse raised for ground it may not then work would be a contradiction"
		)



# -- a farmer is never dragged off their own field --------------------------
#
# Reported in play: "No crops (wheat) grow and get harvested.. it plants then
# nothing happens it worked before". Caused by the needs layer
# (docs/concept/npc_social_life.md): _step_farm returns null BETWEEN actions
# -- while seeking, and during the re-commit pause -- and in exactly those
# frames the villager read as free, so thirst (which crosses its threshold
# every ~16s) walked them to the well. They planted, left, and the bed
# withered before they came back.


func test_a_farmer_between_two_beds_is_still_at_work():
	_give_a_field()
	marker.economy.needs.set_level("thirst", 1.0)
	# Mid-job but with nothing to walk to this instant: exactly the frame
	# that used to read as idle.
	marker._step_farm(0.1, true)
	assert_true(marker.is_on_real_work(), "a farmer working a field is at work every frame of it")
	assert_null(
		marker._step_needs(0.1, not marker.is_on_real_work()),
		"and is not sent to the well from the middle of their own field"
	)


## The regression itself, end to end: a thirsty farmer with a real field
## keeps working it instead of walking away. The well is deliberately in the
## opposite direction from the field, so "walked off" is unambiguous.
func test_a_thirsty_farmer_keeps_farming():
	_give_a_field()
	marker.landmarks = {"well": HOME + Vector2(600, 0), "stall": WORKSPOT, "gate": WORKSPOT}
	marker.economy.needs.set_level("thirst", 1.0)
	_run(12.0)
	assert_gt(
		marker.position.distance_to(marker.landmarks["well"]), 400.0,
		"a thirsty farmer with a field to work does not walk off to the well"
	)
	assert_gt(world.plots.size(), 0, "and really got beds planted while they were at it")
