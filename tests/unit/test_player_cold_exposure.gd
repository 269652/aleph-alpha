extends GutTest

## The player half of prolonged-cold exposure (docs/concept/survival.md, "The
## four triggers"). The clock itself is pure and lives in ColdExposure; this is
## the wire that makes standing in the sleet actually mean something.

const PlayerScene = preload("res://scenes/player.tscn")
const Player = preload("res://scenes/player.gd")
const ColdExposure = preload("res://src/gameplay/cold_exposure.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")

var player: Player


func before_each():
	# Instantiated and put in the tree the way test_player.gd does: Player's
	# authority checks read `multiplayer`, which is null on a node that is not
	# in a scene tree.
	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)


func after_each():
	remove_child(player)
	player.free()


## Puts the player at a body temperature and runs the exposure clock for
## `seconds`, without needing a world to be cold at them.
func _endure(warmth: float, seconds: float) -> void:
	player.survival.warmth = warmth
	var elapsed := 0.0
	while elapsed < seconds:
		player.step_cold_exposure(1.0)
		elapsed += 1.0


func test_a_warm_player_carries_no_exposure():
	_endure(1.0, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 2.0)
	assert_eq(player.cold_exposure, 0.0)


func test_standing_in_the_cold_accumulates_exposure():
	_endure(SurvivalMeters.COLD_THRESHOLD - 0.05, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 0.5)
	assert_gt(player.cold_exposure, 0.0)


## The consequence: a long enough exposure eventually makes you genuinely,
## diagnosably ill -- not merely slow. Rolled rather than certain, so this
## endures well past the clock to assert the outcome is REACHABLE at all.
func test_a_long_enough_exposure_eventually_makes_you_ill():
	_endure(0.0, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 4.0)
	assert_eq(player.sickness_id, ColdExposure.SICKNESS_ID)


## ...and a mild chill never does, however long it goes on. This is the whole
## claim of the mechanic: prolonged cold is a duration effect, and a body that
## is merely chilly is not on a slow path to hypothermia.
func test_being_merely_chilly_never_makes_you_ill():
	player.survival.warmth = SurvivalMeters.COLD_THRESHOLD + 0.01
	var elapsed := 0.0
	while elapsed < ColdExposure.SECONDS_TO_FULL_EXPOSURE * 4.0:
		player.step_cold_exposure(1.0)
		elapsed += 1.0
	assert_eq(player.sickness_id, "")


## Warming up before the clock runs out is a real escape, not a delay.
##
## Merely COLD rather than freezing, and only half way to the staging
## boundary: at warmth 0.0 the player is freezing, which accrues
## FREEZING_MULTIPLIER times faster and would be past the boundary before the
## rewarming even started.
func test_getting_warm_in_time_saves_you():
	_endure(
		SurvivalMeters.COLD_THRESHOLD - 0.05,
		ColdExposure.SECONDS_TO_FULL_EXPOSURE * ColdExposure.RISK_THRESHOLD * 0.5
	)
	assert_gt(player.cold_exposure, 0.0, "the player never got cold in the first place")
	_endure(1.0, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 4.0)
	assert_eq(player.sickness_id, "")
	assert_eq(player.cold_exposure, 0.0)


## Cold cannot overwrite an illness you already have -- Player.sickness_id
## holds ONE sickness, the same single-instance contract apply_disease_bite
## already respects.
func test_cold_does_not_overwrite_an_illness_you_already_have():
	player.sickness_id = "predator"
	player.sickness_severity = 0.5
	_endure(0.0, ColdExposure.SECONDS_TO_FULL_EXPOSURE * 4.0)
	assert_eq(player.sickness_id, "predator")
