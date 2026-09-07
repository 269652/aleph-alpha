extends SceneTree

## Throwaway diagnostic: exercises the EXACT production code path
## (IntroSplashSheet.generate_textures(), the same call intro_splash.gd's
## _ready() makes) instead of a hand-rolled reimplementation, to find out
## whether a stale/missing .godot/imported/intro.png-*.ctex cache (see
## sprite_sheet_loader.gd's load_image fallback) actually still produces a
## working frame set, and how long it takes -- a live user report says the
## intro doesn't show before the main menu on a checkout in exactly this
## state.

const IntroSplashSheet = preload("res://src/rendering/intro_splash_sheet.gd")
const IntroSplashSequencer = preload("res://src/rendering/intro_splash_sequencer.gd")


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var frames := IntroSplashSheet.new().generate_textures()
	var elapsed_ms := Time.get_ticks_msec() - t0

	print("generate_textures() took ", elapsed_ms, "ms")
	print("frame count: ", frames.size(), " (expected ", IntroSplashSequencer.FRAME_COUNT, ")")

	if frames.is_empty():
		print("EMPTY -- IntroSplash._ready() would call _finish() immediately, never showing anything")
		quit(1)
		return

	for i in frames.size():
		var tex: ImageTexture = frames[i]
		print("  frame ", i, ": ", tex.get_width(), "x", tex.get_height())

	# Save a few sample frames so they can actually be looked at.
	var out_dir := "res://../probe_intro_out"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for i in [0, 8, 16, 31]:
		if i < frames.size():
			var img := frames[i].get_image()
			var path := ProjectSettings.globalize_path(out_dir) + "/frame_%02d.png" % i
			img.save_png(path)
			print("saved ", path)

	quit(0)
