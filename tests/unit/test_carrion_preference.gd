extends GutTest

## docs/concept/monsters.md, entry 11 -- the Nachzehrer: the one species for
## which a nearby corpse outranks a live target. Every predator already
## notices carrion (CreatureMarker._scan_carrion_stimuli, docs/concept/
## carrion.md's opportunistic-scavenging gap); this names which species
## treats it as more than just one more option alongside a live target.
## Pure: which species this applies to, nothing about distance, stimuli, or
## a live creature -- see test_nachzehrer.gd for the CreatureMarker
## integration half (the actual stimulus filtering).

const CarrionPreference = preload("res://src/gameplay/carrion_preference.gd")


func test_only_the_nachzehrer_prefers_carrion():
	assert_true(CarrionPreference.prefers_carrion("nachzehrer"))


func test_no_ordinary_predator_prefers_carrion():
	for species in [
		"wolf", "lynx", "bear", "lion", "jaguar", "jackal", "arctic_fox", "mountain_lion", "curupira", "alp",
	]:
		assert_false(CarrionPreference.prefers_carrion(species), species)


func test_an_unknown_species_does_not_prefer_carrion():
	assert_false(CarrionPreference.prefers_carrion("not_a_real_species"))
