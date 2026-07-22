extends RefCounted

## Frame-set generator for animated creature pixel art. Builds short
## per-action animations by post-processing the single 24x16 base image
## produced by ProceduralAnimalSprite (shifting pixel regions rather than
## re-drawing). Deterministic per (species, action, seed): no
## RandomNumberGenerator. Unknown actions fall back to "walk".

const AnimalSpriteScript := preload("res://src/rendering/procedural_animal_sprite.gd")

const ACTIONS := ["walk", "attack", "eat", "swim", "drink"]

const FRAME_COUNTS := {
	"walk": 2,
	"attack": 2,
	"eat": 2,
	"swim": 2,
	"drink": 2,
}

const WATER_COLOR := Color(0.2, 0.4, 0.85)
const WATER_SURFACE_COLOR := Color(0.35, 0.55, 0.95)
const WATER_TOP_ROW := 10
const LEG_TOP_ROW := 13


func generate_frames(species: String, action: String, seed_value: int) -> Array[Image]:
	var key: String = action if FRAME_COUNTS.has(action) else "walk"
	var sprite := AnimalSpriteScript.new()
	var base: Image = sprite.generate_image(species, seed_value)
	var frames: Array[Image] = []
	for frame_index in int(FRAME_COUNTS[key]):
		frames.append(_build_frame(base, key, frame_index))
	return frames


func generate_textures(species: String, action: String, seed_value: int) -> Array[ImageTexture]:
	var textures: Array[ImageTexture] = []
	for frame in generate_frames(species, action, seed_value):
		textures.append(ImageTexture.create_from_image(frame))
	return textures


func _build_frame(base: Image, action: String, frame_index: int) -> Image:
	match action:
		"walk":
			return _walk_frame(base, frame_index)
		"attack":
			return _attack_frame(base, frame_index)
		"eat":
			return _eat_frame(base, frame_index)
		"swim":
			return _swim_frame(base, frame_index)
		"drink":
			return _drink_frame(base, frame_index)
	return _copy(base)


## Legs alternate: on the off frame the left-half leg pixels shift forward
## and the right-half leg pixels shift back by one column.
func _walk_frame(base: Image, frame_index: int) -> Image:
	if frame_index == 0:
		return _copy(base)
	var frame := _copy(base)
	var w := base.get_width()
	var h := base.get_height()
	_clear_rows(frame, LEG_TOP_ROW, h)
	for y in range(LEG_TOP_ROW, h):
		for x in w:
			var c := base.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var dx := 1 if x < w / 2 else -1
			var nx := x + dx
			if nx >= 0 and nx < w:
				frame.set_pixel(nx, y, c)
	return frame


## Body lunges forward (toward +x) a couple of pixels on the off frame.
func _attack_frame(base: Image, frame_index: int) -> Image:
	if frame_index == 0:
		return _copy(base)
	return _shifted(base, 2, 0)


## Head dips down: the top half of the sprite shifts down one row.
func _eat_frame(base: Image, frame_index: int) -> Image:
	if frame_index == 0:
		return _copy(base)
	var frame := _copy(base)
	var w := base.get_width()
	var half := base.get_height() / 2
	_clear_rows(frame, 0, half)
	for y in half:
		for x in w:
			var c := base.get_pixel(x, y)
			if c.a > 0.0:
				frame.set_pixel(x, y + 1, c)
	return frame


## Only the upper body shows over a water-blue band; the creature bobs
## down one pixel on the off frame.
func _swim_frame(base: Image, frame_index: int) -> Image:
	var frame := _shifted(base, 0, 1 if frame_index != 0 else 0)
	var w := base.get_width()
	var h := base.get_height()
	for y in range(WATER_TOP_ROW, h):
		for x in w:
			frame.set_pixel(x, y, WATER_SURFACE_COLOR if y == WATER_TOP_ROW else WATER_COLOR)
	return frame


## Head dips like eat, with a blue water accent at the ground line.
func _drink_frame(base: Image, frame_index: int) -> Image:
	var frame := _eat_frame(base, frame_index)
	var h := frame.get_height()
	for x in range(2, 6):
		frame.set_pixel(x, h - 1, WATER_COLOR)
	return frame


func _copy(base: Image) -> Image:
	var image := Image.create(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
	image.blit_rect(base, Rect2i(0, 0, base.get_width(), base.get_height()), Vector2i.ZERO)
	return image


func _shifted(base: Image, dx: int, dy: int) -> Image:
	var w := base.get_width()
	var h := base.get_height()
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := base.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and nx < w and ny >= 0 and ny < h:
				image.set_pixel(nx, ny, c)
	return image


func _clear_rows(image: Image, from_row: int, to_row: int) -> void:
	for y in range(from_row, to_row):
		for x in image.get_width():
			image.set_pixel(x, y, Color(0, 0, 0, 0))
