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
##
## Two drawings, not one: the mallet up on the way OUT to the store and a
## load on the shoulder on the way BACK, because a builder now walks a real
## round for the material his project reserved (ConstructionWorkerMarker,
## building.md "And he carries the material") and which leg he is on has to
## read at village zoom.

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
## The load on his shoulder coming back from the store (see
## ConstructionWorkerMarker, docs/concept/building.md "And he carries the
## material"). Pale sawn timber, deliberately BRIGHTER than anything else
## on the figure rather than one more brown in a man already made of
## browns: it is carried over the apron and rests against the head, so it
## owes contrast to both, and both are measured -- test_the_load_reads_
## against_the_apron_it_is_carried_over and _against_the_head_it_rests_
## beside, against the same Lumberjack yardstick the head itself answers
## to.
##
## One colour for every material, on purpose. What he carries really
## varies (a cottage's timber, a hall's stone), but at seven world units a
## man is a silhouette with one readable thing in his arms -- painting the
## load per item would be a distinction nobody can see, and the thing that
## has to read is "loaded" against "empty-handed".
const LOAD_COLOR := Color(0.86, 0.76, 0.55)


func generate_texture(carrying: bool = false) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(carrying))


## `carrying` draws the leg of the round he is on: empty-handed with the
## mallet up on the way OUT to the store, a load on the shoulder on the way
## BACK to the site. One man, two readings, because at village zoom the
## only thing that can say which way he is walking is his silhouette.
func generate_image(carrying: bool = false) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)

	# Body: the same squat silhouette the other two stand on, so the three
	# read as the same people doing different work.
	_draw_oval(image, center + Vector2(0.0, 1.5), 3.0, 4.0, APRON_COLOR)
	# Head.
	_draw_circle(image, center + Vector2(0.0, -3.5), 2.0, SKIN_COLOR)
	if carrying:
		_draw_load(image, center)
	else:
		_draw_mallet(image, center)

	return image


## A mallet held UP, the way the Lumberjack's own axe is slung down: a
## short haft rising from the shoulder with a blunt head at its top. Kept
## inside the canvas and ATTACHED to the body on purpose -- drawn further
## out (measured on a real render at the game's own zoom, a builder is
## about seven world units tall) the head read as a grey slab floating
## beside a blob rather than as a man with a tool.
func _draw_mallet(image: Image, center: Vector2) -> void:
	_draw_line(image, center + Vector2(2.5, 0.5), center + Vector2(4.0, -3.5), HANDLE_COLOR)
	_draw_oval(image, center + Vector2(4.0, -4.0), 1.0, 0.7, HEAD_COLOR)


## A bundle of boards carried under the arm. Three planks rather than one
## bar: a single line reads as a stick, and what a builder walks back from
## the store with is an armful. Drawn from inside the body out past his
## side, so it is attached to the man by construction -- the same lesson
## the mallet above already had to learn once.
##
## At CHEST height, deliberately, and that is the second lesson. Drawn up
## on the shoulder (measured on a real render at the game's own zoom,
## tools/probe_construction_haul.gd) the bundle sat exactly where the head
## is, and sawn timber and skin are near enough in tone that the two
## merged into one pale mass over a brown body. Carried lower, the dark
## apron runs between the head and the load and both read.
func _draw_load(image: Image, center: Vector2) -> void:
	for plank in [0.0, 1.0, 2.0]:
		_draw_line(
			image, center + Vector2(1.0, plank), center + Vector2(5.5, plank - 1.0), LOAD_COLOR
		)


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
