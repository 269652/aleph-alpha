extends RefCounted

## The visible mound over one AntColony entrance (see docs/concept/
## soil_fauna.md's "Ants: myrmecochory" and AntColony's own doc comment) --
## a colony was previously a pure background population effect with no
## rendered presence at all, so a player could never actually see where one
## was or that anything was happening there. Same offline hand-drawn
## procedural style as ProceduralSoilSprite/ProceduralDecomposerSprite: a
## small dirt dome, distinguished from a plain tilled-soil mound (which this
## deliberately resembles -- both are, after all, a small pile of disturbed
## earth) by a dark entrance hole, offset from centre the way a real
## anthill's entrance sits off the crown of its mound rather than dead
## centre, so it reads as "something lives here" rather than just a bare
## dirt pile.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const CharacterView = preload("res://scenes/character_view.gd")

## DETAIL_MULTIPLIER-scale canvas (see docs/concept/art_resolution.md) --
## drawn at world_scale_for()'s own scale below so it gains pixel detail
## without growing the mound's actual world footprint.
const SIZE := 20

## How wide a brand-new, one-ant founding colony's mound reads ON THE
## GROUND, in world pixels -- the smallest a mound is ever drawn. Smaller
## than ProceduralSoilSprite's own SOIL_WORLD_WIDTH (10.0): a wild-crop
## soil patch is worked, tilled ground; even a THRIVING ant mound is a
## modest excavated pile a colony pushes up, not a patch of prepared
## earth. Close to the previous (pre-growth) pass's own flat 5.25 (itself
## already corrected once from an oversized 7.0, then an overshot-tiny
## 3.5 -- see docs/concept/soil_fauna.md "Ants at half their old size")
## rather than a step backward at the weakest end -- only mounds that
## have actually grown now read any bigger than that.
const MOUND_WORLD_WIDTH_MIN := 4.0

## Real player height in world pixels, restated locally rather than
## importing StoneSize for one shared number -- same "read against the
## player" convention StoneSize/ProceduralFlowerSprite already establish,
## mirrored precisely (see PLAYER_WORLD_HEIGHT_PX's own cross-file
## precedent) so a future CharacterView proportion change can't silently
## desync three independent copies without a test somewhere catching it.
const PLAYER_WORLD_HEIGHT_PX := -CharacterView.HEAD_TOP_Y * CharacterView.SCALE

## How wide a thriving, near-AntPopulationModel.MAX_REFERENCE_POPULATION
## mound reads: half the player's own real-world height. Requested
## directly, right after relaunch: mounds read as barely visible at their
## previous flat size -- "it should be half a human high and grow with
## the colony" (see docs/concept/soil_fauna.md "Mound size grows with the
## colony").
const MOUND_WORLD_WIDTH_MAX := PLAYER_WORLD_HEIGHT_PX * 0.5

## Growth reads fastest early and flattens out approaching full size --
## the identical `pow`-exponent-below-1 technique and reasoning
## StoneSize.SIZE_EXAGGERATION already uses: a young colony's own
## workforce visibly swells its mound quickly, while a mature colony's
## digging capacity outstrips how fast its own population can still be
## rising. Tuned, not load-bearing -- test_growth_reads_faster_early_
## than_late pins the CURVE SHAPE this produces, not this literal number.
const GROWTH_EXAGGERATION := 0.5


## How wide a mound reads at `growth_fraction` ([0,1], see AntColony.
## growth_fraction_at) of its own way from a founding colony to a
## thriving, near-max-population one. Clamped rather than trusted, since
## growth_fraction should never exceed 1.0 but a caller's own math is
## never assumed infallible here.
static func world_width_for(growth_fraction: float) -> float:
	var eased := pow(clampf(growth_fraction, 0.0, 1.0), GROWTH_EXAGGERATION)
	return MOUND_WORLD_WIDTH_MIN + eased * (MOUND_WORLD_WIDTH_MAX - MOUND_WORLD_WIDTH_MIN)


## The scale factor AntMoundMarker applies to a SIZE-authored mound sprite
## to make it actually read at world_width_for(growth_fraction) on
## screen -- never left unscaled the way DecomposerMarker's own ant/bug
## sprite once was (reported live: "gigantic ant blobs"), the identical
## failure class this project has already hit more than once.
static func world_scale_for(growth_fraction: float) -> float:
	return world_width_for(growth_fraction) / float(SIZE)

const MOUND_COLOR := Color(0.34, 0.22, 0.12)
## Distinctly darker than MOUND_COLOR's own shade band, but not
## PixelPalette.OUTLINE-dark -- see test_entrance_color_is_distinguishable_
## from_the_outline. A true near-black entrance would recreate the exact
## "fill colour lands on the outline ring" black-blob failure
## ProceduralDecomposerSprite's ant/bug fill already hit once.
const ENTRANCE_COLOR := Color(0.14, 0.09, 0.05)
## Where the entrance sits, offset from the mound's own centre -- a real
## anthill's opening is off to one side of the crown, not dead centre.
const ENTRANCE_OFFSET := Vector2(2.0, 1.5)
const ENTRANCE_RADIUS := 2.6

var _palette := PixelPalette.new()


func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())


func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var radius := SIZE / 2.0
	var entrance_center := center + ENTRANCE_OFFSET

	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var d := point.distance_to(center)
			if d > radius:
				continue
			image.set_pixel(x, y, _color_at(point, center, radius, d, entrance_center))
	return image


func _color_at(point: Vector2, center: Vector2, radius: float, d: float, entrance_center: Vector2) -> Color:
	if d > radius - 1.0:
		return _palette.outline_color()

	if point.distance_to(entrance_center) <= ENTRANCE_RADIUS:
		return ENTRANCE_COLOR

	# The dome itself: posterized light/shadow banding from the upper-left,
	# same single-light-source convention every other generator here follows
	# (see ProceduralSoilSprite._color_at).
	var to_point := point - center
	var lit := to_point.x < 0 and to_point.y < 0
	return _palette.highlight(MOUND_COLOR) if lit else _palette.shade(MOUND_COLOR)
