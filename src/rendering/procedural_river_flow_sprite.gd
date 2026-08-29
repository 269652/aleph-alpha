extends RefCounted

## Per-pixel (flow-DIRECTION, flow-SPEED) data, not art -- mirrors
## procedural_hillshade_sprite.gd's exact "bake a data channel into a
## texture, sample it as data in the fragment shader" shape: direction in
## red, speed fraction in green, the same two-channel layout hillshade
## uses for (slope, aspect).
##
## Real flow direction is continuous per tile (the same
## TerrainRelief.aspect_degrees_from_gradient every river tile already
## computes for hillshading -- "the direction water would actually flow",
## by that function's own doc comment), so this quantizes into a small,
## honestly-coarse set of compass bins -- the same kind of simplification
## procedural_hillshade_sprite.gd already accepts for aspect. Speed
## (added 2026-08-29, "more natural water flow") is likewise a continuous
## [0,1] fraction (see RiverFlowShader.speed_fraction_for_slope_deg),
## quantized the same way.

const SIZE := 32

## 16 compass sectors (22.5 deg each) -- finer than hillshade's 8 aspect
## bins, since a directional streak's exact angle is more visually
## noticeable than a shading band's.
const DIRECTION_BINS := 16

## 6 speed bands -- coarser than direction, since "how fast" reads as a
## gradient of pacing rather than a sharply distinguishable value the way
## direction is; plenty to tell a lazy lowland stretch from a rushing
## mountain one without needing hundreds of atlas tiles for a difference
## too subtle to see at this pixel scale anyway (the same reasoning
## ProceduralHillshadeSprite.SLOPE_BINS's own comment already gives).
const SPEED_BINS := 6


## Which compass sector a real bearing in degrees falls into.
static func direction_bin_for(angle_deg: float) -> int:
	var wrapped := fposmod(angle_deg, 360.0)
	return int(clampf(wrapped / 360.0, 0.0, 0.999999) * DIRECTION_BINS)


## The representative (bin-center) bearing this bin bakes.
static func angle_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(DIRECTION_BINS) * 360.0


## Which speed band a real [0,1] speed fraction falls into. Clamped at
## both ends, so a value outside [0,1] (shouldn't happen given
## RiverFlowShader.speed_fraction_for_slope_deg's own clamp, but cheap
## insurance) still lands in a real bin rather than going undrawable.
static func speed_bin_for(speed_fraction: float) -> int:
	var clamped := clampf(speed_fraction, 0.0, 0.999999)
	return int(clamped * SPEED_BINS)


## The representative (bin-center) speed fraction this bin bakes.
static func speed_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(SPEED_BINS)


func generate_texture(angle_deg: float, speed_fraction: float) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(angle_deg, speed_fraction))


## One data tile: red = normalized compass bearing [0,1], green = speed
## fraction [0,1], uniform across the whole tile, like
## ProceduralHillshadeSprite's own tiles.
func generate_image(angle_deg: float, speed_fraction: float) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var red := clampf(fposmod(angle_deg, 360.0) / 360.0, 0.0, 1.0)
	var green := clampf(speed_fraction, 0.0, 1.0)
	image.fill(Color(red, green, 0.0, 1.0))
	return image
