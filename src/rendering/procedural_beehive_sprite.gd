extends RefCounted

## Procedural fallback for a honeybee hive (see BeeHiveMarker,
## docs/concept/bees.md) -- mirrors ProceduralAntMoundSprite's own shape
## and reasoning: a colony was previously invisible, so this exists as a
## same-day safety net alongside the real illustrated art
## (IllustratedBeehiveSprite), the identical "offline hand-drawn
## procedural style, has_variants()-gated fallback" pattern every
## illustrated sprite in this codebase already has.
##
## Recoloured to a honeycomb wax palette and drawn as a hanging teardrop,
## narrower at the top where it meets its branch, rather than a squat
## ground dome -- a wild hive hangs in the open, it is not dug into the
## earth the way an ant mound is.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const CharacterView = preload("res://scenes/character_view.gd")

## Authoring canvas -- taller than ProceduralAntMoundSprite's own square
## SIZE (20), to fit a teardrop shape's own taller-than-wide proportions
## without clipping.
const SIZE := 24

## How wide a brand-new, just-founded exposed comb reads ON THE GROUND
## (well, in the air -- see the doc comment above), in world pixels -- a
## small, fragile early cluster, comparable in spirit to
## ProceduralAntMoundSprite.MOUND_WORLD_WIDTH_MIN's own "smallest a
## founding colony ever reads" reasoning.
const HIVE_WORLD_WIDTH_MIN := 3.0

const PLAYER_WORLD_HEIGHT_PX := -CharacterView.HEAD_TOP_Y * CharacterView.SCALE

## How wide a thriving, near-BeePopulationModel.MAX_REFERENCE_POPULATION
## hive reads. A real wild comb hanging from a branch is genuinely
## smaller than a whole ant colony's excavated earthworks spread across
## the ground -- deliberately well UNDER ProceduralAntMoundSprite.
## MOUND_WORLD_WIDTH_MAX's own 1.5x-player-height ceiling (itself a
## live-tuned correction across several reports this doc has no
## equivalent live signal for yet). A real, named first-pass estimate --
## comparable to a human torso's own width -- not claimed to be final;
## expect this to move the same way the ant mound's own ceiling did once
## a player has actually seen one in the world.
const HIVE_WORLD_WIDTH_MAX := PLAYER_WORLD_HEIGHT_PX * 0.4

## Identical technique and reasoning to ProceduralAntMoundSprite.
## GROWTH_EXAGGERATION: a young colony's own workforce builds out its
## comb quickly, a mature one's building capacity outstrips how fast its
## population can still be rising.
const GROWTH_EXAGGERATION := 0.5

## A teardrop is taller than it is wide -- how much taller, as a
## multiple of the width computed from world_width_for.
const HEIGHT_TO_WIDTH_RATIO := 1.3


static func world_width_for(growth_fraction: float) -> float:
	var eased := pow(clampf(growth_fraction, 0.0, 1.0), GROWTH_EXAGGERATION)
	return HIVE_WORLD_WIDTH_MIN + eased * (HIVE_WORLD_WIDTH_MAX - HIVE_WORLD_WIDTH_MIN)


## The scale factor BeeHiveMarker applies to a SIZE-authored hive sprite
## so it actually reads at world_width_for(growth_fraction) on screen.
static func world_scale_for(growth_fraction: float) -> float:
	return world_width_for(growth_fraction) / float(SIZE)


const HIVE_COLOR := Color(0.85, 0.65, 0.15)
## Distinctly darker than HIVE_COLOR's own shade band, but not
## PixelPalette.OUTLINE-dark -- mirrors ProceduralAntMoundSprite.
## ENTRANCE_COLOR's own reasoning exactly: a true near-black entrance
## would recreate the "fill colour lands on the outline ring" black-blob
## failure this project has already hit once.
const ENTRANCE_COLOR := Color(0.28, 0.17, 0.05)
## Near the bottom of the teardrop -- a real hive's entrance sits at its
## own lowest point, not dead centre.
const ENTRANCE_OFFSET := Vector2(0.0, 4.5)
const ENTRANCE_RADIUS := 2.4

var _palette := PixelPalette.new()


func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())


func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var half_width := SIZE / 2.0
	var half_height := half_width * HEIGHT_TO_WIDTH_RATIO
	var entrance_center := center + ENTRANCE_OFFSET

	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var to_point := point - center
			# Ellipse distance: scale the vertical axis down to a circle's
			# terms before measuring against half_width -- a teardrop's
			# rounder bottom half is approximated by one ellipse rather
			# than a genuinely pinched top, close enough for a fallback
			# nobody sees once real art loads.
			var normalized := Vector2(to_point.x / half_width, to_point.y / half_height)
			var d := normalized.length() * half_width
			if d > half_width:
				continue
			image.set_pixel(x, y, _color_at(point, center, half_width, d, entrance_center))
	return image


func _color_at(point: Vector2, center: Vector2, half_width: float, d: float, entrance_center: Vector2) -> Color:
	if d > half_width - 1.0:
		return _palette.outline_color()

	if point.distance_to(entrance_center) <= ENTRANCE_RADIUS:
		return ENTRANCE_COLOR

	# Posterized light/shadow banding from the upper-left, same
	# single-light-source convention every other generator here follows.
	var to_point := point - center
	var lit := to_point.x < 0 and to_point.y < 0
	return _palette.highlight(HIVE_COLOR) if lit else _palette.shade(HIVE_COLOR)
