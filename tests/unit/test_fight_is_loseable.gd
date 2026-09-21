extends GutTest

## Can a fight actually be lost?
##
## An audit of the combat layer found, and this file measures, that it
## cannot. Three facts compound:
##
##   Player.ATTACK_RANGE   20.0 px      CreatureMarker.ATTACK_RANGE  16.0 px
##   Player.ATTACK_COOLDOWN 0.5 s       KNOCKBACK_FORCE              60.0
##   CreatureMarker._process RETURNS EARLY for the whole KNOCKBACK_DURATION
##
## So every landed swing shoves the creature outside its own reach AND
## freezes its AI while it slides. The player out-reaches it, re-closes
## faster than their own cooldown, and always strikes first. A player who
## holds the attack key and walks forward kills every predator in the
## roster without being bitten.
##
## And being hit is not an event: CreatureMarker.take_damage subtracts
## health, updates the bar and calls a flinch that is a no-op for every
## species -- it sets no target, raises no aggro, wakes no herd. There is
## no damage-driven aggro anywhere in the game.
##
## These tests drive a REAL player against a REAL creature on real frames.
## They are deliberately about the exchange, not about either side's
## numbers, because every number here was already individually tested and
## the fight was still free.

const PlayerScene = preload("res://scenes/player.tscn")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")

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
	var marker = renderer.spawn_single(
		creatures_parent, species, player.position + offset, manager, TerrainRenderer.TILE_SIZE
	)
	return marker


# -- a blow is an event, not arithmetic ----------------------------------

## The omission the whole audit turned on: nothing in this game reacts to
## being hurt. A creature struck from behind carries on with its errand.
func test_being_struck_makes_a_creature_aware_of_its_attacker():
	var marker = _creature("wolf", Vector2(18.0, 0.0))
	assert_false(marker.info.is_aggroed, "precondition: it was minding its own business")
	marker.struck_by(player, 5.0)
	assert_true(
		marker.info.is_aggroed,
		"a creature that has been hit must know it is in a fight"
	)


func test_a_struck_creature_remembers_who_hit_it():
	var marker = _creature("wolf", Vector2(18.0, 0.0))
	marker.struck_by(player, 5.0)
	assert_eq(
		marker.aggressor(), player,
		"and must know WHO -- an aggro with no target is a mood"
	)


## A killing blow is not an aggro: a corpse has no opinion.
func test_a_lethal_blow_does_not_aggro_a_corpse():
	var marker = _creature("wolf", Vector2(18.0, 0.0))
	marker.struck_by(player, marker.info.max_health * 2.0)
	assert_true(
		not is_instance_valid(marker) or marker.aggressor() == null,
		"a dead thing holds no grudge"
	)


# -- and a shove is a function of the blow AND the body ------------------

## The reason the fight was free. A 60px shove is the same 60px whether it
## lands on a squirrel or a bear, so every swing repositioned a 300kg
## predator outside its own reach. Momentum against mass is the model this
## project already uses everywhere else (Throwable.impact_knockback).
func test_a_heavy_animal_is_barely_moved_by_a_blow_that_throws_a_light_one():
	var heavy = _creature("bear", Vector2(18.0, 0.0))
	var light = _creature("squirrel", Vector2(-18.0, 0.0))
	assert_gt(
		CreatureMass.mass_kg_for("bear"), CreatureMass.mass_kg_for("squirrel") * 10.0,
		"precondition: these are very different animals"
	)
	var force := Vector2(60.0, 0.0)
	assert_lt(
		heavy.knockback_distance_for(force), light.knockback_distance_for(force),
		"the same blow must not move a bear as far as a squirrel"
	)


## And the specific number that made the fight free: a bear must not be
## shoved clear of its own bite by one swing.
func test_one_swing_does_not_shove_a_bear_out_of_its_own_reach():
	var bear = _creature("bear", Vector2(18.0, 0.0))
	var shove: float = bear.knockback_distance_for(Vector2(60.0, 0.0))
	assert_lt(
		shove, CreatureMarker.ATTACK_RANGE,
		"a shove that clears the creature's own reach hands the player a free kill"
	)


# -- the whole exchange --------------------------------------------------

## The assertion the audit's verdict rests on, measured rather than argued:
## a player who does nothing but swing and close must NOT walk away from a
## bear untouched.
func test_a_player_who_only_swings_does_not_beat_a_bear_for_free():
	# One real frame before the fight, so every node's _ready has run and
	# the marker is fully initialised -- without it the bear never takes
	# its first decision and the exchange measures nothing.
	await get_tree().process_frame
	var bear = _creature("bear", Vector2(18.0, 0.0))
	var before: float = player.health
	var frame := 1.0 / 60.0
	var elapsed := 0.0
	# Twelve seconds of the simplest possible strategy: stand in reach and
	# swing whenever the cooldown allows.
	while elapsed < 12.0 and is_instance_valid(bear) and bear.info.health > 0.0:
		if player._attack_cooldown_remaining <= 0.0:
			player._perform_attack()
		player._attack_cooldown_remaining = maxf(0.0, player._attack_cooldown_remaining - frame)
		bear._process(frame)
		elapsed += frame
	assert_lt(
		player.health, before,
		"holding the attack key and standing still must not be a free kill"
	)
