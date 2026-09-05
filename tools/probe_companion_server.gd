extends SceneTree

## Dev tool: runs the companion server standalone for a fixed window so its
## real HTTP responses can be inspected by hand (curl/a browser) without
## launching the full game -- instances the exact autoload class, just
## driven from a plain SceneTree instead of project.godot's autoload list,
## so this is the same code path a real play session runs.
##
## Usage: godot --headless --path . -s tools/probe_companion_server.gd -- [seconds]
## (listens on CompanionRouter.PORT for `seconds` -- default _DEFAULT_RUN_SECONDS
## -- then exits; this is a manual-inspection tool, not a persistent server --
## for that, run the actual game, whose CompanionServer autoload stays up for
## the whole play session instead of a fixed window)

const CompanionServer = preload("res://src/companion_server/companion_server.gd")

const _DEFAULT_RUN_SECONDS := 20.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var run_seconds := _DEFAULT_RUN_SECONDS if args.is_empty() else float(args[0])
	var server := CompanionServer.new()
	root.add_child(server)
	print("probe_companion_server: listening for %.0fs..." % run_seconds)
	await create_timer(run_seconds).timeout
	print("probe_companion_server: done")
	quit()
