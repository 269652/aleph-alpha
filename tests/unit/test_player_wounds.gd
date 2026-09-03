extends GutTest

## The player's side of the open-wound trigger (docs/concept/survival.md, "The
## four triggers" -> "Open wounds, not just HP").
##
## The same WoundModel a struck deer carries: a gash on the player and a gash
## on an animal are mechanically the same real thing, which is the honest
## answer to this project's own earlier open question about whether a combat
## gash and a butchering cut should be.

const PlayerScene = preload("res://scenes/player.tscn")
const Player = preload("res://scenes/player.gd")
const WoundModel = preload("res://src/gameplay/wound_model.gd")

var player: Player


func before_each():
	# Instantiated and put in the tree the way test_player.gd does: Player's
	# authority checks read `multiplayer`, which is null on a node that is not
	# in a scene tree.
	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.health = player.max_health


func after_each():
	remove_child(player)
	player.free()


func test_a_real_blow_opens_a_wound():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	assert_gt(player.wound_stacks(), 0)


func test_a_scratch_does_not():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND * 0.5)
	assert_eq(player.wound_stacks(), 0)


## The bleed: a wound keeps costing after the blow that made it.
func test_a_wound_bleeds():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	var after_the_hit := player.health
	player.step_wounds(5.0)
	assert_lt(player.health, after_the_hit)


func test_an_unwounded_player_does_not_bleed():
	var before := player.health
	player.step_wounds(20.0)
	assert_eq(player.health, before)


## Bandaging is the point of the mechanic: it closes the wound outright rather
## than waiting it out.
func test_bandaging_closes_the_wound():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	assert_gt(player.wound_stacks(), 0)
	player.bandage_wounds()
	assert_eq(player.wound_stacks(), 0)


## ...and it resets the sepsis clock, so binding a wound really does take the
## infection risk away rather than only pausing it.
func test_bandaging_takes_the_infection_risk_away():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	player.step_wounds(WoundModel.SECONDS_UNTIL_SEPSIS * 0.9)
	player.bandage_wounds()
	assert_eq(player.seconds_wounded, 0.0)


## An untreated wound is a real infection vector -- the actual mechanism
## behind wound sepsis. Endures well past the clock, since the roll is a
## chance rather than a certainty.
func test_an_untreated_wound_eventually_goes_septic():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	var elapsed := 0.0
	while elapsed < WoundModel.SECONDS_UNTIL_SEPSIS * 8.0:
		player.step_wounds(1.0)
		elapsed += 1.0
	assert_eq(player.sickness_id, WoundModel.SICKNESS_ID)


## ...and the clock keeps running after the BLEEDING has stopped. A cut stops
## bleeding in minutes and stays open for days; it is the open wound rather
## than the bleeding one that gets infected, so letting it clot is not the same
## as binding it.
func test_the_sepsis_clock_outlives_the_bleeding():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	player.step_wounds(WoundModel.DURATION_SECONDS + 5.0)
	assert_eq(player.wound_stacks(), 0, "it should have stopped bleeding by now")
	assert_gt(player.seconds_wounded, WoundModel.DURATION_SECONDS)


## A wound that is bound in time never does.
func test_a_wound_bound_in_time_never_goes_septic():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	player.step_wounds(WoundModel.SECONDS_UNTIL_SEPSIS * 0.5)
	player.bandage_wounds()
	var elapsed := 0.0
	while elapsed < WoundModel.SECONDS_UNTIL_SEPSIS * 8.0:
		player.step_wounds(1.0)
		elapsed += 1.0
	assert_eq(player.sickness_id, "")


# -- and what death does to it ----------------------------------------------


## Found by actually dying to a wolf: `_respawn` restored health, position and
## the input latch, and nothing else -- so a player came back still bleeding,
## still on the sepsis clock, still carrying whatever illness had been rolled.
##
## That is not survivable content, it is a soft lock: there is no bandage item
## and no cure in the game yet, so anything the body carries across death it
## carries forever. Death is documented as "a straight reset"
## (Player.max_health's own doc comment) -- so the body really has to reset.
func test_respawning_closes_your_wounds():
	player.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	player.step_wounds(WoundModel.SECONDS_UNTIL_SEPSIS * 0.5)
	player.take_damage(player.max_health * 2.0)
	assert_true(player.is_dead, "the test failed to kill the player")
	player._respawn()
	assert_eq(player.wound_stacks(), 0, "you came back still bleeding")
	assert_eq(player.seconds_wounded, 0.0, "you came back on the sepsis clock")


## Likewise the illness itself, and the cold that could still be running you
## toward another one.
func test_respawning_leaves_the_illness_behind():
	player.sickness_id = WoundModel.SICKNESS_ID
	player.sickness_severity = 0.7
	player.sickness_diagnosed = true
	player.cold_exposure = 1.0
	player.take_damage(player.max_health * 2.0)
	player._respawn()
	assert_eq(player.sickness_id, "")
	assert_eq(player.sickness_severity, 0.0)
	assert_false(player.sickness_diagnosed)
	assert_eq(player.cold_exposure, 0.0)
