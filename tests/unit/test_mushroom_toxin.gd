extends GutTest

## MushroomToxin (see docs/concept/mushrooms.md's "Eating one"). Same shape
## as VenomModel -- DebuffStack tracks stacking/ticking; this module only
## adds "how much does N stacks hurt per second" -- plus a per-REAL-SPECIES
## severity VenomModel didn't need (a snake bite is one snake; mushroom
## toxicity varies enormously by real species).

const MushroomToxin = preload("res://src/gameplay/mushroom_toxin.gd")


# -- severity, per real species ------------------------------------------

func test_death_cap_is_more_severe_than_fly_agaric():
	# Real: amatoxin poisoning (Death Cap) is far more dangerous than
	# muscimol/ibotenic-acid poisoning (Fly Agaric) -- a real, grounded
	# ordering, not two arbitrary numbers.
	assert_gt(MushroomToxin.severity_for("death_cap"), MushroomToxin.severity_for("fly_agaric"))


func test_a_non_toxic_species_has_zero_severity():
	for id in ["chanterelle", "porcini", "puffball"]:
		assert_eq(MushroomToxin.severity_for(id), 0.0, "%s is a real edible, not toxic" % id)


func test_an_unknown_species_has_zero_severity():
	assert_eq(MushroomToxin.severity_for("portobello"), 0.0)


# -- damage per second, N stacks ------------------------------------------

func test_no_stacks_means_no_damage():
	var toxin := MushroomToxin.new()
	assert_eq(toxin.damage_per_second(0, "death_cap"), 0.0)


func test_a_non_toxic_species_never_hurts_however_many_stacks():
	var toxin := MushroomToxin.new()
	assert_eq(toxin.damage_per_second(MushroomToxin.MAX_STACKS, "chanterelle"), 0.0)


func test_more_stacks_hurts_more_of_the_same_toxic_species():
	var toxin := MushroomToxin.new()
	var one: float = toxin.damage_per_second(1, "death_cap")
	var two: float = toxin.damage_per_second(2, "death_cap")
	assert_gt(two, one)


func test_damage_is_clamped_to_max_stacks():
	var toxin := MushroomToxin.new()
	var at_max: float = toxin.damage_per_second(MushroomToxin.MAX_STACKS, "death_cap")
	var beyond: float = toxin.damage_per_second(MushroomToxin.MAX_STACKS + 5, "death_cap")
	assert_eq(beyond, at_max)


func test_death_cap_hurts_more_than_fly_agaric_at_the_same_stack_count():
	var toxin := MushroomToxin.new()
	var death_cap: float = toxin.damage_per_second(MushroomToxin.MAX_STACKS, "death_cap")
	var fly_agaric: float = toxin.damage_per_second(MushroomToxin.MAX_STACKS, "fly_agaric")
	assert_gt(death_cap, fly_agaric)
