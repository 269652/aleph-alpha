extends GutTest

## A caterpillar -- requested live: "wire caterpillars which live on trees
## and on the ground around them; they should also do groundforaging and
## eat green leaves (spring, summer only)". Mirrors DecomposerMarker's own
## shape closely: no CreatureMarker/AnimalAnatomy stack (the wrong shape
## for a tiny insect whose entire behaviour is "find food, eat it, wander
## otherwise"), ambient wander via the same shared, already-tested
## AmbientFlyerMovement algorithm, an injected duck-typed `_world` for the
## one chunk-specific thing it needs (real trees + real leaf litter,
## exactly the pattern DecomposerMarker's own leaf-litter foraging already
## established).
##
## Season gating (spring/summer only) lives entirely at the SPAWN decision
## (see CaterpillarRenderer) -- once spawned, a caterpillar forages
## year-round, same accepted approximation every other ambient decoration
## in this codebase already has (nothing re-validates a spawned flyer's own
## season/biome eligibility continuously either). What IS checked here,
## per-leaf: a fallen leaf's own recorded season, so a caterpillar eats
## GREEN (spring/summer-fallen) litter specifically, not old brown autumn
## litter still lying around from before it decays away.

const CaterpillarMarker = preload("res://src/rendering/caterpillar_marker.gd")
const CaterpillarForageBehavior = preload("res://src/gameplay/caterpillar_forage_behavior.gd")
const IllustratedCaterpillarSprite = preload("res://src/rendering/illustrated_caterpillar_sprite.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")

const TILE_SIZE := 16.0

## Minimal duck-typed `_world` wrapping a real LeafLitterField -- mirrors
## test_decomposer_marker.gd's own LeafLitterWorld shape exactly -- plus
## trees_near, the same shape EarthChunkManager.trees_near/StubTreeWorld
## (test_ambient_flyer_marker.gd) already establish.
class StubWorld:
	extends RefCounted
	var field := LeafLitterField.new()
	var trees: Array = []

	func nearest_leaf_litter_near(pixel_position: Vector2, radius_px: float) -> Dictionary:
		return field.nearest_leaf_near(pixel_position, radius_px)

	func consume_leaf_litter_at(pixel_position: Vector2) -> bool:
		return field.consume_leaf_at(pixel_position)

	func trees_near(position: Vector2, radius_tiles: int) -> Array:
		var out: Array = []
		for t in trees:
			if position.distance_to(t["position"]) / TILE_SIZE <= float(radius_tiles):
				out.append(t)
		return out


var marker: CaterpillarMarker


func before_each():
	marker = CaterpillarMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 7
	add_child_autofree(marker)


func test_joins_the_hoverable_group():
	const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
	assert_true(marker.is_in_group(HoverTargetFinder.GROUP_NAME))


func test_stays_near_home_while_nothing_to_eat():
	for i in 30:
		marker._process(0.5)
	assert_lt(marker.position.distance_to(marker.home), CaterpillarMarker.WANDER_RADIUS_PX * 2.0)


func test_wanders_when_idle_instead_of_sitting_frozen():
	var start := marker.position
	for i in 30:
		marker._process(0.5)
	assert_ne(marker.position, start)


func test_draws_real_illustrated_art_at_its_real_tiny_world_size():
	var sprite := marker.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)
	assert_eq(sprite.scale, Vector2.ONE * IllustratedCaterpillarSprite.new().world_scale())


func test_never_looks_for_food_without_an_injected_world():
	assert_null(marker._world, "precondition: this marker never had setup() called")
	assert_null(marker._nearest_food())


# -- ground foraging: real, in-season (green) leaf litter --------------------

func test_forages_and_eats_a_nearby_green_leaf():
	var world := StubWorld.new()
	world.field.add_leaf(Vector2(105, 100), "cherry", "summer", 0.0)
	marker.setup(world)
	for i in 400:
		marker._process(0.5)
		if world.field.leaves().is_empty():
			break
	assert_true(world.field.leaves().is_empty(), "a caterpillar should forage and eat a green fallen leaf")


## The precision "eat green leaves" actually asks for: an old brown, still-
## decaying autumn leaf sitting on the ground (LeafLitterField's own 270-day
## lifespan means one absolutely can still be there come spring/summer) is
## not what this caterpillar is after.
func test_ignores_an_old_brown_autumn_leaf():
	var world := StubWorld.new()
	world.field.add_leaf(Vector2(105, 100), "cherry", "autumn", 0.0)
	marker.setup(world)
	for i in 400:
		marker._process(0.5)
	assert_false(world.field.leaves().is_empty(), "a caterpillar must not eat a brown, non-green leaf")


# -- tree foraging: climbs a real nearby tree and eats there, without -------
# -- ever removing it -- a tree is not a one-visit consumable like a leaf ----

func test_climbs_and_eats_at_a_nearby_tree():
	var world := StubWorld.new()
	var tree_position := Vector2(105, 100)
	world.trees = [{"position": tree_position, "species": "apple"}]
	marker.setup(world)
	var ate := false
	for i in 400:
		marker._process(0.5)
		if marker._behavior.phase == CaterpillarForageBehavior.Phase.EATING:
			ate = true
			break
	assert_true(ate, "a caterpillar with a real tree nearby should climb it and eat")
	assert_almost_eq(
		marker.position, tree_position, Vector2.ONE * 2.0,
		"it should actually be at the tree while eating, not merely EATING in name"
	)


## The whole reason EATING has to end on its own clock (see
## CaterpillarForageBehavior.EAT_SECONDS's own doc comment): without this, a
## caterpillar that found a tree first would never be seen ground-foraging
## at all, which is exactly half of what was asked for.
func test_eating_at_a_tree_ends_and_it_goes_back_to_seeking():
	var world := StubWorld.new()
	world.trees = [{"position": Vector2(105, 100), "species": "apple"}]
	marker.setup(world)
	var was_eating := false
	var resumed_seeking := false
	for i in 800:
		marker._process(0.5)
		if marker._behavior.phase == CaterpillarForageBehavior.Phase.EATING:
			was_eating = true
		elif was_eating and marker._behavior.phase == CaterpillarForageBehavior.Phase.SEEKING:
			resumed_seeking = true
			break
	assert_true(was_eating, "precondition: it actually started eating")
	assert_true(resumed_seeking, "eating at a tree must actually end, not hold forever")


func test_eating_at_a_tree_never_removes_it():
	var world := StubWorld.new()
	world.trees = [{"position": Vector2(105, 100), "species": "apple"}]
	marker.setup(world)
	for i in 400:
		marker._process(0.5)
	assert_eq(world.trees.size(), 1, "a tree is not a one-visit consumable the way a leaf is")


## Same overshoot guard test_decomposer_marker.gd's own identical test
## pins: a target closer than one approach step must still be reached, not
## orbited forever.
func test_approaching_a_close_target_does_not_overshoot_and_orbit_forever():
	var world := StubWorld.new()
	world.field.add_leaf(marker.position + Vector2(6.0, 0.0), "cherry", "spring", 0.0)
	marker.setup(world)
	marker._target_position = marker.position + Vector2(6.0, 0.0)
	marker._target_is_tree = false
	marker._behavior.phase = CaterpillarForageBehavior.Phase.APPROACHING
	for i in 20:
		marker._process(0.5)
		if marker._behavior.phase == CaterpillarForageBehavior.Phase.EATING:
			break
	assert_eq(
		marker._behavior.phase, CaterpillarForageBehavior.Phase.EATING,
		"a target closer than one approach step should still be reached, not orbited forever"
	)
