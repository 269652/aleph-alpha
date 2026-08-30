extends RefCounted

## Per-tile river DATA, not art -- mirrors procedural_hillshade_sprite.gd's
## "bake a data channel into a texture, sample it as data in the fragment
## shader" shape. See docs/concept/rivers.md's "Flow rendering" section.
##
## Four channels:
##   R  wrapped streak phase   -- the continuous phase potential along the
##                               river's own course (see RiverPhaseField).
##   G  flow direction x       -- as a VECTOR COMPONENT, not a bearing
##   B  flow direction y       -- ditto
##   A  packed (depth band, fast flag, bank proximity) -- see pack_edge()
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
## so these are a real budget.
##
## PHASE_BINS trades directly against quality: the phase is continuous in
## principle, and binning to 12 caps the worst seam between neighbouring
## tiles at 1/24 of a cycle.
const PHASE_BINS := 12
const DIRECTION_BINS := 16

## Flat colour bands ACROSS the channel, from its shallow edge to its deep
## centreline. Five rather than three because these draw the river's
## CROSS-SECTION -- the thing that makes it read as a channel rather than a
## flat slab -- and three steps across a four-tile river is too coarse to
## describe a shape.
##
## Banded by the cross-channel depth FRACTION, not by absolute metres: a
## small stream and a great river must both show structure, and an absolute
## scale would paint the whole Dreisam a single colour.
const DEPTH_BANDS := 5

## 12 phase * 16 direction * 10 style = 1920 tiles, laid out as a 2D grid.
## A single row would be 61,440 px wide, vastly past the 16,384
## GL_MAX_TEXTURE_SIZE common on the integrated GPUs this game targets.
## At 48 columns the atlas is 1536x1536 -- measured cheap to build.
const ATLAS_COLUMNS := 48

## Speed reads as "an extra wave mark or not" rather than as a continuum.
##
## The separate bank flag is GONE: it used to paint a whole tile near-black
## and, because bank-ness is decided per tile and a tile is tens of screen
## pixels, that read as a solid block eating half the channel rather than an
## outline. The outermost cross-section band now IS the channel's edge, which
## needs no extra dimension and cannot block up.
const SPEED_LEVELS := 2


static func phase_bin_for(wrapped_phase: float) -> int:
	return int(clampf(fposmod(wrapped_phase, 1.0), 0.0, 0.999999) * PHASE_BINS)


static func phase_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(PHASE_BINS)


static func direction_bin_for(angle_deg: float) -> int:
	var wrapped := fposmod(angle_deg, 360.0)
	return int(clampf(wrapped / 360.0, 0.0, 0.999999) * DIRECTION_BINS)


static func angle_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(DIRECTION_BINS) * 360.0


## Total distinct values the alpha channel carries.
const PACKED_LEVELS := DEPTH_BANDS * SPEED_LEVELS


static func unpack_combined(packed: float) -> int:
	return clampi(int(floor(packed * float(PACKED_LEVELS))), 0, PACKED_LEVELS - 1)


static func unpack_depth_band(packed: float) -> int:
	return unpack_combined(packed) / SPEED_LEVELS


static func unpack_is_fast(packed: float) -> bool:
	return unpack_combined(packed) % SPEED_LEVELS == 1


## Flat index of a (phase, direction) combination, and its position in the
## 2D atlas grid. One function owns the packing so the tile-set builder and
## the per-cell lookup can never disagree about it.
static func atlas_index_for(phase_bin: int, direction_bin: int, style_index: int) -> int:
	return (style_index * PHASE_BINS * DIRECTION_BINS) + (phase_bin * DIRECTION_BINS) + direction_bin


## The style index a (depth band, fast flag, bank flag) triple maps to --
## the single atlas dimension all three share.
static func style_index_for(depth_band: int, is_fast: bool) -> int:
	return clampi(depth_band, 0, DEPTH_BANDS - 1) * SPEED_LEVELS + (1 if is_fast else 0)


## The alpha value a style index bakes to -- the centre of its slot, so
## 8-bit quantisation cannot round it into a neighbouring style.
static func alpha_for_style(style_index: int) -> float:
	return (float(clampi(style_index, 0, PACKED_LEVELS - 1)) + 0.5) / float(PACKED_LEVELS)


static func atlas_cell_for_index(index: int) -> Vector2i:
	return Vector2i(index % ATLAS_COLUMNS, index / ATLAS_COLUMNS)


static func total_tiles() -> int:
	return PHASE_BINS * DIRECTION_BINS * PACKED_LEVELS


func generate_texture(angle_deg: float, wrapped_phase: float, packed_edge: float) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(angle_deg, wrapped_phase, packed_edge))


## One data tile, uniform across its whole area like
## ProceduralHillshadeSprite's own tiles.
func generate_image(angle_deg: float, wrapped_phase: float, packed_edge: float) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var radians := deg_to_rad(fposmod(angle_deg, 360.0))
	# Godot 2D: +X east, +Y DOWN (screen space), so "north" is -Y.
	var direction := Vector2(sin(radians), -cos(radians))
	image.fill(Color(
		clampf(fposmod(wrapped_phase, 1.0), 0.0, 1.0),
		direction.x * 0.5 + 0.5,
		direction.y * 0.5 + 0.5,
		clampf(packed_edge, 0.0, 1.0)
	))
	return image
