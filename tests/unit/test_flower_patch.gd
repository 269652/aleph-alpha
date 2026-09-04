extends GutTest

## FlowerPatch: the per-chunk meadow -- which cells grow a flower, of which
## species, and how much nectar each currently holds (see
## concept/flora.md, concept/ecosystem_dynamics.md).
##
## Bloom-aware rendering: a flower VISIBLE on screen must be one a pollinator
## will actually visit. Rendering every planted cell regardless of season
## meant a large share of the flowers on screen in spring were summer/autumn
## species with exactly zero scent (FlowerSpecies.scent_strength returns 0.0
## out of bloom), so pollinators correctly ignored them and the feature read
## as broken -- reported twice, most recently with a screenshot: "There's a
## butterfly near two flowers and does nothing... they are not attracted by
## scent at all." The simulation was right; the WORLD was lying about what
## was in bloom.

const FlowerPatch = preload("res://src/world/flower_patch.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const FlowerEstablishment = preload("res://src/world/flower_establishment.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const WindDispersal = preload("res://src/world/wind_dispersal.gd")

const SEASONS := ["winter", "spring", "summer", "autumn"]


func _all_grassland(w: int, h: int) -> Array:
	var biome: Array = []
	for i in w * h:
		biome.append("grassland")
	return biome


func _patch() -> FlowerPatch:
	return FlowerPatch.new(1234, 24, 24, _all_grassland(24, 24))


func test_a_grassland_patch_seeds_some_flowers():
	assert_gt(_patch().get_flower_cells().size(), 0)


func test_blooming_cells_only_returns_species_in_bloom_this_season():
	var patch := _patch()
	for season in SEASONS:
		for cell in patch.blooming_cells(season):
			assert_true(
				FlowerSpecies.is_in_bloom(patch.species_at(cell), season),
				"blooming_cells must never include an out-of-bloom species"
			)


## The filter must not simply empty the world: every season has bloomers, so
## hiding everything would be as wrong as hiding nothing.
##
## Asserted across a stretch of WORLD rather than one small patch, which is
## the scale the claim is actually about. A single chunk holds a handful of
## plants and (since MeadowSpread gives a whole lineage its founder's species)
## only a few species, so one chunk with nothing in bloom in winter is a
## correct meadow, not a broken filter -- what would be wrong is a whole
## region with nothing.
func test_every_season_still_has_some_flowers_in_bloom_somewhere():
	var found := {}
	for season in SEASONS:
		found[season] = 0
	for chunk in 12:
		var patch := FlowerPatch.new(
			1234, 32, 32, _all_grassland(32, 32), Vector2i(chunk * 32, 0)
		)
		for season in SEASONS:
			found[season] += patch.blooming_cells(season).size()
	for season in SEASONS:
		assert_gt(
			found[season], 0,
			"%s showed no blooms at all across twelve chunks of grassland" % season
		)


## The point of the filter: seasons genuinely differ. If every season showed
## the identical set, the bloom table would not be doing anything.
func test_which_flowers_bloom_actually_changes_with_the_season():
	var patch := _patch()
	var spring := patch.blooming_cells("spring")
	var summer := patch.blooming_cells("summer")
	assert_ne(spring.size(), summer.size(), "spring and summer should not show the identical meadow")


## Blooming cells are always a subset of planted cells -- the filter hides
## plants, it never invents them.
func test_blooming_cells_are_a_subset_of_planted_cells():
	var patch := _patch()
	var planted := patch.get_flower_cells()
	for season in SEASONS:
		for cell in patch.blooming_cells(season):
			assert_true(planted.has(cell), "a blooming cell must be a planted cell")


# -- seed: real objects that fall from flowers onto the ground -------------
#
# Seed is NOT a state of the plant -- it is its own entity lying in the grass
# (see concept/flora.md). Flowers shed seed over time and it accumulates
# AROUND them, so a granivore has something it can actually see and walk to,
# and so a picked-clean patch looks different from an untouched one.

func test_a_fresh_meadow_has_not_shed_any_seed_yet():
	assert_eq(_patch().ground_seed_cells().size(), 0, "seed has to fall before it is there")


## A POLLINATED meadow drops seed around itself.
##
## This used to shed with nothing having visited it, which is a meadow
## reproducing on its own with the pollinator as decoration. Requiring pollen
## is what makes the bees load-bearing.
func test_pollinated_flowers_shed_seed_onto_the_ground_over_time():
	var patch := _patch()
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	for i in 200:
		patch.shed_seed(1.0, "summer")
	assert_gt(patch.ground_seed_cells().size(), 0, "a standing meadow should drop seed around itself")


## Seed lands where the WIND put it, not anywhere in the chunk -- that is what
## makes a meadow read as a seed source rather than as scenery scattered at
## random.
##
## This used to assert a flat two-cell radius (the old FlowerPatch.
## SEED_FALL_RADIUS), which stopped being true when shedding moved onto
## WindDispersal: flower seed is the lightest class in the world and a gust
## takes it much further than that. The bound that is actually true is the
## kernel's own -- and it is still a real claim, because the kernel's reach is
## a small fraction of a chunk.
func test_shed_seed_lands_within_the_winds_reach_of_a_flower():
	var patch := _patch()
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	patch.set_wind(Vector2.RIGHT, 0.7)
	for i in 200:
		patch.shed_seed(1.0, "summer")
	assert_gt(patch.ground_seed_cells().size(), 0, "precondition: something shed")
	var flowers := patch.get_flower_cells()
	for cell in patch.ground_seed_cells():
		var nearest := 9999.0
		for flower in flowers:
			nearest = minf(nearest, Vector2(cell - flower).length())
		assert_lte(
			nearest, WindDispersal.MAX_TRAVEL_TILES,
			"seed lay %.1f tiles from any plant -- further than any wind could take it" % nearest
		)


## Seed carries the species that dropped it, so a bird planting it later
## grows the right flower.
func test_ground_seed_knows_its_species():
	var patch := _patch()
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	for i in 200:
		patch.shed_seed(1.0, "summer")
	for cell in patch.ground_seed_cells():
		assert_true(FlowerSpecies.IDS.has(patch.species_of_ground_seed(cell)))


func test_taking_a_ground_seed_removes_it():
	var patch := _patch()
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	for i in 200:
		patch.shed_seed(1.0, "summer")
	var cell = patch.ground_seed_cells()[0]
	assert_ne(patch.take_ground_seed(cell), "", "taking returns the species eaten")
	assert_false(patch.ground_seed_cells().has(cell))
	assert_eq(patch.take_ground_seed(cell), "", "nothing left to take twice")


## Bounded, like every other per-chunk population here -- an unattended
## meadow must not carpet itself in seed over a long session.
func test_ground_seed_is_capped():
	var patch := _patch()
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	for i in 5000:
		patch.shed_seed(1.0, "summer")
	assert_lte(patch.ground_seed_cells().size(), FlowerPatch.MAX_GROUND_SEEDS)


## Plants in bloom are busy flowering; it is the ones whose bloom is over
## that are dropping seed. With nothing out of bloom, nothing sheds.
func test_only_plants_past_their_bloom_shed_seed():
	var patch := _patch()
	# A season in which every planted species is still blooming would shed
	# nothing; assert the weaker, always-true form: shed seed only ever comes
	# from a species that is NOT in bloom that season.
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	for i in 200:
		patch.shed_seed(1.0, "summer")
	assert_gt(
		patch.ground_seed_cells().size(), 0,
		"nothing shed at all -- the rest of this test would assert nothing"
	)
	for cell in patch.ground_seed_cells():
		assert_false(
			FlowerSpecies.is_in_bloom(patch.species_of_ground_seed(cell), "summer"),
			"a flower still in bloom has not set seed yet"
		)


# -- flowers grow ------------------------------------------------------------
#
# Every flower was full-size the instant it existed, so a meadow filling in
# from shed seed looked like blooms popping into being (reported: "saplings
# and young flowers should be even smaller"). Mirrors TallGrass, where
# map-seeded patches start mature and newly-spread ones grow.

func test_a_newly_planted_flower_starts_as_a_seedling():
	var patch := FlowerPatch.new(1, 8, 8, _grassland(8, 8))
	var cell := Vector2i(3, 3)
	if patch.has_flower(cell):
		return  # that cell was map-seeded; nothing to plant
	assert_true(patch.plant(cell, "rose"))
	assert_lt(patch.growth_at(cell), 1.0, "a just-planted flower is not a full bloom")


## Map-seeded flowers are the meadow that was already there, so they start
## grown -- the same rule TallGrass uses for its initial patches.
func test_the_meadow_that_was_always_there_starts_grown():
	# A full chunk's worth of ground, not a 12x12 corner of one: a baked
	# meadow is now sparse enough (see MeadowSpread) that a small patch can
	# honestly hold nothing at all.
	var patch := FlowerPatch.new(2, 32, 32, _grassland(32, 32))
	var cells := patch.get_flower_cells()
	assert_gt(cells.size(), 0, "precondition: some flowers seeded")
	for cell in cells:
		assert_almost_eq(patch.growth_at(cell), 1.0, 0.001)


func test_a_seedling_grows_to_full_size_and_stops():
	var patch := FlowerPatch.new(3, 8, 8, _grassland(8, 8))
	var cell := Vector2i(5, 5)
	if patch.has_flower(cell):
		return
	patch.plant(cell, "tulip")
	patch.advance(FlowerPatch.SECONDS_TO_MATURE * 2.0, 1.0)
	assert_almost_eq(patch.growth_at(cell), 1.0, 0.001, "growth stops at grown")


## Lighter regression pin of the seasonal-growth contract test_tall_grass.gd
## proves thoroughly (see its test_advance_grows_slower_in_winter_than_in_
## summer_for_the_same_elapsed_time): growth_modifier must scale FlowerPatch's
## own seedling growth increment too -- NOT the nectar/seed regen in the same
## advance() call, which are unrelated resources, not "growing".
func test_advance_grows_seedlings_slower_in_winter_than_in_summer():
	var cycle := SeasonCycle.new()
	var summer_modifier: float = cycle.growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.375)
	var winter_modifier: float = cycle.growth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.875)

	var summer := FlowerPatch.new(1, 8, 8, _grassland(8, 8))
	var winter := FlowerPatch.new(1, 8, 8, _grassland(8, 8))
	var cell := Vector2i(3, 3)
	if summer.has_flower(cell):
		return  # that cell was map-seeded; nothing to plant for this check
	assert_true(summer.plant(cell, "rose"))
	assert_true(winter.plant(cell, "rose"))

	summer.advance(FlowerPatch.SECONDS_TO_MATURE * 0.1, summer_modifier)
	winter.advance(FlowerPatch.SECONDS_TO_MATURE * 0.1, winter_modifier)

	assert_gt(summer.growth_at(cell), winter.growth_at(cell))


func test_growth_takes_a_while_rather_than_a_moment():
	var patch := FlowerPatch.new(4, 8, 8, _grassland(8, 8))
	var cell := Vector2i(2, 6)
	if patch.has_flower(cell):
		return
	patch.plant(cell, "clover")
	patch.advance(FlowerPatch.SECONDS_TO_MATURE * 0.25, 1.0)
	assert_lt(patch.growth_at(cell), 0.5, "a quarter of the way is not most of the way")


func test_an_empty_cell_has_no_growth():
	var patch := FlowerPatch.new(5, 8, 8, _grassland(8, 8))
	assert_eq(patch.growth_at(Vector2i(99, 99)), 0.0)


func _grassland(width: int, height: int) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(width * height)
	biome.fill("grassland")
	return biome


# -- seed needs pollen -------------------------------------------------------

## A plant that sets seed on its own is not being pollinated -- it is just
## reproducing, with the pollinator as decoration. Requiring pollen makes the
## bees load-bearing: no bees, no seed.
func test_an_unpollinated_meadow_sets_no_seed():
	var patch := FlowerPatch.new(1234, 16, 16, _grassland(16, 16))
	for step in 200:
		patch.advance(60.0, 1.0)
		patch.shed_seed(60.0, "winter")
	assert_eq(
		patch.ground_seed_cells().size(), 0,
		"a meadow nothing visited should not seed itself"
	)


func test_a_pollinated_plant_sets_seed():
	var patch := FlowerPatch.new(1234, 16, 16, _grassland(16, 16))
	var pollinated := false
	for cell in patch.get_flower_cells():
		if patch.pollinate(cell, patch.species_at(cell)):
			pollinated = true
	assert_true(pollinated, "no female flower in the whole patch to pollinate")
	for step in 200:
		patch.advance(60.0, 1.0)
		patch.shed_seed(60.0, "winter")
	assert_gt(
		patch.ground_seed_cells().size(), 0,
		"a pollinated meadow should set seed"
	)


## Pollen of the wrong species does nothing.
func test_the_wrong_pollen_does_not_pollinate():
	var patch := FlowerPatch.new(1234, 16, 16, _grassland(16, 16))
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, "not_a_species")
	for step in 200:
		patch.advance(60.0, 1.0)
		patch.shed_seed(60.0, "winter")
	assert_eq(patch.ground_seed_cells().size(), 0, "wrong pollen should set no seed")



# -- seed goes on the wind ---------------------------------------------------

## Flower seed is the lightest thing in the world and should travel furthest --
## it is why meadows colonise faster than woods. It was dropped within two
## tiles of the parent regardless of weather, which is heavier behaviour than
## an acorn's.
func test_seed_travels_further_than_the_old_two_tile_scatter():
	var patch := FlowerPatch.new(1234, 48, 48, _grassland(48, 48))
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	patch.set_wind(Vector2.RIGHT, 1.0)
	for i in 400:
		patch.shed_seed(1.0, "winter")
	var furthest := 0
	for seed_cell in patch.ground_seed_cells():
		for flower in patch.get_flower_cells():
			furthest = maxi(
				furthest,
				mini(
					absi(seed_cell.x - flower.x) + absi(seed_cell.y - flower.y),
					999
				)
			)
	assert_gt(furthest, 2, "seed should carry further than the old fixed radius")


## It goes DOWNWIND: a meadow creeps in the direction the wind blows rather
## than expanding as a circle.
func test_seed_drifts_downwind():
	var east := _seeded_with_wind(Vector2.RIGHT)
	var west := _seeded_with_wind(Vector2.LEFT)
	assert_gt(east, west, "seed should land further east when the wind blows east")


## In dead calm it still spreads, just not far -- a still day is not a barren
## one.
func test_seed_still_falls_in_dead_calm():
	var patch := FlowerPatch.new(99, 32, 32, _grassland(32, 32))
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	patch.set_wind(Vector2.RIGHT, 0.0)
	for i in 300:
		patch.shed_seed(1.0, "winter")
	assert_gt(patch.ground_seed_cells().size(), 0, "a calm day should still seed")


## The mean landing point, east-west, for a given wind.
func _seeded_with_wind(direction: Vector2) -> float:
	var patch := FlowerPatch.new(1234, 48, 48, _grassland(48, 48))
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	patch.set_wind(direction, 1.0)
	for i in 400:
		patch.shed_seed(1.0, "winter")
	var total := 0.0
	var count := 0
	for seed_cell in patch.ground_seed_cells():
		total += float(seed_cell.x)
		count += 1
	return total / float(maxi(count, 1))


# -- rain roots what is lying there ------------------------------------------

## A seed lies there until it is watered. That is what makes rain something a
## player waits for rather than a weather texture (see SeedGermination).
func test_rain_roots_seed_into_new_plants():
	var patch := _sown_patch()
	var before := patch.get_flower_cells().size()
	var lying := patch.ground_seed_cells().size()
	assert_gt(lying, 0, "nothing was sown to root")
	patch.root_seeds(1.0, 1.0)  # soaking wet, bare earth
	assert_gt(patch.get_flower_cells().size(), before, "rain should have rooted something")


func test_dry_weather_roots_nothing():
	var patch := _sown_patch()
	var before := patch.get_flower_cells().size()
	patch.root_seeds(0.25, 1.0)  # dry
	assert_eq(patch.get_flower_cells().size(), before, "seed should not root in dry weather")


## A rooted seed is gone from the ground -- it is a plant now, not a seed.
func test_a_rooted_seed_is_no_longer_lying_there():
	var patch := _sown_patch()
	var lying := patch.ground_seed_cells().size()
	patch.root_seeds(1.0, 1.0)
	assert_lt(patch.ground_seed_cells().size(), lying)


## Bare earth roots more of them than thick turf, which is what makes clearing
## ground a way to start a meadow.
## Rooting respects the meadow's own ceiling: a full patch takes no more seed
## however hard it rains.
##
## Bare-earth-versus-turf is NOT asserted here. A patch has a flower ceiling
## (MAX_FLOWERS) and a sown one is already at it, so both grounds root the same
## handful and the comparison shows nothing about the seedbed -- it shows the
## cap. The seedbed difference is tested where it lives, in
## test_seed_germination.
func test_rooting_respects_the_meadows_ceiling():
	var patch := _sown_patch()
	for step in 20:
		patch.root_seeds(1.0, 1.0)
	assert_lte(
		patch.get_flower_cells().size(), FlowerPatch.MAX_FLOWERS,
		"a meadow should not root past its own ceiling"
	)


## A new plant starts as a seedling, not a full bloom -- growth is something
## the player can watch.
func test_a_rooted_seed_starts_as_a_seedling():
	var patch := _sown_patch()
	var before := {}
	for cell in patch.get_flower_cells():
		before[cell] = true
	patch.root_seeds(1.0, 1.0)
	for cell in patch.get_flower_cells():
		if before.has(cell):
			continue
		assert_lt(patch.growth_at(cell), 1.0, "a newly rooted seed should be a seedling")


func _sown_patch() -> FlowerPatch:
	var patch := FlowerPatch.new(1234, 32, 32, _grassland(32, 32))
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	patch.set_wind(Vector2.RIGHT, 0.5)
	for i in 300:
		patch.shed_seed(1.0, "winter")
	return patch


# -- the meadow that was already there ---------------------------------------
#
# Reported live: flowers "spread or grow way too dense", and the baked initial
# world state "should also respect this and simulate spread based on wind
# strength and direction". The initial meadow used to be an independent coin
# flip per grassland cell -- a uniform speckle that produced adjacent pairs and
# triples constantly and knew nothing about the wind. It is now run through
# MeadowSpread (see concept/flora.md#the-meadow-you-arrive-to-is-what-the-wind-
# already-did).

func _far_from_every_flower(patch: FlowerPatch, width: int, height: int) -> Vector2i:
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if FlowerEstablishment.is_clear(cell, patch.get_flower_cells()):
				return cell
	return Vector2i(-1, -1)


func test_the_meadow_it_starts_with_is_spaced_out():
	for seed_value in [1234, 77, 9, -4]:
		var patch := FlowerPatch.new(seed_value, 48, 48, _grassland(48, 48))
		var cells := patch.get_flower_cells()
		for i in cells.size():
			for j in range(i + 1, cells.size()):
				assert_gte(
					Vector2(cells[i] - cells[j]).length(), FlowerEstablishment.MIN_SPACING_TILES,
					"seed %d started with %s and %s on top of each other"
					% [seed_value, cells[i], cells[j]]
				)


## The baked state answers to the wind like everything else does.
func test_the_prevailing_wind_shapes_the_meadow_it_starts_with():
	var east := FlowerPatch.new(
		7, 48, 48, _grassland(48, 48), Vector2i.ZERO, Vector2.RIGHT, 0.9
	)
	var west := FlowerPatch.new(
		7, 48, 48, _grassland(48, 48), Vector2i.ZERO, Vector2.LEFT, 0.9
	)
	assert_ne(
		east.get_flower_cells(), west.get_flower_cells(),
		"the wind's direction made no difference to the meadow"
	)


## A meadow near the origin and the same meadow far away are different ground,
## not the same chunk repeated -- founders live in world tiles.
func test_where_in_the_world_the_chunk_is_decides_what_grows_on_it():
	var here := FlowerPatch.new(7, 32, 32, _grassland(32, 32), Vector2i.ZERO)
	var there := FlowerPatch.new(7, 32, 32, _grassland(32, 32), Vector2i(4096, -2048))
	assert_ne(here.get_flower_cells(), there.get_flower_cells())


# -- the gate applies to every way a flower comes into being -----------------

## An animal dropping carried seed at a standing plant's foot does not grow a
## second plant there. A gate the animal-dispersal path could route around
## would silently refill exactly the gaps the baked meadow opened.
func test_seed_dropped_at_a_standing_plants_foot_does_not_take():
	var patch := FlowerPatch.new(1234, 32, 32, _grassland(32, 32))
	var standing: Vector2i = patch.get_flower_cells()[0]
	assert_false(
		patch.plant(standing + Vector2i(1, 0), "rose"),
		"a seed rooted right beside a standing plant"
	)


func test_seed_dropped_clear_of_the_meadow_still_takes():
	var patch := FlowerPatch.new(1234, 32, 32, _grassland(32, 32))
	var clear := _far_from_every_flower(patch, 32, 32)
	assert_ne(clear, Vector2i(-1, -1), "precondition: the meadow left some open ground")
	assert_true(patch.plant(clear, "rose"), "open ground refused a seed")


## And rain rooting lying seed obeys it too -- the third and last way a flower
## can appear.
func test_rain_never_roots_seed_on_top_of_a_standing_plant():
	var patch := FlowerPatch.new(1234, 32, 32, _grassland(32, 32))
	for cell in patch.get_flower_cells():
		patch.pollinate(cell, patch.species_at(cell))
	patch.set_wind(Vector2.RIGHT, 0.5)
	for i in 300:
		patch.shed_seed(1.0, "winter")
	for step in 10:
		patch.root_seeds(1.0, 1.0)
	var cells := patch.get_flower_cells()
	assert_gt(cells.size(), 0, "precondition: there is a meadow to crowd")
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			assert_gte(
				Vector2(cells[i] - cells[j]).length(), FlowerEstablishment.MIN_SPACING_TILES,
				"rain rooted %s on top of %s" % [cells[i], cells[j]]
			)
