extends GutTest

## A millipede -- see docs/concept/soil_fauna.md "Millipedes: a dedicated
## autumn leaf-litter decomposer". Mirrors CaterpillarMarker's own shape
## closely, minus everything tree-related (a millipede never climbs, has
## only one food source) and minus the green/brown season filter --
## deliberately the OPPOSITE restriction from a caterpillar: any leaf, any
## season, is real food, since the whole point is reaching the autumn pile
## a caterpillar structurally cannot touch.

const MillipedeMarker = preload("res://src/rendering/millipede_marker.gd")
const CaterpillarForageBehavior = preload("res://src/gameplay/caterpillar_forage_behavior.gd")
const IllustratedMillipedeSprite = preload("res://src/rendering/illustrated_millipede_sprite.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")

## Minimal duck-typed `_world` wrapping a real LeafLitterField -- mirrors
## test_caterpillar_marker.gd's own StubWorld shape, minus trees (a
## millipede never queries them at all).
class StubWorld:
	extends RefCounted
	var field := LeafLitterField.new()

	func nearest_leaf_litter_near(pixel_position: Vector2, radius_px: float) -> Dictionary:
		return field.nearest_leaf_near(pixel_position, radius_px)

	func consume_leaf_litter_at(pixel_position: Vector2) -> bool:
		return field.consume_leaf_at(pixel_position)


var marker: MillipedeMarker


func before_each():
	marker = MillipedeMarker.new()
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
	assert_lt(marker.position.distance_to(marker.home), MillipedeMarker.WANDER_RADIUS_PX * 2.0)


func test_wanders_when_idle_instead_of_sitting_frozen():
	var start := marker.position
	for i in 30:
		marker._process(0.5)
	assert_ne(marker.position, start)


func test_draws_real_illustrated_art_at_its_real_tiny_world_size():
	var sprite := marker.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)
	assert_eq(sprite.scale, Vector2.ONE * IllustratedMillipedeSprite.new().world_scale())


func test_never_looks_for_food_without_an_injected_world():
	assert_null(marker._world, "precondition: this marker never had setup() called")
	assert_null(marker._nearest_food())


# -- ground foraging: real leaf litter, ANY season (see the class doc -------
# -- comment for why this is the opposite restriction from a caterpillar) --

func test_forages_and_eats_a_nearby_leaf():
	var world := StubWorld.new()
	world.field.add_leaf(Vector2(105, 100), "cherry", "summer", 0.0)
	marker.setup(world)
	for i in 400:
		marker._process(0.5)
		if world.field.leaves().is_empty():
			break
	assert_true(world.field.leaves().is_empty(), "a millipede should forage and eat a nearby leaf")


## THE reason this creature exists (see the concept doc): a caterpillar
## structurally refuses an old brown autumn leaf; a millipede must eat it
## exactly the same as any other leaf.
func test_eats_an_autumn_leaf_too():
	var world := StubWorld.new()
	world.field.add_leaf(Vector2(105, 100), "cherry", "autumn", 0.0)
	marker.setup(world)
	for i in 400:
		marker._process(0.5)
		if world.field.leaves().is_empty():
			break
	assert_true(world.field.leaves().is_empty(), "a millipede must eat an autumn leaf, unlike a caterpillar")


func test_eats_a_leaf_of_every_recorded_season():
	for season in ["spring", "summer", "autumn", "winter"]:
		var world := StubWorld.new()
		world.field.add_leaf(Vector2(105, 100), "cherry", season, 0.0)
		var m := MillipedeMarker.new()
		m.home = Vector2(100, 100)
		m.position = Vector2(100, 100)
		m.wander_seed = 7
		add_child_autofree(m)
		m.setup(world)
		for i in 400:
			m._process(0.5)
			if world.field.leaves().is_empty():
				break
		assert_true(world.field.leaves().is_empty(), "season %s should be eaten" % season)


## Same overshoot guard test_caterpillar_marker.gd's own identical test
## pins: a target closer than one approach step must still be reached, not
## orbited forever.
func test_approaching_a_close_target_does_not_overshoot_and_orbit_forever():
	var world := StubWorld.new()
	world.field.add_leaf(marker.position + Vector2(6.0, 0.0), "cherry", "autumn", 0.0)
	marker.setup(world)
	marker._target_position = marker.position + Vector2(6.0, 0.0)
	marker._behavior.phase = CaterpillarForageBehavior.Phase.APPROACHING
	for i in 20:
		marker._process(0.5)
		if marker._behavior.phase == CaterpillarForageBehavior.Phase.EATING:
			break
	assert_eq(
		marker._behavior.phase, CaterpillarForageBehavior.Phase.EATING,
		"a target closer than one approach step should still be reached, not orbited forever"
	)


## A millipede never climbs -- it has no tree food source at all, so
## nothing in this class should ever offset its sprite vertically the way
## CaterpillarMarker._step_climb does.
func test_has_no_climb_mechanism():
	assert_false(marker.has_method("_step_climb"))
