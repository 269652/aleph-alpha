extends RefCounted

## Procedural fallback mushroom sprite (see docs/concept/mushrooms.md's "No
## illustrated art this pass"). Same house style as every other procedural
## generator here: deterministic, no RandomNumberGenerator, FORMAT_RGBA8,
## PixelForm's lit-spheroid shading through PixelRamp, PixelPalette's shared
## outline technique.
##
## Draws two lit ellipses -- a cap and a narrower stem below it -- rather
## than one plain oval (ProceduralEggSprite's own shape): a mushroom's
## silhouette is genuinely cap-on-stem, and that silhouette has to read
## correctly even before any species colour is applied.
##
## `generate_image(species_id, identified)` draws the SPECIES' real cap
## colour only when `identified` is true (see MushroomSpecies.cap_color_for)
## -- when false it always draws ONE shared, plain, nondescript colour
## regardless of species, the exact "one shared look because a real
## observer can't tell species apart yet" idiom ProceduralEggSprite already
## established for pre-hatch pollinators (see that class's own doc comment),
## applied here to a learned skill instead of a life stage.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelForm = preload("res://src/rendering/pixel_form.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")

const SIZE := Vector2i(16, 16)

## How wide a mushroom should read ON THE GROUND, in world pixels -- a
## small forest-floor object, smaller than even the smallest excavated
## ant mound (ProceduralAntMoundSprite.MOUND_WORLD_WIDTH_MIN -- a mound
## now GROWS with its colony rather than sitting at one flat width, see
## that class's own "Mound size grows with the colony" doc reference, but
## even a founding colony's own smallest mound stays comfortably above
## this). Picked comfortably below the flat value this constant was
## originally set against (3.5, see docs/concept/mushrooms.md's merge
## note), not the very first 7.0 either.
const MUSHROOM_WORLD_WIDTH := 2.5
## The scale factor a marker applies to a SIZE-authored sprite to make it
## actually read at MUSHROOM_WORLD_WIDTH on screen -- never left unscaled,
## the exact "gigantic ant blobs" failure this project has already hit more
## than once (see ProceduralAntMoundSprite.world_scale_for).
const MUSHROOM_WORLD_SCALE := MUSHROOM_WORLD_WIDTH / float(SIZE.x)

## One shared, plain, nondescript colour for every species while
## unidentified -- see class doc comment. A dull brown-tan, deliberately
## unlike any single real roster species' own cap_color.
const UNIDENTIFIED_COLOR := Color(0.5, 0.42, 0.3)

## Cap and stem geometry, as fractions of SIZE -- a cap centered near the
## top, overhanging a narrower stem below it.
const _CAP_CENTER_FRACTION := Vector2(0.5, 0.36)
const _CAP_HALF_FRACTION := Vector2(0.4, 0.24)
const _STEM_CENTER_FRACTION := Vector2(0.5, 0.68)
const _STEM_HALF_FRACTION := Vector2(0.12, 0.26)

## Real mushroom stems are pale, not the cap's own colour -- true regardless
## of species or identification.
const _STEM_COLOR := Color(0.88, 0.85, 0.76)

var _palette := PixelPalette.new()
var _ramp := PixelRamp.new()
var _form := PixelForm.new()


func generate_texture(species_id: String, identified: bool) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species_id, identified))


func generate_image(species_id: String, identified: bool) -> Image:
	var cap_color := MushroomSpecies.cap_color_for(species_id) if identified else UNIDENTIFIED_COLOR
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)

	var size := Vector2(SIZE)
	var cap_center := _CAP_CENTER_FRACTION * size
	var cap_half := _CAP_HALF_FRACTION * size
	var stem_center := _STEM_CENTER_FRACTION * size
	var stem_half := _STEM_HALF_FRACTION * size

	for y in SIZE.y:
		for x in SIZE.x:
			var point := Vector2(x + 0.5, y + 0.5)
			# Stem drawn first, cap layered on top -- a real cap overhangs
			# and hides the top of its own stem.
			if _form.ellipse_depth(stem_center, stem_half, point) > 0.0:
				image.set_pixel(x, y, _form.shade(_ramp, _STEM_COLOR, stem_center, stem_half, point))
			if _form.ellipse_depth(cap_center, cap_half, point) > 0.0:
				image.set_pixel(x, y, _form.shade(_ramp, cap_color, cap_center, cap_half, point))

	_outline_silhouette(image)
	return image


## Same generic edge-detection outline technique as ProceduralEggSprite/
## ProceduralBirdSprite -- rings whatever silhouette was actually drawn,
## unchanged whether that silhouette is one ellipse or two.
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
