extends GutTest

## Real average adult body mass, kilograms, per fish species (see
## docs/concept/aquatic_foraging.md's "Revised (2026-09-07)" -- the target
## FishGrowth grows a fish's own mass_kg toward).
##
## Mirrors CreatureMass._REAL_MASS_KG's own convention exactly: a real,
## commonly-cited reference figure for that real species, never invented.

const FishMass = preload("res://src/world/fish_mass.gd")
const ProceduralFishSprite = preload("res://src/rendering/procedural_fish_sprite.gd")


func test_bluegill_adult_mass_is_a_real_reference_weight():
	assert_almost_eq(FishMass.mass_kg_for("bluegill"), 0.25, 0.0001)


func test_trout_adult_mass_is_a_real_reference_weight():
	assert_almost_eq(FishMass.mass_kg_for("trout"), 0.5, 0.0001)


func test_goldfish_adult_mass_is_a_real_reference_weight():
	assert_almost_eq(FishMass.mass_kg_for("goldfish"), 0.4, 0.0001)


func test_koi_adult_mass_is_a_real_reference_weight():
	assert_almost_eq(FishMass.mass_kg_for("koi"), 3.5, 0.0001)


## Real ornamental koi genuinely dwarf the other three species -- the one
## real-world size fact this table is grounded to reproduce.
func test_koi_is_the_largest_species_by_a_wide_margin():
	var koi := FishMass.mass_kg_for("koi")
	for species in ["bluegill", "trout", "goldfish"]:
		assert_gt(koi, FishMass.mass_kg_for(species) * 2.0, "koi should clearly dwarf %s" % species)


## Every species that can actually spawn must have a real adult mass, or
## FishGrowth has nothing real to grow it toward.
func test_every_spawnable_fish_has_a_real_adult_mass():
	for species in ProceduralFishSprite.SPECIES_IDS:
		assert_gt(FishMass.mass_kg_for(species), 0.0, "%s has no adult mass" % species)


func test_an_unknown_species_falls_back_rather_than_erroring():
	assert_gt(FishMass.mass_kg_for("coelacanth"), 0.0)
