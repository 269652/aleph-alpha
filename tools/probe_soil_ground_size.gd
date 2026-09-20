extends SceneTree

## How much of its own tile does a farm bed's soil ground really COVER?
##
## Reported live with three beds in shot: *"weird sil tiles"* -- the beds read
## as separate brown squares with grass between them rather than one worked
## field. Measured off that screenshot: each bed's dirt reads 64 screen px
## while the beds sit 80 screen px apart, so a fifth of every tile shows grass.
##
## A frame being 32x32 and nominally "opaque" is not the same as covering the
## tile: a card with a soft alpha falloff at its rim is opaque by any
## threshold test and still lets the ground through. This reports the real
## alpha profile across a frame's edge.

const IllustratedTerrainSprite = preload("res://src/rendering/illustrated_terrain_sprite.gd")


func _initialize() -> void:
	var terrain := IllustratedTerrainSprite.new()
	var count := terrain.frame_count_for("soil")
	for variant in range(count):
		var image: Image = terrain.frame_for("soil", variant)
		if image == null:
			continue
		var w := image.get_width()
		var h := image.get_height()
		var mid := h / 2
		# alpha across the left edge, and the first column that is fully solid
		var row: Array[String] = []
		for x in range(min(8, w)):
			row.append("%.2f" % image.get_pixel(x, mid).a)
		var first_solid := -1
		for x in range(w):
			if image.get_pixel(x, mid).a >= 0.99:
				first_solid = x
				break
		var last_solid := -1
		for x in range(w - 1, -1, -1):
			if image.get_pixel(x, mid).a >= 0.99:
				last_solid = x
				break
		# how much of the whole frame is fully solid
		var solid := 0
		for y in range(h):
			for x in range(w):
				if image.get_pixel(x, y).a >= 0.99:
					solid += 1
		print(
			"RESULT variant=%d frame=%dx%d left_alpha=[%s] solid_cols=%d..%d solid_fraction=%.3f covered=%.3f"
			% [
				variant, w, h, ", ".join(row), first_solid, last_solid,
				float(solid) / float(w * h),
				float(last_solid - first_solid + 1) / float(w),
			]
		)
	quit()
