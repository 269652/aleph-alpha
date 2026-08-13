extends RefCounted

## Small ambient-flyer pixel art (butterflies) -- see
## docs/concept/ecosystem_dynamics.md's Species roster. Same "one shared
## shape, colorful per-species variants" approach as ProceduralFishSprite.
## Pure logic, no RandomNumberGenerator -- same (species, seed) always
## yields the same image.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelForm = preload("res://src/rendering/pixel_form.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")




const JITTER_RANGE := 0.1

## Real butterflies genuinely are this vivid -- unlike songbirds (see
## procedural_bird_sprite.gd), vividness here is real-world-grounded.
const SPECIES_IDS: Array[String] = ["monarch", "swallowtail", "blue_morpho"]

const SPECIES_BASE_COLORS := {
	"monarch": Color(0.92, 0.45, 0.05),
	"swallowtail": Color(0.95, 0.85, 0.1),
	"blue_morpho": Color(0.15, 0.35, 0.95),
}

## Butterfly silhouette, facing up/forward: symmetric upper+lower wings
## around a thin body/antenna line down the middle. Legend: '.' transparent,
## 'o' outline, 'b' body (wing color), 'n' dark body/antenna accent.


var _palette := PixelPalette.new()
var _ramp := PixelRamp.new()
var _form := PixelForm.new()


func generate_texture(species: String, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species, seed_value))


## Renders `species` in its own color (falling back to "monarch" for an
## unrecognized name) with a small seeded brightness jitter so individuals of
## the same species still vary slightly -- same technique as
## ProceduralFishSprite.generate_image.
## The butterfly's WORLD footprint, unchanged by the art resolution pass.
const WORLD_SIZE := Vector2i(14, 10)
## The ART canvas: DETAIL_MULTIPLIER times that (see
## docs/concept/art_resolution.md), drawn at ArtResolution.SPRITE_SCALE.
const SIZE := Vector2i(28, 20)

## Per-species wing plan, as canvas fractions. Butterflies used to stamp ONE
## hand-authored bitmap, so every species was the same silhouette in a
## different colour. A butterfly IS its wings, so that is what varies: the
## monarch has broad rounded wings with a dark border, the swallowtail is
## the one with trailing hindwing tails, the blue morpho has the widest,
## most angular span.
##   forewing/hindwing        half-extents of each wing pair
##   tail_length              hindwing tail projection (swallowtail only)
##   border                   whether a dark wing border is drawn
const SPECIES_WINGS := {
	"monarch": {"forewing": Vector2(0.17, 0.20), "hindwing": Vector2(0.13, 0.14), "tail_length": 0.0, "border": true},
	"swallowtail": {"forewing": Vector2(0.16, 0.19), "hindwing": Vector2(0.12, 0.13), "tail_length": 0.22, "border": true},
	"blue_morpho": {"forewing": Vector2(0.20, 0.23), "hindwing": Vector2(0.15, 0.15), "tail_length": 0.0, "border": false},
}

## Ramp stops for the hindwing and the dark wing border.
const _HINDWING_STOP := 0.35
const _BORDER_STOP := 0.1


func generate_image(species: String, seed_value: int) -> Image:
	var key: String = species if SPECIES_BASE_COLORS.has(species) else "monarch"
	var base_color: Color = SPECIES_BASE_COLORS[key]

	var jitter := PixelNoise.unit(seed_value, key.length(), 0) - 0.5
	var wing := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_paint_butterfly(image, SPECIES_WINGS.get(key, SPECIES_WINGS["monarch"]), wing, 1.0)
	_outline_silhouette(image)
	return image


## Seen from above: a thin body down the middle with a mirrored pair of
## forewings and hindwings either side. Flat colours per the codebase's
## 16-bit convention (see docs/concept/pixel_art_engine.md).
## Frames in a wing-beat. A butterfly's beat is the most visible of any
## flyer: the wings swing from fully spread to nearly closed.
const FLAP_FRAME_COUNT := 4

## How far the wings close at the tightest point of the beat, as a fraction
## of their spread width. Butterflies nearly fold shut, which is what makes
## the flutter read at this size.
const _WING_CLOSE := 0.35


## One full wing-beat cycle, as images.
func generate_flap_images(species: String, seed_value: int) -> Array:
	var frames := []
	for i in FLAP_FRAME_COUNT:
		# Spread swings between fully open and nearly folded.
		var openness: float = lerp(_WING_CLOSE, 1.0, 0.5 + 0.5 * cos(TAU * float(i) / float(FLAP_FRAME_COUNT)))
		frames.append(_butterfly_image(species, seed_value, openness))
	return frames


func generate_flap_textures(species: String, seed_value: int) -> Array:
	var textures := []
	for frame in generate_flap_images(species, seed_value):
		textures.append(ImageTexture.create_from_image(frame))
	return textures


func _butterfly_image(species: String, seed_value: int, openness: float) -> Image:
	var key: String = species if SPECIES_BASE_COLORS.has(species) else "monarch"
	var base_color: Color = SPECIES_BASE_COLORS[key]
	var jitter := PixelNoise.unit(seed_value, key.length(), 0) - 0.5
	var wing := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_paint_butterfly(image, SPECIES_WINGS.get(key, SPECIES_WINGS["monarch"]), wing, openness)
	_outline_silhouette(image)
	return image


func _paint_butterfly(image: Image, plan: Dictionary, wing: Color, openness: float) -> void:
	var w := float(SIZE.x)
	var h := float(SIZE.y)
	var center := Vector2(w * 0.5, h * 0.5)
	var hind := _ramp.sample(wing, _HINDWING_STOP)
	var border := _ramp.sample(wing, _BORDER_STOP)

	var forewing: Vector2 = Vector2(plan.forewing.x * w * openness, plan.forewing.y * h)
	var hindwing: Vector2 = Vector2(plan.hindwing.x * w * openness, plan.hindwing.y * h)

	for side in [-1.0, 1.0]:
		# Forewings sit forward and above the body's midline.
		# Pushed up and well out from the body so the two wing pairs read as
		# separate wings rather than merging into one disc.
		var fore_center := center + Vector2(forewing.x * 0.82 * side, -h * 0.22)
		_fill_ellipse(image, fore_center, forewing, wing)
		# Hindwings behind and below.
		var hind_center := center + Vector2(hindwing.x * 0.78 * side, h * 0.30)
		_fill_ellipse(image, hind_center, hindwing, hind)

		# Swallowtail's trailing tails.
		var tail_length: float = plan.tail_length * h
		if tail_length >= 1.0:
			var tail_root := hind_center + Vector2(hindwing.x * 0.3 * side, hindwing.y * 0.7)
			for i in int(tail_length):
				var px := int(tail_root.x + float(i) * 0.35 * side)
				var py := int(tail_root.y + float(i))
				if px >= 0 and px < SIZE.x and py >= 0 and py < SIZE.y:
					image.set_pixel(px, py, hind)

		if plan.border:
			_outline_ellipse(image, fore_center, forewing, border)

	# Body: a narrow dark spindle down the middle, plus antennae.
	var body_color := _ramp.sample(wing, _BORDER_STOP)
	_fill_ellipse(image, center, Vector2(maxf(w * 0.045, 1.0), h * 0.42), body_color)
	for side in [-1.0, 1.0]:
		for i in int(h * 0.2):
			var px := int(center.x + side * (1.0 + float(i) * 0.5))
			var py := int(center.y - h * 0.42 - float(i) * 0.6)
			if px >= 0 and px < SIZE.x and py >= 0 and py < SIZE.y:
				image.set_pixel(px, py, body_color)


func _fill_ellipse(image: Image, center: Vector2, half: Vector2, color: Color) -> void:
	for y in SIZE.y:
		for x in SIZE.x:
			if _form.ellipse_depth(center, half, Vector2(x + 0.5, y + 0.5)) > 0.0:
				image.set_pixel(x, y, color)


## Draws just the rim of an ellipse -- the monarch/swallowtail wing border.
func _outline_ellipse(image: Image, center: Vector2, half: Vector2, color: Color) -> void:
	for y in SIZE.y:
		for x in SIZE.x:
			var depth := _form.ellipse_depth(center, half, Vector2(x + 0.5, y + 0.5))
			if depth > 0.0 and depth < _WING_BORDER_DEPTH:
				image.set_pixel(x, y, color)


## How far in from a wing's edge its dark border reaches.
const _WING_BORDER_DEPTH := 0.22


## Rings the assembled silhouette so the butterfly separates from whatever
## it flutters over.
func _outline_silhouette(image: Image) -> void:
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	var offsets := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for y in SIZE.y:
		for x in SIZE.x:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for offset in offsets:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or nx >= SIZE.x or ny < 0 or ny >= SIZE.y:
					continue
				if image.get_pixel(nx, ny).a > 0.0:
					to_outline.append(Vector2i(x, y))
					break
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)

func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
