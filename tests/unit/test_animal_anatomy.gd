extends GutTest

## AnimalAnatomy: per-species body proportions, so animals are built from
## real anatomy rather than from a handful of shared hand-drawn bitmaps.
##
## Before this, `herbivore`, `horse`, `deer`, `camel`, `reindeer` and `goat`
## all mapped to ONE "deer_shape" bitmap and differed only in coat colour --
## reported as "herbivore, deer and horse look exactly the same". Proportions
## are expressed as fractions of the canvas, so one profile draws correctly
## at any art resolution.

const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")


func test_every_known_species_has_a_profile():
	for species in AnimalAnatomy.SPECIES:
		assert_true(AnimalAnatomy.has_profile(species), species)


func test_an_unknown_species_falls_back_without_crashing():
	var profile := AnimalAnatomy.profile_for("not_a_real_animal")
	assert_not_null(profile)
	assert_gt(profile.body_length, 0.0)


## The reported bug: these three shared one silhouette. Every pair must now
## differ in more than just colour.
func test_horse_deer_and_generic_herbivore_have_distinct_bodies():
	var horse := AnimalAnatomy.profile_for("horse")
	var deer := AnimalAnatomy.profile_for("deer")
	var herbivore := AnimalAnatomy.profile_for("herbivore")
	assert_ne(horse, deer, "horse and deer must not share a body plan")
	assert_ne(horse, herbivore, "horse and herbivore must not share a body plan")
	assert_ne(deer, herbivore, "deer and herbivore must not share a body plan")


## Real-life proportions, not arbitrary differences: a horse is the tall
## long-necked one, a deer the slender antlered one.
func test_a_horse_is_taller_and_longer_necked_than_a_deer():
	var horse := AnimalAnatomy.profile_for("horse")
	var deer := AnimalAnatomy.profile_for("deer")
	assert_gt(horse.leg_length, deer.leg_length, "horses stand taller")
	assert_gt(horse.neck_length, deer.neck_length, "horses have longer necks")


func test_only_a_horse_has_a_mane_and_a_flowing_tail():
	assert_true(AnimalAnatomy.profile_for("horse").has_mane)
	assert_false(AnimalAnatomy.profile_for("deer").has_mane)
	assert_eq(AnimalAnatomy.profile_for("horse").tail, AnimalAnatomy.TAIL_FLOWING)
	assert_ne(AnimalAnatomy.profile_for("deer").tail, AnimalAnatomy.TAIL_FLOWING)


func test_headgear_matches_the_real_animal():
	assert_eq(AnimalAnatomy.profile_for("deer").headgear, AnimalAnatomy.HEADGEAR_ANTLERS)
	assert_eq(AnimalAnatomy.profile_for("goat").headgear, AnimalAnatomy.HEADGEAR_HORNS)
	assert_eq(AnimalAnatomy.profile_for("boar").headgear, AnimalAnatomy.HEADGEAR_TUSKS)
	assert_eq(AnimalAnatomy.profile_for("horse").headgear, AnimalAnatomy.HEADGEAR_NONE)


## A boar is the low, bulky, humped one -- the opposite build to a deer.
func test_a_boar_is_low_slung_and_humped_unlike_a_deer():
	var boar := AnimalAnatomy.profile_for("boar")
	var deer := AnimalAnatomy.profile_for("deer")
	assert_lt(boar.leg_length, deer.leg_length, "boars are short-legged")
	assert_gt(boar.shoulder_hump, deer.shoulder_hump, "boars have a shoulder hump")
	assert_gt(boar.body_height, deer.body_height, "boars are bulkier")


func test_a_camel_has_the_biggest_hump_of_all():
	var camel := AnimalAnatomy.profile_for("camel")
	for species in AnimalAnatomy.SPECIES:
		if species == "camel":
			continue
		assert_gte(camel.shoulder_hump, AnimalAnatomy.profile_for(species).shoulder_hump, species)


func test_a_mouse_is_the_smallest_and_a_bear_among_the_bulkiest():
	var mouse := AnimalAnatomy.profile_for("mouse")
	var bear := AnimalAnatomy.profile_for("bear")
	assert_lt(mouse.body_length, bear.body_length)
	assert_lt(mouse.leg_length, bear.leg_length)
	assert_gt(mouse.ear_size, bear.ear_size, "mice have oversized ears for their head")


## Every proportion is a canvas fraction, so a profile renders correctly at
## any art resolution (see docs/concept/art_resolution.md).
func test_all_proportions_are_canvas_fractions():
	for species in AnimalAnatomy.SPECIES:
		var p := AnimalAnatomy.profile_for(species)
		for field in ["body_length", "body_height", "neck_length", "leg_length", "head_length"]:
			assert_between(p.get(field), 0.0, 1.0, "%s.%s should be a canvas fraction" % [species, field])


func test_profiles_are_deterministic():
	assert_eq(AnimalAnatomy.profile_for("wolf"), AnimalAnatomy.profile_for("wolf"))
