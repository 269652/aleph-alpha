extends GutTest

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureWander = preload("res://src/rendering/creature_wander.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")

const TILE_SIZE := 16


## Duck-typed world: every tile is the same biome unless overridden. Land
## (non-water, non-food) by default so sensing doesn't trigger food/water
## seeking in the flee/hunt tests.
class StubWorld:
	var biome := "grassland"
	func biome_at_global(_x: int, _y: int) -> String:
		return biome


class StubPlayer:
	extends Node2D
	var damage_taken := 0.0
	func take_damage(amount: float) -> void:
		damage_taken += amount


var marker: CreatureMarker
var _extra: Array = []


func before_each():
	marker = CreatureMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 5
	marker.info = CreatureInfo.new("herbivore")
	add_child(marker)


func after_each():
	remove_child(marker)
	marker.free()
	for node in _extra:
		if is_instance_valid(node):
			node.free()
	_extra = []


func _add_stub_creature(species: String, at: Vector2) -> CreatureMarker:
	var stub := CreatureMarker.new()
	stub.info = CreatureInfo.new(species)
	stub.position = at
	stub.home = at
	add_child(stub)
	_extra.append(stub)
	return stub


func _add_stub_player(at: Vector2) -> StubPlayer:
	var player := StubPlayer.new()
	player.position = at
	add_child(player)
	player.add_to_group(CreatureMarker.PLAYER_GROUP)
	_extra.append(player)
	return player


func test_position_changes_after_processing():
	var before := marker.position
	marker._process(0.5)
	assert_ne(marker.position, before)


func test_stays_within_a_bounded_range_of_home_over_many_steps():
	for i in 100:
		marker._process(0.5)
	assert_lt(marker.position.distance_to(marker.home), CreatureWander.WANDER_RADIUS * 2.0)


func test_two_markers_with_different_seeds_move_differently():
	var other := CreatureMarker.new()
	other.home = Vector2(100, 100)
	other.position = Vector2(100, 100)
	other.wander_seed = 99
	add_child(other)

	marker._process(0.5)
	other._process(0.5)

	assert_ne(marker.position, other.position)
	remove_child(other)
	other.free()


func test_is_added_to_the_creature_group_on_ready():
	assert_true(marker.is_in_group(CreatureMarker.GROUP_NAME))


func test_take_damage_reduces_info_health():
	var before := marker.info.health
	marker.take_damage(5.0)
	assert_eq(marker.info.health, before - 5.0)


func test_has_a_visible_health_bar_at_full_health():
	assert_almost_eq(marker._health_bar_fill.size.x, CreatureMarker.HEALTH_BAR_WIDTH, 0.01)


func test_health_bar_shrinks_as_the_creature_takes_damage():
	var full_width: float = marker._health_bar_fill.size.x
	marker.take_damage(marker.info.max_health * 0.5)
	assert_lt(marker._health_bar_fill.size.x, full_width)
	assert_gt(marker._health_bar_fill.size.x, 0.0)


func test_take_damage_frees_the_marker_once_health_reaches_zero():
	marker.take_damage(marker.info.max_health)
	assert_true(marker.is_queued_for_deletion())


func test_dying_drops_its_species_loot_via_the_world_item_bus():
	# A herbivore drops 2 stacks (hide + meat) -- see LootTable.
	watch_signals(WorldItemBus)
	marker.take_damage(marker.info.max_health)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 2)


func test_a_non_lethal_hit_drops_no_loot():
	watch_signals(WorldItemBus)
	marker.take_damage(1.0)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 0)


func test_take_damage_does_not_free_the_marker_while_still_alive():
	marker.take_damage(1.0)
	assert_false(marker.is_queued_for_deletion())


func test_apply_knockback_does_not_teleport_instantly():
	# Hammerwatch-style: a hit should slide the creature over a short time,
	# not snap it to the destination the instant it's hit.
	var before := marker.position
	marker.apply_knockback(Vector2(10, -5))
	assert_eq(marker.position, before)


func test_knockback_plays_out_smoothly_over_its_duration():
	var before := marker.position
	marker.apply_knockback(Vector2(30, 0))

	var step_delta := 0.05
	marker._process(step_delta)
	var mid_distance := marker.position.distance_to(before)
	assert_gt(mid_distance, 0.0, "should have started moving")
	assert_lt(mid_distance, 30.0, "should not have covered the full distance yet")

	# Advance only through the rest of the knockback's own duration -- not a
	# single frame further, or idle wander would take over once it ends and
	# throw off the distance measurement.
	var remaining_steps := int(ceil((CreatureMarker.KNOCKBACK_DURATION - step_delta) / step_delta))
	for i in remaining_steps:
		marker._process(step_delta)
	assert_almost_eq(marker.position.distance_to(before), 30.0, 0.5, "should finish covering the full knockback")


func test_knockback_suppresses_normal_wandering_while_active():
	marker.apply_knockback(Vector2(200, 0))
	var right_after_knockback := marker.position
	marker._process(0.001)
	# Only the (tiny) knockback step should have moved it, not a wander jump.
	assert_lt(marker.position.distance_to(right_after_knockback), 5.0)


# -- behavior: fleeing (calm herbivore) ---------------------------------------

func test_herbivore_flees_away_from_a_nearby_predator():
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_creature("predator", Vector2(120, 100))  # to the east, within sense range

	marker._process(0.2)

	assert_lt(marker.position.x, 100.0, "herbivore should move west, away from the predator")


func test_herbivore_flees_away_from_a_nearby_player():
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_player(Vector2(120, 100))

	marker._process(0.2)

	assert_lt(marker.position.x, 100.0, "herbivore should move away from the player")


func test_herbivore_ignores_a_predator_that_is_far_out_of_sense_range():
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_creature("predator", Vector2(100000, 100))

	marker._process(0.2)

	# No threat sensed -> idle wander stays near home, doesn't bolt away.
	assert_lt(marker.position.distance_to(marker.home), CreatureWander.WANDER_RADIUS)


# -- behavior: predator hunting/predation -------------------------------------

func test_hungry_predator_moves_toward_a_distant_herbivore():
	var predator := _make_predator(Vector2(100, 100))
	predator._needs.hunger = 1.0
	_add_stub_creature("herbivore", Vector2(160, 100))  # east, in sense range but not adjacent

	predator._process(0.2)

	assert_gt(predator.position.x, 100.0, "hungry predator should move toward its prey")


func test_hungry_predator_eats_an_adjacent_herbivore_and_is_no_longer_hungry():
	var predator := _make_predator(Vector2(100, 100))
	predator._needs.hunger = 1.0
	var prey := _add_stub_creature("herbivore", Vector2(105, 100))  # within predation range

	predator._process(0.2)

	assert_true(prey.is_queued_for_deletion(), "caught prey should be killed")
	assert_false(predator._needs.is_hungry(), "eating should sate the predator")


func test_sated_predator_does_not_chase_prey():
	var predator := _make_predator(Vector2(100, 100))
	predator._needs.hunger = 0.0
	_add_stub_creature("herbivore", Vector2(160, 100))

	predator._process(0.2)

	assert_lt(predator.position.distance_to(predator.home), CreatureWander.WANDER_RADIUS)


# -- behavior: predator vs player (strong attacks, weak flees) -----------------

func test_strong_aggressive_predator_attacks_a_nearby_player():
	var predator := _make_predator(Vector2(100, 100))
	var player := _add_stub_player(Vector2(108, 100))  # within attack range

	predator._process(0.2)

	assert_gt(player.damage_taken, 0.0, "a strong predator should damage the player")


func test_weakened_predator_flees_the_player_instead_of_attacking():
	var predator := _make_predator(Vector2(100, 100))
	predator.info.health = 1.0  # health_fraction well below the fight threshold
	var player := _add_stub_player(Vector2(120, 100))

	predator._process(0.2)

	assert_lt(predator.position.x, 100.0, "a weak predator should flee the player")
	assert_eq(player.damage_taken, 0.0, "a fleeing predator should not attack")


# -- behavior: needs (drink/graze in place) -----------------------------------

func test_thirsty_creature_drinks_when_standing_on_water():
	var world := StubWorld.new()
	world.biome = "ocean"
	marker.setup(world, TILE_SIZE)
	marker._needs.thirst = 1.0

	marker._process(0.2)

	assert_false(marker._needs.is_thirsty(), "standing on water should quench thirst")


func test_hungry_herbivore_grazes_when_standing_on_a_food_biome():
	var world := StubWorld.new()
	world.biome = "grassland"
	marker.setup(world, TILE_SIZE)
	marker._needs.hunger = 1.0

	marker._process(0.2)

	assert_false(marker._needs.is_hungry(), "grazing on food terrain should sate hunger")


func test_thirsty_creature_with_no_water_in_sight_roams_far_beyond_its_home():
	# Grassland everywhere: it grazes so never travels for food, but there's
	# no water anywhere, so a thirsty creature should roam to search -- ranging
	# well past the tight idle-wander radius instead of orbiting home.
	var world := StubWorld.new()
	world.biome = "grassland"
	marker.setup(world, TILE_SIZE)
	marker._needs.thirst = 1.0  # thirsty, and grassland has no water to quench it

	var max_distance := 0.0
	for i in 80:
		marker._process(0.3)
		max_distance = maxf(max_distance, marker.position.distance_to(marker.home))

	# Well past anything home-bounded idle-wander could reach (it clamps to
	# ~WANDER_RADIUS plus a single step's overshoot) -- proving real roaming.
	assert_gt(max_distance, CreatureWander.WANDER_RADIUS * 2.5,
		"a searching creature should range far beyond the idle-wander radius")


func _make_predator(at: Vector2) -> CreatureMarker:
	# The before_each herbivore `marker` shares the scene tree and the creature
	# group; park it far away so it doesn't register as prey in these tests.
	marker.position = Vector2(1_000_000, 1_000_000)

	var predator := CreatureMarker.new()
	predator.info = CreatureInfo.new("predator")
	predator.position = at
	predator.home = at
	predator.wander_seed = 3
	predator.setup(StubWorld.new(), TILE_SIZE)
	add_child(predator)
	_extra.append(predator)
	return predator
