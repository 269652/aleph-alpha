extends RefCounted

## Per-tile river DATA, not art -- mirrors procedural_hillshade_sprite.gd's
## "bake a data channel into a texture, sample it as data in the fragment
## shader" shape. See docs/concept/rivers.md's "Flow rendering" section.
##
## Channels:
##   R  unused                 -- the signed across-offset lived here for a
##                               while; it now travels as a bilinear float
##                               map (EarthChunkManager._flow_across_image)
##                               because an atlas dimension must be
##                               quantized, and every quantisation of
##                               across drew visible tile seams
##   G  flow direction x       -- as a VECTOR COMPONENT, not a bearing
##   B  flow direction y       -- ditto
##   A  fast flag
##
## Direction is a vector rather than the compass angle it once was because
## it saves the shader a `radians`/`sin`/`cos` per fragment and removes the
## 0/360 wrap hazard entirely.
##
## The three coarse style values (depth band, fast flag, bank flag) are
## packed into the alpha channel AND into the atlas index together.
##
## Both, necessarily: a TileMapLayer cell can only select an atlas tile, so
## anything that varies per cell has to be an atlas dimension -- there is no
## per-cell uniform. Packing them into one STYLE index keeps that a single
## dimension of 12 rather than three separate ones, and baking the same
## packed value into alpha is what lets the shader read it back out.

const SIZE := 32

## Quantisation of each baked dimension. Total atlas tiles is the product,
## so these are a real budget -- and a dimension the shader does not read is
## paid for in full and returns nothing.
##
## There used to be a third dimension here: a 12-bin scrolling PHASE, baked
## per tile so the old streak pattern would not break at tile edges. The
## switch to two-phase flow-map advection removed the need for it entirely,
## because the shader now advects continuously over TIME on the GPU and
## needs no baked phase at all.
##
## Keeping it would have been actively harmful, not merely wasteful: a
## per-tile offset applied to a NOISE field makes the noise jump at every
## tile boundary -- a grid of seams straight across the river. World
## position already decorrelates every reach continuously and for free.
##
## Dropping it took the atlas from 1920 tiles to 160. The across dimension
## added later brought it to 1536 -- but that one the shader READS every
## fragment, so it pays rent.
const DIRECTION_BINS := 96


## 96 direction * 2 speed = 192 tiles -- the across dimension left for
## the bilinear map, taking 48x of the atlas with it. At 96 columns the
## atlas is a slim 3072x64.
const ATLAS_COLUMNS := 96

## Speed reads as a higher-contrast surface rather than as a continuum.
const SPEED_LEVELS := 2


static func direction_bin_for(angle_deg: float) -> int:
	var wrapped := fposmod(angle_deg, 360.0)
	return int(clampf(wrapped / 360.0, 0.0, 0.999999) * DIRECTION_BINS)


static func angle_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(DIRECTION_BINS) * 360.0


static func unpack_is_fast(packed: float) -> bool:
	return packed > 0.5




## Flat index of a (direction, across, speed) combination, and its position
## in the 2D atlas grid. One function owns the packing so the tile-set
## builder and the per-cell lookup can never disagree about it.
static func atlas_index_for(direction_bin: int, speed_index: int) -> int:
	return (speed_index * DIRECTION_BINS) + direction_bin


## The alpha value the fast flag bakes to -- slot centres, so 8-bit
## quantisation cannot round one flag into the other.
static func alpha_for_fast(is_fast: bool) -> float:
	return 0.75 if is_fast else 0.25


static func atlas_cell_for_index(index: int) -> Vector2i:
	return Vector2i(index % ATLAS_COLUMNS, index / ATLAS_COLUMNS)


static func total_tiles() -> int:
	return DIRECTION_BINS * SPEED_LEVELS


func generate_texture(angle_deg: float, packed_alpha: float) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(angle_deg, packed_alpha))


## One data tile, uniform across its whole area like
## ProceduralHillshadeSprite's own tiles.
func generate_image(angle_deg: float, packed_alpha: float) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var radians := deg_to_rad(fposmod(angle_deg, 360.0))
	# Godot 2D: +X east, +Y DOWN (screen space), so "north" is -Y.
	var direction := Vector2(sin(radians), -cos(radians))
	image.fill(Color(
		0.0,
		direction.x * 0.5 + 0.5,
		direction.y * 0.5 + 0.5,
		clampf(packed_alpha, 0.0, 1.0)
	))
	return image
