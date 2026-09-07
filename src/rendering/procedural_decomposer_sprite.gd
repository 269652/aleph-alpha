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

## The ant queen -- requested live, directly after the honeybee queen
## shipped: "give ants a real queen as well". No real queen art has been
## delivered (only ant.png/ant_mound.png exist -- see
## IllustratedDecomposerSprite.has_species, false for "queen" today), so
## this is the honest procedural fallback every other not-yet-illustrated
## species in this codebase already gets, gated behind the exact same
## has_species()/has_action() seam -- real queen art, if ever delivered,
## slots in for free the moment it exists, no changes needed here.
##
## A separate, larger canvas from the worker's own SIZE (below), not a
## bigger draw within the same 12x12 grid -- a queen's real anatomical
## difference from a worker is not just "bigger", it is disproportionately
## bigger at the gaster (abdomen), which a fixed 12px canvas has no room
## left to grow into once a recognizable head/thorax already sit there.
## 22, against the worker's 12 -- roughly 1.8x -- sits at the upper end of
## the commonly-cited real queen:worker body-length ratio for common
## temperate genera (Lasius/Formica/Camponotus: roughly 1.5-2x for most
## castes), picked generously (rather than the conservative low end)
## because the SAME multiplier also has to carry the head/thorax, which
## grow far LESS than the gaster does in real physogastric queens (see
## _generate_queen's own doc comment) -- a smaller overall canvas would
## force the gaster to be cropped or the head/thorax to be shrunk out of
## proportion to fit it.
const QUEEN_SIZE := 22

var _palette := PixelPalette.new()


func generate_texture(species: String) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species))


func generate_image(species: String) -> Image:
	if species == "bug":
		return _generate_bug()
	if species == "queen":
		return _generate_queen()
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


## Same three-segment head/thorax/gaster anatomy and 6-leg layout as
## _generate_ant() (unlike _generate_bug()'s different, legless-oval
## anatomy) -- she is unambiguously the same KIND of creature as a
## worker, just a queen of it, not a different insect. Real ant queens
## are anatomically the same three segments as a worker but substantially
## larger overall, and MUCH more dramatically so at the gaster: her
## abdomen swells to hold the ovaries that do essentially all of a real
## colony's egg-laying (physogastry), a genuine anatomical difference
## rather than a uniform scale-up of a worker's whole body. The gaster
## segment here grows to more than double a worker's own abdomen radius
## (2.2 -> 5.0, against QUEEN_SIZE/SIZE's own more modest ~1.8x for the
## canvas as a whole) so she reads as genuinely physogastric, not just
## "a bigger ant". Same ANT_COLOR as a worker -- she is the same
## species/chitin, not a different-colored creature.
func _generate_queen() -> Image:
	var image := Image.create(QUEEN_SIZE, QUEEN_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(QUEEN_SIZE / 2.0, QUEEN_SIZE / 2.0)
	var segments := [
		{"offset": Vector2(-5.5, 0.0), "radius": 2.4},  # head
		{"offset": Vector2(-0.8, 0.0), "radius": 2.6},  # thorax
		{"offset": Vector2(5.0, 0.0), "radius": 5.0},  # gaster -- the real physogastric tell
	]
	for segment in segments:
		_draw_circle(image, center + segment.offset, segment.radius, ANT_COLOR)
	for leg_x in [-2.5, 0.8, 4.0]:
		for leg_dir in [-1.0, 1.0]:
			_draw_line(
				image, center + Vector2(leg_x, 0.0),
				center + Vector2(leg_x + leg_dir * 0.8, leg_dir * 5.5), ANT_COLOR
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
##
## Reads its own canvas size from `image.get_width()` rather than the
## module-level SIZE constant (added for _generate_queen's own bigger
## QUEEN_SIZE canvas) -- a pure refactor, not a behaviour change: every
## existing caller (_generate_ant/_generate_bug) still creates an
## image.get_width() == SIZE canvas exactly as before.
func _outline_silhouette(image: Image) -> void:
	var canvas_size := image.get_width()
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	var offsets := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for y in canvas_size:
		for x in canvas_size:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for offset in offsets:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or nx >= canvas_size or ny < 0 or ny >= canvas_size:
					continue
				if image.get_pixel(nx, ny).a > 0.0:
					to_outline.append(Vector2i(x, y))
					break
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)


## Reads its own canvas size from `image` rather than SIZE -- see
## _outline_silhouette's own doc comment for why (identical reasoning,
## identical "no behaviour change for any existing SIZE-canvas caller").
func _draw_circle(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var canvas_size := image.get_width()
	var from_x := maxi(0, int(center.x - radius - 1))
	var to_x := mini(canvas_size, int(center.x + radius + 1))
	var from_y := maxi(0, int(center.y - radius - 1))
	var to_y := mini(canvas_size, int(center.y + radius + 1))
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


## Reads its own canvas size from `image` rather than SIZE -- see
## _outline_silhouette's own doc comment for why (identical reasoning,
## identical "no behaviour change for any existing SIZE-canvas caller").
func _draw_line(image: Image, from: Vector2, to: Vector2, color: Color) -> void:
	var canvas_size := image.get_width()
	var steps := int(from.distance_to(to) * 2.0) + 1
	for i in steps + 1:
		var point := from.lerp(to, float(i) / float(steps))
		var x := int(point.x)
		var y := int(point.y)
		if x >= 0 and x < canvas_size and y >= 0 and y < canvas_size:
			image.set_pixel(x, y, color)
