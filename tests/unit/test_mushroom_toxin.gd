extends GutTest

## MushroomToxin (see docs/concept/mushrooms.md's "Eating one"). Same shape
## as VenomModel -- DebuffStack tracks stacking/ticking; this module only
## adds "how much does N stacks hurt per second" -- plus a per-REAL-SPECIES
## severity VenomModel didn't need (a snake bite is one snake; mushroom
## toxicity varies enormously by real species).
##
## Roster revised (see mushrooms.md's merge note) to match the real
## illustrated art delivered: Fly Agaric and Psilocybe are the two real
## psychoactive species now (replacing the originally-designed Death Cap,
## which no art exists for) -- neither is typically lethal, but real
## ibotenic-acid/muscimol poisoning (Fly Agaric) carries more physical risk
## than psilocybin's primarily perceptual effects (Psilocybe), so the
## ordering survives with Fly Agaric now the more severe of the two.

const MushroomToxin = preload("res://src/gameplay/mushroom_toxin.gd")


# -- severity, per real species ------------------------------------------

func test_fly_agaric_is_more_severe_than_psylo():
	# Real: ibotenic-acid/muscimol poisoning (Fly Agaric) carries more real
	# physical risk (sedation, GI distress, rare severe reactions) than
	# psilocybin poisoning (Psilocybe), which is primarily perceptual and
	# rarely physically dangerous -- a real, grounded ordering, not two
	# arbitrary numbers.
	assert_gt(MushroomToxin.severity_for("fly_agaric"), MushroomToxin.severity_for("psylo"))


func test_psylo_is_still_genuinely_toxic_not_zero():
	# Unlike the edible species below, Psilocybe is real and psychoactive --
	# the milder of the roster's two toxic species, not a non-event.
	assert_gt(MushroomToxin.severity_for("psylo"), 0.0)


func test_a_non_toxic_species_has_zero_severity():
	for id in ["black_trumpet", "champignon", "chanterelle", "parasol"]:
		assert_eq(MushroomToxin.severity_for(id), 0.0, "%s is a real edible, not toxic" % id)


func test_an_unknown_species_has_zero_severity():
	assert_eq(MushroomToxin.severity_for("portobello"), 0.0)


# -- damage per second, N stacks ------------------------------------------

func test_no_stacks_means_no_damage():
	var toxin := MushroomToxin.new()
	assert_eq(toxin.damage_per_second(0, "fly_agaric"), 0.0)


func test_a_non_toxic_species_never_hurts_however_many_stacks():
	var toxin := MushroomToxin.new()
	assert_eq(toxin.damage_per_second(MushroomToxin.MAX_STACKS, "chanterelle"), 0.0)


func test_more_stacks_hurts_more_of_the_same_toxic_species():
	var toxin := MushroomToxin.new()
	var one: float = toxin.damage_per_second(1, "fly_agaric")
	var two: float = toxin.damage_per_second(2, "fly_agaric")
	assert_gt(two, one)


func test_damage_is_clamped_to_max_stacks():
	var toxin := MushroomToxin.new()
	var at_max: float = toxin.damage_per_second(MushroomToxin.MAX_STACKS, "fly_agaric")
	var beyond: float = toxin.damage_per_second(MushroomToxin.MAX_STACKS + 5, "fly_agaric")
	assert_eq(beyond, at_max)


func test_fly_agaric_hurts_more_than_psylo_at_the_same_stack_count():
	var toxin := MushroomToxin.new()
	var fly_agaric: float = toxin.damage_per_second(MushroomToxin.MAX_STACKS, "fly_agaric")
	var psylo: float = toxin.damage_per_second(MushroomToxin.MAX_STACKS, "psylo")
	assert_gt(fly_agaric, psylo)
