extends GutTest

const TreeGenome = preload("res://src/gameplay/tree_genome.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

var model


func before_each():
	model = FruitingModel.new()


func _genome(seed_value: int, fruit_yield: float) -> Object:
	var g := TreeGenome.new(seed_value)
	g.fruit_yield = fruit_yield
	return g


func test_state_is_a_dictionary_with_growing_and_ripe_counts():
	var g := _genome(1, 0.8)
	var s = model.state_at(g, 0.0, 0.5)
	assert_true(s.has("growing"))
	assert_true(s.has("ripe"))
	assert_typeof(s["growing"], TYPE_INT)
	assert_typeof(s["ripe"], TYPE_INT)


func test_deterministic_for_same_inputs():
	var g := _genome(7, 0.6)
	var a = model.state_at(g, 100.0, 0.4)
	var b = model.state_at(g, 100.0, 0.4)
	assert_eq(a["growing"], b["growing"])
	assert_eq(a["ripe"], b["ripe"])


func test_crop_cap_scales_with_fruit_yield():
	# Sample ripe over a full cycle and take the peak crop for two yields.
	var low := _genome(3, 0.2)
	var high := _genome(3, 0.9)
	low.maturity_time = 40.0
	high.maturity_time = 40.0
	var peak_low := 0
	var peak_high := 0
	# Sampled across a real BEARING CYCLE rather than a hardcoded 100
	# seconds: that window was sized to the old maturity_time cycle, and once
	# a cycle became a year it fell entirely inside the growing phase, so
	# both peaks were 0 and the assertion below stopped meaning anything.
	for i in range(0, 200):
		var t = FruitingModel.BEARING_CYCLE_SECONDS * float(i) / 200.0
		peak_low = maxi(peak_low, model.state_at(low, t, 0.5)["ripe"])
		peak_high = maxi(peak_high, model.state_at(high, t, 0.5)["ripe"])
	assert_gt(peak_high, peak_low, "higher fruit_yield yields a larger crop cap")
	assert_lte(peak_high, FruitingModel.MAX_CROP)


func test_warmer_tree_ripens_at_least_as_fast():
	# At a fixed mid time, the warmer tree has ripened at least as much.
	var g := _genome(11, 0.9)
	# Taken partway into the ripening half of the cycle, where warmth can
	# actually show -- see the note in test_crop_cap_scales_with_fruit_yield.
	var t = FruitingModel.BEARING_CYCLE_SECONDS * 0.45
	# Measured as TOTAL fruit brought to ripeness by t -- still hanging plus
	# already shed -- not as the hanging count alone. A warm tree far enough
	# along is already dropping its crop, so it can hold FEWER ripe fruit
	# than a colder one that has only just ripened, while being unambiguously
	# further through its year.
	var cold: int = model.state_at(g, t, 0.2)["ripe"] + model.fallen_between(g, 0.0, t, 0.2)
	var warm: int = model.state_at(g, t, 0.9)["ripe"] + model.fallen_between(g, 0.0, t, 0.9)
	assert_gte(warm, cold)


func test_zero_yield_genome_bears_no_fruit():
	var g := _genome(5, 0.0)
	var total_fallen = 0
	for i in range(0, 100):
		var s = model.state_at(g, float(i), 0.5)
		assert_eq(s["ripe"], 0)
		assert_eq(s["growing"], 0)
	total_fallen = model.fallen_between(g, 0.0, 1000.0, 0.5)
	assert_eq(total_fallen, 0)


## Spanned in BEARING CYCLES rather than a hardcoded number of seconds: the
## window was 3000s, which stopped covering even one cycle the moment an
## in-game day became four real hours, and the test then measured nothing.
## The same staleness that had test_terrain_renderer asserting a 4x art
## multiplier years after it became 2x.
func test_fallen_accumulates_over_multiple_cycles():
	var g := _genome(9, 0.8)
	var crop: int = model.crop_potential(g)
	var span: float = FruitingModel.BEARING_CYCLE_SECONDS * 4.0
	var total = model.fallen_between(g, 0.0, span, 0.6)
	assert_gt(total, crop, "four bearing cycles should drop more than one crop")


func test_fallen_over_a_span_equals_sum_of_subintervals():
	var g := _genome(4, 0.7)
	g.maturity_time = 30.0
	var whole = model.fallen_between(g, 0.0, 600.0, 0.5)
	var part_a = model.fallen_between(g, 0.0, 300.0, 0.5)
	var part_b = model.fallen_between(g, 300.0, 600.0, 0.5)
	# Continuous cumulative model: additive within rounding tolerance.
	assert_almost_eq(whole, part_a + part_b, 2)


# -- per-species multipliers (see TreeSpecies) --------------------------------
#
# Named species (Cherry/Apple/Walnut) lean on the same phenology, scaled by
# two per-species multipliers rather than a parallel model -- a yield
# multiplier on crop size, a ripening multiplier on cycle length. Defaulting
# both to 1.0 must reproduce today's behaviour exactly, so every test above
# stays meaningful unchanged.

func test_default_multipliers_reproduce_the_unscaled_behaviour():
	var g := _genome(21, 0.6)
	assert_eq(model.crop_potential(g), model.crop_potential(g, 1.0))
	var plain = model.state_at(g, 50.0, 0.4)
	var explicit = model.state_at(g, 50.0, 0.4, 1.0, 1.0)
	assert_eq(plain["growing"], explicit["growing"])
	assert_eq(plain["ripe"], explicit["ripe"])


func test_yield_multiplier_scales_crop_potential():
	var g := _genome(22, 0.8)
	var boosted = model.crop_potential(g, 1.5)
	var reduced = model.crop_potential(g, 0.5)
	assert_gt(boosted, model.crop_potential(g, 1.0))
	assert_lt(reduced, model.crop_potential(g, 1.0))


## A ripening_multiplier below 1 should ripen a tree FASTER (a shorter
## effective bearing cycle) -- at a fixed elapsed time, the faster-ripening
## tree has fallen at least as much fruit as the baseline.
func test_ripening_multiplier_below_one_ripens_faster():
	var g := _genome(23, 0.9)
	g.maturity_time = 40.0
	var baseline = model.fallen_between(g, 0.0, 400.0, 0.5, 1.0, 1.0)
	var faster = model.fallen_between(g, 0.0, 400.0, 0.5, 1.0, 0.6)
	assert_gte(faster, baseline, "a faster-ripening species should shed at least as much fruit by the same time")


func test_ripening_multiplier_above_one_ripens_slower():
	var g := _genome(24, 0.9)
	g.maturity_time = 40.0
	var baseline = model.fallen_between(g, 0.0, 400.0, 0.5, 1.0, 1.0)
	var slower = model.fallen_between(g, 0.0, 400.0, 0.5, 1.0, 1.4)
	assert_lte(slower, baseline, "a slower-ripening species should shed no more fruit by the same time")


# -- how OFTEN a tree bears ---------------------------------------------------
#
# The bearing cycle was genome.maturity_time -- 20-60 SECONDS. That is the
# time a sapling needs to grow up (see TreeMaturity), not the length of a
# fruiting year, and reusing it meant every tree shed its entire crop every
# half-minute. It went unnoticed for the same reason the 30-second
# reproduction cooldown did: the ecology simulation was never actually
# stepping (see World.owns_ecosystem_simulation_for). The moment it ran, a
# forest buried itself in windfall within a minute of play (reported: "way
# too much fruit are being dropped", with the ground under every tree
# carrying stacks of ~100).

func test_a_tree_bears_about_once_a_year_not_twice_a_minute():
	var g := _genome(31, 0.8)
	var a_year: float = SeasonCycle.SECONDS_PER_YEAR
	var crop: int = model.crop_potential(g)
	var shed_in_a_year: int = model.fallen_between(g, 0.0, a_year, 0.4)
	assert_between(
		float(shed_in_a_year), float(crop) * 0.5, float(crop) * 2.0,
		"a year should shed about one crop, not dozens"
	)


## The number the player actually experiences: how much windfall a forest
## puts on the ground per minute of play. A stand of trees in fruit should
## litter the ground over a season, not bury it in a minute.
func test_a_forest_does_not_bury_itself_in_windfall():
	var trees: Array = []
	for i in 40:
		trees.append(_genome(100 + i, 0.8))
	var per_minute := 0
	for g in trees:
		per_minute += model.fallen_between(g, 0.0, 60.0, 0.4, 1.3, 0.65)  # cherry, the fastest species
	assert_lt(per_minute, 40, "a 40-tree stand should not out-drop the ground-item budget every minute")


## maturity_time keeps meaning what it says -- when a SAPLING can first bear
## (TreeMaturity) -- and must no longer secretly set the bearing cycle too.
func test_how_fast_a_sapling_grows_up_does_not_change_how_often_it_bears():
	var quick := _genome(41, 0.8)
	var slow := _genome(41, 0.8)
	quick.maturity_time = TreeGenome.MIN_MATURITY_TIME
	slow.maturity_time = TreeGenome.MAX_MATURITY_TIME
	assert_eq(
		model.fallen_between(quick, 0.0, SeasonCycle.SECONDS_PER_YEAR * 2.0, 0.4),
		model.fallen_between(slow, 0.0, SeasonCycle.SECONDS_PER_YEAR * 2.0, 0.4)
	)


# -- the crop follows the calendar -------------------------------------------

## A tree flowers in spring, swells its crop through summer, ripens it toward
## autumn, and is BARE BY WINTER.
##
## The bearing cycle ran on its own clock, unaligned to the seasons: abscission
## began at four fifths of the year, which is midwinter, so fruit hung on bare
## branches through the cold and a lot of it never fell at all. Reported as
## fruit staying on the tree until winter.
func test_a_tree_is_bare_by_winter():
	var model := FruitingModel.new()
	var genome := TreeGenome.new(12345)
	var year := SeasonCycle.SECONDS_PER_YEAR
	var cycle := SeasonCycle.new()
	for step in 200:
		var t := float(step) / 199.0 * year
		if cycle.season_at(t) != "winter":
			continue
		var state := model.state_at(genome, t, 1.0)
		assert_eq(
			int(state.ripe), 0,
			"ripe fruit still hanging in winter at year fraction %.2f" % (t / year)
		)


## Everything that grew has come down by the end of autumn -- nothing is
## carried over into the next year still on the branch.
func test_the_whole_crop_is_down_by_the_end_of_autumn():
	var model := FruitingModel.new()
	var genome := TreeGenome.new(9876)
	var year := SeasonCycle.SECONDS_PER_YEAR
	var crop := model.crop_potential(genome)
	var fallen := model.fallen_between(genome, 0.0, year, 1.0)
	assert_gte(
		fallen, float(crop) * 0.99,
		"only %.1f of a crop of %d came down in the year" % [fallen, crop]
	)


## There is ripe fruit to pick in autumn -- the season the whole harvest is
## supposed to happen in.
## Asked of an AUTUMN species now. Species ripen at their own times, so an
## arbitrary genome may well be a cherry -- over and gone before autumn -- and
## asking it about autumn tests nothing.
func test_there_is_ripe_fruit_in_autumn():
	var model := FruitingModel.new()
	var genome := _genome_for("apple")
	var year := SeasonCycle.SECONDS_PER_YEAR
	var cycle := SeasonCycle.new()
	var best := 0
	for step in 200:
		var t := float(step) / 199.0 * year
		if cycle.season_at(t) == "autumn":
			best = maxi(best, int(model.state_at(genome, t, 1.0).ripe))
	assert_gt(best, 0, "nothing ripe in autumn")


## ...and none in spring, when the tree is still in blossom.
## Nothing is ripe in spring for ANY species at ANY warmth: a tree in spring is
## still in blossom, and fruit cannot precede the flower.
func test_nothing_is_ripe_in_spring():
	var model := FruitingModel.new()
	var genome := _genome_for("cherry")
	var year := SeasonCycle.SECONDS_PER_YEAR
	var cycle := SeasonCycle.new()
	for step in 200:
		var t := float(step) / 199.0 * year
		if cycle.season_at(t) == "spring":
			assert_eq(int(model.state_at(genome, t, 1.0).ripe), 0, "ripe fruit in spring")


# -- species ripen at their own times -----------------------------------------

## Cherries ripen in early summer and apples in autumn. One fixed ripening date
## for every tree meant no fruit hung on anything through most of summer, and a
## cherry tree that never bore a cherry when it should (reported).
func test_a_cherry_ripens_in_summer():
	assert_true(_has_ripe_fruit_in("cherry", "summer"), "cherries ripen in summer")


func test_an_apple_ripens_in_autumn():
	assert_true(_has_ripe_fruit_in("apple", "autumn"), "apples ripen in autumn")


## Cherries are gone before the apples are ready -- that is the whole point of
## them ripening at different times.
func test_cherries_are_over_before_apples_are_ready():
	assert_lt(
		FruitingModel.ripe_phase_for("cherry"), FruitingModel.ripe_phase_for("apple")
	)


## Every species bears at some point in the year. One that never ripens is a
## tree that can never be foraged.
func test_every_species_bears_at_some_point():
	for species in TreeSpecies.IDS:
		var borne := false
		for season in SeasonCycle.SEASONS:
			if _has_ripe_fruit_in(species, season):
				borne = true
		assert_true(borne, "%s never bears at all" % species)


## Nothing bears in winter, whatever the species.
func test_nothing_bears_in_winter():
	for species in TreeSpecies.IDS:
		assert_false(_has_ripe_fruit_in(species, "winter"), "%s bears in winter" % species)


## Between them, the roster covers summer AND autumn -- so there is fruit on
## something for most of the growing year rather than one glut.
func test_the_roster_covers_more_than_one_season():
	var seasons := {}
	for species in TreeSpecies.IDS:
		for season in SeasonCycle.SEASONS:
			if _has_ripe_fruit_in(species, season):
				seasons[season] = true
	assert_gte(seasons.size(), 2, "every tree in the world ripens in the same season")


func _has_ripe_fruit_in(species: String, season: String) -> bool:
	var model := FruitingModel.new()
	var genome := _genome_for(species)
	var cycle := SeasonCycle.new()
	for step in 400:
		var t := float(step) / 399.0 * SeasonCycle.SECONDS_PER_YEAR
		if cycle.season_at(t) != season:
			continue
		if int(model.state_at(genome, t, 0.5).ripe) > 0:
			return true
	return false


## A genome whose species_bias lands on the species asked for, with a decent
## crop so the test is about TIMING rather than about yield.
func _genome_for(species: String) -> TreeGenome:
	for attempt in 4000:
		var genome := TreeGenome.new(attempt * 17 + 3)
		if TreeSpecies.species_for_bias(genome.species_bias) != species:
			continue
		if FruitingModel.new().crop_potential(genome) <= 0:
			continue
		return genome
	return TreeGenome.new(1)


## Every species in the roster can actually be dropped as an item.
##
## The drop path indexes its item table by species id, so a species that bears
## fruit with no entry there is a crash waiting for its season -- which is
## exactly what pine, acorn and hazelnut were after they joined the roster.
func test_every_bearing_species_has_something_to_drop():
	var EarthChunkManager := load("res://src/world/earth_chunk_manager.gd")
	for species in TreeSpecies.IDS:
		assert_true(
			EarthChunkManager._NAMED_FRUIT_ITEMS.has(species),
			"%s bears fruit but has no item to drop" % species
		)


# -- bearing is locked to the calendar ---------------------------------------

## Every species bears ONCE a year, in its own season -- not on a private cycle
## that drifts against the calendar.
##
## `_cycle_length` multiplied the year by the species' ripening_multiplier, so a
## cherry (0.65) ran a bearing cycle 0.65 of a year long and a pine (1.8) one
## nearly two years long. The per-species phases are fractions OF A YEAR
## (cherry ripens at 0.32, early summer), so applying them to a 0.65-year cycle
## put the fruit somewhere new every year: measured, 28 cherries in one year in
## two separate windows, the second landing in the middle of WINTER.
##
## This is the same conflation BEARING_CYCLE_SECONDS was introduced to kill --
## how fast a species ripens is WHEN in the year it bears, which the phases
## already say, not how often it bears.
func test_every_species_bears_once_a_year():
	var year := SeasonCycle.SECONDS_PER_YEAR
	for species in TreeSpecies.IDS:
		var genome := _genome(4242, 0.8)
		genome.species_bias = _bias_for(species)
		var yield_multiplier: float = TreeSpecies.yield_multiplier_for(species)
		var ripening: float = TreeSpecies.ripening_multiplier_for(species)
		var crop: int = model.crop_potential(genome, yield_multiplier)
		var fell: int = model.fallen_between(
			genome, 0.0, year, 0.5, yield_multiplier, ripening
		)
		assert_almost_eq(
			float(fell), float(crop), float(crop) * 0.15,
			"%s should shed about one crop (%d) a year, not %d" % [species, crop, fell]
		)


## Nothing is still coming down in winter. The last fruit of the year falls by
## the end of autumn -- the boundary the calendar decides rather than the
## weather.
func test_no_fruit_falls_after_autumn():
	var year := SeasonCycle.SECONDS_PER_YEAR
	var end_of_autumn := year * 0.75
	for species in TreeSpecies.IDS:
		var genome := _genome(4242, 0.8)
		genome.species_bias = _bias_for(species)
		var yield_multiplier: float = TreeSpecies.yield_multiplier_for(species)
		var ripening: float = TreeSpecies.ripening_multiplier_for(species)
		assert_eq(
			model.fallen_between(
				genome, end_of_autumn, year, 0.5, yield_multiplier, ripening
			),
			0,
			"%s should have finished dropping before winter" % species
		)


## And it does not drift: the fifth year looks like the first.
func test_bearing_does_not_drift_across_years():
	var year := SeasonCycle.SECONDS_PER_YEAR
	for species in TreeSpecies.IDS:
		var genome := _genome(4242, 0.8)
		genome.species_bias = _bias_for(species)
		var yield_multiplier: float = TreeSpecies.yield_multiplier_for(species)
		var ripening: float = TreeSpecies.ripening_multiplier_for(species)
		# The same quarter of the year, five years apart.
		for quarter in 4:
			var from := year * float(quarter) / 4.0
			var span := year / 4.0
			assert_eq(
				model.fallen_between(
					genome, from, from + span, 0.5, yield_multiplier, ripening
				),
				model.fallen_between(
					genome, from + year * 5.0, from + year * 5.0 + span,
					0.5, yield_multiplier, ripening
				),
				"%s quarter %d should look the same five years on" % [species, quarter]
			)


func _bias_for(species: String) -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == species:
			return bias
	return 0.0


## Fruit falls the same whether the world is stepped in seconds or in years.
##
## THE bug behind "no fruits accumulate". `fallen_between` rounded each call's
## own increment to a whole fruit, and the game steps fruiting once a SECOND
## (EarthChunkManager.FRUITING_INTERVAL). One second of a crop of twelve spread
## across a fall window a tenth of a year long is about 0.0002 of a fruit, which
## rounds to zero -- every single step, forever. A year-long call returned the
## whole crop, so every test that asked in one big span passed while the running
## game shed nothing at all.
##
## Counting whole fruit fallen SO FAR and differencing that is what makes the
## two agree: most one-second steps yield nothing and occasionally one yields a
## fruit, and any partition of the year sums to the same total.
func test_stepping_a_year_in_seconds_sheds_the_same_crop_as_one_call():
	var year := SeasonCycle.SECONDS_PER_YEAR
	for species in TreeSpecies.IDS:
		var genome := _genome(4242, 0.8)
		genome.species_bias = _bias_for(species)
		var yield_multiplier: float = TreeSpecies.yield_multiplier_for(species)
		var ripening: float = TreeSpecies.ripening_multiplier_for(species)
		var in_one_call: int = model.fallen_between(
			genome, 0.0, year, 0.5, yield_multiplier, ripening
		)
		assert_gt(in_one_call, 0, "precondition: %s should bear at all" % species)

		# Walk the year in many small steps, as the game does.
		var stepped := 0
		var steps := 2000
		for index in steps:
			var from := year * float(index) / float(steps)
			var to := year * float(index + 1) / float(steps)
			stepped += model.fallen_between(
				genome, from, to, 0.5, yield_multiplier, ripening
			)
		assert_eq(
			stepped, in_one_call,
			"%s shed %d stepping through the year but %d asking once"
			% [species, stepped, in_one_call]
		)


# -- fruit are individuals ---------------------------------------------------

## What falls is what stopped hanging. The two used to be computed separately,
## from windows that disagreed about warmth -- the displayed window was shifted
## earlier by `_earliness` and the falling window was not -- so a tree could
## drop cherries while drawn bare, and carry cherries that had already fallen
## (reported: cherries drop in ecotest even though the tree does not bear yet).
##
## Defining a drop as the DECREASE in the hanging count is what makes them
## agree by construction: a fruit cannot fall without leaving the tree.
func test_what_falls_is_exactly_what_stopped_hanging():
	var year := SeasonCycle.SECONDS_PER_YEAR
	for species in TreeSpecies.IDS:
		var genome := _genome(4242, 0.8)
		genome.species_bias = _bias_for(species)
		var ym: float = TreeSpecies.yield_multiplier_for(species)
		var rm: float = TreeSpecies.ripening_multiplier_for(species)
		for step in 60:
			var t0 := year * float(step) / 60.0
			var t1 := year * float(step + 1) / 60.0
			# Warmth as it really varies over the year, which is what exposed
			# the disagreement: a constant warmth hid it.
			var warmth: float = SeasonCycle.new().warmth_modifier(t1)
			var left_the_tree: int = (
				model.hanging_at(genome, t0, warmth, ym, rm)
				- model.hanging_at(genome, t1, warmth, ym, rm)
			)
			if left_the_tree <= 0:
				continue
			assert_eq(
				model.fallen_between(genome, t0, t1, warmth, ym, rm),
				left_the_tree,
				"%s: %d left the tree but a different number hit the ground"
				% [species, left_the_tree]
			)


## Never the other way round either: nothing hits the ground that was not on
## the tree a moment earlier.
func test_nothing_falls_that_was_not_hanging():
	var year := SeasonCycle.SECONDS_PER_YEAR
	for species in TreeSpecies.IDS:
		var genome := _genome(4242, 0.8)
		genome.species_bias = _bias_for(species)
		var ym: float = TreeSpecies.yield_multiplier_for(species)
		var rm: float = TreeSpecies.ripening_multiplier_for(species)
		for step in 60:
			var t0 := year * float(step) / 60.0
			var t1 := year * float(step + 1) / 60.0
			var warmth: float = SeasonCycle.new().warmth_modifier(t1)
			var fell: int = model.fallen_between(genome, t0, t1, warmth, ym, rm)
			if fell <= 0:
				continue
			assert_gt(
				model.hanging_at(genome, t0, warmth, ym, rm), 0,
				"%s dropped %d from a bare tree" % [species, fell]
			)


## The canopy draws the hanging count itself, not a rounded stand-in for it.
func test_the_displayed_crop_is_the_hanging_count():
	var year := SeasonCycle.SECONDS_PER_YEAR
	var genome := _genome(4242, 0.8)
	genome.species_bias = _bias_for("cherry")
	var ym: float = TreeSpecies.yield_multiplier_for("cherry")
	var rm: float = TreeSpecies.ripening_multiplier_for("cherry")
	for step in 40:
		var t := year * float(step) / 40.0
		var warmth: float = SeasonCycle.new().warmth_modifier(t)
		var state: Dictionary = model.state_at(genome, t, warmth, ym, rm)
		assert_eq(
			int(state.get("ripe", -1)),
			model.hanging_at(genome, t, warmth, ym, rm)
		)


## Fruit leave from the TOP of the order, so a crop empties one fruit at a time
## from its own scattered positions rather than thinning uniformly -- and the
## fruit that leaves index k is the one that lands.
func test_fruit_leave_from_the_top_of_the_order():
	assert_eq(model.fallen_indices(5, 2), [4, 3], "the last two hanging are the ones that go")
	assert_eq(model.fallen_indices(5, 0), [])
	assert_eq(model.fallen_indices(3, 9), [2, 1, 0], "cannot drop more than it carried")


# -- peak-timed harvest (docs/concept/progression.md "Ecological literacy") --
#
# "Peak ripeness" is real and tested against the model's OWN output, not an
# invented calendar band: the crop is at genuine peak exactly while it is
# STILL FULLY HANGING (hanging_at has reached its own crop_potential) -- the
# plateau after grow_end (nothing has fallen yet) and before fall_start
# (abscission begins). The moment even one fruit has left the tree, ripeness
# is no longer at its peak.

func test_is_peak_ripe_true_while_the_full_crop_is_still_hanging():
	var genome := _genome_for("apple")
	var window: Dictionary = model._window_for(genome, 0.5)
	# Comfortably inside the plateau, not right at either edge.
	var mid_plateau: float = (float(window.grow_end) + float(window.fall_start)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	assert_eq(model.hanging_at(genome, mid_plateau, 0.5), model.crop_potential(genome))
	assert_true(model.is_peak_ripe(genome, mid_plateau, 0.5))


func test_is_peak_ripe_false_once_abscission_has_begun():
	var genome := _genome_for("apple")
	var window: Dictionary = model._window_for(genome, 0.5)
	var mid_fall: float = (float(window.fall_start) + float(window.fall_end)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	assert_lt(model.hanging_at(genome, mid_fall, 0.5), model.crop_potential(genome))
	assert_false(model.is_peak_ripe(genome, mid_fall, 0.5))


func test_is_peak_ripe_false_before_anything_has_ripened_yet():
	var genome := _genome_for("apple")
	var window: Dictionary = model._window_for(genome, 0.5)
	var still_growing: float = float(window.grow_end) * 0.5 * FruitingModel.BEARING_CYCLE_SECONDS
	assert_false(model.is_peak_ripe(genome, still_growing, 0.5))


func test_is_peak_ripe_false_for_a_zero_yield_genome():
	var g := _genome(50, 0.0)
	assert_false(model.is_peak_ripe(g, 1000.0, 0.5))
