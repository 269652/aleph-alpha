extends GutTest

## Tests for active foraging by land herbivores -- horses, deer and boars
## walking to a specific thing they can see and eating it, instead of
## absorbing food from whatever biome they happen to be standing on.

var GrazerForaging = preload("res://src/gameplay/grazer_foraging.gd")
var FoodConsumption = preload("res://src/gameplay/food_consumption.gd")


# -- diet: who eats what --------------------------------------------------

func test_a_horse_crops_grass():
	assert_true(GrazerForaging.eats("horse", "Grazer", GrazerForaging.FOOD_GRASS))


## Horses are strict grazers -- they don't work fallen mast the way a deer or
## a boar does, so the fruit under an apple tree is not theirs.
func test_a_horse_does_not_work_fallen_fruit():
	assert_false(GrazerForaging.eats("horse", "Grazer", GrazerForaging.FOOD_FRUIT))


## Deer are mixed feeders, not strict grazers: grass and forbs, but also hard
## mast and windfall fruit. They carry a species override on top of the
## "Grazer" label they share with the horse.
func test_a_deer_takes_both_grass_and_fallen_fruit():
	assert_true(GrazerForaging.eats("deer", "Grazer", GrazerForaging.FOOD_GRASS))
	assert_true(GrazerForaging.eats("deer", "Grazer", GrazerForaging.FOOD_FRUIT))


## A boar roots: mast, seed and the soil fauna under it. The worm is the
## point -- it is the one food kind only the rooters take.
func test_a_boar_roots_for_worms_and_mast():
	for kind in [GrazerForaging.FOOD_FRUIT, GrazerForaging.FOOD_SEED, GrazerForaging.FOOD_WORM]:
		assert_true(GrazerForaging.eats("boar", "Omnivore", kind), "a boar eats %s" % kind)


func test_only_rooters_take_worms():
	assert_false(GrazerForaging.eats("horse", "Grazer", GrazerForaging.FOOD_WORM))
	assert_false(GrazerForaging.eats("deer", "Grazer", GrazerForaging.FOOD_WORM))


## The diet LABEL drives the default, so a species added later with no entry
## of its own still forages instead of silently standing around.
func test_an_unlisted_grazer_still_forages_off_its_diet_label():
	assert_true(GrazerForaging.eats("reindeer", "Grazer", GrazerForaging.FOOD_GRASS))
	assert_false(GrazerForaging.forage_kinds("reindeer", "Grazer").is_empty())


## Hunters feed by catching prey (CreatureBehavior's "hunt"), so they must
## not also be handed a grazing cycle.
func test_a_hunter_has_nothing_to_forage():
	assert_true(GrazerForaging.forage_kinds("lynx", "Hunter").is_empty())


# -- choosing a bite ------------------------------------------------------

func test_a_grazer_walks_to_something_it_can_actually_see():
	var candidates := [
		{"position": Vector2(400, 400), "kind": GrazerForaging.FOOD_GRASS},
		{"position": Vector2(20, 0), "kind": GrazerForaging.FOOD_GRASS},
	]
	var chosen := GrazerForaging.choose_bite(Vector2.ZERO, candidates, 1)
	assert_eq(chosen.get("position"), Vector2(20, 0))


func test_an_empty_meadow_yields_no_bite():
	assert_true(GrazerForaging.choose_bite(Vector2.ZERO, [], 1).is_empty())


## Two animals standing together must not queue up behind the same tuft --
## the same conga-line failure PollinatorForaging.NEAREST_CANDIDATE_POOL's
## per-individual scatter was built to fix, which is why this delegates to it
## rather than re-implementing "nearest wins".
func test_two_grazers_side_by_side_pick_different_tufts():
	var candidates: Array = []
	for i in 6:
		candidates.append({"position": Vector2(30 + i * 12, 0), "kind": GrazerForaging.FOOD_GRASS})
	var picks := {}
	for seed_value in 8:
		picks[GrazerForaging.choose_bite(Vector2.ZERO, candidates, seed_value).get("position")] = true
	assert_gt(picks.size(), 1, "a herd spreads over the meadow rather than single-filing")


# -- the graze cycle ------------------------------------------------------

func test_a_grazer_starts_out_looking_for_food():
	var forage = GrazerForaging.new()
	assert_eq(forage.phase, GrazerForaging.Phase.SEEKING)
	assert_false(forage.is_grazing())


func test_it_walks_to_the_bite_before_eating_it():
	var forage = GrazerForaging.new()
	forage.advance(GrazerForaging.REGRAZE_SECONDS)
	assert_true(forage.begin_approach())
	assert_eq(forage.phase, GrazerForaging.Phase.APPROACHING)
	assert_false(forage.is_grazing(), "still on its way, head up")


## The approach ends on ARRIVAL, not on a clock: how long the walk takes
## depends on how far the tuft was.
func test_arriving_puts_its_head_down():
	var forage = _approaching()
	assert_true(forage.arrive())
	assert_true(forage.is_grazing())


func test_it_swallows_once_per_bout_not_once_per_frame():
	var forage = _approaching()
	forage.arrive()
	var swallows := 0
	for _i in 200:
		if forage.advance(GrazerForaging.GRAZE_SECONDS / 100.0):
			swallows += 1
	assert_eq(swallows, 1, "one mouthful taken from the world per bout")


func test_the_head_is_still_down_when_the_mouthful_is_taken():
	var forage = _approaching()
	forage.arrive()
	var swallowed := false
	for _i in 100:
		if forage.advance(GrazerForaging.GRAZE_SECONDS / 100.0):
			swallowed = true
			break
	assert_true(swallowed)
	assert_true(forage.is_grazing(), "the tuft vanishes while the muzzle is in it")


func test_a_finished_bout_goes_looking_for_the_next_one():
	var forage = _approaching()
	forage.arrive()
	forage.advance(GrazerForaging.GRAZE_SECONDS + 0.01)
	assert_eq(forage.phase, GrazerForaging.Phase.SEEKING)
	assert_false(forage.is_grazing())


## A real grazer feeds for most of its active day and only steps between
## mouthfuls. Pinned as the RATIO the two constants produce, so re-timing
## either can't quietly turn grazing into snacking.
func test_a_grazer_spends_most_of_its_day_head_down():
	var duty: float = GrazerForaging.GRAZE_SECONDS / (
		GrazerForaging.GRAZE_SECONDS + GrazerForaging.REGRAZE_SECONDS
	)
	assert_gt(duty, 0.75, "head-down for most of the cycle, not a quick snack")


## A committed target can become unreachable -- another animal ate it, a tree
## sits between, the chunk unloaded. Without a timeout the animal would walk
## at a dead point forever, which is exactly how the old approach-a-fixed-
## point bugs looked in game.
func test_an_unreachable_bite_is_eventually_given_up_on():
	var forage = _approaching()
	forage.advance(GrazerForaging.APPROACH_TIMEOUT + 0.01)
	assert_eq(forage.phase, GrazerForaging.Phase.SEEKING)


func test_a_bite_that_is_gone_on_arrival_can_be_abandoned():
	var forage = _approaching()
	forage.abort()
	assert_eq(forage.phase, GrazerForaging.Phase.SEEKING)
	assert_false(forage.can_commit(), "and it walks on a while before re-targeting")


func test_it_does_not_chain_bouts_back_to_back():
	var forage = GrazerForaging.new()
	assert_false(forage.can_commit(), "a fresh animal steps before its first bite")
	forage.advance(GrazerForaging.REGRAZE_SECONDS)
	assert_true(forage.can_commit())


func test_a_busy_grazer_refuses_a_second_target():
	var forage = _approaching()
	assert_false(forage.begin_approach(), "already walking to one")


## Arrival is close enough to eat a ground item, shared with the food the
## world already lets herbivores pick up -- two different answers to "close
## enough to eat it" would be two different bugs.
func test_arrival_matches_how_close_the_world_lets_an_animal_eat():
	assert_almost_eq(GrazerForaging.ARRIVAL_DISTANCE, FoodConsumption.EAT_RADIUS, 0.001)


func _approaching():
	var forage = GrazerForaging.new()
	forage.advance(GrazerForaging.REGRAZE_SECONDS)
	forage.begin_approach()
	return forage
