extends GutTest

## VillagePond: the fisher's own 3x2 water, dug where the farmer's field is
## sown (see docs/concept/village_ponds.md). Asked for directly: "The Fisher
## should build a similar 3x2 enclosure but filled with water and a pond with
## river water physics and fish swimming in it which reproduce".
##
## These pin the SAMENESS as hard as the pond itself: a pond that sited or
## fenced itself by its own rule would drift away from the field it is
## modelled on, and "similar" is the whole of the ask.

const VillagePond = preload("res://src/gameplay/village_pond.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const HOUSE := "house_small"

var _anywhere := func(_cell: Vector2i) -> bool: return true


## A pond is still sited by the FIELD's own search and the field's own
## shapes -- "similar" is the whole of the ask, and a pond that invented its
## own rule would drift away from the thing it is modelled on.
##
## It differs in exactly one way, and deliberately: a pond may be dug
## BEHIND the house. A farmhouse refuses ground north of itself because
## that is the next row of buildings; a fisher's house fronts the street to
## the south, so behind it is the only ground of their own they have.
## Measured at the first grassland village with a fisher, every free cell on
## their own side of the street was north of the house -- so a search that
## could only look south had nowhere to go but across the road, which is
## exactly what was reported ("it's randomly placed somewhere not adjacent
## to the fishers house or across the street").
func test_a_pond_is_sited_by_the_fields_own_rule_but_may_lie_behind_the_house():
	var origin := Vector2i(6, 4)
	assert_eq(
		VillagePond.pond_rect(origin, HOUSE, _anywhere),
		VillageFarm.field_rect(origin, HOUSE, _anywhere, true),
		"a pond sites itself by the field's rule, with the ground behind opened up"
	)
	assert_true(
		VillageFarm.FIELD_SHAPES.has((VillagePond.pond_rect(origin, HOUSE, _anywhere) as Rect2i).size),
		"and still takes one of the field's own shapes"
	)


## The difference is real, not incidental: on open ground the pond takes
## ground the field would have refused.
func test_a_field_still_refuses_the_ground_behind_the_house():
	var origin := Vector2i(6, 4)
	var field = VillageFarm.field_rect(origin, HOUSE, _anywhere)
	assert_not_null(field)
	assert_gte(
		(field as Rect2i).position.y, origin.y,
		"a farmhouse never sows north of itself -- that is the next row of buildings"
	)


func test_a_pond_is_six_cells_in_one_of_the_shapes_that_was_asked_for():
	var rect = VillagePond.pond_rect(Vector2i(6, 4), HOUSE, _anywhere)
	assert_not_null(rect, "open ground has room for a pond")
	assert_true(VillageFarm.FIELD_SHAPES.has((rect as Rect2i).size), "3x2 or 2x3, as asked")
	assert_eq(VillagePond.pond_cells(Vector2i(6, 4), HOUSE, _anywhere).size(), 6)


func test_ground_with_no_room_gets_no_pond():
	var nowhere := func(_cell: Vector2i) -> bool: return false
	assert_null(VillagePond.pond_rect(Vector2i(6, 4), HOUSE, nowhere))
	assert_eq(VillagePond.pond_cells(Vector2i(6, 4), HOUSE, nowhere), [])


## The frame is the farm's frame, rails and all -- same ring, same facings,
## same corner posts.
func test_a_pond_is_fenced_exactly_the_way_a_field_is():
	var origin := Vector2i(6, 4)
	var cells := VillagePond.pond_cells(origin, HOUSE, _anywhere)
	assert_eq(
		VillagePond.fence_cells(origin, HOUSE, _anywhere),
		VillageFarm.fence_cells(cells, origin, HOUSE),
		"a pond's frame must be the field's frame"
	)


func test_the_water_has_a_tile_id_of_its_own():
	assert_ne(VillagePond.POND_TILE_ID, "", "built water has to persist as something")
	assert_true(VillagePond.is_pond_tile(VillagePond.POND_TILE_ID))
	assert_false(VillagePond.is_pond_tile(""))
	assert_false(VillagePond.is_pond_tile("farm_fence_north"))
	assert_false(
		VillageFarm.is_fence_tile(VillagePond.POND_TILE_ID),
		"water is not a rail -- it replaces the ground rather than standing on it"
	)


# -- fish that live there, and go on living there --------------------------
#
# "...and fish swimming in it which reproduce". A pond stocked once and
# fished flat is a bucket; a pond whose fish breed toward what the water can
# feed is a fishery (docs/concept/village_ponds.md).
#
# The population model is the world's OWN aquatic one, not a second one: a
# pond is a small body of water, and fish in it breed for the same reasons
# and at the same rate as fish anywhere else.

const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")

const MILD := 0.55  # AquaticPopulationModel.OPTIMAL_TEMPERATURE


func test_a_ponds_ceiling_is_the_worlds_own_aquatic_one_for_that_much_water():
	var cells := 6
	assert_almost_eq(
		VillagePond.carrying_capacity(cells, MILD),
		AquaticPopulationModel.new().carrying_capacity(float(cells), MILD),
		0.0001,
		"a pond with a ceiling of its own is a second model to keep in step"
	)


func test_more_water_feeds_more_fish():
	assert_gt(
		VillagePond.carrying_capacity(6, MILD), VillagePond.carrying_capacity(4, MILD),
		"a bigger pond has to feed more"
	)


## Cold or hot water feeds fewer, exactly as open water does.
func test_water_a_fish_cannot_thrive_in_feeds_fewer():
	assert_lt(VillagePond.carrying_capacity(6, 0.05), VillagePond.carrying_capacity(6, MILD))


## A pond is STOCKED, not spontaneous: nothing swims in water nobody put
## fish into, however good the water is.
func test_an_unstocked_pond_never_grows_fish_from_nothing():
	var population := VillagePond.step(0.0, 6, MILD, 30.0)
	assert_almost_eq(population, 0.0, 0.0001, "fish appeared in water nobody stocked")


func test_a_stocked_pond_breeds_toward_what_its_water_can_feed():
	var ceiling := VillagePond.carrying_capacity(6, MILD)
	var population := float(VillagePond.STOCKING_FISH)
	assert_lt(population, ceiling, "precondition: a stocking is below the ceiling")
	for _day in 40:
		population = VillagePond.step(population, 6, MILD, 1.0)
	assert_gt(population, float(VillagePond.STOCKING_FISH), "the stock never bred")
	assert_lte(population, ceiling + 0.0001, "a pond cannot feed more than its water can")


## And it does not overshoot: a pond already at its ceiling stays there.
func test_a_full_pond_stays_full():
	var ceiling := VillagePond.carrying_capacity(6, MILD)
	assert_almost_eq(VillagePond.step(ceiling, 6, MILD, 10.0), ceiling, 0.0001)


## Two is the smallest stocking that can breed at all -- one fish is a pet.
func test_a_stocking_is_enough_fish_to_breed():
	assert_gte(VillagePond.STOCKING_FISH, 2, "one fish cannot reproduce")


# -- a dug pond is water you can actually get into ---------------------------
#
# Reported live: "there's no real pond with river / lake water physics".
# A pond answered is_water_at_global (so nothing builds or grows on it) but
# carried no DEPTH, and the player's own water state is the maximum of
# ocean, river and lake depth -- three sources a pond is not one of. So a
# fisher's pond was water everything avoided and nobody could wade into.

const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")


## A pond dug to keep fish is dug deep enough for them to overwinter in --
## the standard temperate figure, and the reason a village pond is a real
## hole rather than a puddle. Pinned against the wade threshold rather than
## asserted as a number: what matters about the depth is that a pond reads
## as water to swim in, not a puddle to walk through.
func test_a_pond_is_deeper_than_a_person_can_wade():
	assert_gt(
		VillagePond.DEPTH_METERS, WaterMovementModel.WADE_DEPTH_METERS,
		"a fisher's pond that can be walked across is not a pond"
	)


## And not absurdly deep either -- it is a dug village pond, not a quarry.
func test_a_pond_is_a_dug_pond_not_a_quarry():
	assert_lt(VillagePond.DEPTH_METERS, 3.0)


# -- the hut on the bank ---------------------------------------------------
#
# Reported live with a screenshot of a dug, fenced, EMPTY enclosure: "it's
# missing a fisher hut (use farmhouse sprite until illustration exists)".
# A farmer's beds have a farmhouse standing over them; a fisher's water had
# nothing at all, which is the half of "the same shape as a field" that was
# never built.


func _pond_at(top_left: Vector2i, size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(top_left.y, top_left.y + size.y):
		for x in range(top_left.x, top_left.x + size.x):
			cells.append(Vector2i(x, y))
	return cells


func _hut_cells(origin: Vector2i) -> Array:
	return BuildingCatalog.footprint_cells(VillagePond.HUT_BUILDING_ID, origin)


func test_a_hut_stands_on_the_bank_of_its_own_water():
	var water := _pond_at(Vector2i(8, 8), Vector2i(3, 2))

	var origin = VillagePond.hut_origin(water, _anywhere)

	assert_not_null(origin, "open ground round a pond must put a hut somewhere")
	var nearest := 9999.0
	for cell in _hut_cells(origin):
		for wet in water:
			nearest = minf(nearest, Vector2(cell as Vector2i).distance_to(Vector2(wet as Vector2i)))
	assert_lte(nearest, float(VillagePond.HUT_BANK_REACH_TILES), "a fisher's hut stands at their own water")


## It is a hut BESIDE the water, never a hut IN it -- the pond is dug
## ground nothing may be built on (is_buildable_ground_at refuses it), and
## a hut standing in the pond would be a building in a lake.
func test_a_hut_never_stands_in_the_water_it_fishes():
	var water := _pond_at(Vector2i(8, 8), Vector2i(3, 2))
	var origin = VillagePond.hut_origin(water, _anywhere)
	for cell in _hut_cells(origin):
		assert_false(water.has(cell), "%s is in the pond" % cell)


## Ground nothing fits on gets no hut, honestly -- the same answer a pond
## with no room gives, rather than a hut squeezed onto water or rails.
func test_no_room_means_no_hut():
	var water := _pond_at(Vector2i(8, 8), Vector2i(3, 2))
	assert_null(VillagePond.hut_origin(water, func(_cell: Vector2i) -> bool: return false))


func test_no_water_means_no_hut():
	assert_null(VillagePond.hut_origin([], _anywhere))


## Deterministic, like every other siting in this module: the same water
## puts the hut in the same place on every reload, or a village grows a
## second hut every time it is walked past.
func test_the_same_water_always_puts_the_hut_in_the_same_place():
	var water := _pond_at(Vector2i(8, 8), Vector2i(3, 2))
	assert_eq(VillagePond.hut_origin(water, _anywhere), VillagePond.hut_origin(water, _anywhere))


## The hut is a real building, and the same size as the farmhouse it is
## drawn as until its own art lands -- so what stands over a pond reads at
## the same scale as what stands over a field.
func test_a_fisher_hut_is_a_real_building_the_size_of_a_farmhouse():
	assert_true(BuildingCatalog.has_building(VillagePond.HUT_BUILDING_ID))
	assert_eq(
		BuildingCatalog.footprint_of(VillagePond.HUT_BUILDING_ID),
		BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	)
	assert_eq(BuildingCatalog.capacity_of(VillagePond.HUT_BUILDING_ID), 0, "nobody lives in a work hut")


# -- the shape of the water itself -----------------------------------------
#
# Reported live with a screenshot: "The built pond renders as earth instead
# of water". Two separate faults, and this is the second: once the surface
# was painted at all, a 3x2 pond still read as a small blue puddle in a
# brown rectangle -- measured on a real render at 10.4% of the pond's own
# area (tools/probe_fisher_pond_render.gd).
#
# Water rides one overlay, and where its edge falls is decided by an ACROSS
# field: |across| < 1 is water, 1 is the waterline, and the shader
# reconstructs it by interpolating between cell centres. The pond wrote
# 0.75 on its own cells and nothing at all round them, so the field ran
# from 0.75 straight up to whatever the nearest river left there -- tens of
# tiles' worth -- and crossed 1 a few pixels past each cell's own centre.
# Hence a puddle.


## The waterline is a CONTOUR, so the only number that matters is where it
## lands: half a tile out from a water cell's centre is that cell's own
## edge, which is the edge of the pond.
func test_a_ponds_waterline_lands_on_its_own_edge():
	assert_almost_eq(
		VillagePond.waterline_offset_tiles(), 0.5, 0.0001,
		"a dug pond is water right up to the hole's own edge, not a puddle in the middle of it"
	)


## And it is water all the way in: a dug pond is a flat-bottomed hole, not
## a channel with a deep line down the middle.
func test_a_ponds_own_water_is_open_water_everywhere_inside_that_edge():
	assert_almost_eq(VillagePond.WATER_ACROSS, 0.0, 0.0001)


## The manager's surface pass must use THESE numbers -- a model nothing
## reads is a comment. Source-contract, the same shape
## test_earth_chunk_manager_footprints.gd uses.
func test_the_water_surface_pass_paints_a_pond_from_this_model():
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	assert_true(
		source.contains("VillagePond.WATER_ACROSS"),
		"the pond's own cells must carry the model's own across value"
	)
	assert_true(
		source.contains("VillagePond.BANK_ACROSS"),
		"and the ring round it must carry the bank that puts the waterline on its edge"
	)


# -- a pond is dug where its works can stand -------------------------------
#
# Reported live, standing at the water: *"no Fisher Hut is near"*. Measured
# on three real streamed villages (tools/probe_village_geometry.gd): one of
# them had a pond with NO hut anywhere, and the reason was not a near miss
# -- all 51 candidate origins within HUT_BANK_REACH_TILES of that water
# were refused, 19 by the village street, 21 by neighbouring houses, 5 by
# the pond's own fence rail and 6 by the water itself. The pond had been
# dug into the two-row strip between the street and the next house row,
# which is exactly wide enough for the water and nothing else.
#
# Two passes that never spoke: the dig takes the best rectangle in reach,
# and the hut is sited afterwards on whatever bank that leaves. A pond with
# nowhere to put its works is a pond that should have been dug elsewhere --
# the same rule VillageLayout already applies to a farmhouse, which refuses
# a plot with no room for its field.


## The ground as it WILL BE, not as it is: a candidate hut site is judged
## against the pond dug and FENCED, because the rails go in with the water
## and a site that overlaps one is a site the hut cannot have.
##
## The fixture is the whole point. The only clear ground within reach of
## this water is the three rows under it, and the nearest of those three
## is the pond's own southern rail line -- so the question asked at
## PLACEMENT time (where the rails are already real ground the caller's
## own is_free refuses) and the question asked BEFORE the dig have to give
## different answers, or the dig would choose a site whose only bank is
## the fence it is about to build.
func test_a_bank_that_only_the_fence_would_block_is_not_a_bank():
	var water := _pond_at(Vector2i(8, 8), Vector2i(3, 2))
	var rails := VillageFarm.fence_cells(water, Vector2i(8, 13), HOUSE)
	assert_false(rails.is_empty(), "precondition: this pond really is fenced")
	var under_the_water := func(cell: Vector2i) -> bool:
		return cell.x >= 7 and cell.x <= 11 and cell.y >= 10 and cell.y <= 12

	assert_not_null(
		VillagePond.hut_origin(water, under_the_water),
		"precondition: the placement-time question puts a hut on this ground"
	)
	assert_null(
		VillagePond.hut_origin_after_fencing(water, Vector2i(8, 13), HOUSE, under_the_water),
		"...and that ground is the pond's own rail line, so before the dig it is no bank at all"
	)


## And open ground still does -- the fencing test must not refuse a bank
## that is genuinely clear.
func test_open_ground_round_a_pond_still_takes_a_hut_once_it_is_fenced():
	var water := _pond_at(Vector2i(8, 8), Vector2i(3, 2))
	var origin = VillagePond.hut_origin_after_fencing(water, Vector2i(8, 11), HOUSE, _anywhere)
	assert_not_null(origin, "open ground round a pond must still put a hut somewhere")
	for cell in _hut_cells(origin):
		assert_false(
			VillageFarm.fence_cells(water, Vector2i(8, 11), HOUSE).has(cell),
			"%s is one of the pond's own rails" % cell
		)


## A strip of ground exactly as deep as the water itself takes a pond but
## no works. Given a wider site as well, the dig must take the wider one.
func test_a_pond_is_dug_where_its_hut_can_stand():
	var house := Vector2i(8, 12)
	# Two tiles deep immediately behind the house -- room for the water and
	# nothing else, which is the real village layout this was measured in
	# (the strip between the street and the next house row). And open
	# ground one row further out, wide enough for both. Both inside
	# VillageFarm.FIELD_REACH_TILES of the house, or the search would never
	# see the second.
	var strip := func(cell: Vector2i) -> bool:
		if cell.y >= 10 and cell.y <= 11:
			return cell.x >= 6 and cell.x <= 12
		return cell.x >= 5 and cell.x <= 13 and cell.y >= 5 and cell.y <= 9

	var takes_a_hut := func(cells: Array) -> bool:
		return VillagePond.bank_takes_a_hut(cells, house, HOUSE, strip)
	var water: Array = VillagePond.pond_cells(house, HOUSE, strip, takes_a_hut)

	assert_false(water.is_empty(), "there is room for a pond here")
	assert_not_null(
		VillagePond.hut_origin_after_fencing(water, house, HOUSE, strip),
		"the pond was dug on ground its own works cannot stand beside: %s" % str(water)
	)


## ...and the strip alone still gets its water. A pond with no hut beats no
## pond at all: the fisher works the water, not the building.
func test_ground_that_can_never_take_a_hut_still_gets_its_pond():
	var house := Vector2i(8, 12)
	var strip := func(cell: Vector2i) -> bool:
		return cell.y >= 10 and cell.y <= 11 and cell.x >= 6 and cell.x <= 12

	var takes_a_hut := func(cells: Array) -> bool:
		return VillagePond.bank_takes_a_hut(cells, house, HOUSE, strip)
	assert_true(
		VillagePond.pond_cells(house, HOUSE, strip, takes_a_hut).is_empty(),
		"precondition: nowhere on this strip can take a hut"
	)
	assert_false(
		VillagePond.pond_cells(house, HOUSE, strip).is_empty(),
		"and without the condition there is still a pond to dig"
	)


## The condition is the caller's, exactly like VillageLayout's own
## accepts_origin -- passing none leaves the search it has always done.
func test_a_dig_with_no_condition_sites_the_pond_exactly_as_before():
	var house := Vector2i(6, 4)
	assert_eq(
		VillagePond.pond_rect(house, HOUSE, _anywhere, Callable()),
		VillagePond.pond_rect(house, HOUSE, _anywhere)
	)
	assert_eq(
		VillagePond.pond_rect(house, HOUSE, _anywhere),
		VillageFarm.field_rect(house, HOUSE, _anywhere, true)
	)
