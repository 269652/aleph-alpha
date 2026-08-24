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
