extends RefCounted

## The pre-hatch visual for a pollinator's offspring (see LifeCycle's
## COURTING/MATED/EGG stages, and docs/concept/ecosystem_dynamics.md's
## "Courtship, and where births come from").
##
## Before this, a just-conceived offspring was rendered from the moment it
## spawned as the ADULT insect's own procedural silhouette scaled down to
## LifeCycle.HATCHLING_SCALE -- a tiny adult, not anything egg-shaped, for the
## entire COURTING/MATED/EGG span (see AmbientFlyerMarker.begin_life/
## _step_growing, which is unchanged and still owns the JUVENILE-onward
## "growing tiny adult" look; this only fills the gap BEFORE it). A small,
## pale, unremarkable oval -- real insect eggs are exactly that, not
## miniature insects.
##
## ONE shared shape/color for every pollinator species, deliberately: a real
## butterfly/bee egg is not identifiable by species to the naked eye either,
## and the whole point of this sprite is legibility at a glance ("this is an
## egg, not a bug yet") rather than species identification -- that job is
## already done once the animal HATCHES into its recognizable tiny-adult
## juvenile. Documented as a known simplification in
## docs/concept/ecosystem_dynamics.md.
##
## Same house style as every other procedural generator here: deterministic
## per seed (no RandomNumberGenerator, same (seed) always yields the same
## image), FORMAT_RGBA8, PixelForm's lit-spheroid shading sampled through
## PixelRamp, PixelPalette's shared outline color and outlining technique.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelForm = preload("res://src/rendering/pixel_form.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Small enough to read as an egg rather than a landmark once the marker's
## own per-species world scale AND LifeCycle.HATCHLING_SCALE are applied on
## top (see AmbientFlyerMarker._step_growing) -- this canvas only ever has to
## hold a plain oval, not a jointed body plan, so it is far smaller than the
## butterfly/bird canvases.
const SIZE := Vector2i(10, 8)

## A real insect egg: pale, off-white/cream rather than vividly colored --
## unlike the vividly saturated adult butterflies this stage precedes (see
## ProceduralButterflySprite's SPECIES_BASE_COLORS doc comment). Not pure
## white: a hint of warmth reads as organic rather than as a plastic bead.
const BASE_COLOR := Color(0.93, 0.9, 0.78)

## How much individual eggs vary in tone, seeded per instance so a clutch
## doesn't read as identical stamps -- same small-jitter technique every
## other generator here uses (see ProceduralButterflySprite.JITTER_RANGE).
const JITTER_RANGE := 0.08

## Egg is longer than it is wide -- real insect eggs are prolate ovals, not
## circles -- but only slightly: an exaggerated egg shape reads as a
## cartoon, not as something small and unremarkable.
const HALF_SIZE := Vector2(0.34, 0.42)

var _palette := PixelPalette.new()
var _ramp := PixelRamp.new()
var _form := PixelForm.new()


func generate_texture(seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(seed_value))


## Renders a small lit oval, with a seeded brightness jitter so individual
## eggs still vary slightly -- same technique as every other generator's
## generate_image here. Species-agnostic on purpose (see the class doc
## comment): only `seed_value` is taken, never a species id.
func generate_image(seed_value: int) -> Image:
	var jitter := PixelNoise.unit(seed_value, 0, 0) - 0.5
	var shell := BASE_COLOR.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE.x * 0.5, SIZE.y * 0.5)
	var half := Vector2(HALF_SIZE.x * SIZE.x, HALF_SIZE.y * SIZE.y)
	for y in SIZE.y:
		for x in SIZE.x:
			var point := Vector2(x + 0.5, y + 0.5)
			if _form.ellipse_depth(center, half, point) <= 0.0:
				continue
			image.set_pixel(x, y, _form.shade(_ramp, shell, center, half, point))
	_outline_silhouette(image)
	return image


## Rings the assembled silhouette so the egg separates from whatever it sits
## on -- same technique as every other generator here.
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
