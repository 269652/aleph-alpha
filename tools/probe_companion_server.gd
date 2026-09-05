extends SceneTree

## Dev tool: keeps a bare Godot process alive for a fixed window so the
## companion server can be inspected by hand (curl/a browser) without
## launching the full game.
##
## Does NOT instantiate CompanionServer itself -- it is a registered
## autoload (project.godot's [autoload]), and Godot instantiates every
## registered autoload for ANY process boot, including a bare `-s
## script.gd` one like this, before this script's own _initialize() ever
## runs. An earlier version of this file manually did `CompanionServer.new()
## ; root.add_child(...)` here too, which just raced the autoload's own
## instance for the same port and always lost (a harmless but confusing
## "could not bind" warning on every single run, since the autoload's
## instance had already bound it first by the time this script's own copy
## tried).
##
## Usage: godot --headless --path . -s tools/probe_companion_server.gd -- [seconds]
## (the autoload listens on CompanionRouter.PORT regardless of this
## script; this just keeps the process running for `seconds` -- default
## _DEFAULT_RUN_SECONDS -- then exits. Manual-inspection tool, not a
## persistent server -- for that, run the actual game, where the same
## autoload stays up for the whole play session instead of a fixed window)

const _DEFAULT_RUN_SECONDS := 20.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var run_seconds := _DEFAULT_RUN_SECONDS if args.is_empty() else float(args[0])
	print("probe_companion_server: listening for %.0fs..." % run_seconds)
	await create_timer(run_seconds).timeout
	print("probe_companion_server: done")
	quit()
