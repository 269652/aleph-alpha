extends RefCounted

## Per-pixel flow-DIRECTION data, not art -- mirrors
## procedural_hillshade_sprite.gd's exact "bake a data channel into a
## texture, sample it as data in the fragment shader" shape, just one
## dimension (direction only, not magnitude -- see river_flow_shader.gd's
## own doc comment on why speed is uniform) instead of hillshade's two
## (slope + aspect).
##
## Real flow direction is continuous per tile (the same
## TerrainRelief.aspect_degrees_from_gradient every river tile already
## computes for hillshading -- "the direction water would actually flow",
## by that function's own doc comment), so this quantizes into a small,
## honestly-coarse set of compass bins -- the same kind of simplification
## procedural_hillshade_sprite.gd already accepts for aspect.

const SIZE := 32

## 16 compass sectors (22.5 deg each) -- finer than hillshade's 8 aspect
## bins, since a directional streak's exact angle is more visually
## noticeable than a shading band's.
const DIRECTION_BINS := 16


## Which compass sector a real bearing in degrees falls into.
static func direction_bin_for(angle_deg: float) -> int:
	var wrapped := fposmod(angle_deg, 360.0)
	return int(clampf(wrapped / 360.0, 0.0, 0.999999) * DIRECTION_BINS)


## The representative (bin-center) bearing this bin bakes.
static func angle_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(DIRECTION_BINS) * 360.0


func generate_texture(angle_deg: float) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(angle_deg))


## One data tile: red = normalized compass bearing [0,1], uniform across
## the whole tile, like ProceduralHillshadeSprite's own tiles.
func generate_image(angle_deg: float) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var red := clampf(fposmod(angle_deg, 360.0) / 360.0, 0.0, 1.0)
	image.fill(Color(red, 0.0, 0.0, 1.0))
	return image
