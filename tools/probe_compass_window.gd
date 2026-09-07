extends SceneTree

## Real-render verification for CompassWindow (docs/concept/wayfinding.md's
## "in-world UI" gap) -- per this codebase's own established discipline,
## code tracing/headless tests alone are not enough evidence for "what does
## this look like" (see [[canopy-snow-settles-top-down]] memory). Needs a
## REAL GPU window, not --headless. Run:
##   <godot> --path . --rendering-driver opengl3 -s tools/probe_compass_window.gd
##
## Renders the widget at four readings (0/90/180/270) to confirm the needle
## actually visibly rotates a full turn and the readout label updates and
## stays legible/unclipped at each.
##
## CONFIRMED A REAL BUG (2026-09-08), not just a headless-vs-real gap: the
## needle's `rotation` silently reverted to 0.0 one frame after being set,
## whenever the Label was CenterContainer's own direct child -- Godot's
## Container re-applies its own layout to a managed child on every sort
## pass, and that reset the child's rotation along with its position/size.
## Fixed by wrapping the needle in a plain (non-Container) Control that
## CenterContainer centers instead; the Label inside that wrapper is
## positioned manually and never touched by a container layout pass, so it
## rotates freely. Confirmed visually AND via an objective pixel-diff
## between captures (not just eyeballing a small glyph, which this
## investigation's own history shows is easy to misjudge): the needle now
## renders as a clean ▲/▶/▼/◀ at 0/90/180/270 degrees respectively, no
## clipping, readout label legible at each.

const CompassWindow = preload("res://scenes/compass_window.gd")

const OUT_DIR := "res://tools/compass_window_renders"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	var viewport := SubViewport.new()
	viewport.size = Vector2i(120, 130)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	# A plain opaque backdrop -- transparent_bg on a headless-adjacent probe
	# has bitten this codebase before (magenta/alpha confusion); an explicit
	# dark backdrop makes the widget's own light theme unambiguous in the
	# saved PNG.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.15, 0.18, 0.22, 1.0)
	backdrop.size = Vector2(120, 130)
	viewport.add_child(backdrop)

	var window := CompassWindow.new()
	window.position = Vector2(4, 4)
	viewport.add_child(window)
	window.visible = true

	var needle: Label = window.get("_needle")
	var captures := {}
	for reading in [0.0, 90.0, 180.0, 270.0]:
		window.update_reading(reading)
		print(
			"reading=", reading, " needle.rotation=", needle.rotation,
			" pivot_offset=", needle.pivot_offset, " size=", needle.size,
			" min_size=", needle.get_minimum_size()
		)
		var img: Image = await _capture(viewport)
		captures[reading] = img
		var path := "%s/compass_%d.png" % [OUT_DIR, int(reading)]
		img.save_png(path)
		print("saved ", path, " for reading=", reading)

	# Objective pixel diff -- a tiny rotated glyph is easy to misjudge by eye
	# at this size, so count actually-differing pixels rather than trusting
	# a glance.
	var img0: Image = captures[0.0]
	for other_reading in [90.0, 180.0, 270.0]:
		var other: Image = captures[other_reading]
		var diff_count := 0
		for y in img0.get_height():
			for x in img0.get_width():
				if img0.get_pixel(x, y) != other.get_pixel(x, y):
					diff_count += 1
		print("pixels differing between 0deg and ", other_reading, "deg: ", diff_count,
			" / ", img0.get_width() * img0.get_height())

	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


func _capture(viewport: SubViewport) -> Image:
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	return viewport.get_texture().get_image()
