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


func test_only_the_robin_hunts_worms_among_the_songbirds():
	var worm_eaters: Array = []
	for species in AmbientFlyerRenderer.BIRD_SPECIES_POOL:
		if FlyerDiet.eats(species, FlyerDiet.FOOD_WORMS):
			worm_eaters.append(species)
	assert_eq(worm_eaters, ["robin"])


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
		FlyerDiet.FOOD_FISH, FlyerDiet.FOOD_NECTAR,
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
