extends RefCounted

## The builder working a construction site (see ConstructionWorkerMarker,
## docs/concept/building.md "Somebody is working on it"). Asked for
## directly, watching a village raise a cottage: *"the construction site
## should show a builder working on it"*.
##
## Deliberately NOT CharacterView's full character-composite rig, for the
## same reason ProceduralLumberjackSprite and ProceduralPorterSprite are
## not: this is a small, purpose-built walker rather than a villager with a
## schedule and a face. Drawn in that sprite's own style and at its own
## SIZE, so the three people a village has out at once -- the woodsman with
## his axe, the carter with his shaft, this one with a mallet up -- read at
## one scale and are told apart at a glance.

const ProceduralLumberjackSprite = preload("res://src/rendering/procedural_lumberjack_sprite.gd")

## The same tiny walker size the Sägewerk's own Lumberjack is drawn at,
## read off it rather than restated, so the two cannot drift apart.
const SIZE := ProceduralLumberjackSprite.SIZE

## A builder's leather apron. Darker than skin by about what the
## Lumberjack's own tunic is, because at the size this is really drawn
## (seven world units) a head the tone of the body under it simply
## disappears -- measured, and pinned by
## test_a_builders_head_reads_against_his_own_body. Redder and duller than
## the woodsman's working brown, and nothing like the carter's blue smock,
## so the three are still told apart.
const APRON_COLOR := Color(0.40, 0.22, 0.16)
const SKIN_COLOR := ProceduralLumberjackSprite.SKIN_COLOR
## The mallet: a pale hickory handle and a dark iron head, held UP rather
## than down at the side, which is the whole difference between a man about
## to strike and a man walking somewhere with a tool.
const HANDLE_COLOR := Color(0.62, 0.48, 0.28)
const HEAD_COLOR := Color(0.30, 0.31, 0.34)


func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())


func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)

	# Body: the same squat silhouette the other two stand on, so the three
	# read as the same people doing different work.
	_draw_oval(image, center + Vector2(0.0, 1.5), 3.0, 4.0, APRON_COLOR)
	# Head.
	_draw_circle(image, center + Vector2(0.0, -3.5), 2.0, SKIN_COLOR)
	# A mallet held UP, the way the Lumberjack's own axe is slung down: a
	# short haft rising from the shoulder with a blunt head at its top.
	# Kept inside the canvas and ATTACHED to the body on purpose -- drawn
	# further out (measured on a real render at the game's own zoom, a
	# builder is about seven world units tall) the head read as a grey slab
	# floating beside a blob rather than as a man with a tool.
	_draw_line(image, center + Vector2(2.5, 0.5), center + Vector2(4.0, -3.5), HANDLE_COLOR)
	_draw_oval(image, center + Vector2(4.0, -4.0), 1.0, 0.7, HEAD_COLOR)

	return image


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
		var point: Vector2 = from.lerp(to, float(i) / float(steps))
		var x := int(point.x)
		var y := int(point.y)
		if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
			image.set_pixel(x, y, color)
