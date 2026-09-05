extends GutTest

## Pins `project.godot`'s own identity fields against the name every other
## user-facing surface (README.md, LICENSE.md, the repository itself) uses.
##
## `application/config/name` had silently drifted to "Aleph Alfa" -- a typo
## invisible during ordinary `godot --path .` play, since nothing in-game
## ever reads it, but real on every surface a player or the Godot editor
## actually shows it: the OS window title bar, the Godot Project Manager's
## project list, and an exported build's own file properties. Found during
## a cross-alignment pass over README/progress/roadmap vs. the real
## implementation state (see docs/progress.md); this is the regression
## test that keeps it from drifting back unnoticed a second time.
##
## `godot` is not installed in this sandboxed environment (verified: no
## binary on PATH, no CI workflow that runs GUT), so this could not be
## executed here to observe the red/green transition directly -- confirmed
## instead by reading `ProjectSettings.get_setting`'s well-defined behavior
## against project.godot's literal `config/name="Aleph Alfa"` line, which
## can only ever return that exact string. Written red-first per this
## project's CLAUDE.md regardless: it must be run (`godot --headless -s
## addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/unit/test_project_config.gd -gexit`)
## on a machine with Godot before this fix is trusted.
func test_the_project_display_name_matches_the_games_real_name():
	var app_name = ProjectSettings.get_setting("application/config/name")
	assert_eq(
		app_name,
		"Aleph Alpha",
		"project.godot's application/config/name has drifted from the game's real name " +
		"(every other surface -- README.md, LICENSE.md, the repository itself -- calls it 'Aleph Alpha')"
	)
