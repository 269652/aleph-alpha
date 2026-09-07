extends GutTest

## Per-species diet for every fish (see docs/concept/aquatic_foraging.md's
## "Revised (2026-09-07): real per-species diet and forage-coupled mass").
##
## Mirrors FlyerDiet's own shape exactly: a species with a food type in its
## diet is handed that food to look for at forage time; one without simply
## never seeks it, however the shared marker code changes. Deliberately NOT
## a weighted-preference table -- FlyerDiet's own binary eats/doesn't-eat
## shape already proved sufficient for a roster this size.

const FishDiet = preload("res://src/gameplay/fish_diet.gd")
const ProceduralFishSprite = preload("res://src/rendering/procedural_fish_sprite.gd")


# -- the headline claim -------------------------------------------------------

func test_bluegill_eat_vegetation_and_invertebrates():
	assert_true(FishDiet.eats("bluegill", FishDiet.FOOD_VEGETATION))
	assert_true(FishDiet.eats("bluegill", FishDiet.FOOD_INVERTEBRATES))


func test_koi_eat_vegetation_and_invertebrates():
	assert_true(FishDiet.eats("koi", FishDiet.FOOD_VEGETATION))
	assert_true(FishDiet.eats("koi", FishDiet.FOOD_INVERTEBRATES))


func test_goldfish_eat_vegetation_and_invertebrates():
	assert_true(FishDiet.eats("goldfish", FishDiet.FOOD_VEGETATION))
	assert_true(FishDiet.eats("goldfish", FishDiet.FOOD_INVERTEBRATES))


## Real trout are overwhelmingly insectivorous/carnivorous -- aquatic insect
## larvae are the entire basis of fly-fishing. Plant matter barely features,
## so trout gets the same narrow, single-food-type shape FlyerDiet already
## gives the kingfisher (fish-only) rather than a padded-out omnivore list.
func test_trout_eat_invertebrates_but_not_vegetation():
	assert_true(FishDiet.eats("trout", FishDiet.FOOD_INVERTEBRATES))
	assert_false(FishDiet.eats("trout", FishDiet.FOOD_VEGETATION))


func test_only_trout_is_a_vegetation_holdout_among_the_roster():
	var non_grazers: Array = []
	for species in ProceduralFishSprite.SPECIES_IDS:
		if not FishDiet.eats(species, FishDiet.FOOD_VEGETATION):
			non_grazers.append(species)
	assert_eq(non_grazers, ["trout"])


# -- extensibility / safety ---------------------------------------------------

func test_the_food_types_are_distinct():
	var types := [FishDiet.FOOD_VEGETATION, FishDiet.FOOD_INVERTEBRATES]
	var distinct := {}
	for type in types:
		distinct[type] = true
	assert_eq(distinct.size(), types.size(), "food types must be distinct")


## Every species that can actually spawn must be in the table, or its diet
## is silently empty and it quietly stops foraging.
func test_every_spawnable_fish_has_a_diet():
	for species in ProceduralFishSprite.SPECIES_IDS:
		assert_gt(FishDiet.foods_for(species).size(), 0, "%s has no diet" % species)


func test_an_unknown_species_eats_nothing_rather_than_crashing():
	assert_eq(FishDiet.foods_for("coelacanth"), [])
	assert_false(FishDiet.eats("coelacanth", FishDiet.FOOD_VEGETATION))
