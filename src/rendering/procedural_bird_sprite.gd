extends RefCounted

## Small bird pixel art, shared by ambient songbirds (sparrow/robin) and the
## fish-eating kingfisher -- see docs/concept/ecosystem_dynamics.md's Species
## roster. Same "one shared shape, per-species color variants" approach as
## ProceduralFishSprite. Pure logic, no RandomNumberGenerator -- same
## (species, seed) always yields the same image.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelForm = preload("res://src/rendering/pixel_form.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")




const EYE_COLOR := Color(0.05, 0.05, 0.05)
## Bill colour -- a warm horn tone, distinct from every species' plumage
## so the kingfisher's oversized dagger bill reads at a glance.
const BEAK_COLOR := Color(0.85, 0.68, 0.28)
const JITTER_RANGE := 0.1

## sparrow/robin deliberately stay muted (real songbirds mostly are, unlike
## butterflies) -- only kingfisher is required to be vivid, see
## test_kingfisher_is_vividly_saturated.
const SPECIES_IDS: Array[String] = ["sparrow", "robin", "kingfisher"]

const SPECIES_BASE_COLORS := {
	"sparrow": Color(0.45, 0.35, 0.25),
	"robin": Color(0.55, 0.28, 0.2),
	"kingfisher": Color(0.1, 0.55, 0.85),
}

## Bird silhouette, side profile facing right (perched/gliding): round
## head+body like ProceduralFishSprite's oval body, a swept wing on top, a
## small pointed beak, and a short tail at the back. Legend: '.' transparent,
## 'o' outline, 'h' highlight, 'b' body, 's' shade, 'e' eye, 'n' beak (dark
## accent), 't' tail (reuses the dark accent color, same technique as
## ProceduralAnimalSprite's mouse_shape reusing 'n' for its tail).


var _palette := PixelPalette.new()
var _ramp := PixelRamp.new()
var _form := PixelForm.new()


func generate_texture(species: String, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species, seed_value))


## Renders `species` in its own color (falling back to "sparrow" for an
## unrecognized name) with a small seeded brightness jitter so individuals of
## the same species still vary slightly -- same technique as
## ProceduralFishSprite.generate_image.
## The bird's WORLD footprint, unchanged by the art resolution pass.
const WORLD_SIZE := Vector2i(16, 10)
## The ART canvas: DETAIL_MULTIPLIER times that (see
## docs/concept/art_resolution.md), drawn at ArtResolution.SPRITE_SCALE.
const SIZE := Vector2i(32, 20)

## Per-species body plan, as canvas fractions. Birds used to stamp ONE
## hand-authored bitmap, so every species was the same silhouette in a
## different colour. These are the proportions that tell small birds apart:
## a sparrow is small-billed and round, a robin rounder still with a plump
## breast, a kingfisher is the one with the oversized dagger bill and a
## stubby tail.
##   body_length/body_depth  the torso
##   head_size               head radius, relative to body depth
##   beak_length/beak_depth  bill size -- the kingfisher's giveaway
##   tail_length             tail projection behind the body
const SPECIES_BODY := {
	"sparrow": {"body_length": 0.46, "body_depth": 0.52, "head_size": 0.62, "beak_length": 0.10, "beak_depth": 0.14, "tail_length": 0.30},
	"robin": {"body_length": 0.48, "body_depth": 0.62, "head_size": 0.60, "beak_length": 0.09, "beak_depth": 0.12, "tail_length": 0.26},
	"kingfisher": {"body_length": 0.50, "body_depth": 0.50, "head_size": 0.70, "beak_length": 0.30, "beak_depth": 0.12, "tail_length": 0.16},
}

## Which ramp stops the belly and the wing use.
const _BELLY_STOP := 0.3
const _WING_STOP := 0.2


func generate_image(species: String, seed_value: int) -> Image:
	var key: String = species if SPECIES_BASE_COLORS.has(species) else "sparrow"
	var base_color: Color = SPECIES_BASE_COLORS[key]

	var jitter := PixelNoise.unit(seed_value, key.length(), 0) - 0.5
	var body := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_paint_bird(image, SPECIES_BODY.get(key, SPECIES_BODY["sparrow"]), body)
	_outline_silhouette(image)
	return image


## The bird faces right: torso, round head, bill, a folded wing panel and a
## tail projecting back. Flat colours with one belly shadow, per the
## codebase's 16-bit convention (see docs/concept/pixel_art_engine.md).
func _paint_bird(image: Image, plan: Dictionary, body: Color) -> void:
	var w := float(SIZE.x)
	var h := float(SIZE.y)
	var half := Vector2(plan.body_length * w * 0.5, plan.body_depth * h * 0.5)
	var center := Vector2(w * 0.46, h * 0.56)
	var belly := _ramp.sample(body, _BELLY_STOP)
	var wing := _ramp.sample(body, _WING_STOP)

	# Tail, projecting back from the body.
	var tail_length: float = plan.tail_length * w
	var tail_root := center.x - half.x + 1.0
	for x in SIZE.x:
		var into_tail := tail_root - (float(x) + 0.5)
		if into_tail < 0.0 or into_tail > tail_length:
			continue
		for y in SIZE.y:
			if absf(float(y) + 0.5 - center.y) <= half.y * 0.34:
				image.set_pixel(x, y, wing)

	# Torso.
	for y in SIZE.y:
		for x in SIZE.x:
			var point := Vector2(x + 0.5, y + 0.5)
			if _form.ellipse_depth(center, half, point) <= 0.0:
				continue
			image.set_pixel(x, y, belly if point.y > center.y + half.y * 0.2 else body)

	# Folded wing: a darker panel across the flank.
	var wing_half := Vector2(half.x * 0.62, half.y * 0.42)
	var wing_center := center + Vector2(-half.x * 0.12, -half.y * 0.05)
	for y in SIZE.y:
		for x in SIZE.x:
			var point := Vector2(x + 0.5, y + 0.5)
			if _form.ellipse_depth(wing_center, wing_half, point) > 0.0:
				image.set_pixel(x, y, wing)

	# Head, sitting forward and above the torso.
	var head_radius: float = half.y * plan.head_size
	var head_center: Vector2 = center + Vector2(half.x * 0.78, -half.y * 0.72)
	for y in SIZE.y:
		for x in SIZE.x:
			var point := Vector2(x + 0.5, y + 0.5)
			if _form.ellipse_depth(head_center, Vector2(head_radius, head_radius), point) > 0.0:
				image.set_pixel(x, y, body)

	# Bill: a wedge off the head. Length is the strongest species cue here.
	var beak_length: float = plan.beak_length * w
	var beak_depth: float = maxf(plan.beak_depth * h, 1.0)
	for x in SIZE.x:
		var into_beak: float = (float(x) + 0.5) - (head_center.x + head_radius * 0.7)
		if into_beak < 0.0 or into_beak > beak_length:
			continue
		var t := into_beak / maxf(beak_length, 0.001)
		var spread: float = beak_depth * (1.0 - t) * 0.5
		for y in SIZE.y:
			if absf(float(y) + 0.5 - head_center.y) <= maxf(spread, 0.5):
				image.set_pixel(x, y, BEAK_COLOR)

	var eye := Vector2i(int(head_center.x + head_radius * 0.2), int(head_center.y - head_radius * 0.15))
	if eye.x >= 0 and eye.x < SIZE.x and eye.y >= 0 and eye.y < SIZE.y:
		image.set_pixel(eye.x, eye.y, EYE_COLOR)


## Rings the assembled silhouette so the bird separates from the sky.
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
