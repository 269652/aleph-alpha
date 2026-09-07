extends SceneTree

## One-off probe (see [[godot-s-script-cannot-resolve-autoloads]] -- this
## touches no autoload, only RefCounted art-loading classes, so a raw -s
## script is fine here): measures REAL pixel value/saturation for the tree
## canopy's snow frame vs. its blossom frame, and the ground snow atlas, so
## the sparkle colour gate's thresholds are picked from real numbers rather
## than eyeballed. Run:
##   <godot> --headless --path . -s tools/probe_snow_sparkle_colors.gd

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const SnowStampAtlas = preload("res://src/rendering/snow_stamp_atlas.gd")


func _init():
	var tree := IllustratedTree.new()
	for species in ["cherry", "apple", "walnut", "acorn", "hazelnut", "pine"]:
		_report("%s/snow" % species, tree.snow_canopy_for(species))
	_report("cherry/blossom", tree.canopy_for("cherry", "spring"))
	_report("cherry/leaf", tree.canopy_for("cherry", "summer"))
	_report("cherry/turning", tree.canopy_for("cherry", "autumn"))
	_report("cherry/bare", tree.canopy_for("cherry", "winter"))
	_report("apple/blossom", tree.canopy_for("apple", "spring"))

	var atlas := SnowStampAtlas.new()
	_report_image("ground_snow_atlas", atlas.build_atlas_image())

	quit()


func _report(label: String, texture: Texture2D) -> void:
	if texture == null:
		print("%s: null (no frame)" % label)
		return
	_report_image(label, texture.get_image())


func _report_image(label: String, img: Image) -> void:
	if img == null:
		print("%s: null image" % label)
		return
	img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var min_v := 1.0
	var max_v := 0.0
	var sum_v := 0.0
	var min_s := 1.0
	var max_s := 0.0
	var sum_s := 0.0
	var count := 0
	# Candidate gate thresholds -- how many opaque pixels would pass each.
	var candidates := [
		Vector2(0.85, 0.18), Vector2(0.88, 0.15), Vector2(0.90, 0.12), Vector2(0.92, 0.10)
	]
	var passes := []
	passes.resize(candidates.size())
	for i in passes.size():
		passes[i] = 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var mx: float = max(c.r, max(c.g, c.b))
			var mn: float = min(c.r, min(c.g, c.b))
			var v: float = mx
			var s: float = 0.0 if mx <= 0.0001 else (mx - mn) / mx
			min_v = minf(min_v, v)
			max_v = maxf(max_v, v)
			sum_v += v
			min_s = minf(min_s, s)
			max_s = maxf(max_s, s)
			sum_s += s
			count += 1
			for i in candidates.size():
				var cand: Vector2 = candidates[i]
				if v >= cand.x and s <= cand.y:
					passes[i] += 1
	if count == 0:
		print("%s: no opaque pixels" % label)
		return
	var pass_str := ""
	for i in candidates.size():
		var cand: Vector2 = candidates[i]
		pass_str += " gate(v>=%.2f,s<=%.2f)=%.4f" % [
			cand.x, cand.y, float(passes[i]) / float(count)
		]
	print(
		"%s: n=%d value[min=%.3f mean=%.3f max=%.3f] sat[min=%.3f mean=%.3f max=%.3f]%s"
		% [label, count, min_v, sum_v / count, max_v, min_s, sum_s / count, max_s, pass_str]
	)
