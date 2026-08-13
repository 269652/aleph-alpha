extends RefCounted

## Small bird pixel art, shared by ambient songbirds (sparrow/robin) and the
## fish-eating kingfisher -- see docs/concept/ecosystem_dynamics.md's Species
## roster. Same "one shared shape, per-species color variants" approach as
## ProceduralFishSprite. Pure logic, no RandomNumberGenerator -- same
## (species, seed) always yields the same image.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## NOT yet on the resolution pass: this generator stamps hand-authored
## ASCII bitmaps (see the SPECIES/SHAPE tables below), which are
## written for exactly this canvas. Doubling the canvas would need the
## bitmaps redrawn -- upscaling them adds pixels but no information,
## the trap docs/concept/art_resolution.md warns about. Converting
## these to anatomy-built sprites (as ProceduralAnimalSprite now is)
## is the real fix and is deferred.
const SIZE := Vector2i(16, 10)

const EYE_COLOR := Color(0.05, 0.05, 0.05)
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
const BIRD_BITMAP := [
	"................",
	"................",
	".....oooo.......",
	"....ohhhboo.....",
	"..toobbbbboo....",
	".tt.obbbbbbenoo.",
	"..oobbbbbbboo...",
	"...oossssssoo...",
	"....oo....oo....",
	"................",
]

var _palette := PixelPalette.new()


func generate_texture(species: String, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species, seed_value))


## Renders `species` in its own color (falling back to "sparrow" for an
## unrecognized name) with a small seeded brightness jitter so individuals of
## the same species still vary slightly -- same technique as
## ProceduralFishSprite.generate_image.
func generate_image(species: String, seed_value: int) -> Image:
	var key: String = species if SPECIES_BASE_COLORS.has(species) else "sparrow"
	var base_color: Color = SPECIES_BASE_COLORS[key]

	var jitter := _seeded_unit_float(seed_value, key + "_shade") - 0.5
	var body := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)
	var palette := {
		"o": _palette.outline_color(),
		"b": body,
		"h": _palette.highlight(body),
		"s": _palette.shade(body),
		"e": EYE_COLOR,
		"n": body.darkened(0.5),
		"t": body.darkened(0.35),
	}

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	for y in SIZE.y:
		var row: String = BIRD_BITMAP[y]
		for x in mini(row.length(), SIZE.x):
			var glyph := row[x]
			if palette.has(glyph):
				image.set_pixel(x, y, palette[glyph])

	return image


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
