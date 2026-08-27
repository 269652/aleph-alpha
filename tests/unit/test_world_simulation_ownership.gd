extends GutTest

## Which process advances the shared world simulation (World.
## _owns_ecosystem_simulation / owns_ecosystem_simulation_for).
##
## This gate fronts EVERY ecology step: step_ecosystem, step_forage,
## step_tree_spread, step_tall_grass, step_wild_crops, step_flowers,
## step_worms, step_fruiting. `step_tree_spread` is also what advances
## `_world_age_seconds`, so when the gate is closed the world CLOCK stops
## too -- season and weather freeze at their day-zero values.
##
## It was `_is_dedicated_server or multiplayer_peer == null`, which is false
## for the normal way the game is played: starting a world from the menu
## hosts it, so a peer exists and the process is not a dedicated server.
## Measured in the running game: `owns=false, age=0`. Nothing grew, no worm
## ever surfaced (it had never actually rained -- the weather was pinned to
## day zero), no fruit fell, and birds had nothing to forage. Every
## subsystem test passed throughout, because they call the step functions
## directly and never go through this gate.

const World = preload("res://scenes/world.gd")


## The case that was broken, and the one that matters most: a player who
## starts a world from the menu is hosting it, and is therefore its
## authority.
func test_a_player_hosting_their_own_world_owns_the_simulation():
	assert_true(World.owns_ecosystem_simulation_for(false, true, true))


func test_a_dedicated_server_owns_the_simulation():
	assert_true(World.owns_ecosystem_simulation_for(true, true, true))


## No networking at all -- nothing to defer to.
func test_a_solo_session_with_no_peer_owns_the_simulation():
	assert_true(World.owns_ecosystem_simulation_for(false, false, false))


## The one case that must NOT own it: a client connected to someone else's
## world, which would otherwise run a second, divergent simulation on top of
## the authoritative one.
func test_a_connected_client_does_not_own_the_simulation():
	assert_false(World.owns_ecosystem_simulation_for(false, true, false))


## A step function with green unit tests and NO production caller. Every
## test in test_earth_chunk_manager.gd calls step_wild_crops directly, so
## the sim was provably correct and provably never run: in a real session
## wild crops only ever had the maturity _seed_initial_patches gave them at
## chunk creation, and spread never fired once. This file's own header was
## written about exactly this shape one level further in -- so the guard
## belongs here, next to it.
##
## A source-contract test rather than a behavioural one: standing up a whole
## World node headlessly to spy the call is not worth the fight, and this
## file is pure and instant (it only preloads scenes/world.gd), which is why
## it is the right home rather than the 10-minute test_earth_chunk_manager.
## Same spirit as test_ground_tint.gd's SHADER_CODE assertions, which this
## codebase already accepts for things a headless run cannot otherwise see.
func test_the_ecology_batch_advances_wild_crops_like_every_other_plant_sim():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _step_ecology_batch")
	assert_gt(start, -1, "the ecology batch must still be called that")
	var body_end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, body_end - start)
	assert_true(
		body.contains("step_tall_grass"),
		"the premise: this really is the batch that fronts the plant sims"
	)
	assert_true(
		body.contains("step_wild_crops"),
		"wild crops must be advanced by the batch, not only by their own tests"
	)
