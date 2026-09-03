extends RefCounted

## Ants and carrion bugs -- the decomposer tier that finishes what a
## player's own butchering doesn't (see DecomposerMarker,
## docs/concept/carrion.md). Tiny, deterministic, no per-instance variants
## needed -- same offline-art style as ProceduralBobberSprite and friends.
##
## Two silhouettes: "ant" (small, round-bodied, six thin legs -- reads as a
## swarm insect) and "bug" (a carrion-beetle stand-in: a broader oval body,
## a distinct head, no visible legs at this scale -- reads as a single
## bigger scavenger rather than a swarm).

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SIZE := 12

## Dark, warm chitin tones -- real ants and carrion beetles (Silphidae, see
## docs/concept/carrion.md) genuinely are near-black, so these stay dark
## rather than reaching for this game's usual "brighter, saturated Zelda/
## Pokemon" palette (PixelPalette's own doc comment) -- but they must stay
## CLEARLY apart from PixelPalette.OUTLINE (0.08, 0.06, 0.1), the shared
## near-black silhouette-ring color every creature generator draws around
## itself. These used to sit almost exactly on top of it (ANT_COLOR was
## (0.08, 0.06, 0.05) -- a hair from the outline itself), which is why an
## outline was never missed by eye: fill and ring were the same color, so
## the whole creature rendered as one undifferentiated black blob (reported
## live, from a real screenshot: "these black blobs"). Pinned apart by
## test_ant_color_is_distinguishable_from_the_shared_outline/test_bug_
## color_is_distinguishable_from_the_shared_outline rather than left an
## eyeballed pair of literals.
const ANT_COLOR := Color(0.22, 0.15, 0.09)
## A bug is the bigger single scavenger (see the class doc comment) --
## a shade warmer/richer than the ant so the two read as different insects
## even before their silhouettes are compared, not just a darker/lighter
## split of the same tone.
const BUG_COLOR := Color(0.28, 0.16, 0.1)

var _palette := PixelPalette.new()


func generate_texture(species: String) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species))


func generate_image(species: String) -> Image:
	if species == "bug":
		return _generate_bug()
	return _generate_ant()  # default/fallback -- always draws something valid


func _generate_ant() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	# Three small round segments (head/thorax/abdomen) strung front-to-back,
	# plus a few thin leg strokes -- reads as an ant at this tiny scale
	# without needing real limb articulation.
	var segments := [
		{"offset": Vector2(-3.0, 0.0), "radius": 1.6},
		{"offset": Vector2(0.0, 0.0), "radius": 1.8},
		{"offset": Vector2(3.2, 0.0), "radius": 2.2},
	]
	for segment in segments:
		_draw_circle(image, center + segment.offset, segment.radius, ANT_COLOR)
	for leg_x in [-1.5, 0.5, 2.5]:
		for leg_dir in [-1.0, 1.0]:
			_draw_line(
				image, center + Vector2(leg_x, 0.0),
				center + Vector2(leg_x + leg_dir * 0.5, leg_dir * 3.5), ANT_COLOR
			)
	_outline_silhouette(image)
	return image


func _generate_bug() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	# One broad oval body plus a small distinct head -- a single bigger
	# scavenger, not a swarm-reading silhouette like the ant.
	_draw_oval(image, center, 4.2, 3.0, BUG_COLOR)
	_draw_circle(image, center + Vector2(-3.8, 0.0), 1.3, BUG_COLOR)
	_outline_silhouette(image)
	return image


## Rings the assembled silhouette in the shared outline color, so it
## separates from the ground the same way every other creature generator's
## silhouette does (see ProceduralBirdSprite._outline_silhouette, the same
## technique reused here rather than reinvented). Without this, a fill
## color -- however different from OUTLINE in the abstract -- still has no
## drawn edge marking where the creature ends and the grass begins.
func _outline_silhouette(image: Image) -> void:
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	var offsets := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for y in SIZE:
		for x in SIZE:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for offset in offsets:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or nx >= SIZE or ny < 0 or ny >= SIZE:
					continue
				if image.get_pixel(nx, ny).a > 0.0:
					to_outline.append(Vector2i(x, y))
					break
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)


func _draw_circle(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var from_x := maxi(0, int(center.x - radius - 1))
	var to_x := mini(SIZE, int(center.x + radius + 1))
	var from_y := maxi(0, int(center.y - radius - 1))
	var to_y := mini(SIZE, int(center.y + radius + 1))
	for y in range(from_y, to_y):
		for x in range(from_x, to_x):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				image.set_pixel(x, y, color)


func _draw_oval(image: Image, center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var normalized := Vector2((point.x - center.x) / radius_x, (point.y - center.y) / radius_y)
			if normalized.length() <= 1.0:
				image.set_pixel(x, y, color)


func _draw_line(image: Image, from: Vector2, to: Vector2, color: Color) -> void:
	var steps := int(from.distance_to(to) * 2.0) + 1
	for i in steps + 1:
		var point := from.lerp(to, float(i) / float(steps))
		var x := int(point.x)
		var y := int(point.y)
		if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
			image.set_pixel(x, y, color)
