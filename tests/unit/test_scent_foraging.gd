extends GutTest

## Following a smell to its source (see docs/concept/olfaction.md).
##
## The model said what things smell of and what an animal makes of them; this
## is the part that turns that into somewhere to walk. Without it the whole
## olfaction system is a set of numbers nothing reads.

const ScentForaging = preload("res://src/gameplay/scent_foraging.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func _source(at: Vector2, freshness: float) -> Dictionary:
	return {"position": at, "mixture": Olfaction.fruit_mixture("apple", freshness)}


# -- picking a target --------------------------------------------------------

func test_an_animal_heads_for_what_it_wants():
	var here := Vector2.ZERO
	var target := ScentForaging.best_source("boar", here, [_source(Vector2(40, 0), 1.0)])
	assert_false(target.is_empty(), "a boar should head for a ripe apple")
	assert_eq(target.position, Vector2(40, 0))


func test_an_animal_ignores_what_repels_it():
	var here := Vector2.ZERO
	assert_true(
		ScentForaging.best_source("deer", here, [_source(Vector2(40, 0), 0.0)]).is_empty(),
		"a deer should not walk toward a rotting apple"
	)


## The pillar, at the level that matters: same two fruits, two animals, two
## different destinations.
func test_a_fly_and_a_boar_walk_to_different_fruit():
	var here := Vector2.ZERO
	var ripe := _source(Vector2(60, 0), 1.0)
	var rotten := _source(Vector2(-60, 0), 0.0)
	assert_eq(ScentForaging.best_source("boar", here, [ripe, rotten]).position, ripe.position)
	assert_eq(ScentForaging.best_source("fly", here, [ripe, rotten]).position, rotten.position)


func test_the_stronger_smell_wins_over_the_weaker():
	var here := Vector2.ZERO
	var faint := _source(Vector2(30, 0), 0.35)
	var strong := _source(Vector2(30, 30), 1.0)
	assert_eq(ScentForaging.best_source("boar", here, [faint, strong]).position, strong.position)


## Between two identical smells, the nearer one wins -- because dilution makes
## it louder, not because of a tiebreak rule bolted on.
func test_the_nearer_of_two_identical_smells_wins():
	var here := Vector2.ZERO
	var near := _source(Vector2(20, 0), 1.0)
	var far := _source(Vector2(200, 0), 1.0)
	assert_eq(ScentForaging.best_source("boar", here, [near, far]).position, near.position)


func test_nothing_in_range_means_nothing_to_head_for():
	var here := Vector2.ZERO
	var beyond := Olfaction.MAX_RANGE_TILES * TerrainRenderer.TILE_SIZE * 3.0
	assert_true(
		ScentForaging.best_source("boar", here, [_source(Vector2(beyond, 0), 1.0)]).is_empty()
	)


func test_an_empty_world_offers_nothing():
	assert_true(ScentForaging.best_source("boar", Vector2.ZERO, []).is_empty())


func test_an_animal_with_no_nose_heads_nowhere():
	assert_true(
		ScentForaging.best_source("nonesuch", Vector2.ZERO, [_source(Vector2(20, 0), 1.0)]).is_empty()
	)


# -- eating ------------------------------------------------------------------

## Close enough to eat is closer than close enough to smell.
func test_an_animal_has_to_arrive_before_it_eats():
	assert_false(ScentForaging.can_eat(Vector2.ZERO, Vector2(80, 0)))
	assert_true(ScentForaging.can_eat(Vector2.ZERO, Vector2(2, 0)))


## Which animals go looking for food by smell at all.
func test_the_foragers_are_the_ones_with_receptors():
	for species in ["boar", "robin", "fly"]:
		assert_true(ScentForaging.forages_by_smell(species), species)


func test_something_with_no_receptors_does_not_forage_by_smell():
	assert_false(ScentForaging.forages_by_smell("nonesuch"))


# -- slice 2: the ranking lives in the kernel ---------------------------------

const Ethogram = preload("res://src/gameplay/ethogram.gd")


## A smelled source becomes a stimulus that carries its own loudness at this
## range (Olfaction.dilution), so the kernel ranks it by the physics of smell
## rather than by its unit-free distance ranking.
func test_smelled_sources_become_stimuli_with_their_dilution_as_strength():
	var here := Vector2.ZERO
	var near := _source(Vector2(TerrainRenderer.TILE_SIZE * 2.0, 0), 1.0)
	var far := _source(Vector2(TerrainRenderer.TILE_SIZE * 10.0, 0), 1.0)
	var stimuli := ScentForaging.stimuli_from(here, [near, far])
	assert_eq(stimuli.size(), 2)
	assert_almost_eq(stimuli[0]["strength"], Olfaction.dilution(2.0), 0.0001)
	assert_almost_eq(stimuli[1]["strength"], Olfaction.dilution(10.0), 0.0001)
	assert_eq(stimuli[0]["mixture"], near["mixture"])
	assert_eq(stimuli[0]["position"], near["position"])


## The interest floor is the smell wiring floor in the ethogram, not a second number.
func test_the_interest_floor_is_the_ethograms():
	assert_almost_eq(ScentForaging.MIN_INTEREST, Ethogram.SMELL_INTEREST_FLOOR, 0.0)


## An individual reaches the choice through its genome: a boar born without a
## decay receptor is not led to carrion the species would go to.
func test_an_individuals_receptor_genes_reach_the_choice_of_source():
	var here := Vector2.ZERO
	var carrion := {"position": Vector2(40, 0), "mixture": {Olfaction.DECAY: 1.0}}
	assert_false(ScentForaging.best_source("boar", here, [carrion]).is_empty(), "the species takes carrion")
	assert_true(
		ScentForaging.best_source("boar", here, [carrion], {"receptor_decay": 0.0}).is_empty(),
		"this individual cannot smell it"
	)
