extends GutTest

## Can a predator ever start a fight?
##
## Measured, and the answer was **no**. `CreatureMarker.fears_players()` is
## literally `not is_tame()`, so it is true for every untamed creature --
## predators included -- and it is the sole gate on
## `_cached_caution_threats`, the wander-avoidance list. The bias built from
## it ramps `clampf((CAUTION_RADIUS - d) / (CAUTION_RADIUS - SENSE_RADIUS),
## 0, 1)`, which saturates at **exactly SENSE_RADIUS**: the distance at
## which a predator would first perceive the player at all.
##
## So a wandering wolf's closing speed toward a player was 24 px/s at
## 160 px, 6 px/s at 100, 3 at 90 and **0 at 80**. It asymptoted to its own
## perception boundary and could never cross it. A predator could never
## INITIATE on a player; it only ever fought one who walked into its bubble.
##
## Not one of the five tests that pin the caution bias would have caught
## this: every one of them uses a calm herbivore, and nothing anywhere
## drove a predator toward a player from outside attack range.

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const PlayerScene = preload("res://scenes/player.tscn")

const FRAME := 1.0 / 60.0

var player
var manager
var renderer
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	add_child(creatures_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	renderer = CreatureRenderer.new()
	player = PlayerScene.instantiate()
	add_child(player)
	player.position = Vector2.ZERO


func after_each():
	player.queue_free()
	creatures_parent.free()
	tile_map_layer.free()
	entities_parent.free()


func _creature(species: String, offset: Vector2):
	return renderer.spawn_single(
		creatures_parent, species, player.position + offset, manager, TerrainRenderer.TILE_SIZE
	)


# -- the predicate --------------------------------------------------------

## The two questions one predicate was answering. `fears_players` is the ON
## switch for the whole PLAYER receptor channel, so turning it off for a
## predator would silently stop it attacking at all -- the obvious fix is
## the opposite of a fix. The repulsion has to be cut where the avoidance
## list is built, not at perception.
func test_a_hunter_still_perceives_people():
	var wolf = _creature("wolf", Vector2(40.0, 0.0))
	assert_true(wolf.fears_players(), "a predator that cannot see you cannot hunt you")


func test_a_hunter_does_not_steer_around_people():
	var wolf = _creature("wolf", Vector2(40.0, 0.0))
	assert_false(wolf.steers_clear_of_players(), "a hunter does not give you a wide berth")


## Nor does anything that fights back: a boar is not a predator by role but
## it is aggressive, and an animal that will fight you has no business
## politely routing around you.
func test_something_that_fights_back_does_not_steer_around_people_either():
	var boar = _creature("boar", Vector2(40.0, 0.0))
	assert_false(boar.steers_clear_of_players())


## And the behaviour the five existing caution tests protect is untouched:
## a calm grazer still gives people a wide berth while roaming, which is
## what stopped the flee hysteria those tests were written for.
func test_a_grazer_still_keeps_its_distance():
	var deer = _creature("deer", Vector2(40.0, 0.0))
	assert_true(deer.steers_clear_of_players())


## A tamed animal is not steering around its own keeper.
func test_a_tamed_animal_neither_fears_nor_avoids():
	var deer = _creature("deer", Vector2(40.0, 0.0))
	deer.trust = 1.0
	assert_false(deer.fears_players())
	assert_false(deer.steers_clear_of_players())


# -- and it can really close --------------------------------------------

## The whole point, driven rather than argued: a wolf that starts outside
## its own perception radius must be able to reach it.
func test_a_wolf_can_close_on_a_player_it_has_not_sensed_yet():
	await get_tree().process_frame
	var wolf = _creature("wolf", Vector2(120.0, 0.0))
	var start: float = wolf.position.distance_to(player.position)
	assert_gt(start, CreatureMarker.SENSE_RADIUS, "precondition: it cannot perceive them yet")
	for _i in 600:
		wolf._process(FRAME)
	assert_lt(
		wolf.position.distance_to(player.position), CreatureMarker.SENSE_RADIUS,
		"a predator that cannot reach its own perception radius can never start a fight"
	)
