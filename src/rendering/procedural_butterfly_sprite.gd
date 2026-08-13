extends RefCounted

## Small ambient-flyer pixel art (butterflies) -- see
## docs/concept/ecosystem_dynamics.md's Species roster. Same "one shared
## shape, colorful per-species variants" approach as ProceduralFishSprite.
## Pure logic, no RandomNumberGenerator -- same (species, seed) always
## yields the same image.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## NOT yet on the resolution pass: this generator stamps hand-authored
## ASCII bitmaps (see the SPECIES/SHAPE tables below), which are
## written for exactly this canvas. Doubling the canvas would need the
## bitmaps redrawn -- upscaling them adds pixels but no information,
## the trap docs/concept/art_resolution.md warns about. Converting
## these to anatomy-built sprites (as ProceduralAnimalSprite now is)
## is the real fix and is deferred.
const SIZE := Vector2i(14, 10)

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
const BUTTERFLY_BITMAP := [
	"..............",
	"..............",
	"..obb....bbo..",
	".obbbb..bbbbo.",
	".obbbb..bbbbo.",
	"..ob..nn..bo..",
	"..bb......bb..",
	"...o......o...",
	"..............",
	"..............",
]

var _palette := PixelPalette.new()


func generate_texture(species: String, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species, seed_value))


## Renders `species` in its own color (falling back to "monarch" for an
## unrecognized name) with a small seeded brightness jitter so individuals of
## the same species still vary slightly -- same technique as
## ProceduralFishSprite.generate_image.
func generate_image(species: String, seed_value: int) -> Image:
	var key: String = species if SPECIES_BASE_COLORS.has(species) else "monarch"
	var base_color: Color = SPECIES_BASE_COLORS[key]

	var jitter := _seeded_unit_float(seed_value, key + "_shade") - 0.5
	var wing := base_color.lightened(maxf(jitter * JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * JITTER_RANGE, 0.0)
	)
	var palette := {
		"o": _palette.outline_color(),
		"b": wing,
		"n": base_color.darkened(0.6),
	}

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	for y in SIZE.y:
		var row: String = BUTTERFLY_BITMAP[y]
		for x in mini(row.length(), SIZE.x):
			var glyph := row[x]
			if palette.has(glyph):
				image.set_pixel(x, y, palette[glyph])

	return image


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
