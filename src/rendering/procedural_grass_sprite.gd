extends RefCounted

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Deterministic offline pixel-art for a tuft of tall grass -- a few green
## blades on a transparent background, using the same shaded technique as
## ProceduralTreeSprite (trees) and the other procedural sprite generators.
## `seed_value` (typically hashed from the patch's cell) varies blade count,
## lean, and height so neighbouring tufts aren't pixel-identical clones.

## DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- drawn at ArtResolution.SPRITE_SCALE
## so it gains pixel detail without growing in the world.
const SIZE := Vector2i(32, 32)
## A blade is this wide at its root, tapering to a single pixel at the
## tip. A uniform 1px stroke reads as a scratch, not a blade.
const BLADE_ROOT_WIDTH := 2

const BLADE_COUNT_MIN := 11
const BLADE_COUNT_MAX := 16
const BASE_COLOR := Color(0.3, 0.55, 0.18)
const SHADE_DARKEN := 0.25
const HIGHLIGHT_LIGHTEN := 0.25


func generate_texture(seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(seed_value))


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var blade_count := BLADE_COUNT_MIN + PixelNoise.range_index(
		seed_value, 0, 0, BLADE_COUNT_MAX - BLADE_COUNT_MIN + 1
	)
	for i in blade_count:
		_paint_blade(image, seed_value, i)
	return image


## One blade: a 1px-wide column rising from the bottom edge, leaning left or
## right as it climbs. Blades near the tuft's center get the highlight tint,
## outer blades the shade tint, so the tuft reads as lit from above.
func _paint_blade(image: Image, seed_value: int, index: int) -> void:
	# Placement comes from PixelNoise, not Godot's string hash: hashing
	# "..._0", "..._1", "..._2" correlates, so consecutive blades landed
	# beside each other at the same height and merged into solid slabs
	# instead of reading as separate blades. Same clustering this project
	# hit with village house sizes and tree leaves.
	var h := PixelNoise.value(seed_value, index, 0)
	var base_x := 2 + h % (SIZE.x - 4)
	var height := 13 + (h / 31) % 14  # 13..26 px: tall enough to read as blades
	var lean: int = [-2, -1, 0, 1, 2][(h / 977) % 5]

	# Five tones so overlapping blades read as a clump with depth rather
	# than one flat green mass.
	var tones := [
		BASE_COLOR.darkened(SHADE_DARKEN),
		BASE_COLOR,
		BASE_COLOR.lightened(HIGHLIGHT_LIGHTEN),
		BASE_COLOR.darkened(SHADE_DARKEN * 0.5),
		Color(BASE_COLOR.r * 1.05, BASE_COLOR.g * 0.9, BASE_COLOR.b * 0.55),  # dry
	]
	var color: Color = tones[(h / 613) % tones.size()]

	for step in height:
		var y := SIZE.y - 1 - step
		if y < 0:
			break
		var t := float(step) / maxf(float(height - 1), 1.0)
		# Blades CURVE: the root stays planted and the lean accelerates
		# toward the tip, so a tuft bends instead of leaning like a stick.
		var x: int = base_x + int(round(float(lean) * pow(t, 2.0)))
		# ...and TAPER: wide at the root, a single pixel at the tip.
		var width := BLADE_ROOT_WIDTH if t < 0.15 else 1
		var stroke: Color = color.lightened(0.2) if step >= height - 2 else color
		for w in width:
			var px := x + w
			if px >= 0 and px < SIZE.x:
				image.set_pixel(px, y, stroke)
