extends GutTest

## docs/concept/dodge.md: the answer a player is allowed to give.
##
## Measured before this: `src/gameplay/dodge.gd` was a complete, tested pure
## module with ZERO consumers outside `SpeciesBite` reading two of its
## constants. `grep -rn "dodge\|Dodge" scenes/player.gd` returned nothing;
## no `dodge` action existed in `Keybindings.ACTIONS`; and
## `grep -rn "invulner\|invincib\|iframe" scenes/player.gd` returned one
## comment. The player had no i-frames of any kind.
##
## Which means `docs/concept/predator_profiles.md` -- whose two windup
## anchors are `Dodge.INVINCIBLE_DURATION` and `Dodge.COOLDOWN_DURATION` by
## name -- had balanced the entire predator roster against a verb the player
## could not perform.

const PlayerScene = preload("res://scenes/player.tscn")
const Dodge = preload("res://src/gameplay/dodge.gd")
const SprintCost = preload("res://src/gameplay/sprint_cost.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)
	player.survival.stamina = 1.0


func after_each():
	player.queue_free()


# -- the distance, derived rather than typed -------------------------------

## You move at the speed you can already move, for exactly as long as you
## are untouchable. Nothing new is chosen.
func test_the_dash_is_a_sprint_for_the_length_of_the_window():
	assert_almost_eq(
		Dodge.distance_px(),
		SprintCost.sprint_speed_px_per_second() * Dodge.INVINCIBLE_DURATION,
		0.0001
	)


## And the number that falls out is a real one: a human evasive dive or
## shoulder roll covers roughly one and a half to two metres.
func test_a_dodge_covers_about_what_a_diving_human_covers():
	var metres: float = Dodge.distance_px() / GroundSlide.PX_PER_METER
	assert_gt(metres, 1.4, "shorter than this is a flinch, not a dive")
	assert_lt(metres, 2.1, "further than this is a leap")


## The load-bearing one: a dodge begun from inside anything's reach ends
## outside it. If this stopped being true the verb would be decoration, so
## it is asserted rather than left to arithmetic nobody re-does.
func test_a_dodge_carries_you_out_of_a_bites_reach():
	assert_gt(Dodge.distance_px(), CreatureMarker.ATTACK_RANGE)


## Movement costs what movement costs (docs/concept/survival.md's stamina
## scope): exactly a sprint of the same length, never a cheaper way to
## cross ground.
func test_a_dodge_costs_exactly_the_sprint_it_is():
	assert_almost_eq(
		Dodge.stamina_cost(),
		SprintCost.stamina_for_seconds(Dodge.INVINCIBLE_DURATION, true),
		0.0001
	)


# -- the verb -------------------------------------------------------------

func test_the_dodge_is_a_key_a_player_can_press():
	var bound: Array = Keybindings.new().action_names()
	assert_true(bound.has("dodge"), "a verb with no key is not a verb")


func test_a_dodge_really_happens():
	assert_true(player.dodge(), "it is allowed")
	assert_true(player.is_invincible(), "and it grants the window")


## Driven through `_knockback_velocity`, the boundary the shove itself is
## already tested at, rather than through `move_and_slide` -- a unit test
## has no physics frame, and what matters is that the verb really commits a
## displacement, not that Godot integrates it.
func test_a_dodge_really_moves_you():
	player.dodge()
	var velocity: Vector2 = player._knockback_velocity(Vector2.ZERO, 1.0 / 60.0)
	assert_gt(velocity.length(), 0.0, "a dodge in place is a block button")


## And it commits the whole distance, over exactly the window it is
## untouchable for -- the two are one interval, not two that could disagree.
func test_the_dash_and_the_window_are_the_same_interval():
	player.dodge()
	var travelled := 0.0
	var step := Dodge.INVINCIBLE_DURATION / 60.0
	for _i in 60:
		travelled += player._knockback_velocity(Vector2.ZERO, step).length() * step
	assert_almost_eq(travelled, Dodge.distance_px(), 0.5)
	assert_almost_eq(player._knockback_velocity(Vector2.ZERO, step).length(), 0.0, 0.0001)


func test_a_dodge_spends_the_legs():
	var before: float = player.survival.stamina
	player.dodge()
	assert_almost_eq(player.survival.stamina, before - Dodge.stamina_cost(), 0.0001)


# -- what the window refuses ----------------------------------------------

## The whole point. Blocking reduces, armour soaks, a dodge REFUSES.
func test_a_blow_inside_the_window_does_not_land_at_all():
	player.dodge()
	var before: float = player.health
	player.take_damage(25.0)
	assert_almost_eq(player.health, before, 0.0001, "the blow was refused, not softened")


## And it raises no receipt either: nothing happened to answer for.
func test_a_refused_blow_answers_nothing():
	player.dodge()
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))
	player.take_damage(25.0)
	assert_eq(seen.size(), 0)


## Pillar 5: you cannot roll away from something already in your blood.
func test_a_poison_already_inside_you_is_not_dodgeable():
	player.dodge()
	var before: float = player.health
	player.take_tick_damage(5.0)
	assert_lt(player.health, before, "venom does not care that you rolled")


func test_the_window_really_closes():
	player.dodge()
	player._dodge_timers_step(Dodge.INVINCIBLE_DURATION * 2.0)
	assert_false(player.is_invincible())
	var before: float = player.health
	player.take_damage(25.0)
	assert_lt(player.health, before, "the window is a window, not a state")


# -- what refuses the dodge -----------------------------------------------

func test_a_second_dodge_inside_the_cooldown_refuses():
	assert_true(player.dodge())
	assert_false(player.dodge(), "an answer you can spam is an invincibility toggle")


func test_the_cooldown_really_runs_out():
	player.dodge()
	player._dodge_timers_step(Dodge.COOLDOWN_DURATION * 1.1)
	assert_true(player.dodge(), "and then you may answer again")


## "Exhausted" on the survival panel and "cannot dodge" are one fact, the
## same single-source rule the sprint already follows.
func test_winded_legs_cannot_roll():
	player.survival.stamina = SurvivalMeters.EXHAUSTED_THRESHOLD
	assert_false(player.dodge())


func test_a_dead_character_does_not_dodge():
	player.take_damage(player.max_health + 10.0)
	assert_false(player.dodge())


func test_a_sleeper_does_not_dodge():
	player.begin_rest()
	assert_false(player.dodge())


## A refusal is a sentence, like every other verb in this overhaul.
## And a refusal is never muted by the success that caused it: pressing
## dodge again the instant after a roll is the commonest press in the game,
## and a press that says nothing teaches a player the key is broken.
func test_every_refusal_says_why():
	player.dodge()
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))
	player.dodge()
	assert_eq(seen.size(), 1, "a refused press still answers")
	assert_true(bool(seen[0]["failed"]))
	assert_ne(String(seen[0]["message"]), "", "and it says something")


func test_the_dodge_answers_when_it_works():
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))
	player.dodge()
	assert_eq(seen.size(), 1)
	assert_false(bool(seen[0]["failed"]))
	assert_eq(String(seen[0]["action"]), "dodge")


func test_the_feedback_table_knows_the_verb():
	assert_true(Answerback.has_feedback("dodge"))
