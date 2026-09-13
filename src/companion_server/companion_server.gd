extends Node

## The companion webserver's real socket glue -- owns a TCPServer bound to
## 127.0.0.1, accepts connections, and dispatches each request through the
## pure parser/router/view/response modules. Every branch/decision that
## CAN be pure already is (companion_http_request.gd, companion_router.gd,
## the view renderers), leaving this file as thin as possible on purpose.
## The glue itself is covered by tests/unit/test_companion_server.gd over a
## real loopback socket on an OS-assigned port (listen_port below). It
## started out deliberately untested -- the same "engine side effects
## aren't unit-tested" boundary src/licensing/github_device_auth.gd draws
## for its real HTTPRequest glue -- until a live bug (the pause hang, see
## _ready) proved the one thing that can go wrong here, the Node
## lifecycle, is exactly what no pure test ever sees.
##
## Registered as an autoload (project.godot's [autoload]), not instanced
## from scenes/world.gd: world.gd's _ready() re-runs on
## get_tree().reload_current_scene() (every New Game / license retry), and a
## node instanced there would rebind its socket every time that happens. An
## autoload survives scene reloads, matching SelfIntegrity/LicenseGate's own
## rationale for being autoloads rather than scene nodes.
##
## Read-only by construction: every route only ever reads a freshly loaded
## PlayerSave dict and renders it -- no route here writes to the save, a
## wallet, or anything else (companion_server.md pillar 2, "the server
## proposes, the core decides" -- Tier 1 has nothing to propose, it only
## shows).

const CompanionHttpRequest = preload("res://src/companion_server/companion_http_request.gd")
const CompanionHttpResponse = preload("res://src/companion_server/companion_http_response.gd")
const CompanionRouter = preload("res://src/companion_server/companion_router.gd")
const CompanionCharacterSheetView = preload("res://src/companion_server/companion_character_sheet_view.gd")
const CompanionItemCatalogView = preload("res://src/companion_server/companion_item_catalog_view.gd")
const CompanionItemDetailView = preload("res://src/companion_server/companion_item_detail_view.gd")
const CompanionCompanionsView = preload("res://src/companion_server/companion_companions_view.gd")
const CompanionKeptAnimalsReader = preload("res://src/companion_server/companion_kept_animals_reader.gd")
const PlayerSave = preload("res://src/gameplay/player_save.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CraftedItemRegistry = preload("res://src/gameplay/crafted_item_registry.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

## Read bytes only up to this size per request -- Tier 1 traffic is a bare
## GET request line plus a couple of small browser headers; 4KiB is
## generously larger than any real request this server will ever receive.
const _MAX_REQUEST_BYTES := 4096

## A loopback request's bytes can land a tick or two after accept() rather
## than in the same frame -- bounded retry beats either blocking forever or
## dropping a real, just-slightly-late request. 20x1ms is well under one
## visible frame and far more than real loopback latency ever needs.
const _POLL_ATTEMPTS := 20
const _POLL_DELAY_MSEC := 1

## The port _ready() binds. The autoload leaves it at CompanionRouter.PORT;
## a test instance sets it to 0 BEFORE entering the tree to get an
## OS-assigned ephemeral port instead (see bound_port()), so it never
## races the real autoload for 8731 the way a second hand-made copy on the
## same port would (tools/probe_companion_server.gd's header).
var listen_port: int = CompanionRouter.PORT

var _tcp_server: TCPServer


func _ready() -> void:
	# scenes/world.gd pauses the whole SceneTree while the main menu is up
	# (_show_main_menu), while the settings overlay is open
	# (_toggle_settings_menu) and for the joust/handheld Easter eggs. A node
	# that inherits that pause state never runs _process, so every
	# connection was accepted by the OS listen backlog and then hung with
	# no response for as long as the menu was up (live, 2026-09-12). The
	# server has nothing to respect in a pause: it reads a saved file,
	# never live world state.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(listen_port, "127.0.0.1")
	if err != OK:
		# Most likely another running instance (a second dev/test run)
		# already bound this port -- the companion server is optional and
		# must never take the game down for a reason this unrelated.
		push_warning("CompanionServer: could not bind 127.0.0.1:%d (err %d) -- companion server disabled this session." % [listen_port, err])
		_tcp_server = null
		return
	print("Companion server: http://127.0.0.1:%d/" % bound_port())


## The port actually being served this session -- the OS-assigned one when
## listen_port was 0 -- or 0 when the bind failed and the server is off.
func bound_port() -> int:
	return 0 if _tcp_server == null else _tcp_server.get_local_port()


func _process(_delta: float) -> void:
	if _tcp_server == null or not _tcp_server.is_connection_available():
		return
	_serve(_tcp_server.take_connection())


func _serve(connection: StreamPeerTCP) -> void:
	# A connection that never sends bytes within the poll window (a stray
	# TCP probe, a client that connected then hung up) gets no response --
	# inventing a status code companion_http_response.gd's own tests don't
	# cover would be untested behavior with no real client to observe it.
	var raw := _read_request(connection)
	if not raw.is_empty():
		connection.put_data(_response_for(CompanionHttpRequest.parse(raw)))
	connection.disconnect_from_host()


func _read_request(connection: StreamPeerTCP) -> PackedByteArray:
	for _attempt in range(_POLL_ATTEMPTS):
		connection.poll()
		var available := connection.get_available_bytes()
		if available > 0:
			return connection.get_data(mini(available, _MAX_REQUEST_BYTES))[1]
		OS.delay_msec(_POLL_DELAY_MSEC)
	return PackedByteArray()


func _response_for(parsed: Dictionary) -> PackedByteArray:
	if not parsed.get("ok", false) or parsed.method != "GET":
		return CompanionHttpResponse.build(404, "text/plain", "not found")
	var save_dict := PlayerSave.new().load_data()
	var catalog := ItemCatalog.new()
	catalog.use_crafted_registry(CraftedItemRegistry.from_dicts(save_dict.get("crafted_items", {})))
	var routed := CompanionRouter.route_for(parsed.path)
	match routed.route:
		"character_sheet":
			return CompanionHttpResponse.build(200, "text/html", CompanionCharacterSheetView.render(save_dict, catalog))
		"item_catalog":
			return CompanionHttpResponse.build(200, "text/html", CompanionItemCatalogView.render(save_dict, catalog, parsed.get("query", {})))
		"item_detail":
			var recipe_book := CraftingRecipeBook.new()
			return CompanionHttpResponse.build(200, "text/html", CompanionItemDetailView.render(routed.item_id, catalog, recipe_book))
		"companions":
			var kept_animals := CompanionKeptAnimalsReader.read_all()
			return CompanionHttpResponse.build(200, "text/html", CompanionCompanionsView.render(save_dict, kept_animals))
		_:
			return CompanionHttpResponse.build(404, "text/html", "<p>not found</p>")
