extends GutTest

## The CompanionServer transport itself (src/companion_server/
## companion_server.gd) -- the Node-lifecycle glue every other
## test_companion_*.gd file deliberately leaves out. A real, live-confirmed
## bug is what earned it a test file of its own (2026-09-12): scenes/world.gd
## pauses the whole SceneTree while the main menu is up (_show_main_menu),
## while the settings overlay is open (_toggle_settings_menu) and for the
## joust/handheld Easter eggs, and a server node that merely INHERITS the
## tree's pause state stops taking connections the moment the menu appears.
## Every connection to 127.0.0.1:8731 was accepted by the OS listen backlog
## and then hung with no response for as long as the menu was up, while the
## game itself stayed fully responsive. No pure module could have caught
## that, so this file exercises the glue over a real loopback socket.
##
## Isolation: each round-trip test instantiates its OWN CompanionServer on
## an OS-assigned ephemeral port (listen_port = 0). It never instantiates a
## second copy on CompanionRouter.PORT -- tools/probe_companion_server.gd's
## header explains why that only ever races the real autoload (and, on a dev
## machine, a running game) for the same port and loses. The registered
## autoload is checked structurally instead (its process_mode), since
## whether it managed to bind 8731 at all depends on what else is running
## on the machine.

const CompanionServerScript = preload("res://src/companion_server/companion_server.gd")
const CompanionRouter = preload("res://src/companion_server/companion_router.gd")

var _client: StreamPeerTCP


func before_each() -> void:
	_client = StreamPeerTCP.new()


func after_each() -> void:
	# A test that failed or errored part-way must never leave the tree
	# paused for every test that runs after it.
	get_tree().paused = false
	_client.disconnect_from_host()
	_client = null


## Untyped on purpose: on a typed instance a missing member is a PARSE
## error, which GUT only reports as a discovery warning and then silently
## skips the whole file -- dynamic access fails loudly at runtime instead.
func _spawn_server():
	var server = CompanionServerScript.new()
	server.listen_port = 0
	add_child_autofree(server)
	return server


# -- listening ----------------------------------------------------------------


func test_an_instance_binds_an_os_assigned_port_when_told_to_listen_on_port_zero() -> void:
	var server = _spawn_server()
	assert_gt(server.bound_port(), 0, "listen_port = 0 must bind a real, OS-assigned ephemeral port")
	assert_ne(
		server.bound_port(), CompanionRouter.PORT,
		"an ephemeral port must never contend with the real autoload's own port"
	)
