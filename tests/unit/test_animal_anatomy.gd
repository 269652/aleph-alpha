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


## Reported: "the horse should have a straighter back" -- a real horse's
## topline reads as level, unlike the humped rooters (boar/camel/bear) that
## carry extra rise over the shoulders on purpose.
func test_a_horses_back_is_level_not_humped():
	var horse := AnimalAnatomy.profile_for("horse")
	var camel := AnimalAnatomy.profile_for("camel")
	var boar := AnimalAnatomy.profile_for("boar")
	assert_almost_eq(horse.shoulder_hump, 0.0, 0.001, "a horse's topline should read as level")
	assert_lt(horse.shoulder_hump, camel.shoulder_hump)
	assert_lt(horse.shoulder_hump, boar.shoulder_hump)


## Reported: "less flat head" -- the horse's head should read as deep
## (forehead-to-jaw), not a paper-thin plank with a long snout tacked on.
func test_a_horses_head_is_not_flat():
	var horse := AnimalAnatomy.profile_for("horse")
	var deer := AnimalAnatomy.profile_for("deer")
	assert_gt(horse.head_height, deer.head_height, "a horse's head should read as deep, not flat")


## Reported again later, alongside "less flat head, more horsish" and
## "slightly smaller legs" -- shoulder_hump alone (see the level-back test
## above) wasn't enough: ProceduralAnimalSprite._paint_animal attaches every
## species' neck partway down the body's side by default, and a horse's
## unusually long neck made that fixed attachment point read as a notch cut
## into an otherwise-level topline instead of one continuous slope from
## withers to poll. neck_attach_height lets a species attach its neck closer
## to the back's own top edge; only horse sets it today.
func test_a_horses_neck_attaches_near_the_top_of_its_back_not_partway_down():
	var horse := AnimalAnatomy.profile_for("horse")
	var deer := AnimalAnatomy.profile_for("deer")
	assert_gt(
		horse.get("neck_attach_height", 0.45), 0.6,
		"a horse's neck should attach near the top of the back, not partway down"
	)
	# Every other species keeps today's implicit 0.45 (see
	# ProceduralAnimalSprite._paint_animal's own .get() fallback) -- this is
	# an opt-in per-species override, not a default every animal now gets.
	assert_false(deer.has("neck_attach_height"))


## A real horse's head is long and narrow, not a short round blob -- the
## same "more horsish" report as the flatness fix above, but about
## elongation rather than depth. Compared proportionally (length ÷ height)
## against a generic grazer rather than as a raw length, since a longer head
## on a bigger animal alone wouldn't prove it reads as more ELONGATED.
func test_a_horses_head_is_more_elongated_than_a_generic_grazers():
	var horse := AnimalAnatomy.profile_for("horse")
	var herbivore := AnimalAnatomy.profile_for("herbivore")
	var horse_ratio: float = horse.head_length / horse.head_height
	var herbivore_ratio: float = herbivore.head_length / herbivore.head_height
	assert_gt(horse_ratio, herbivore_ratio, "a horse's head should read as elongated, not a short round blob")


## Reported: "slightly smaller legs" -- clarified as "shorter legs, not
## thinner" after a first pass thinned leg_thickness instead. leg_thickness
## is intentionally left alone here; only length comes down, and only
## partway -- a horse should still read as taller-legged than a deer, just
## not to its former exaggerated degree.
func test_a_horses_legs_are_shorter_than_before_but_still_taller_than_a_deers():
	var horse := AnimalAnatomy.profile_for("horse")
	var deer := AnimalAnatomy.profile_for("deer")
	var herbivore := AnimalAnatomy.profile_for("herbivore")
	assert_lt(horse.leg_length, 0.38, "a horse's legs should be shorter than the original exaggerated length")
	assert_gt(horse.leg_length, deer.leg_length, "a horse should still stand taller-legged than a deer")
	assert_eq(horse.leg_thickness, herbivore.leg_thickness, "leg thickness should be untouched -- shorter, not thinner")


## A deer is 0.8x the size of a horse -- requested directly ("make deer 0.8
## of horse size"). Pinned as a RATIO, not as a bare number on each: the two
## are meant to stay in proportion, so re-sizing the horse without re-sizing
## the deer should fail here rather than silently drift.
func test_a_deer_is_four_fifths_the_size_of_a_horse():
	var deer: float = AnimalAnatomy.profile_for("deer").world_scale
	var horse: float = AnimalAnatomy.profile_for("horse").world_scale
	assert_almost_eq(deer / horse, 0.8, 0.01)


## Reported gap: jackal/arctic_fox/mountain_lion/lion already have tuned
## stats (creature_info.gd) and already spawn from CreatureRenderer's biome
## pools, but had no AnimalAnatomy profile at all -- profile_for() silently
## fell back to the generic herbivore build (wrong world_scale/body plan for
## a predator), and ConsoleSpecies.resolve() (which validates against
## AnimalAnatomy.SPECIES) rejected "/spawn jackal" outright.
func test_the_four_level_backed_predators_have_profiles():
	for species in ["jackal", "arctic_fox", "mountain_lion", "lion"]:
		assert_true(AnimalAnatomy.has_profile(species), species)


## Each of the four must read as its own real-world body plan, not a copy
## of an existing predator.
func test_jackal_is_small_lean_and_big_eared():
	var jackal := AnimalAnatomy.profile_for("jackal")
	var lynx := AnimalAnatomy.profile_for("lynx")
	var wolf := AnimalAnatomy.profile_for("wolf")
	assert_lt(jackal.world_scale, 1.0, "a jackal is a small canid")
	assert_gte(jackal.world_scale, lynx.world_scale, "comparable to or a touch above a lynx")
	assert_gt(jackal.ear_size, wolf.ear_size, "jackals have notably big ears")
	assert_lt(jackal.tail_length, wolf.tail_length, "a jackal's tail is shorter than a wolf's")


func test_arctic_fox_is_the_smallest_and_stockiest_with_a_long_tail():
	var fox := AnimalAnatomy.profile_for("arctic_fox")
	for species in ["jackal", "mountain_lion", "lion"]:
		assert_lt(
			fox.world_scale, AnimalAnatomy.profile_for(species).world_scale,
			"arctic fox should be the smallest of the four"
		)
	var wolf := AnimalAnatomy.profile_for("wolf")
	var jackal := AnimalAnatomy.profile_for("jackal")
	assert_lt(fox.leg_length, wolf.leg_length, "short legs minimize surface area")
	assert_lt(fox.head_length, wolf.head_length, "short muzzle minimizes surface area")
	assert_gt(fox.tail_length, jackal.tail_length, "a very long bushy tail relative to its small body")


func test_mountain_lion_is_leaner_than_jaguar():
	var cougar := AnimalAnatomy.profile_for("mountain_lion")
	var jaguar := AnimalAnatomy.profile_for("jaguar")
	assert_eq(cougar.tail, AnimalAnatomy.TAIL_FLOWING, "a long flowing tail like a jaguar's")
	assert_gte(cougar.body_length, jaguar.body_length, "long-bodied, at or beyond a jaguar's")
	assert_lt(cougar.barrel_squareness, jaguar.barrel_squareness, "leaner, less bulky than a jaguar")
	assert_lt(cougar.shoulder_hump, jaguar.shoulder_hump, "leaner, less bulky than a jaguar")


## Scoped to the level-backed predator profiles (bear is a separate, low
## bulky-rooter build, not part of this family -- see the file's section
## comments), matching the brief's "highest world_scale of any predator
## profile".
func test_lion_is_the_biggest_maned_predator():
	var lion := AnimalAnatomy.profile_for("lion")
	for species in ["wolf", "lynx", "jaguar", "predator", "jackal", "arctic_fox", "mountain_lion"]:
		assert_gt(
			lion.world_scale, AnimalAnatomy.profile_for(species).world_scale,
			"a lion should be the biggest of the level-backed predators: %s" % species
		)
	assert_true(lion.has_mane, "real male lions have manes")


# -- squirrel: a genuine 22nd species, not a reskin of mouse -----------------
#
# A real tree-nut forager (see docs/concept/flora.md's disperser-vs-predator
# tension and docs/concept/ecosystem_dynamics.md's Species roster section):
# small, short-legged like a mouse, but bigger, and defined above all by a
# large expressive bushy tail -- proportionally one of the most distinctive
# features of a real squirrel.

func test_squirrel_has_a_profile():
	assert_true(AnimalAnatomy.has_profile("squirrel"))
	assert_true(AnimalAnatomy.SPECIES.has("squirrel"))


func test_squirrel_is_small_and_short_legged_but_bigger_than_a_mouse():
	var squirrel := AnimalAnatomy.profile_for("squirrel")
	var mouse := AnimalAnatomy.profile_for("mouse")
	assert_lt(squirrel.world_scale, 1.0, "a squirrel is a small rodent")
	assert_gt(squirrel.world_scale, mouse.world_scale, "a squirrel is bigger than a mouse")
	assert_lt(squirrel.leg_length, 0.15, "real squirrels have short legs relative to body")


## A squirrel's tail is proportionally one of its most distinctive real-world
## features -- LONGER relative to its own body than any other profile's,
## including mouse's own already-long thin cord tail, but bushy rather than
## thin (see AnimalAnatomy.TAIL_BUSHY).
func test_squirrel_has_a_bushy_tail_longer_relative_to_its_body_than_anything_else():
	var squirrel := AnimalAnatomy.profile_for("squirrel")
	assert_eq(squirrel.tail, AnimalAnatomy.TAIL_BUSHY)
	var squirrel_ratio: float = squirrel.tail_length / squirrel.body_length
	for species in AnimalAnatomy.SPECIES:
		if species == "squirrel":
			continue
		var other := AnimalAnatomy.profile_for(species)
		var other_ratio: float = other.tail_length / other.body_length
		assert_gt(
			squirrel_ratio, other_ratio,
			"squirrel's tail should be proportionally longer than %s's" % species
		)
