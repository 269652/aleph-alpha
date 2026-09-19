extends RefCounted

## Names the most likely cause of a silent game, from real audio facts.
##
## Reported live: *"The game has no sound anymore... completely mute
## everywhere, I checked windows settings, the process is not muted."* A
## mute has many possible causes and they all look identical from the
## player's chair, so this turns one launch into an answer instead of a
## round trip per hypothesis.
##
## Pure: every fact is passed in rather than read from a live AudioServer
## or scene tree, so every branch is reachable headlessly -- the same
## "pure model, thin Node" split `AudioSettings` and `NatureSoundscape`
## already use, with `World._log_audio_diagnostics` as the thin glue that
## gathers the facts.
##
## The causes below are not guesses: each is a path that really exists in
## this codebase and really produces total silence. See
## docs/concept/soundscape.md's "Diagnosing silence".

## Where the master volume is persisted, quoted in the diagnosis because
## it is the one cause a player can fix without a rebuild. Restated rather
## than preloaded from `World` (a RefCounted utility pulling in the whole
## world scene for one string would be absurd) and pinned equal to it by
## test_the_settings_path_matches_the_one_world_actually_writes.
const SETTINGS_PATH := "user://keybindings.cfg"


## Every cause present, newline-separated, or "" when nothing is wrong.
##
## Deliberately reports ALL of them rather than stopping at the first:
## these causes stack (a paused tree AND a zero volume is entirely
## possible), and a report that names one at a time costs a launch per
## cause.
static func silence_diagnosis(facts: Dictionary) -> String:
	var causes: Array[String] = []

	if int(facts.get("master_bus_index", 0)) < 0:
		causes.append(
			"There is no audio bus named \"Master\", so the volume was written to a bus that does not exist."
		)
	if bool(facts.get("master_muted", false)):
		causes.append("The Master bus is muted at the mixer.")
	# The single most likely cause, and the only thing in this codebase that
	# can silence everything at once: AudioSettings.volume_to_bus_db maps a
	# setting of 0 to SILENT_BUS_DB (-80), and it persists across restarts.
	var master_db := float(facts.get("master_db", 0.0))
	if master_db <= -60.0:
		causes.append(
			"The Master bus is at %.1f dB, i.e. silent. The in-game master volume is %.2f -- set it above zero in Settings, or delete the [audio] section of %s." % [
				master_db, float(facts.get("volume_setting", 0.0)), SETTINGS_PATH
			]
		)
	# World._ready() returns early at the license gate and at the GitHub
	# identity check, both BEFORE add_child(_nature_soundscape.build()).
	if not bool(facts.get("soundscape_in_tree", true)) or not bool(facts.get("sfx_in_tree", true)):
		causes.append(
			"The audio players never reached the tree, so boot returned before building them (the license gate and the identity check both do this)."
		)
	# Every clip in this game is load()ed at RUNTIME, never preloaded, so a
	# resource missing from an exported build fails per stream, silently,
	# rather than failing the build.
	var missing: Array = facts.get("missing_streams", [])
	if not missing.is_empty():
		causes.append(
			"%d audio stream(s) failed to load and are empty: %s. Every clip is load()ed at runtime, so these are missing from this build rather than merely quiet." % [
				missing.size(), ", ".join(missing)
			]
		)
	# Neither audio builder sets process_mode, so both stop dead while the
	# tree is paused -- which it is on the main menu and the settings overlay.
	if bool(facts.get("paused", false)):
		causes.append(
			"The scene tree is paused. Neither audio node sets process_mode, so all sound stops while it is (the main menu and the settings overlay both pause it)."
		)
	return "\n".join(causes)


## The raw facts, for pasting back. Always ends with the diagnosis, so the
## report is self-contained rather than needing this file to read it.
static func report_lines(facts: Dictionary) -> Array[String]:
	var lines: Array[String] = ["-- audio diagnostics --"]
	var keys := facts.keys()
	keys.sort()
	for key in keys:
		lines.append("  %s: %s" % [key, facts[key]])
	var diagnosis := silence_diagnosis(facts)
	lines.append("  diagnosis: no cause found" if diagnosis.is_empty() else "  diagnosis:")
	if not diagnosis.is_empty():
		for cause in diagnosis.split("\n"):
			lines.append("    - " + cause)
	return lines


## Names every AudioStreamPlayer under `root` whose stream failed to
## resolve. A runtime `load()` that cannot find its resource returns null
## and leaves the player silent with no error a player would ever see, so
## this is the only way that failure becomes visible.
static func missing_streams(root: Node) -> Array[String]:
	var names: Array[String] = []
	if root == null:
		return names
	# AudioStreamPlayer only, deliberately: InteractionSfxPlayer's own voice
	# pools are streamless by construction until something plays through
	# them (see its build()), so counting an empty voice as a failure would
	# report a healthy game as broken. The layers that are SUPPOSED to hold
	# a stream from the moment they are built are NatureSoundscapePlayer's,
	# and those are plain AudioStreamPlayers.
	for child in root.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream == null:
			names.append(String(child.name))
	return names
