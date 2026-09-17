extends SceneTree

## What does each surface actually have underfoot? Reported live: *"Can you
## find better sounds for the footsteps on every terrain? They sound weak
## and not natural"* -- a report about audio nobody in this environment can
## hear, so the part that is measurable got measured, and it turned out to
## be the whole explanation.
##
## A footstep one-shot is ~0.2-0.5s. Every clip the game played was a LONG
## recording of somebody walking (forest 41.67s, snow 13.72s, the generic
## 3.64s) except grass, and every step played its clip from 0.0 -- so each
## step was the same fraction of the same run-in, identically, forever. The
## levels were 35dB apart on top of that. Every surface has a pool of real,
## level-matched one-shots now; this reports what is in them, read back
## from the real imported streams and from the manifest the pipeline that
## built them left behind. See docs/concept/creature_and_footstep_audio.md,
## "A long recording is not a footstep".
##
## Godot cannot hand raw samples back from a compressed stream, so this
## reports no peak or RMS of its own rather than reporting zeros: the
## lengths are what it can honestly measure, and the levels come from
## tools/prepare_footstep_oneshots.py, which decodes the files for real.

const MANIFEST_PATH := "res://assets/audio/footsteps/steps/levels.json"


func _initialize() -> void:
	var FootstepSound = load("res://src/audio/footstep_sound.gd")
	var manifest: Dictionary = {}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file != null:
		manifest = JSON.parse_string(file.get_as_text())

	print("surface      steps   length range    gain     rms      one-shots?")
	for surface in ["grass", "forest", "sand", "rock", "wood", "snow", "underwater", "default"]:
		var pool: Array = FootstepSound.step_variants_for(surface)
		var shortest := 999.0
		var longest := 0.0
		var missing := 0
		var windowed := 0
		for path in pool:
			var stream = load(path)
			if stream == null:
				missing += 1
				continue
			var length: float = stream.get_length()
			shortest = minf(shortest, length)
			longest = maxf(longest, length)
			if FootstepSound.is_walking_bed(path):
				windowed += 1
		var levels: Dictionary = manifest.get("surfaces", {}).get(surface, {})
		print("%-12s %3d   %5.2f-%5.2fs   %+5.1fdB  %6.1f   %s" % [
			surface, pool.size(), shortest, longest,
			float(levels.get("gain_db", 0.0)), float(levels.get("achieved_rms_dbfs", 0.0)),
			"yes" if windowed == 0 and missing == 0 else
			("%d MISSING" % missing if missing > 0 else "%d still windowed" % windowed),
		])

	var fallback = load(FootstepSound.FALLBACK_CLIP_PATH)
	print()
	print("fallback (a surface with nothing sourced): %s" % FootstepSound.FALLBACK_CLIP_PATH)
	print("  %.2fs, windowed: %s" % [
		fallback.get_length() if fallback != null else -1.0,
		FootstepSound.is_walking_bed(FootstepSound.FALLBACK_CLIP_PATH),
	])
	print("step window: %.2fs   pitch variation: +/-%.0f%%   target %.2f dBFS rms" % [
		FootstepSound.STEP_WINDOW_SECONDS, FootstepSound.PITCH_VARIATION * 100.0,
		float(manifest.get("target_rms_dbfs", 0.0)),
	])
	quit()
