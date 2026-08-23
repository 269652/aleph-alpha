extends GutTest

## Fruit on the ground does not last (see docs/concept/flora.md#where-a-forest-
## comes-from).
##
## It is eaten -- by the player, by mammals, by birds who carry the seed on --
## or it rots. Fruit that lies untouched forever turns the ground under every
## tree into a permanent larder and removes the reason to come back in season.

const FruitSpoilage = preload("res://src/gameplay/fruit_spoilage.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- how long fruit keeps ----------------------------------------------------

## Fresh when it lands.
func test_fruit_is_fresh_when_it_falls():
	assert_true(FruitSpoilage.is_edible("apple", 0.0, "autumn"))
	assert_eq(FruitSpoilage.freshness("apple", 0.0, "autumn"), 1.0)


func test_fruit_rots_if_it_is_left():
	var life := FruitSpoilage.edible_seconds("apple", "autumn")
	assert_false(FruitSpoilage.is_edible("apple", life * 2.0, "autumn"))


func test_freshness_falls_off_steadily():
	var life := FruitSpoilage.edible_seconds("apple", "autumn")
	var previous := 2.0
	for step in 20:
		var freshness := FruitSpoilage.freshness("apple", float(step) / 19.0 * life, "autumn")
		assert_lte(freshness, previous)
		previous = freshness
	assert_almost_eq(previous, 0.0, 0.001)


## Fruit keeps for a useful part of a season, not a couple of minutes: the
## point is that a windfall is worth coming back for, and then that it is gone.
func test_fruit_keeps_long_enough_to_be_worth_returning_for():
	var season := SeasonCycle.SECONDS_PER_YEAR / float(SeasonCycle.SEASONS.size())
	var life := FruitSpoilage.edible_seconds("apple", "autumn")
	assert_gt(life, season * 0.02, "a windfall that rots in minutes is not forage")
	assert_lt(life, season, "fruit lying around a whole season is a permanent larder")


# -- what keeps longer than what ---------------------------------------------

## A nut in its shell keeps far longer than soft fruit. That is the whole
## reason a squirrel caches nuts and nobody caches cherries.
func test_nuts_keep_far_longer_than_soft_fruit():
	assert_gt(
		FruitSpoilage.edible_seconds("walnut", "autumn"),
		FruitSpoilage.edible_seconds("cherry", "autumn") * 2.0
	)


func test_every_forage_food_has_a_shelf_life():
	for item in ["apple", "cherry", "walnut", "nut", "fruit"]:
		assert_gt(FruitSpoilage.edible_seconds(item, "autumn"), 0.0, item)


## An unknown item still gets a sane answer rather than rotting instantly or
## never -- the same fail-safe the rest of the lookups use.
func test_an_unknown_item_still_has_a_shelf_life():
	assert_gt(FruitSpoilage.edible_seconds("nonesuch", "autumn"), 0.0)


# -- the cold keeps things -----------------------------------------------------

## Cold slows rot. A windfall in late autumn is still there weeks later; the
## same fruit in high summer is not.
func test_fruit_keeps_longer_in_the_cold():
	assert_gt(
		FruitSpoilage.edible_seconds("apple", "winter"),
		FruitSpoilage.edible_seconds("apple", "summer")
	)


func test_every_season_gives_a_sane_shelf_life():
	for season in SeasonCycle.SEASONS:
		assert_gt(FruitSpoilage.edible_seconds("apple", season), 0.0, season)
