extends GutTest

## Pins the BOOT CONTRACT that the rest of the licensing tests deliberately
## leave out. test_license_gate.gd/test_self_integrity.gd both state they
## cover "decision logic only, not the Node-lifecycle glue" -- a sound
## boundary, but it left one thing nothing at all asserted: that the two
## gates are actually REGISTERED as autoloads in project.godot.
##
## That gap shipped a real, total launch failure. self_integrity.gd's own
## header says "Registered as an autoload (see project.godot) so this runs
## BEFORE the main scene loads", and world.gd's _ready() calls
## SelfIntegrity.require_verified() by that global name -- but for three
## commits (2913e5b..a7f9b52) the autoload line was missing from
## project.godot. GDScript resolves autoload names at COMPILE time, so the
## main scene's script failed to parse outright:
##
##     Parse Error: Identifier "SelfIntegrity" not declared in the current scope.
##     ERROR: Failed to load script "res://scenes/world.gd" with error "Parse error".
##
## Not a degraded mode -- the game could not start at all, in the editor or
## an export. Every existing licensing test still passed the whole time,
## because each one preloads its subject by PATH; none went through the
## global autoload name that boot actually depends on.
##
## So these tests assert the wiring itself rather than any decision logic.

const LICENSING_AUTOLOADS := {
	"SelfIntegrity": "res://src/licensing/self_integrity.gd",
	"LicenseGate": "res://src/licensing/license_gate.gd",
}


## The direct regression test for the shipped bug: the main scene's script
## must actually compile. This is the failure exactly as a player met it --
## load the main scene the way the engine does at boot. Any undeclared
## identifier in it (a missing autoload being the way this bug happened,
## but not the only way) makes this null, so this guards the whole class of
## "main scene no longer parses", not just the one name that broke.
func test_the_main_scene_script_still_compiles():
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_ne(main_scene, "", "project.godot must declare a main scene")
	var script: Resource = load("res://scenes/world.gd")
	assert_not_null(
		script,
		"res://scenes/world.gd failed to compile -- the game cannot launch at all. " +
		"A missing autoload in project.godot is the usual cause (see this file's header)."
	)


## The specific contract each gate's own header claims for itself. Checked
## by the global name because that is what world.gd compiles against -- a
## file existing at the right path is NOT the same thing as it being wired,
## which is precisely how the bug slipped through a green suite.
func test_both_licensing_gates_are_registered_autoloads():
	for autoload_name: String in LICENSING_AUTOLOADS:
		assert_true(
			ProjectSettings.has_setting("autoload/%s" % autoload_name),
			"%s is referenced as a global (see scenes/world.gd) but is not " % autoload_name +
			"registered in project.godot's [autoload] section"
		)


## The path each autoload points at must exist, and be the licensing script
## it claims to be -- a registered autoload aimed at a missing/renamed file
## fails at boot just as hard as no registration at all.
func test_licensing_autoloads_point_at_scripts_that_exist():
	for autoload_name: String in LICENSING_AUTOLOADS:
		var setting := "autoload/%s" % autoload_name
		if not ProjectSettings.has_setting(setting):
			continue  # already reported by the registration test above
		var value: String = ProjectSettings.get_setting(setting)
		# Godot prefixes a singleton autoload's path with "*".
		var path := value.trim_prefix("*")
		assert_eq(
			path,
			LICENSING_AUTOLOADS[autoload_name],
			"%s must point at its documented script path" % autoload_name
		)
		assert_true(
			ResourceLoader.exists(path),
			"%s's autoload path %s does not exist" % [autoload_name, path]
		)


## Every OTHER autoload the project declares gets the same existence check,
## so this guards the same failure mode for autoloads added later without
## anyone remembering to come back here.
func test_every_declared_autoload_points_at_a_file_that_exists():
	var checked := 0
	for setting in ProjectSettings.get_property_list():
		var name: String = setting.name
		if not name.begins_with("autoload/"):
			continue
		var value = ProjectSettings.get_setting(name)
		if typeof(value) != TYPE_STRING:
			continue
		var path: String = String(value).trim_prefix("*")
		if path == "":
			continue
		checked += 1
		assert_true(
			ResourceLoader.exists(path),
			"autoload %s points at %s, which does not exist" % [name, path]
		)
	assert_gt(checked, 0, "expected project.godot to declare at least one autoload")
