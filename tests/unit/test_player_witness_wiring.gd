extends GutTest

## docs/concept/spell_weaving.md: the four phenomena that were "specified and
## tabled but have no call site yet", actually raised.
##
## WitnessConditions is pinned by test_witness_conditions.gd. What is
## asserted here is that the Player really assembles the facts from live
## state and really grants the mote -- so `shock_damage`, `illuminate`,
## `slow` and `fear` stop being reachable only through the dev console.

const PlayerScene = preload("res://scenes/player.tscn")
const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const WitnessConditions = preload("res://src/gameplay/witness_conditions.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	player.queue_free()


func _player_source() -> String:
	return FileAccess.get_file_as_string("res://scenes/player.gd")


# -- every condition really grants its mote ------------------------------

## The behavioural half: handing the character a real moment really puts the
## real mote in the real pouch.
func test_every_condition_phenomenon_really_grants_its_mote():
	for phenomenon in WitnessConditions.CONDITION_PHENOMENA:
		var atom := SpellMote.first_witness_atom_for(String(phenomenon))
		assert_ne(atom, "", "precondition: %s teaches something" % phenomenon)
		assert_true(player.witness(String(phenomenon)), "%s is new to this character" % phenomenon)
		assert_eq(int(player.motes().get(atom, 0)), 1, "%s reached the pouch" % phenomenon)


## Once only -- a character who stood in one storm has learned the storm.
func test_a_phenomenon_teaches_once_however_long_it_lasts():
	assert_true(player.witness(SpellMote.PHENOMENON_CAUGHT_IN_A_STORM))
	assert_false(player.witness(SpellMote.PHENOMENON_CAUGHT_IN_A_STORM), "the second storm is weather")


## Four of twenty-five atoms were unobtainable. After this they are not.
func test_the_four_unreachable_atoms_are_reachable():
	for phenomenon in [
		SpellMote.PHENOMENON_CAUGHT_IN_A_STORM,
		SpellMote.PHENOMENON_HUNGRY_IN_THE_DARK,
		SpellMote.PHENOMENON_CLIMBED_HARD_GROUND,
		SpellMote.PHENOMENON_HUNTED,
	]:
		player.witness(String(phenomenon))
	assert_eq(player.motes().size(), 4, "four atoms that could not be come by, now come by")


# -- and the step really asks ---------------------------------------------

func test_the_step_asks_the_shared_rule():
	assert_true(
		_player_source().contains("WitnessConditions.taught_by"),
		"one place answers what a moment teaches"
	)


## The scattered ad-hoc checks are gone: two places deciding what freezing
## teaches is exactly the drift every shared rule in this overhaul replaced.
func test_the_old_scattered_checks_are_gone():
	var source := _player_source()
	assert_false(
		source.contains("witness(SpellMote.PHENOMENON_FROZE)"),
		"freezing is decided by the shared rule now, not inline"
	)
	assert_false(
		source.contains("witness(SpellMote.PHENOMENON_WARMED_AT_A_FIRE)"),
		"and so is the fire"
	)


## Venom stays an event, raised where the bite lands -- never a condition.
func test_venom_is_still_raised_by_the_bite():
	assert_true(_player_source().contains("witness(SpellMote.PHENOMENON_ENVENOMATED)"))


# -- the facts are live ---------------------------------------------------

func test_the_facts_are_read_off_real_state():
	var source := _player_source()
	for fact in ["is_freezing", "is_starving", "current_weather", "slope_at_global"]:
		assert_true(source.contains(fact), "%s is a real reading, not a literal" % fact)


## Being hunted is a real predator with the player in its senses, not a flag
## somebody set.
func test_being_hunted_is_a_real_predator_scan():
	var source := _player_source()
	assert_true(source.contains("_is_being_hunted"), "the player really looks")
	var body_start := source.find("func _is_being_hunted")
	assert_gt(body_start, -1)
	var body := source.substr(body_start, 1400)
	assert_true(body.contains("is_predator"), "only a predator hunts you")
	assert_true(body.contains("sense_radius_tiles"), "and only once it can sense you")
