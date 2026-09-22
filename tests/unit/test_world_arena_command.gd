extends GutTest

## docs/concept/arena.md: the `/arena` verb, wired.
##
## Arena itself is pinned by test_arena.gd and the combat it stages by
## test_battle_loop.gd. What is asserted here is that World really offers
## the verb, really stages through the shared rule, and really hands the
## player the two things that otherwise make a battletest impossible -- the
## motes and, for a class with no pool, the mana.

const World = preload("res://scenes/world.gd")
const Arena = preload("res://src/gameplay/arena.gd")


func _world_source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func _function_body(name: String) -> String:
	var source := _world_source()
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


func test_the_verb_exists_at_all():
	assert_false(_function_body("_handle_arena_command").is_empty())


## Typed by a person, so it has to be routed from the console like every
## other verb, and listed where `/help` can find it.
func test_the_console_really_routes_it():
	var source := _world_source()
	assert_true(source.contains('"arena"'), "the command is registered")
	assert_true(
		_function_body("_handle_console_command").contains("_handle_arena_command")
		or source.contains("_handle_arena_command(args"),
		"and reaches its handler"
	)


# -- it stages through the shared rule -----------------------------------

func test_the_ring_is_the_shared_rules_own():
	var body := _function_body("_handle_arena_command")
	assert_true(body.contains("Arena.ring_radius_px_for"), "where they stand")
	assert_true(body.contains("Arena.ring_offsets"), "and how they are spread")


## The same species resolution `/spawn` already uses, with its friendly
## aliases, rather than a second opinion about what a "snake" is.
func test_it_resolves_species_the_way_spawn_already_does():
	assert_true(_function_body("_handle_arena_command").contains("ConsoleSpecies.resolve"))


## Real creatures out of the real renderer -- the arena stages, it never
## simulates.
func test_the_opposition_is_real_creatures_from_the_real_renderer():
	assert_true(_function_body("_handle_arena_command").contains("spawn_single"))


# -- and it hands over what makes a battletest possible ------------------

## Without motes there is nothing to weave, and a new character owns none.
func test_it_hands_over_the_motes():
	var body := _function_body("_handle_arena_command")
	assert_true(body.contains("Arena.loadout_motes"), "one of every atom")
	assert_true(body.contains("grant_mote"), "into the real pouch")


## A warrior has max_mana 0.0 and can never cast. The arena lends a pool.
func test_it_lends_a_pool_to_a_class_that_has_none():
	var body := _function_body("_handle_arena_command")
	assert_true(body.contains("Arena.mana_pool_for"), "through the shared rule")
	assert_true(body.contains("max_mana"), "and it really reaches the character")


## And says so. A tester who does not know their mana was topped up will
## misread every result after it.
func test_it_reports_what_it_did_including_the_loan():
	assert_true(_function_body("_handle_arena_command").contains("Arena.report_line"))


## A verb that refuses says why, the same rule every other refusal follows.
func test_an_unknown_species_is_a_sentence_rather_than_silence():
	var body := _function_body("_handle_arena_command")
	assert_true(body.contains("Unknown"), "name what was not understood")
	assert_true(body.contains("spawnable"), "and say what would have worked")


## A verb nobody can find is a verb nobody has. /help is how every other
## command in this console is discovered.
func test_the_verb_is_listed_in_help():
	assert_true(_world_source().contains("/arena"), "listed where /help prints it")
