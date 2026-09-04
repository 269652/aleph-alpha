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


# -- a whole seed rain at once -----------------------------------------------
#
# is_clear answers for one seed against plants that already stand. Worldgen has
# the other problem: a whole season's seed rain landing at once, none of it
# standing yet, and no meaningful order to consider it in. Considering it in
# SOME order (a sweep) would make the answer depend on where the sweep started,
# and a chunk generator's sweep starts at its own chunk -- so two chunks would
# disagree about a plant on their shared boundary. `survivors` is therefore
# order-independent: within a neighbourhood, the seed with the most vigour
# takes, and which that is does not depend on who asked.


func _rain(cells: Array, ranks: Array) -> Array:
	var out: Array = []
	for i in cells.size():
		out.append({"cell": cells[i], "rank": ranks[i]})
	return out


func test_a_lone_seed_survives():
	var survivors := FlowerEstablishment.survivors(_rain([Vector2i(4, 4)], [1]))
	assert_eq(survivors.size(), 1)
	assert_eq(survivors[0]["cell"], Vector2i(4, 4))


func test_seed_scattered_wide_apart_all_survives():
	var rain := _rain([Vector2i(0, 0), Vector2i(20, 0), Vector2i(0, 20)], [1, 2, 3])
	assert_eq(FlowerEstablishment.survivors(rain).size(), 3)


## The rule itself: crowded seed thins to one plant, and it is the one with
## the most vigour rather than the one that happened to be listed first.
func test_crowded_seed_thins_to_the_one_with_the_most_vigour():
	var rain := _rain([Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)], [1, 9, 4])
	var survivors := FlowerEstablishment.survivors(rain)
	assert_eq(survivors.size(), 1)
	assert_eq(survivors[0]["cell"], Vector2i(6, 5), "the weakest seed won")


## The property that makes chunks agree at their seams: shuffling the rain
## must not change which seed takes.
func test_the_order_the_rain_is_listed_in_changes_nothing():
	var cells := [Vector2i(0, 0), Vector2i(1, 1), Vector2i(9, 0), Vector2i(10, 1), Vector2i(4, 7)]
	var ranks := [5, 8, 2, 7, 3]
	var forwards: Array = []
	for survivor in FlowerEstablishment.survivors(_rain(cells, ranks)):
		forwards.append(survivor["cell"])
	cells.reverse()
	ranks.reverse()
	var backwards: Array = []
	for survivor in FlowerEstablishment.survivors(_rain(cells, ranks)):
		backwards.append(survivor["cell"])
	# As a SET: reversing the input reverses the output listing, which is
	# fine -- what must not change is WHICH seed took.
	forwards.sort()
	backwards.sort()
	assert_eq(forwards, backwards, "the sweep order decided the meadow")


## Whatever survives must satisfy the gate the rest of this module enforces --
## the two halves cannot disagree about how far apart plants stand.
func test_nothing_that_survives_stands_too_close_to_anything_else():
	var rain: Array = []
	for i in 400:
		rain.append({"cell": Vector2i(i % 20, i / 20), "rank": (i * 37) % 401})
	var survivors := FlowerEstablishment.survivors(rain)
	assert_gt(survivors.size(), 0, "a 20x20 downpour rooted nothing at all")
	for a in survivors:
		for b in survivors:
			if a["cell"] == b["cell"]:
				continue
			assert_gte(
				Vector2(a["cell"] - b["cell"]).length(), FlowerEstablishment.MIN_SPACING_TILES,
				"%s and %s both survived" % [a["cell"], b["cell"]]
			)


## Two seeds of identical vigour in the same neighbourhood must not BOTH take
## just because nothing separates them -- the tie has to break somewhere.
func test_a_dead_heat_still_produces_one_plant():
	var rain := _rain([Vector2i(5, 5), Vector2i(6, 5)], [7, 7])
	assert_eq(FlowerEstablishment.survivors(rain).size(), 1)


## Negative coordinates are the ordinary case, not an edge case: the world is
## centred on the origin and half of it has negative tiles. Bucketing by
## integer division (truncating toward zero) would fold the two cells either
## side of the origin into one bucket.
func test_it_works_on_negative_ground_too():
	var rain := _rain([Vector2i(-40, -40), Vector2i(-41, -40), Vector2i(-60, -60)], [1, 5, 3])
	var survivors := FlowerEstablishment.survivors(rain)
	assert_eq(survivors.size(), 2)


func test_no_rain_roots_nothing():
	assert_eq(FlowerEstablishment.survivors([]).size(), 0)
