extends RefCounted

## The village porter -- the worker a warehouse binds to walk its round and
## pull the Bollerwagen (see LogisticsMarker, CartMarker, docs/concept/
## village_warehouse.md's Mechanism 4 and 5).
##
## Reported live with the wagon in shot: *"The cart is not being pulled by a
## worker, but by a floor tile???"*. It was: LogisticsMarker drew itself with
## ProceduralStructureSprite's own `storage` TILE at half scale, left in as a
## placeholder when the worker was first written ("a hand-cart has no
## dedicated art yet") and never replaced -- so a shed appeared to be pulling
## the wagon across the village.
##
## Deliberately NOT CharacterView's full character-composite rig, for the
## same reason ProceduralLumberjackSprite is not: this is a small,
## purpose-built walker rather than a villager with a schedule and a face.
## Drawn in that sprite's own style and at its own SIZE, so the two people
## working one village read at the same scale -- a body, a head, and an arm
## out behind for the shaft they are pulling.

const ProceduralLumberjackSprite = preload("res://src/rendering/procedural_lumberjack_sprite.gd")

## The same tiny walker size the Sägewerk's own Lumberjack is drawn at, read
## off it rather than restated, so the two cannot drift apart.
const SIZE := ProceduralLumberjackSprite.SIZE

## A carter's smock -- a plainer, duller cloth than the Lumberjack's brown
## working tunic, so the two villagers are told apart at a glance.
const TUNIC_COLOR := Color(0.32, 0.34, 0.45)
const SKIN_COLOR := ProceduralLumberjackSprite.SKIN_COLOR
## The shaft of the cart, held out behind: a pale worn wood, the same hue
## family as the wagon's own timber.
const SHAFT_COLOR := Color(0.48, 0.36, 0.22)


func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())


func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)

	# Body: a squat smock, standing on the tile's lower half -- the same
	# silhouette the Lumberjack stands on, so they read as the same people.
	_draw_oval(image, center + Vector2(0.0, 1.5), 3.0, 4.0, TUNIC_COLOR)
	# Head: a small round patch of skin above it.
	_draw_circle(image, center + Vector2(0.0, -3.5), 2.0, SKIN_COLOR)
	# An arm out BEHIND, holding the shaft: what says "pulling something"
	# rather than "carrying something", which is the whole difference
	# between this worker and the one with an axe.
	_draw_line(image, center + Vector2(-2.5, 0.0), center + Vector2(-5.0, 2.0), SKIN_COLOR)
	_draw_line(image, center + Vector2(-4.5, 2.0), center + Vector2(-6.5, 3.5), SHAFT_COLOR)

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
