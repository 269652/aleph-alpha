extends GutTest

## Per-chunk solitary/wild bee nest population -- see docs/concept/
## bees.md's "Wild bee nests" section. Deliberately a MUCH lighter
## system than BeeColony: no queen, no worker caste, no shared colony,
## no honey, no swarming -- real solitary bees are genuinely solitary,
## each female provisioning her own few brood cells in her own hole with
## no economy to speak of. Mirrors EarthwormPatch's own lightweight
## per-chunk fixed-site shape, not AntColony/BeeColony's heavier one.

const WildBeePatch = preload("res://src/world/wild_bee_patch.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")

const WIDTH := 16
const HEIGHT := 16


func _all_grassland() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for i in biome.size():
		biome[i] = "grassland"
	return biome


func _all_desert() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for i in biome.size():
		biome[i] = "desert"
	return biome


func _patch_with_one_nest() -> WildBeePatch:
	for seed_value in range(1, 200):
		var patch := WildBeePatch.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		if patch.nest_cells().size() > 0:
			return patch
	fail_test("no seed in [1, 200) placed a single nest")
	return null


# -- placement / seeding -----------------------------------------------------

func test_seeds_at_least_one_nest_across_a_reasonable_search_of_seeds():
	assert_gt(_patch_with_one_nest().nest_cells().size(), 0)


func test_never_seeds_a_nest_on_a_biome_with_no_trees():
	var patch := WildBeePatch.new(1, WIDTH, HEIGHT, _all_desert())
	assert_eq(patch.nest_cells().size(), 0)


func test_placement_is_deterministic_for_the_same_seed():
	var a := WildBeePatch.new(42, WIDTH, HEIGHT, _all_grassland())
	var b := WildBeePatch.new(42, WIDTH, HEIGHT, _all_grassland())
	assert_eq(a.nest_cells(), b.nest_cells())


func test_never_exceeds_the_hard_per_chunk_cap():
	for seed_value in range(20):
		var patch := WildBeePatch.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		assert_lte(patch.nest_cells().size(), WildBeePatch.MAX_NESTS)


## Real solitary-bee nest density is considerably HIGHER than a single
## honeybee colony's own hive density (many individual females each
## working her own hole, rather than one shared superorganism per
## territory) -- an ordering, not an eyeballed number.
func test_nests_are_denser_than_honeybee_hives():
	assert_gt(WildBeePatch.NEST_CHANCE, BeeColony.HIVE_CHANCE)


func test_has_nest_is_true_only_for_a_real_seeded_cell():
	var patch := _patch_with_one_nest()
	for cell in patch.nest_cells():
		assert_true(patch.has_nest(cell))
	assert_false(patch.has_nest(Vector2i(-1, -1)))


# -- residents: a real, if very simple, "more bees over time" signal -------

func test_a_freshly_seeded_nest_starts_with_one_resident():
	var patch := _patch_with_one_nest()
	for cell in patch.nest_cells():
		assert_almost_eq(patch.residents_at(cell), 1.0, 0.01)


func test_residents_at_an_unrelated_cell_reads_the_starting_default():
	var patch := _patch_with_one_nest()
	assert_almost_eq(patch.residents_at(Vector2i(-5, -5)), 1.0, 0.01)


func test_record_forage_result_moves_the_recent_success_signal_up_on_success():
	var patch := _patch_with_one_nest()
	var cell: Vector2i = patch.nest_cells()[0]
	for i in 10:
		patch.record_forage_result(cell, true)
	assert_gt(patch.forage_success_at(cell), 0.5)


func test_residents_grow_slowly_under_sustained_real_forage_success():
	var patch := _patch_with_one_nest()
	var cell: Vector2i = patch.nest_cells()[0]
	for i in 400:
		patch.record_forage_result(cell, true)
		patch.advance(WildBeePatch.SECONDS_PER_SIMULATED_DAY)
	assert_gt(patch.residents_at(cell), 1.0, "sustained real forage success should grow the nest")


func test_residents_never_exceed_the_per_nest_cap():
	var patch := _patch_with_one_nest()
	var cell: Vector2i = patch.nest_cells()[0]
	for i in 4000:
		patch.record_forage_result(cell, true)
		patch.advance(WildBeePatch.SECONDS_PER_SIMULATED_DAY)
	assert_lte(patch.residents_at(cell), WildBeePatch.MAX_RESIDENTS_PER_NEST)


func test_residents_never_grow_without_any_real_forage_success():
	var patch := _patch_with_one_nest()
	var cell: Vector2i = patch.nest_cells()[0]
	for i in 400:
		patch.advance(WildBeePatch.SECONDS_PER_SIMULATED_DAY)
	assert_almost_eq(patch.residents_at(cell), 1.0, 0.01)


# -- relocation: the one absconding trigger a wild nest keeps ---------------
#
# See docs/concept/bees.md's own "Wild bee nests": no honey, no harvest,
# no swarming, but a nest that has genuinely lost its nearby forage
# still moves on -- the real, if less dramatic, thing a lone female
# would do by simply choosing a different hole.

func test_should_relocate_is_false_for_a_freshly_seeded_nest():
	var patch := _patch_with_one_nest()
	assert_false(patch.should_relocate_at(patch.nest_cells()[0]))


func test_should_relocate_becomes_true_after_sustained_forage_failure():
	var patch := _patch_with_one_nest()
	var cell: Vector2i = patch.nest_cells()[0]
	for i in 100:
		patch.record_forage_result(cell, false)
	assert_true(patch.should_relocate_at(cell))


func test_should_relocate_is_false_at_an_unrelated_cell():
	var patch := _patch_with_one_nest()
	assert_false(patch.should_relocate_at(Vector2i(-9, -9)))


func test_relocate_to_moves_the_resident_count_to_the_new_site():
	var patch := _patch_with_one_nest()
	var from_cell: Vector2i = patch.nest_cells()[0]
	var to_cell := Vector2i(-1, -1)
	for y in HEIGHT:
		for x in WIDTH:
			if not patch.has_nest(Vector2i(x, y)):
				to_cell = Vector2i(x, y)
				break
		if to_cell.x >= 0:
			break
	var residents := patch.residents_at(from_cell)
	patch.relocate_to(from_cell, to_cell)
	assert_false(patch.has_nest(from_cell))
	assert_true(patch.has_nest(to_cell))
	assert_almost_eq(patch.residents_at(to_cell), residents, 0.01)


func test_relocate_to_is_a_no_op_at_an_invalid_destination():
	var patch := _patch_with_one_nest()
	var from_cell: Vector2i = patch.nest_cells()[0]
	patch.relocate_to(from_cell, from_cell)
	assert_true(patch.has_nest(from_cell))


func test_is_valid_nest_site_rejects_an_occupied_cell():
	var patch := _patch_with_one_nest()
	assert_false(patch.is_valid_nest_site(patch.nest_cells()[0]))


func test_is_valid_nest_site_rejects_a_biome_with_no_trees():
	var patch := WildBeePatch.new(1, WIDTH, HEIGHT, _all_desert())
	assert_false(patch.is_valid_nest_site(Vector2i(3, 3)))


func test_should_forage_rolls_both_outcomes_across_many_nests():
	var results := {true: 0, false: 0}
	for seed_value in range(400):
		var patch := WildBeePatch.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		for cell in patch.nest_cells():
			results[patch.should_forage(cell)] += 1
	assert_gt(results[true], 0)
	assert_gt(results[false], 0)
