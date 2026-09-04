extends GutTest

## The flowering plants a meadow can grow (see docs/concept/flora.md).

const FlowerSpecies = preload("res://src/world/flower_species.gd")


# -- varieties ---------------------------------------------------------------

## A species is not one colour. Crocuses come up purple, white, yellow and
## lilac from the same bed; tulips are the classic case of a species bred into
## a whole shelf of colours. A meadow where every crocus is the identical
## purple reads as copy-paste, which is what a hand-planted bed does not look
## like.
func test_a_species_can_come_up_in_more_than_one_colour():
	var seen := {}
	for seed_value in 60:
		seen[FlowerSpecies.tint_for("crocus", seed_value).to_html()] = true
	assert_gt(seen.size(), 1, "every crocus being the same purple reads as copy-paste")


## ...but an individual flower does not change colour. The tint is a property
## of the plant, derived from its own seed, not rolled per frame.
func test_a_given_flower_keeps_its_colour():
	for seed_value in [0, 7, 91, 5000]:
		assert_eq(
			FlowerSpecies.tint_for("crocus", seed_value),
			FlowerSpecies.tint_for("crocus", seed_value)
		)


func test_every_tint_is_one_the_species_actually_declares():
	for species in FlowerSpecies.IDS:
		var declared := {}
		for tint in FlowerSpecies.tints_for(species):
			declared[tint.to_html()] = true
		for seed_value in 40:
			assert_true(
				declared.has(FlowerSpecies.tint_for(species, seed_value).to_html()),
				"%s came up in a colour it does not have" % species
			)


## Every species declares at least its own canonical colour, so a species
## added later with no variety list still renders.
func test_every_species_has_at_least_one_tint():
	for species in FlowerSpecies.IDS:
		assert_gt(FlowerSpecies.tints_for(species).size(), 0, species)


## The canonical colour is still the species' identity -- it is what the
## minimap, the scent overlay and anything else that wants "the colour of a
## rose" gets, and it stays the first variety.
func test_the_canonical_colour_is_one_of_the_varieties():
	for species in FlowerSpecies.IDS:
		assert_eq(FlowerSpecies.tints_for(species)[0], FlowerSpecies.color_for(species), species)


## A red tulip and a white one are still both tulips: variety changes the
## colour, never the species' identity, size or scent.
func test_variety_does_not_change_what_the_species_is():
	# Reading the same species twice must give the same answer regardless of
	# which variety any individual plant came up as -- variety lives on the
	# plant, not on the species.
	var scent: float = FlowerSpecies.scent_strength("tulip", "spring")
	var height: float = FlowerSpecies.height_cm_for("tulip")
	for seed_value in 20:
		FlowerSpecies.tint_for("tulip", seed_value)
	assert_eq(FlowerSpecies.scent_strength("tulip", "spring"), scent)
	assert_eq(FlowerSpecies.height_cm_for("tulip"), height)


## An unknown id still yields a colour rather than crashing the field, the
## same fail-safe the rest of the lookups use.
func test_an_unknown_species_still_has_a_colour():
	assert_gt(FlowerSpecies.tints_for("nonesuch").size(), 0)


# -- what to call one --------------------------------------------------------
#
# Reported live: flowers "still don't [show] hover tooltips". A tooltip needs a
# name, and the roster is where a species' name belongs -- alongside its
# colour, its scent and its stature.

func test_every_species_has_a_name_fit_to_show_a_player():
	for id in FlowerSpecies.IDS:
		var name := FlowerSpecies.display_name(id)
		assert_ne(name, "", "%s has no name" % id)
		assert_eq(name, name.strip_edges(), "%s's name has loose whitespace" % id)
		assert_eq(
			name.substr(0, 1), name.substr(0, 1).to_upper(),
			"%s reads as '%s' -- a tooltip is prose, not an id" % [id, name]
		)


func test_no_two_species_share_a_name():
	var seen := {}
	for id in FlowerSpecies.IDS:
		var name := FlowerSpecies.display_name(id)
		assert_false(seen.has(name), "two species both read as '%s'" % name)
		seen[name] = true


## Same fail-safe shape as every other lookup here: an odd id gives a plain
## answer rather than an empty tooltip or a crash.
func test_an_unknown_species_still_has_something_to_call_it():
	assert_ne(FlowerSpecies.display_name("not_a_species"), "")
