extends GutTest

## Per-species diet for every ambient flyer (see docs/concept/soil_fauna.md's
## "Bird diet, as a first-class concept").
##
## This is the table that makes "robins eat worms, sparrows eat seeds" a
## structural fact rather than an `if species == "robin"` buried in a marker:
## a species with worms in its diet is handed a worm world and a ground-forage
## brain at spawn time, and one without simply cannot hunt worms.
##
## Deliberately NOT CreatureInfo.DIET_BY_SPECIES, which is HUD flavour text
## ("Grazer"/"Hunter") that nothing behavioural reads.

const FlyerDiet = preload("res://src/gameplay/flyer_diet.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const ProceduralBirdSprite = preload("res://src/rendering/procedural_bird_sprite.gd")


# -- the headline claim -----------------------------------------------------

func test_robins_eat_worms():
	assert_true(FlyerDiet.eats("robin", FlyerDiet.FOOD_WORMS))


func test_sparrows_eat_seeds():
	assert_true(FlyerDiet.eats("sparrow", FlyerDiet.FOOD_SEEDS))


## The explicit negative half of "diets are per species". A sparrow sharing a
## meadow with a robin must never hunt worms, however the shared marker code
## changes.
func test_sparrows_do_not_eat_worms():
	assert_false(FlyerDiet.eats("sparrow", FlyerDiet.FOOD_WORMS))


func test_robins_do_not_eat_seeds():
	assert_false(FlyerDiet.eats("robin", FlyerDiet.FOOD_SEEDS))


## Real robins are genuine omnivores that switch to soft fruit/berries once
## it's available (a second diet entry FlyerDiet's own doc comment already
## flags as the natural next step for the worm-eating robin -- see
## FOOD_FRUIT).
func test_robins_also_eat_fallen_fruit():
	assert_true(FlyerDiet.eats("robin", FlyerDiet.FOOD_FRUIT))


## Widened to include blackbird (see docs/concept/seasonal_behavior.md,
## "Blackbird: new species, real population, real diet shift") -- a real,
## deliberate second real thrush with the same genuine worm-hunting
## specialism as robin, the same kind of widening this file's own ants
## already went through (robin-only, then deliberately given to both
## ground-foraging songbirds once a second real fit existed). Sparrow's
## granivore bill still makes it a poor real-world fit, so it stays out.
func test_only_real_thrushes_hunt_worms_among_the_songbirds():
	var worm_eaters: Array = []
	for species in AmbientFlyerRenderer.BIRD_SPECIES_POOL:
		if FlyerDiet.eats(species, FlyerDiet.FOOD_WORMS):
			worm_eaters.append(species)
	assert_eq(worm_eaters, ["robin", "blackbird"])


## Real robins are famous caterpillar-hunters -- caterpillars are what a
## robin feeds its own chicks more than almost anything else. A second real
## ground-forage food alongside worms/fruit (see FOOD_WORMS/FOOD_FRUIT
## above), not a new mechanism: this reuses the identical descend/sit/peck
## ground-forage cycle those already drive.
func test_robins_also_eat_caterpillars():
	assert_true(FlyerDiet.eats("robin", FlyerDiet.FOOD_CATERPILLARS))


## Sparrow's granivore bill still makes it a poor real-world fit here, but
## widened to include blackbird -- a real, deliberate second real thrush
## caterpillar-hunter (see docs/concept/seasonal_behavior.md, "Blackbird:
## new species, real population, real diet shift"), the same "started
## narrow, later widened for a real reason" precedent this file's own ants
## already went through.
func test_only_real_thrushes_eat_caterpillars_among_the_songbirds():
	var caterpillar_eaters: Array = []
	for species in AmbientFlyerRenderer.BIRD_SPECIES_POOL:
		if FlyerDiet.eats(species, FlyerDiet.FOOD_CATERPILLARS):
			caterpillar_eaters.append(species)
	assert_eq(caterpillar_eaters, ["robin", "blackbird"])


func test_caterpillars_are_a_ground_food():
	assert_true(FlyerDiet.GROUND_FOODS.has(FlyerDiet.FOOD_CATERPILLARS))


## Reported live: "birds should forage live ants". Unlike caterpillars
## (robin-only -- a genuinely visual, foliage/ground-gleaning hunt closer
## to a robin's own worm-hunting specialism), ants are deliberately given
## to BOTH ground-foraging songbirds: real American robins are documented
## generalist ground insectivores that do take ants among their varied
## invertebrate diet, but real house sparrows -- despite being primarily
## granivorous -- are ALSO well-documented opportunistic ant-eaters,
## arguably proportionally more so than robins, precisely because
## sparrows spend so much of their time working bare ground and short
## grass where ant trails and mounds are common, rather than visually
## hunting larger, specific prey the way a robin's worm/caterpillar
## hunting already does. No strong real-world reason favours excluding
## either, unlike the caterpillar case.
func test_robins_also_eat_ants():
	assert_true(FlyerDiet.eats("robin", FlyerDiet.FOOD_ANTS))


func test_sparrows_also_eat_ants():
	assert_true(FlyerDiet.eats("sparrow", FlyerDiet.FOOD_ANTS))


func test_ants_are_a_ground_food():
	assert_true(FlyerDiet.GROUND_FOODS.has(FlyerDiet.FOOD_ANTS))


func test_the_kingfisher_does_not_eat_ants():
	assert_false(FlyerDiet.eats("kingfisher", FlyerDiet.FOOD_ANTS))


# -- the rest of the roster -------------------------------------------------

func test_the_kingfisher_eats_fish_and_nothing_on_the_ground():
	assert_true(FlyerDiet.eats("kingfisher", FlyerDiet.FOOD_FISH))
	assert_false(FlyerDiet.eats("kingfisher", FlyerDiet.FOOD_WORMS))


## Pollinator wiring keys off this too, so the butterflies/bees that already
## forage nectar must be in the table -- otherwise adding the table would
## silently switch off scent steering.
func test_every_pollinator_drinks_nectar():
	for species in AmbientFlyerRenderer.BUTTERFLY_SPECIES_POOL:
		assert_true(
			FlyerDiet.eats(species, FlyerDiet.FOOD_NECTAR),
			"%s should be a nectar feeder" % species
		)


func test_no_pollinator_hunts_worms():
	for species in AmbientFlyerRenderer.BUTTERFLY_SPECIES_POOL:
		assert_false(FlyerDiet.eats(species, FlyerDiet.FOOD_WORMS))


func test_no_bird_drinks_nectar():
	for species in ProceduralBirdSprite.SPECIES_IDS:
		assert_false(FlyerDiet.eats(species, FlyerDiet.FOOD_NECTAR))


## Every species that can actually spawn must be in the table, or its diet is
## silently empty and it quietly stops feeding.
func test_every_spawnable_flyer_has_a_diet():
	var roster: Array = []
	roster.append_array(AmbientFlyerRenderer.BIRD_SPECIES_POOL)
	roster.append_array(AmbientFlyerRenderer.BUTTERFLY_SPECIES_POOL)
	roster.append("kingfisher")
	for species in roster:
		assert_gt(FlyerDiet.foods_for(species).size(), 0, "%s has no diet" % species)


func test_an_unknown_species_eats_nothing_rather_than_crashing():
	assert_eq(FlyerDiet.foods_for("pterodactyl"), [])
	assert_false(FlyerDiet.eats("pterodactyl", FlyerDiet.FOOD_WORMS))


# -- blackbird: real thrush omnivore, plus a real winter diet shift ---------
#
# See docs/concept/seasonal_behavior.md, "Blackbird: new species, real
# population, real diet shift". Real Eurasian blackbirds eat worms/
# caterpillars/insects and soft fruit year-round, same broad diet as robin
# (both thrushes) -- but shift toward fruit specifically once insects thin
# out in winter, unlike robin/sparrow, which keep their existing flat diet
# weighting (a named, separate follow-up, not done here).

func test_blackbirds_eat_worms_fruit_caterpillars_and_ants_like_robins():
	for food in [FlyerDiet.FOOD_WORMS, FlyerDiet.FOOD_FRUIT, FlyerDiet.FOOD_CATERPILLARS, FlyerDiet.FOOD_ANTS]:
		assert_true(FlyerDiet.eats("blackbird", food), food)


func test_a_blackbird_takes_every_tree_fruit_like_a_robin():
	for fruit in ["cherry", "walnut", "apple"]:
		assert_true(FlyerDiet.eats_fruit_species("blackbird", fruit))


## eats_now() is eats() unless the real season has genuinely shut that food
## off for this species -- every existing caller/species keeps its exact
## old, season-blind behavior (the same "safe default preserves old
## behavior" convention this session's other seasonal-behavior phases
## already established).
func test_eats_now_matches_eats_for_every_species_outside_winter():
	for season in ["spring", "summer", "autumn"]:
		assert_true(FlyerDiet.eats_now("blackbird", FlyerDiet.FOOD_WORMS, season))
		assert_true(FlyerDiet.eats_now("robin", FlyerDiet.FOOD_WORMS, season))


func test_eats_now_matches_eats_for_robin_and_sparrow_even_in_winter():
	# Robin/sparrow deliberately keep their flat diet weighting -- only
	# blackbird gets the new seasonal shift in this pass.
	assert_true(FlyerDiet.eats_now("robin", FlyerDiet.FOOD_WORMS, "winter"))
	assert_true(FlyerDiet.eats_now("sparrow", FlyerDiet.FOOD_SEEDS, "winter"))


func test_a_blackbird_stops_pursuing_insects_in_winter():
	for food in [FlyerDiet.FOOD_WORMS, FlyerDiet.FOOD_CATERPILLARS, FlyerDiet.FOOD_ANTS]:
		assert_false(FlyerDiet.eats_now("blackbird", food, "winter"), food)


func test_a_blackbird_still_pursues_fruit_in_winter():
	assert_true(FlyerDiet.eats_now("blackbird", FlyerDiet.FOOD_FRUIT, "winter"))


func test_eats_now_is_false_for_a_food_this_species_never_eats_regardless_of_season():
	assert_false(FlyerDiet.eats_now("blackbird", FlyerDiet.FOOD_SEEDS, "summer"))
	assert_false(FlyerDiet.eats_now("blackbird", FlyerDiet.FOOD_SEEDS, "winter"))


# -- ground foraging --------------------------------------------------------
#
# The shared query the marker/renderer gate on: does this species feed on
# things lying on the ground (and therefore need to land, sit and peck)?
# Designed so the follow-on seed pass needs no new machinery -- a sparrow is
# already a ground forager here, it just has nothing to find yet.

func test_a_robin_is_a_ground_forager():
	assert_true(FlyerDiet.forages_on_the_ground("robin"))


func test_a_sparrow_is_a_ground_forager_too():
	assert_true(
		FlyerDiet.forages_on_the_ground("sparrow"),
		"seed-eating is ground feeding as well -- the next pass gives it seeds to find"
	)


func test_a_butterfly_is_not_a_ground_forager():
	assert_false(FlyerDiet.forages_on_the_ground("monarch"))


func test_a_kingfisher_is_not_a_ground_forager():
	assert_false(FlyerDiet.forages_on_the_ground("kingfisher"))


# -- extensibility ----------------------------------------------------------
#
# soil_fauna.md commits to seeds and fruit slotting in without redesign.

func test_the_food_types_the_roadmap_needs_all_exist():
	var types := [
		FlyerDiet.FOOD_WORMS, FlyerDiet.FOOD_SEEDS, FlyerDiet.FOOD_FRUIT,
		FlyerDiet.FOOD_FISH, FlyerDiet.FOOD_NECTAR, FlyerDiet.FOOD_CATERPILLARS,
	]
	var distinct := {}
	for type in types:
		distinct[type] = true
	assert_eq(distinct.size(), types.size(), "food types must be distinct")


func test_ground_foods_are_a_subset_of_the_known_food_types():
	for food in FlyerDiet.GROUND_FOODS:
		assert_true(
			FlyerDiet.FOOD_TYPES.has(food), "%s must be a declared food type" % food
		)


## Fallen fruit sits on the ground exactly like a worm does -- a fruit-eating
## bird has to land, sit, and peck at it too, so it belongs in the same
## GROUND_FOODS set that already drives forages_on_the_ground.
func test_fruit_is_a_ground_food():
	assert_true(FlyerDiet.GROUND_FOODS.has(FlyerDiet.FOOD_FRUIT))


# -- which fruit, not just whether fruit -----------------------------------

## Requested: robins eat cherries, walnuts and apples; sparrows eat seeds
## plus walnuts. FOOD_FRUIT alone is too coarse for that -- a sparrow's bill
## is built for hard seed and nuts, not soft cherries.
func test_a_robin_takes_every_tree_fruit():
	for fruit in ["cherry", "walnut", "apple"]:
		assert_true(FlyerDiet.eats_fruit_species("robin", fruit))


func test_a_sparrow_takes_walnuts_but_not_soft_fruit():
	assert_true(FlyerDiet.eats_fruit_species("sparrow", "walnut"))
	assert_false(FlyerDiet.eats_fruit_species("sparrow", "cherry"))
	assert_false(FlyerDiet.eats_fruit_species("sparrow", "apple"))


func test_a_sparrow_still_eats_seed():
	assert_true(FlyerDiet.eats("sparrow", FlyerDiet.FOOD_SEEDS))


## A bird with no fruit in its diet at all takes none of it, whatever the
## species-level table says.
func test_a_non_fruit_eater_takes_no_fruit():
	assert_false(FlyerDiet.eats_fruit_species("kingfisher", "cherry"))
	assert_false(FlyerDiet.eats_fruit_species("monarch", "apple"))
