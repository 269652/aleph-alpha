extends SceneTree

## Diffs two rendered sparkle frames, amplifies, and saves -- sparkle is
## deliberately subtle ("not too heavy"), so a raw side-by-side glance may
## not show it clearly; an amplified diff cancels out the static snow/canopy
## texture and leaves only what actually CHANGED between moments, which can
## only be the twinkle (nothing else in either scene moves). Run:
##   <godot> --headless --path . -s tools/probe_diff_sparkle.gd

const DIR := "res://tools/sparkle_renders"
const AMPLIFY := 6.0


func _init():
	_diff_pair("ground_snow_t0.png", "ground_snow_t2.png", "ground_diff_amplified.png")
	_diff_pair("cherry_blossom_snow_t0.png", "cherry_blossom_snow_t2.png", "cherry_diff_amplified.png")
	quit()


func _diff_pair(name_a: String, name_b: String, out_name: String) -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path("%s/%s" % [DIR, name_a]))
	var b := Image.load_from_file(ProjectSettings.globalize_path("%s/%s" % [DIR, name_b]))
	var w := a.get_width()
	var h := a.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	var max_diff := 0.0
	var changed := 0
	var brightest_at := Vector2i.ZERO
	for y in h:
		for x in w:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var dr := absf(ca.r - cb.r)
			var dg := absf(ca.g - cb.g)
			var db := absf(ca.b - cb.b)
			var mag := maxf(dr, maxf(dg, db))
			if mag > max_diff:
				max_diff = mag
				brightest_at = Vector2i(x, y)
			if mag > 0.02:
				changed += 1
			out.set_pixel(x, y, Color(dr * AMPLIFY, dg * AMPLIFY, db * AMPLIFY, 1.0))
	out.save_png("%s/%s" % [DIR, out_name])
	print(
		"%s vs %s -> %s : max_diff=%.4f changed_px(>0.02)=%d/%d (%.3f%%) brightest_at=%s"
		% [name_a, name_b, out_name, max_diff, changed, w * h, 100.0 * float(changed) / float(w * h), brightest_at]
	)
