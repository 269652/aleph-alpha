extends GutTest

## A bite you can see coming (docs/concept/predator_profiles.md, "The
## telegraph, in the engine").
##
## `SpeciesBite.windup_seconds` has been authored, fairness-tested and
## balanced against the player's own dodge since the table was written --
## and it was COMPLETELY DEAD. `grep -rn windup` outside `species_bite.gd`
## returned two comments. `_try_attack` checked the cooldown, checked the
## range, and dealt damage in the same call, so a bite was unavoidable by
## construction and the whole fairness model was arithmetic about a thing
## that never happened.
##
## These tests drive a REAL creature against a REAL player on real frames,
## because every number involved was already individually tested and the
## bite still could not be answered.

const PlayerScene = preload("res://scenes/player.tscn")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const BiteTell = preload("res://src/rendering/bite_tell.gd")
const Dodge = preload("res://src/gameplay/dodge.gd")

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


func _predator(species: String, offset: Vector2):
	var marker = renderer.spawn_single(
		creatures_parent, species, player.position + offset, manager, TerrainRenderer.TILE_SIZE
	)
	marker.info.is_aggroed = true
	return marker


func _windup_of(species: String) -> float:
	return SpeciesBite.windup_seconds_for(species, player.max_health)


func _run(marker, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		marker._process(FRAME)
		elapsed += FRAME


# -- the bite is no longer instantaneous ----------------------------------

## The whole point. A predator that walks into reach used to bite on that
## very frame, with the cooldown charged afterwards.
func test_a_bite_does_not_land_on_the_frame_it_is_decided():
	var wolf = _predator("wolf", Vector2(8.0, 0.0))
	var before: float = player.health
	wolf._try_attack(player)
	assert_almost_eq(player.health, before, 0.0001, "it commits; it does not connect")


func test_it_really_commits_to_the_bite():
	var wolf = _predator("wolf", Vector2(8.0, 0.0))
	wolf._try_attack(player)
	assert_true(wolf.is_winding_up(), "the jaws are coming")


## And the wait is the species' own, from the table that has always
## carried it -- never a number the marker invented.
func test_the_wait_is_the_species_own_windup():
	var bear = _predator("bear", Vector2(8.0, 0.0))
	bear._try_attack(player)
	assert_almost_eq(bear.windup_remaining(), _windup_of("bear"), 0.0001)


## A frail character is warned MORE, not less -- the table takes the
## player's live max health by design, and the marker must pass it through
## rather than baking one number per species.
##
## A QUARTER of the bar, not a half, and the reason is worth recording: the
## bear's authored 0.90 s floor dominates its computed requirement until the
## character is genuinely frail (0.48 s at full health, 0.78 s at half), so
## halving alone changes nothing and a test that halved would have been
## asserting the floor rather than the rule.
func test_a_frailer_character_is_warned_longer():
	var bear = _predator("bear", Vector2(8.0, 0.0))
	bear._try_attack(player)
	var hale: float = bear.windup_remaining()
	player.max_health = player.max_health * 0.25
	var other = _predator("bear", Vector2(8.0, 0.0))
	other._try_attack(player)
	assert_gt(other.windup_remaining(), hale)


func test_the_bite_lands_when_the_wait_runs_out():
	var wolf = _predator("wolf", Vector2(8.0, 0.0))
	var before: float = player.health
	wolf._try_attack(player)
	_run(wolf, _windup_of("wolf") + FRAME * 2.0)
	assert_lt(player.health, before, "a telegraph is not a reprieve")


# -- the freeze -----------------------------------------------------------

## Measured across the twelve biting profiles: if a creature keeps closing
## while it winds up, the dodge fails for ten of them -- a bear closes
## 62.2 px during its 0.90 s, against a dodge worth 20. Frozen, the gap at
## resolve is always R + 20 > 16.
func test_a_creature_plants_itself_while_it_winds_up():
	var bear = _predator("bear", Vector2(10.0, 0.0))
	bear._try_attack(player)
	var planted: Vector2 = bear.position
	_run(bear, _windup_of("bear") * 0.5)
	assert_almost_eq(bear.position.distance_to(planted), 0.0, 0.01, "it plants to strike")


# -- and it can be answered -----------------------------------------------

## The re-check that makes the dodge worth anything: without it the windup
## is a delayed guaranteed hit.
func test_a_target_that_leaves_reach_is_not_bitten():
	var wolf = _predator("wolf", Vector2(8.0, 0.0))
	var before: float = player.health
	wolf._try_attack(player)
	player.position = Vector2(400.0, 0.0)
	_run(wolf, _windup_of("wolf") + FRAME * 2.0)
	assert_almost_eq(player.health, before, 0.0001, "the jaws closed on nothing")


## End to end, through the real verb: see the tell, roll, and the bite
## finds empty ground.
func test_a_dodge_away_really_denies_the_bite():
	var bear = _predator("bear", Vector2(14.0, 0.0))
	var before: float = player.health
	bear._try_attack(player)
	# Away from it, which is what the claim is about: a dodge is a heading,
	# and a player who has just walked INTO a bear rolls into it.
	player._last_facing_direction = Vector2.LEFT
	player.dodge()
	for _i in 60:
		player._knockback_velocity(Vector2.ZERO, Dodge.INVINCIBLE_DURATION / 60.0)
		player.position += Vector2.LEFT * (Dodge.distance_px() / 60.0)
	_run(bear, _windup_of("bear") + FRAME * 2.0)
	assert_almost_eq(player.health, before, 0.0001, "twenty pixels beats sixteen")


## A whiff still costs the predator its recovery, so a dodge buys TIME
## rather than one skipped hit.
func test_a_bite_that_missed_still_costs_the_recovery():
	var wolf = _predator("wolf", Vector2(8.0, 0.0))
	wolf._try_attack(player)
	player.position = Vector2(400.0, 0.0)
	_run(wolf, _windup_of("wolf") + FRAME * 2.0)
	player.position = Vector2(8.0, 0.0)
	var before: float = player.health
	wolf._try_attack(player)
	assert_false(wolf.is_winding_up(), "it cannot simply try again")
	assert_almost_eq(player.health, before, 0.0001)


# -- who is owed a telegraph ----------------------------------------------

## The Alp does not strike at all (docs/concept/monsters.md entry 3), so it
## has nothing to telegraph.
func test_the_alp_never_winds_up():
	var alp = _predator("alp", Vector2(4.0, 0.0))
	alp._try_attack(player)
	assert_false(alp.is_winding_up())


## And a grazer owes no telegraph because it lands no bite -- a zero-length
## windup must not become a state a sheep sits in every frame.
func test_a_grazer_neither_winds_up_nor_bites():
	var deer = _predator("deer", Vector2(8.0, 0.0))
	var before: float = player.health
	deer._try_attack(player)
	assert_false(deer.is_winding_up())
	_run(deer, 1.0)
	assert_almost_eq(player.health, before, 0.0001)


# -- and it is visible ----------------------------------------------------

func test_a_winding_creature_visibly_rears():
	var bear = _predator("bear", Vector2(10.0, 0.0))
	var resting: Vector2 = bear.scale
	bear._try_attack(player)
	bear._process(FRAME)
	assert_gt(bear.scale.y, resting.y, "a bite nobody can see coming is not a telegraph")


## And it goes back to being its own size, rather than staying reared or
## snapping to a size the growth curve did not choose.
func test_the_rear_up_really_settles_again():
	var bear = _predator("bear", Vector2(10.0, 0.0))
	var resting: Vector2 = bear.scale
	bear._try_attack(player)
	_run(bear, _windup_of("bear") + FRAME * 3.0)
	assert_almost_eq(bear.scale.y, resting.y, 0.001)


## The shape is the module's, not a second opinion written into the marker.
func test_the_rear_up_is_the_shared_rule():
	var bear = _predator("bear", Vector2(10.0, 0.0))
	var resting: Vector2 = bear.scale
	bear._try_attack(player)
	bear._process(FRAME)
	var total := _windup_of("bear")
	var expected: Vector2 = BiteTell.scale_multiplier(bear.windup_remaining(), total)
	assert_almost_eq(bear.scale.y / resting.y, expected.y, 0.001)


# -- a committed animal is braced -----------------------------------------

## The hole the freeze opens, found by running the exchange rather than by
## reasoning about it: `test_a_player_who_only_swings_does_not_beat_a_bear_
## for_free` went green-to-red the moment the windup landed.
##
## The freeze is what makes the dodge real -- a creature that kept closing
## would defeat it for ten of the twelve biting profiles. But a frozen
## creature cannot close again either, so ANY shove during a windup makes
## the bite whiff. A bear is shoved 8 px per swing and winds up for 0.90 s,
## during which the player's 0.5 s swing lands twice: sixteen pixels, and
## the jaws close on nothing, for ever. That is precisely the unloseable
## fight this overhaul had just finished removing.
##
## So an animal that has planted itself to strike is BRACED. The asymmetry
## is the design: moving YOURSELF out of reach answers a bite; shoving the
## animal does not.
func test_a_planted_animal_is_not_shoved_off_its_strike():
	var bear = _predator("bear", Vector2(10.0, 0.0))
	bear._try_attack(player)
	var planted: Vector2 = bear.position
	bear.struck_by(player, 1.0, Vector2(60.0, 0.0))
	_run(bear, _windup_of("bear") * 0.5)
	assert_almost_eq(bear.position.distance_to(planted), 0.0, 0.01, "braced")


func test_a_shove_still_moves_an_animal_that_is_not_committed():
	var bear = _predator("bear", Vector2(30.0, 0.0))
	var standing: Vector2 = bear.position
	bear.apply_knockback(Vector2(60.0, 0.0))
	_run(bear, 0.2)
	assert_gt(bear.position.distance_to(standing), 0.0, "an unbraced animal still gives")


## And being struck still HURTS a committed animal, and still makes it
## angry -- only its footing is unmoved.
func test_a_braced_animal_is_still_hurt_by_the_blow():
	var bear = _predator("bear", Vector2(10.0, 0.0))
	bear._try_attack(player)
	var before: float = bear.info.health
	bear.struck_by(player, 5.0, Vector2(60.0, 0.0))
	assert_lt(bear.info.health, before)
	assert_eq(bear.aggressor(), player)


# -- what a commitment survives, and what it does not ----------------------

## The rule stated once and tested rather than left to be discovered: a
## commitment keeps running through a root, exactly as it keeps running
## through a shove. What a root takes away is the creature's FOOTING, and
## an animal held in place still snaps at what is in front of it.
##
## It is a behavioural change for the root spell -- a root used to prevent
## the bite outright, because the early return came before the AI decided
## anything -- so it is written down rather than absorbed silently.
func test_a_rooted_animal_still_finishes_the_bite_it_committed_to():
	var wolf = _predator("wolf", Vector2(8.0, 0.0))
	var before: float = player.health
	wolf._try_attack(player)
	wolf.apply_spell_debuff("root", 10.0)
	assert_true(wolf.is_rooted(), "precondition: it really is held")
	_run(wolf, _windup_of("wolf") + FRAME * 2.0)
	assert_lt(player.health, before, "a held animal still has jaws")


## And a creature killed mid-strike does not stay reared over its own
## corpse: the clock and the pose go together.
func test_a_creature_killed_mid_strike_does_not_stay_reared():
	var bear = _predator("bear", Vector2(10.0, 0.0))
	bear._try_attack(player)
	assert_true(bear.is_winding_up(), "precondition: it had committed")
	bear.take_damage(bear.info.max_health * 2.0)
	assert_false(bear.is_winding_up(), "a corpse is not about to bite anybody")
