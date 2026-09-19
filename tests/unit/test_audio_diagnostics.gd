extends GutTest

## Names the most likely cause of a silent game from the real audio facts
## (see AudioDiagnostics, docs/concept/soundscape.md's "Diagnosing
## silence"). Reported live: "The game has no sound anymore... completely
## mute everywhere, I checked windows settings, the process is not muted."
##
## Pure: every fact is passed in, nothing is read from a live AudioServer
## or scene tree, so every branch is reachable headlessly -- the same
## "pure model, thin Node" split AudioSettings/NatureSoundscape already use.

const AudioDiagnostics = preload("res://src/audio/audio_diagnostics.gd")


func _facts(overrides: Dictionary = {}) -> Dictionary:
	# A healthy game, which each test then breaks in exactly one way.
	var facts := {
		"master_db": 0.0,
		"master_muted": false,
		"master_bus_index": 0,
		"volume_setting": 1.0,
		"soundscape_in_tree": true,
		"sfx_in_tree": true,
		"missing_streams": [],
		"paused": false,
	}
	for key in overrides:
		facts[key] = overrides[key]
	return facts


func test_a_healthy_game_reports_no_cause():
	assert_eq(AudioDiagnostics.silence_diagnosis(_facts()), "")


## The single most likely cause, and the only thing in this whole codebase
## that can silence everything at once: one slider drag to zero writes
## SILENT_BUS_DB to the Master bus and persists it across restarts.
func test_a_master_bus_at_the_silent_floor_is_named_with_its_setting():
	var diagnosis := AudioDiagnostics.silence_diagnosis(
		_facts({"master_db": -80.0, "volume_setting": 0.0})
	)
	assert_string_contains(diagnosis, "master volume")
	assert_string_contains(diagnosis, "keybindings.cfg")


func test_a_muted_master_bus_is_named_separately_from_a_quiet_one():
	var diagnosis := AudioDiagnostics.silence_diagnosis(_facts({"master_muted": true}))
	assert_string_contains(diagnosis.to_lower(), "muted")


## Boot returning before `add_child(_nature_soundscape.build())` -- the
## license gate and the GitHub identity check both do exactly this -- leaves
## a game with no audio nodes at all rather than quiet ones.
func test_audio_that_never_reached_the_tree_is_named():
	var diagnosis := AudioDiagnostics.silence_diagnosis(
		_facts({"soundscape_in_tree": false, "sfx_in_tree": false})
	)
	assert_string_contains(diagnosis.to_lower(), "never reached the tree")


## Every clip in this game is load()ed at RUNTIME, never preloaded, so a
## resource missing from an exported build fails silently per stream rather
## than at startup -- the one failure mode that looks exactly like a mute.
func test_streams_that_failed_to_load_are_named_and_counted():
	var diagnosis := AudioDiagnostics.silence_diagnosis(
		_facts({"missing_streams": ["wind", "river", "forest_day"]})
	)
	assert_string_contains(diagnosis, "3")
	assert_string_contains(diagnosis, "wind")


## Neither audio node sets process_mode, so both stop dead while the tree
## is paused -- which it is on the main menu and the settings overlay.
func test_a_paused_tree_is_named():
	assert_string_contains(AudioDiagnostics.silence_diagnosis(_facts({"paused": true})).to_lower(), "paused")


## A bus index of -1 means get_bus_index("Master") found nothing, so the
## volume was written to a bus that does not exist.
func test_a_missing_master_bus_is_named():
	var diagnosis := AudioDiagnostics.silence_diagnosis(_facts({"master_bus_index": -1}))
	assert_string_contains(diagnosis.to_lower(), "master")


## Several things can be wrong at once; the report must not stop at the
## first one, or fixing it just reveals the next on the following launch.
func test_every_cause_present_is_reported_not_just_the_first():
	var diagnosis := AudioDiagnostics.silence_diagnosis(
		_facts({"master_muted": true, "paused": true, "missing_streams": ["wind"]})
	)
	assert_string_contains(diagnosis.to_lower(), "muted")
	assert_string_contains(diagnosis.to_lower(), "paused")
	assert_string_contains(diagnosis, "wind")


# -- the raw dump that goes in the log ------------------------------------

func test_the_report_carries_every_fact_it_was_given():
	var lines := AudioDiagnostics.report_lines(_facts({"master_db": -12.5}))
	var text := "\n".join(lines)
	assert_string_contains(text, "-12.5")
	assert_string_contains(text.to_lower(), "master")


## The report is what a player pastes back, so it must say plainly when it
## found nothing rather than looking like it failed to run.
func test_a_healthy_report_says_so_in_words():
	var text := "\n".join(AudioDiagnostics.report_lines(_facts()))
	assert_string_contains(text.to_lower(), "no cause found")


# -- walking a real node for dead streams ----------------------------------

## Every clip is load()ed at runtime, so a stream that failed to resolve is
## simply null on its player -- this is what finds them.
func test_missing_streams_finds_players_with_no_stream():
	var root := Node.new()
	var loaded := AudioStreamPlayer.new()
	loaded.name = "wind"
	loaded.stream = AudioStreamWAV.new()
	root.add_child(loaded)
	var dead := AudioStreamPlayer.new()
	dead.name = "river"
	root.add_child(dead)
	var found := AudioDiagnostics.missing_streams(root)
	assert_eq(found, ["river"], "only the player with no stream at all")
	root.free()


func test_missing_streams_on_a_null_root_is_empty_not_a_crash():
	assert_eq(AudioDiagnostics.missing_streams(null), [])


## The diagnosis tells a player which file to edit, so that path must be
## the one World really writes -- restated in AudioDiagnostics rather than
## preloaded (a RefCounted utility pulling in the whole world scene for one
## string would be absurd), and pinned equal here so the two cannot drift.
func test_the_settings_path_matches_the_one_world_actually_writes():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	assert_string_contains(
		source, 'KEYBINDINGS_PATH := "%s"' % AudioDiagnostics.SETTINGS_PATH,
		"AudioDiagnostics.SETTINGS_PATH must be the path World persists audio settings to"
	)
