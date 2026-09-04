extends GutTest

## FlowerEstablishment: which seed actually becomes a plant (see
## concept/flora.md#how-far-apart-flowers-stand-escape-from-the-parent).
##
## Reported live: flowers "spread or grow way too dense... the seeds should be
## carried a bit further by the wind and birds so it leaves more space between
## individual flowers". The fix is NOT to flatten WindDispersal's heavy tail --
## that tail is real, and a uniform scatter would be a cosmetic mechanism
## replacing a true one. Where seed LANDS and where a plant STANDS are two
## different distributions: seed rain is densest directly under the parent and
## survival there is close to nil (Janzen-Connell). This module is that second
## distribution, and it is the only thing in the flower code that decides how
## far apart two plants may stand.

const FlowerEstablishment = preload("res://src/world/flower_establishment.gd")


# -- the gate itself ---------------------------------------------------------

func test_a_cell_with_nothing_near_it_takes_a_seed():
	assert_true(FlowerEstablishment.is_clear(Vector2i(10, 10), [Vector2i(40, 40)]))


func test_open_ground_takes_a_seed():
	assert_true(FlowerEstablishment.is_clear(Vector2i(3, 4), []))


## The whole point: a seed landing at an established plant's foot does not
## become a second plant there.
func test_a_seed_at_an_established_plants_foot_does_not_take():
	assert_false(FlowerEstablishment.is_clear(Vector2i(5, 5), [Vector2i(5, 5)]))


func test_a_seed_beside_an_established_plant_does_not_take():
	assert_false(FlowerEstablishment.is_clear(Vector2i(6, 5), [Vector2i(5, 5)]))


## Diagonals count. A gate that only looked along the axes would leave flowers
## standing corner to corner, which on screen is the same wall of blooms the
## report was about.
func test_a_seed_diagonally_beside_an_established_plant_does_not_take():
	assert_false(FlowerEstablishment.is_clear(Vector2i(6, 6), [Vector2i(5, 5)]))


## Real distance, not a bounding box: a square gate would refuse a cell
## further away in a corner than one it accepts along an axis.
func test_the_gate_measures_real_distance_rather_than_a_square():
	var spacing := 3.0
	# (3, 3) is 4.24 tiles away -- outside a 3-tile circle, inside a 3-tile box.
	assert_true(FlowerEstablishment.is_clear(Vector2i(3, 3), [Vector2i(0, 0)], spacing))
	# (3, 0) is exactly 3 -- the spacing is a MINIMUM, so exactly at it is fine.
	assert_true(FlowerEstablishment.is_clear(Vector2i(3, 0), [Vector2i(0, 0)], spacing))
	assert_false(FlowerEstablishment.is_clear(Vector2i(2, 0), [Vector2i(0, 0)], spacing))


## One plant anywhere in the neighbourhood is enough to refuse -- the gate is
## an ALL check, not a nearest-few sample.
func test_any_one_neighbour_is_enough_to_refuse():
	var crowd := [Vector2i(50, 50), Vector2i(5, 5), Vector2i(90, 2)]
	assert_false(FlowerEstablishment.is_clear(Vector2i(5, 6), crowd))


## FlowerPatch holds its flowers as a cell -> species Dictionary and
## MeadowSpread accumulates a plain Array; both must read identically rather
## than each growing its own copy of this rule.
func test_a_dictionary_of_plants_reads_the_same_as_a_list():
	var as_list := [Vector2i(5, 5)]
	var as_dict := {Vector2i(5, 5): "rose"}
	for cell in [Vector2i(5, 6), Vector2i(20, 20), Vector2i(5, 5)]:
		assert_eq(
			FlowerEstablishment.is_clear(cell, as_list),
			FlowerEstablishment.is_clear(cell, as_dict),
			"the two shapes disagreed about %s" % cell
		)


# -- the spacing constant ----------------------------------------------------

## Pinned as a property rather than as a number: whatever the constant is
## tuned to, it has to be wide enough that no two flowers can ever stand in
## touching cells -- side by side OR corner to corner. That is the smallest
## claim the report ("more space between individual flowers") actually makes.
func test_the_default_spacing_never_lets_two_flowers_touch():
	assert_gt(
		FlowerEstablishment.MIN_SPACING_TILES, sqrt(2.0),
		"flowers could still stand corner to corner"
	)


## And bounded above: a gate wide enough to thin a meadow to a handful of
## plants would starve the pollinator circuit, which needs a LOCAL density of
## blooms to work (see concept/flora.md#trap-lining). The rule opens gaps
## between individuals; it must not empty the meadow.
func test_the_default_spacing_still_allows_a_meadow_rather_than_a_scattering():
	assert_lt(
		FlowerEstablishment.MIN_SPACING_TILES, 5.0,
		"this spacing would leave too few blooms in forage range to work a circuit"
	)


func test_the_spacing_is_measured_in_tiles_not_pixels():
	# A pixel-valued constant would sail through both bounds above while
	# meaning something ~16x smaller. Cheapest guard: it is a small number.
	assert_lt(FlowerEstablishment.MIN_SPACING_TILES, 16.0)


# -- the indexed form --------------------------------------------------------
#
# MeadowSpread tests thousands of landings per chunk load, so it cannot afford
# is_clear's walk over every plant placed so far. The indexed form buckets
# plants by spacing so only the neighbouring buckets are looked at -- but it
# has to be the SAME RULE, not a second one that drifts.

func test_an_empty_index_takes_anything():
	assert_true(FlowerEstablishment.index_is_clear(Vector2i(7, 7), FlowerEstablishment.new_index()))


func test_the_index_refuses_a_cell_beside_a_plant_it_holds():
	var index := FlowerEstablishment.new_index()
	FlowerEstablishment.index_add(Vector2i(5, 5), index)
	assert_false(FlowerEstablishment.index_is_clear(Vector2i(6, 5), index))
	assert_true(FlowerEstablishment.index_is_clear(Vector2i(25, 25), index))


## The guard that keeps the fast path honest: over a crowd of plants and a
## sweep of query cells, the bucketed answer must equal the plain one
## everywhere. A bucketing bug shows up as a plant slipping through at a
## bucket boundary, which is exactly the case a hand-picked example misses.
func test_the_indexed_form_answers_exactly_what_the_plain_form_does():
	var plants: Array = []
	var index := FlowerEstablishment.new_index()
	for i in 60:
		var cell := Vector2i((i * 7) % 31 - 15, (i * 13) % 29 - 14)
		plants.append(cell)
		FlowerEstablishment.index_add(cell, index)
	var disagreements := 0
	for y in range(-18, 19):
		for x in range(-18, 19):
			var cell := Vector2i(x, y)
			if (
				FlowerEstablishment.index_is_clear(cell, index)
				!= FlowerEstablishment.is_clear(cell, plants)
			):
				disagreements += 1
	assert_eq(disagreements, 0, "the fast path is not the same rule as the slow one")


## Negative coordinates are the ordinary case, not an edge case: the world is
## centred on the origin and half of it has negative tiles. Integer division
## truncating toward zero would fold -0.5 and +0.5 into the same bucket.
func test_the_index_works_on_negative_ground_too():
	var index := FlowerEstablishment.new_index()
	FlowerEstablishment.index_add(Vector2i(-40, -40), index)
	assert_false(FlowerEstablishment.index_is_clear(Vector2i(-41, -40), index))
	assert_true(FlowerEstablishment.index_is_clear(Vector2i(-60, -60), index))
