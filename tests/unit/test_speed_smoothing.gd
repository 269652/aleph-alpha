extends GutTest

## The composed speed multiplier, on both the player and creatures (see
## MovementPenalty).

const PlayerScene = preload("res://scenes/player.tscn")
const Player = preload("res://scenes/player.gd")
const MovementPenalty = preload("res://src/gameplay/movement_penalty.gd")
const WoundModel = preload("res://src/gameplay/wound_model.gd")

var player: Player


func before_each():
	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.health = player.max_health


func after_each():
	remove_child(player)
	player.free()


## A gash on the player and a gash on a deer are mechanically the same real
## thing -- that is the wound model's own claim -- but only the deer was ever
## slowed by one. The player bled and kept walking at full pace.
func test_a_wounded_player_is_slowed_like_a_wounded_animal():
	var healthy := player._wound_speed_multiplier()
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	assert_lt(player._wound_speed_multiplier(), healthy)


func test_an_unwounded_player_is_not_slowed():
	assert_eq(player._wound_speed_multiplier(), 1.0)


## ...and it is the SAME rule the animal side uses, not a second one.
func test_the_players_wound_slow_is_the_animals_own_rule():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	assert_eq(player._wound_speed_multiplier(), WoundModel.speed_multiplier(player.wound_stacks()))


## The composition goes through MovementPenalty rather than multiplying
## straight -- which is what stops six ordinary conditions leaving the player
## at two pixels a second.
func test_the_players_speed_is_composed_not_multiplied():
	var factors := [0.65, 0.3, 0.45]
	assert_gt(MovementPenalty.compose(factors), factors[0] * factors[1] * factors[2])
