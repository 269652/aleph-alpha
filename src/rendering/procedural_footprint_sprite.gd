extends RefCounted

## Procedural footprint stamp art (see FootstepGait, FootprintField). No
## real hand-illustrated footprint/boot/track art exists anywhere in this
## project (confirmed by a dedicated search before writing this file) --
## generates a real, simple, recognizable sole shape directly, the same
## "procedural first, real art can replace it later" precedent
## ProceduralMushroomSprite/LeafLitterAtlas's own procedural fallback
## already establish throughout this codebase.
##
## Same house style as every other procedural generator here:
## deterministic, no RandomNumberGenerator, FORMAT_RGBA8, PixelForm's
## lit-ellipse shading through PixelRamp, PixelPalette's shared outline
## technique (see ProceduralMushroomSprite's own identical use of all
## three).
##
## Draws two overlapping ellipses along the LENGTH axis -- a wider "ball"
## toward the toe end, a narrower "heel" below it -- rather than one plain
## oval: a real sole reads as longer than wide and wider at the ball than
## the heel, and that silhouette has to read correctly even at tiny
## on-screen size. The ball is offset slightly to one side (a real
## big-toe bulge) so the shape is genuinely asymmetric -- "left" and
## "right" are the SAME generated image, mirrored horizontally at render
## time (see FootprintRenderer), not two separately-generated shapes;
## an asymmetric source shape is what makes that mirroring actually show
## as a different foot rather than an identical oval at a different spot.
##
## "Stamped ... with displacement" (reported live): a flat silhouette
## alone reads as a sticker lying ON the ground, not a mark pressed INTO
## it. Drawn with two real depth cues instead of one flat fill -- a
## slightly larger, lighter RIM shape underneath (surface material pushed
## up and catching the light) and a smaller, darker CORE shape on top
## (the actual depression) -- so a visible ring of the rim tone survives
## around the core's own edge.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelForm = preload("res://src/rendering/pixel_form.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

## Authored longer than wide (12x20 world-scale pixels before
## DETAIL_MULTIPLIER oversampling) -- a real sole's own proportions, not a
## round blob that would read as a paw print or a puddle.
const SIZE := Vector2i(12 * ArtResolution.DETAIL_MULTIPLIER, 20 * ArtResolution.DETAIL_MULTIPLIER)

## Real average adult shoe length (heel to toe) -- converted via
## GroundSlide.PX_PER_METER, the same real-human-scale idiom
## FootstepGait's own STRIDE_LENGTH_METERS/STANCE_WIDTH_METERS already
## use, not an eyeballed pixel count.
const PRINT_LENGTH_METERS := 0.27
## The scale factor a renderer applies to a SIZE-authored print so it
## actually reads at a real shoe's length on screen -- never left
## unscaled, the same "gigantic blobs" failure this codebase has hit
## more than once elsewhere (see ProceduralMushroomSprite.
## MUSHROOM_WORLD_SCALE's own doc comment).
const PRINT_WORLD_SCALE := (PRINT_LENGTH_METERS * GroundSlide.PX_PER_METER) / float(SIZE.y)

## Ball (toe) and heel geometry, as fractions of SIZE -- a wider ball
## offset toward +x (a real big-toe-side bulge) near the top, a narrower
## heel centred near the bottom.
const _BALL_CENTER_FRACTION := Vector2(0.58, 0.3)
const _BALL_HALF_FRACTION := Vector2(0.42, 0.28)
const _HEEL_CENTER_FRACTION := Vector2(0.5, 0.76)
const _HEEL_HALF_FRACTION := Vector2(0.3, 0.2)

## How much larger the RIM ellipses are than the CORE ones, as an extra
## fraction of SIZE added to each half-extent -- the width of the visible
## "pushed up" ring left showing around the core's own edge.
const _RIM_MARGIN_FRACTION := 0.12

## Per-surface (core, rim) tone pairs -- a real design choice grounded in
## how each real ground actually looks disturbed, the same category of
## judgement call MushroomSpecies.cap_color_for's own entries already are
## (real reference, not a physically-measurable constant): snow's core is
## a cool shadow-blue (the real look of compacted snow in its own
## shadow) with a near-white rim (fresh snow pushed up catching the
## light); grass/forest cores are the pressed earth/leaf-litter showing
## through flattened cover, with a slightly lighter rim of the
## still-standing cover right at the edge -- forest reads a little
## darker throughout than open grassland, real forest floor being
## shadier and litter-covered rather than bare soil.
const _TONES_BY_SURFACE := {
	"snow": {"core": Color(0.58, 0.65, 0.75), "rim": Color(0.95, 0.97, 1.0)},
	"grass": {"core": Color(0.26, 0.22, 0.13), "rim": Color(0.42, 0.5, 0.22)},
	"forest": {"core": Color(0.22, 0.17, 0.11), "rim": Color(0.34, 0.28, 0.15)},
}
## A plain, nondescript fallback for any surface this generator doesn't
## specifically know -- same "never crash on an unlisted id" fallback
## convention as MushroomSpecies.profile_for's own _FALLBACK.
const _FALLBACK_TONES := {"core": Color(0.3, 0.26, 0.2), "rim": Color(0.45, 0.4, 0.32)}

var _palette := PixelPalette.new()
var _ramp := PixelRamp.new()
var _form := PixelForm.new()


func generate_texture(surface: String) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(surface))


func generate_image(surface: String) -> Image:
	var tones: Dictionary = _TONES_BY_SURFACE.get(surface, _FALLBACK_TONES)
	var core_color: Color = tones["core"]
	var rim_color: Color = tones["rim"]
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)

	var size := Vector2(SIZE)
	var ball_center := _BALL_CENTER_FRACTION * size
	var ball_half := _BALL_HALF_FRACTION * size
	var heel_center := _HEEL_CENTER_FRACTION * size
	var heel_half := _HEEL_HALF_FRACTION * size
	var rim_margin := _RIM_MARGIN_FRACTION * size

	for y in SIZE.y:
		for x in SIZE.x:
			var point := Vector2(x + 0.5, y + 0.5)
			# Rim drawn first (both lobes, at their larger radius), core
			# layered on top -- the surviving ring is exactly the rim
			# tone showing past the smaller core shape.
			if _form.ellipse_depth(ball_center, ball_half + rim_margin, point) > 0.0:
				image.set_pixel(x, y, _form.shade(_ramp, rim_color, ball_center, ball_half + rim_margin, point))
			if _form.ellipse_depth(heel_center, heel_half + rim_margin, point) > 0.0:
				image.set_pixel(x, y, _form.shade(_ramp, rim_color, heel_center, heel_half + rim_margin, point))
			if _form.ellipse_depth(ball_center, ball_half, point) > 0.0:
				image.set_pixel(x, y, _form.shade(_ramp, core_color, ball_center, ball_half, point))
			if _form.ellipse_depth(heel_center, heel_half, point) > 0.0:
				image.set_pixel(x, y, _form.shade(_ramp, core_color, heel_center, heel_half, point))

	_outline_silhouette(image)
	return image


## Same generic edge-detection outline technique as
## ProceduralMushroomSprite/ProceduralEggSprite/ProceduralBirdSprite --
## rings whatever silhouette was actually drawn.
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
