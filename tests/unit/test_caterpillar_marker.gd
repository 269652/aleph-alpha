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
const SquashCrushEffect = preload("res://src/rendering/squash_crush_effect.gd")

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
	# The real, intentional arrival contract is ARRIVE_DISTANCE_PX (see
	# _step_approaching) -- not a tighter, arbitrary number. A slower
	# WALK_SPEED (2026-09-06, requested "1/3 of the speed") takes finer
	# steps on the final approach, so the exact position the instant
	# arrival triggers can legitimately land anywhere up to that real
	# radius, not snap almost exactly onto the target the way a single
	# large fast-speed step used to.
	assert_lte(
		marker.position.distance_to(tree_position), CaterpillarMarker.ARRIVE_DISTANCE_PX,
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


# -- climbing: a caterpillar visually rises up the trunk while targeting a --
# -- tree, purely a sprite offset (see docs/concept/soil_fauna.md's ---------
# -- "Caterpillars actually climb, and move a third as fast") --------------

func test_climbs_while_targeting_a_tree():
	var world := StubWorld.new()
	world.trees = [{"position": Vector2(105, 100), "species": "apple"}]
	marker.setup(world)
	var reached_positive_climb := false
	for i in 400:
		marker._process(0.5)
		if marker._climb_height_px > 0.0:
			reached_positive_climb = true
			break
	assert_true(reached_positive_climb, "a caterpillar targeting a tree should visually climb")
	assert_lte(
		marker._climb_height_px, CaterpillarMarker.CLIMB_HEIGHT_PX,
		"should never climb past its own ceiling"
	)


## Direct state manipulation, the same "isolate this one behaviour" shape
## test_approaching_a_close_target_does_not_overshoot_and_orbit_forever
## already uses below -- seeded already at full climb height rather than
## derived by first running an organic approach/eat cycle, since an
## organic cycle risks the caterpillar simply re-committing to the SAME
## nearby tree the instant REHUNT_SECONDS clears (nothing else exists in
## this minimal stub world), which would start it climbing again before
## this could observe a clean, uninterrupted descent.
func test_settles_back_to_ground_level_once_a_tree_is_no_longer_the_target():
	marker._climb_height_px = CaterpillarMarker.CLIMB_HEIGHT_PX
	assert_eq(marker._climb_height_px, CaterpillarMarker.CLIMB_HEIGHT_PX, "precondition: seeded at full climb height")
	marker._target_is_tree = false
	marker._behavior.phase = CaterpillarForageBehavior.Phase.SEEKING
	for i in 20:
		marker._process(0.5)
	assert_almost_eq(
		marker._climb_height_px, 0.0, 0.01,
		"should climb back down to ground level once no longer targeting a tree"
	)


func test_never_climbs_for_ground_leaf_litter():
	var world := StubWorld.new()
	world.field.add_leaf(Vector2(105, 100), "cherry", "summer", 0.0)
	marker.setup(world)
	var max_climb := 0.0
	for i in 400:
		marker._process(0.5)
		max_climb = maxf(max_climb, marker._climb_height_px)
	assert_almost_eq(max_climb, 0.0, 0.0001, "a ground leaf visit should never climb even briefly")


# -- speed: 1/3 of the original, requested alongside climbing above --------

func test_walk_speed_is_a_third_of_the_original_fourteen():
	assert_almost_eq(CaterpillarMarker.WALK_SPEED, 14.0 / 3.0, 0.0001)


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


# -- crushed underfoot: procedural squash fallback (see SquashCrushEffect's -
# -- own doc comment -- no dedicated crushed art exists for a caterpillar, -
# -- unlike worm's real "die" row or millipede's real "crushed" row) --------

func test_crush_applies_the_squash_effect_to_its_sprite():
	var sprite := marker.get_child(0) as Sprite2D
	var scale_before := sprite.scale.y
	marker.crush()
	assert_almost_eq(
		sprite.scale.y, scale_before * SquashCrushEffect.VERTICAL_SQUASH, 0.0001,
		"the squash must apply RELATIVE to the caterpillar's own existing scale, not overwrite it outright"
	)
	assert_eq(sprite.modulate, SquashCrushEffect.TINT)


func test_crush_stops_all_movement_and_foraging():
	var world := StubWorld.new()
	world.field.add_leaf(Vector2(105, 100), "cherry", "spring", 0.0)
	marker.setup(world)
	marker.crush()
	var position_before := marker.position
	marker._process(1.0)
	assert_eq(marker.position, position_before, "a crushed caterpillar should no longer move")
	assert_false(world.field.leaves().is_empty(), "a crushed caterpillar should no longer forage")


func test_crush_removes_the_marker_after_lingering():
	marker.crush()
	marker._process(SquashCrushEffect.LINGER_SECONDS - 0.01)
	assert_false(marker.is_queued_for_deletion(), "should still be lingering just before the linger duration elapses")
	marker._process(0.02)
	assert_true(marker.is_queued_for_deletion(), "should free itself once the linger duration has passed")


func test_crush_called_twice_does_not_push_the_linger_clock_back_out():
	marker.crush()
	marker._process(SquashCrushEffect.LINGER_SECONDS - 0.01)
	marker.crush()  # a second heavy footstep landing before the corpse has cleared
	marker._process(0.02)
	assert_true(marker.is_queued_for_deletion(), "a second crush call should not reset the linger timer")
