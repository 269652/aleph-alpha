extends RefCounted

## The kerb laid round a building's own plot (docs/concept/building.md,
## "The ground a building stands on, and the kerb round its plot").
## Reported live with a screenshot: "there should be some kind of border so
## the hitbox is visible."
##
## It draws the footprint's outline and nothing else -- the same rect
## EarthChunkManager._spawn_building_node gives the StaticBody2D's
## RectangleShape2D, so what a player sees IS what they walk into rather
## than a picture of it that can drift. Deterministic (no seed, no noise:
## a kerb is laid, not scattered), drawn at TerrainRenderer.ART_TILE_SIZE
## like every other procedural generator here.
##
## Its middle is fully transparent on purpose. The ground inside a
## footprint is chosen by the kerb RULE (TerrainRenderer.building_ground_
## tile_for -- the square's own paving under a hall, a worn yard anywhere
## else), and a filled plate would hide the very thing that fix exists to
## show.

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const TILE := TerrainRenderer.ART_TILE_SIZE

## The stone itself, and the mortar joint between one stone and the next.
## Dark and desaturated rather than black: it has to read against both the
## cobbles of a village square and open grass, and pure black reads as a
## debug rectangle drawn over the world rather than something laid in it.
const _KERB_STONE := Color(0.29, 0.27, 0.24, 0.82)
const _KERB_JOINT := Color(0.13, 0.12, 0.11, 0.82)

## The lit top face, one pixel inside the stone -- what stops the edge
## reading as a flat line. Carried at lower alpha so it lightens whatever
## it lies on instead of painting a second hard line over it.
const _KERB_TOP := Color(0.66, 0.64, 0.58, 0.42)

## How thick each part of the edge is, in ART pixels: two of stone, one of
## lit top face. Three art pixels is 1.5 world units on TerrainRenderer's
## own 16-unit tile (ART_TILE_SIZE is DETAIL_MULTIPLIER pixels per unit),
## which is a visible line at the camera's real zoom without being a wall
## drawn round every house.
const EDGE_PIXELS := 2
const TOP_PIXELS := 1

## The full width of the drawn band -- what a caller (or a test) asks when
## it wants to know which pixels are kerb and which are the plot inside it.
const BAND_PIXELS := EDGE_PIXELS + TOP_PIXELS

## The least any ground may wash the kerb out, as a distance in the RGB
## unit cube once the kerb's own pixels are composited over it. "So the
## hitbox is visible" is the whole point of drawing it, and a kerb lies on
## three real grounds: the village's cobbles under a hall on its square,
## the worn earth yard of a plot on open ground, and the grass a yard
## dithers into. Measured, this drawing clears it on all three -- 0.44
## over cobbles, 0.28 over a worn yard, 0.31 over grass -- so this is a
## floor with real margin beneath every one of them rather than a number
## fitted to them (see
## test_the_kerb_stands_out_from_every_ground_it_can_lie_on).
const MIN_GROUND_CONTRAST := 0.12

## One joint every this many art pixels along the run -- 8 art pixels is a
## quarter of a tile, so a 2x2 plot shows eight stones a side rather than
## one long curb or a dotted line.
const STONE_PITCH := 8


## The outline at art resolution: `footprint.x * TILE` by `footprint.y *
## TILE`, the plot's own rect exactly, transparent everywhere but the band
## round its edge.
func generate_image(footprint: Vector2i) -> Image:
	var width := maxi(footprint.x, 1) * TILE
	var height := maxi(footprint.y, 1) * TILE
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in height:
		for x in width:
			var from_side := mini(mini(x, width - 1 - x), mini(y, height - 1 - y))
			if from_side >= BAND_PIXELS:
				continue
			# Which way this stretch of kerb runs: a top or bottom band is
			# laid along x, a left or right band along y. Read off whichever
			# edge the pixel is actually nearer, so the corners belong to
			# the side they turn into rather than to neither.
			var horizontal := mini(y, height - 1 - y) <= mini(x, width - 1 - x)
			var along := x if horizontal else y
			var joint := along % STONE_PITCH == 0
			if from_side < EDGE_PIXELS:
				image.set_pixel(x, y, _KERB_JOINT if joint else _KERB_STONE)
			elif not joint:
				# The joint cuts the lit face, which is what makes one stone
				# read as ending and the next as beginning. The stone band
				# above never breaks: a gap in the outline is a hitbox edge
				# you cannot see.
				image.set_pixel(x, y, _KERB_TOP)
	return image


## How far this kerb's own drawn pixels end up from `ground` once
## composited over it -- the RGB distance of whichever band stands out
## most, which is what decides whether the outline reads at all. Measured
## off a real generated image rather than off the palette constants, so a
## change to the drawing is a change to this answer.
func contrast_over(ground: Color) -> float:
	var image := generate_image(Vector2i(1, 1))
	var beneath := Vector3(ground.r, ground.g, ground.b)
	var strongest := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var drawn := image.get_pixel(x, y)
			if drawn.a <= 0.0:
				continue
			var over := Vector3(
				drawn.a * drawn.r + (1.0 - drawn.a) * ground.r,
				drawn.a * drawn.g + (1.0 - drawn.a) * ground.g,
				drawn.a * drawn.b + (1.0 - drawn.a) * ground.b
			)
			strongest = maxf(strongest, (over - beneath).length())
	return strongest


## That outline scaled for a Sprite2D lying on a footprint at `tile_size`
## world units per tile -- exactly the plot's own rect, unlike
## ProceduralBuildingPlaceholderSprite's own footprint_texture (which adds
## a tile of height for the roof rising above the ground it stands on).
func footprint_texture(footprint: Vector2i, tile_size: int) -> ImageTexture:
	var image := generate_image(footprint)
	var scaled := image.duplicate() as Image
	scaled.resize(maxi(footprint.x, 1) * tile_size, maxi(footprint.y, 1) * tile_size, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(scaled)
