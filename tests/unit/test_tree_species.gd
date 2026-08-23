extends GutTest

## TreeSpecies (see docs/concept/flora.md's "Named fruit and nut tree species").
##
## Before this, a tree's "species" was a single continuous TreeGenome.species_bias
## float (0=nut..1=fruit) bucketed into 4 anonymous canopy-colour buckets --
## nothing a player could actually name. This gives the fruit/nut end of that
## spectrum three real, named species: Cherry and Apple anchor the fruit end,
## Walnut the nut end, each with its own colour and ripening character.
##
## Species is still derived purely from a tree's own position (via its
## genome's species_bias), never stored state -- same "no per-tree state,
## everything re-derivable from position" idiom TreeGenome/ForageScheduler
## already use.

const TreeSpecies = preload("res://src/world/tree_species.gd")


# -- classification: species_bias -> named species ---------------------------

## The bias spectrum runs NUT to FRUIT, and the roster is ordered along it, so
## the lowest bias is the nuttiest tree and the highest is an orchard fruit.
func test_the_lowest_bias_is_the_nuttiest_tree():
	assert_eq(TreeSpecies.species_for_bias(0.0), TreeSpecies.IDS[0])


func test_the_highest_bias_is_the_fruitiest_tree():
	assert_eq(TreeSpecies.species_for_bias(1.0), TreeSpecies.IDS[-1])
	assert_eq(TreeSpecies.species_for_bias(0.999), TreeSpecies.IDS[-1])


## Bands are computed from the roster rather than written down as thresholds.
##
## They were three hardcoded numbers, which meant every species added needed
## another one -- and the constants were named after the species either side of
## them, so the names went stale the moment the roster changed.
func test_the_range_is_split_evenly_between_the_species():
	var counts := {}
	var samples := 6000
	for i in samples:
		var bias := float(i) / float(samples)
		var species := TreeSpecies.species_for_bias(bias)
		counts[species] = counts.get(species, 0) + 1
	assert_eq(counts.size(), TreeSpecies.IDS.size(), "some species never comes up")
	var expected := float(samples) / float(TreeSpecies.IDS.size())
	for species in counts:
		assert_almost_eq(
			float(counts[species]), expected, expected * 0.05,
			"%s gets an uneven share of the spectrum" % species
		)


## Species come up in roster order as the bias rises -- the spectrum is
## ordered, not shuffled.
func test_species_appear_in_roster_order_along_the_spectrum():
	var seen: Array[String] = []
	for i in 600:
		var species := TreeSpecies.species_for_bias(float(i) / 600.0)
		if seen.is_empty() or seen[-1] != species:
			seen.append(species)
	assert_eq(seen, TreeSpecies.IDS)


func test_every_bias_in_zero_one_maps_to_a_known_species():
	for i in 21:
		var bias := float(i) / 20.0
		assert_true(TreeSpecies.IDS.has(TreeSpecies.species_for_bias(bias)))


# -- catalog contents ---------------------------------------------------------

func test_ids_lists_every_named_species():
	assert_eq(
		TreeSpecies.IDS, ["pine", "acorn", "hazelnut", "walnut", "cherry", "apple"]
	)


## Every species drops an item the game actually knows about: a tree's species
## id IS the id of the item it drops, so a species with no matching catalog
## entry would drop nothing at all.
func test_every_species_drops_a_real_item():
	var catalog = load("res://src/gameplay/item_catalog.gd").new()
	for id in TreeSpecies.IDS:
		assert_true(catalog.has(id), "%s has no item to drop" % id)


func test_every_species_has_a_display_name():
	for id in TreeSpecies.IDS:
		assert_gt(TreeSpecies.display_name_for(id).length(), 0)


## Canopy colours must be distinct per species (the reported gap: "canopy/
## fruit colour distinct from the current bucketed continuous-species
## colours") and must still read as green -- these are real trees, not
## autumn foliage.
func test_canopy_colours_are_distinct_and_green_dominant():
	var seen := {}
	for id in TreeSpecies.IDS:
		var c: Color = TreeSpecies.canopy_color_for(id)
		assert_gt(c.g, c.r, "%s canopy should read as green" % id)
		assert_gt(c.g, c.b, "%s canopy should read as green" % id)
		seen[c] = true
	assert_eq(seen.size(), TreeSpecies.IDS.size(), "every species should have its own canopy colour")


func test_fruit_colours_are_distinct_per_species():
	var seen := {}
	for id in TreeSpecies.IDS:
		seen[TreeSpecies.fruit_color_for(id)] = true
	assert_eq(seen.size(), TreeSpecies.IDS.size(), "every species should have its own fruit colour")


## Real cherries ripen fast (a couple of months from bloom); real walnuts
## take a long, slow season. Grounded ordering, not just "different numbers".
func test_cherry_ripens_faster_than_walnut():
	assert_lt(
		TreeSpecies.ripening_multiplier_for("cherry"),
		TreeSpecies.ripening_multiplier_for("walnut")
	)


## Real apples/cherries are heavier, more prolific bearers than a walnut's
## comparatively small, high-value nut crop.
func test_apple_and_cherry_out_yield_walnut():
	var walnut_yield: float = TreeSpecies.yield_multiplier_for("walnut")
	assert_gt(TreeSpecies.yield_multiplier_for("apple"), walnut_yield)
	assert_gt(TreeSpecies.yield_multiplier_for("cherry"), walnut_yield)


func test_an_unknown_species_falls_back_rather_than_crashing():
	assert_gt(TreeSpecies.display_name_for("dragonfruit").length(), 0)
	var c: Color = TreeSpecies.canopy_color_for("dragonfruit")
	assert_gt(c.g, c.r)
