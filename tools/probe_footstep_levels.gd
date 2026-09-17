extends SceneTree

## How long is each footstep clip REALLY? Reported live: *"Can you find
## better sounds for the footsteps on every terrain? They sound weak and not
## natural"* -- a report about audio nobody in this environment can hear, so
## the part that is measurable got measured, and it turned out to be the
## whole explanation.
##
## A footstep one-shot is ~0.2-0.5s. Only grass.ogg is one. The rest are
## LONG recordings of somebody walking continuously, and every step played
## them from 0.0 -- so each step was the same fraction of the same run-in,
## identically, every time. See docs/concept/creature_and_footstep_audio.md,
## "A long recording is not a footstep".
##
## Godot cannot hand raw samples back from a compressed stream, so peak and
## RMS are deliberately NOT reported here rather than reported as zero: the
## length is what this can honestly measure, and it was enough.

func _initialize() -> void:
	var FootstepSound = load("res://src/audio/footstep_sound.gd")
	print("clip                      length   is a walking bed?")
	for name in ["default.ogg", "forest_twigs.ogg", "grass.ogg", "snow.mp3", "mushroom_crush.mp3"]:
		var path := "res://assets/audio/footsteps/%s" % name
		var stream = load(path)
		if stream == null:
			print("%-24s  could not load" % name)
			continue
		var length: float = stream.get_length()
		print("%-24s %6.2fs   %s" % [
			name, length,
			"yes -- one step is a window into it" if length > FootstepSound.STEP_WINDOW_SECONDS * 2.0 else "no -- a real one-shot"
		])
	print()
	print("step window: %.2fs   pitch variation: +/-%.0f%%" % [
		FootstepSound.STEP_WINDOW_SECONDS, FootstepSound.PITCH_VARIATION * 100.0
	])
	quit()
