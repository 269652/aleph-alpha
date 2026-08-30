extends RefCounted

## Per-tile river DATA, not art -- mirrors procedural_hillshade_sprite.gd's
## "bake a data channel into a texture, sample it as data in the fragment
## shader" shape. See docs/concept/rivers.md's "Flow rendering" section.
##
## Channels:
##   R  signed across-offset   -- the tile CENTRE's cross-channel offset in
##                               half-widths, encoded over +/-ACROSS_RANGE.
##                               The shader adds each fragment's own
##                               within-tile delta to this, which is what
##                               makes the cross-section continuous and the
##                               shoreline the real bank curve.
##   G  flow direction x       -- as a VECTOR COMPONENT, not a bearing
##   B  flow direction y       -- ditto
##   A  fast flag              -- and nothing else; the depth band it used
##                               to pack is gone, replaced by the
##                               continuous reconstruction above
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
const DIRECTION_BINS := 24

## The signed across-offset dimension: the tile centre's cross-channel
## position in half-widths, negative on one bank, positive on the other,
## |1| exactly at the bank line. The range runs past 1 so the painter's
## apron cells (whose centres sit beyond the bank while their inner corners
## still hold water) encode honestly rather than clamping to the bank.
##
## 32 bins over +/-1.4 is a 0.0875 step -- the worst tile-to-tile seam the
## reconstruction can show, versus the FULL BAND a tile used to jump.
const ACROSS_BINS := 32
const ACROSS_RANGE := 1.4

## 24 direction * 32 across * 2 speed = 1536 tiles in a 2D grid. A single
## row would be 49,152 px wide, vastly past the 16,384 GL_MAX_TEXTURE_SIZE
## common on the integrated GPUs this game targets. At 48 columns the atlas
## is 1536x1024.
const ATLAS_COLUMNS := 48

## Speed reads as a higher-contrast surface rather than as a continuum.
const SPEED_LEVELS := 2


static func direction_bin_for(angle_deg: float) -> int:
	var wrapped := fposmod(angle_deg, 360.0)
	return int(clampf(wrapped / 360.0, 0.0, 0.999999) * DIRECTION_BINS)


static func angle_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(DIRECTION_BINS) * 360.0


static func unpack_is_fast(packed: float) -> bool:
	return packed > 0.5


## Which across bin a signed cross-channel fraction falls in -- clamped,
## never wrapped: past the encodable range is simply "at the range edge",
## and those cells are transparent in the shader anyway.
static func across_bin_for(signed_fraction: float) -> int:
	var normalized := (clampf(signed_fraction, -ACROSS_RANGE, ACROSS_RANGE) / ACROSS_RANGE + 1.0) / 2.0
	return clampi(int(normalized * float(ACROSS_BINS)), 0, ACROSS_BINS - 1)


## The signed fraction at a bin's centre -- what the baked tile actually
## says, and what the reconstruction tests quantize through.
static func fraction_for_bin(bin: int) -> float:
	return ((float(bin) + 0.5) / float(ACROSS_BINS) * 2.0 - 1.0) * ACROSS_RANGE


## The red-channel value a signed fraction encodes to.
static func red_for_fraction(signed_fraction: float) -> float:
	return (clampf(signed_fraction, -ACROSS_RANGE, ACROSS_RANGE) / ACROSS_RANGE + 1.0) / 2.0


## Flat index of a (direction, across, speed) combination, and its position
## in the 2D atlas grid. One function owns the packing so the tile-set
## builder and the per-cell lookup can never disagree about it.
static func atlas_index_for(direction_bin: int, across_bin: int, speed_index: int) -> int:
	return ((speed_index * ACROSS_BINS) + across_bin) * DIRECTION_BINS + direction_bin


## The alpha value the fast flag bakes to -- slot centres, so 8-bit
## quantisation cannot round one flag into the other.
static func alpha_for_fast(is_fast: bool) -> float:
	return 0.75 if is_fast else 0.25


static func atlas_cell_for_index(index: int) -> Vector2i:
	return Vector2i(index % ATLAS_COLUMNS, index / ATLAS_COLUMNS)


static func total_tiles() -> int:
	return DIRECTION_BINS * ACROSS_BINS * SPEED_LEVELS


func generate_texture(angle_deg: float, across_fraction: float, packed_alpha: float) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(angle_deg, across_fraction, packed_alpha))


## One data tile, uniform across its whole area like
## ProceduralHillshadeSprite's own tiles.
func generate_image(angle_deg: float, across_fraction: float, packed_alpha: float) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var radians := deg_to_rad(fposmod(angle_deg, 360.0))
	# Godot 2D: +X east, +Y DOWN (screen space), so "north" is -Y.
	var direction := Vector2(sin(radians), -cos(radians))
	image.fill(Color(
		red_for_fraction(across_fraction),
		direction.x * 0.5 + 0.5,
		direction.y * 0.5 + 0.5,
		clampf(packed_alpha, 0.0, 1.0)
	))
	return image
