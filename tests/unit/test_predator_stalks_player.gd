extends GutTest

## A predator acquiring the player by scent (see PredatorScent, and
## docs/concept/olfaction.md's "The wind carries it").
##
## Predators have never hunted the player at all: `_nearby_prey_creatures`
## only ever returned other CREATURES, so the player was something a predator
## bumped into rather than something it came looking for.

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const PredatorScent = preload("res://src/gameplay/predator_scent.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const WindScent = preload("res://src/world/wind_scent.gd")


## A world with a wind blowing a known way.
class WindyWorld:
	extends Node2D
	var wind := Vector2.RIGHT
	var strength := 1.0

	func biome_at_global(_x: int, _y: int) -> String:
		return "grassland"

	func wind_direction() -> Vector2:
		return wind

	func wind_advection_strength() -> float:
		return strength


var world: WindyWorld
var wolf: CreatureMarker
var player: Node2D


func before_each():
	world = WindyWorld.new()
	add_child(world)
	player = Node2D.new()
	player.add_to_group(CreatureMarker.PLAYER_GROUP)
	add_child(player)
	player.position = Vector2.ZERO
	wolf = CreatureMarker.new()
	wolf.info = CreatureInfo.new("wolf")
	wolf.info.health = 100.0
	wolf.info.max_health = 100.0
	add_child(wolf)
	wolf.setup(world, TerrainRenderer.TILE_SIZE)


func after_each():
	remove_child(wolf)
	wolf.free()
	remove_child(player)
	player.free()
	remove_child(world)
	world.free()


## Places the wolf `tiles` away, on the side of the player the wind blows
## toward (downwind) or away from (upwind).
func _place_wolf(tiles: float, downwind: bool) -> void:
	var offset := world.wind * tiles * float(TerrainRenderer.TILE_SIZE)
	wolf.position = player.position + (offset if downwind else -offset)


## The headline: a wolf downwind of you comes looking, from further out than
## it could possibly see you.
func test_a_downwind_wolf_smells_you_from_beyond_sight():
	_place_wolf(PredatorScent.HUNT_RANGE_TILES * 0.6, true)
	assert_gt(
		wolf.position.length(),
		CreatureMarker.SENSE_RADIUS,
		"the test put the wolf inside sight range, which proves nothing"
	)
	assert_true(wolf.smells_a_player_to_hunt())


## ...and the same gap upwind is safe, which is the entire point of the wind.
func test_the_same_gap_upwind_is_safe():
	_place_wolf(PredatorScent.HUNT_RANGE_TILES * 0.6, false)
	assert_false(wolf.smells_a_player_to_hunt())


func test_a_wolf_far_enough_away_smells_nothing():
	_place_wolf(PredatorScent.HUNT_RANGE_TILES * 4.0, true)
	assert_false(wolf.smells_a_player_to_hunt())


## A grazer is not hunting anybody, however close and however downwind.
func test_a_grazer_never_stalks_you():
	var horse := CreatureMarker.new()
	horse.info = CreatureInfo.new("horse")
	horse.info.health = 100.0
	horse.info.max_health = 100.0
	add_child(horse)
	horse.setup(world, TerrainRenderer.TILE_SIZE)
	horse.position = player.position + Vector2(8.0, 0.0)
	assert_false(horse.smells_a_player_to_hunt())
	remove_child(horse)
	horse.free()


## A TAMED predator does not stalk the person who tamed it -- the same
## exemption fears_players already makes on the prey side.
func test_a_tamed_predator_does_not_stalk_you():
	_place_wolf(PredatorScent.HUNT_RANGE_TILES * 0.6, true)
	wolf.trust = 1.0  # tame (see Taming.is_tame)
	assert_false(wolf.smells_a_player_to_hunt())
