extends GutTest

## See docs/concept/soil_fauna.md "Crushed underfoot: weight-emergent worm
## mortality". Real average adult body mass, kilograms, per AnimalAnatomy
## species -- the mass term the worm-crush momentum calculation reads.

const CreatureMass = preload("res://src/world/creature_mass.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")


func test_mass_is_positive_for_every_real_species():
	for species in AnimalAnatomy.SPECIES:
		assert_gt(CreatureMass.mass_kg_for(species), 0.0, "%s should have a positive mass" % species)


## The whole point of this table: a mouse is nowhere near a horse's own
## real-world mass. Pinned as a real inequality, not exact numbers, so
## re-tuning either figure later can't silently break the calibration
## this entire mechanic exists to draw.
func test_a_horse_is_far_heavier_than_a_mouse():
	assert_gt(CreatureMass.mass_kg_for("horse"), CreatureMass.mass_kg_for("mouse") * 1000.0)


func test_a_horse_is_heavier_than_a_deer():
	assert_gt(CreatureMass.mass_kg_for("horse"), CreatureMass.mass_kg_for("deer"))


## Real reference figures, not derived from world_scale -- a horse's own
## world_scale (1.2) is only a fifth again as much as a deer's (0.96), for
## on-screen legibility, nowhere near its real ~7x mass -- so this table
## must carry real, independently-cited numbers for the animals that
## actually matter to the calibration, not a formula that would badly
## under-represent a horse specifically (verified directly: cubing
## world_scale ratios alone would put a "horse" under 150kg, nothing like
## a real one).
func test_horse_mass_is_a_real_reference_figure_not_derived_from_world_scale():
	assert_gt(CreatureMass.mass_kg_for("horse"), 400.0)
	assert_lt(CreatureMass.mass_kg_for("horse"), 700.0)


## A mouse and squirrel are real, tiny animals -- comfortably under a
## human's own 1kg mark, the scale this whole mechanic needs a "definitely
## too light to matter" example at.
func test_small_creatures_are_genuinely_tiny():
	assert_lt(CreatureMass.mass_kg_for("mouse"), 1.0)
	assert_lt(CreatureMass.mass_kg_for("squirrel"), 1.0)


## The player's own mass reuses StoneSize.AVERAGE_BODY_MASS_KG directly --
## the same reference figure this codebase already established for a
## human, not a second, independent guess.
func test_player_mass_matches_stone_sizes_own_human_reference():
	const StoneSize = preload("res://src/world/stone_size.gd")
	assert_almost_eq(CreatureMass.PLAYER_MASS_KG, StoneSize.AVERAGE_BODY_MASS_KG, 0.001)


## Mythical world bosses have no real animal to cite a mass for -- they
## fall back to their own world_scale, cubed against a real land mammal's
## own mass/scale ratio (see mass_kg_for's own doc comment). Pinned as a
## real relationship (a bigger boss reads as heavier than a smaller one),
## not an exact number nothing can verify.
func test_mythical_bosses_scale_by_their_own_world_scale():
	var squallmaw_scale: float = AnimalAnatomy.profile_for("squallmaw").world_scale
	var kraken_scale: float = AnimalAnatomy.profile_for("kraken").world_scale
	if kraken_scale > squallmaw_scale:
		assert_gt(CreatureMass.mass_kg_for("kraken"), CreatureMass.mass_kg_for("squallmaw"))
	else:
		assert_gte(CreatureMass.mass_kg_for("kraken"), CreatureMass.mass_kg_for("squallmaw"))


func test_unknown_species_falls_back_rather_than_crashing():
	assert_gt(CreatureMass.mass_kg_for("not_a_real_species"), 0.0)
