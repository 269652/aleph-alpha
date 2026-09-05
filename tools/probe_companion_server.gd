extends SceneTree

## Dev tool: runs the companion server standalone for a fixed window so its
## real HTTP responses can be inspected by hand (curl/a browser) without
## launching the full game -- instances the exact autoload class, just
## driven from a plain SceneTree instead of project.godot's autoload list,
## so this is the same code path a real play session runs.
##
## Usage: godot --headless --path . -s tools/probe_companion_server.gd
## (listens on CompanionRouter.PORT for _RUN_SECONDS, then exits)

const CompanionServer = preload("res://src/companion_server/companion_server.gd")

const _RUN_SECONDS := 20.0


func _initialize() -> void:
	var server := CompanionServer.new()
	root.add_child(server)
	print("probe_companion_server: listening for %.0fs..." % _RUN_SECONDS)
	await create_timer(_RUN_SECONDS).timeout
	print("probe_companion_server: done")
	quit()
