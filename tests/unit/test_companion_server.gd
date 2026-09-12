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

## Real loopback latency is microseconds and the server answers inside the
## very frame it accepts on; a multi-second budget is orders of magnitude
## above that on any machine, so exhausting it can only mean nothing is
## answering (the bug itself), never a slow machine.
const RESPONSE_DEADLINE_MSEC := 5000
## Bounded synchronous spin for the client's non-blocking connect to
## complete (loopback: effectively immediate).
const CONNECT_ATTEMPTS := 500
const CONNECT_DELAY_MSEC := 1

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


## Connects to 127.0.0.1:`port`, sends one GET for `path` and returns the
## raw response text -- "" when nothing answered before the deadline.
## Connect + send happen synchronously inside ONE frame: the server's
## _read_request blocks the main thread for up to its poll window right
## after accepting, so a client that yielded a frame between connecting
## and sending would always miss that window. A real browser/curl writes
## the instant connect() returns, which this mirrors.
func _fetch(port: int, path: String) -> String:
	if _client.connect_to_host("127.0.0.1", port) != OK:
		return ""
	for _attempt in range(CONNECT_ATTEMPTS):
		_client.poll()
		if _client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		OS.delay_msec(CONNECT_DELAY_MSEC)
	if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return ""
	var request := "GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % path
	if _client.put_data(request.to_utf8_buffer()) != OK:
		return ""
	var received := PackedByteArray()
	var deadline := Time.get_ticks_msec() + RESPONSE_DEADLINE_MSEC
	while Time.get_ticks_msec() < deadline:
		_client.poll()
		# poll() only ever disconnects once the receive buffer is drained, so
		# a non-connected status here means the server's Connection: close
		# arrived after everything it wrote -- the response is complete. It
		# must be checked BEFORE get_available_bytes(), which logs an engine
		# error (and GUT fails the test) on the already-closed socket.
		if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var available := _client.get_available_bytes()
		if available > 0:
			var chunk: PackedByteArray = _client.get_data(available)[1]
			received.append_array(chunk)
		await get_tree().process_frame
	return received.get_string_from_utf8()


# -- listening ----------------------------------------------------------------


func test_an_instance_binds_an_os_assigned_port_when_told_to_listen_on_port_zero() -> void:
	var server = _spawn_server()
	assert_gt(server.bound_port(), 0, "listen_port = 0 must bind a real, OS-assigned ephemeral port")
	assert_ne(
		server.bound_port(), CompanionRouter.PORT,
		"an ephemeral port must never contend with the real autoload's own port"
	)


# -- the registered autoload ---------------------------------------------------


## The autoload must not inherit the SceneTree's pause state: world.gd
## pauses the tree for the main menu, the settings overlay and the
## joust/handheld Easter eggs, and an inheriting server stops taking
## connections for exactly that long (the 2026-09-12 hang).
func test_the_autoload_processes_regardless_of_the_tree_pause_state() -> void:
	var autoload := get_tree().root.get_node_or_null("CompanionServer")
	assert_not_null(autoload, "CompanionServer must be registered in project.godot's [autoload] section")
	if autoload == null:
		return
	assert_eq(
		autoload.process_mode, Node.PROCESS_MODE_ALWAYS,
		"CompanionServer must keep serving while the tree is paused (main menu, settings overlay)"
	)


# -- a real loopback round trip ------------------------------------------------


## Control for the paused case below: the same round trip against a tree
## that is running. A failure HERE means the transport/harness itself is
## broken, not the pause handling.
func test_serves_a_request_while_the_tree_is_running() -> void:
	var server = _spawn_server()
	var response := await _fetch(server.bound_port(), "/companions")
	assert_true(
		response.begins_with("HTTP/1.1 200 "),
		"expected a 200 from a running tree, got: '%s'" % response.left(60)
	)


## The live bug as a test: the identical request with the tree paused the
## way _show_main_menu/_toggle_settings_menu pause it. Before the fix the
## connection sits in the OS backlog and nothing ever answers.
func test_serves_a_request_while_the_tree_is_paused() -> void:
	var server = _spawn_server()
	get_tree().paused = true
	var response := await _fetch(server.bound_port(), "/companions")
	get_tree().paused = false
	assert_true(
		response.begins_with("HTTP/1.1 200 "),
		"no/bad response while the tree was paused (the main-menu hang), got: '%s'" % response.left(60)
	)
