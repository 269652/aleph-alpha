extends GutTest

## The sward -- the low rosette layer between the tussocks (see
## docs/concept/ground_cover.md).
##
## Reported live against a real grassland chunk at noon: "the bare grass parts
## feel empty". TallGrass covers ~20% of grassland and FlowerPatch 3.5%, so
## about three quarters of a meadow carried nothing at all.
##
## Every test here is an ORDERING or an INVARIANT rather than a number: the
## multipliers must stay retunable, and what must not change is that shade
## suppresses the sward, grazing releases it, and no combination of the two can
## push cover outside its range.

const GroundCover = preload("res://src/world/ground_cover.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")

const RICH := 1.0
const POOR := 0.0
const NO_GRASS := 0.0
const FULL_TUSSOCK := 1.0
const UNGRAZED := 0.0
const HARD_GRAZED := 1.0


# -- the one piece of ecology ------------------------------------------------


## A tussock closing over a cell shades the rosettes out. This is half of why
## the sward is a readout rather than scatter.
func test_shade_suppresses_the_sward():
	assert_gt(
		GroundCover.cover_for(RICH, NO_GRASS, UNGRAZED),
		GroundCover.cover_for(RICH, FULL_TUSSOCK, UNGRAZED)
	)


## ...and grazing is the other half. Every species in the sward grows from a
## crown at ground level, so a bite that takes a grass's growing point merely
## trims theirs.
func test_grazing_releases_the_sward():
	assert_gt(
		GroundCover.cover_for(RICH, FULL_TUSSOCK, HARD_GRAZED),
		GroundCover.cover_for(RICH, FULL_TUSSOCK, UNGRAZED)
	)


## The composition that makes the readout legible in play, and the reason the
## real thing is called a grazing LAWN: a hard-grazed cell under a tussock
## carries more sward than an untouched bare one. Without this the player would
## only ever see the sward where grass happens not to grow, which is scatter
## again by another name.
func test_a_grazed_tussock_beats_an_ungrazed_gap():
	assert_gt(
		GroundCover.cover_for(RICH, FULL_TUSSOCK, HARD_GRAZED),
		GroundCover.cover_for(RICH, NO_GRASS, UNGRAZED)
	)


## Soil varies. A meadow that carried exactly the same sward on every cell
## would read as a texture rather than as ground.
func test_richer_ground_carries_more_sward():
	assert_gt(
		GroundCover.cover_for(RICH, NO_GRASS, UNGRAZED),
		GroundCover.cover_for(POOR, NO_GRASS, UNGRAZED)
	)


func test_cover_never_leaves_its_range():
	for base_step in 5:
		for grass_step in 5:
			for graze_step in 5:
				var cover := GroundCover.cover_for(
					float(base_step) / 4.0, float(grass_step) / 4.0, float(graze_step) / 4.0
				)
				assert_between(cover, 0.0, 1.0)


## Out-of-range inputs are a real case in this codebase, not defensiveness: a
## caller reading a live growth value should never be able to produce a cover
## that breaks the renderer's instance count.
func test_out_of_range_inputs_are_clamped_rather_than_propagated():
	assert_between(GroundCover.cover_for(9.0, -3.0, 42.0), 0.0, 1.0)
	assert_between(GroundCover.cover_for(-9.0, 3.0, -42.0), 0.0, 1.0)


# -- what gets drawn ---------------------------------------------------------


## Cover drives how MANY plants a cell shows, not how big they are: a richer
## patch of sward is more plants, not larger ones.
func test_more_cover_means_more_plants():
	var sparse := GroundCover.plant_count_for(0.1)
	var dense := GroundCover.plant_count_for(1.0)
	assert_gt(dense, sparse)


func test_plant_count_never_leaves_its_range():
	for step in 21:
		var count := GroundCover.plant_count_for(float(step) / 20.0 * 1.5 - 0.25)
		assert_between(count, 0, GroundCover.MAX_PLANTS_PER_CELL)


## Bare ground stays bare. Without a real zero the sward would be a uniform
## carpet, and the shade/grazing readout would have nothing to read against.
func test_no_cover_draws_nothing():
	assert_eq(GroundCover.plant_count_for(0.0), 0)


# -- a chunk's worth ---------------------------------------------------------


func _grassland(width: int, height: int) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(width * height)
	biome.fill("grassland")
	return biome


func test_a_grassland_chunk_carries_sward_on_most_of_its_cells():
	var sim := GroundCover.new(4242, 16, 16, _grassland(16, 16))
	var covered := 0
	for y in 16:
		for x in 16:
			if sim.cover_at(Vector2i(x, y), NO_GRASS) > 0.0:
				covered += 1
	# The whole point: the ~76% of a meadow that carried nothing now carries
	# something. Asserted against TallGrass's own reference density rather than
	# a bare number, so the two layers cannot silently drift apart.
	assert_gt(
		float(covered) / 256.0,
		1.0 - TallGrass.SEED_CHANCE,
		"the sward should reach the ground tall grass leaves bare"
	)


## ...but not uniformly, or it is a texture and not ground.
func test_the_sward_is_not_uniform():
	var sim := GroundCover.new(4242, 16, 16, _grassland(16, 16))
	var seen := {}
	for y in 16:
		for x in 16:
			seen[sim.plant_count_at(Vector2i(x, y), NO_GRASS)] = true
	assert_gt(seen.size(), 1, "every cell showing the same number of plants is a texture")


## Only grassland. A forest herb layer is real and is the obvious next biome,
## but the species table this draws is a pasture sward.
func test_nothing_grows_on_ocean():
	var biome := PackedStringArray()
	biome.resize(4 * 4)
	biome.fill("ocean")
	var sim := GroundCover.new(1, 4, 4, biome)
	for y in 4:
		for x in 4:
			assert_eq(sim.cover_at(Vector2i(x, y), NO_GRASS), 0.0)


## Deterministic, like every other patch sim here: a chunk that unloads and
## reloads comes back as the same meadow.
func test_the_same_seed_rebuilds_the_same_sward():
	var first := GroundCover.new(77, 8, 8, _grassland(8, 8))
	var second := GroundCover.new(77, 8, 8, _grassland(8, 8))
	for y in 8:
		for x in 8:
			assert_eq(first.cover_at(Vector2i(x, y), NO_GRASS), second.cover_at(Vector2i(x, y), NO_GRASS))


func test_a_different_seed_is_a_different_meadow():
	var first := GroundCover.new(77, 8, 8, _grassland(8, 8))
	var second := GroundCover.new(78, 8, 8, _grassland(8, 8))
	var same := 0
	for y in 8:
		for x in 8:
			if first.cover_at(Vector2i(x, y), NO_GRASS) == second.cover_at(Vector2i(x, y), NO_GRASS):
				same += 1
	assert_lt(same, 64, "two seeds should not produce an identical meadow")


# -- grazing memory ----------------------------------------------------------


func test_a_grazed_cell_carries_more_sward_than_it_did()  :
	var sim := GroundCover.new(5, 8, 8, _grassland(8, 8))
	var cell := Vector2i(3, 3)
	var before := sim.cover_at(cell, FULL_TUSSOCK)

	sim.record_graze(cell)

	assert_gt(sim.cover_at(cell, FULL_TUSSOCK), before)


func test_grazing_one_cell_leaves_its_neighbour_alone():
	var sim := GroundCover.new(5, 8, 8, _grassland(8, 8))
	var neighbour := Vector2i(4, 3)
	var before := sim.cover_at(neighbour, FULL_TUSSOCK)

	sim.record_graze(Vector2i(3, 3))

	assert_eq(sim.cover_at(neighbour, FULL_TUSSOCK), before)


## Repeated grazing compounds -- a meadow kept under stock is different from
## one an animal wandered across once.
func test_repeated_grazing_compounds():
	var sim := GroundCover.new(5, 8, 8, _grassland(8, 8))
	var cell := Vector2i(3, 3)
	sim.record_graze(cell)
	var once := sim.cover_at(cell, FULL_TUSSOCK)
	sim.record_graze(cell)
	assert_gt(sim.cover_at(cell, FULL_TUSSOCK), once)


## The tussocks come back, and the sward closes again. Expressed against
## TallGrass.SPREAD_INTERVAL -- the clock on which grass actually returns --
## rather than as an eyeballed number of seconds.
func test_the_sward_closes_again_once_the_grazing_stops():
	var sim := GroundCover.new(5, 8, 8, _grassland(8, 8))
	var cell := Vector2i(3, 3)
	sim.record_graze(cell)
	var grazed := sim.cover_at(cell, FULL_TUSSOCK)

	sim.advance(TallGrass.SPREAD_INTERVAL * GroundCover.RECOVERY_SPREADS)

	assert_lt(sim.cover_at(cell, FULL_TUSSOCK), grazed)


func test_grazing_memory_decay_is_frame_rate_independent():
	var one := GroundCover.new(5, 8, 8, _grassland(8, 8))
	var many := GroundCover.new(5, 8, 8, _grassland(8, 8))
	var cell := Vector2i(3, 3)
	one.record_graze(cell)
	many.record_graze(cell)

	one.advance(8.0)
	for step in 4:
		many.advance(2.0)

	assert_almost_eq(one.cover_at(cell, FULL_TUSSOCK), many.cover_at(cell, FULL_TUSSOCK), 0.0001)


func test_grazing_an_off_map_cell_is_harmless():
	var sim := GroundCover.new(5, 8, 8, _grassland(8, 8))
	sim.record_graze(Vector2i(-1, 99))
	assert_eq(sim.cover_at(Vector2i(-1, 99), NO_GRASS), 0.0)


# -- where the plants actually go --------------------------------------------
#
# Pure unit-space placement: offsets are fractions of a cell, so the math is
# tile-size agnostic and testable without a renderer. The MultiMesh fill that
# consumes this is thin glue -- per-instance transforms do not round-trip under
# --headless (the dummy renderer), the same split
# IllustratedGrassPatch.instances_for_cards / fill_band already uses.


func test_a_cell_lays_out_exactly_the_plants_it_was_asked_for():
	assert_eq(GroundCover.plants_for_cell(Vector2i(2, 3), 3, 99).size(), 3)
	assert_eq(GroundCover.plants_for_cell(Vector2i(2, 3), 0, 99).size(), 0)


## Every plant sits INSIDE its own cell, or the sward would bleed across tile
## boundaries and a grazed cell's readout would smear into its neighbour.
func test_every_plant_stays_inside_its_own_cell():
	for cell_x in 4:
		for count in range(1, GroundCover.MAX_PLANTS_PER_CELL + 1):
			for plant in GroundCover.plants_for_cell(Vector2i(cell_x, 7), count, 4242):
				assert_between(plant["offset"].x, 0.0, 1.0)
				assert_between(plant["offset"].y, 0.0, 1.0)


## Plants in one cell must not stack on top of each other -- overlapping
## rosettes read as one bigger plant, which is the opposite of what cover means.
func test_plants_in_a_cell_do_not_sit_on_top_of_each_other():
	var plants := GroundCover.plants_for_cell(Vector2i(1, 1), GroundCover.MAX_PLANTS_PER_CELL, 7)
	for i in plants.size():
		for j in range(i + 1, plants.size()):
			assert_gt(
				plants[i]["offset"].distance_to(plants[j]["offset"]),
				0.15,
				"two rosettes landed on the same spot"
			)


## Neighbouring cells must not lay out identically, which is the clustering bug
## this project has hit repeatedly with Godot's string hash (see PixelNoise).
func test_neighbouring_cells_do_not_lay_out_identically():
	var here := GroundCover.plants_for_cell(Vector2i(5, 5), 3, 11)
	var next_door := GroundCover.plants_for_cell(Vector2i(6, 5), 3, 11)
	var identical := true
	for i in here.size():
		if here[i]["offset"] != next_door[i]["offset"] or here[i]["species"] != next_door[i]["species"]:
			identical = false
	assert_false(identical, "a cell and its neighbour laid out the same sward")


## Deterministic, like everything else here: the same cell redraws the same
## plants after a chunk unload and reload.
func test_a_cell_lays_out_the_same_plants_every_time():
	assert_eq(
		GroundCover.plants_for_cell(Vector2i(3, 9), 4, 55),
		GroundCover.plants_for_cell(Vector2i(3, 9), 4, 55)
	)


## Every species in the table actually turns up. A species nothing ever draws
## is a species that does not exist.
func test_every_species_is_reachable():
	var seen := {}
	for y in 24:
		for x in 24:
			for plant in GroundCover.plants_for_cell(Vector2i(x, y), GroundCover.MAX_PLANTS_PER_CELL, 3):
				seen[plant["species"]] = true
	assert_eq(seen.size(), GroundCover.SPECIES.size(), "not every sward species is ever drawn")


func test_every_species_index_is_in_range():
	for x in 16:
		for plant in GroundCover.plants_for_cell(Vector2i(x, 2), GroundCover.MAX_PLANTS_PER_CELL, 8):
			assert_between(plant["species"], 0, GroundCover.SPECIES.size() - 1)


## A rosette is not a perfect circle, so drawing every one at the same size and
## angle would read as stamped clones.
func test_plants_vary_in_size_and_angle():
	var scales := {}
	var rotations := {}
	for x in 20:
		for plant in GroundCover.plants_for_cell(Vector2i(x, 4), GroundCover.MAX_PLANTS_PER_CELL, 6):
			scales[snappedf(plant["scale"], 0.01)] = true
			rotations[snappedf(plant["rotation"], 0.01)] = true
	assert_gt(scales.size(), 1)
	assert_gt(rotations.size(), 1)


func test_plant_scales_stay_sane():
	for x in 20:
		for plant in GroundCover.plants_for_cell(Vector2i(x, 4), GroundCover.MAX_PLANTS_PER_CELL, 6):
			assert_between(plant["scale"], GroundCover.MIN_PLANT_SCALE, GroundCover.MAX_PLANT_SCALE)


# -- keeping step with the tussocks ------------------------------------------
#
# The sward is rebuilt on a throttle (GRASS_REFRESH_INTERVAL, 5s), which is
# fine while standing still and visibly wrong while walking: the tile window it
# is drawn against moves with the player, so without a nudge the ground at the
# leading edge of the screen stays bare for up to five seconds after it comes
# into view. Grass solves this by making its own throttled refresh DUE
# immediately whenever the player crosses a tile or a chunk boundary
# (_sync_decoration_and_grass_tracking); the sward has to ride the same
# trigger, or the two plant layers visibly disagree about where the meadow is.

const EarthChunkManagerForSward = preload("res://src/world/earth_chunk_manager.gd")


func _manager() -> EarthChunkManagerForSward:
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	add_child(tile_map_layer)
	add_child(entities)
	add_child(creatures)
	_scratch.append(tile_map_layer)
	_scratch.append(entities)
	_scratch.append(creatures)
	return EarthChunkManagerForSward.new(tile_map_layer, entities, creatures)


var _scratch: Array = []


func after_each():
	for node in _scratch:
		node.queue_free()
	_scratch.clear()


func test_walking_a_tile_makes_the_sward_refresh_due_immediately():
	var manager := _manager()
	manager.update(Vector2i(0, 0))
	manager.step_ground_cover(EarthChunkManagerForSward.GRASS_REFRESH_INTERVAL)

	manager.update(Vector2i(1, 0))

	assert_gte(
		manager._sward_refresh_accumulator,
		EarthChunkManagerForSward.GRASS_REFRESH_INTERVAL,
		"the sward must resync on the same tile-crossing trigger grass does"
	)


## ...and the trigger is genuinely shared, not a second copy that can drift:
## after the same update, grass and the sward are both due.
func test_the_sward_and_the_tussocks_come_due_together():
	var manager := _manager()
	manager.update(Vector2i(0, 0))
	manager.step_tall_grass(EarthChunkManagerForSward.GRASS_REFRESH_INTERVAL)
	manager.step_ground_cover(EarthChunkManagerForSward.GRASS_REFRESH_INTERVAL)

	manager.update(Vector2i(0, 1))

	assert_eq(manager._sward_refresh_accumulator, manager._grass_refresh_accumulator)
